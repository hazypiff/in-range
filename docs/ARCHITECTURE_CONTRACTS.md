# Architecture contracts — what surrounds the deterministic core

> Two kinds of contract live here. **Part 0** is the locked platform/product
> stack and the early protocol decisions (migrated 2026-07-26 from
> `ULTIMATE_AUDIT_PROMPT.md`, `HANDOFF.md` and `BUILD_PLAN.md` when those were
> retired). **C1–C6** are the ML/walk-pipeline contracts from the 2026-07-18
> review.

---

# Part 0 — locked stack, protocol, and early decisions

## 0.1 Binding constraints (do not re-debate)

Migrated verbatim from `ULTIMATE_AUDIT_PROMPT.md` §BINDING CONSTRAINTS before
that prompt-scaffolding file was retired. These are settled choices, not
open questions:

- Framework: **Flutter + Shorebird OTA** (NOT React Native, NOT KMP)
- Backend: **Supabase Postgres + PostGIS** (NOT Firebase)
- BLE: **`flutter_blue_plus`** scan + **`flutter_ble_peripheral`** advertise
- Devices: Android 10 Galaxy S9s (4 devices), **Android MVP first, iOS later**
- Encounter reveal delay: **4 h minimum (prod), 0 h for testing**

**One constraint from that list was retracted, not carried:** the prompt
permitted "photo storage public-read by URL is an acceptable threat-model
tradeoff (document, don't fix)". `ULTIMATE_AUDIT_REPORT_2026-07-12.md` I-03
overrode it — baseline migration 0018 had already made those buckets private,
and the audit deliberately retained the stricter
owner/revealed-encounter/active-match policy on the grounds that **UUID paths
are not authorization**. Private buckets are the current contract. Do not
re-open public read on the basis of the old prompt.

## 0.2 Deployment classification

From `ULTIMATE_AUDIT_REPORT_2026-07-12.md`: Dart-only follow-up changes may
ship via **Shorebird** after a compatible base release. Any change touching
`pubspec`, Android package/manifest/ABI/signing, the Kotlin source path, or
the plugin set requires a **new Play Store / base release**, not a patch.

Historical install note: test installs under the old `com.example.in_range`
application id will not update in place over `io.inrange.app` — uninstall or
migrate intentionally. (Root cause of that rename, for the record: Kotlin
source sat in `com/inrange/in_range/MainActivity.kt` while the Gradle
namespace, manifest relative name, and `applicationId` all used
`com.example.in_range`.)

## 0.3 Token flow and the two range modes

The end-to-end chain, migrated from `HANDOFF.md` — this remains the only
compact statement of it:

> client generates → `claim_token` → advertises → others scan →
> `record_sighting` → `correlate_encounter` → `encounters` row → swipe via
> `encounter_actions` → mutual → `matches` → realtime → `messages`.

**Two range modes:** *feet* (BLE RSSI, 24 h expiry) and *miles* (GPS +
PostGIS, `location_pings` + `nearby_location_pings`). Note that
`nearby_location_pings` was later **dropped in migration 0015** — see §0.6.

## 0.4 BLE payload decisions (origin + rationale)

- **16-byte correlation ID.** The original implementation advertised a utf8
  slice of the token truncated to 20 bytes; the token is ~52 chars base64, so
  the scanner decoded raw charcodes into garbage, `record_sighting` uploaded
  junk, and `correlate_encounter` never matched — **the core feature was
  broken**. Fix and current design: a 16-byte correlation ID derived from
  `HMAC-SHA256(token, salt)[:16]`, advertised as `manufacturerData` with a
  16-byte payload.
- **Dual-power advertising** runs 20 s high / 10 s medium, with the slot
  flagged in a **17th manufacturer-payload byte**. (Cadence is also in
  `PROXIMITY_ALGORITHM.md`; the byte index was recorded only in the retired
  `REVIEW_PROMPT.md`.)
- Two early SQL root causes, fixed, kept so the class of bug stays known:
  `record_sighting` hardcoded 50 m + 90 min regardless of `range_type` (so
  miles modes never correlated), and `correlate_encounter`'s time filter used
  `valid_until > NOW() - window` instead of `valid_until > NOW()`, letting
  expired claims pass.

## 0.5 Platform research findings (verified against pub.dev + Android docs)

Migrated from `BUILD_PLAN.md`, which was the only citation-bearing copy:

- `BLUETOOTH_SCAN` / `ADVERTISE` / `CONNECT` runtime permissions are
  **Android 12+ only** — do **not** request them on API 29.
- **Permission sequence:** request `locationWhenInUse` **first**, then
  `locationAlways`. A direct `locationAlways` request is **ignored on
  Android 10**. (The pyramid is restated in `permission_service.dart`; the
  Android-10 evidence existed only here.)
- `flutter_blue_plus`' README explicitly disclaims background support ("you
  may have to fork it"), and `flutter_background_service` does not mention
  BLE. A foreground service with `FOREGROUND_SERVICE_LOCATION` is required
  but **not guaranteed** to keep advertising alive — a known integration
  risk, treated as best-effort.
- **PostGIS:** `geography(Point, 4326)`, `ST_DWithin` for radius,
  **longitude first** (`ST_Point(long, lat)`), GIST index.
- **Shorebird** supports Flutter ≥ 3.24.0.

## 0.6 Small closures worth not rediscovering

From the retired `AUDIT_TODO.md` / `FULL_AUDIT_REPORT.md` pair:

- **Dead enum values in migration 0003.** `record_sighting`'s `CASE`
  references nonexistent enum values `feet_100` / `feet_500`. Dead code once
  0008 replaced the path with helper functions, but if migrations were applied
  to 0003 and `record_sighting` called before 0008, the `CASE` would silently
  hit `ELSE` with the wrong radius. **Decision: accept and document — the
  canonical authority is `range_radius_meters`.**
- `nearby_location_pings` was executable to `authenticated` and was **dropped
  in migration 0015**. `BACKEND_API.md` may still document it as live — see
  the conflict list in `docs/README.md`.
- `is_blocked_pair` was probeable; authorization now requires the caller to be
  a participant.
- Migration 0014 revoked column privileges on `email_hint`, `phone_hint`,
  `dob`, `gender`, `sexual_preference`, `interests`, `display_name`, `bio`
  from the `authenticated` role.
- `syncProfile` now sends `session.photoPaths` rather than null — this fixed
  an "invisible user" bug.
- `STUB_AUTO_APPROVE=true` auto-verifies lab users; `false` keeps users
  invisible until manual approval.
- The neighborhood-precision leak: `record_location_ping` + `miles-correlate`
  used to emit lat/lon as a neighborhood fallback (`Area 34.05, -118.24` —
  roughly **1.1 km** precision). Fallback is now the literal string
  `'Nearby'`.

## 0.7 Open design questions (never resolved — do not assume an answer)

Carried from `HANDOFF.md`. Both were open when that doc was retired:

1. **Token replay protection.** The server should reject `record_sighting`
   for tokens whose `claim_token` is past `valid_until` + grace. This wants a
   `CHECK` inside `record_sighting`; today it relies on the `token_claims`
   `DELETE` in cleanup.
2. **Neighborhood reverse-geocoding: server-side (Edge Function) or
   client-side?** Affects privacy and cost. *De facto* it went client-side —
   `BACKEND_API.md` shows `neighborhood?` as a caller-supplied RPC argument —
   but the rationale was never written down and the decision was never
   formally made.

Also still provisional (from the retired `REVIEW_PROMPT.md`): **the fusion
confidence weights are provisional**, intended to be fit from walk-#4 labeled
data. Hand-tuned linear weighted-sum fusion is known-weak and is flagged as
such in the research. And: **iOS WiFi scanning is architecturally
impossible**; the connected-BSSID mitigation is spec'd but not built.

---

# Part 1 — ML / walk-pipeline contracts (2026-07-18 review)

From the 2026-07-18 research-backed architecture review. The verdict: keep
the simple deterministic core (rules → GNB); scalability comes from the
identity, schema, routing, decision, and concurrency **contracts** around
it. This doc tracks each contract's status.

## Implemented (2026-07-18)

### C1. Walk identity — `walk_manifest.v1` (was: CLI-stamped pair)
Capture already knew the devices (meta-pull.json); training used to drop
that and trust `--pair`. Now `extract_walk.py --pair --capture-meta
--freeze` embeds a manifest in walk.json:
`walk_id` (content hash of the raw archives — rename-proof,
collision-proof), `pair_id`, `devices[]` (serials+models), `freeze` tag,
`archive_digests`. `ingest.py` **verifies instead of assigns**: manifest
pair mismatch → walk REFUSED; legacy archives ingest with a loud
unverified-pair warning AND `identity_verified: false` on every row —
carried into the model artifact (`cv.unverified_walks`), blocking
promotion; export refuses unless `--non-production` (artifact then
stamped `non_production: true`, never shippable). Desk archive
retro-stamped.

### C5. Concurrency — exact handoff + atomic publish
- run id = `<utc-ts>-<pair>-<dataset_sha[:8]>` (collision-proof).
- train writes the run dir as `.tmp` then atomic-renames — readers never
  see a half-written run. Publication is idempotent: an identical twin run
  (same second, same inputs → same id) treats the existing dir as success
  and never clobbers it.
- train emits `RUN_ID=<run>`; loop.sh consumes exactly that (the old
  `ls -1t | head -1` could pick a concurrent run's output).
- LEARNING_LOG appends go through `flock`.
- `PROMOTED` stays a human-edited file; export re-verifies everything, so
  a racy human edit fails closed rather than deploying silently.

### C6. LLM input policy — path-hard guard
`report_llm.py` resolves symlinks and requires exactly
`learn/registry/<run>/report.md` (suffix check alone accepted look-alike
paths outside the registry). Output lands beside the canonical path.
Endpoint remains 127.0.0.1 only. When LLM powers grow beyond narration,
they go through a typed policy broker (declared inputs, allowed actions,
audit trail, human approval for mutations) — not ad-hoc script access.

## Pre-deploy blockers (contracts required BEFORE any learned-runtime wiring)

### C2. Feature contract + cross-language golden tests
There is a named schema (`inrange-gnb-1`) and matching feature-name lists,
but **no single feature generator and no end-to-end parity proof**:
offline features come from Python `extract_walk.phone_station`; the app
has no Dart builder of that feature map, and the live path speaks a
different tier vocabulary (`feet_10|feet_30|feet_60|none` vs
`close|near|inrange`). Required:
1. versioned feature-contract constants shared by Python + Dart;
2. one shared raw fixture → both extractors → exact-match golden test;
3. one canonical tier enum (or an explicit mapping layer);
4. a live rolling-window feature builder with station-window-equivalent
   semantics, or a documented reconciliation.

### C3. Decision object with abstention (not a tier string)
`classify()` returning a bare string means empty evidence returns the
highest prior — correct math, unsafe product. Required shape:
`ProximityDecision { tier|abstain, confidence, model_id/schema,
modality_coverage {ble,wifi,gps}, fallback_reason }`.
Abstention must define **minimum evidence**, not "all features null" —
missingness is asymmetric (silence keeps `rate=0.0` present while
`high_med` is None). Align with `ProximityFusion`'s existing abstain
philosophy instead of inventing a second one. Confidence is an
uncalibrated softmax margin: product logic uses margin thresholds +
rules fallback, never treats it as probability.

### C4. Per-pair promotion + fallback routing
One global `PROMOTED` pointer cannot serve heterogeneous pairs. Promotion
becomes per `(pair, modality-profile)` — a small JSON map — and runtime
model selection routes:
`exact pair → device family → platform → deterministic rules`.
iOS is a genuinely different modality profile (no medium TX slot, no
WiFi layer) — feature masks per profile, not one global feature set.

## Provenance axes (keep distinct)

- **Collection artifact**: the freeze tag in each walk's manifest
  (`calib-freeze-2026-07-18b`) — pins the walk-producing code. Only
  capture/extraction changes require a new freeze.
- **Analysis artifact**: `trainer_commit` + `dataset_sha256` inside each
  model.json — analysis code may evolve freely; every run self-identifies.

Runtime loader contract (already enforced at the seam):
`GnbClassifier.fromJson` **rejects `non_production: true`** — a
non-production export structurally cannot load in the app, independent of
C2/C4 discipline.

## Standing verdict

| Dimension | Status |
|---|---|
| Dynamic model seam | Yes (ProximityClassifier + inrange-gnb-1) |
| Auditable / reproducible | Yes (hashes, registry, freeze tags, manifests) |
| Heterogeneous device pairs | Not yet — C4 (identity half done via C1) |
| Safe learned runtime deploy | Not until C2 + C3 |
| Concurrent agents | Yes at current scale (C5) |
| LLM orchestration foundation | Yes — advisory-only; policy broker before more power |
