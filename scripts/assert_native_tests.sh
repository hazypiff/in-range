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

# Discovered == passed. Count the AUTHORITATIVE per-test result lines directly
# (works for both output formats); a summary is only trusted after it is
# RECONCILED against those counts. A prior version trusted "Executed N" blindly,
# so a log with one passed line but "Executed 70 tests" wrongly passed (codex A5).
PASSED_LINES="$(grep -Ec "Test [Cc]ase '.*' passed" "$LOG" || true)"
FAILED_LINES="$(grep -Ec "Test [Cc]ase '.*' failed" "$LOG" || true)"
[ "${FAILED_LINES:-1}" -eq 0 ] || fail "failed test result line(s) present ($FAILED_LINES) in $LOG"

# xcodebuild prints one "Executed N tests, with M failures" per suite AND a final
# aggregate (the outermost bundle) — so the GRAND TOTAL is the MAXIMUM N, never
# the sum (summing double-counts nested suites). Take the max N as discovered and
# require ANY summary line reporting failures to fail the gate. With 0 skips and 0
# failures, every discovered test must have produced a passed result line, or a
# bundle silently vanished / the summary was forged (codex A5 repro: 1 passed
# line but "Executed 70 tests" — 70 != 1 now fails).
DISCOVERED=0; HAVE_SUMMARY=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  HAVE_SUMMARY=1
  n="$(printf '%s' "$line" | grep -Eo 'Executed [0-9]+' | grep -Eo '[0-9]+')"
  m="$(printf '%s' "$line" | grep -Eo 'with [0-9]+ failures?' | grep -Eo '[0-9]+')"
  [ "${m:-0}" -eq 0 ] || fail "a summary line reports ${m} failure(s) in $LOG"
  [ "${n:-0}" -le "$DISCOVERED" ] || DISCOVERED="${n:-0}"   # keep the max (aggregate)
  # Match singular AND plural forms ("1 test, with 1 failure") so a real failing
  # run can never evade summary parsing on grammar alone (codex A5 re-review).
done < <(grep -Eo 'Executed [0-9]+ tests?, with [0-9]+ failures?' "$LOG")

if [ "$HAVE_SUMMARY" -eq 1 ]; then
  [ "$DISCOVERED" -eq "$PASSED_LINES" ] \
    || fail "discovered ($DISCOVERED) != passed result lines ($PASSED_LINES) in $LOG"
  N="$DISCOVERED"
else
  N="$PASSED_LINES"
fi
[ "${N:-0}" -ge "$MIN" ] || fail "passed $N < expected minimum $MIN in $LOG"

# The named test actually ran AND passed (not absent-because-skipped).
if [ -n "$NAMED" ]; then
  grep -Eq "Test [Cc]ase '.*${NAMED}.*' passed" "$LOG" \
    || fail "named test '$NAMED' did not run and pass"
fi

echo "OK: $LOG — passed $N, 0 failures, 0 controlling skips${NAMED:+, '$NAMED' ran+passed}"
