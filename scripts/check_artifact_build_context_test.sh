#!/usr/bin/env bash
# Red/green harness for the signed-artifact provenance gate. Uses only synthetic
# temporary repositories and never prints their machine-local paths.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/check_artifact_build_context.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SRC="$TMP/source"
WT="$TMP/linked-detached"
WT_BRANCH="$TMP/linked-branch"
FAILS=0

ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; FAILS=$((FAILS + 1)); }
expect_pass() {
  local label="$1" repo="$2" sha="$3"
  if bash "$CHECK" "$repo" "$sha" >/dev/null 2>&1; then ok "$label"; else bad "$label (expected PASS)"; fi
}
expect_fail() {
  local label="$1" repo="$2" sha="$3"
  if bash "$CHECK" "$repo" "$sha" >/dev/null 2>&1; then bad "$label (expected FAIL)"; else ok "$label"; fi
}

git init -q "$SRC"
git -C "$SRC" config user.name fixture
git -C "$SRC" config user.email fixture@example.invalid
printf '.env\n' > "$SRC/.gitignore"
printf 'tracked\n' > "$SRC/tracked.txt"
git -C "$SRC" add .gitignore tracked.txt
git -C "$SRC" commit -qm initial
SHA="$(git -C "$SRC" rev-parse HEAD)"

expect_fail "attached primary checkout rejected" "$SRC" "$SHA"
git -C "$SRC" checkout -q --detach
expect_fail "detached primary checkout is not a separate worktree" "$SRC" "$SHA"

git -C "$SRC" worktree add -q --detach "$WT" "$SHA"
expect_pass "clean linked detached worktree accepted" "$WT" "$SHA"
expect_fail "wrong frozen SHA rejected" "$WT" "0000000000000000000000000000000000000000"

printf 'changed\n' >> "$WT/tracked.txt"
expect_fail "tracked modification rejected" "$WT" "$SHA"
git -C "$WT" restore tracked.txt

printf 'untracked\n' > "$WT/untracked.txt"
expect_fail "non-ignored untracked file rejected" "$WT" "$SHA"
rm -f "$WT/untracked.txt"

printf 'approved ignored input\n' > "$WT/.env"
expect_pass "ignored environment input does not dirty Git provenance" "$WT" "$SHA"
rm -f "$WT/.env"

git -C "$SRC" worktree add -q -b fixture-branch "$WT_BRANCH" "$SHA"
expect_fail "linked but branch-attached worktree rejected" "$WT_BRANCH" "$SHA"

printf '%s\n' '----'
if [ "$FAILS" -eq 0 ]; then
  echo "ALL ARTIFACT-CONTEXT TESTS PASSED"
else
  echo "$FAILS ARTIFACT-CONTEXT TEST(S) FAILED"
  exit 1
fi
