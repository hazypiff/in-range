#!/usr/bin/env bash
# Assert an xcodebuild native-test log meets the Wave A gate: TEST SUCCEEDED,
# ZERO controlling skips, discovered==passed (0 failures), the passed count, and
# (optionally) that a NAMED test actually ran and passed. A bare
# `grep TEST SUCCEEDED` proves none of these (R6).
#
#   assert_native_tests.sh <log> <count> [named-test] [expected-source-sha]
#
# <count> forms (A.1-4 — pin the discovered SET, not only a lower bound):
#   N     minimum: discovered/passed must be >= N   (lower bound; legacy)
#   =N    EXACT:   discovered/passed must EQUAL N    (pinned set — a silently
#                  dropped OR an unexpectedly added test both fail the gate)
#
# expected-source-sha (A.1-5 — panel intake provenance): when given, the log MUST
# carry a `# source_sha: <sha>` header (as stamped by sanitize_native_log.sh) that
# EQUALS it. A sanitized evidence file with no/other source SHA fails intake.
#
# Supports both xcodebuild output formats:
#   old: "Test Case '-[Suite testX]' passed" + "Executed N tests, with M failures"
#   new: "Test case 'Suite.testX()' passed on 'Clone ...'"
set -uo pipefail
LOG="${1:?log path required}"; COUNT_SPEC="${2:?count (N or =N) required}"
NAMED="${3:-}"; EXPECT_SHA="${4:-}"
fail() { echo "ASSERT FAIL: $1" >&2; exit 1; }

EXACT=0
case "$COUNT_SPEC" in
  =*) EXACT=1; MIN="${COUNT_SPEC#=}" ;;
  *)  MIN="$COUNT_SPEC" ;;
esac
printf '%s' "$MIN" | grep -Eq '^[0-9]+$' || fail "count must be N or =N (got '$COUNT_SPEC')"

[ -f "$LOG" ] || fail "log missing: $LOG"
grep -q '\*\* TEST SUCCEEDED \*\*' "$LOG" || fail "no '** TEST SUCCEEDED **' in $LOG"

# A.1-5: panel-intake provenance — the sanitized evidence must be stamped with the
# expected source SHA in its header.
if [ -n "$EXPECT_SHA" ]; then
  hdr_sha="$(grep -m1 -E '^# source_sha:' "$LOG" | awk '{print $3}')"
  [ -n "$hdr_sha" ] || fail "no '# source_sha:' header in $LOG (unstamped evidence)"
  [ "$hdr_sha" = "$EXPECT_SHA" ] \
    || fail "source_sha header ($hdr_sha) != expected ($EXPECT_SHA) in $LOG"
fi

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
if [ "$EXACT" -eq 1 ]; then
  [ "${N:-0}" -eq "$MIN" ] \
    || fail "discovered/passed $N != pinned exact set $MIN in $LOG (a test was dropped or added)"
else
  [ "${N:-0}" -ge "$MIN" ] || fail "passed $N < expected minimum $MIN in $LOG"
fi

# The named test actually ran AND passed (not absent-because-skipped).
if [ -n "$NAMED" ]; then
  grep -Eq "Test [Cc]ase '.*${NAMED}.*' passed" "$LOG" \
    || fail "named test '$NAMED' did not run and pass"
fi

echo "OK: $LOG — passed $N ($([ "$EXACT" -eq 1 ] && echo "exact ==$MIN" || echo ">= $MIN")), 0 failures, 0 controlling skips${NAMED:+, '$NAMED' ran+passed}${EXPECT_SHA:+, source_sha verified}"
