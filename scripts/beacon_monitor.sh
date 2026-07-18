#!/usr/bin/env bash
# In Range multi-phone beacon test monitor.
# Streams flutter logs from every connected Android (except EXCLUDE list),
# filters beacon/sighting/encounter lines, prefixes device label + wall time,
# writes a combined timeline + per-device logs under run_logs/beacon_test/.
#
# Usage:
#   bash scripts/beacon_monitor.sh            # monitor all connected devices
#   EXCLUDE="0A081JECB06627" bash scripts/... # exclude serials (default: the Pixel)
#   CALIB=1 bash scripts/beacon_monitor.sh    # also pass the calibration record
#                                             # types (Advert/WifiScan/WifiAp/
#                                             # GpsFix) so walk health is visible
#                                             # live. Monitoring is a VIEW only —
#                                             # extraction always uses the raw
#                                             # walk_capture.sh logcat dumps.
#
# Wireless: before unplugging a phone, run:
#   adb -s <serial> tcpip 5555
#   adb connect <phone-wifi-ip>:5555
# then the monitor keeps streaming over WiFi.

set -u
EXCLUDE="${EXCLUDE:-0A081JECB06627}"   # never touch the Pixel proxy
OUT_DIR="$(cd "$(dirname "$0")/.." && pwd)/run_logs/beacon_test"
mkdir -p "$OUT_DIR"
COMBINED="$OUT_DIR/combined_$(date +%H%M%S).log"
echo "combined timeline: $COMBINED"

PATTERN='Started BLE advertising|BLE scan started|Sighting observed|record_sighting|claim_token|Encounter|encounter|turnOnBeacon|Beacon refused|advertising stopped|scan (re)?start|release_token|Locals server sync|record_location_ping|token rotat|Rotated token'
if [ "${CALIB:-0}" = "1" ]; then
  PATTERN="$PATTERN|Advert corr=|WifiScan seq=|WifiAp seq=|GpsFix lat="
fi

pids=()
cleanup() { for p in "${pids[@]}"; do kill "$p" 2>/dev/null; done; }
trap cleanup EXIT INT TERM

for S in $(adb devices | awk 'NR>1 && $2=="device" {print $1}'); do
  skip=false
  for X in $EXCLUDE; do [ "$S" = "$X" ] && skip=true; done
  $skip && { echo "skip (excluded): $S"; continue; }
  MODEL=$(adb -s "$S" shell getprop ro.product.model 2>/dev/null | tr -d '\r' | tr ' ' '_')
  LABEL="${MODEL:-$S}-${S: -6}"
  echo "monitoring: $LABEL ($S)"
  adb -s "$S" logcat -T 1 -s flutter:I 2>/dev/null \
    | grep --line-buffered -E "$PATTERN" \
    | while IFS= read -r line; do
        ts=$(date +%H:%M:%S)
        echo "$ts [$LABEL] $line" | tee -a "$OUT_DIR/$LABEL.log"
      done >> "$COMBINED" &
  pids+=($!)
done

[ ${#pids[@]} -eq 0 ] && { echo "no devices to monitor"; exit 1; }
echo "--- monitor running, Ctrl-C to stop; tail -f $COMBINED ---"
wait
