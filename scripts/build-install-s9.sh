#!/usr/bin/env bash
# Multi-ABI debug APK + install to all connected devices (Galaxy S9 arm64-v8a).
# F1 fix: never build android-arm only — S9 #2 rejects 32-bit-only APKs.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "=== flutter build apk --debug (arm + arm64) ==="
# Optional: bake host .env into APK via dart-define (device cannot read host files).
# Secrets stay out of git; only present in this lab build artifact.
DEFINES=()
if [[ -f .env ]]; then
  # shellcheck disable=SC1091
  set -a
  # shellcheck source=/dev/null
  source <(grep -E '^(SUPABASE_URL|SUPABASE_PUBLISHABLE_KEY|INRANGE_HMAC_SECRET|INRANGE_USER_ID_SECRET|ENCOUNTER_REVEAL_DELAY_HOURS)=' .env | sed 's/\r$//')
  set +a
  [[ -n "${SUPABASE_URL:-}" ]] && DEFINES+=(--dart-define=SUPABASE_URL="$SUPABASE_URL")
  [[ -n "${SUPABASE_PUBLISHABLE_KEY:-}" ]] && DEFINES+=(--dart-define=SUPABASE_PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY")
  [[ -n "${INRANGE_HMAC_SECRET:-}" ]] && DEFINES+=(--dart-define=INRANGE_HMAC_SECRET="$INRANGE_HMAC_SECRET")
  [[ -n "${INRANGE_USER_ID_SECRET:-}" ]] && DEFINES+=(--dart-define=INRANGE_USER_ID_SECRET="$INRANGE_USER_ID_SECRET")
  [[ -n "${ENCOUNTER_REVEAL_DELAY_HOURS:-}" ]] && DEFINES+=(--dart-define=ENCOUNTER_REVEAL_DELAY_HOURS="$ENCOUNTER_REVEAL_DELAY_HOURS")
  echo "Using ${#DEFINES[@]} dart-define(s) from .env"
fi

flutter build apk --debug \
  --target-platform android-arm,android-arm64 \
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
  adb -s "$ser" shell am force-stop com.example.in_range || true
  adb -s "$ser" shell monkey -p com.example.in_range -c android.intent.category.LAUNCHER 1 >/dev/null || true
done

echo "Done. Multi-ABI APK on ${#DEVICES[@]} device(s)."
