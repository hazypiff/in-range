#!/usr/bin/env bash
# Synthetic xcodebuild used only by run_artifact_native_gate_test.sh.
set -euo pipefail

SCHEME=""
PREV=""
for arg in "$@"; do
  if [ "$PREV" = "-scheme" ]; then SCHEME="$arg"; fi
  PREV="$arg"
done
ARGS=" $* "
case "$ARGS" in
  *" -parallel-testing-enabled NO "*) ;;
  *) echo "fake xcodebuild: serial flags missing" >&2; exit 2 ;;
esac
case "$ARGS" in
  *" -maximum-concurrent-test-simulator-destinations 1 "*) ;;
  *) echo "fake xcodebuild: simulator concurrency cap missing" >&2; exit 2 ;;
esac

case "$SCHEME" in
  Runner) COUNT="${FAKE_RUNNER_COUNT:-55}"; ANCHOR=testBuildFlavorMatchesScheme ;;
  diag) COUNT="${FAKE_DIAG_COUNT:-105}"; ANCHOR=testHandleUsesProvisionedRunSecret ;;
  *) echo "fake xcodebuild: unknown scheme" >&2; exit 2 ;;
esac

i=1
while [ "$i" -le "$COUNT" ]; do
  NAME="testFixture$i"
  if [ "$i" -eq 1 ] && [ "${FAKE_MISSING_ANCHOR_SCHEME:-}" != "$SCHEME" ]; then
    NAME="$ANCHOR"
  fi
  printf "Test Case '-[RunnerTests.Fixture %s]' passed (0.00 seconds).\n" "$NAME"
  i=$((i + 1))
done
if [ "${FAKE_CONTROLLING_SKIP_SCHEME:-}" = "$SCHEME" ]; then
  printf "Test Case '-[RunnerTests.Fixture testSkipped]' skipped (0.00 seconds).\n"
fi
printf '\t Executed %s tests, with 0 failures (0 unexpected) in 0.0 (0.0) seconds\n' "$COUNT"
printf '%s\n' '** TEST SUCCEEDED **'
