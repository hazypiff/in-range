#!/usr/bin/env bash
# Whole-tip privacy scanner. Walks the tracked files at the working tree and
# FAILS if any machine-local identifier or secret is present. Enforces the final
# directive's sanitized-evidence rule so no raw device/host value can ride into
# the docs, implementation, or PR history.
#
#   scripts/privacy_scan.sh
#
# FAILS on (each finding prints file:line + CLASS only — never the value, so the
# scanner itself cannot leak a real identifier into a log or transcript):
#   * /Users/<name>            real home dir  (placeholder /Users/<redacted> is fine) — binaries too
#   * machine-local env dumps  RUN_DESTINATION_DEVICE_UDID / *SESSION_ID / LaunchInstanceID assignments — binaries too
#   * the fleet run secret     exact value (binaries included), if $INRANGE_DIAG_RUN_SECRET set (never printed)
#   * UUID / UDID forms        8-4-4-4-12 hex, unless APPROVED (TEXT files only — binary hex is noise; a real
#                              device id baked into a binary is caught by the home-path / env / secret binary scans above)
#   * Bluetooth / MAC ids      XX:XX:XX:XX:XX:XX in TEXT files, unless APPROVED
#   * leak in a FILENAME       UUID/MAC/`/Users` in any tracked path name (every file, binaries included)
#   * raw xcodebuild logs      native_*_*.log lacking the sanitizer derivation header
#
# Git commit SHAs (40-hex) and content hashes (64-hex) are NOT flagged — they are
# legitimate, non-identifying provenance. This scanner targets identifiers.
#
# APPROVAL MODEL ("unapproved" per the directive), hardened after panel P4:
#   * The FILENAME check and the fleet-SECRET check apply to EVERY tracked path,
#     with NO exceptions (even shape-trusted files / binaries).
#   * The /Users and env-dump CONTENT checks apply to every file EXCEPT the small,
#     explicitly code-reviewed set of DEFINITIONAL files (this scanner + its test +
#     the leak-fixture files), which contain the leak patterns by construction.
#   * A UUID/MAC TOKEN is a finding unless approved_token() matches a public/standard
#     constant (Bluetooth SIG base UUID, app iBeacon UUID, Herald UUID, nil UUID,
#     placeholder MAC). This shape check is relaxed ONLY inside the synthetic-fixture
#     TREES (supabase/seed, supabase/tests, test/), which hold many invented UUIDs.
# DOCUMENTED RESIDUAL: a real device UDID is shape-indistinguishable from a synthetic
# one, so one committed into a fixture tree / definitional file would pass the shape
# check; those locations are fixture-only by policy and code review is the backstop.
# Real device UDIDs are deliberately NOT in approved_token().
set -uo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

FINDINGS="$(mktemp)"; trap 'rm -f "$FINDINGS"' EXIT
report() { printf '%s\t%s\n' "$1" "$2" >> "$FINDINGS"; }

UUID_RE='[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}'
MAC_RE='([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}'
USERPATH_RE='/Users/[A-Za-z0-9._+-]+'
ENVDUMP_RE='(RUN_DESTINATION_DEVICE_UDID|TERM_SESSION_ID|LaunchInstanceID|CLAUDE_CODE_SESSION_ID)='

# Approved token shapes (public constants / documentation placeholders).
approved_token() {
  local t="$1"
  case "$t" in
    # Bluetooth SIG base UUID (any 16/32-bit service UUID mapped onto it).
    *-0000-1000-8000-00805[fF]9[bB]34[fF][bB]) return 0 ;;
    # nil UUID.
    00000000-0000-0000-0000-000000000000) return 0 ;;
    # App's fixed iBeacon proximity UUID (public constant, identical every install).
    2F234454-CF6D-4A0F-ADF2-F4911BA9FFA6|2f234454-cf6d-4a0f-adf2-f4911ba9ffa6) return 0 ;;
    # Test-only carrier UUID used by apple_overflow_bit unit tests.
    9aa4730f-b25c-4cc3-b821-c931559fc196|9AA4730F-B25C-4CC3-B821-C931559FC196) return 0 ;;
    # Herald library signal characteristic UUID (public library constant, cited in
    # IOS_PROXIMITY_RESEARCH; identical for every install — not a device identifier).
    0eb0d5f2-eae4-4a9a-8af3-a4adb02d4363|0EB0D5F2-EAE4-4A9A-8AF3-A4ADB02D4363) return 0 ;;
    # Documentation placeholder MACs.
    [Aa][Aa]:[Bb][Bb]:[Cc][Cc]:[Dd][Dd]:[Ee][Ee]:[Ff][Ff]) return 0 ;;
    11:22:33:44:55:66) return 0 ;;
    [Aa][Aa]:[Aa][Aa]:[Aa][Aa]:[Aa][Aa]:[Aa][Aa]:[Aa][Aa]) return 0 ;;
    [Bb][Bb]:[Bb][Bb]:[Bb][Bb]:[Bb][Bb]:[Bb][Bb]:[Bb][Bb]) return 0 ;;
  esac
  return 1
}

# SHAPE-trusted trees/files (panel P4): these relax ONLY the UUID/MAC *shape*
# check, because they contain many synthetic UUID/MAC-shaped fixtures by
# construction. They do NOT bypass the /Users, env-dump, filename, or fleet-secret
# checks — those still run on every tracked file. RESIDUAL (documented, accepted):
# a real device UDID is shape-indistinguishable from a synthetic one, so a real
# UDID *committed into one of these fixture trees* would pass the shape check
# unflagged; these trees are fixture-only by policy and code review is the backstop.
shape_trusted_path() {
  case "$1" in
    supabase/seed/*|supabase/tests/*|test/*) return 0 ;;
  esac
  return 1
}
# Files that hold a synthetic UUID/MAC-shaped fixture and get ONLY the UUID/MAC
# SHAPE relaxed (never the /Users, env-dump, filename, or secret checks — those
# still run). The test files build their /Users and env-dump fixture strings from
# CONCATENATED parts so no real-looking assignment appears literally here (panel
# P4): the only shape they carry is a synthetic UUID, which this list relaxes.
shape_trusted_file() {
  case "$1" in
    scripts/privacy_scan_test.sh) return 0 ;;
    docs/research/2026-08-01-hardening/sanitize_native_log_test.sh) return 0 ;;
    docs/research/2026-08-01-hardening/hw_matrix_pull_test.sh) return 0 ;;
  esac
  return 1
}

# Report file:line for any line containing an UNAPPROVED token of a given form.
scan_form() { # file, class, regex
  local f="$1" cls="$2" re="$3" ln rest tok bad
  while IFS=: read -r ln rest; do
    [ -n "$ln" ] || continue
    bad=0
    for tok in $(printf '%s\n' "$rest" | grep -oE "$re"); do
      approved_token "$tok" && continue
      bad=1
    done
    [ "$bad" -eq 1 ] && report "$f:$ln" "$cls"
  done < <(grep -nE "$re" "$f" 2>/dev/null)
}

while IFS= read -r f; do
  # FILENAME check first — applies to EVERY tracked path, even binaries and
  # shape-trusted files (panel P4: a leak in a tracked filename was unscanned).
  for tok in $(printf '%s' "$f" | grep -oE "$UUID_RE"); do
    approved_token "$tok" || report "$f" "UUID/UDID identifier in filename"
  done
  for tok in $(printf '%s' "$f" | grep -oE "$MAC_RE"); do
    approved_token "$tok" || report "$f" "Bluetooth/MAC identifier in filename"
  done
  printf '%s' "$f" | grep -Eq "$USERPATH_RE" && report "$f" "/Users/<name> in tracked path"

  [ -f "$f" ] || continue
  is_text=1; LC_ALL=C grep -qI . "$f" 2>/dev/null || is_text=0

  # raw xcodebuild log detector (applies even to shape-trusted files).
  case "$f" in
    *native_*.log)
      head -1 "$f" | grep -q '^# sanitized native-test evidence$' \
        || report "$f" "raw xcodebuild log (missing sanitizer header)"
      ;;
  esac

  # Machine-local IDENTIFIER content checks run on EVERY tracked file INCLUDING
  # BINARIES (grep -a): a /Users home path or an env-dump identifier baked into a
  # committed binary must be caught too (panel P4 — binaries were previously
  # skipped for content). The scanner source avoids a literal env assignment, and
  # the test files build their leak fixtures from concatenated parts, so nothing
  # self-matches here.
  while IFS=: read -r ln _; do
    [ -n "$ln" ] && report "$f:$ln" "machine-local env identifier"
  done < <(grep -a -nE "$ENVDUMP_RE" "$f" 2>/dev/null)
  while IFS=: read -r ln _; do
    [ -n "$ln" ] && report "$f:$ln" "absolute /Users/<name> home path"
  done < <(grep -a -nE "$USERPATH_RE" "$f" 2>/dev/null)

  # UUID/MAC *shape* checks — TEXT files only (a binary is full of random hex that
  # would match the UUID/MAC shape and drown the scan in noise; a real device id
  # baked into a binary is instead caught by the /Users, env-dump, and secret
  # checks above, which DO scan binaries). Relaxed ONLY for the synthetic-fixture
  # trees and the shape-fixture files. Documented residual: a real UDID is shape-
  # indistinguishable from a synthetic one, so one committed into such a tree/file
  # passes the shape check; those are fixture-only by policy (code review backstop).
  if [ "$is_text" -eq 1 ] && ! shape_trusted_path "$f" && ! shape_trusted_file "$f"; then
    scan_form "$f" "UUID/UDID identifier"      "$UUID_RE"
    scan_form "$f" "Bluetooth/MAC identifier"  "$MAC_RE"
  fi
done < <(git ls-files)

# fleet run secret exact-value check — scans BINARIES too (panel P4: -I would skip
# a secret baked into a tracked binary). Never printed; only the filename surfaces.
if [ -n "${INRANGE_DIAG_RUN_SECRET:-}" ]; then
  while IFS= read -r hf; do
    [ -n "$hf" ] && report "$hf" "fleet run secret value present"
  done < <(git grep -l -F -- "$INRANGE_DIAG_RUN_SECRET" 2>/dev/null || true)
fi

n="$(wc -l < "$FINDINGS" | tr -d ' ')"
if [ "$n" -eq 0 ]; then
  echo "PRIVACY SCAN CLEAN — no machine-local identifiers or secrets in the tip."
else
  sort -u "$FINDINGS" | while IFS="$(printf '\t')" read -r loc cls; do
    printf 'PRIVACY FAIL  %-56s  %s\n' "$loc" "$cls"
  done
  echo "----"
  echo "PRIVACY SCAN FAILED — $(sort -u "$FINDINGS" | wc -l | tr -d ' ') finding(s) above."
  exit 1
fi
