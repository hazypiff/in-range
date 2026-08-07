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
  local label="$1" repo="$2" sha="$3" mode="${4:-generated-ok}"
  if bash "$CHECK" "$repo" "$sha" "$mode" >/dev/null 2>&1; then ok "$label"; else bad "$label (expected PASS)"; fi
}
expect_fail() {
  local label="$1" repo="$2" sha="$3" mode="${4:-generated-ok}"
  if bash "$CHECK" "$repo" "$sha" "$mode" >/dev/null 2>&1; then bad "$label (expected FAIL)"; else ok "$label"; fi
}

git init -q "$SRC"
git -C "$SRC" config user.name fixture
git -C "$SRC" config user.email fixture@example.invalid
printf '.env\nbuild/\n' > "$SRC/.gitignore"
printf 'tracked\n' > "$SRC/tracked.txt"
printf 'config-hidden.txt\n' > "$SRC/excludes.txt"
mkdir -p "$SRC/scripts"
cp "$CHECK" "$SRC/scripts/check_artifact_build_context.sh"
cp "$BUILDER" "$SRC/scripts/build_diag_artifact.sh"
git -C "$SRC" add .gitignore tracked.txt excludes.txt scripts
git -C "$SRC" commit -qm initial
SHA="$(git -C "$SRC" rev-parse HEAD)"

expect_fail "attached primary checkout rejected" "$SRC" "$SHA"
git -C "$SRC" checkout -q --detach
expect_fail "detached primary checkout is not a separate worktree" "$SRC" "$SHA"

git -C "$SRC" worktree add -q --detach "$WT" "$SHA"
expect_pass "clean linked detached worktree accepted" "$WT" "$SHA"
expect_pass "fresh worktree accepted by inputs-only mode" "$WT" "$SHA" inputs-only
expect_fail "unknown cleanliness mode rejected" "$WT" "$SHA" unknown
expect_fail "wrong frozen SHA rejected" "$WT" "0000000000000000000000000000000000000000"

printf 'changed\n' >> "$WT/tracked.txt"
expect_fail "tracked modification rejected" "$WT" "$SHA"
git -C "$WT" restore tracked.txt

git -C "$WT" update-index --assume-unchanged tracked.txt
printf 'hidden tracked change\n' > "$WT/tracked.txt"
expect_fail "assume-unchanged cannot hide modified tracked bytes" "$WT" "$SHA"
git -C "$WT" update-index --no-assume-unchanged tracked.txt
git -C "$WT" restore tracked.txt

git -C "$WT" update-index --skip-worktree tracked.txt
printf 'hidden sparse change\n' > "$WT/tracked.txt"
expect_fail "skip-worktree cannot hide modified tracked bytes" "$WT" "$SHA"
git -C "$WT" update-index --no-skip-worktree tracked.txt
git -C "$WT" restore tracked.txt

printf 'untracked\n' > "$WT/untracked.txt"
expect_fail "non-ignored untracked file rejected" "$WT" "$SHA"
rm -f "$WT/untracked.txt"

printf 'hidden by ambient config\n' > "$WT/config-hidden.txt"
if env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.excludesFile \
  GIT_CONFIG_VALUE_0="$WT/excludes.txt" \
  bash "$CHECK" "$WT" "$SHA" >/dev/null 2>&1; then
  bad "ambient core.excludesFile cannot hide an untracked file (expected FAIL)"
else
  ok "ambient core.excludesFile cannot hide an untracked file"
fi
rm -f "$WT/config-hidden.txt"

printf 'info-hidden.txt\n' >> "$SRC/.git/info/exclude"
printf 'hidden by info exclude\n' > "$WT/info-hidden.txt"
expect_fail "mutable info/exclude cannot hide an untracked file" "$WT" "$SHA"
rm -f "$WT/info-hidden.txt"

mkdir -p "$WT/untracked-ignore"
printf '*\n' > "$WT/untracked-ignore/.gitignore"
printf 'hidden by untracked ignore\n' > "$WT/untracked-ignore/payload.txt"
expect_fail "an untracked .gitignore cannot hide itself and a payload" "$WT" "$SHA"
rm -rf "$WT/untracked-ignore"

printf 'approved ignored input\n' > "$WT/.env"
expect_pass "ignored environment input does not dirty Git provenance" "$WT" "$SHA"
expect_pass "regular .env is the sole approved pre-build input" "$WT" "$SHA" inputs-only
rm -f "$WT/.env"

printf 'approved environment input\n' > "$TMP/env-input"
ln -s "$TMP/env-input" "$WT/.env"
expect_fail "symlinked .env is not an approved pre-build input" "$WT" "$SHA" inputs-only
rm -f "$WT/.env"

mkdir -p "$WT/build"
printf 'stale generated input\n' > "$WT/build/stale.bin"
expect_pass "repo-ignored generated output is allowed after gates" "$WT" "$SHA" generated-ok
expect_fail "repo-ignored generated output is forbidden before gates" "$WT" "$SHA" inputs-only
rm -rf "$WT/build"

# A same-SHA foreign Git environment can satisfy a child context check while
# still poisoning later build tools in the parent shell. The builder must clear
# every plumbing variable before deriving SOURCE_SHA or invoking Flutter.
mkdir -p "$TMP/bin"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'if env | grep -q "^GIT_[A-Za-z0-9_]*="; then' \
  '  printf poisoned > "$ARTIFACT_ENV_MARKER"' \
  '  exit 41' \
  'fi' \
  'printf clean > "$ARTIFACT_ENV_MARKER"' \
  'exit 42' > "$TMP/bin/flutter"
chmod 700 "$TMP/bin/flutter"
MARKER="$TMP/builder-env-marker"
VALID_SECRET="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
mkdir -p "$WT/build"
printf 'preexisting ignored input\n' > "$WT/build/preexisting.bin"
if env PATH="$TMP/bin:$PATH" ARTIFACT_ENV_MARKER="$MARKER" \
  bash "$WT/scripts/build_diag_artifact.sh" >/dev/null 2>&1; then
  bad "builder rejects preexisting ignored build input (expected nonzero)"
elif [ -e "$MARKER" ]; then
  bad "builder rejects preexisting ignored build input before Flutter"
else
  ok "builder rejects preexisting ignored build input before Flutter"
fi
rm -rf "$WT/build"
rm -f "$MARKER"
BAD_NEWLINE_SECRET="$VALID_SECRET"$'\n''not-hex'
if env PATH="$TMP/bin:$PATH" ARTIFACT_ENV_MARKER="$MARKER" \
  INRANGE_DIAG_RUN_SECRET="$BAD_NEWLINE_SECRET" \
  bash "$WT/scripts/build_diag_artifact.sh" >/dev/null 2>&1; then
  bad "builder rejects a newline-tailed run secret (expected nonzero)"
elif [ -e "$MARKER" ]; then
  bad "builder rejects a newline-tailed run secret before Flutter"
else
  ok "builder rejects a newline-tailed run secret before Flutter"
fi
rm -f "$MARKER"
if env PATH="$TMP/bin:$PATH" ARTIFACT_ENV_MARKER="$MARKER" \
  INRANGE_DIAG_RUN_SECRET="${VALID_SECRET}a" \
  bash "$WT/scripts/build_diag_artifact.sh" >/dev/null 2>&1; then
  bad "builder rejects an odd-length run secret (expected nonzero)"
elif [ -e "$MARKER" ]; then
  bad "builder rejects an odd-length run secret before Flutter"
else
  ok "builder rejects an odd-length run secret before Flutter"
fi
rm -f "$MARKER"
if env PATH="$TMP/bin:$PATH" ARTIFACT_ENV_MARKER="$MARKER" \
  INRANGE_DIAG_RUN_SECRET="$VALID_SECRET" \
  GIT_DIR="$SRC/.git" GIT_WORK_TREE="$SRC" \
  GIT_COMMON_DIR="$SRC/.git" GIT_INDEX_FILE="$SRC/.git/index" \
  GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.excludesFile \
  GIT_CONFIG_VALUE_0="$WT/excludes.txt" \
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
