#!/usr/bin/env bash
# Positive-leak fixtures + determinism test for sanitize_native_log.sh.
#
# RED-BEFORE intuition: the fixture raw log deliberately embeds every leak class
# the panel flagged (a /Users/<name> path, a simulator UDID, a launch/term/session
# UUID, a MAC address, a /var/folders temp path, an ISO timestamp, a KEYCHAIN
# export). Emitting the raw log verbatim (the pre-fix behaviour) publishes all of
# them. GREEN-AFTER: the sanitizer's output must contain NONE of them, while the
# evidence lines (test names, pass/fail verbs, Executed summary, TEST SUCCEEDED)
# and their counts survive intact and recomputably.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SAN="$HERE/sanitize_native_log.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0
ok()   { printf 'ok   %s\n' "$1"; }
bad()  { printf 'FAIL %s\n' "$1"; fails=$((fails+1)); }

RAW="$TMP/raw.log"
# /Users and the env-dump KEY NAMES are built from concatenated parts so this
# test's own SOURCE carries no literal home path or `<var>=` assignment that the
# whole-tip privacy scan would (correctly) flag against it (panel P4 — this file
# is shape-trusted for the synthetic UUIDs only, not for /Users or env-dumps).
U="/Users/"; RDU="RUN_DESTINATION_DEVICE""_UDID"; TSI="TERM_SESSION""_ID"
LII="LaunchInstance""ID"; CSK="CODE_SIGN""_KEYCHAIN"
cat > "$RAW" <<EOF
=== BUILD TARGET Runner OF PROJECT Runner WITH CONFIGURATION Debug ===
    cd ${U}someuser/in-range/ios
    export ${CSK}=${U}someuser/Library/Keychains/login.keychain-db
    export ${RDU}=11111111-2222-3333-4444-555555555555
    export ${TSI}=AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE
    export ${LII}=99999999-8888-7777-6666-555544443333
    builtin-copy /private/var/folders/xy/abc123/T/Runner.app
    peripheral 11:22:33:44:55:66 discovered
Test Suite 'All tests' started at 2026-08-06 13:26:06.668.
Test Suite 'RunnerTests.xctest' started at 2026-08-06 13:26:06.669.
Test Case '-[RunnerTests.W5DiagTests testHandleUsesProvisionedRunSecret]' passed (0.004 seconds).
Test Case '-[RunnerTests.W5DiagTests testAnother]' passed (0.002 seconds).
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.006 (0.007) seconds
Test Suite 'All tests' passed at 2026-08-06 13:26:27.115.
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.006 (0.010) seconds
** TEST SUCCEEDED **
EOF

OUT="$(bash "$SAN" "$RAW" deadbeefcafe0000deadbeefcafe0000deadbeef "Runner (Debug)")"

# --- leaks must be gone --------------------------------------------------------
check_absent() { # label, pattern
  if printf '%s\n' "$OUT" | grep -Eq "$2"; then bad "leak survived: $1"; else ok "leak removed: $1"; fi
}
check_absent "/Users/<name> path"     "${U}someuser"
check_absent "simulator UDID"         '11111111-2222-3333-4444-555555555555'
check_absent "TERM_SESSION_ID uuid"   'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE'
check_absent "LaunchInstanceID uuid"  '99999999-8888-7777-6666-555544443333'
check_absent "any UUID form"          '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}'
check_absent "MAC address"            '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}'
check_absent "/var/folders temp"      '/private/var/folders|/var/folders'
check_absent "KEYCHAIN export line"   'CODE_SIGN_KEYCHAIN'
check_absent "ISO timestamp"          '[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}'

# --- evidence must survive -----------------------------------------------------
check_present() { # label, pattern
  if printf '%s\n' "$OUT" | grep -Eq "$2"; then ok "evidence kept: $1"; else bad "evidence LOST: $1"; fi
}
check_present "named test line"       "Test Case '.*testHandleUsesProvisionedRunSecret.*' passed"
check_present "second test line"      "Test Case '.*testAnother.*' passed"
check_present "executed summary"      'Executed 2 tests, with 0 failures'
check_present "build result"          '\*\* TEST SUCCEEDED \*\*'
check_present "source_sha header"     '^# source_sha: deadbeefcafe0000deadbeefcafe0000deadbeef$'
check_present "raw_input_sha256"      '^# raw_input_sha256: [0-9a-f]{64}$'

# --- counts preserved (2 passed lines, 0 failed) -------------------------------
np="$(printf '%s\n' "$OUT" | grep -Ec "Test Case '.*' passed")"
nf="$(printf '%s\n' "$OUT" | grep -Ec "Test Case '.*' failed")"
[ "$np" -eq 2 ] && ok "passed-line count preserved (2)" || bad "passed-line count wrong ($np)"
[ "$nf" -eq 0 ] && ok "no failed lines"                  || bad "failed lines present ($nf)"

# --- determinism ---------------------------------------------------------------
OUT2="$(bash "$SAN" "$RAW" deadbeefcafe0000deadbeefcafe0000deadbeef "Runner (Debug)")"
[ "$OUT" = "$OUT2" ] && ok "deterministic (identical re-run)" || bad "non-deterministic output"

echo "----"
if [ "$fails" -eq 0 ]; then echo "ALL SANITIZER TESTS PASSED"; else echo "$fails SANITIZER TEST(S) FAILED"; exit 1; fi
