#!/usr/bin/env bash
# Deterministically derive a privacy-sanitized native-test evidence file from a
# RAW xcodebuild log. The raw log is NEVER committed; only this derivative is.
#
#   sanitize_native_log.sh <raw.log> <SOURCE_SHA> <SCHEME-LABEL>   > out.sanitized.log
#
# DESIGN: allowlist, not denylist. A raw `xcodebuild test` log is >90% machine
# -local noise (an env dump with absolute paths, a simulator UDID, terminal and
# launch session identifiers, per-run timestamps, compiler invocations). Rather
# than hunt every leak in that noise, this extractor emits ONLY the evidence-
# bearing lines and drops everything else by construction:
#
#   * Test Suite '<name>' started / passed / failed
#   * Test Case  '<name>' passed / failed / skipped
#   * Executed N tests, with M failures ...            (per-suite + aggregate)
#   * ** TEST SUCCEEDED **  /  ** TEST FAILED **
#
# Those lines carry test NAMES and COUNTS only — no user data. As defense in
# depth, each kept line is still passed through redact() so that a machine-local
# token can never ride along on a test name. Output is a pure function of
# (raw bytes, SOURCE_SHA, SCHEME) and is therefore recomputable: re-running the
# sanitizer on the same raw input reproduces byte-identical output and hash.
#
# Preserved for the gate (scripts/assert_native_tests.sh parses these): the
# per-test pass/fail result lines, the reconciled Executed-summary lines, and
# the overall build result. Removed: per-run timings and suite start timestamps
# (they vary and carry no evidentiary value), plus all env/path/identifier noise.
set -euo pipefail

RAW="${1:?raw log path required}"
SHA="${2:?source SHA required}"
SCHEME="${3:?scheme label required}"

[ -f "$RAW" ] || { echo "sanitize: raw log missing: $RAW" >&2; exit 2; }

# --- redact(): strip any machine-local token; longest/most-specific first. -----
# This runs ONLY over already-allowlisted evidence lines, never the header, so
# the intentional 40-hex SOURCE_SHA in the header is not clobbered.
redact() {
  sed -E \
    -e 's#/Users/[A-Za-z0-9._+-]+#/Users/<redacted>#g' \
    -e 's#/private/var/folders/[A-Za-z0-9._/+-]+#<tmp>#g' \
    -e 's#/var/folders/[A-Za-z0-9._/+-]+#<tmp>#g' \
    -e 's#[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}#<uuid>#g' \
    -e 's#([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}#<mac>#g' \
    -e 's#[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?#<ts>#g' \
    -e 's#[0-9A-Fa-f]{64}#<hex64>#g' \
    -e 's#[0-9A-Fa-f]{40}#<hex40>#g'
}

RAW_SHA256="$(shasum -a 256 "$RAW" | awk '{print $1}')"

# --- header (trusted; not passed through redact) -------------------------------
printf '# sanitized native-test evidence\n'
printf '# derived_by: sanitize_native_log.sh v1 (allowlist extraction)\n'
printf '# source_sha: %s\n' "$SHA"
printf '# scheme: %s\n' "$SCHEME"
printf '# raw_input_sha256: %s\n' "$RAW_SHA256"
printf '# note: derivative only — the raw xcodebuild log is never committed; kept in protected scratch and removed after validation.\n'
printf '#\n'

# --- allowlisted evidence lines ------------------------------------------------
grep -E \
  "Test Suite '.*' (started|passed|failed)|Test [Cc]ase '.*' (passed|failed|skipped)|Executed [0-9]+ tests?, with [0-9]+ failures?|\*\* TEST (SUCCEEDED|FAILED) \*\*" \
  "$RAW" | redact
