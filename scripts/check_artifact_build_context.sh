#!/usr/bin/env bash
# Fail closed unless an artifact build runs from a clean, linked, detached Git
# worktree at the expected source SHA. File names are deliberately never printed:
# an untracked path can itself contain a private device or host identifier.
set -euo pipefail

REPO="${1:?repository path required}"
EXPECTED_SHA="${2:?expected source SHA required}"
fail() { echo "ARTIFACT CONTEXT FAIL: $1" >&2; exit 1; }

cd "$REPO" 2>/dev/null || fail "repository is inaccessible"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || fail "not inside a Git worktree"

ACTUAL_SHA="$(git rev-parse HEAD 2>/dev/null)" \
  || fail "cannot resolve HEAD"
[ "$ACTUAL_SHA" = "$EXPECTED_SHA" ] \
  || fail "HEAD does not match the frozen source SHA"

# A detached HEAD is necessary but not sufficient: the controlling directive
# requires a separate linked worktree, not the ordinary checkout detached in
# place. Linked worktree gitdirs live below the common repository's worktrees/.
if git symbolic-ref -q HEAD >/dev/null 2>&1; then
  fail "HEAD is attached to a branch"
fi
GIT_DIR="$(git rev-parse --git-dir 2>/dev/null)" \
  || fail "cannot resolve the worktree gitdir"
case "$GIT_DIR" in
  */worktrees/*) ;;
  *) fail "checkout is not a separate linked worktree" ;;
esac

STATUS_FILE="$(mktemp)"
trap 'rm -f "$STATUS_FILE"' EXIT
git status --porcelain=v1 -z --untracked-files=all > "$STATUS_FILE" \
  || fail "cannot inspect worktree cleanliness"
[ ! -s "$STATUS_FILE" ] \
  || fail "tracked or non-ignored untracked changes are present"

echo "OK: clean linked detached worktree at $ACTUAL_SHA"
