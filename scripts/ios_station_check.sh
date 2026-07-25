#!/usr/bin/env bash
# Pull an iPhone calibration DB over USB and summarize one operator-recorded
# station. Windowing is anchored to the recorded wall-clock start, never to
# the first received advert: a locked iPhone may not deliver its first row
# until the hand half of the station.
#
# Measured 90 s pocket -> hand station:
#   bash scripts/ios_station_check.sh 15p \
#     --date 2026-07-25 --start 10:00:00
#
# Foreground 60 s desk smoke:
#   bash scripts/ios_station_check.sh 15p \
#     --date 2026-07-25 --start 09:15:00 \
#     --window smoke:0:60 --trim 0
set -euo pipefail

IPHONE14="27A0976C-78DD-5D1D-926E-0CE635E5C23A"
IPHONE15P="67B16DBC-964F-592E-986C-281FED5AE8B8"

case "${1:-}" in
  14)  IOS_DEVICE=$IPHONE14 ;;
  15p) IOS_DEVICE=$IPHONE15P ;;
  *)
    echo "usage: $0 14|15p --date YYYY-MM-DD --start HH:MM:SS [summary options]"
    exit 1
    ;;
esac
IOS_LABEL=$1
shift

if (( $# == 0 )); then
  echo "usage: $0 14|15p --date YYYY-MM-DD --start HH:MM:SS [summary options]"
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STATION_TMP="$(mktemp -d "${TMPDIR:-/tmp}/inrange_station_${IOS_LABEL}_XXXXXX")"
DB_COPY="$STATION_TMP/in_range_local.db"

xcrun devicectl device copy from --device "$IOS_DEVICE" --user mobile \
  --domain-type appDataContainer --domain-identifier io.inrange.inRange \
  --source Documents/in_range_local.db --destination "$DB_COPY" >/dev/null

echo "iPhone DB copy: $DB_COPY"
python3 "$SCRIPT_DIR/ios_station_summary.py" "$DB_COPY" "$@"
