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
  if env PATH="$TMP/bin:$PATH" "$@" bash "$GATE" "$SHA" "$TMP/evidence" >/dev/null 2>&1; then ok "$label"; else bad "$label (expected PASS)"; fi
}
expect_fail() {
  local label="$1"; shift
  if env PATH="$TMP/bin:$PATH" "$@" bash "$GATE" "$SHA" "$TMP/evidence" >/dev/null 2>&1; then bad "$label (expected FAIL)"; else ok "$label"; fi
}

expect_pass "55/105 exact sets + anchors accepted"
find "$TMP/evidence" -type f -name 'runner.sanitized.log' -print -quit | grep -q . \
  && find "$TMP/evidence" -type f -name 'diag.sanitized.log' -print -quit | grep -q . \
  && find "$TMP/evidence" -type f -name 'manifest.txt' -print -quit | grep -q . \
  && ok "sanitized logs + hash manifest retained" \
  || bad "sanitized logs + hash manifest retained"
MANIFEST="$(find "$TMP/evidence" -type f -name manifest.txt -print -quit)"
EVIDENCE_DIR="$(dirname "$MANIFEST")"
RUNNER_HASH="$(shasum -a 256 "$EVIDENCE_DIR/runner.sanitized.log" | awk '{print $1}')"
DIAG_HASH="$(shasum -a 256 "$EVIDENCE_DIR/diag.sanitized.log" | awk '{print $1}')"
grep -Fxq "runner_sanitized_sha256=$RUNNER_HASH" "$MANIFEST" \
  && grep -Fxq "diag_sanitized_sha256=$DIAG_HASH" "$MANIFEST" \
  && ok "retained manifest hashes recompute" \
  || bad "retained manifest hashes recompute"
if find "$TMP/evidence" \( -name '*.xcresult' -o -name 'runner.log' -o -name 'diag.log' \) \
  -print -quit | grep -q .; then
  bad "raw logs and result bundles removed"
else
  ok "raw logs and result bundles removed"
fi
expect_fail "stale 54 Runner set rejected" FAKE_RUNNER_COUNT=54
expect_fail "stale 103 diagnostic set rejected" FAKE_DIAG_COUNT=103
expect_fail "controlling Runner skip rejected" FAKE_CONTROLLING_SKIP_SCHEME=Runner
expect_fail "controlling diagnostic skip rejected" FAKE_CONTROLLING_SKIP_SCHEME=diag
expect_fail "missing Runner anchor rejected" FAKE_MISSING_ANCHOR_SCHEME=Runner
expect_fail "missing diagnostic anchor rejected" FAKE_MISSING_ANCHOR_SCHEME=diag
if env PATH="$TMP/bin:$PATH" bash "$GATE" \
  0000000000000000000000000000000000000000 "$TMP/evidence" >/dev/null 2>&1; then
  bad "wrong source SHA rejected before xcodebuild (expected FAIL)"
else
  ok "wrong source SHA rejected before xcodebuild"
fi
FOREIGN_REPO="$TMP/foreign-repo"
mkdir -p "$FOREIGN_REPO"
git -C "$FOREIGN_REPO" init -q
git -C "$FOREIGN_REPO" config user.email fixture@example.invalid
git -C "$FOREIGN_REPO" config user.name fixture
printf 'foreign\n' > "$FOREIGN_REPO/fixture.txt"
git -C "$FOREIGN_REPO" add fixture.txt
git -C "$FOREIGN_REPO" commit -qm fixture
FOREIGN_SHA="$(git -C "$FOREIGN_REPO" rev-parse HEAD)"
if env PATH="$TMP/bin:$PATH" GIT_DIR="$FOREIGN_REPO/.git" \
  GIT_WORK_TREE="$FOREIGN_REPO" bash "$GATE" "$FOREIGN_SHA" \
  "$TMP/evidence" >/dev/null 2>&1; then
  bad "ambient Git plumbing cannot stamp foreign SHA (expected FAIL)"
else
  ok "ambient Git plumbing cannot stamp foreign SHA"
fi
mkdir -p "$TMP/real-evidence-root"
ln -s "$TMP/real-evidence-root" "$TMP/evidence-root-link"
if env PATH="$TMP/bin:$PATH" bash "$GATE" "$SHA" \
  "$TMP/evidence-root-link" >/dev/null 2>&1; then
  bad "symlink evidence root rejected (expected FAIL)"
else
  ok "symlink evidence root rejected"
fi
mkdir -p "$TMP/real-parent"
ln -s "$TMP/real-parent" "$TMP/evidence-parent-link"
if env PATH="$TMP/bin:$PATH" bash "$GATE" "$SHA" \
  "$TMP/evidence-parent-link/nested" >/dev/null 2>&1; then
  bad "symlinked evidence parent rejected (expected FAIL)"
else
  ok "symlinked evidence parent rejected"
fi

printf '%s\n' '----'
if [ "$FAILS" -eq 0 ]; then
  echo "ALL ARTIFACT-NATIVE-GATE TESTS PASSED"
else
  echo "$FAILS ARTIFACT-NATIVE-GATE TEST(S) FAILED"
  exit 1
fi
