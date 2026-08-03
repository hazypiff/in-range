#!/usr/bin/env bash
# Three-iPhone W5 hardware matrix — evidence puller + sanitizer.
# Pulls the diag-flavor wake log + W5 RSSI log + local DB from a device and
# writes a SANITIZED copy (tokens/hex ids truncated) suitable for committing to
# PR #11. Raw pulls stay in the scratchpad and are NEVER committed.
#
#   ./hw_matrix_pull.sh <UDID> <label> <case-name>
# e.g. ./hw_matrix_pull.sh 99B56AAB-... iphone14 case1-third-peer
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
pull bb_wake_log.txt
pull w5_rssi_log.jsonl
pull in_range_local.db

# Sanitize: replace any 32-hex token / 16-byte id with a stable short hash tag,
# so co-presence/timeline structure survives but no raw identifier is exposed.
sanitize() {
  local f="$1"
  [ -f "$RAW/$f" ] || return 0
  python3 - "$RAW/$f" "$OUT/${LABEL}_$f" <<'PY'
import sys, re, hashlib
src, dst = sys.argv[1], sys.argv[2]
def tag(m):
    h = hashlib.sha256(m.group(0).encode()).hexdigest()[:6]
    return f"id:{h}"
data = open(src, 'r', errors='replace').read()
data = re.sub(r'\b[0-9a-fA-F]{32}\b', tag, data)   # 16-byte hex ids/tokens
open(dst, 'w').write(data)
print(f"  sanitized -> {dst}")
PY
}
sanitize bb_wake_log.txt
sanitize w5_rssi_log.jsonl

echo "Raw (uncommitted): $RAW"
echo "Sanitized (commit-safe): $OUT"
