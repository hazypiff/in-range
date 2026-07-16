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

| Tier | Target range | Meaning | Radio basis |
|---|---|---|---|
| **Close by** | ~0–20 ft | Same-conversation distance | Strong, stable windowed RSSI; UWB-confirmable later (iPhone 11+ / UWB Androids) |
| **Near by** | ~20–75 ft | Same room / patio / storefront | Medium windowed RSSI |
| **In range** | ~75 ft → detection limit | Detectable at all ("they're around") | Beacon heard; no finer distance claim |

Rationale: nearly all of BLE RSSI's distance resolution lives in the first
~50 ft (log-distance path loss). Boundaries beyond ~75 ft are not
distinguishable by signal strength; "in range" therefore means detection
itself. Phone-to-phone detection ceiling is ~100–200 ft line-of-sight
outdoors, and ~30–80 ft with bodies/pockets/indoors — there is no reliable
"200+ ft" tier on this hardware.

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

## RSSI threshold table (to be filled by calibration)

| Advertiser → Scanner | Close By ≤ ft | promote / demote dBm | Near By ≤ ft | promote / demote dBm |
|---|---|---|---|---|
| S9 → S9 | 20 | TBD / TBD | 75 | TBD / TBD |
| iPhone 14 → S9 | 20 | TBD / TBD | 75 | TBD / TBD |
| S9 → iPhone 14 | 20 | TBD / TBD | 75 | TBD / TBD |
| iPhone 14 → iPhone 14 | 20 | TBD / TBD | 75 | TBD / TBD |

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
4. Log everything to `run_logs/sessions/` and summarize as a journal entry in
   `DEVICE_TESTING_JOURNAL.md`.

Pre-walk checklist: iPhone + Android charged; Bluetooth + location granted
on both; iPhone app opens from home screen (release build); `.env` cloud
secrets — optional for this session (local logging suffices) but copy from
the Dell if server feeds are wanted.
