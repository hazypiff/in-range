#!/usr/bin/env bash
# Phase 4: diagnostic artifact generation GATED ON TESTS. Produces the diag
# device app for hardware runs ONLY after the full test + isolation gates pass,
# and emits the artifact SHA-256 + build config for the evidence manifest.
set -euo pipefail
# Clear every caller-controlled Git override in the coordinator shell itself.
# Child provenance checks also clear these, but their environment changes cannot
# protect later Flutter/Xcode commands executed by this parent process.
while IFS= read -r git_env_name; do
  unset "$git_env_name"
done < <(compgen -A variable GIT_ || true)
# Canonicalize the trusted worktree root first. On macOS, temporary roots such
# as /var may themselves be system symlinks to /private/var; later evidence-path
# checks should inspect only the resulting physical path.
cd -P "$(dirname "$0")/.."
SOURCE_SHA="$(git rev-parse HEAD)"

# The final hardware artifact is admissible only when it comes from a separate,
# linked, detached worktree with no tracked or non-ignored untracked changes.
# Check both before any gate and immediately before the signed build so a test or
# build-setting generator cannot silently mutate the candidate in between.
bash scripts/check_artifact_build_context.sh "$PWD" "$SOURCE_SHA" inputs-only

echo "== gate 0: generate dependencies from the clean source tree =="
flutter pub get
flutter build ios --config-only --debug --no-codesign
(cd ios && pod install)

echo "== gate 1: flutter analyze + test =="
flutter analyze
flutter test

echo "== gate 2: native RunnerTests (both schemes) =="
bash scripts/run_artifact_native_gate.sh "$SOURCE_SHA" "$PWD/.artifact-evidence"

echo "== gate 3: release isolation (build-settings + final-binary) =="
bash scripts/check_release_isolation.sh
bash scripts/check_final_binary_isolation.sh

bash scripts/check_artifact_build_context.sh "$PWD" "$SOURCE_SHA" generated-ok

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
bash scripts/check_artifact_build_context.sh "$PWD" "$SOURCE_SHA" generated-ok
APP="build/ios/iphoneos/Runner.app"
echo "artifact: $APP"
echo "bundle id: $(plutil -extract CFBundleIdentifier raw "$APP/Info.plist")"
echo "SHA-256(Runner): $(shasum -a 256 "$APP/Runner" | awk '{print $1}')"
# Fingerprint only — NOT the secret value. Fleet devices sharing the secret show
# the same fingerprint; the value stays out of build output and the manifest.
echo "diag run-secret fingerprint (sha256[:12], NOT the value): $RUN_SECRET_FP"
