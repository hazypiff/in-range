#!/usr/bin/env bash
# Red/green harness for the signed-artifact provenance gate. Uses only synthetic
# temporary repositories and never prints their machine-local paths.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/check_artifact_build_context.sh"
BUILDER="$HERE/build_diag_artifact.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SRC="$TMP/source"
WT="$TMP/linked-detached"
WT_BRANCH="$TMP/linked-branch"
DECEPTIVE="$TMP/worktrees/deceptive-primary"
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
mkdir -p "$SRC/scripts"
cp "$CHECK" "$SRC/scripts/check_artifact_build_context.sh"
cp "$BUILDER" "$SRC/scripts/build_diag_artifact.sh"
git -C "$SRC" add .gitignore tracked.txt scripts
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

# A same-SHA foreign Git environment can satisfy a child context check while
# still poisoning later build tools in the parent shell. The builder must clear
# every plumbing variable before deriving SOURCE_SHA or invoking Flutter.
mkdir -p "$TMP/bin"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'if [ -n "${GIT_DIR+x}" ] || [ -n "${GIT_WORK_TREE+x}" ] || [ -n "${GIT_COMMON_DIR+x}" ] || [ -n "${GIT_INDEX_FILE+x}" ]; then' \
  '  printf poisoned > "$ARTIFACT_ENV_MARKER"' \
  '  exit 41' \
  'fi' \
  'printf clean > "$ARTIFACT_ENV_MARKER"' \
  'exit 42' > "$TMP/bin/flutter"
chmod 700 "$TMP/bin/flutter"
MARKER="$TMP/builder-env-marker"
if env PATH="$TMP/bin:$PATH" ARTIFACT_ENV_MARKER="$MARKER" \
  GIT_DIR="$SRC/.git" GIT_WORK_TREE="$SRC" \
  GIT_COMMON_DIR="$SRC/.git" GIT_INDEX_FILE="$SRC/.git/index" \
  bash "$WT/scripts/build_diag_artifact.sh" >/dev/null 2>&1; then
  bad "builder stopped at the synthetic Flutter boundary (expected nonzero)"
elif [ "$(cat "$MARKER" 2>/dev/null || true)" = clean ]; then
  ok "builder clears ambient Git plumbing before later build tools"
else
  bad "builder clears ambient Git plumbing before later build tools"
fi

git -C "$SRC" worktree add -q -b fixture-branch "$WT_BRANCH" "$SHA"
expect_fail "linked but branch-attached worktree rejected" "$WT_BRANCH" "$SHA"

# Red mutation from the Opus attack: a primary repository whose ordinary path
# happens to contain a component named "worktrees" must not impersonate a linked
# worktree, even when the checker is invoked from a nested directory.
git init -q "$DECEPTIVE"
git -C "$DECEPTIVE" config user.name fixture
git -C "$DECEPTIVE" config user.email fixture@example.invalid
printf 'tracked\n' > "$DECEPTIVE/tracked.txt"
git -C "$DECEPTIVE" add tracked.txt
git -C "$DECEPTIVE" commit -qm initial
DECEPTIVE_SHA="$(git -C "$DECEPTIVE" rev-parse HEAD)"
git -C "$DECEPTIVE" checkout -q --detach
mkdir -p "$DECEPTIVE/nested"
expect_fail "path named worktrees cannot forge linked-worktree status" \
  "$DECEPTIVE/nested" "$DECEPTIVE_SHA"
if env GIT_DIR="$DECEPTIVE/.git" GIT_WORK_TREE="$DECEPTIVE" \
  bash "$CHECK" "$DECEPTIVE/nested" "$DECEPTIVE_SHA" >/dev/null 2>&1; then
  bad "ambient Git-dir override cannot forge linked-worktree status (expected FAIL)"
else
  ok "ambient Git-dir override cannot forge linked-worktree status"
fi

printf '%s\n' '----'
if [ "$FAILS" -eq 0 ]; then
  echo "ALL ARTIFACT-CONTEXT TESTS PASSED"
else
  echo "$FAILS ARTIFACT-CONTEXT TEST(S) FAILED"
  exit 1
fi
