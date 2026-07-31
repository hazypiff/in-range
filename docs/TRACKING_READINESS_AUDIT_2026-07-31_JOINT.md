# In Range tracking system — joint completion-readiness audit (2026-07-31)

**Auditors:** Claude + Kimi (both Linux-side), two independent agents. Claude gathered evidence
and drafted findings; Kimi verified each item CONFIRM/DISPUTE with its own git/grep passes; one
finding was overturned in reconciliation and is recorded below. Full dialogue transcript retained
by hazypiff.
**Refs audited:** `origin/main` @ `96a9d56`; `origin/fix/w5-encounter-lease` @ `dc972e5` (PR #9).
**Scope:** detection layer, W5 link layer, ranging/calibration, classifier/learning loop,
upload/backend/wake path, verification infrastructure. Launch/compliance included as context.

## Joint verdict (agreed by both auditors)

**The tracking system is NOT completion-ready — and the gap is narrower but deeper than the open
PR count suggests.** Narrower: the feared "two divergent W5 implementations" does not exist
(`ec7856e` is an ancestor of the PR #9 branch — one coherent, flag-gated W5 stack, with a
properly conformance-pinned binary codec). Deeper: the system's correctness center of gravity has
shifted from "does the link stay up" to "are encounter-lease semantics right under rotation,
eviction, and reconnect grace" — and that surface is vector-tested only at the codec layer,
unpinned at the ownership layer (Dart and Swift state machines share no conformance vectors),
unpersisted across process death, and completely unvalidated on hardware. Meanwhile every green
signal for the +5,246-line W5 stack is self-reported by its authoring agent past a billing-dead
CI, and the only defect users can hit **today** sits in the still-unmerged PR #5. Detection
baseline, ranging pipeline, source-tagged observation envelope, and upload path are
production-shaped and test-covered; calibration and the learning loop are deliberately parked
pending walk #4.

## Executable gates run for this audit

| Gate | Result |
|---|---|
| `flutter test` @ `origin/main` 96a9d56 (Claude, local) | **158/158 green** |
| Dart suite @ PR #9 `dfb4b99` (Kimi, prior audit, clean worktree; pre-codec head — the later `095388f` 52/52 codec suite is self-reported, per A14/K5) | **201/201 green** |
| Fork CI `hazypiff/in-range` (analyze+test; iOS release compile, manual dispatch) | green / green |
| inrangeai CI (runs 30645525212 / 30645522537) | zero-signal — jobs never start (billing) |

## Agreed findings

### Link layer / W5
- **A1 (was N1 — DISPUTED by Kimi, Claude conceded after re-verification).** There is ONE W5
  native line, not two: PR #9's branch contains main's `ec7856e` persistent-link commit and
  builds on it (full branch diff vs main: +5,246/−44 across 24 files; `BackgroundBeacon.swift`
  ~300 diff-lines). What survives: (a) merge-order interaction with PR #5 is real — PR #5 touches
  `BackgroundBeacon.swift`, `beacon_service.dart`, `app_config.dart`, the same stack; (b) the
  W5LinkController stack sits *on top of* the flag-gated `ec7856e` path rather than replacing it —
  someone must still decide what "production W5" is when the flag turns on.
- **A2 (N2).** PR #9 is gated on hazypiff: round-7 review of the current head has not happened,
  and the `prevAlias`-in-HELLO ratification is explicitly hazypiff's call. PR is DRAFT, retitled
  "DO NOT MERGE (pending hazypiff review)"; latest activity 2026-07-31 16:03Z.
- **A3 (N3).** Hardware Phase 5 entirely unproven. The persistent-link bench doc says it itself:
  "Single evening, single pair… NOT yet durability-proven"; "Explicitly NOT proven: Durability."
  Rotation, ≥2-boundary both-locked, multi-peer, restoration, overnight soak: none run.
- **A4 (N4, refined by Kimi).** Two layers, different states: BLE *plumbing* restoration is BUILT
  on main (`willRestoreState` recovers the peripheral service registration; central re-attaches
  restored peripherals) — the completion plan's "restoration callbacks are empty" is stale. But
  W5 *lease/ownership* persistence is genuinely absent (`w5_ownership.dart`, 609 lines, no
  persistence code; in-memory only) — lease state dies with the Dart isolate even when iOS
  restores the link underneath it. The hole moved down a layer; it didn't close. (Task #8.)
- **K2 (Kimi).** The ownership state machine has NO cross-language conformance pin: the codec is
  properly pinned (shared `w5_codec_vectors.json` + external SHA-256 anchor), but
  `W5OwnershipTests.swift` and `w5_ownership_test.dart` share no vectors — two implementations of
  lease semantics that can silently diverge. Fix is obvious: same treatment as the codec.
- **K3 (Kimi).** Lease semantics are a new, hardware-unvalidated correctness surface. A wrong
  lease mints spurious second leases, which corrupts *encounter counting*, not just connectivity.
  `prevAlias` exists precisely for the keeper-down-during-rotation case — exactly the Phase-5
  matrix that has never run.
- **K1 (Kimi).** Review coverage lags the branch head: the CA6E codec (`095388f`) and native
  integration (`dfb4b99`) landed at/after the reviewed rounds; Kimi's `dc972e5` audit covers
  `dfb4b99` only. Nobody has reviewed the current head end-to-end.
- **K4 (Kimi).** Bit-rot risk compounds with queue time: PR #9 patches `BackgroundBeacon.swift`
  by ~300 lines while main keeps moving (wake scaffolding, PR #5 pending). DRAFT posture is
  right; the rebase widens weekly.

### Detection layer
- **A5 (N5).** PR #5 ("BLE Tier-1: restore iPhone→Android detection, close silent-blindness
  holes, pin plugin licence") is still open (its open status is the finding; last list activity
  2026-07-26). Until merged, the live
  cross-platform detection path retains known blindness holes — the highest-severity
  *shipped-behavior* gap in the audit. PR #6 (licence-exposure docs) also open.
- **A6 (N6).** Cold discovery of two dark iPhones remains a documented, accepted platform
  boundary — not a defect.

### Ranging / calibration / learning loop
- **A7 (N7).** Product tiers are deliberately qualitative until walk #4 calibrates the middle
  tier (`range_estimator.dart:247`); `WALK4_PROTOCOL.md` exists; `run_logs/walks/2026-07-27/` is
  empty — walk #4 has not run.
- **A8 (N8 + K6).** Cross-platform thresholds are provisional: one S22↔iPhone six-station walk
  (2026-07-23) with ~9 dB direction asymmetry (figure per Claude's pass of the device-testing
  journal and `docs/PROXIMITY_TIERS.md`; Kimi verified the per-direction cutoffs were locked but
  did not re-derive the number) ⇒ per-pair per-direction table required.
  **Prerequisite:** Rahul's S22 and iPhone 15 Plus must be reinstalled from ≥ `95c6eae` before
  the next walk — calibration is gated on physical device action, not just scheduling.
- **A9 (N9).** `GnbClassifier` is trained and tested but NOT wired — the live default is
  `RulesClassifier`; the learning loop waits on walk #4 data.
- **A10 (N11).** A locked iPhone still can't report `med_n`: native `onSighting(token, rssi, at)`
  carries no power field; `AdvertPower.high` hardcoded (`beacon_service.dart:92`, `:306`).

### Upload / backend / wake path
- **A11 (N12).** Early-sighting/no-GPS upload defect fixed (`56b12ef`); calibration pipeline
  end-to-end consistent.
- **A12 (N13).** Migrations at 0061; anon-reachable proximity-wake RPC closed and the dead
  security suite revived (`b1815af`). `require_attestation` remains 0 (OFF) by design pending
  client rollout.
- **A13 (N14, dates corrected).** Wake path is scaffolding-stage: W5 persistent GATT sessions +
  wake-ping scaffolding (`5e21a0c`) and APNs tier-4 entitlement (`12d6efc`) landed 2026-07-29;
  server half exists (`send-push`, `proximity-wake` edge functions); zero soak/field evidence for
  any wake tier.

### Verification infrastructure
- **A14 (N15).** `ios-build.yml` triggers on `workflow_dispatch` + push-to-main only — no
  `pull_request` trigger; no `xcodebuild test`/RunnerTests step exists in any workflow. Native
  "30/30 green" rests entirely on the authoring Mac's simulator run.
- **A15 (N16).** inrangeai CI remains zero-signal billing-blocked. Fork CI (`hazypiff/in-range`)
  is the only live GitHub-side gate.
- **K5 (Kimi).** Process: PR status comments are claims, not ground truth — the Mac agent's own
  2026-07-31 comment opens by correcting its earlier #8 status. Readiness assessments should
  trust code, vectors, and bench docs over comment narratives.

### Docs
- **A16 (N10 + N17).** `IN_RANGE_IPHONE_COMPLETION_PLAN.md` §1 "What is *not* true yet" is now
  half false: W5 is built (item 1), plumbing restoration exists (item 5), the source-tagged
  observation envelope is wired into `beacon_service` + `range_estimator` (item 6), and item 7 is
  dubious post-`56b12ef`. A stale master plan actively misleads future sessions. Kimi's F4 (the
  Mac-side audit trail exists only uncommitted on the Mac) also remains open.

### Launch / compliance (context)
- **A17 (N18).** inrange.life is live with the waitlist funnel; per project records all *code*
  launch-blockers were cleared 2026-07-24. Remaining blockers are human/external plus device
  testing — the tracking system above is now the long pole for launch.

## Agreed priority order — what needs updating

Items 1–3 are hazypiff-gated and can proceed in parallel; 4–6 are agent-executable in sequence.

1. **Merge PR #5** — the only user-visible defect surface; smallest diff; unblocks the beacon
   stack for everything behind it.
2. **Restore CI signal** — fix inrangeai billing or formally adopt fork CI as the interim gate;
   either way add a `pull_request` trigger to `ios-build.yml` and an `xcodebuild test` (simulator)
   step so native claims get third-party corroboration. Until then, every W5 green is
   self-reported. (Kimi ranks this above 3; Claude accepts — a round-7 review without an
   independent gate has capped value.)
3. **Round-7 review + `prevAlias` ratification** (hazypiff) — the current PR #9 head is well past
   what any reviewer has seen end-to-end.
4. **Lease persistence (Task #8) BEFORE the Phase-5 soak** — otherwise the soak measures a
   restoration path that cannot work. Then the hardware matrix: rotation, ≥2-boundary
   both-locked, multi-peer, restoration, overnight soak. Add an ownership conformance-vector pin
   (K2) alongside — cheap, high leverage.
5. **Calibration program** — reinstall Rahul's devices (≥ `95c6eae`), run walk #4, adopt per-pair
   per-direction table governance, then wire `GnbClassifier` once walk #4 data lands. Add the
   `med_n` power field to native sightings (A10) so the iPhone side stops training on a constant.
6. **Docs hygiene** — refresh the completion plan §1 (A16), commit the Mac-side audit/review
   trail (F4), fold A4's two-layer restoration correction into the design docs.

## Sign-off

- Claude (Linux-side): AGREED 2026-07-31
- Kimi (Linux-side): **SIGN-OFF: AGREED** 2026-07-31 (round-2 reply; re-verified A1(a)/A12/A13
  independently before signing; three non-blocking nits applied above)
