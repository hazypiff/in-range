#!/usr/bin/env bash
# Multi-ABI debug APK + install to all connected devices (Galaxy S9 arm64-v8a).
# F1 fix: never build android-arm only — S9 #2 rejects 32-bit-only APKs.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "=== flutter build apk --debug (arm + arm64 + x64) ==="
# Flutter parses the env file directly. Do not source an untrusted file as shell.
DEFINES=()
if [[ -f .env ]]; then
  DEFINES+=(--dart-define-from-file=.env)
  echo "Using Flutter dart-defines from .env"
fi

flutter build apk --debug \
  --target-platform android-arm,android-arm64,android-x64 \
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

for ser in "${DEVICES[@]}"; do
  echo "--- $ser ---"
  adb -s "$ser" install -r "$APK"
  adb -s "$ser" shell am force-stop io.inrange.app || true
  adb -s "$ser" shell monkey -p io.inrange.app -c android.intent.category.LAUNCHER 1 >/dev/null || true
done

echo "Done. Multi-ABI APK on ${#DEVICES[@]} device(s)."
