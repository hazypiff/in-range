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

# Sanitize: replace any raw identifier with a STABLE short hash tag, so
# co-presence/timeline structure survives but no raw id is exposed. Matches both
# 32-hex tokens/16-byte ids AND UUID-format CoreBluetooth peripheral handles
# (the previous regex missed UUIDs, which is how raw h=out:<uuid> reached the
# committed logs). Same raw → same tag, so cross-file correlation is preserved.
sanitize() {
  local f="$1"
  [ -f "$RAW/$f" ] || return 0
  python3 - "$RAW/$f" "$OUT/${LABEL}_$f" <<'PY'
import sys, re, hashlib
src, dst = sys.argv[1], sys.argv[2]
def tag(m):
    h = hashlib.sha256(m.group(0).lower().encode()).hexdigest()[:6]
    return f"id:{h}"
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
