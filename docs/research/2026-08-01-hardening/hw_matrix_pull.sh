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
  "$XCRUN" devicectl device copy from --device "$UDID" --user mobile \
    --domain-type appDataContainer --domain-identifier "$BUNDLE" \
    --source "Documents/$1" --destination "$RAW/$1" >/dev/null 2>&1 \
    && echo "  pulled $1" || echo "  (no $1)"
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
prev_seq, case_epoch = None, None
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
        ce = obj.get("caseEpoch")
        if not isinstance(ce, int) or isinstance(ce, bool):
            fatal(15, "missing/invalid integer 'caseEpoch' at line %d" % i)
        if case_epoch is None:
            case_epoch = ce
        elif ce != case_epoch:
            fatal(16, "caseEpoch changed within file (%r != %r) at line %d"
                  % (ce, case_epoch, i))
        for req in ("keyEpoch", "runEpoch"):
            if not isinstance(obj.get(req), int) or isinstance(obj.get(req), bool):
                fatal(17, "missing/invalid integer '%s' at line %d" % (req, i))
    elif mode == "rssi":
        if not (isinstance(obj.get("token"), str)
                and isinstance(obj.get("rssi"), int) and not isinstance(obj.get("rssi"), bool)
                and isinstance(obj.get("ts"), int) and not isinstance(obj.get("ts"), bool)):
            fatal(18, "rssi line %d must be {token:str, rssi:int, ts:int}" % i)
    out.append(json.dumps(san(obj)))
    n += 1
if n == 0:
    fatal(19, "no JSON records after parse")
open(dst, 'w').write('\n'.join(out) + '\n')
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

# --- 6. ATOMIC PUBLISH ------------------------------------------------------
# Replace the case dir's contents atomically: stage a sibling dir, then rename.
mkdir -p "$OUT_ROOT"
PUB_TMP="$(mktemp -d "$OUT_ROOT/.pub.${CASE}.XXXXXX")"
cp "$SAN"/* "$PUB_TMP"/ 2>/dev/null || true
rm -rf "$OUT"
mv "$PUB_TMP" "$OUT"

echo "Raw (uncommitted, wiped on exit): $RAW"
echo "Sanitized + validated (commit-safe): $OUT"
ls -1 "$OUT"
