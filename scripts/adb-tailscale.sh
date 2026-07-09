#!/usr/bin/env bash
# Connect / re-connect phones over Tailscale ADB (port 5555).
# Prerequisite: each phone has Tailscale Connected on the SAME account as this
# host (mayor420@), and `adb tcpip 5555` was run once while USB was plugged in.
set -euo pipefail

# Known device Tailscale IPs (update when nodes rejoin)
declare -A TS_IPS=(
  [pixel-4a-5g]=100.79.154.58
  # galaxy-s9 on mayor420 tailnet (when online): check `tailscale status`
)

PORT=5555

usage() {
  cat <<EOF
Usage: $0 [status|connect|tcpip-usb|rssi]

  status      Show adb devices + tailscale peers
  connect     adb connect all known Tailscale IPs:5555
  tcpip-usb   On every USB device, run adb tcpip 5555 (run before unplugging)
  rssi        Grep live In Range BLE sighting logs from all devices
EOF
}

cmd_status() {
  echo "=== adb devices ==="
  adb devices -l
  echo
  echo "=== tailscale status ==="
  tailscale status 2>/dev/null || true
}

cmd_connect() {
  # Discover online android peers from tailscale
  while read -r ip name; do
    [[ -z "${ip:-}" ]] && continue
    echo "→ adb connect ${ip}:${PORT}  ($name)"
    timeout 8 adb connect "${ip}:${PORT}" 2>&1 || echo "  (timeout/fail)"
  done < <(tailscale status 2>/dev/null | awk '/android/ && !/offline/ {print $1, $2}')

  # Also try static map
  for name in "${!TS_IPS[@]}"; do
    ip="${TS_IPS[$name]}"
    echo "→ adb connect ${ip}:${PORT}  ($name static)"
    timeout 8 adb connect "${ip}:${PORT}" 2>&1 || echo "  (timeout/fail)"
  done
  echo
  adb devices -l
}

cmd_tcpip_usb() {
  mapfile -t serials < <(adb devices | awk '/\tdevice$/ {print $1}' | grep -v :)
  if ((${#serials[@]} == 0)); then
    echo "No USB devices. Plug phones in first."
    exit 1
  fi
  for s in "${serials[@]}"; do
    echo "→ adb -s $s tcpip $PORT"
    adb -s "$s" tcpip "$PORT"
  done
  echo "TCP mode enabled. Ensure Tailscale is Connected, then: $0 connect"
  echo "You can unplug USB after connect succeeds."
}

cmd_rssi() {
  mapfile -t devs < <(adb devices | awk '/\tdevice$/ {print $1}')
  for d in "${devs[@]}"; do
    echo "========== $d =========="
    adb -s "$d" logcat -d 2>/dev/null | grep 'I flutter' | grep -iE 'Sighting|Started BLE|Local encounter' | tail -8
  done
}

case "${1:-status}" in
  status) cmd_status ;;
  connect) cmd_connect ;;
  tcpip-usb) cmd_tcpip_usb ;;
  rssi) cmd_rssi ;;
  -h|--help|help) usage ;;
  *) usage; exit 1 ;;
esac
