#!/bin/bash
# Back up EEPROM and flash a Keyball (Pro Micro / caterina) half with avrdude.
# Usage: flash.sh <firmware.hex> [side] [wait_seconds]
#        flash.sh --backup-only  [side] [wait_seconds]
set -u
TARGET="${1:?usage: flash.sh <firmware.hex>|--backup-only [side] [wait_seconds]}"
SIDE="${2:-unknown}"
WAIT="${3:-570}"
REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
BACKUP_DIR="$REPO_ROOT/.tmp/eeprom"
EEPROM_SIZE=1024

if [ "$TARGET" = "--backup-only" ]; then
  HEX=""
else
  HEX="$TARGET"
  [ -r "$HEX" ] || { echo "!!! hex not found: $HEX"; exit 2; }
fi
mkdir -p "$BACKUP_DIR"

echo "Waiting for caterina bootloader (press the reset button on the '$SIDE' half)..."
end=$((SECONDS+WAIT))
while [ $SECONDS -lt $end ]; do
  for dev in /dev/ttyACM*; do
    # udev applies the uaccess ACL slightly after the node appears; wait for -w, not just -e
    if [ -w "$dev" ]; then
      BACKUP="$BACKUP_DIR/eeprom-$SIDE-$(date +%Y%m%d-%H%M%S).bin"
      echo ">>> $(date +%T) bootloader writable at $dev"
      # One avrdude session: caterina stays in the bootloader while a programmer is connected,
      # so the EEPROM read and the flash write both fit in the single ~8s window.
      ops=(-U "eeprom:r:$BACKUP:r")
      [ -n "$HEX" ] && ops+=(-U "flash:w:$HEX:i")
      # A hung avr109 handshake must not block the next attempt.
      if timeout 40 avrdude -p atmega32u4 -c avr109 -P "$dev" "${ops[@]}"; then
        size=$(stat -c %s "$BACKUP" 2>/dev/null || echo 0)
        if [ "$size" -ne "$EEPROM_SIZE" ]; then
          echo "!!! EEPROM backup is $size bytes, expected $EEPROM_SIZE: $BACKUP"
          exit 3
        fi
        echo ">>> EEPROM backup OK ($size bytes): $BACKUP"
        echo ">>> restore with: avrdude -p atmega32u4 -c avr109 -P /dev/ttyACM0 -U eeprom:w:$BACKUP:r"
        [ -n "$HEX" ] && echo ">>> FLASH OK"
        exit 0
      fi
      rm -f "$BACKUP"
      echo "!!! $(date +%T) attempt failed, waiting for next reset..."
      sleep 1
    fi
  done
  sleep 0.05
done
echo "!!! timeout: nothing written"
exit 1
