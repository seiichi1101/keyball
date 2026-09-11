#!/bin/bash
# Restore a VIA keymap backup onto a half whose firmware was rebuilt on a different date.
#
# QMK derives the VIA EEPROM magic from QMK_BUILDDATE (via_eeprom_is_valid()), so a firmware
# built on another day rejects the stored keymap and reinitialises it from keymap.c. Writing the
# backup unchanged does not help: the running firmware just resets it again on the next boot.
# This patches the backup's 3 magic bytes to whatever the running firmware wrote, then restores.
#
# Usage: restore-eeprom.sh <backup.bin> [wait_seconds]
set -u
BACKUP="${1:?usage: restore-eeprom.sh <backup.bin> [wait_seconds]}"
WAIT="${2:-570}"
MAGIC_OFF=$((0x25))   # VIA_EEPROM_MAGIC_ADDR, 3 bytes
EEPROM_SIZE=1024
[ -r "$BACKUP" ] || { echo "!!! backup not found: $BACKUP"; exit 2; }
[ "$(stat -c %s "$BACKUP")" -eq "$EEPROM_SIZE" ] || { echo "!!! backup is not $EEPROM_SIZE bytes"; exit 2; }

WORK="$(dirname "$BACKUP")"
LIVE="$WORK/.live-$$.bin"
PATCHED="$WORK/.patched-$$.bin"
trap 'rm -f "$LIVE" "$PATCHED"' EXIT

wait_for_bootloader() {
  local end=$((SECONDS+WAIT))
  while [ $SECONDS -lt $end ]; do
    for dev in /dev/ttyACM*; do
      # udev applies the uaccess ACL slightly after the node appears; wait for -w, not just -e
      [ -w "$dev" ] && { echo "$dev"; return 0; }
    done
    sleep 0.05
  done
  return 1
}

echo "STEP 1/2: reading the magic the running firmware expects."
echo "Press the reset button now..."
dev=$(wait_for_bootloader) || { echo "!!! timeout"; exit 1; }
echo ">>> $(date +%T) bootloader at $dev"
timeout 40 avrdude -p atmega32u4 -c avr109 -P "$dev" -U "eeprom:r:$LIVE:r" || { echo "!!! read failed"; exit 1; }

python3 - "$BACKUP" "$LIVE" "$PATCHED" "$MAGIC_OFF" <<'PY' || exit 1
import sys
backup, live, out, off = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
b = bytearray(open(backup,'rb').read())
magic = open(live,'rb').read()[off:off+3]
print(f">>> backup magic   {bytes(b[off:off+3]).hex(' ')}")
print(f">>> firmware magic {magic.hex(' ')}")
if bytes(b[off:off+3]) == magic:
    print(">>> magic already matches; restoring as-is")
b[off:off+3] = magic
open(out,'wb').write(bytes(b))
PY

echo
echo "STEP 2/2: writing the patched keymap back."
echo "Press the reset button again..."
dev=$(wait_for_bootloader) || { echo "!!! timeout"; exit 1; }
echo ">>> $(date +%T) bootloader at $dev"
timeout 60 avrdude -p atmega32u4 -c avr109 -P "$dev" -U "eeprom:w:$PATCHED:r" || { echo "!!! write failed"; exit 1; }
echo ">>> RESTORE OK -- reconnect the keyboard and check the keymap in Remap"
