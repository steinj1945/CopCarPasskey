#!/usr/bin/env bash
# Build & Flash -- PasskeyLock ESP32
# Usage: ./flash.sh [/dev/cu.usbserial-xxx]

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -n "$1" ]; then
    PORT="$1"
else
    echo "Detected serial ports:"
    ls /dev/cu.* 2>/dev/null | grep -iE "usb|serial|esp|cp210|ch340|ftdi" || echo "  (none found)"
    echo
    read -r -p "Enter port (e.g. /dev/cu.usbserial-0001): " PORT
fi

echo
echo "Port : $PORT"
echo

echo "[1/2] Compiling..."
pio run -d "$SCRIPT_DIR"

echo
echo "[2/2] Uploading to $PORT..."
pio run -d "$SCRIPT_DIR" -t upload --upload-port "$PORT"

echo
echo "Done."
