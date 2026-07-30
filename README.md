# totem-kb
For backing up totem flashing files.

This backs up a working Keycoon TOTEM split-keyboard setup where a nice!nano dongle acts as the
BLE central for both halves (dongle plugs into the PC via USB, left/right run on independent
power and connect to it over BLE), with ZMK Studio support for live keymap editing.

- **`FLASHING.md`** — quick-start guide for reflashing `firmware/*.uf2` onto the boards.
- **`NOTES.md`** — full narrative of how this setup was built and debugged (useful background,
  not needed for a routine reflash).
- **`config/`** / **`build.yaml`** — the ZMK config source these firmware files were built from.
- **`firmware/`** — compiled `.uf2` files, ready to flash.
