#!/usr/bin/env bash
# Run the two native suites used to authorize a signed diagnostic artifact and
# enforce the exact discovered sets, zero controlling skips, named anchors, and
# source-SHA provenance. Raw Xcode logs live only in protected temporary storage.
set -euo pipefail
umask 077

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_SHA="${1:?frozen source SHA required}"
[ "$(git -C "$ROOT" rev-parse HEAD)" = "$SOURCE_SHA" ] || {
  echo "ARTIFACT NATIVE GATE FAIL: HEAD changed before native tests" >&2
  exit 1
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SIM='platform=iOS Simulator,name=iPhone 17'

run_scheme() {
  local scheme="$1" configuration="$2" log="$3" result="$4"
  {
    printf '# source_sha: %s\n' "$SOURCE_SHA"
    xcodebuild test \
      -workspace ios/Runner.xcworkspace \
      -scheme "$scheme" \
      -configuration "$configuration" \
      -resultBundlePath "$result" \
      -destination "$SIM" \
      -only-testing:RunnerTests \
      -parallel-testing-enabled NO \
      -maximum-concurrent-test-simulator-destinations 1 \
      CODE_SIGNING_ALLOWED=NO
  } | tee "$log" >/dev/null
}

cd "$ROOT"
run_scheme Runner Debug "$TMP/runner.log" "$TMP/RunnerResult.xcresult"
bash scripts/assert_native_tests.sh "$TMP/runner.log" =55 \
  testBuildFlavorMatchesScheme "$SOURCE_SHA"

run_scheme diag Debug-diag "$TMP/diag.log" "$TMP/DiagResult.xcresult"
bash scripts/assert_native_tests.sh "$TMP/diag.log" =105 \
  testHandleUsesProvisionedRunSecret "$SOURCE_SHA"

echo "OK: signed-artifact native gate passed at $SOURCE_SHA (Runner=55, diag=105)"
