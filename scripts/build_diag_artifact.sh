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
flutter build ios --flavor diag --release --dart-define-from-file=.env \
  --dart-define=INRANGE_W5_LINKS=true
APP="build/ios/iphoneos/Runner.app"
echo "artifact: $APP"
echo "bundle id: $(plutil -extract CFBundleIdentifier raw "$APP/Info.plist")"
echo "SHA-256(Runner): $(shasum -a 256 "$APP/Runner" | awk '{print $1}')"
