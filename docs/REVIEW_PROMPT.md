# Adversarial Review Prompt — In Range proximity engine

Paste the block below to a fresh code-review agent (Claude Code, a review bot, or
another engineer's setup). It is self-contained — assume the reviewer has **no
prior context** beyond the repository.

---

You are a senior engineer doing an adversarial correctness and design review of a
Flutter + Supabase BLE proximity app (`in-range`, package `io.inrange.app`). Your
job is to find **real bugs, data-integrity risks, security/privacy holes, and
concrete improvements** — not style nits. Verify every claim against the actual
code before reporting it; do not speculate.

## What the app does

Two phones detect each other's proximity by advertising a rotating ephemeral BLE
token (15-min epochs) and scanning for peers. Proximity is surfaced as three
tiers — **Close By / Near By / In Range** — plus a WiFi "same venue" signal and a
GPS plausibility veto, fused into one classification with a confidence score.
Encounters correlate server-side (Supabase/Postgres/PostGIS) into per-pair rows,
with a recurrence feature ("crossed paths N times").

## Architecture & where to look

- `lib/features/beacon/beacon_service.dart` — BLE advertise + scan lifecycle,
  dual-power advertising (20s high / 10s medium, slot flagged in a 17th
  manufacturer-payload byte), token rotation, sighting upload, WiFi + GPS wiring.
- `lib/features/beacon/range_estimator.dart` — the tier classifier: rolling 90s
  window of (time, rssi, power) per peer; Close By = median high-power RSSI ≥ −80
  with ≥5 samples; Near By = ≥2 medium-power-slot samples; In Range = any packet;
  `nearDwell`, `evidenceFor`.
- `lib/features/beacon/venue_matcher.dart` — WiFi fingerprint venue score
  (Jaccard + Sørensen/Bray-Curtis on a "powed" RSSI transform), BSSID hashing,
  staleness, and `ProximityFusion.fuse` (the fusion table + confidence weighting).
- `lib/features/beacon/wifi_scanner.dart` + `android/.../MainActivity.kt` — WiFi
  cached-scan platform channel (Android-only).
- `lib/features/encounters/local_encounter_store.dart`, `swipe_card.dart` — local
  encounter model, band persistence, recurrence fields.
- `lib/core/db/local_db.dart` — SQLite (schema v3: sightings, aliases, rssi_log).
- `supabase/migrations/0020_*..0025_*.sql` — the recent server changes:
  feet_60 enum + range maps, encounter band from sighting, accuracy-aware GPS
  gate, and encounter recurrence. **These have been rewritten several times.**
- `docs/PROXIMITY_ALGORITHM.md`, `docs/PROXIMITY_TIERS.md`, `docs/research/` —
  the design intent and the evidence behind every constant.

## Focus areas (highest-risk first — spend time here)

1. **BLE lifecycle & concurrency (`beacon_service.dart`).** This has a history of
   a "zombie advertiser" bug. Scrutinize: the advertising op-chain serialization
   and `_advertisingWanted` gate; the `_sessionGeneration` guard across async
   token rotation vs `turnOffBeacon`; every timer (rotation, flush, scan-restart,
   power-cycle, watchdog) — are all cancelled on every stop path? Can any
   `unawaited(...)` future resume after teardown and start advertising/claim a
   token? Can the dual-power `_startAdvertising` restart race token rotation?
2. **SQL migration ordering & final state.** `correlate_encounter` is
   `CREATE OR REPLACE`d in 0022, 0024, AND 0025 — confirm the LAST definition is
   correct and self-consistent (band-from-sighting narrowing, 400m clamp,
   recurrence session logic all present). Check the recurrence math in 0025:
   session-gap boundary, `session_count`/`distinct_day_count` increments,
   `encounter_sessions` insert conditions, the advisory-lock scope, and whether a
   new enum value is ever used in the same transaction that adds it (0020/0021
   split was needed for exactly this). Check RLS on `encounter_sessions`.
3. **RangeEstimator correctness.** Median (even/odd), window pruning vs the
   dwell accounting (`nearSince`/`nearAccum` — can silence bank dwell?),
   `evidenceFor`, unbounded memory. Does the classifier ever act on a single
   reading? Does a multipath spike change the tier?
4. **Fusion & confidence (`venue_matcher.dart`).** The `powed` transform,
   Sørensen denominator (div-by-zero), the confidence weighting bounds [0,1], the
   conflict rule, and — importantly — **is `ProximityFusion.fuse` actually called
   anywhere in the live pipeline, or is it dead scaffolding?** Is the WiFi
   fingerprint ever exchanged between the two phones, or only computed locally?
5. **Data flow / cross-phone.** Sighting upload (accuracy, band), the
   `_pendingByCorr` reconstruction (does it drop any field?), the 5s sighting
   throttle vs the raw `rssi_log`, best-band narrowing-never-widening.
6. **Privacy & security.** BSSID salted-hashing before upload; the hotspot-BSSID
   exclusion (does an unexcluded travelling hotspot manufacture a false venue
   match?); token self-sighting filter; RLS/`SECURITY DEFINER` on all RPCs; any
   raw location/BSSID/audio that could leak.
7. **Cross-platform parity.** What is Android-only and silently no-ops on iOS
   (WiFi channel, `getPhySupport`, calibration logging)? Any place the app
   assumes Android behavior?

## Known-open (do NOT re-report these — they are tracked)

- Fusion (`ProximityFusion.fuse`) is built + unit-tested but **not yet wired**
  into the live encounter pipeline; WiFi fingerprint is **not yet exchanged**
  cross-phone. (Confirm scope, but it's known.)
- Migrations 0020–0025 are **not applied to live Supabase** yet.
- The confidence weights are provisional (to be fit from walk-#4 labeled data);
  hand-tuned linear weighted-sum fusion is known-weak — flagged in the research.
- iOS WiFi scanning is impossible (architectural); connected-BSSID mitigation is
  spec'd (§7) but not built.
- Duplicate anonymous local cards across token rotation (needs server identity).

## Deliverable

Run the tests (`flutter test`) and `flutter analyze` first. Then report a
**prioritized list**, most-severe first. For each finding:

- **Severity**: correctness-bug / data-loss / security / race / improvement.
- **Location**: `file:line`.
- **Failure scenario**: concrete inputs/state → wrong result (not "this looks
  risky").
- **Confidence**: CONFIRMED (traced in code) vs SUSPECTED (needs a repro).
- **Fix**: the minimal change.

End with a short "checked and fine" list of things you verified are correct, so
we know the coverage. Do not modify files — report only. Do not report anything
in the known-open list. Prefer 8 real, verified findings over 40 speculative ones.
