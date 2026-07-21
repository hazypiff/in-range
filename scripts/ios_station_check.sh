#!/usr/bin/env bash
# Per-station field check for the iPhone feet tests (2026-07-22 protocol).
#
# Run after plugging a phone in between stations:
#   bash scripts/ios_station_check.sh 14        # walker origin phone
#   bash scripts/ios_station_check.sh 15p       # walking phone
#
# Pulls Documents/in_range_local.db over USB and summarizes the LATEST burst
# (bursts = rssi_log rows separated by >60 s gaps, i.e. beacon-off walks).
# The 90 s dwell is pocket-first then hand, so the burst splits at +45 s.
set -euo pipefail

IPHONE14="27A0976C-78DD-5D1D-926E-0CE635E5C23A"
IPHONE15P="67B16DBC-964F-592E-986C-281FED5AE8B8"

case "${1:-}" in
  14)  DEV=$IPHONE14 ;;
  15p) DEV=$IPHONE15P ;;
  *) echo "usage: $0 14|15p"; exit 1 ;;
esac

OUT="${TMPDIR:-/tmp}/station_${1}_$(date +%H%M%S).db"
xcrun devicectl device copy from --device "$DEV" --user mobile \
  --domain-type appDataContainer --domain-identifier io.inrange.inRange \
  --source Documents/in_range_local.db --destination "$OUT" >/dev/null

python3 - "$OUT" <<'PY'
import sqlite3, sys, statistics as st

rows = sqlite3.connect(sys.argv[1]).execute(
    "SELECT at_ms, rssi FROM rssi_log WHERE rssi < 0 ORDER BY at_ms").fetchall()
if not rows:
    sys.exit("no valid rssi_log rows at all")

# Split into bursts on >60 s gaps; report the latest one.
bursts, cur = [], [rows[0]]
for prev, row in zip(rows, rows[1:]):
    if row[0] - prev[0] > 60_000:
        bursts.append(cur); cur = []
    cur.append(row)
bursts.append(cur)

b = bursts[-1]
t0, t1 = b[0][0], b[-1][0]
dur = (t1 - t0) / 1000
pocket = [r for t, r in b if t - t0 < 45_000]
hand   = [r for t, r in b if t - t0 >= 45_000]

def s(xs):
    if not xs: return "NO SAMPLES"
    q = st.quantiles(xs, n=4)
    return f"median {st.median(xs):.0f} dBm  IQR {q[0]:.0f}..{q[2]:.0f}  n={len(xs)}"

print(f"bursts today-ish: {len(bursts)} | latest burst: {len(b)} samples, {dur:.0f}s")
print(f"  pocket (first 45s): {s(pocket)}")
print(f"  hand   (rest):      {s(hand)}")
if dur < 70: print("  ⚠ burst under 70s — dwell cut short? consider redoing this station")
if not pocket or not hand: print("  ⚠ one half is empty — advertising may have died (screen lock?)")
PY
