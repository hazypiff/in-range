# Proximity Tiers — Close By / Near By / In Range

Product decision (2026-07-15): proximity is surfaced as three buckets, not
feet. Feet boundaries are fixed in the product; the RSSI cutoffs that
implement them are per-device-model and come from calibration walks.

## Tiers

| Tier | Target range | Meaning | Radio basis |
|---|---|---|---|
| **Close by** | 1–100 ft | Same immediate area | Strong-to-medium windowed RSSI |
| **Near by** | 101–200 ft | Same block / large venue | Weak windowed RSSI |
| **In range** | 201+ ft | Detectable at the edge | Beacon heard at detection limit |

Boundaries set by product decision 2026-07-15 (owner call). **Known physics
risk to validate on the first walk:** BLE RSSI resolution concentrates in
the first ~50 ft (log-distance path loss), so 100 vs 200 ft separation by
signal strength is expected to be marginal; and phone-to-phone detection
ceiling is ~100–200 ft line-of-sight outdoors (30–80 ft with bodies/
pockets/indoors), so the 201+ ft tier may rarely trigger on this hardware.
The 2026-07-16 protocol includes stations to 250 ft specifically to
measure both. If the data shows the boundaries aren't separable, revisit
here with the measured curves.

## Classification rules

1. **Windowed, bilateral RSSI** — classify on 30–60 s aggregates (median +
   variance), averaging both directions (A→B and B→A) when available. Never
   classify on a single reading.
2. **Dwell** — a tier must hold ≥30 s before being surfaced; transient
   passers-by never appear.
3. **Hysteresis** — promote/demote thresholds are separated (e.g. promote to
   Close By at ≤85 ft-equivalent, demote at ≥115 ft-equivalent) so boundary
   cases don't flicker.
4. **Per-model thresholds** — RSSI cutoffs keyed by (advertiser model,
   scanner model). Calibration walks populate this table.
5. **GPS/WiFi gate unchanged** — location remains a plausibility gate (same
   venue / within combined GPS error), never a distance measurement.

## RSSI threshold table (to be filled by calibration)

| Advertiser → Scanner | Close By ≤ ft | promote / demote dBm | Near By ≤ ft | promote / demote dBm |
|---|---|---|---|---|
| S9 → S9 | 100 | TBD / TBD | 200 | TBD / TBD |
| iPhone 14 → S9 | 100 | TBD / TBD | 200 | TBD / TBD |
| S9 → iPhone 14 | 100 | TBD / TBD | 200 | TBD / TBD |
| iPhone 14 → iPhone 14 | 100 | TBD / TBD | 200 | TBD / TBD |

Known asymmetry to expect: iOS backgrounded advertising is weaker/overflow-
area only — a pocketed iPhone may classify one tier farther than reality.
Quantify before compensating.

## Test protocol — first cross-platform session (planned 2026-07-16)

Devices: iPhone 14 (release build, signed 2026-07-15 — valid through
2026-07-22) + Dell-managed Android(s).

1. **Smoke test**: both apps foreground, phones hand-held, 3 ft apart —
   confirm mutual token detection at all (first ever iOS↔Android contact).
2. **Static sweep** (both directions): 5, 25, 50, 75, 100, 125, 150, 175,
   200, 225, 250 ft; 60 s per station; log windowed RSSI both ways AND
   whether detection happens at all per station (the 200+ stations test the
   In Range tier's viability). Foreground first; repeat pocketed if time
   allows. Needs an open outdoor area ≥250 ft (park/field).
3. **Boundary dwell**: hold at 100 ft and 200 ft (tier edges) for 3 min
   each — measure classification flicker rate to size hysteresis.
4. Log everything to `run_logs/sessions/` and summarize as a journal entry in
   `DEVICE_TESTING_JOURNAL.md`.

Pre-walk checklist: iPhone + Android charged; Bluetooth + location granted
on both; iPhone app opens from home screen (release build); `.env` cloud
secrets — optional for this session (local logging suffices) but copy from
the Dell if server feeds are wanted.
