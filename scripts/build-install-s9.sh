#!/usr/bin/env bash
# Multi-ABI debug APK + install to all connected devices (Galaxy S9 arm64-v8a).
# F1 fix: never build android-arm only — S9 #2 rejects 32-bit-only APKs.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "=== flutter build apk --debug (arm + arm64) ==="
flutter build apk --debug \
  --target-platform android-arm,android-arm64

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
  adb -s "$ser" shell am force-stop com.example.in_range || true
  adb -s "$ser" shell monkey -p com.example.in_range -c android.intent.category.LAUNCHER 1 >/dev/null || true
done

echo "Done. Multi-ABI APK on ${#DEVICES[@]} device(s)."
