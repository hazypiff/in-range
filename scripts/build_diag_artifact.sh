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

# B3 fleet alignment: bake one shared W5-event run secret into the diagnostic
# build so HMAC handles align across devices and survive OS restoration. Match
# the native decoder's contract exactly and fail before any generator runs.
RUN_SECRET="${INRANGE_DIAG_RUN_SECRET:-}"
RUN_SECRET_LEN="${#RUN_SECRET}"
if [ "$RUN_SECRET_LEN" -lt 64 ] \
  || [ $((RUN_SECRET_LEN % 2)) -ne 0 ] \
  || [[ "$RUN_SECRET" == *[!0-9a-fA-F]* ]]; then
  echo "ERROR: set INRANGE_DIAG_RUN_SECRET to an even number of >= 64 HEX chars." >&2
  echo "       (native rejects malformed values, so the builder must fail first.)" >&2
  echo "       It is baked for fleet alignment; it is never generated or committed." >&2
  exit 1
fi

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
# The value is provided only through the environment and never printed. Emit a
# short fingerprint so the manifest can confirm fleet alignment without
# exposing the secret itself.
RUN_SECRET_FP=$(printf '%s' "$RUN_SECRET" | shasum -a 256 | cut -c1-12)
flutter build ios --flavor diag --release --dart-define-from-file=.env \
  --dart-define=INRANGE_W5_LINKS=true \
  --dart-define=INRANGE_DIAG=true \
  --dart-define=INRANGE_DIAG_RUN_SECRET="$RUN_SECRET"
bash scripts/check_artifact_build_context.sh "$PWD" "$SOURCE_SHA" generated-ok
APP="build/ios/iphoneos/Runner.app"
echo "artifact: $APP"
echo "bundle id: $(plutil -extract CFBundleIdentifier raw "$APP/Info.plist")"
echo "SHA-256(Runner): $(shasum -a 256 "$APP/Runner" | awk '{print $1}')"
# Fingerprint only — NOT the secret value. Fleet devices sharing the secret show
# the same fingerprint; the value stays out of build output and the manifest.
echo "diag run-secret fingerprint (sha256[:12], NOT the value): $RUN_SECRET_FP"
