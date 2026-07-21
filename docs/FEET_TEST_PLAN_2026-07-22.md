# Feet Test Plan — 2026-07-22 (iPhone 14 ↔ iPhone 15 Plus)

Goal: pick the FINAL tier boundaries — Close / middle tier / In Range — and
prove they hold up outside the open-field ideal. The 2026-07-17 sweep gave the
baseline curve (open field, line of sight, phone in hand); tomorrow answers
the question that curve can't: **do the boundaries survive real streets and
real carry?**

> Naming confirmed by owner 2026-07-21: **Close By (1–75 ft) · Near By
> (76–150 ft) · In Range (151+)** — three user-pickable tiers, never shown
> as feet in the UI. No rename.

## Baseline being tested (from 2026-07-17, docs/PROXIMITY_TIERS.md)

Close 0–75 ft = RSSI ≥ −84 · Middle 76–150 ft = −84…−96 · In Range 151+ = < −96.
Curve: 35 ft/−77 · 65/−83 · 110/−89 · 150/−96 · 175/−90 (that 175 reading is
the noisy tail — past ~110 ft expect ±6–8 dB).

## Prep (before leaving — DO NOT SKIP)

1. **Swap both phones to RELEASE builds.** Debug builds will not launch
   untethered on iOS. Rebuild with `.env` defines, install, launch, verify the
   beacon toggles ON on both.
2. Both phones 100% + a battery pack. Bluetooth on, Low Power Mode OFF.
3. Hotspot or phone data available so rssi_log can cloud-sync between
   sessions (local logging works offline; sync is for safety).
4. Distance measure: pace calibration — walk a known 50 ft (football field /
   measuring app), count steps, write your ft-per-step down. Precision within
   ±5 ft is fine; tiers are qualitative.
5. Paper or notes app for the station log: `session / distance / start–stop
   time / notes`. The station log is what makes extract_walk slicing work.

## Method rules (proven 07-17, keep identical)

- Beacon ON **only while at a station** — walk between stations with both
  beacons OFF (prevents close-range contamination of far-station data).
- Arrive at station → 10 s settle → dwell → beacons OFF → note the times.
- **Split dwell at EVERY station (owner decision 2026-07-21): ~45 s phone in
  hand (chest height, facing the origin), then ~45 s phone in pocket, still
  facing the origin. Note the hand→pocket switch time at each station.**
  In-hand gives the physics curve (comparable to 07-17); pocket gives the
  real-carry curve — final RSSI thresholds get picked from the POCKET curve,
  with the in-hand curve as the sanity reference.
- One phone (14) stays at the origin, propped in the open (controlled
  anchor — do NOT pocket the origin phone except where Session D says so).
- Log everything in the station log; when in doubt, write it down.

## Sessions ("all over" = 3 environments + a carry overlay)

### Session A — Open field, line of sight (~45 min)
Purpose: re-verify the baseline + densify around the candidate boundaries.
Stations (ft), 90 s each: **10 · 25 · 50 · 65 · 75 · 90 · 110 · 130 · 150 · 175 · 200**
(dense around 65–90 and 130–175 because that's where the two boundaries live;
200 probes the true edge — 175 was still strong on 07-17).

### Session B — Sidewalk / street clutter (~30 min)
Purpose: parked cars, poles, people — does the middle band survive clutter?
Stations, 60 s each: **25 · 50 · 75 · 100 · 125 · 150 · 175**
Straight stretch of sidewalk, stay line-of-sight where possible.

### Session C — Park with trees / courtyard (~30 min)
Purpose: soft obstruction + one deliberate non-line-of-sight point.
Stations, 60 s each: **25 · 50 · 75 · 100 · 125 · 150**, plus ONE station at
~75 ft with a tree/corner directly between phones (mark it "NLOS" in the log).

### Session D — Worst-case overlay (~15 min, can fold into Session A)
Pocket-carry is now baked into every station via the split dwell, so this
session covers the two remaining worst cases:
- At **50, 100, 150 ft**: 45 s in hand but back turned (body block).
- At **75 and 150 ft** (the two boundary distances): 45 s with BOTH phones
  pocketed — origin 14 in a pocket too. This is the true worst case and the
  margin check on the tier boundaries.
Log each sub-condition separately. Expect 5–10 dB extra loss.

Total field time ≈ 2–2.5 h including walking and resets.

## After (back at the Mac)

1. Pull both phones' DBs, run `scripts/extract_walk.py` per session against
   the station log (same flow as 07-17; filter rssi < 0, 127 = invalid).
2. Per station, per direction, per carry condition (hand vs pocket): median +
   IQR — the split-dwell times in the station log separate the two. Both
   directions should agree within ~2 dB like last time — if not, flag it.
3. **Boundary rule (unchanged from the spec):** each boundary goes at the
   largest distance where adjacent stations' RSSI distributions still separate
   cleanly — but now judged across ALL sessions, with Session D's loss as the
   margin check. If street/carry data collapses the 150 ft edge, the middle
   boundary moves down; better honest-tight than optimistic-loose.
4. Deliverables: updated curve tables (per environment) in
   docs/PROXIMITY_TIERS.md, final locked boundaries + RSSI thresholds, and a
   session entry in docs/DEVICE_TESTING_JOURNAL.md.

## Abort/retry notes

- Rain or a crowded field: reschedule Session A rather than pollute the data.
- If a beacon wedges (CoreBluetooth after many on/off cycles): restart the
  phone — known 07-17 behavior, not a bug to debug in the field.
- If a station's samples look wild (>±10 dB IQR), redo that one station
  before moving on; 90 extra seconds beats a redo trip.
