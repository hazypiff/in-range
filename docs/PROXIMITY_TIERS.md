# Proximity Tiers — Close By / Near By / In Range

Product decision (2026-07-15): proximity is surfaced as three buckets, not
feet, and **the customer picks which tier triggers their alerts** (Close By
= only the closest contacts; Near By = that tier or closer; In Range = any
detection). The tier feet below are PROVISIONAL predictions — the
calibration walks decide the final boundaries: each boundary is placed at
the largest distance where the measured RSSI distributions still separate
cleanly for our device pairings. The UI never promises feet, only tier
names.

## Tiers

Working boundaries (owner decision 2026-07-17) — contiguous, no gap:

| Tier | Range | Meaning | Radio basis |
|---|---|---|---|
| **Close by** | 0–75 ft | Nearby / same space | Strong-to-medium windowed RSSI |
| **Near by** | 76–150 ft | Same block / large venue | Weak windowed RSSI, near the detection edge |
| **In range** | 151+ ft | Detected but far (edge of range) | Beacon heard at the detection limit |

**Status: CALIBRATED (iPhone 14 ↔ iPhone 15 Plus, outdoor line-of-sight,
2026-07-17).** Tiers are **qualitative** — the UI shows the tier name, never
feet — so the feet are approximate by design; "151+" just means "far."

Outdoor RSSI-vs-distance curve (median, both directions agreed within ~2 dB):

| Distance | Median RSSI | Samples/90 s | Notes |
|---|---|---|---|
| 35 ft | −77 | 1,900 | clean |
| 65 ft | −83 | 1,760 | clean (edge of Close) |
| 110 ft | −89 | 1,510 | clean |
| 150 ft | −96 | 240–525 | weak; one earlier run read stronger |
| 175 ft | −90 | 1,540 | **still robust — BLE does NOT cut off here** |

Findings that set the tiers:
- **35–110 ft is the clean, distance-tracking zone** (monotonic ~6–7 dB/step).
  The **Close/Near boundary at 75 ft ≈ −84 dBm** is well-separated and reliable.
- **Past ~110 ft RSSI gets noisy** — 150 ft read −96 but 175 ft read −90 (6–8 dB
  station-to-station scatter from multipath/orientation). Fine for qualitative
  tiers: "Near" vs "In range" is a soft, approximate boundary, not a precise one.
- **BLE reaches well past 151 ft** (175 ft still 1,500 samples). So **"In range
  151+" lives on BLE** — the earlier "BLE dies at 150 → needs GPS" was a bad
  reading (close-range setup contamination). GPS/`miles` mode is only for the
  genuinely-far feed, not for In Range.
- **Indoors, RSSI does NOT track distance at all** at 5–25 ft (same 25 ft read
  −63 then −73; multipath dominates). Enclosed spaces are unusable for
  calibration and blur the close tiers — expected, and why Close is one wide
  0–75 bucket rather than split.

## Classification rules

1. **Windowed, bilateral RSSI** — classify on 30–60 s aggregates (median +
   variance), averaging both directions (A→B and B→A) when available. Never
   classify on a single reading.
2. **Dwell** — a tier must hold ≥30 s before being surfaced; transient
   passers-by never appear.
2b. **Conservative promotion (gray zone)** — promotion to a closer tier
   requires strong, sustained evidence; ambiguous readings in the boundary
   overlap stay in the farther tier. A trustworthy Close By alert beats a
   fast one. (UWB confirm on capable pairs, e.g. iPhone 11+, later makes
   Close By exact.)
3. **Hysteresis** — promote/demote thresholds are separated (e.g. promote to
   Close By at ≤15 ft-equivalent, demote at ≥25 ft-equivalent) so boundary
   cases don't flicker.
4. **Per-model thresholds** — RSSI cutoffs keyed by (advertiser model,
   scanner model). Calibration walks populate this table.
5. **GPS/WiFi gate unchanged** — location remains a plausibility gate (same
   venue / within combined GPS error), never a distance measurement.

## RSSI threshold table (per model)

Walk #3 (S9→S9, txPowerHigh) gives the first real row. Its lesson bounds the
whole product: RSSI is only cleanly separable in the first ~15 ft — close-range
readings were **−66…−73 dBm**, but everything from 10 to 60 ft sat flat at
**−83…−92 dBm** (20 ft even read *stronger* than 10 ft). So "Close By" is an
RSSI cutoff; "Near By" cannot be an RSSI cutoff on this hardware and is gated by
the **medium-power advertising slot** instead (medium dies at ~25 ft while high
carries past 60 ft); "In Range" is presence out to the ~60–80 ft S9 ceiling.

| Advertiser → Scanner | Close By | Near By | In Range | Source |
|---|---|---|---|---|
| S9 → S9 | median ≥ **−80 dBm** (≈ ≤10–15 ft) | heard on **medium slot** (≈ ≤25–40 ft) | any packet (≤ ~80 ft) | walk #3, provisional; walk #4 tightens |
| iPhone 14 ↔ iPhone 15 Plus | median ≥ **−84 dBm** (≤~75 ft) | **−85 to −96 dBm** (~76–150 ft) | **< −96 dBm** (151 ft → ~175–200 ceiling) | outdoor sweep 2026-07-17 (symmetric both directions) |
| iPhone 14 → S9 | TBD | TBD | TBD | needs Android scan-filter widen to 0xCAFE (issue #1) |
| S9 → iPhone 14 | TBD | TBD | TBD | needs Android scan-filter widen to 0xCAFE (issue #1) |

> **Not yet wired into runtime**: `RangeEstimator` still runs the S9-row logic
> (median ≥ −80 + medium-slot gating). The iPhone −84/−96 cutoffs above are
> calibration results only; wiring them in requires the per-model threshold
> table (rule 4) so the S9 fleet keeps its own row. Boundary convention:
> integer-dBm bands, closer tier owns its cutoff (Close ≥ −84, Near −85…−96
> inclusive, In Range < −96).

## Close By — confidence roadmap (the flagship feature)

"Get as close as possible, with high confidence" is the one tier that makes a
real *distance* claim rather than presence or co-location — which is exactly why
it is the hardest to calibrate and the most valuable to get right. The far tiers
are robust because they answer yes/no questions ("same venue?", "detectable?");
Close By is fragile because a body (−30 dB), a pocket, or phone orientation
(−20 dB) all bite hardest at short range. Three stages, increasing confidence:

1. **BLE windowed median + dwell + hysteresis (now).** Median over 30–60 s in
   both directions kills single-reading noise; ≥30 s dwell kills walk-pasts;
   separated promote/demote cutoffs kill boundary flicker. Confidently answers
   "within ~10–15 ft", not "8.3 ft".
2. **Per-model calibration (walk #4 + cross-platform).** The feet boundary is
   fixed in the product; the RSSI cutoff behind it is tuned per (advertiser,
   scanner) model pair. An iPhone in a pocket may read a tier farther — quantify
   before compensating.
3. **UWB confirmation (roadmap).** iPhone 11+ and UWB-capable Androids can
   measure *centimeter* distance with direction (the AirTag/NearbyInteraction
   radio). BLE gets a peer *into* the Close By tier; UWB turns it into an exact
   number — "3 ft, that way." This is the endgame for the flagship feature and
   why walk #4's close stops are the tightest and most repeated.

Known asymmetry to expect: iOS backgrounded advertising is weaker/overflow-
area only — a pocketed iPhone may classify one tier farther than reality.
Quantify before compensating.

## Test protocol — first cross-platform session (planned 2026-07-16)

Devices: iPhone 14 (release build, signed 2026-07-15 — valid through
2026-07-22) + Dell-managed Android(s).

1. **Smoke test**: both apps foreground, phones hand-held, 3 ft apart —
   confirm mutual token detection at all (first ever iOS↔Android contact).
2. **Static sweep** (repeat walk #4 distances, both directions): 5, 10, 15,
   20, 30, 50, 75, 100, 150 ft; 60 s per station; log windowed RSSI both
   ways. Foreground first; repeat pocketed if time allows.
3. **Boundary dwell**: hold at 20 ft and 75 ft (tier edges) for 3 min each —
   measure classification flicker rate to size hysteresis.
4. **Record station times**: note wall-clock arrive/leave time at every
   distance station (photo of a watch works). The rssi_log rows are
   timestamped; station times are how samples get labeled with true
   distance afterward. Without them the raw log can't be sliced.
5. Log everything to `run_logs/sessions/` and summarize as a journal entry in
   `DEVICE_TESTING_JOURNAL.md`.

### Post-walk data extraction (dry-run verified 2026-07-15)

iPhone (from the Mac; app must be installed, phone plugged in/trusted):
```sh
xcrun devicectl device copy from \
  --device 27A0976C-78DD-5D1D-926E-0CE635E5C23A \
  --domain-type appDataContainer --domain-identifier io.inrange.inRange \
  --source Documents/in_range_local.db \
  --destination run_logs/sessions/<date>_iphone.db
```

Android (from the Dell, as in prior walks):
```sh
adb pull $(adb shell run-as io.inrange.app sh -c 'ls /data/data/*/databases/in_range_local.db' | head -1) \
  run_logs/sessions/<date>_android.db
# or: adb root && adb pull, per device setup
```

Analysis query (per station window, per device pairing):
```sql
SELECT power, COUNT(*),
       MIN(rssi), MAX(rssi), AVG(rssi)
FROM rssi_log
WHERE at_ms BETWEEN <station_start_ms> AND <station_end_ms>
GROUP BY power;
```

Pre-walk checklist: iPhone + Android charged; Bluetooth + location granted
on both; iPhone app opens from home screen (release build); `.env` cloud
secrets — optional for this session (local logging suffices) but copy from
the Dell if server feeds are wanted.

## Recurrence — "you keep crossing paths"

Familiarity is one of the strongest signals a proximity app has: someone you've
passed 4 times this week is a far better prospect than a one-time walk-by. This
is tracked **server-side only**, by necessity — a peer's BLE token rotates every
15 minutes, so locally the same person is a new anonymous id each pass and there
is nothing to link. The server maps every token to a stable user, and the
`encounters` table is already one canonical row per pair, so recurrence builds
naturally on top.

- A **session** = one continuous crossing. A new session starts when the pair is
  seen again after a gap longer than `encounter_session_gap()` (1 h) — long
  enough that stepping away and back is the same crossing, short enough that
  meeting again after lunch counts as a second.
- `encounter_sessions` logs one row per crossing (bounded — not per packet), so
  "N times in the last 7 days" is a cheap query.
- `encounters` carries denormalized counters (`session_count`,
  `distinct_day_count`, `first_seen_at`, `last_recurrence_at`) for the feed,
  which now ranks familiar faces first and shows "Crossed paths N times".
- Each session also records the closest tier reached (`best_range`), so later we
  can distinguish "passed at a distance 5 times" from "stood Close By 5 times".

Product uses this unlocks later: familiarity ranking, "regular near you" prompts,
matching people who share a routine (same gym/coffee/commute), and safety signals
(a stranger appearing repeatedly in unusual patterns).
