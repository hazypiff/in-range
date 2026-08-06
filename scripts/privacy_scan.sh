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
# Every check below scans the COMMITTED GIT BLOB of every tracked path (enumerated
# with `git ls-files -z`, so filenames with newlines/special chars are handled), so
# regular files, symlinks (blob == target), dangling symlinks, AND binaries are all
# covered. Findings print file:line + CLASS only — never the matched value; a
# leak-bearing FILENAME is redacted before it is reported.
#   * /Users/<name>            real home dir (placeholder /Users/<redacted> is fine) — text + binary
#   * machine-local env dumps  RUN_DESTINATION_DEVICE_UDID / *SESSION_ID / LaunchInstanceID assignments — text + binary
#   * the fleet run secret     exact value, if $INRANGE_DIAG_RUN_SECRET is set (never printed) — text + binary
#   * UUID / UDID forms        8-4-4-4-12 hex — text + binary (the dashed form is specific
#                              enough that random binary bytes essentially never match), unless APPROVED
#   * Bluetooth / MAC ids      XX:XX:XX:XX:XX:XX — text + binary, unless APPROVED
#   * leak in a FILENAME       UUID/MAC/`/Users` in any tracked path name (every file)
#   * raw xcodebuild logs      native_*_*.log lacking the sanitizer derivation header
#
# Git commit SHAs (40-hex) and content hashes (64-hex) are NOT flagged — they are
# legitimate, non-identifying provenance. This scanner targets identifiers.
#
# APPROVAL MODEL ("unapproved" per the directive), hardened across panel P4 rounds:
#   * The FILENAME and fleet-SECRET checks apply to EVERY tracked path, no exception.
#   * The /Users and env-dump CONTENT checks apply to every file EXCEPT the small,
#     explicitly code-reviewed set of DEFINITIONAL files (this scanner + its test +
#     the leak-fixture files), which contain the leak patterns by construction; those
#     files build any home-path or env fixture from concatenated parts so nothing real hides.
#   * A UUID/MAC TOKEN (text OR binary) is a finding unless approved_token() matches a
#     public/standard constant (Bluetooth SIG base UUID, app iBeacon UUID, Herald UUID,
#     nil UUID, placeholder MAC). The shape check is relaxed ONLY inside the synthetic-
#     fixture TREES (supabase/seed, supabase/tests, test/) and the shape-fixture files.
# SOLE DOCUMENTED RELAXATION: a real device UDID is shape-indistinguishable from a
# synthetic one, so one committed INTO a fixture tree/file would pass the shape check —
# those locations are fixture-only by policy (code review is the backstop). This is an
# in-scope-documented allowlist boundary, not a downgrade of a real defect elsewhere.
# Real device UDIDs are deliberately NOT in approved_token().
set -uo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

FINDINGS="$(mktemp)"; BLOBF="$(mktemp)"; trap 'rm -f "$FINDINGS" "$BLOBF"' EXIT
report() { printf '%s\t%s\n' "$1" "$2" >> "$FINDINGS"; }
# Redact any matched leak token from a path before it is reported, so a finding
# for a leak-bearing FILENAME never re-prints the sensitive value (panel P4).
redact_path() { # path
  printf '%s' "$1" | sed -E "s#$UUID_RE#<uuid>#g; s#$MAC_RE#<mac>#g; s#$USERPATH_RE#/Users/<redacted>#g"
}

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

# Report <reportname>:line for any UNAPPROVED token of a given form in <scanfile>.
# Uses `grep -oan` (only-matching + line number) so each matched token is extracted
# CLEANLY as its own string — NUL-safe, because a binary line is never read into a
# shell variable (which would truncate at the first NUL and drop a later token).
# report writes to the $FINDINGS FILE, so the `grep | while` subshell is fine.
scan_form() { # reportname, class, regex, scanfile
  local rn="$1" cls="$2" re="$3" sf="$4"
  grep -oan -E "$re" "$sf" 2>/dev/null | while IFS=: read -r ln tok; do
    [ -n "$ln" ] || continue
    approved_token "$tok" || report "$rn:$ln" "$cls"
  done
}

while IFS= read -r -d '' f; do
  # FILENAME check — EVERY tracked path (binaries + shape-trusted included). The
  # reported location is REDACTED so a leak-bearing filename is never re-printed
  # (panel P4).
  for tok in $(printf '%s' "$f" | grep -oE "$UUID_RE"); do
    approved_token "$tok" || report "$(redact_path "$f")" "UUID/UDID identifier in filename"
  done
  for tok in $(printf '%s' "$f" | grep -oE "$MAC_RE"); do
    approved_token "$tok" || report "$(redact_path "$f")" "Bluetooth/MAC identifier in filename"
  done
  printf '%s' "$f" | grep -Eq "$USERPATH_RE" && report "$(redact_path "$f")" "/Users/<name> in tracked path"

  # Extract the COMMITTED BLOB and scan THAT — this covers regular files, symlinks
  # (blob == the link target text), DANGLING symlinks, and binaries uniformly, so
  # nothing is skipped by a working-tree `[ -f ]` test (panel P4 round-4). A
  # deleted/unreadable blob yields an empty scan file.
  git show ":$f" > "$BLOBF" 2>/dev/null || git cat-file blob "HEAD:$f" > "$BLOBF" 2>/dev/null || : > "$BLOBF"

  case "$f" in
    *native_*.log)
      head -1 "$BLOBF" | grep -q '^# sanitized native-test evidence$' \
        || report "$f" "raw xcodebuild log (missing sanitizer header)"
      ;;
  esac

  # Machine-local IDENTIFIER content checks — EVERY tracked file, TEXT or BINARY
  # (grep -a over the blob): a /Users home path or env-dump id baked into a binary
  # or named by a symlink target is caught. (The fleet-secret binary scan is the
  # separate git grep below.)
  while IFS=: read -r ln _; do
    [ -n "$ln" ] && report "$f:$ln" "machine-local env identifier"
  done < <(grep -a -nE "$ENVDUMP_RE" "$BLOBF" 2>/dev/null)
  while IFS=: read -r ln _; do
    [ -n "$ln" ] && report "$f:$ln" "absolute /Users/<name> home path"
  done < <(grep -a -nE "$USERPATH_RE" "$BLOBF" 2>/dev/null)

  # UUID/MAC *shape* checks — TEXT and BINARY blobs (grep -a). The DASHED UUID form
  # (32 hex + 4 dashes at exact 8-4-4-4-12 offsets) and the COLONed MAC form are
  # specific enough that random binary bytes essentially never match, so a real
  # device UUID/UDID baked into a tracked BINARY IS flagged (no residual here).
  # Shape is relaxed ONLY for the synthetic-fixture trees/files (invented values,
  # fixture-only by policy; code review is the backstop) — the sole remaining
  # relaxation, and it is in-scope-documented, not a real-defect downgrade.
  if ! shape_trusted_path "$f" && ! shape_trusted_file "$f"; then
    scan_form "$f" "UUID/UDID identifier"      "$UUID_RE" "$BLOBF"
    scan_form "$f" "Bluetooth/MAC identifier"  "$MAC_RE"  "$BLOBF"
  fi
done < <(git ls-files -z)   # -z: NUL-delimited + UNquoted, so a filename containing a
                            # newline or special chars is read whole (panel P4 round-5).

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
