#!/usr/bin/env bash
# Fail closed unless an artifact build runs from a clean, linked, detached Git
# worktree at the expected source SHA. File names are deliberately never printed:
# an untracked path can itself contain a private device or host identifier.
set -euo pipefail

REPO="${1:?repository path required}"
EXPECTED_SHA="${2:?expected source SHA required}"
MODE="${3:-generated-ok}"
fail() { echo "ARTIFACT CONTEXT FAIL: $1" >&2; exit 1; }

case "$MODE" in
  inputs-only|generated-ok) ;;
  *) fail "unknown cleanliness mode" ;;
esac

# Repository identity and ignore policy must come from the supplied worktree,
# never from ambient Git plumbing/config variables inherited from an operator
# shell or wrapper.
while IFS= read -r git_env_name; do
  unset "$git_env_name"
done < <(compgen -A variable GIT_ || true)

cd "$REPO" 2>/dev/null || fail "repository is inaccessible"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || fail "not inside a Git worktree"
WORKTREE_ROOT="$(pwd -P)" || fail "cannot resolve repository path"
TOPLEVEL_RAW="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || fail "cannot resolve worktree root"
TOPLEVEL="$(cd -P "$TOPLEVEL_RAW" 2>/dev/null && pwd -P)" \
  || fail "cannot canonicalize worktree root"
[ "$WORKTREE_ROOT" = "$TOPLEVEL" ] \
  || fail "repository path is not the worktree root"

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
RAW_OTHERS_FILE="$(mktemp)"
UNTRACKED_FILE="$(mktemp)"
INDEX_FLAGS_FILE="$(mktemp)"
IRREGULAR_FILE="$(mktemp)"
EMPTY_DIR_FILE="$(mktemp)"
trap 'rm -f "$STATUS_FILE" "$RAW_OTHERS_FILE" "$UNTRACKED_FILE" "$INDEX_FLAGS_FILE" "$IRREGULAR_FILE" "$EMPTY_DIR_FILE"' EXIT

# assume-unchanged and skip-worktree can hide modified tracked bytes from status.
# A release artifact worktree must use an ordinary, fully materialized index.
git ls-files -v -z > "$INDEX_FLAGS_FILE" \
  || fail "cannot inspect index flags"
while IFS= read -r -d '' indexed_entry; do
  case "$indexed_entry" in
    H\ *) ;;
    *) fail "a tracked path carries a nonstandard index flag" ;;
  esac
done < "$INDEX_FLAGS_FILE"

# Inspect tracked/index state separately. Command-line settings disable local
# performance helpers that could return a stale answer.
git -c core.fsmonitor=false -c core.untrackedCache=false \
  -c core.fileMode=true status \
  --porcelain=v1 -z --untracked-files=no > "$STATUS_FILE" \
  || fail "cannot inspect tracked worktree state"
[ ! -s "$STATUS_FILE" ] \
  || fail "tracked changes are present"

# Git does not enumerate FIFOs, sockets, or device nodes as untracked paths.
# Inspect the filesystem directly so those cannot become invisible build inputs.
if ! find . -path './.git' -prune -o \
  ! -type d ! -type f ! -type l -print > "$IRREGULAR_FILE" 2>/dev/null; then
  fail "cannot inspect filesystem entry types"
fi
[ ! -s "$IRREGULAR_FILE" ] \
  || fail "an irregular filesystem entry is present"

# Only committed per-directory .gitignore files define the permitted ignored
# build/environment surface. Do not honor ambient core.excludesFile or the
# mutable common .git/info/exclude. First reject an untracked .gitignore even if
# it tries to hide itself, then enumerate non-ignored untracked files using the
# repository rules alone.
git ls-files --others -z > "$RAW_OTHERS_FILE" \
  || fail "cannot inspect untracked ignore controls"
if [ "$MODE" = inputs-only ]; then
  # Git cannot represent empty directories either. Before generation, even an
  # empty extra directory violates the allowlist of tracked files plus .env.
  if ! find . -path './.git' -prune -o -type d -empty -print \
    > "$EMPTY_DIR_FILE" 2>/dev/null; then
    fail "cannot inspect pre-build directories"
  fi
  [ ! -s "$EMPTY_DIR_FILE" ] \
    || fail "an unapproved pre-build directory is present"
  while IFS= read -r -d '' untracked_path; do
    case "$untracked_path" in
      .env)
        [ -f .env ] && [ ! -L .env ] \
          || fail "approved environment input is not a regular local file"
        ;;
      *)
        fail "an unapproved pre-build input is present"
        ;;
    esac
  done < "$RAW_OTHERS_FILE"
  echo "OK: clean linked detached worktree at $ACTUAL_SHA"
  exit 0
fi

while IFS= read -r -d '' untracked_path; do
  case "$untracked_path" in
    .gitignore|*/.gitignore)
      fail "an untracked ignore-control file is present"
      ;;
  esac
done < "$RAW_OTHERS_FILE"

git ls-files --others -z --exclude-per-directory=.gitignore \
  > "$UNTRACKED_FILE" \
  || fail "cannot inspect non-ignored untracked files"
[ ! -s "$UNTRACKED_FILE" ] \
  || fail "non-ignored untracked files are present"

echo "OK: clean linked detached worktree at $ACTUAL_SHA"
