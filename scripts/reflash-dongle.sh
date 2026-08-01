#!/usr/bin/env bash
# Rebuild + reflash the dongle from the current config/boards/shields/totem/totem.keymap.
# For pure keymap/behavior/combo changes only the dongle needs rebuilding (it's the BLE
# central running all keymap logic) — see FLASHING.md. Left/right are untouched by this.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "==> Building dongle firmware..."
docker run --rm -v "$REPO_ROOT:/workspaceRoot" -w /workspaceRoot zmkfirmware/zmk-build-arm:stable bash -c "
set -e
git config --global --add safe.directory '*'
west zephyr-export
west build -s zmk/app -b nice_nano/nrf52840/zmk -d build/dongle -p always -- -DSHIELD='totem_dongle dongle_display' -DZMK_CONFIG=/workspaceRoot/config -DSNIPPET=studio-rpc-usb-uart -DCONFIG_ZMK_STUDIO=y
"

cp build/dongle/zephyr/zmk.uf2 firmware/dongle.uf2
echo "==> Built firmware/dongle.uf2 ($(stat -c%s firmware/dongle.uf2) bytes)"

echo
echo "Double-tap the reset button on the dongle now to enter the bootloader."
echo "Waiting for the NICENANO drive to mount (up to 60s)..."

MOUNT=""
for _ in $(seq 1 60); do
  for candidate in /media/*/NICENANO /run/media/*/NICENANO; do
    if [ -d "$candidate" ]; then
      MOUNT="$candidate"
      break 2
    fi
  done
  sleep 1
done

if [ -z "$MOUNT" ]; then
  echo "Timed out waiting for the NICENANO drive."
  echo "Flash manually: cp firmware/dongle.uf2 <mount-point>/"
  exit 1
fi

echo "==> Found $MOUNT, flashing..."
cp firmware/dongle.uf2 "$MOUNT/"
echo "==> Flashed. The dongle will reboot automatically (drive will disappear)."
