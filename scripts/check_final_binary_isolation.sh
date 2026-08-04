#!/usr/bin/env bash
# Phase 4 / panel B5: final-binary negative + positive controls, ENFORCED (not
# just printed). Builds production and diag IN ISOLATION (flutter clean between
# builds so incremental Swift artifacts can't cross-contaminate), then applies
# the agreed production contract:
#
#   The ONLY diagnostic-related strings allowed in a production binary are the
#   compiled-in-all-builds channel + foreign-wipe machinery (channel case names
#   like "armW5Fault"/"setDiagRunSecret", and the diagnostic FILE NAMES the
#   wipe path erases). Everything else diagnostic must be absent:
#     - the diagnostic CODE itself: W5Diag + W5EvidenceWriter symbols, and
#     - the diagnostic-only run-secret ENV read "INRANGE_DIAG_RUN_SECRET".
#
#   NEGATIVE (production): diag symbols == 0 AND the run-secret env string absent.
#   POSITIVE (diag):       diag symbols  > 0 AND the run-secret env string present.
#
# CONTRACT RATIFIED BY THE OWNER (2026-08-04): production excludes diagnostic
# SYMBOLS + the run-secret env read; the compiled-in channel-case names and
# diagnostic filenames (foreign-wipe machinery) are explicitly ALLOWED. (Panel
# B5 ruling — "Symbols + run-secret env".)
#
# The positive control proves the discriminators actually fire; the informational
# filename/channel strings are reported but NOT failed (they are contract-allowed).
# Fail-closed on any missing build. CI-friendly: .env is optional.
set -uo pipefail
cd "$(dirname "$0")/.."

BIN="build/ios/iphoneos/Runner.app/Runner"
FAIL=0

# Diagnostic CODE symbols (types that are ENTIRELY #if INRANGE_DIAG).
symcount() { nm "$1" 2>/dev/null | grep -cE 'W5Diag|W5EvidenceWriter'; }
# Diagnostic-only run-secret env read (never compiled into production).
secretcount() { strings "$1" 2>/dev/null | grep -c 'INRANGE_DIAG_RUN_SECRET'; }
# Contract-allowed machinery strings (reported for information only).
machinecount() { strings "$1" 2>/dev/null | grep -cE 'bb_wake_log|w5_events|w5_rssi_log|armW5Fault|setDiagRunSecret'; }

ENVFLAG=""
[ -f .env ] && ENVFLAG="--dart-define-from-file=.env"

echo "== production release (clean) =="
flutter clean >/dev/null 2>&1
# --no-codesign: the isolation check inspects the unsigned Mach-O with nm/strings;
# signing is irrelevant and would fail on a CI runner with no signing identity
# (the exact isolation-ios failure at 9775960). Local runs also work unsigned.
if ! flutter build ios --release --no-codesign >/dev/null 2>&1; then echo "FAIL: prod build"; exit 1; fi
[ -f "$BIN" ] || { echo "FAIL: prod binary missing"; exit 1; }
PSYM=$(symcount "$BIN"); PSEC=$(secretcount "$BIN"); PMAC=$(machinecount "$BIN")
echo "production: diag-syms=$PSYM run-secret-env=$PSEC (machinery-strings=$PMAC, allowed/informational)"
if [ "$PSYM" -eq 0 ]; then echo "OK(negative/sym): no diagnostic code in production"
else echo "FAIL(negative/sym): production contains $PSYM diagnostic symbols"; FAIL=1; fi
if [ "$PSEC" -eq 0 ]; then echo "OK(negative/str): no run-secret env read in production"
else echo "FAIL(negative/str): production references INRANGE_DIAG_RUN_SECRET"; FAIL=1; fi

echo "== diag release (clean) =="
flutter clean >/dev/null 2>&1
if ! flutter build ios --flavor diag --release --no-codesign $ENVFLAG \
  --dart-define=INRANGE_W5_LINKS=true >/dev/null 2>&1; then echo "FAIL: diag build"; exit 1; fi
[ -f "$BIN" ] || { echo "FAIL: diag binary missing"; exit 1; }
DSYM=$(symcount "$BIN"); DSEC=$(secretcount "$BIN")
echo "diag: diag-syms=$DSYM run-secret-env=$DSEC"
if [ "$DSYM" -gt 0 ]; then echo "OK(positive/sym): diagnostic code present in diag (sym control discriminates)"
else echo "FAIL(positive/sym): diag binary has no diagnostic symbols — check cannot discriminate"; FAIL=1; fi
if [ "$DSEC" -gt 0 ]; then echo "OK(positive/str): run-secret env read present in diag (str control discriminates)"
else echo "FAIL(positive/str): diag binary lacks INRANGE_DIAG_RUN_SECRET — str check cannot discriminate"; FAIL=1; fi

exit $FAIL
