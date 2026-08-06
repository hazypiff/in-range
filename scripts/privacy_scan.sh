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
#   * /Users/<name>            real home dir  (placeholder /Users/<redacted> is fine)
#   * UUID / UDID forms        8-4-4-4-12 hex, unless APPROVED (see allow-model)
#   * Bluetooth / MAC ids      XX:XX:XX:XX:XX:XX, unless APPROVED
#   * machine-local env dumps  RUN_DESTINATION_DEVICE_UDID=, *SESSION_ID=, LaunchInstanceID=
#   * the fleet run secret     exact value, if $INRANGE_DIAG_RUN_SECRET is set (never printed)
#   * raw xcodebuild logs      native_*_*.log lacking the sanitizer derivation header
#
# Git commit SHAs (40-hex) and content hashes (64-hex) are NOT flagged — they are
# legitimate, non-identifying provenance. This scanner targets identifiers.
#
# APPROVAL MODEL ("unapproved" per the directive). A UUID/MAC token is a finding
# UNLESS it is approved by one of:
#   - ALLOW_VALUE_RE : a public/standard constant shape (Bluetooth SIG base UUID,
#                      the app's fixed iBeacon UUID, the nil UUID, a documentation
#                      placeholder MAC).
#   - a path in ALLOW_PATH : synthetic-fixture trees (seed/test SQL, Dart tests)
#                      that by construction contain only invented values.
#   - a file in ALLOW_FILE : this scanner + its fixtures + the sanitizer fixture.
# Everything else must be a real, non-identifying value or it fails. Real device
# UDIDs are deliberately NOT approved.
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

# Synthetic-fixture trees: only invented UUIDs/MACs by construction.
allow_path() {
  case "$1" in
    supabase/seed/*|supabase/tests/*|test/*) return 0 ;;
  esac
  return 1
}

# Files permitted to hold leak-SHAPED fixtures (synthetic values only).
allow_file() {
  case "$1" in
    scripts/privacy_scan.sh|scripts/privacy_scan_test.sh) return 0 ;;
    docs/research/2026-08-01-hardening/sanitize_native_log_test.sh) return 0 ;;
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
  [ -f "$f" ] || continue
  LC_ALL=C grep -qI . "$f" 2>/dev/null || continue   # skip binary

  # raw xcodebuild log detector (applies even to allow-listed dirs).
  case "$f" in
    *native_*.log)
      head -1 "$f" | grep -q '^# sanitized native-test evidence$' \
        || report "$f" "raw xcodebuild log (missing sanitizer header)"
      ;;
  esac

  allow_file "$f" && continue

  # env-dump identifiers are never allowed anywhere.
  while IFS=: read -r ln _; do
    [ -n "$ln" ] && report "$f:$ln" "machine-local env identifier"
  done < <(grep -nE "$ENVDUMP_RE" "$f" 2>/dev/null)

  # /Users/<name> real home paths (placeholder /Users/<redacted> excluded by class).
  while IFS=: read -r ln _; do
    [ -n "$ln" ] && report "$f:$ln" "absolute /Users/<name> home path"
  done < <(grep -nE "$USERPATH_RE" "$f" 2>/dev/null)

  allow_path "$f" && continue

  scan_form "$f" "UUID/UDID identifier"      "$UUID_RE"
  scan_form "$f" "Bluetooth/MAC identifier"  "$MAC_RE"
done < <(git ls-files)

# fleet run secret exact-value check (never printed; only filename can surface).
if [ -n "${INRANGE_DIAG_RUN_SECRET:-}" ]; then
  while IFS= read -r hf; do
    [ -n "$hf" ] && report "$hf" "fleet run secret value present"
  done < <(git grep -I -l -F -- "$INRANGE_DIAG_RUN_SECRET" 2>/dev/null || true)
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
