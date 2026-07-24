#!/usr/bin/env bash
# Multi-ABI debug APK + install to all connected devices (Galaxy S9 arm64-v8a).
# F1 fix: never build android-arm only — S9 #2 rejects 32-bit-only APKs.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Devices owned by another rig. Extra serials can be appended through EXCLUDE,
# but callers cannot accidentally remove the protected defaults.
PROTECTED_DEVICES="0A081JECB06627 3931395a4d583398"
EXCLUDE="$PROTECTED_DEVICES ${EXCLUDE:-}"

is_excluded() {
  local serial=$1 excluded
  for excluded in $EXCLUDE; do
    [[ "$serial" == "$excluded" ]] && return 0
  done
  return 1
}

echo "=== flutter build apk --debug (arm + arm64 + x64) ==="
# Flutter parses the env file directly. Do not source an untrusted file as shell.
DEFINES=()
if [[ -f .env ]]; then
  DEFINES+=(--dart-define-from-file=.env)
  echo "Using Flutter dart-defines from .env"
fi

# Stamp the source commit into versionName so walk_capture.sh can verify the
# phones are on the frozen build before a calibration walk (2026-07-23: Rahul's
# devices silently ran a pre-native-GATT build for a whole round). A dirty
# client tree gets a -dirty suffix — the preflight refuses those, because the
# sha alone would misdescribe what is actually installed.
STAMP="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
if ! git diff --quiet HEAD -- lib android ios scripts 2>/dev/null; then
  STAMP="$STAMP-dirty"
  echo "WARNING: client tree is dirty — stamping $STAMP (not walk-eligible)" >&2
fi
BUILD_NAME="0.1.0-$STAMP"
echo "Build stamp: $BUILD_NAME"

flutter build apk --debug \
  --target-platform android-arm,android-arm64,android-x64 \
  --build-name="$BUILD_NAME" \
  "${DEFINES[@]}"
APK="build/app/outputs/flutter-apk/app-debug.apk"
if [[ ! -f "$APK" ]]; then
  echo "APK missing: $APK" >&2
  exit 1
fi

echo "=== Install on all adb devices ==="
mapfile -t DEVICES < <(adb devices | awk '/\tdevice$/{print $1}')
if [[ ${#DEVICES[@]} -eq 0 ]]; then
  echo "No devices connected" >&2
  exit 1
fi

installed=0
for ser in "${DEVICES[@]}"; do
  if is_excluded "$ser"; then
    echo "--- $ser: skip (protected/excluded) ---"
    continue
  fi
  echo "--- $ser ---"
  adb -s "$ser" install -r "$APK"
  adb -s "$ser" shell am force-stop io.inrange.app || true
  adb -s "$ser" shell monkey -p io.inrange.app -c android.intent.category.LAUNCHER 1 >/dev/null || true
  installed=$((installed + 1))
done

if [[ "$installed" -eq 0 ]]; then
  echo "No non-excluded devices connected; nothing installed" >&2
  exit 1
fi

echo "Done. Multi-ABI APK on $installed device(s)."
