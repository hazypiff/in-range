#!/usr/bin/env bash
# Walk capture harness — reproducible calibration log capture.
#
#   scripts/walk_capture.sh prep [name]   BEFORE the walk: resize each phone's
#                                         logcat ring buffer (NOTE: -G clears
#                                         it) and record clock offsets.
#   scripts/walk_capture.sh pull [name]   AFTER the walk: raw threadtime dump
#                                         per phone -> dated gzip archive +
#                                         meta.json (offsets re-measured).
#
# Archive: run_logs/walks/<YYYY-MM-DD>[-name]/<model>-<serial6>.threadtime.log.gz
# meta-<phase>.json carries host_minus_device_s per device — pass it to
# extract_walk.py as --offset-a/--offset-b so device log timestamps align with
# the host clock the station times were noted on.
#
# Raw logs are the source of truth; everything extract_walk.py derives is
# reproducible from this archive.
set -euo pipefail
cd "$(dirname "$0")/.."

EXCLUDE="${EXCLUDE:-0A081JECB06627}"   # Pixel proxy — never touch
BUF="${BUF:-16M}"
MODE="${1:-}"
NAME="${2:-}"
DIR="run_logs/walks/$(date +%F)${NAME:+-$NAME}"

usage() { sed -n '2,17p' "$0"; exit 1; }
[ "$MODE" = "prep" ] || [ "$MODE" = "pull" ] || usage

devices() {
  adb devices | awk 'NR>1 && $2=="device" {print $1}' | while read -r S; do
    skip=0
    for X in $EXCLUDE; do [ "$S" = "$X" ] && skip=1; done
    [ "$skip" = 0 ] && echo "$S"
  done
}

label_for() {
  local S=$1 MODEL
  MODEL=$(adb -s "$S" shell getprop ro.product.model 2>/dev/null | tr -d '\r' | tr ' ' '_')
  echo "${MODEL:-unknown}-${S: -6}"
}

# Seconds the HOST clock is ahead of the device clock (host - device),
# bracketed by two host reads so ADB latency cancels to first order. Device
# `date +%s` is whole-second, so treat offsets as ±0.5 s.
offset_for() {
  local S=$1 h0 h1 dev
  h0=$(date +%s.%3N)
  dev=$(adb -s "$S" shell date +%s 2>/dev/null | tr -d '\r')
  h1=$(date +%s.%3N)
  awk -v h0="$h0" -v h1="$h1" -v d="$dev" 'BEGIN { printf "%.1f", (h0 + h1) / 2 - d }'
}

write_meta() {
  local phase=$1 first=1 S
  {
    echo '{'
    echo "  \"host_time\": \"$(date -Is)\","
    echo "  \"phase\": \"$phase\","
    echo "  \"buffer_target\": \"$BUF\","
    echo '  "devices": ['
    for S in $(devices); do
      [ "$first" = 0 ] && echo ','
      first=0
      printf '    {"serial": "%s", "label": "%s", "buffer": "%s", "host_minus_device_s": %s}' \
        "$S" "$(label_for "$S")" \
        "$(adb -s "$S" logcat -g main 2>/dev/null | head -1 | tr -d '\r' | sed 's/"/\\"/g')" \
        "$(offset_for "$S")"
    done
    echo
    echo '  ]'
    echo '}'
  } > "$DIR/meta-$phase.json"
  echo "wrote $DIR/meta-$phase.json"
}

mkdir -p "$DIR"

case "$MODE" in
  prep)
    for S in $(devices); do
      echo "prep $(label_for "$S"): logcat buffer -> $BUF (buffer cleared)"
      adb -s "$S" logcat -G "$BUF"
    done
    write_meta prep
    echo "ready — walk now; station times on the HOST clock, then: $0 pull${NAME:+ $NAME}"
    ;;
  pull)
    for S in $(devices); do
      L=$(label_for "$S")
      OUT="$DIR/$L.threadtime.log"
      echo "pull $L -> $OUT.gz"
      adb -s "$S" logcat -d -v threadtime > "$OUT"
      gzip -9 -f "$OUT"
    done
    write_meta pull
    echo "done — extract with:"
    echo "  python3 scripts/extract_walk.py $DIR/<A>.threadtime.log.gz $DIR/<B>.threadtime.log.gz \\"
    echo "      --stations <label@HH:MM:SS+dur ...> --offset-a <A host_minus_device_s> \\"
    echo "      --offset-b <B ...> --json $DIR/walk.json --csv $DIR/walk.csv"
    ;;
esac
