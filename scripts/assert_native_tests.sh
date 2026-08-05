#!/usr/bin/env bash
# Assert an xcodebuild native-test log meets the Wave A gate: TEST SUCCEEDED,
# ZERO controlling skips, discovered==passed (0 failures), a minimum passed
# count, and (optionally) that a NAMED test actually ran and passed. A bare
# `grep TEST SUCCEEDED` proves none of these (R6).
#
#   assert_native_tests.sh <log> <min-passed> [named-test]
#
# Supports both xcodebuild output formats:
#   old: "Test Case '-[Suite testX]' passed" + "Executed N tests, with M failures"
#   new: "Test case 'Suite.testX()' passed on 'Clone ...'"
set -uo pipefail
LOG="${1:?log path required}"; MIN="${2:?min passed count required}"
NAMED="${3:-}"
fail() { echo "ASSERT FAIL: $1" >&2; exit 1; }

[ -f "$LOG" ] || fail "log missing: $LOG"
grep -q '\*\* TEST SUCCEEDED \*\*' "$LOG" || fail "no '** TEST SUCCEEDED **' in $LOG"

# ZERO controlling skips (either output format).
if grep -Eq "Test [Cc]ase '.*' skipped" "$LOG"; then
  grep -E "Test [Cc]ase '.*' skipped" "$LOG" >&2
  fail "controlling skip(s) present in $LOG"
fi

# Discovered == passed. Prefer the old "Executed N tests, with M failures"
# summary; fall back to counting per-test result lines (new Xcode format).
SUMMARY="$(grep -Eo 'Executed [0-9]+ tests?, with [0-9]+ failures' "$LOG" | tail -1)"
if [ -n "$SUMMARY" ]; then
  N="$(printf '%s' "$SUMMARY" | grep -Eo 'Executed [0-9]+' | grep -Eo '[0-9]+')"
  FAILS="$(printf '%s' "$SUMMARY" | grep -Eo 'with [0-9]+ failures' | grep -Eo '[0-9]+')"
else
  N="$(grep -Ec "Test [Cc]ase '.*' passed" "$LOG" || true)"
  FAILS="$(grep -Ec "Test [Cc]ase '.*' failed" "$LOG" || true)"
fi
[ "${FAILS:-1}" -eq 0 ] || fail "non-zero failures ($FAILS) in $LOG"
[ "${N:-0}" -ge "$MIN" ] || fail "passed $N < expected minimum $MIN in $LOG"

# The named test actually ran AND passed (not absent-because-skipped).
if [ -n "$NAMED" ]; then
  grep -Eq "Test [Cc]ase '.*${NAMED}.*' passed" "$LOG" \
    || fail "named test '$NAMED' did not run and pass"
fi

echo "OK: $LOG — passed $N, 0 failures, 0 controlling skips${NAMED:+, '$NAMED' ran+passed}"
