#!/usr/bin/env bash
# Three-iPhone W5 hardware matrix — evidence puller + sanitizer.
# Pulls the diag-flavor wake log + W5 RSSI log + local DB from a device and
# writes a SANITIZED copy (tokens/hex ids truncated) suitable for committing to
# PR #11. Raw pulls stay in the scratchpad and are NEVER committed.
#
#   ./hw_matrix_pull.sh <UDID> <label> <case-name>
# e.g. ./hw_matrix_pull.sh <device-udid> iphone14 case1-third-peer
#
# Diag flavor bundle id (issue #8 isolation):
BUNDLE="io.inrange.inRange.diag"
set -euo pipefail

UDID="${1:?UDID required}"; LABEL="${2:?label required}"; CASE="${3:?case required}"
RAW="${HW_MATRIX_RAW_DIR:-${TMPDIR:-/tmp}/hw_matrix_raw}/${CASE}_${LABEL}"
OUT="$(cd "$(dirname "$0")" && pwd)/hardware_evidence/${CASE}"
mkdir -p "$RAW" "$OUT"

pull() {
  xcrun devicectl device copy from --device "$UDID" --user mobile \
    --domain-type appDataContainer --domain-identifier "$BUNDLE" \
    --source "Documents/$1" --destination "$RAW/$1" >/dev/null 2>&1 \
    && echo "  pulled $1" || echo "  (no $1)"
}
# B4 evidence extraction: pull the STRUCTURED events JSONL (the Case 1-3 proof)
# and EVERY rotated file too — the previous puller silently dropped w5_events.*
# and the .1 rotations, so a real run's primary evidence never left the device.
pull bb_wake_log.txt
pull bb_wake_log.1.txt
pull w5_events.jsonl
pull w5_events.1.jsonl
pull w5_rssi_log.jsonl
pull w5_rssi_log.1.jsonl
pull in_range_local.db

# Sanitize with the SAME keyed, run-scoped handle the live layer uses. Set
# INRANGE_DIAG_RUN_SECRET to the fleet run secret the diag build was built with
# (dart-define), and each raw id becomes id:<14hex> = truncated
# HMAC-SHA256(secret, "peer\0"+raw) — identical to W5Diag.handle("peer", raw).
# So a token's tag in the committed wake/RSSI logs MATCHES its handle in the
# live w5_events.jsonl (and across fleet devices sharing the secret). Without a
# secret it falls back to an unkeyed sha256[:6] tag (still stable, but NOT
# aligned with the live handles) and warns. Matches UUID-format ids AND 32-hex.
# FAIL-CLOSED: a valid run secret is REQUIRED (no unkeyed fallback — that was
# fail-open and produced tags that don't align with live handles). The sanitizer
# is DOMAIN-AWARE: JSON id fields are hashed under their live domain
# (peer/lease/link/peripheral), and bare hex in text logs is hashed as `peer`
# (the only raw id class those logs carry — RSSI/wake peer tokens).
if [ -z "${INRANGE_DIAG_RUN_SECRET:-}" ] || [ "${#INRANGE_DIAG_RUN_SECRET}" -lt 32 ]; then
  echo "ERROR: set INRANGE_DIAG_RUN_SECRET (the diag build's run secret, >=32 hex)." >&2
  echo "       The puller refuses to write commit-safe evidence without it." >&2
  exit 1
fi
sanitize() {
  local f="$1"
  [ -f "$RAW/$f" ] || return 0
  python3 - "$RAW/$f" "$OUT/${LABEL}_$f" <<'PY'
import sys, os, re, json, hmac, hashlib
src, dst = sys.argv[1], sys.argv[2]
key = bytes.fromhex(os.environ["INRANGE_DIAG_RUN_SECRET"])
def h(domain, raw):  # == W5Diag.handle(domain, raw): trunc HMAC-SHA256, 14 hex
    return "id:" + hmac.new(key, domain.encode() + b"\x00" + raw.encode(),
                            hashlib.sha256).digest()[:7].hex()
HEX = re.compile(r'^(?:[0-9a-fA-F]{32}|[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$')
FIELD_DOMAIN = {"token": "peer", "peer": "peer", "lease": "lease",
                "link": "link", "peripheral": "peripheral"}
def sanitize_json_obj(o):
    if isinstance(o, dict):
        return {k: (h(FIELD_DOMAIN[k], v) if k in FIELD_DOMAIN and isinstance(v, str)
                    and HEX.match(v) else sanitize_json_obj(v)) for k, v in o.items()}
    if isinstance(o, list):
        return [sanitize_json_obj(x) for x in o]
    return o
def bare(m):  # bare hex in text logs → peer domain (only raw class those carry)
    return h("peer", m.group(0))
out = []
for line in open(src, 'r', errors='replace'):
    s = line.rstrip('\n')
    try:  # JSONL → domain-aware by field
        out.append(json.dumps(sanitize_json_obj(json.loads(s))))
    except Exception:  # plain text → bare-hex as peer
        s = re.sub(r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', bare, s)
        s = re.sub(r'\b[0-9a-fA-F]{32}\b', bare, s)
        out.append(s)
open(dst, 'w').write('\n'.join(out) + ('\n' if out else ''))
print(f"  sanitized -> {dst}")
PY
}
sanitize bb_wake_log.txt
sanitize bb_wake_log.1.txt
sanitize w5_events.jsonl
sanitize w5_events.1.jsonl
sanitize w5_rssi_log.jsonl
sanitize w5_rssi_log.1.jsonl

echo "Raw (uncommitted): $RAW"
echo "Sanitized (commit-safe): $OUT"
