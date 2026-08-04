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
# OS restoration. The secret is provided ONLY via the INRANGE_DIAG_RUN_SECRET
# env (never generated here, never committed). The build NEVER prints the value
# — only a short fingerprint so the manifest can confirm fleet devices share the
# same secret without exposing it.
if ! printf '%s' "${INRANGE_DIAG_RUN_SECRET:-}" | grep -qE '^[0-9a-fA-F]{64,}$'; then
  echo "ERROR: set INRANGE_DIAG_RUN_SECRET to >= 64 HEX chars in the environment." >&2
  echo "       (native rejects non-hex silently, so a non-hex value must fail here.)" >&2
  echo "       It is baked for fleet alignment; it is never generated or committed." >&2
  exit 1
fi
RUN_SECRET_FP=$(printf '%s' "$INRANGE_DIAG_RUN_SECRET" | shasum -a 256 | cut -c1-12)
flutter build ios --flavor diag --release --dart-define-from-file=.env \
  --dart-define=INRANGE_W5_LINKS=true \
  --dart-define=INRANGE_DIAG=true \
  --dart-define=INRANGE_DIAG_RUN_SECRET="$INRANGE_DIAG_RUN_SECRET"
APP="build/ios/iphoneos/Runner.app"
echo "artifact: $APP"
echo "bundle id: $(plutil -extract CFBundleIdentifier raw "$APP/Info.plist")"
echo "SHA-256(Runner): $(shasum -a 256 "$APP/Runner" | awk '{print $1}')"
# Fingerprint only — NOT the secret value. Fleet devices sharing the secret show
# the same fingerprint; the value stays out of build output and the manifest.
echo "diag run-secret fingerprint (sha256[:12], NOT the value): $RUN_SECRET_FP"
