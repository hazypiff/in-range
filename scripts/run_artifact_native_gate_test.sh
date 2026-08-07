#!/usr/bin/env bash
# Red/green fixture for the artifact builder's native exact-set gate.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="$HERE/run_artifact_native_gate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cp "$HERE/fixtures/fake_artifact_xcodebuild.sh" "$TMP/bin/xcodebuild"
chmod 700 "$TMP/bin/xcodebuild"
SHA="$(git -C "$HERE/.." rev-parse HEAD)"
FAILS=0

ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; FAILS=$((FAILS + 1)); }
expect_pass() {
  local label="$1"; shift
  if env PATH="$TMP/bin:$PATH" "$@" bash "$GATE" "$SHA" >/dev/null 2>&1; then ok "$label"; else bad "$label (expected PASS)"; fi
}
expect_fail() {
  local label="$1"; shift
  if env PATH="$TMP/bin:$PATH" "$@" bash "$GATE" "$SHA" >/dev/null 2>&1; then bad "$label (expected FAIL)"; else ok "$label"; fi
}

expect_pass "55/105 exact sets + anchors accepted"
expect_fail "stale 103 diagnostic set rejected" FAKE_DIAG_COUNT=103
expect_fail "controlling diagnostic skip rejected" FAKE_CONTROLLING_SKIP=1
if env PATH="$TMP/bin:$PATH" bash "$GATE" \
  0000000000000000000000000000000000000000 >/dev/null 2>&1; then
  bad "wrong source SHA rejected before xcodebuild (expected FAIL)"
else
  ok "wrong source SHA rejected before xcodebuild"
fi

printf '%s\n' '----'
if [ "$FAILS" -eq 0 ]; then
  echo "ALL ARTIFACT-NATIVE-GATE TESTS PASSED"
else
  echo "$FAILS ARTIFACT-NATIVE-GATE TEST(S) FAILED"
  exit 1
fi
