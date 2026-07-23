# Architecture contracts — what surrounds the deterministic core

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
