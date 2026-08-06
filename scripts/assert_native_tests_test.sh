#!/usr/bin/env bash
# Self-contained red/green fixtures for scripts/assert_native_tests.sh. No device,
# no build — synthetic xcodebuild-shaped logs prove the gate's teeth: exact-set
# pinning, discovered==passed reconciliation, zero-skip, named anchor, and the
# A.1-5 source-SHA panel-intake check.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
A="$HERE/assert_native_tests.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0
pass_ok(){ printf 'ok   %s\n' "$1"; }
pass_bad(){ printf 'FAIL %s\n' "$1"; fails=$((fails+1)); }
# expect_pass <label> args...   ; expect_fail <label> args...
expect_pass(){ local l="$1"; shift; if bash "$A" "$@" >/dev/null 2>&1; then pass_ok "$l"; else pass_bad "$l (expected PASS)"; fi; }
expect_fail(){ local l="$1"; shift; if bash "$A" "$@" >/dev/null 2>&1; then pass_bad "$l (expected FAIL)"; else pass_ok "$l"; fi; }

SHA=abc1230000000000000000000000000000000000

# good.log — stamped, 2 passed, reconciled summary, success.
cat > "$TMP/good.log" <<EOF
# sanitized native-test evidence
# source_sha: $SHA
Test Case '-[RunnerTests.S testAnchor]' passed (0.00 seconds).
Test Case '-[RunnerTests.S testOther]' passed (0.00 seconds).
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.0 (0.0) seconds
** TEST SUCCEEDED **
EOF

# skip.log — a controlling skip must fail.
cat > "$TMP/skip.log" <<EOF
Test Case '-[RunnerTests.S testAnchor]' passed (0.00 seconds).
Test Case '-[RunnerTests.S testSkipped]' skipped (0.00 seconds).
	 Executed 1 test, with 0 failures (0 unexpected) in 0.0 (0.0) seconds
** TEST SUCCEEDED **
EOF

# forged.log — 1 passed line but summary claims 70 (discovered!=passed).
cat > "$TMP/forged.log" <<EOF
Test Case '-[RunnerTests.S testAnchor]' passed (0.00 seconds).
	 Executed 70 tests, with 0 failures (0 unexpected) in 0.0 (0.0) seconds
** TEST SUCCEEDED **
EOF

# fail.log — a failing summary must fail even with a passed line.
cat > "$TMP/fail.log" <<EOF
Test Case '-[RunnerTests.S testAnchor]' passed (0.00 seconds).
Test Case '-[RunnerTests.S testBad]' failed (0.00 seconds).
	 Executed 2 tests, with 1 failure (1 unexpected) in 0.0 (0.0) seconds
** TEST FAILED **
EOF

expect_pass "exact =2 + anchor + SHA"          "$TMP/good.log" "=2" testAnchor "$SHA"
expect_pass "min >=2 backward compatible"      "$TMP/good.log" 2
expect_fail "exact =3 mismatch (added/dropped)" "$TMP/good.log" "=3"
expect_fail "exact =1 mismatch"                "$TMP/good.log" "=1"
expect_fail "wrong expected SHA"               "$TMP/good.log" "=2" "" deadbeef
expect_fail "expected SHA but log unstamped"   "$TMP/skip.log" 1 "" "$SHA"
expect_fail "controlling skip present"         "$TMP/skip.log" 1
expect_fail "forged summary (discovered!=passed)" "$TMP/forged.log" 1
expect_fail "failing summary"                  "$TMP/fail.log" 1
expect_fail "named anchor absent"              "$TMP/good.log" "=2" testMissingAnchor
expect_fail "bad count spec"                   "$TMP/good.log" "~2"

echo "----"
if [ "$fails" -eq 0 ]; then echo "ALL ASSERT-GATE TESTS PASSED"; else echo "$fails FAILED"; exit 1; fi
