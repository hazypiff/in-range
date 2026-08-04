#!/usr/bin/env bash
# Phase 4 / panel B5: final-BUNDLE negative + positive controls, ENFORCED.
# Builds production and diag IN ISOLATION (flutter clean between builds) and
# scans EVERY Mach-O in the .app bundle — the native Runner AND every framework
# executable, including Flutter's Dart AOT at App.framework/App. (Round-3 panel:
# the previous checker scanned only Runner.app/Runner and missed the
# INRANGE_DIAG_RUN_SECRET key that shipped in the Dart AOT — a false-green.)
#
# CONTRACT (owner-ratified 2026-08-04 — "symbols + run-secret env"):
#   A production build must contain, across the WHOLE bundle:
#     - 0 diagnostic Swift symbols (W5Diag / W5EvidenceWriter), and
#     - 0 occurrences of the diagnostic run-secret VALUE (native OR Dart AOT).
#   NOTE: the run-secret KEY name is not a runtime string — String.fromEnvironment
#   resolves at compile time — so the discriminator is the baked VALUE, which is
#   a runtime const in diag and folded away (kDiagBuild=false) in production.
#   The compiled-in-all-builds channel-case names (armW5Fault / setDiagRunSecret)
#   and diagnostic file names (foreign-wipe machinery) are contract-ALLOWED and
#   reported for information only.
#   NEGATIVE (production): diag symbols == 0 AND run-secret key absent EVERYWHERE.
#   POSITIVE (diag):       diag symbols  > 0 (Runner) AND run-secret key present
#                          (its Dart AOT), so both discriminators are proven live.
# Fail-closed on any missing build. CI-friendly: .env optional.
set -uo pipefail
cd "$(dirname "$0")/.."

APP="build/ios/iphoneos/Runner.app"
FAIL=0

# EVERY Mach-O anywhere in the bundle — recursively: the app binary, every
# framework/dylib executable (incl. nested), and any .appex/plugin binary.
# (Round-4 panel: a top-level Frameworks/*.framework scan missed nested
# frameworks, dylibs, and app extensions.)
bundle_machos() {
  local app="$1" f
  find "$app" -type f 2>/dev/null | while IFS= read -r f; do
    if file "$f" 2>/dev/null | grep -q 'Mach-O'; then echo "$f"; fi
  done
}

# A KNOWN diagnostic run-secret VALUE baked ONLY into the diag build below. The
# discriminator is the baked VALUE, not the key NAME: `String.fromEnvironment`
# resolves at COMPILE time, so the key name is never a runtime string in either
# build — the round-3 leak was actually the removed switch case-LABEL. The
# baked value, by contrast, IS a runtime const in the diag Dart AOT and must be
# ABSENT from production (kDiagBuild folds the read away). Not a real secret.
KNOWN_DIAG_SECRET="d1a6d1a6d1a6d1a6d1a6d1a6d1a6d1a6d1a6d1a6d1a6d1a6d1a6d1a6d1a6d1a6"

# Diagnostic Swift symbols (types ENTIRELY #if INRANGE_DIAG) — native only.
symcount() { nm "$APP/Runner" 2>/dev/null | grep -cE 'W5Diag|W5EvidenceWriter'; }
# The baked run-secret VALUE across the WHOLE bundle (must be 0 in production).
secretcount_bundle() {
  local total=0 m n
  while IFS= read -r m; do
    [ -f "$m" ] || continue
    n=$(strings "$m" 2>/dev/null | grep -c "$KNOWN_DIAG_SECRET")
    total=$((total + n))
  done < <(bundle_machos "$APP")
  echo "$total"
}
# The baked run-secret VALUE in the Dart AOT (positive control target for diag).
secretcount_dart() {
  strings "$APP/Frameworks/App.framework/App" 2>/dev/null | grep -c "$KNOWN_DIAG_SECRET"
}
machinecount() { strings "$APP/Runner" 2>/dev/null | grep -cE 'bb_wake_log|w5_events|w5_rssi_log|armW5Fault|setDiagRunSecret'; }

ENVFLAG=""
[ -f .env ] && ENVFLAG="--dart-define-from-file=.env"

echo "== production release (clean) =="
flutter clean >/dev/null 2>&1
# --no-codesign: the check inspects unsigned Mach-Os; signing is irrelevant and
# fails on a CI runner with no identity.
if ! flutter build ios --release --no-codesign >/dev/null 2>&1; then echo "FAIL: prod build"; exit 1; fi
[ -f "$APP/Runner" ] || { echo "FAIL: prod bundle missing"; exit 1; }
PSYM=$(symcount); PSEC=$(secretcount_bundle); PMAC=$(machinecount)
echo "production: diag-syms=$PSYM run-secret-value(bundle)=$PSEC (machinery-strings=$PMAC, allowed/informational)"
echo "  scanned: $(bundle_machos "$APP" | tr '\n' ' ')"
if [ "$PSYM" -eq 0 ]; then echo "OK(negative/sym): no diagnostic code in production"
else echo "FAIL(negative/sym): production contains $PSYM diagnostic symbols"; FAIL=1; fi
if [ "$PSEC" -eq 0 ]; then echo "OK(negative/str): baked run-secret value absent from the whole bundle"
else echo "FAIL(negative/str): production bundle contains the diag run-secret value ($PSEC)"; FAIL=1; fi

echo "== diag release (clean) =="
flutter clean >/dev/null 2>&1
# INRANGE_DIAG=true lights kDiagBuild so the Dart run-secret read compiles in;
# baking a KNOWN value lets the positive control confirm the checker can detect
# it in the Dart AOT (so production's 0 is a meaningful discriminator, not a
# blind spot). INRANGE_W5_LINKS enables the link layer.
if ! flutter build ios --flavor diag --release --no-codesign $ENVFLAG \
  --dart-define=INRANGE_W5_LINKS=true \
  --dart-define=INRANGE_DIAG=true \
  --dart-define=INRANGE_DIAG_RUN_SECRET="$KNOWN_DIAG_SECRET" >/dev/null 2>&1; then echo "FAIL: diag build"; exit 1; fi
[ -f "$APP/Runner" ] || { echo "FAIL: diag bundle missing"; exit 1; }
DSYM=$(symcount); DSEC=$(secretcount_dart)
echo "diag: diag-syms(Runner)=$DSYM run-secret-value(App.framework)=$DSEC"
if [ "$DSYM" -gt 0 ]; then echo "OK(positive/sym): diagnostic code present in diag Runner"
else echo "FAIL(positive/sym): diag Runner has no diagnostic symbols — check cannot discriminate"; FAIL=1; fi
if [ "$DSEC" -gt 0 ]; then echo "OK(positive/str): baked run-secret value present in diag Dart AOT (discriminator proven)"
else echo "FAIL(positive/str): diag Dart AOT lacks the baked run-secret value — str check cannot discriminate"; FAIL=1; fi

exit $FAIL
