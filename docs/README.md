# Documentation index

Entry point for `docs/`. One line per document: what it is, and when to read it.
**Read this before opening anything else here** — several documents are dated
snapshots that were true when written, and the notes below say which ones.

Consolidated 2026-07-26. Twelve superseded documents were retired in that pass;
their unique content was migrated first (see *Retired documents* at the bottom
for where each thing went). Nothing is lost — retired files are recoverable from
git.

**Three conventions that matter:**

1. **Dated filenames are snapshots, not current direction.** A doc named
   `*_2026-07-24.md` describes that day. Where a later doc supersedes part of it,
   the newer one says so.
2. `docs/research/**` is **sourced external research** — do not edit or delete
   it, and cite it as `docs/research/<file>.md` (the full path, including
   `docs/`). A citation that drops the `docs/` prefix has already been
   misread once as "unsourced".
3. **Anything a person reads in the field is load-bearing.** Be conservative with
   `WALK_PREFLIGHT_*`, `MAC_SETUP.md`, `RAHUL_REINSTALL.md`.

---

## Architecture and algorithm

| Doc | What it is / when to read it |
|---|---|
| [`ARCHITECTURE_CONTRACTS.md`](ARCHITECTURE_CONTRACTS.md) | **Read first for any design question.** Part 0 = the locked platform/product stack, BLE payload decisions, platform research findings, and the still-open design questions. Parts C1–C6 = the ML/walk-pipeline contracts that gate any learned-runtime deploy. |
| [`PROXIMITY_ALGORITHM.md`](PROXIMITY_ALGORITHM.md) | The layered design that turns three noisy radios into one answer. The algorithm reference. |
| [`PROXIMITY_TIERS.md`](PROXIMITY_TIERS.md) | **The tier authority.** Close By / Near By / In Range definitions, the measured per-pair per-direction RSSI cutoff table, and the Close By confidence roadmap. Most-referenced doc in the repo. |
| [`SUBTLE_TRACKING_ARCHITECTURE.md`](SUBTLE_TRACKING_ARCHITECTURE.md) | Multi-radio "subtle wake" architecture (2026-07-25). Cited from Swift, Dart, SQL and the `proximity-wake` Edge Function. |
| [`IOS_BACKGROUND_BLE_WIRING.md`](IOS_BACKGROUND_BLE_WIRING.md) | Locked-phone iOS BLE wiring plan; W2+W4 bench-verified. The iOS background reference, cited from Swift/Kotlin/Dart/SQL. |
| [`ephemeral-token-spec.md`](ephemeral-token-spec.md) | Rotating ephemeral token format. Cited from the generator and migration 0002. |
| [`BACKEND_API.md`](BACKEND_API.md) | RPC surface. ⚠️ See *Known conflicts* — it may still list a dropped RPC. |
| [`CLOUD_RSSI_UPLOAD_SPEC.md`](CLOUD_RSSI_UPLOAD_SPEC.md) | Calibration RSSI cloud-upload spec; server side (migration 0056) implemented. |

### iOS proximity design set (2026-07-24 → 07-26)

Read in this order if you are picking up the iPhone work cold.

| Doc | What it is / when to read it |
|---|---|
| [`IPHONE_BEACON_COMPLETION_HANDOFF.md`](IPHONE_BEACON_COMPLETION_HANDOFF.md) | **The current iPhone source of truth.** State + the ordered open queue (§16.2) + Mac readiness. §16.4 "Standing rules" is cited **by number** from `test/config_policy_test.dart` — do not renumber it. |
| [`IN_RANGE_IPHONE_COMPLETION_PLAN.md`](IN_RANGE_IPHONE_COMPLETION_PLAN.md) | The strategic plan behind that handoff. Still needed: it holds the file:line "what is not true yet" evidence table, `W5Constants`, every P1–P4 acceptance gate, and the §12 non-goals/traps list. ⚠️ Two stale details flagged below. |
| [`IPHONE_DARK_PAIR_TEST_2026-07-26.md`](IPHONE_DARK_PAIR_TEST_2026-07-26.md) | **The measurement everything is gated on.** Protocol for two stationary dark iPhones, with contamination rules, arms/controls and a decision rule. Required by handoff §16.4 rule 3 before any screen-off claim. |
| [`IPHONE_WALK_ROOT_CAUSE_REPORT_2026-07-24.md`](IPHONE_WALK_ROOT_CAUSE_REPORT_2026-07-24.md) | Why the 07-24 iPhone walk was unusable. The reason the current preflight's corrections exist. |
| [`IOS_SCREEN_OFF_FUSION_2026-07-24.md`](IOS_SCREEN_OFF_FUSION_2026-07-24.md) | Screen-off fusion design. |
| [`IOS_PROXIMITY_RESEARCH_2026-07-24.md`](IOS_PROXIMITY_RESEARCH_2026-07-24.md) | Long-form iOS proximity research + agent handoff. |
| [`IOS_LOCATION_RESIDENCY_REVIEW_2026-07-24.md`](IOS_LOCATION_RESIDENCY_REVIEW_2026-07-24.md) | Review of the continuous-location residency path. It demanded the same-binary R-on/R-off A/B that the dark-pair test now runs. |
| [`IOS_CARRIER_DECISION_2026-07-16.md`](IOS_CARRIER_DECISION_2026-07-16.md) | How the iOS BLE carrier was chosen; also holds the 2026-07-16 permission root cause. |
| [`IOS_ADVERTISING_CARRIER.md`](IOS_ADVERTISING_CARRIER.md) | The advertising-gap spec handed to the protocol owner. Background to the decision above. |

## Walks and calibration

Five live documents. They are **not** duplicates of each other — each covers a
different experiment or a different layer.

| Doc | What it is / when to read it |
|---|---|
| [`WALK_PREFLIGHT_2026-07-25.md`](WALK_PREFLIGHT_2026-07-25.md) | **The current operator checklist — read this the morning of a walk.** S22 ↔ iPhone locked-bridge ladder, USB capture, the explicit no-migration/no-cloud boundary, and a "what this walk does NOT measure" section written to stop the results being over-claimed. |
| [`WALK4_PROTOCOL.md`](WALK4_PROTOCOL.md) | A **different, still-unrun** experiment: the S9 three-radio walk with the indoor Wi-Fi venue stations (Part B). Also the protocol pinned by the calibration freezes. Not the cross-platform ladder. |
| [`CALIBRATION_FREEZE_2026-07-23.md`](CALIBRATION_FREEZE_2026-07-23.md) | **The current freeze** (baseline tag `calib-freeze-2026-07-24b`). What every walk's code is pinned to, the build-stamp verification rules, and the collection-round promotion gates. Supersedes the retired 07-18/07-18b freezes and preserves their tag→commit mapping. |
| [`WALK_LOGISTICS.md`](WALK_LOGISTICS.md) | Historical 2026-07-18 logistics, but still the **only** statement of the walk-data sensitivity tiers (what may leave the machine — raw GPS/BSSIDs are local-only) and the requirements for a capture to join the training dataset. |
| [`DEVICE_TESTING_JOURNAL.md`](DEVICE_TESTING_JOURNAL.md) | **The field-evidence log — the highest-value doc in the repo.** Dated entries with measured dBm, method lessons and root causes, iOS vs Android. Append here after every session; never overwrite an entry. |
| [`FEET_TEST_PLAN_2026-07-22.md`](FEET_TEST_PLAN_2026-07-22.md) | Partly executed. Session A ran (and locked the current iPhone-pair thresholds); **Sessions B (street clutter) and C (park/NLOS) were never run** and remain open experiments. Header annotates what is superseded. |
| [`RUNTIME_HEALTH.md`](RUNTIME_HEALTH.md) | Live-observed runtime defects, tracked apart from feature work. RH-1 (a phone can advertise while its scanner is silently dead) is the pre-walk health check. |
| [`RAHUL_REINSTALL.md`](RAHUL_REINSTALL.md) | Field reinstall procedure for the S22 + iPhone 15 Plus, including the 7-day signing expiry. Cited from `scripts/walk_capture.sh` on abort. |

Calibration model registry, trainer and `LEARNING_LOG.md` live in `learn/` and
at the repo root (`learn/loop.sh` appends to `LEARNING_LOG.md` by relative path
— that file must stay at the root).

## Security, privacy and compliance

| Doc | What it is / when to read it |
|---|---|
| [`SECURITY_HANDOFF.md`](SECURITY_HANDOFF.md) | **Start here for proximity-security ("#6") work.** Executable handoff: the precise threat-model wording, the pending enforcement cutover with its SQL and rollback, attestation, and the "harness is the gate" ground rules. Tasks A, C-client and D verified still open. ⚠️ two stale lines flagged below. |
| [`ADVERSARIAL_REVIEW_2026-07-15.md`](ADVERSARIAL_REVIEW_2026-07-15.md) | The 24-finding proximity-engine review **plus** the roadmap narrative in its header. All 24 addressed and deployed. ⚠️ The finding bodies are preserved at their original *open* wording — the resolutions are in the header, so do not read a finding body alone and conclude it is live. |
| [`ULTIMATE_AUDIT_REPORT_2026-07-12.md`](ULTIMATE_AUDIT_REPORT_2026-07-12.md) | The app-wide security/authz audit (RLS, grants, storage, edge JWT, auth, chat, push, photo review, build config). **Different scope from the adversarial review — neither supersedes the other.** Still the only home for open findings H-12/H-13/H-14/H-15. Moved from the repo root 2026-07-26. |
| [`PRIVACY_COMPLIANCE_2026-07-19.md`](PRIVACY_COMPLIANCE_2026-07-19.md) | Privacy audit, fixes shipped, and what remains. |
| [`APP_STORE_COMPLIANCE_2026-07-25.md`](APP_STORE_COMPLIANCE_2026-07-25.md) | App Store review compliance findings, verified against the code. Read before a submission. |
| [`SAFETY_RUNBOOK.md`](SAFETY_RUNBOOK.md) | For whoever is on call for user safety. Legal-response and escalation procedures. |
| [`RELAY_ABUSE_RUNBOOK.md`](RELAY_ABUSE_RUNBOOK.md) | Operating the relay-abuse telemetry. **Do not auto-punish** — in a forwarding relay both parties are normally victims. Cited from migration 0053 and the scan schedule. |

## Setup and ops

| Doc | What it is / when to read it |
|---|---|
| [`MAC_SETUP.md`](MAC_SETUP.md) | **Mac/iOS bring-up: toolchain, signing, connect+trust, build+run, and the gotchas in the order you hit them.** Load-bearing on any Mac session; cited from `scripts/build-install-ios.sh`. |
| [`CI_IOS_BUILD.md`](CI_IOS_BUILD.md) | Compiling the iOS side without a Mac via GitHub Actions. Green as of 2026-07-25. Cite a CI run ID whenever you claim an `ios/` change is verified (handoff §16.4 rule 2). |
| [`SUPABASE_SETUP.md`](SUPABASE_SETUP.md) | Backend setup, secrets, and the pg_cron schedules. |
| [`GO_LIVE_CHECKLIST.md`](GO_LIVE_CHECKLIST.md) | The remaining credential/config steps before launch. |
| [`MARKETING_PLAN.md`](MARKETING_PLAN.md) | "City Strike" go-to-market and financial plan, adopted 2026-07-24. Cited from the waitlist/referral migration. |
| [`rtk-setup.md`](rtk-setup.md) | Optional dev-machine CLI output compression. |

## Research (do not edit)

[`research/README.md`](research/README.md) indexes the sourced external
research: BLE radio optimization, COVID exposure-notification BLE calibration,
GPS-fused location, iOS co-location, Wi-Fi co-location, sensor fusion, the
privacy-law landscape, and minors/age assurance. Raw source captures are in
`research/raw/`.

`sessions/` holds two dated raw session logs (`2026-07-12-full-bug-run.md`,
`2026-07-17-iphone-outdoor-sweep.md`).

---

## ⚠️ `BLE_PRIOR_ART_REVIEW_2026-07-26.md` is NOT on this branch — read this before grepping for it

Five code comments cite `docs/BLE_PRIOR_ART_REVIEW_2026-07-26.md`
(`beacon_service.dart:417, 500, 1731`, `background_beacon_channel.dart:6`,
`AdvertScanner.kt:20`). The file is real but lives **only on the private branch
`docs/ble-prior-art-review`** (commit `8982991`, on `origin`/`inrangeai` — never
pushed to the public `hazypiff` remote). Read it with:

```bash
git show origin/docs/ble-prior-art-review:docs/BLE_PRIOR_ART_REVIEW_2026-07-26.md
```

It is deliberately private: it contains the flutter_blue_plus licence exposure and
a list of live unfixed defects, neither of which belongs in a public repo.

**It is the source for every `Wn` instrument, and for finding ids of the form
`A1`–`A14` (Herald), `B1`–`B15` (contact tracers), `C1`–`C12` (mesh apps),
`D1`–`D11` (Apple overflow area + AOSP scan internals) and `E1`–`E14` (plugin
layer) that appear in code comments and commit messages.** Also note its
"Post-implementation corrections" section **retracts several of its own findings** —
including one that wrongly claimed `research/ble-radio-optimization.md` did not
exist, when it is at `docs/research/`. Never act on a finding there without
checking that section first.

This pointer exists because a bare path in a comment that resolves to nothing is
exactly how a load-bearing citation got misread as unsourced on 2026-07-26.

---

## Known conflicts — a human should resolve these

Found during the 2026-07-26 consolidation. **Not decided here**, because each is
two documents disagreeing about a current value:

1. **Shipped migration number.** `SECURITY_HANDOFF.md` says the prod ledger is
   "through 0034"; the old root README said "through 0033"; the repo contains
   migrations up to **0061**. The README now points at `supabase/migrations/`
   instead of quoting a number, but the handoff line is still stale.
2. **Is `pg_net` installed on prod?** `SECURITY_HANDOFF.md` asserts it is
   **not**, and builds its "verification must live in the Edge Function"
   conclusion on that. Later work contradicts the premise — migrations
   `0049_schedule_maintenance_edge_worker.sql` and
   `0051_harden_pg_net_and_ncii_rate.sql` plus `SAFETY_RUNBOOK.md` all describe
   pg_net scheduling live in prod. If pg_net *is* available, that architectural
   conclusion needs revisiting.
3. **`nearby_location_pings`.** `BACKEND_API.md` documents it as a live RPC; the
   2026-07-09 audit ledger recorded it as **dropped in migration 0015**. One of
   the two is wrong.
4. **`IN_RANGE_IPHONE_COMPLETION_PLAN.md` has two stale specifics** that would
   misdirect anyone following it literally: it proposes the channel name
   `io.inrange.app/wifi_ios` (shipped as `.../wifi_assist`), and it assigns
   `0057_active_proximity_sessions.sql` (0057 was actually consumed by
   `0057_subtle_wake_support.sql`).
5. **`IPHONE_BEACON_COMPLETION_HANDOFF.md` header vs body.** The header says
   `Current HEAD: e8ad7b9`, §16 says `f6bf21e`, and it records a migration
   rehearsal of `0001→0060` while `0061` now exists.
6. **Evidence-stack ordering** is deliberately different between the completion
   handoff (ordered by coverage) and the completion plan (ordered by precision).
   The handoff explains why and wins; noted so it does not read as an error.

## Retired documents (2026-07-26)

Recoverable with `git show <rev>:<path>`. Unique content was migrated **before**
deletion:

| Retired | Superseded by | Unique content migrated to |
|---|---|---|
| `ULTIMATE_AUDIT_PROMPT.md` | its own deliverable, `ULTIMATE_AUDIT_REPORT_2026-07-12.md` | binding constraints → `ARCHITECTURE_CONTRACTS.md` §0.1 |
| `REVIEW_PROMPT.md` | its own deliverable, `ADVERSARIAL_REVIEW_2026-07-15.md` | provisional-weights + iOS-Wi-Fi caveats, 17th-byte flag → `ARCHITECTURE_CONTRACTS.md` §0.4, §0.7 |
| `FULL_AUDIT_REPORT.md` | `ULTIMATE_AUDIT_REPORT_2026-07-12.md` (strict superset but for 5 items) | those 5 → `ARCHITECTURE_CONTRACTS.md` §0.6 |
| `AUDIT_TODO.md` | same | 5 unresolved/unique rows → `ARCHITECTURE_CONTRACTS.md` §0.6 |
| `HANDOFF.md` (root, Phase 0) | superseded in every live respect; carried expired standing orders and a wrong JVM version | token flow, two range modes, open design questions, MainActivity root cause → `ARCHITECTURE_CONTRACTS.md` §0.3, §0.2, §0.7 |
| `BUILD_PLAN.md` | all 9 phases met | platform research findings + BLE payload root causes → `ARCHITECTURE_CONTRACTS.md` §0.4, §0.5 |
| `NEXT-STEPS.md` | self-marked ✅ DONE; duplicated `HANDOFF.md` | nothing unique |
| `LLM_SHUTDOWN_NOTE.txt` | expired 2026-07-07 note; its "do not restart" order was a dangling standing instruction | nothing durable |
| `IPHONE_BEACON_PROGRESS_HANDOFF.md` | named `IPHONE_BEACON_COMPLETION_HANDOFF.md` as its successor itself | 5 facts (raw-BSSID rule, plugin cannot wake the app, `'scan'` localState, advert-only band decisions) → that handoff's **Appendix A** |
| `IOS_BEACON_AUDIT_2026-07-16.md` | root cause restated in `IOS_CARRIER_DECISION_2026-07-16.md` | diagnostic string, AOT-`strings` tooling lesson, CoreDevice un-wedge remedy, dated history → `DEVICE_TESTING_JOURNAL.md` 2026-07-16 entry |
| `WALK_IPHONE_FIRST_PROTOCOL.md` | its sweep was executed; outcomes in `DEVICE_TESTING_JOURNAL.md` 07-17 entries and `PROXIMITY_TIERS.md` | method lessons already present in those entries |
| `CALIBRATION_FREEZE_2026-07-18.md` | `CALIBRATION_FREEZE_2026-07-23.md` says "Supersedes `calib-freeze-2026-07-18b`" and preserves the tag→commit table | tag→commit mapping already in the 07-23 doc |
