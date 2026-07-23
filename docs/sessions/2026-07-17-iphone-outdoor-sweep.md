# 2026-07-17 — iPhone outdoor high-distance sweep (calibration results)

Outdoor sweep iPhone 14 ↔ iPhone 15 Plus, symmetric both directions.
Full curve, journal, and tier decision live in the app repo
(`~/in-range` `docs/PROXIMITY_TIERS.md` + `docs/DEVICE_TESTING_JOURNAL.md`,
commits `65c0324` / `4957640`); this note records the outcome on the
calibration side.

## Measured curve (median RSSI dBm)

| ft | 35 | 65 | 110 | 150 | 175 |
|---|---|---|---|---|---|
| dBm | −77 | −83 | −89 | −96 | −90 |

- 35–110 ft is the clean monotonic zone (~6–7 dB/step).
- Past ~110 ft it's noisy: **175 ft read −90, stronger than 150 ft's −96**
  (multipath/orientation scatter). The far boundary is qualitative, not a
  precise cutoff.
- BLE reaches past 151 ft (175 ft still ~1,500 samples), so the far tier
  stays BLE-based — no GPS needed for "In Range".

## Tier cutoffs (locked 2026-07-17, boundary fix 2026-07-18)

Integer-dBm bands, **closer tier owns its cutoff** (the original write-up
had −84 in both Close and Near; corrected):

| Tier | Feet | RSSI (iPhone 14 ↔ 15 Plus row) |
|---|---|---|
| Close | 0–75 | ≥ −84 |
| Near | 76–150 | −85 … −96 |
| In Range | 151+ | < −96 |

## Status

- Cutoffs are **per-model table rows**, not global: the S9→S9 row keeps its
  own logic (median ≥ −80 + medium-advert-slot gating).
- **Not yet wired into runtime** — the app's `RangeEstimator` still runs the
  S9 logic; the iPhone row is calibration data pending the per-model
  threshold table.
- Beacon cold-start bug found in post-commit review (adapter-ready poll read
  an unprimed plugin cache; ~24 s failure on fresh launch) — fixed in the app
  repo by priming `FlutterBluePlus.adapterState` before polling.
