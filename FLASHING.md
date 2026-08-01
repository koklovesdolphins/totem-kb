# Flashing guide: TOTEM dongle-as-central

Quick reference for reflashing the two keyboard halves and the dongle from this repo's
`firmware/*.uf2` files. For the full story of how this setup was built and debugged, see
`NOTES.md`.

## Which board is which

| Board       | Hardware       | Bootloader drive name |
|-------------|----------------|------------------------|
| Left half   | Seeed XIAO BLE | `XIAO-SENSE`           |
| Right half  | Seeed XIAO BLE | `XIAO-SENSE`           |
| Dongle      | nice!nano      | `NICENANO`             |

## Entering the bootloader

Double-tap the reset button on the board. It reboots into UF2 bootloader mode and mounts as a USB
mass storage drive (see table above for the expected name). Copying a `.uf2` file onto it flashes
and reboots the board automatically (the drive disappears once the write completes).

## Flash order (per board)

Always flash `settings_reset` **first** to clear old BLE bonds, then the real firmware:

1. **Left half**: `settings_reset_xiao_ble.uf2` → double-tap reset again → `left.uf2`
2. **Right half**: `settings_reset_xiao_ble.uf2` → double-tap reset again → `right.uf2`
3. **Dongle**: `settings_reset_nice_nano.uf2` → double-tap reset again → `dongle.uf2`

Order across boards doesn't matter, but always do `settings_reset` immediately before the real
firmware on the *same* board (don't batch all the resets first).

## After flashing

- Only the **dongle** needs to stay plugged into the PC (it's the BLE central + USB HID device).
- Left and right just need power — battery or any USB charger/power bank. They don't act as USB
  keyboards themselves.
- Bonds are established automatically: once both halves are running fresh firmware, they scan for
  and connect to the dongle within a few seconds of power-up.

## If one half doesn't reconnect after flashing

This happened once with the right half after an otherwise-normal `settings_reset` + reflash — it
just didn't show any BLE activity while the left half worked immediately. What fixed it: **redoing
the settings_reset + reflash cycle a second time** on the affected half. Root cause wasn't fully
pinned down (likely a stale bond/NVS remnant from that board's history), but the fix was simple
and reliable. See the 2026-07-30 status update in `NOTES.md` for the full debugging trail.

## Reflashing after a display/Kconfig-only change (no settings_reset needed)

`settings_reset` is only needed when BLE bonds need clearing. For changes that are purely
devicetree/Kconfig (display tweaks, sleep settings, etc.), just flash the real firmware directly
— no need to touch bonds. All three current `firmware/*.uf2` files include the OLED display
(dongle) and deep-sleep battery saver (left/right); reflash them the same way as any other
firmware update, `settings_reset` not required.

## Reflashing after a pure keymap change (dongle only)

Peripherals (left/right) don't process the keymap at all — they only scan the matrix and forward
raw key-position events over BLE. All layer/behavior/combo logic runs on the **dongle** (the
central). Confirmed empirically: after a keymap-only change, `left.uf2`/`right.uf2` rebuilt
byte-identical to the previous build, while `dongle.uf2` differed.

So for a change to `totem.keymap` or `totem.conf` (new layers, behaviors, combos, timing
tweaks — anything that isn't matrix/physical-layout), you only need to rebuild and reflash the
**dongle**: `settings_reset_nice_nano.uf2` is not needed either, since bonds aren't affected —
just flash `dongle.uf2` directly. Left/right only need rebuilding if `totem.dtsi`, the
`totem_left.overlay`/`totem_right.overlay` files, or `totem-layouts.dtsi` change.

## OLED display (dongle)

Driver is `sinowealth,sh1106` (128x64, on `pro_micro_i2c`) — the module's stated default
(`solomon,ssd1306fb`) showed a garbled image on this hardware; sh1106 is the one that actually
works here. Shows battery, active layer (bigger font, right-aligned), and Mac-style modifier
icons. Screen blanks after 5 minutes idle.

**Important if rebuilding from source:** the `zmk-dongle-display` west module (pinned in
`config/west.yml`) needed two local bug fixes that aren't upstream — see
`zmk-dongle-display-local-fixes.patch` in this repo. After any fresh `west update` fetches that
module, apply the patch before building:
```bash
cd <wherever west put zmk-dongle-display>
git apply /path/to/zmk-dongle-display-local-fixes.patch
```
Without it, the layer-number widget renders nothing (a real bug in the module, not our config —
see `NOTES.md` for the full root-cause explanation).

## Battery saver (left/right deep sleep)

`CONFIG_ZMK_SLEEP=y` is enabled on both halves (15 min idle timeout, the default). **Waking up is
a full chip reset + BLE reconnect, roughly 1-3 seconds — not instant**, and the keypress that
wakes the board is typically dropped. This is a deliberate tradeoff for battery life, not a bug —
just press the key again if the first one after a long idle doesn't register. The dongle itself
does NOT sleep (it's USB-powered and needs to stay connected as central).

## ZMK Studio

The dongle firmware includes the `studio-rpc-usb-uart` snippet and `CONFIG_ZMK_STUDIO=y`, so ZMK
Studio (web at studio.zmk.dev, or the desktop app) can connect directly to the dongle's serial
port to live-edit the keymap. On Linux, the serial device is owned by `root:dialout` — if Studio
can't see/open the port, make sure your user is in the `dialout` group *and* you've done a full
logout/login (or reboot) since being added — just locking/unlocking the screen isn't enough, group
membership only refreshes on a real new login session.

## Rebuilding from source

If you need to change the config and rebuild, see `NOTES.md` for the Docker-based `west build`
commands used originally (image: `zmkfirmware/zmk-build-arm:stable`). The `config/` and
`build.yaml` in this repo are the exact sources these `firmware/*.uf2` files were built from.

The west workspace (`zephyr/`, `zmk/`, `zmk-dongle-display/`, `modules/`, `.west/`, `build/`)
lives inside this repo and is gitignored. If it's missing, recreate it from the repo root:
```bash
west init -l config
west update
```
then re-apply `zmk-dongle-display-local-fixes.patch` (see above) before building.

**Gotcha to watch for:** don't add a keymap/conf file directly at the `config/` root (e.g.
`config/totem.keymap`) unless you specifically intend it as an override — ZMK's build will
silently prefer it over `config/boards/shields/totem/totem.keymap` for *any* `totem_*` shield,
with no error or warning. This bit us once already (see the 2026-08-01 status update in
`NOTES.md`). If a rebuild ever behaves like it ignored your keymap edits, check which file was
actually used:
```bash
grep KEYMAP_FILE build/*/CMakeCache.txt
```
