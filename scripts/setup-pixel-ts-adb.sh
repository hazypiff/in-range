#!/usr/bin/env bash
# Safe wireless ADB setup for rooted Pixel over Tailscale.
# DO NOT stop/restart adbd — that drops USB and can leave TCP closed.
# Use: plug Pixel USB once → run this → unplug → stays on TS:5555
set -euo pipefail

PORT=5555
TS_IP="${PIXEL_TS_IP:-100.79.154.58}"
PKG=io.inrange.app

echo "Looking for Pixel USB..."
SERIAL=""
for i in $(seq 1 60); do
  SERIAL=$(adb devices -l | awk '/product:bramble|model:Pixel/{print $1; exit}')
  if [[ -n "$SERIAL" && "$SERIAL" != *:* ]]; then
    break
  fi
  # also match by any google device
  SERIAL=$(adb devices | awk '/\tdevice$/{print $1}' | grep -v ':' | while read -r s; do
    m=$(adb -s "$s" shell getprop ro.product.device 2>/dev/null | tr -d '\r')
    [[ "$m" == "bramble" ]] && echo "$s" && break
  done)
  [[ -n "$SERIAL" ]] && break
  sleep 1
done

if [[ -z "${SERIAL:-}" ]]; then
  echo "No Pixel on USB. Plug the rooted Pixel in with USB debugging on."
  exit 1
fi

echo "Found USB serial: $SERIAL"
adb -s "$SERIAL" shell su -c 'id' | head -1

# Safe TCP enable (does not kill USB connection permanently)
echo "→ adb tcpip $PORT"
adb -s "$SERIAL" tcpip "$PORT"
sleep 2

echo "→ adb connect ${TS_IP}:${PORT}"
adb connect "${TS_IP}:${PORT}"
sleep 1

# Root grants + BT + keep awake
adb -s "${TS_IP}:${PORT}" shell su -c "
pm grant $PKG android.permission.ACCESS_FINE_LOCATION 2>/dev/null
pm grant $PKG android.permission.ACCESS_COARSE_LOCATION 2>/dev/null
pm grant $PKG android.permission.ACCESS_BACKGROUND_LOCATION 2>/dev/null
pm grant $PKG android.permission.BLUETOOTH_SCAN 2>/dev/null
pm grant $PKG android.permission.BLUETOOTH_CONNECT 2>/dev/null
pm grant $PKG android.permission.BLUETOOTH_ADVERTISE 2>/dev/null
appops set $PKG FINE_LOCATION allow 2>/dev/null
appops set $PKG COARSE_LOCATION allow 2>/dev/null
cmd bluetooth_manager enable 2>/dev/null
settings put global bluetooth_on 1
settings put system screen_off_timeout 1800000
svc power stayon true
echo setup-ok
"

echo
echo "Wireless ADB ready:"
echo "  adb -s ${TS_IP}:${PORT} shell su -c id"
echo "You can unplug USB now. Tailscale must stay Connected."
adb devices -l
