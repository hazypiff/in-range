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
RAW="/private/tmp/claude-501/-Users-artigupta/hw_matrix_raw/${CASE}_${LABEL}"
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
sanitize() {
  local f="$1"
  [ -f "$RAW/$f" ] || return 0
  INRANGE_DIAG_RUN_SECRET="${INRANGE_DIAG_RUN_SECRET:-}" python3 - "$RAW/$f" "$OUT/${LABEL}_$f" <<'PY'
import sys, os, re, hmac, hashlib
src, dst = sys.argv[1], sys.argv[2]
sec = os.environ.get("INRANGE_DIAG_RUN_SECRET", "")
key = bytes.fromhex(sec) if len(sec) >= 32 else None
if key is None:
    sys.stderr.write("  WARN: no INRANGE_DIAG_RUN_SECRET; unkeyed tags won't align with live handles\n")
def tag(m):
    raw = m.group(0)
    if key is not None:  # keyed, run-scoped: matches W5Diag.handle("peer", raw)
        mac = hmac.new(key, b"peer\x00" + raw.encode(), hashlib.sha256).digest()
        return "id:" + mac[:7].hex()  # 14 hex
    return "id:" + hashlib.sha256(raw.lower().encode()).hexdigest()[:6]
data = open(src, 'r', errors='replace').read()
# UUID-format first (longer, more specific), then bare 32-hex.
data = re.sub(r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', tag, data)
data = re.sub(r'\b[0-9a-fA-F]{32}\b', tag, data)
open(dst, 'w').write(data)
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
