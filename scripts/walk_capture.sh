#!/usr/bin/env bash
# Walk capture harness — reproducible calibration log capture.
#
#   scripts/walk_capture.sh prep [name]   BEFORE the walk: verify every phone
#                                         runs the frozen build, resize each
#                                         phone's logcat ring buffer (NOTE: -G
#                                         clears it) and record clock offsets.
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
#
# prep aborts if any phone's installed build is not the FREEZE build (default
# calib-freeze-2026-07-24b). ALLOW_BUILD_MISMATCH=1 downgrades that to a warning.
set -euo pipefail
cd "$(dirname "$0")/.."

# Pixel proxy + S9 assigned to the Instagram fleet — never touch. EXCLUDE adds
# session-specific serials without replacing these protected defaults.
PROTECTED_DEVICES="0A081JECB06627 3931395a4d583398"
EXCLUDE="$PROTECTED_DEVICES ${EXCLUDE:-}"
# 64M: the earlier audit found 16M already ~60% consumed on a walk, and full
# WiFi AP logging adds substantial volume on top.
BUF="${BUF:-64M}"
# Calibration freeze the walk must run under. prep verifies every connected
# phone's installed build against this before touching the buffers.
FREEZE="${FREEZE:-calib-freeze-2026-07-24b}"
PKG="${PKG:-io.inrange.app}"
MODE="${1:-}"
NAME="${2:-}"
DIR="run_logs/walks/$(date +%F)${NAME:+-$NAME}"

usage() { sed -n '2,22p' "$0"; exit 1; }
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

# versionName of the installed app, e.g. "0.1.0-95c6eae" (see
# build-install-s9.sh). Builds predating the stamp report "1.0".
installed_stamp() {
  adb -s "$1" shell dumpsys package "$PKG" 2>/dev/null \
    | tr -d '\r' | sed -n 's/.*versionName=\([^ ]*\).*/\1/p' | head -1
}

# Refuse to start a calibration walk on phones that are not running the frozen
# build. This exists because a stale install does not fail loudly — it produces
# plausible rows under different behavior (2026-07-23: pre-native-GATT W3), and
# the fail-closed trainer gates will happily pass a model fit on that mixture.
# Override with ALLOW_BUILD_MISMATCH=1 for deliberate cross-build experiments.
verify_builds() {
  local want S L got sha bad=0
  # ^{commit} is load-bearing: on an ANNOTATED tag plain rev-parse returns the
  # tag object, which never equals a build stamp, so every phone would fall
  # through to the diff path and report "differs outside client code" instead
  # of an exact match. (07-23 was lightweight and hid this; 07-24 is annotated.)
  want=$(git rev-parse --short "$FREEZE^{commit}" 2>/dev/null || true)
  if [ -z "$want" ]; then
    echo "ERROR: cannot resolve freeze '$FREEZE' — try: git fetch --tags" >&2
    exit 1
  fi
  echo "freeze $FREEZE = $want — verifying installed builds"
  for S in $(devices); do
    L=$(label_for "$S")
    got=$(installed_stamp "$S")
    if [ -z "$got" ]; then
      echo "  FAIL $L: $PKG not installed" >&2; bad=1; continue
    fi
    case "$got" in
      *-*) sha=${got#*-} ;;
      *)   echo "  FAIL $L: unstamped build ($got) — predates build stamping, reinstall" >&2
           bad=1; continue ;;
    esac
    case "$sha" in
      *-dirty) echo "  FAIL $L: built from a dirty tree ($sha) — the commit does not describe it" >&2
               bad=1; continue ;;
    esac
    if [ "$sha" = "$want" ]; then
      echo "  ok   $L: $sha"
      continue
    fi
    # A later commit is fine as long as it changes nothing the walk measures —
    # docs/web churn moves HEAD constantly and must not block a walk.
    if ! git cat-file -e "$sha^{commit}" 2>/dev/null; then
      echo "  FAIL $L: $sha is not a commit in this repo — git fetch, or rebuild" >&2
      bad=1; continue
    fi
    # Client code ONLY. The stamp describes an APK, so comparing host-side
    # scripts/ against it is a category error — deploy-web.sh cannot change what
    # a phone emits, and including it made this check block its own harness.
    if git diff --quiet "$want" "$sha" -- lib android ios 2>/dev/null; then
      echo "  ok   $L: $sha (differs from freeze outside client code only)"
      continue
    fi
    echo "  FAIL $L: $sha differs from freeze $want in client code:" >&2
    git diff --stat "$want" "$sha" -- lib android ios 2>/dev/null \
      | sed 's/^/         /' >&2
    bad=1
  done
  if [ "$bad" != 0 ]; then
    if [ "${ALLOW_BUILD_MISMATCH:-0}" = 1 ]; then
      echo "ALLOW_BUILD_MISMATCH=1 — continuing on non-frozen builds." >&2
      echo "This walk is NOT comparable to the frozen round; stamp it --trainable no." >&2
      return 0
    fi
    echo "aborting; reinstall from $FREEZE (see docs/RAHUL_REINSTALL.md)." >&2
    echo "  bash scripts/build-install-s9.sh" >&2
    exit 1
  fi
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
      # build: what was actually installed, so the archive records the
      # data-producing code rather than relying on the walk being prepped right.
      printf '    {"serial": "%s", "label": "%s", "build": "%s", "buffer": "%s", "host_minus_device_s": %s}' \
        "$S" "$(label_for "$S")" "$(installed_stamp "$S")" \
        "$(adb -s "$S" logcat -g main 2>/dev/null | head -1 | tr -d '\r' | sed 's/"/\\"/g')" \
        "$(offset_for "$S")"
    done
    echo
    echo '  ]'
    echo '}'
  } > "$DIR/meta-$phase.json"
  echo "wrote $DIR/meta-$phase.json"
}

# Before the archive dir exists and before the buffers are touched — a failed
# verify should leave no trace: no cleared logs, no empty walk directory.
if [ "$MODE" = "prep" ]; then verify_builds; fi

mkdir -p "$DIR"

case "$MODE" in
  prep)
    for S in $(devices); do
      L=$(label_for "$S")
      echo "prep $L: logcat buffer -> $BUF + clear"
      adb -s "$S" logcat -G "$BUF"
      # -G does NOT reliably clear on the S9s (desk test 2026-07-18 found
      # hours of retained backlog) — clear explicitly so the walk starts on
      # an empty buffer.
      adb -s "$S" logcat -c
      # Verify the resize actually took — walking with a silently-small buffer
      # loses the start of the walk. Normalizes "64Mb" / "64 MiB" style output.
      line=$(adb -s "$S" logcat -g main 2>/dev/null | head -1 | tr -d '\r')
      got=$(echo "$line" | grep -oiE 'ring buffer is *[0-9]+ *[kmg]i?b' \
              | tr -d ' ' | tr '[:upper:]' '[:lower:]' \
              | sed 's/ringbufferis//; s/ib$/b/')
      want=$(echo "${BUF}b" | tr '[:upper:]' '[:lower:]')
      if [ "$got" != "$want" ]; then
        echo "ERROR: $L buffer verify failed — wanted $want, device reports:" >&2
        echo "  $line" >&2
        echo "aborting; do not walk on this buffer." >&2
        exit 1
      fi
      echo "  verified: $got"
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
