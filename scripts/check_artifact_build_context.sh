#!/usr/bin/env bash
# Fail closed unless an artifact build runs from a clean, linked, detached Git
# worktree at the expected source SHA. File names are deliberately never printed:
# an untracked path can itself contain a private device or host identifier.
set -euo pipefail

REPO="${1:?repository path required}"
EXPECTED_SHA="${2:?expected source SHA required}"
fail() { echo "ARTIFACT CONTEXT FAIL: $1" >&2; exit 1; }

# Repository identity must come from the supplied worktree, never from ambient
# Git plumbing variables inherited from an operator shell or wrapper.
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE

cd "$REPO" 2>/dev/null || fail "repository is inaccessible"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || fail "not inside a Git worktree"

ACTUAL_SHA="$(git rev-parse HEAD 2>/dev/null)" \
  || fail "cannot resolve HEAD"
[ "$ACTUAL_SHA" = "$EXPECTED_SHA" ] \
  || fail "HEAD does not match the frozen source SHA"

# A detached HEAD is necessary but not sufficient: the controlling directive
# requires a separate linked worktree, not the ordinary checkout detached in
# place. Use Git's own absolute git-dir/common-dir relationship; path matching
# on a directory named "worktrees" can be forged by an ordinary checkout.
if git symbolic-ref -q HEAD >/dev/null 2>&1; then
  fail "HEAD is attached to a branch"
fi
GIT_DIR="$(git rev-parse --path-format=absolute --git-dir 2>/dev/null)" \
  || fail "cannot resolve the worktree gitdir"
COMMON_DIR="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
  || fail "cannot resolve the common gitdir"
[ "$GIT_DIR" != "$COMMON_DIR" ] \
  || fail "checkout is not a separate linked worktree"

STATUS_FILE="$(mktemp)"
trap 'rm -f "$STATUS_FILE"' EXIT
git status --porcelain=v1 -z --untracked-files=all > "$STATUS_FILE" \
  || fail "cannot inspect worktree cleanliness"
[ ! -s "$STATUS_FILE" ] \
  || fail "tracked or non-ignored untracked changes are present"

echo "OK: clean linked detached worktree at $ACTUAL_SHA"
