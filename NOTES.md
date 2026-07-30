# TOTEM split keyboard: add dongle-as-central + build/flash locally

## Context

You have a Keycoon TOTEM split keyboard (2x nRF52840 "Seeed XIAO BLE" halves) plus a separate
nRF52840 dongle. Right now:

- Only the dongle shows up on USB (`lsusb`), enumerating as `ZMK Project / E_Solfe-Dongle`
  (VID:PID `1d50:615e`, at `/dev/ttyACM0`). That name/firmware is **not** the TOTEM config — it's
  leftover firmware from something else, so the dongle needs to be reflashed regardless.
- The vendor's config repo (https://github.com/Keycoon/zmk-config-totem) only defines
  `totem_left` and `totem_right` shields. Critically, its `Kconfig.defconfig` makes
  **`totem_left` the BLE central** by default (i.e. out of the box, the left half is meant to
  pair directly to a host, with no dongle involved at all).
- To get "dongle acts as master", the dongle needs its own `totem_dongle` shield, and the
  central role needs to move from the left half to the dongle. This exact pattern already
  exists as a working community fork: https://github.com/robertzd/zmk-config-totem-dongle
  — it will be used as the reference, not blindly copied, since some shared files (kscan
  overlays, `Kconfig.defconfig`) have since changed upstream in the vendor repo.
- You want to build/flash locally via Docker (no GitHub push needed), and configure the keymap
  later via ZMK Studio (already supported by the vendor repo's `totem_left` build target via
  the `studio-rpc-usb-uart` snippet — we'll carry that onto the dongle instead, since the
  dongle is the central/USB-connected piece now).
- Firmware state of the two halves is unknown, so a `settings_reset` flash is included for all
  three boards to clear any stale BLE bonds before pairing.

## Steps

1. **Clone the vendor repo locally, and work from there for the rest of this task**
   `git clone https://github.com/Keycoon/zmk-config-totem ~/totem`
   - `cd ~/totem` and do all subsequent steps (edits, Docker build, flashing notes) from this
     directory.
   - Copy this plan into `~/totem/NOTES.md` (or similar) once cloned, so the working notes live
     alongside the repo instead of only in `~/.claude/plans/`.

2. **Add dongle shield support** in `~/totem/config/boards/shields/totem/`:
   - `Kconfig.shield`: add
     ```
     config SHIELD_TOTEM_DONGLE
         def_bool $(shields_list_contains,totem_dongle)
     ```
   - `Kconfig.defconfig`: restructure so **central role moves to the dongle**, not the left half:
     ```
     if SHIELD_TOTEM_DONGLE
     config ZMK_KEYBOARD_NAME
         default "TOTEM"
     config ZMK_SPLIT_ROLE_CENTRAL
         default y
     config ZMK_USB
         default y
     endif

     if SHIELD_TOTEM_LEFT || SHIELD_TOTEM_RIGHT || SHIELD_TOTEM_DONGLE
     config ZMK_SPLIT
         default y
     config ZMK_BLE
         default y
     endif
     ```
     (drop the old `if SHIELD_TOTEM_LEFT ... ZMK_SPLIT_ROLE_CENTRAL default y` block entirely)
   - `totem.zmk.yml`: add `totem_dongle` to the `siblings:` list
   - New `totem_dongle.conf`:
     ```
     CONFIG_ZMK_SPLIT_BLE_CENTRAL_PERIPHERALS=2
     CONFIG_ZMK_SLEEP=n
     ```
   - New `totem_dongle.overlay`: mirror `totem_right.overlay`'s kscan block (dongle has no real
     switches, but the shared `totem.dtsi` requires `kscan0` fully defined) — same pattern as
     the reference fork's `totem_dongle.overlay`.

3. **Update `~/totem/build.yaml`** — keep the existing `xiao_ble//zmk` board id (matches this
   repo's current west manifest; do not use the reference fork's older `seeeduino_xiao_ble` id),
   add:
   ```yaml
   include:
     - board: xiao_ble//zmk
       shield: totem_left
     - board: xiao_ble//zmk
       shield: totem_right
     - board: xiao_ble//zmk
       shield: totem_dongle
       snippet: studio-rpc-usb-uart
       cmake-args: -DCONFIG_ZMK_STUDIO=y
     - board: xiao_ble//zmk
       shield: settings_reset
   ```

4. **Build all four firmware images locally with Docker** (official `zmkfirmware/zmk-build-arm`
   image), one `west build` invocation per `build.yaml` entry, output `.uf2` per target
   (e.g. `build/left/zephyr/zmk.uf2`, `build/right/...`, `build/dongle/...`,
   `build/reset/...`). Exact `west init/update/build` invocations to be finalized/verified when
   executing (first build will confirm command syntax against this ZMK version).

5. **Flash order**: `settings_reset` on all 3 boards first (clears any stale bonds — important
   since the dongle currently has unrelated foreign firmware/bonds), then `totem_left` →
   left half, `totem_right` → right half, `totem_dongle` → dongle. Flash via UF2 bootloader
   (double-tap reset button mounts board as USB mass storage; drag/copy the `.uf2` file).

6. **Verify pairing**: plug dongle into PC, confirm via `lsusb`/`dmesg` it now enumerates as
   `TOTEM` (composite USB HID + the studio CDC-ACM serial), power on left/right halves, confirm
   keypresses register on the PC as the dongle bonds to both peripherals
   (`CONFIG_ZMK_SPLIT_BLE_CENTRAL_PERIPHERALS=2`).

7. **ZMK Studio**: once the dongle is flashed with the `studio-rpc-usb-uart` snippet, connect
   ZMK Studio to its exposed serial port (likely `/dev/ttyACM0`) to configure the keymap live.

## Verification

- `west build` succeeds for all 4 targets (left, right, dongle, settings_reset) with no errors.
- After flashing settings_reset + real firmware and powering on all 3 boards: `lsusb`/`dmesg`
  show the dongle enumerating as a TOTEM composite device; typing on either half produces
  keystrokes on the PC.
- ZMK Studio successfully connects to the dongle's serial port and shows the live keymap.

---

## STATUS UPDATE (2026-07-29): reverted to wired mode, dongle work paused

**Currently flashed on the physical boards (working, in use right now):**
- **Left half**: `build/left-revert/zephyr/zmk.uf2` — vendor-original config, left = BLE
  central + USB. Plug left into the PC via USB-C; it acts as a normal USB HID keyboard.
- **Right half**: `build/right-revert/zephyr/zmk.uf2` — vendor-original config, right = BLE
  peripheral, pairs to left automatically (no PC connection needed, runs on battery/power).
- This is "wired mode" per the vendor manual: left plugs into the PC by wire, right connects
  to left over BLE (not a physical wire between halves). **Both boards confirmed working.**
- The dongle itself is currently NOT reflashed back to anything — it was last left running a
  debug build (`build/dongle-debug/zephyr/zmk.uf2`, mock-kscan version, `zmk-usb-logging`
  snippet, no ZMK Studio support). It just sits idle/unused right now; unplug it or leave it,
  doesn't matter for the wired-mode setup above.

**Repo state**: the dongle-central changes are still present as **uncommitted edits** in the
working tree (`git diff --stat` shows `Kconfig.defconfig`, `Kconfig.shield`, `totem.zmk.yml`,
`build.yaml`, plus new untracked `totem_dongle.conf` / `totem_dongle.overlay`). Nothing was
lost — to get back to the dongle setup, these files already have the right content; the
currently-flashed left/right boards just need `settings_reset` + `build/left/...` /
`build/right/...` (the **original dongle-mode** builds, not `*-revert`) reflashed again, and
Kconfig.defconfig back to the `SHIELD_TOTEM_DONGLE`-owns-central version (already the case in
the working tree right now — it was stashed then `git stash pop`'d back).

**Key bug found and fixed** (dongle firmware would hang on boot before this fix):
Giving the dongle shield a real `zmk,kscan-gpio-matrix` with dummy/unused pins (since the
dongle has no physical switches) caused a **hard hang during boot**, always after configuring
exactly 3 of 4 row-gpio pins, regardless of which physical pins were chosen and regardless of
interrupt vs. polling kscan mode (`CONFIG_ZMK_KSCAN_MATRIX_POLLING`) — pointing to a deeper
GPIO/GPIOTE resource issue with a fake matrix on this board, not a specific-pin fault.
**Fix**: replaced the real gpio-matrix kscan in `totem_dongle.overlay` with ZMK's built-in
`zmk,kscan-mock` driver (same pattern the built-in `settings_reset` shield uses) — zero real
GPIOs touched, `columns=<10> rows=<4> events=<>`, with `diode-direction`/`row-gpios`/
`col-gpios`/`wakeup-source` deleted from the inherited `totem.dtsi` kscan0 node since they
aren't valid properties for the mock binding. With this fix, the dongle now boots cleanly all
the way to `Welcome to ZMK!` (verified via `zmk-usb-logging` snippet + serial console capture).

**Still unresolved / next things to check when resuming dongle work:**
- After the kscan fix, the dongle boots fine, but **30s of steady-state operation with the left
  board powered nearby showed zero BLE split/central log activity** (no scan-start, no
  device-found messages) — i.e. the dongle doesn't appear to be discovering the left
  peripheral's advertisement. This was NOT yet root-caused before we paused to revert.
- Never got a debug log from the **left board itself** while it's running as a peripheral (only
  ever captured its console while it was flashed with the *central* revert build). Worth
  reflashing left with the dongle-mode peripheral build + `zmk-usb-logging` snippet added to
  confirm it actually starts BLE peripheral advertising at all.
- Debug console capture gotchas learned this session (for next time):
  - `/dev/ttyACM*` and `/dev/serial/by-id/*` need `sudo` (owned by `root:dialout`, user not in
    that group).
  - Use `sudo timeout N stdbuf -o0 cat <path> > ~/somefile.txt` — **must** use `stdbuf -o0`,
    plain buffered `cat > file` loses the tail when `timeout` kills it.
  - Resetting the SAME board you're `cat`-ing from kills the read (USB disconnect races the
    read) — capture only shows whatever streamed out before the disconnect. To see full fresh
    boot logs: start the capture, then reset — you'll reliably get everything up to
    `Welcome to ZMK!` and then it cuts off. To see *post-boot* steady-state activity, start
    capture fresh (device already running, don't touch reset) and trigger events on other
    boards only.
  - Adding `CONFIG_ZMK_USB_LOGGING` manually isn't enough — must also pass
    `-DSNIPPET=zmk-usb-logging` at build time (that snippet adds the actual devicetree
    `zephyr,cdc-acm-uart` console node; without it you get Kconfig dependency errors).
  - Docker containers are ephemeral (`--rm`): every fresh `docker run` needs `west zephyr-export`
    again before `west build`, and `rm -rf build/X` from the host often fails silently
    (permission denied, files are root-owned from the container) — clean stale build dirs
    *inside* the container, or use `west build -p always`.

---

## STATUS UPDATE (2026-07-30): dongle-as-central WORKING

**The dongle setup is done and confirmed working.** Left and right both connect to the dongle
over BLE, keystrokes from both halves register on the PC through the dongle's USB HID, and this
was verified with left/right running on independent power (unplugged from the PC, dongle is the
only thing plugged in) — bonds persist and both halves auto-reconnect on power-up.

**What was actually flashed (final, production, no debug logging):**
- **Left half**: `build/left/zephyr/zmk.uf2` — peripheral role.
- **Right half**: `build/right/zephyr/zmk.uf2` — peripheral role (mirrored kscan wiring +
  `col-offset = <5>` on `&default_transform`, same as before, unrelated to any of the bugs below).
- **Dongle**: `build/dongle/zephyr/zmk.uf2` — central + USB, `studio-rpc-usb-uart` snippet +
  `CONFIG_ZMK_STUDIO=y`, so ZMK Studio can connect to it directly for keymap editing.
- All three were flashed via `settings_reset` first (`build/reset` for the xiao_ble halves,
  `build/reset-nicenano` for the dongle), then the real firmware.
- `config/boards/shields/totem/totem_dongle.conf` final contents:
  ```
  CONFIG_ZMK_SPLIT_BLE_CENTRAL_PERIPHERALS=2
  CONFIG_ZMK_SLEEP=n

  # per ZMK dongle docs: BT_MAX_CONN/BT_MAX_PAIRED should cover the peripherals
  # plus the default 5 host bluetooth profiles
  CONFIG_BT_MAX_CONN=7
  CONFIG_BT_MAX_PAIRED=7
  ```
  (The BT_MAX_CONN/BT_MAX_PAIRED addition came from the official ZMK dongle docs
  https://zmk.dev/docs/development/hardware-integration/dongle — we were missing it before.)
- `totem_dongle.overlay` unchanged from the previous session's fix: `zmk,kscan-mock` instead of a
  real gpio-matrix (dongle has no physical switches).

**Major misdiagnosis from the previous session, corrected this session:** the "dongle not
discovering the peripheral" problem documented in the 2026-07-29 status update above was **not a
real firmware bug**. It was chased using `CONFIG_ZMK_USB_LOGGING` + the `zmk-usb-logging` snippet
for a live serial console, and that debug console **reliably stalls partway through boot on this
hardware** (always right after "Welcome to ZMK!", or — on real kscan hardware — right after
configuring the 3rd of 4 GPIO input pins) while **the rest of the firmware keeps running
completely normally underneath**. This was proven by: independently scanning for the left board's
BLE advertisement with the host's own `bluetoothctl` while its debug console showed nothing, and
then physically typing on the left board and watching keystrokes arrive through the dongle's USB
HID — real functional proof, independent of any serial log. Tried and ruled out as the cause:
interrupt vs. polling kscan mode, explicit `CONFIG_ZMK_LOG_LEVEL_DBG`, board-specific GPIOTE
theories — none of it mattered; the console just silently stops flushing at a consistent point
regardless. **Takeaway: don't trust an apparent boot "hang" on this hardware when
`CONFIG_ZMK_USB_LOGGING`/`zmk-usb-logging` is involved — verify with an independent signal (BLE
scan, physical keypress) before concluding the firmware itself is stuck.**

**A real, separate issue that did come up:** after the first `settings_reset` + production flash,
the **right** half didn't connect (left worked immediately, right showed zero BLE trace from any
angle — including a differential `bluetoothctl` scan with right physically unplugged, which
showed no devices disappearing). Rebuilding right with debug logging didn't help (same console
stall as always). What fixed it: **doing a second, completely fresh `settings_reset` →
reflash-production cycle on the right half specifically.** Not fully root-caused *why* the first
attempt didn't take (possibly a stale/incomplete bond or NVS state from its much earlier history
as a `totem_right`-vendor-peripheral-to-left-central in the wired-mode setup) — but the fix was
simple and reliable. If this recurs on a future re-flash, redo `settings_reset` + reflash on
whichever half is misbehaving before assuming it's a bigger problem.

**Debugging technique added this session:** independent BLE verification via the PC's own
Bluetooth adapter, bypassing the unreliable on-device serial console entirely:
```bash
(echo "scan on"; sleep 15; echo "devices"; sleep 1; echo "scan off"; sleep 1; echo "quit") \
  | bluetoothctl
```
Useful for spotting a peripheral's advertisement, or — via a differential scan with a board
unplugged vs. plugged in (`comm -23 <(sort after.txt) <(sort before.txt)`) — confirming whether a
specific board is advertising at all, independent of naming ambiguity (note: a ZMK dongle with
both `ZMK_USB` and `ZMK_BLE` enabled *also* advertises to the host as a normal BLE HID device
under `CONFIG_BT_DEVICE_NAME`/`ZMK_KEYBOARD_NAME` — don't mistake that for a split peripheral's
advertisement; they can share the same visible name).

**Still open / not done this session:**
- ZMK Studio hasn't actually been tested yet (connecting to the dongle's `usb-ZMK_Project_TOTEM_*`
  serial port to live-edit the keymap) — the build supports it (`studio-rpc-usb-uart` +
  `CONFIG_ZMK_STUDIO=y`), just hasn't been opened and verified.
- The `zmk-dongle-display` community module (https://github.com/englmaxi/zmk-dongle-display) was
  identified as the way to get a status display (battery %, connection status) back on the dongle,
  matching what the dongle's original out-of-box factory firmware showed. Not yet integrated —
  deliberately deferred until the pairing itself was confirmed working, which it now is. This is
  the natural next thing to add.
- Lots of diagnostic build directories (`build/left-diag*`, `build/right-diag*`,
  `build/dongle-debug`) and log files (`build-*.log`, `~/dongle_log*.txt`, `~/left_diag*.txt`,
  `~/right_diag*.txt`, `~/scan_*.txt`) are left over from this session's debugging. Safe to delete
  whenever — not needed for the working config, which lives in `build/left`, `build/right`,
  `build/dongle`, `build/reset`, `build/reset-nicenano` plus the tracked/uncommitted config files.
