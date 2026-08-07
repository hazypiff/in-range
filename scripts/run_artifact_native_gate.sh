#!/usr/bin/env bash
# Run the two native suites used to authorize a signed diagnostic artifact and
# enforce the exact discovered sets, zero controlling skips, named anchors, and
# source-SHA provenance. Raw Xcode logs live only in protected temporary storage
# and are deleted; privacy-sanitized derivatives + hashes are retained for the
# replacement artifact manifest and later exact-SHA panel verification.
set -euo pipefail
umask 077

# Ambient Git plumbing can redirect even `git -C` to a foreign repository.
# The artifact gate must bind provenance to this checkout, never to its caller's
# environment.
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_SHA="${1:?frozen source SHA required}"
EVIDENCE_ROOT="${2:-$ROOT/.artifact-evidence}"
[ "$(git -C "$ROOT" rev-parse HEAD)" = "$SOURCE_SHA" ] || {
  echo "ARTIFACT NATIVE GATE FAIL: HEAD changed before native tests" >&2
  exit 1
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SIM='platform=iOS Simulator,name=iPhone 17'
SANITIZER="$ROOT/docs/research/2026-08-01-hardening/sanitize_native_log.sh"

case "$EVIDENCE_ROOT" in
  /*) ;;
  *) EVIDENCE_ROOT="$ROOT/$EVIDENCE_ROOT" ;;
esac

# Reject a symlink in any path component, not just a symlink at the leaf. This
# keeps retained evidence inside the exact directory named by the manifest.
assert_no_symlink_component() {
  local path="$1" component current=""
  local -a components
  IFS='/' read -r -a components <<< "$path"
  for component in "${components[@]}"; do
    [ -n "$component" ] || continue
    [ "$component" != "." ] || continue
    [ "$component" != ".." ] || {
      echo "ARTIFACT NATIVE GATE FAIL: evidence root contains '..'" >&2
      return 1
    }
    current="$current/$component"
    [ ! -L "$current" ] || {
      echo "ARTIFACT NATIVE GATE FAIL: evidence path contains a symlink" >&2
      return 1
    }
  done
}

assert_no_symlink_component "$EVIDENCE_ROOT"
mkdir -p "$EVIDENCE_ROOT"
assert_no_symlink_component "$EVIDENCE_ROOT"
EVIDENCE_DIR="$(mktemp -d "$EVIDENCE_ROOT/native-$SOURCE_SHA.XXXXXX")"
EVIDENCE_LABEL="$(basename "$EVIDENCE_DIR")"

run_scheme() {
  local scheme="$1" configuration="$2" log="$3" result="$4"
  {
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

sanitize_and_assert() {
  local raw="$1" clean="$2" label="$3" count="$4" anchor="$5"
  bash "$SANITIZER" "$raw" "$SOURCE_SHA" "$label" > "$clean"
  bash scripts/assert_native_tests.sh "$clean" "$count" "$anchor" "$SOURCE_SHA"
}

cd "$ROOT"
if ! run_scheme Runner Debug "$TMP/runner.log" "$TMP/RunnerResult.xcresult"; then
  [ ! -s "$TMP/runner.log" ] || bash "$SANITIZER" "$TMP/runner.log" \
    "$SOURCE_SHA" "Runner (Debug)" > "$EVIDENCE_DIR/runner.sanitized.log" || true
  echo "ARTIFACT NATIVE GATE FAIL: Runner xcodebuild failed; sanitized evidence retained in $EVIDENCE_LABEL" >&2
  exit 1
fi
sanitize_and_assert "$TMP/runner.log" "$EVIDENCE_DIR/runner.sanitized.log" \
  "Runner (Debug)" =55 testBuildFlavorMatchesScheme

if ! run_scheme diag Debug-diag "$TMP/diag.log" "$TMP/DiagResult.xcresult"; then
  [ ! -s "$TMP/diag.log" ] || bash "$SANITIZER" "$TMP/diag.log" \
    "$SOURCE_SHA" "diag (Debug-diag)" > "$EVIDENCE_DIR/diag.sanitized.log" || true
  echo "ARTIFACT NATIVE GATE FAIL: diag xcodebuild failed; sanitized evidence retained in $EVIDENCE_LABEL" >&2
  exit 1
fi
sanitize_and_assert "$TMP/diag.log" "$EVIDENCE_DIR/diag.sanitized.log" \
  "diag (Debug-diag)" =105 testHandleUsesProvisionedRunSecret

RUNNER_HASH="$(shasum -a 256 "$EVIDENCE_DIR/runner.sanitized.log" | awk '{print $1}')"
DIAG_HASH="$(shasum -a 256 "$EVIDENCE_DIR/diag.sanitized.log" | awk '{print $1}')"
{
  printf 'source_sha=%s\n' "$SOURCE_SHA"
  printf 'runner_count=55\nrunner_sanitized_sha256=%s\n' "$RUNNER_HASH"
  printf 'diag_count=105\ndiag_sanitized_sha256=%s\n' "$DIAG_HASH"
} > "$EVIDENCE_DIR/manifest.txt"

echo "OK: signed-artifact native gate passed at $SOURCE_SHA (Runner=55, diag=105)"
echo "OK: sanitized native evidence retained as $EVIDENCE_LABEL"
echo "runner sanitized sha256: $RUNNER_HASH"
echo "diag sanitized sha256: $DIAG_HASH"
