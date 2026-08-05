#!/usr/bin/env bash
# Three-iPhone W5 hardware matrix — evidence puller + sanitizer (A4 strict chain).
#
# Pulls the diag-flavor structured event stream + wake log + W5 RSSI log from a
# device and writes a SANITIZED, VALIDATED copy suitable for committing to PR
# #11. Raw pulls stay in a scratch staging dir and are NEVER committed.
#
#   ./hw_matrix_pull.sh <UDID> <label> <case-name>
# e.g. ./hw_matrix_pull.sh <device-udid> iphone14 case1-third-peer
#
# STRICT STAGED PULL → VALIDATE → SANITIZE → POST-SCAN → ATOMIC PUBLISH:
#   1. The fleet run secret is validated (>= 64 even-length hex, the SAME floor
#      the native provisioner and W5Diag.handle use) BEFORE any device contact —
#      a bad secret aborts before a single byte is pulled.
#   2. Every artifact is pulled into an isolated staging dir (mktemp, wiped on
#      exit). Nothing is written to the committed tree until every check passes.
#   3. The primary artifact (w5_events.jsonl, the Case 1-3 proof) is MANDATORY:
#      absent/empty ⇒ hard fail, so a "successful" pull can't ship without the
#      evidence it exists to carry.
#   4. JSONL evidence is validated against a STRICT per-family schema and
#      sanitized in ONE pass. A malformed JSON line is a HARD FAIL — there is NO
#      regex fallback for a JSONL file (a fallback could silently emit an
#      unsanitized line). Text logs (wake) are regex-sanitized (they are not
#      JSON).
#   5. Every sanitized output is POST-SCANNED for any residual raw id (UUID or a
#      >= 32-hex run). A hit aborts the publish — sanitized handles are only 14
#      hex, so any longer hex run is an escape.
#   6. Only after ALL of the above, the staged sanitized set is published
#      ATOMICALLY into hardware_evidence/<case>/ (staged dir renamed into place).
#
# Sanitization uses the SAME keyed, run-scoped, domain-separated handle the live
# layer uses: each raw id becomes id:<14hex> = truncated HMAC-SHA256(secret,
# "<domain>\0"+raw) — identical to W5Diag.handle(domain, raw). So a token's tag
# in the committed wake/RSSI logs MATCHES its handle in the live w5_events.jsonl
# (and across fleet devices sharing the secret). FAIL-CLOSED: a valid run secret
# is REQUIRED (no unkeyed fallback).
#
# Diag flavor bundle id (issue #8 isolation):
BUNDLE="io.inrange.inRange.diag"
set -euo pipefail

UDID="${1:?UDID required}"; LABEL="${2:?label required}"; CASE="${3:?case required}"

# --- 1. VALIDATE SECRET FIRST (before any device contact) -------------------
SEC="${INRANGE_DIAG_RUN_SECRET:-}"
if ! printf '%s' "$SEC" | grep -Eq '^[0-9a-fA-F]+$' \
  || [ "${#SEC}" -lt 64 ] || [ $(( ${#SEC} % 2 )) -ne 0 ]; then
  echo "ERROR: set INRANGE_DIAG_RUN_SECRET to the diag build's fleet run secret" >&2
  echo "       — >= 64 even-length hex (256-bit). The puller refuses to touch the" >&2
  echo "       device (and to write commit-safe evidence) without it." >&2
  exit 1
fi

# xcrun is overridable for the committed test harness (fake devicectl).
XCRUN="${HW_MATRIX_XCRUN:-xcrun}"

# --- 2. ISOLATED STAGING (never the committed tree until published) ---------
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/hw_matrix.XXXXXX")"
RAW="$STAGE/raw"; SAN="$STAGE/san"
mkdir -p "$RAW" "$SAN"
trap 'rm -rf "$STAGE"' EXIT
OUT_ROOT="$(cd "$(dirname "$0")" && pwd)/hardware_evidence"
OUT="$OUT_ROOT/${CASE}"

pull() {
  # Remove any stale/partial destination first, and DELETE the destination on a
  # failed copy — devicectl can write several complete records and then exit
  # nonzero, and a partial-but-valid-prefix file would otherwise pass schema +
  # sequence validation and be published as complete evidence. A failed copy
  # therefore leaves the file ABSENT, so the mandatory-primary check aborts the
  # run rather than shipping a truncated event stream.
  rm -f "$RAW/$1"
  if "$XCRUN" devicectl device copy from --device "$UDID" --user mobile \
      --domain-type appDataContainer --domain-identifier "$BUNDLE" \
      --source "Documents/$1" --destination "$RAW/$1" >/dev/null 2>&1; then
    echo "  pulled $1"
  else
    rm -f "$RAW/$1"   # discard any partial bytes a failed copy left behind
    echo "  (no $1)"
  fi
}
for f in bb_wake_log.txt bb_wake_log.1.txt \
         w5_events.jsonl w5_events.1.jsonl \
         w5_rssi_log.jsonl w5_rssi_log.1.jsonl \
         in_range_local.db; do
  pull "$f"
done

# --- 3. MANDATORY PRIMARY ARTIFACT ------------------------------------------
if [ ! -s "$RAW/w5_events.jsonl" ]; then
  echo "ERROR: primary artifact w5_events.jsonl is missing or empty." >&2
  echo "       A pull without the structured event stream carries no Case proof" >&2
  echo "       — refusing to publish." >&2
  exit 2
fi

# --- 4. STRICT SANITIZE + VALIDATE ------------------------------------------
# JSONL evidence: hard-fail on any malformed line or schema/epoch/sequence
# violation (NO regex fallback). $1 = filename, $2 = schema mode (events|rssi).
sanitize_jsonl() {
  local f="$1" mode="$2"
  [ -f "$RAW/$f" ] || return 0
  INRANGE_JSONL_MODE="$mode" python3 - "$RAW/$f" "$SAN/${LABEL}_$f" <<'PY'
import sys, os, re, json, hmac, hashlib
src, dst, mode = sys.argv[1], sys.argv[2], os.environ["INRANGE_JSONL_MODE"]
key = bytes.fromhex(os.environ["INRANGE_DIAG_RUN_SECRET"])
def h(domain, raw):  # == W5Diag.handle(domain, raw): trunc HMAC-SHA256, 14 hex
    return "id:" + hmac.new(key, domain.encode() + b"\x00" + raw.encode(),
                            hashlib.sha256).digest()[:7].hex()
HEX = re.compile(r'^(?:[0-9a-fA-F]{32}|'
                 r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
                 r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$')
FIELD_DOMAIN = {"token": "peer", "peer": "peer", "lease": "lease",
                "link": "link", "peripheral": "peripheral"}
def san(o):  # domain-aware id hashing, recursive
    if isinstance(o, dict):
        return {k: (h(FIELD_DOMAIN[k], v)
                    if k in FIELD_DOMAIN and isinstance(v, str) and HEX.match(v)
                    else san(v)) for k, v in o.items()}
    if isinstance(o, list):
        return [san(x) for x in o]
    return o
def fatal(code, msg):
    sys.stderr.write("FATAL(%s): %s [%s]\n" % (code, msg, os.path.basename(src)))
    sys.exit(code)
out, n = [], 0
prev_seq = None
const_epochs = {}   # caseEpoch / keyEpoch / runEpoch must be constant in a file
for i, line in enumerate(open(src, 'r', errors='replace'), start=1):
    s = line.rstrip('\n')
    if not s:
        continue
    try:
        obj = json.loads(s)               # NO regex fallback for JSONL
    except Exception as e:
        fatal(11, "malformed JSON at line %d: %s" % (i, e))
    if not isinstance(obj, dict):
        fatal(12, "line %d is not a JSON object" % i)
    if mode == "events":
        seq = obj.get("seq")
        if not isinstance(seq, int) or isinstance(seq, bool):
            fatal(13, "missing/invalid integer 'seq' at line %d" % i)
        if prev_seq is not None and seq <= prev_seq:
            fatal(14, "non-increasing seq (%r after %r) at line %d"
                  % (seq, prev_seq, i))
        prev_seq = seq
        # caseEpoch, keyEpoch, and runEpoch are ALL constant within one evidence
        # file: any case reset / key rotation / run reset WIPES the files, so a
        # single file can never legitimately mix epochs. Enforce constancy (not
        # merely the type) so an epoch-mixed stream cannot pass as a valid chain.
        for req in ("caseEpoch", "keyEpoch", "runEpoch"):
            v = obj.get(req)
            if not isinstance(v, int) or isinstance(v, bool):
                fatal(15, "missing/invalid integer '%s' at line %d" % (req, i))
            if req not in const_epochs:
                const_epochs[req] = v
            elif v != const_epochs[req]:
                fatal(16, "%s changed within file (%r != %r) at line %d"
                      % (req, v, const_epochs[req], i))
    elif mode == "rssi":
        if not (isinstance(obj.get("token"), str)
                and isinstance(obj.get("rssi"), int) and not isinstance(obj.get("rssi"), bool)
                and isinstance(obj.get("ts"), int) and not isinstance(obj.get("ts"), bool)):
            fatal(18, "rssi line %d must be {token:str, rssi:int, ts:int}" % i)
    out.append(json.dumps(san(obj)))
    n += 1
if n == 0 and mode == "events":
    # The primary event stream MUST carry records (a zero-record events file is
    # indistinguishable from a lost/tampered pull). A non-primary family (e.g.
    # RSSI on a case with no drains) may legitimately be empty — publish it empty
    # rather than conflating "empty" with "corrupt".
    fatal(19, "no JSON records after parse in the primary event stream")
open(dst, 'w').write('\n'.join(out) + ('\n' if out else ''))
print("  sanitized(%s) -> %s (%d records)" % (mode, os.path.basename(dst), n))
PY
}

# Text logs: bare-hex → peer-domain handle. Regex is CORRECT here (not JSON).
sanitize_text() {
  local f="$1"
  [ -f "$RAW/$f" ] || return 0
  python3 - "$RAW/$f" "$SAN/${LABEL}_$f" <<'PY'
import sys, os, re, hmac, hashlib
src, dst = sys.argv[1], sys.argv[2]
key = bytes.fromhex(os.environ["INRANGE_DIAG_RUN_SECRET"])
def h(domain, raw):
    return "id:" + hmac.new(key, domain.encode() + b"\x00" + raw.encode(),
                            hashlib.sha256).digest()[:7].hex()
def bare(m):
    return h("peer", m.group(0))
UUID = re.compile(r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
                  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')
BHEX = re.compile(r'\b[0-9a-fA-F]{32}\b')
out = []
for line in open(src, 'r', errors='replace'):
    s = line.rstrip('\n')
    s = UUID.sub(bare, s)
    s = BHEX.sub(bare, s)
    out.append(s)
open(dst, 'w').write('\n'.join(out) + ('\n' if out else ''))
print("  sanitized(text) -> %s" % os.path.basename(dst))
PY
}

sanitize_jsonl w5_events.jsonl    events   # mandatory (checked above)
sanitize_jsonl w5_events.1.jsonl  events
sanitize_jsonl w5_rssi_log.jsonl  rssi
sanitize_jsonl w5_rssi_log.1.jsonl rssi
sanitize_text  bb_wake_log.txt
sanitize_text  bb_wake_log.1.txt

# Cross-file CHAIN validation for the event stream: a `.dotOne` rotation happens
# WITHIN one case (a case reset wipes both files), so the rotated `.1` records
# must share the SAME caseEpoch as the current file AND have strictly LOWER seq
# than every current record. Validating each file in isolation would let a
# conflicting epoch or an overlapping/decreasing seq across the boundary slip
# through — so the chain is checked end to end here.
if [ -f "$SAN/${LABEL}_w5_events.1.jsonl" ]; then
  python3 - "$SAN/${LABEL}_w5_events.1.jsonl" "$SAN/${LABEL}_w5_events.jsonl" <<'PY'
import sys, json
def bounds(p):
    seqs = []
    ep = {"caseEpoch": set(), "keyEpoch": set(), "runEpoch": set()}
    for line in open(p):
        line = line.strip()
        if not line:
            continue
        o = json.loads(line)
        seqs.append(o["seq"])
        for k in ep:
            ep[k].add(o[k])
    return min(seqs), max(seqs), ep
o_min, o_max, o_ep = bounds(sys.argv[1])   # rotated (older)
c_min, c_max, c_ep = bounds(sys.argv[2])   # current (newer)
# All three epochs must match across the rotation — a rotation is size-based
# within ONE {case,key,run} epoch; any epoch change would have wiped both files.
for k in ("caseEpoch", "keyEpoch", "runEpoch"):
    if o_ep[k] != c_ep[k]:
        sys.stderr.write("FATAL(21): %s differs across rotation %r vs %r\n"
                         % (k, o_ep[k], c_ep[k])); sys.exit(21)
if not (o_max < c_min):
    sys.stderr.write("FATAL(22): rotated max seq %d not < current min seq %d\n"
                     % (o_max, c_min)); sys.exit(22)
PY
  rc=$?
  [ "$rc" -ne 0 ] && exit "$rc"
fi

# --- 5. RAW-ID POST-SCAN (defence in depth) ---------------------------------
# A sanitized handle is `id:<14hex>`. Any UUID or >= 32-hex run in the output is
# an un-sanitized id — abort the publish rather than commit a leak.
if grep -rEln \
  '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})|[0-9a-fA-F]{32,}' \
  "$SAN" >/dev/null 2>&1; then
  echo "ERROR: residual raw id detected in sanitized output — refusing to publish:" >&2
  grep -rEln \
    '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})|[0-9a-fA-F]{32,}' \
    "$SAN" >&2 || true
  exit 3
fi

# --- 6. ATOMIC PUBLISH (symlink swap) ---------------------------------------
# `<case>` is a SYMLINK to a versioned data dir. Publishing = build the full new
# data dir, then repoint the symlink with a SINGLE rename(2). rename is atomic
# and replaces the prior symlink in place, so there is NEVER a moment where
# `<case>` is absent or half-written — a concurrent reader, a committer, or a
# process kill always sees either the old complete evidence or the new complete
# evidence, never nothing. The prior data dir is removed only AFTER the swap.
mkdir -p "$OUT_ROOT"
REV="$(mktemp -d "${OUT}.rev.XXXXXX")"   # fresh versioned data dir for this run
# Fail closed on a staging-copy error (disk full, permission, transient I/O) —
# never publish a partial revision, and re-assert the mandatory primary is
# actually present in the staged rev before it can be swapped into place.
if ! cp "$SAN"/* "$REV"/; then
  rm -rf "$REV"
  echo "ERROR: staging copy failed — refusing to publish partial evidence." >&2
  exit 5
fi
if [ ! -s "$REV/${LABEL}_w5_events.jsonl" ]; then
  rm -rf "$REV"
  echo "ERROR: primary artifact missing from the staged revision." >&2
  exit 5
fi
PREV_REV=""
[ -L "$OUT" ] && PREV_REV="$(readlink "$OUT")"
# One-time migration: an older puller may have left `<case>` as a REAL dir. A
# symlink cannot rename-replace a non-empty dir, so PRESERVE the legacy evidence
# by renaming it into a versioned rev (a dir→dir rename, atomic) — never delete
# it. The brief absence of `<case>` is bounded to this one-time upgrade.
if [ -e "$OUT" ] && [ ! -L "$OUT" ]; then
  mv "$OUT" "${OUT}.rev.legacy.$$"
fi
LINKTMP="${OUT}.link.$$"
ln -s "$(basename "$REV")" "$LINKTMP"
# Swap with rename(2) via python os.replace: it operates on the PATH and never
# follows the destination symlink (unlike `mv`, which would move LINKTMP INTO
# the old rev dir when `<case>` is a symlink-to-dir). Atomic; replaces the prior
# `<case>` symlink in place with no absent/half-written interval.
if python3 -c 'import os,sys; os.replace(sys.argv[1], sys.argv[2])' \
    "$LINKTMP" "$OUT"; then
  # Remove the superseded rev — but ONLY if its name is a bare, expected local
  # basename (`<case>.rev.*`, no slash, no `..`). A tampered/relative symlink
  # target must never let this `rm -rf` escape OUT_ROOT.
  if [ -n "$PREV_REV" ] && [ "$PREV_REV" != "$(basename "$REV")" ] \
     && [ "$PREV_REV" = "$(basename "$PREV_REV")" ]; then
    case "$PREV_REV" in
      *..*) : ;;                                   # reject any '..'
      "$(basename "$OUT").rev."*)
        [ -d "${OUT_ROOT}/${PREV_REV}" ] && rm -rf "${OUT_ROOT}/${PREV_REV}" ;;
    esac
  fi
else
  rm -rf "$LINKTMP" "$REV"
  echo "ERROR: publish swap failed; prior evidence untouched." >&2
  exit 4
fi

echo "Raw (uncommitted, wiped on exit): $RAW"
echo "Sanitized + validated (commit-safe): $OUT -> $(readlink "$OUT")"
ls -1 "$OUT"
