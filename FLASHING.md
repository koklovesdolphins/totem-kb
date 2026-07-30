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
