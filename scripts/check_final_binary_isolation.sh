#!/usr/bin/env bash
# Phase 4: final-binary negative/positive controls. Builds production and diag
# IN ISOLATION (flutter clean between builds so incremental Swift artifacts
# can't cross-contaminate), then discriminates on the DIAGNOSTIC CODE via
# `nm` W5Diag symbol count — NOT on strings.
#
# Why not strings: the foreign-flavor WIPE machinery (diagnosticFileNames +
# wipeDiagnosticFiles) legitimately references the diag file-name literals in
# PRODUCTION (so a production build can erase foreign diag files), so those
# strings appear in both binaries. The true discriminator is whether the
# diagnostic code itself (W5Diag.*) was compiled in.
#   NEGATIVE: production binary has ZERO W5Diag symbols.
#   POSITIVE: diag binary has W5Diag symbols (proves the check discriminates).
# strings counts are reported for information only. Fail-closed on missing build.
set -uo pipefail
cd "$(dirname "$0")/.."

BIN="build/ios/iphoneos/Runner.app/Runner"
FAIL=0

symcount() { nm "$1" 2>/dev/null | grep -c 'W5Diag'; }
strcount() { strings "$1" 2>/dev/null | grep -cE 'bb_wake_log|w5_events|armW5Fault'; }

echo "== production release (clean) =="
flutter clean >/dev/null 2>&1
if ! flutter build ios --release >/dev/null 2>&1; then echo "FAIL: prod build"; exit 1; fi
[ -f "$BIN" ] || { echo "FAIL: prod binary missing"; exit 1; }
PSYM=$(symcount "$BIN"); PSTR=$(strcount "$BIN")
echo "production: W5Diag-syms=$PSYM (strings=$PSTR, informational)"
if [ "$PSYM" -eq 0 ]; then echo "OK(negative): no diagnostic code in production"
else echo "FAIL(negative): production contains $PSYM W5Diag symbols"; FAIL=1; fi

echo "== diag release (clean) =="
flutter clean >/dev/null 2>&1
if ! flutter build ios --flavor diag --release --dart-define-from-file=.env \
  --dart-define=INRANGE_W5_LINKS=true >/dev/null 2>&1; then echo "FAIL: diag build"; exit 1; fi
[ -f "$BIN" ] || { echo "FAIL: diag binary missing"; exit 1; }
DSYM=$(symcount "$BIN"); DSTR=$(strcount "$BIN")
echo "diag: W5Diag-syms=$DSYM (strings=$DSTR, informational)"
if [ "$DSYM" -gt 0 ]; then echo "OK(positive): diagnostic code present in diag (control discriminates)"
else echo "FAIL(positive): diag binary has no W5Diag symbols — check cannot discriminate"; FAIL=1; fi

exit $FAIL
