#!/usr/bin/env bash
# Phase 4: diagnostic artifact generation GATED ON TESTS. Produces the diag
# device app for hardware runs ONLY after the full test + isolation gates pass,
# and emits the artifact SHA-256 + build config for the evidence manifest.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== gate 1: flutter analyze + test =="
flutter analyze
flutter test

echo "== gate 2: native RunnerTests (both schemes) =="
SIM='platform=iOS Simulator,name=iPhone 17'
xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner \
  -configuration Debug -destination "$SIM" -only-testing:RunnerTests \
  CODE_SIGNING_ALLOWED=NO >/dev/null
xcodebuild test -workspace ios/Runner.xcworkspace -scheme diag \
  -configuration Debug-diag -destination "$SIM" -only-testing:RunnerTests \
  CODE_SIGNING_ALLOWED=NO >/dev/null

echo "== gate 3: release isolation (build-settings + final-binary) =="
bash scripts/check_release_isolation.sh
bash scripts/check_final_binary_isolation.sh

echo "== gates passed → building diag artifact =="
# B3 fleet alignment: bake a shared W5-event run secret into the diag build so
# every device installed from THIS artifact shares HMAC handles AND they survive
# OS restoration (native persists it). Provide a 64-hex secret via the
# INRANGE_DIAG_RUN_SECRET env; if absent, generate one so a single build/fleet
# is still aligned (each fresh build without it re-aligns to a new secret).
RUN_SECRET="${INRANGE_DIAG_RUN_SECRET:-$(openssl rand -hex 32)}"
if [ "${#RUN_SECRET}" -lt 64 ]; then
  echo "ERROR: INRANGE_DIAG_RUN_SECRET must be >= 64 hex chars" >&2
  exit 1
fi
flutter build ios --flavor diag --release --dart-define-from-file=.env \
  --dart-define=INRANGE_W5_LINKS=true \
  --dart-define=INRANGE_DIAG_RUN_SECRET="$RUN_SECRET"
APP="build/ios/iphoneos/Runner.app"
echo "artifact: $APP"
echo "bundle id: $(plutil -extract CFBundleIdentifier raw "$APP/Info.plist")"
echo "SHA-256(Runner): $(shasum -a 256 "$APP/Runner" | awk '{print $1}')"
# Record the fleet secret for the evidence manifest (diag-only, not a
# production secret). Install THIS SAME artifact to every device in the fleet
# so their handles align; restoration continuity holds per device regardless.
echo "diag run secret (fleet handle alignment): $RUN_SECRET"
