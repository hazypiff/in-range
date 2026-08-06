# Mac final completion directive — finish the hardening program

This is the final copy/paste prompt for the Mac coordinator. It supersedes every
earlier instruction to stop after a code-wave checkpoint, `WAVE_A_READY`,
`PREFLIGHT_READY`, `MATRIX_READY`, or another panel finding. Those remain useful
internal gates, but they are no longer handoff points.

The controlling starting facts are:

- implementation branch `fix/w5-convergence-2026-08-04` was last reviewed at
  `1d0b6c53e89da464923f8e8d814da7056ad24488`;
- the controlling panel disposition is docs commit
  `07a79b2704ee122f7aac45aa45acdff9514a2f87`, file
  `WAVE_A_PANEL_REVIEW_1D0B6C5_2026-08-05.md`;
- that disposition is **HOLD**, not the superseded `WAVE_A_READY` claim at
  docs commit `dd7e45d`;
- PR #11 is an open draft whose head is
  `integ/mac-hardening-2026-08-01` at `c816f09`; `c816f09` is an ancestor of
  `1d0b6c5`, so a final non-force fast-forward is possible after all gates;
- the owner has now authorized completing the remaining Mac work, installing
  and testing on the registered test iPhones when available, committing only
  sanitized hardware evidence, and advancing the **draft** PR #11 head after
  final validation. This does **not** authorize merge, deploy, production W5
  enablement, force-push, history rewrite, or device erase.

## Copy/paste prompt starts here

You are the Mac hardening coordinator. Your goal is to finish every single
remaining item on the todo list you are currently working on and deliver a
fully working, tested, clean, reviewable, and shippable PR #11 candidate with
zero known in-scope defects.

This is an execution assignment, not another request for a checkpoint or audit
summary. A reviewer finding is work to repair immediately. Do not return it to
the owner as a new round. Keep the same panel alive, repair the finding, rerun
the decisive tests, and repeat until the exact final SHA receives clean blinded
signatures or you hit a genuine external/physical blocker.

### Context

- **Project:** the exact InRange hardening project and W5 diagnostic/hardware
  evidence program already in this conversation and repository.
- **Repository:** `inrangeai/in-range`, with the authorized `hazypiff/in-range`
  mirror when credentials permit.
- **Current implementation line:** `fix/w5-convergence-2026-08-04`.
- **Known reviewed starting object:**
  `1d0b6c53e89da464923f8e8d814da7056ad24488`.
- **Controlling repair packet:** fetch
  `origin/docs/android-panel-assist-2026-08-03` and read
  `docs/research/2026-08-01-hardening/WAVE_A_PANEL_REVIEW_1D0B6C5_2026-08-05.md`
  at docs commit `07a79b2`.
- **Controlling full work orders:** also read
  `MAC_THREE_MODEL_CONVERGENCE_WORK_ORDER_2026-08-04.md` and
  `MAC_HARDWARE_PANEL_WORK_ORDER_2026-08-03.md`. This directive strengthens their
  completion behavior; it does not weaken a technical predicate.
- **Stack:** use the existing Flutter/Dart, Swift/iOS, Xcode, shell, GitHub
  Actions, `devicectl`, and repository tooling exactly as established.
- **Devices:** the three owner-confirmed test iPhones are the iPhone 14,
  iPhone 13, and iPhone 15 Plus. Use committed role labels such as
  `slotA/slotB/slotC`; never commit UDIDs, serials, CoreBluetooth UUIDs, raw
  tokens, credentials, or user paths.
- **Production contract:** W5 remains compile-disabled in production unless a
  later, separate owner decision explicitly enables it. Completing this work
  may make PR #11 integration safe while W5 remains disabled; it does not
  silently resolve the separately deferred H-W5-7 release-enablement design.
- **Already-ratified decisions:** keep `sendWakePing` as the production feature
  with its separate P1 credential-lifecycle follow-up; keep the v1 wire format
  without `HELLO_ACK prevAlias`; do not smuggle H-W5-7 re-keying into this work;
  `resetCase` retains the fleet key; destructive secret clearing is distinct
  and allowed only after all relevant W5/evidence producers are stopped.
- **Model substitution:** do not reopen the old Opus availability blocker. The
  owner already authorized `claude-opus-4-8` as the Opus 5 substitute if a
  genuine Opus 5 backend is unavailable. If genuine Opus 5 is now available,
  use it and record the actual identity. Never claim a backend you did not use.

### Current open work — all of it is mandatory

First, print a numbered plan that includes every unchecked item in your current
todo tracker verbatim and maps each one to a test/evidence gate. At minimum the
open list contains:

1. **Commit sanitized hardware evidence to PR #11; fix and retest every exposure.**
2. **Finish the W5 persisted-restoration schema and hardware acceptance.**
3. **Finish Phases 5–7:** rerun the three-iPhone matrix with forced Case 1,
   real-jetsam Case 3, narrow Case 4, the evidence bundle, and a blinded panel
   on the exact final SHA.
4. **E-B1 end-to-end proof:** a genuinely committed hit through
   `dropPeerByToken`, raw-session cleanup, a real `SwipeFeed` widget test, and
   durable sanitized evidence for every outcome.
5. **E-B2 proof surface:** restoration classification, no-token `dialStart`,
   physical-drop attribution, send/direction/role events, an installed
   selected-peer UI, and a one-shot fault-conditional delay.
6. **Panel repair packet C1–C5:** second-hop puller symlink containment;
   effective native W5-OFF teardown; destruction that cannot regenerate an
   unattested fallback while producers are live; current-key gating before
   restored keyed events; and transactional foreign-flavor wiping.
7. **Evidence repair packet E1–E3:** honest exact-SHA CI wording, fresh exact-SHA
   reviewer artifacts, independently verifiable native logs/hashes, and the
   complete changed-file/artifact manifest.

Inspect the actual tracker after fetching. If it contains another unchecked
in-scope item, add it and finish it. Preserve the 54+ completed items and rerun
their regression gates; do not redo or reinterpret them without a deterministic
regression.

### Success criteria — all must be true

1. Every current in-scope todo is complete; no `TODO`, stub, placeholder,
   controlling skip, or narrative `PARTIAL` remains.
2. All analyzer, Dart, Swift, integration, puller, privacy, isolation, mutation,
   schema, widget, artifact, and hardware validators pass at the final source
   tree. Project-generated errors and warnings are zero. Third-party update
   notices are informational but must not hide a project warning.
3. Every new failure mode has a committed verifier-owned red-before/green-after
   test or mutation. A comment or self-reported manual observation is not proof.
4. Production and diagnostic bundles pass the paired whole-bundle negative and
   positive controls. Production contains no W5 diagnostic code, controls,
   names, canary, or secret plumbing.
5. The installed diagnostic artifact is clean-built from the frozen code SHA,
   signed, hashed, inspected, and is the exact artifact used for preflight and
   all matrix cases.
6. Cases 1–4 are mechanically PROVEN from attributed sanitized event chains and
   positive controls. Smoke, timing inference, retry-floor silence, app-switcher
   kill, `devicectl` process kill, or Android substitution is not proof.
7. Only sanitized evidence is committed. Raw pulls remain in protected scratch
   storage and are removed after validation. The final whole-tip privacy scanner
   reports clean.
8. Two non-author reviewers independently approve each authored lane, and the
   final blinded Kimi 3 + GPT Sol/Opus panel signs the same code SHA, diagnostic
   artifact hash, final evidence SHA, and manifest.
9. The final evidence commit is a non-force descendant of `c816f09`; PR #11's
   draft head is advanced to it only after the gates below. PR #11 is not merged.
10. Every new pattern, environment input, schema decision, test command, retry,
    artifact hash, and known limitation is documented without sensitive values.

### Operating rules — non-negotiable

1. **Plan first.** Begin by outputting a numbered end-to-end task list and gate
   map before editing code. Then execute it in the same run.
2. **Work autonomously.** Do not ask for clarification unless a product choice,
   permission, credential, or physical action truly cannot be derived or
   performed. The decisions listed above are already resolved.
3. **Do not stop at internal gates.** `CODE_READY`, `PREFLIGHT_READY`, and
   `MATRIX_READY` are progress states. Continue automatically through the next
   stage. A panel `HOLD` is a repair queue, not a handoff.
4. **Self-verify after every logical step.** Run the focused red/green test,
   inspect the actual output, and rerun every affected suite before integrating.
5. **Debug your own failures.** Diagnose, repair, and rerun. Simulator clone
   contention may justify one documented serial retry; it may not justify
   suppressing or relabeling a failure.
6. **Use every relevant available tool.** Use clean Git worktrees, Xcode,
   `devicectl`, the physical test devices, CI, artifact download/inspection,
   Kimi 3, GPT Sol, the authorized Opus backend, and primary Apple documentation
   where needed. Do not use tools ceremonially or expose sensitive material.
7. **No placeholders.** Implement real application paths and real states. A
   test-only route that bypasses `SwipeFeed`, `BeaconService`, the registered
   native router, or the installed UI does not close E-B1/E-B2.
8. **Keep a durable progress ledger.** Record completed, in-flight, decisions,
   commands/exits, exact SHAs, and blockers. This ledger is evidence, not a
   reason to check in with the owner.
9. **Continue parallelizable work around blockers.** A GitHub billing failure,
   disconnected phone, or denied mirror push does not pause code, local tests,
   artifacts, documentation, or panel work.
10. **Protect scope and privacy.** No raw secret, token, ID, UDID, serial,
    Bluetooth UUID, account data, user path, or raw device log may enter Git,
    an LLM prompt, or a transcript. Use run-scoped HMAC handles and value-free
    fingerprints only.
11. **Preserve history.** No force-push, rebase of shared reviewed history,
    history rewrite, destructive device erase, production deploy, PR merge, or
    W5 release enablement. Use separable non-force commits.
12. **Check every success criterion before stopping.** The only successful
    terminal response is `MERGE_READY`; the only other terminal responses are
    the precise blocker forms defined below.

### Required execution sequence

#### 1. Pin reality and freeze the ledger

Fetch both remotes and the docs branch. Prove branch tips, PR #11 head, ancestry,
worktree cleanliness, tool versions, model identities, connected-device roles,
and current CI billing state. Do not trust prior prose.

If `fix/w5-convergence-2026-08-04` has advanced beyond `1d0b6c5`, do not reset
or discard it. Prove whether it is a descendant, inventory the delta, and verify
that every C1–C5 predicate is carried forward. If it diverged, create a clean
coordinator integration branch and preserve both histories without rebasing.

Copy the resolved product contracts and all open acceptance predicates into one
ledger. Record actual backend identities. Give each reviewer only the exact SHA,
requirements, and fixtures on its first pass—never another reviewer's verdict.

#### 2. Close C1–C5 before collecting evidence

Treat `WAVE_A_PANEL_REVIEW_1D0B6C5_2026-08-05.md` as controlling. At minimum:

- Reject a `<case>.rev.*` entry that is itself a symlink; require canonical
  containment directly under canonical `OUT_ROOT`; carry only the sanctioned
  `<label>_<artifact>` set. Add the exact two-hop escape fixture and prove failed
  publication preserves prior evidence and never touches the outside target.
- Replace the Boolean `setW5Links(false)` acknowledgment with an atomic native
  effective-OFF transaction. It must close/reap all W5-specific live and
  restored sessions, links, ownership leases, inflight work, timers, and stale
  snapshot state before reporting `effectiveEnabled=false` and quiescent. Dart
  must fail closed unless the structured ack proves both.
- Make `destroySessionSecret` truthful for every diagnostic evidence producer.
  It must reject while a relevant scanner/manager/heartbeat/emitter is live, or
  enter a durable unprovisioned state in which keyed emits cannot regenerate a
  fallback until fleet provisioning. Test beacon-on/W5-off scanning explicitly.
- Ensure the current artifact's authoritative fleet key is available before a
  restored manager can emit a keyed event. For an A-to-B artifact-key change,
  prove no handled event is emitted under A and no required restoration proof is
  erased when B becomes authoritative.
- Make foreign-flavor wipe transactional: inspect every typed family/rotation
  result before deleting keys or advancing the stamp; a failed wipe may not
  append a new-key success record to stranded old evidence.
- Extend protection-class read-back verification and typed accounting to normal
  create/append/rotation, not only replacement. Preserve loss counters until a
  durable record or sanctioned export acknowledges them.

For each repair, first commit a failing regression/mutation, then the repair in
a separable commit. Run both non-author attacks, repair every reproducible
finding in-round, and continue until both return PASS on the same lane SHA. Do
not return `WAVE_A_READY` to the owner; continue into the remaining work.

#### 3. Finish the persisted-restoration schema

Finish the existing W5 snapshot/schema todo through the real registered router
and controller. Freeze the current schema requirements from the code and tracker,
then at minimum prove:

- an explicit version and flavor boundary;
- atomic, protected persistence with no partial state presented as valid;
- committed ownership/lease identity, relevant link metadata, generation,
  alias/grace state, and timers restore consistently;
- unknown/future, corrupt, partial, wrong-flavor, expired-grace, and internally
  inconsistent snapshots fail closed with a structured sanitized reason;
- supported prior schema data either migrates deterministically or is rejected
  and wiped by an explicit documented rule;
- no restore occurs under an unconfirmed current fleet key;
- restoration re-arms only valid deadlines and never leaves an immortal lease,
  duplicate keeper, leaked pending dial, or stale raw session;
- reset, destructive secret clearing, beacon OFF, pass teardown, and
  foreign-flavor transition update or erase snapshot state transactionally.

Add native unit/property fixtures for each state and run the real-jetsam hardware
acceptance below. Do not call a cold reconstruction “restoration.”

#### 4. Finish E-B2—the installed proof surface

Complete a production-invisible, diag-only selected-peer UI reachable through
the installed app and `BeaconService`:

- list eligible peers as run-scoped handles only; retain raw mapping natively;
- select one peer, atomically arm a peer-scoped one-shot pre-ACK fault plus an
  optional delay, show the native structured ack/status, disarm, and reset;
- nil, empty, wildcard, stale, and wrong-peer selections fail closed;
- the delay applies exactly once and only when the selected fault is armed;
- two simultaneous peers prove wrong-peer non-consumption and intended-peer
  exactly-once consumption;
- production UI, methods, strings, symbols, and event/control names are absent
  from the whole production bundle.

Complete the machine-verifiable join graph before hardware. Restoration
classification, locked/no-token `dialStart`, physical drop, HELLO, HELLO_ACK,
PROPOSE, ACK, REJECT, alias rotation, grace entry/bypass/recommit, fault
lifecycle, and teardown must carry every available run-scoped
`peripheral/peer/link/lease`, direction, role, result, and reason **before** the
state is removed. Add positive and deliberately broken chain fixtures; reject a
timestamp-only inference.

#### 5. Finish E-B1—the real pass effect chain

Make a real `SwipeFeed` widget pass execute and await the full application path:

1. distinguish server `encounter_id` from evidence-backed `radioAlias`;
2. dismiss/perform the frozen server action in the documented order;
3. send only a trustworthy fresh/stale radio alias to the real
   `BeaconService.dropPeer` platform seam;
4. route through the same native handler registered by `attach` and the real
   `dropPeerByToken` controller path;
5. close every applicable inbound/outbound/raw physical session, erase the
   committed ownership lease, and return a raw-ID-free structured result;
6. await a durable sanitized evidence acknowledgment before reporting success.

Tests must cover a genuinely committed hit, raw-session-only cleanup, inbound
only, outbound only, two-role, committed-plus-raw, repeat/idempotent miss,
fresh/stale alias classification, server alias unavailable, native unavailable,
and evidence-write failure. `rawSessionsReaped > 0` is never a miss, and native
unavailable never claims native evidence persistence.

Preserve the narrow Case-4 contract: a pass tears down the **currently mapped
lease** when a trustworthy alias exists. It does not create a durable identity
veto or promise no later redial.

#### 6. Rebuild every code and artifact gate

At the frozen candidate source SHA, run the complete repository gates, including:

```bash
flutter analyze
flutter test

xcodebuild test \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:RunnerTests \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO

xcodebuild test \
  -workspace ios/Runner.xcworkspace \
  -scheme diag \
  -configuration Debug-diag \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:RunnerTests \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO

bash scripts/check_release_isolation.sh
bash scripts/check_final_binary_isolation.sh
bash docs/research/2026-08-01-hardening/hw_matrix_pull_test.sh
git diff --check
```

Also run every committed schema, event-chain, privacy, whole-tip, mutation, and
shell syntax validator. Derive and enforce the exact final native discovered
test set; do not rely on the old `40/70` minimum floors. Discovered must equal
passed, failures/skips must be zero, and the new controlling tests must be named
in the raw logs.

Build and inspect production independently. Then clean a separate detached
worktree at the candidate source SHA, provide the real fleet key only through
the approved untracked/environment input, and build the signed diagnostic
artifact. Record source SHA, artifact SHA-256, signing identity, bundle/Mach-O
inventory, Runner/App hashes, and positive/negative isolation results. Never
print or commit the key; fingerprint only.

Dispatch exact-SHA iOS CI once. Verify the run's actual `head_sha`, jobs, steps,
counts, skips, and uploaded artifacts. The prior evidence packet falsely said
`ios-build.yml` ran at `1d0b6c5`; do not repeat that error. If GitHub still
returns the zero-step billing/spending-limit annotation, record the exact run
and continue every local/device stage. It is an external CI blocker, not a
reason to stop early or repeatedly redispatch.

#### 7. Continue through preflight without returning a checkpoint

`CODE_READY` and `PREFLIGHT_READY` are internal ledger entries only. Once the
candidate source SHA has clean code reviews and the exact signed diagnostic
artifact is frozen, install that artifact on one registered test iPhone and run
the combined preflight from the convergence work order: key continuity, reset,
selected-peer controls, wrong/right peer consumption, 100+ monotonic events,
rotation/integrity, injected loss accounting, extraction negative control,
successful sanitize/validate/publish, and artifact-hash binding.

If a preflight defect changes code, repair it, rerun both non-author reviews,
all code/CI/artifact gates, clean-build a new signed artifact, reinstall, and
repeat preflight. Do not reuse evidence or signatures from a superseded SHA.

If the phone is disconnected, locked, untrusted, or requires a human-only
gesture, finish every independent task first. Then return one consolidated
`PHYSICAL_ACTION_REQUIRED` request with exact device roles and steps—never
piecemeal requests. Resume automatically after the action.

#### 8. Execute the full three-iPhone matrix

Use the exact artifact that passed preflight and sanitize through the repaired
puller. Record roles and HMAC handles before each case. Every negative assertion
needs a same-run positive control.

**Case 1 — selected-peer pre-ACK reclamation**

- Arm the intended peer through the installed UI.
- Make the one-shot fault/delay actually reach the pre-`HELLO_ACK` window.
- Introduce the third phone during that forced window.
- Prove the same peer/link's pending dial was created and reclaimed by explicit
  failure or the 20-second TTL sweep.
- Disarm and prove a later clean commit, no leaked contender/pending dial, and
  one keeper per valid encounter.
- A normal three-peer convergence or “zero sweeps” is only smoke.

**Case 2 — drop, rotate, grace reconnect**

Independently prove all of: committed keeper drop; token rotation before
reconnect; `ALIAS_ROLL` could not traverse the dropped link; same-lease recommit
inside 120 seconds; token-cache bypass; retry-floor bypass; and a current-message
positive control.

**Case 3 — genuine jetsam restoration**

- Use genuine OS memory-pressure/jetsam on the suspended app and retain a
  sanitized system termination reason proving jetsam.
- Do **not** use app-switcher force-quit, `devicectl`/developer-process kill,
  controlled crash, or cold relaunch as a substitute.
- Prove a new launch epoch entered actual `willRestoreState`, restored central
  and peripheral objects, rebound control and keepalive characteristics,
  restored both subscriptions, accepted the valid snapshot/schema, preserved
  the same lease/keeper, resumed traffic, rejected a stale generation, and then
  accepted a current positive control.

**Case 4 — narrow mapped-lease teardown**

- Establish a committed local-token lease and pass the matching local card.
- Prove trustworthy alias freshness, native lookup hit, every applicable role
  closed, raw sessions reaped, physical session ended, ownership lease erased,
  durable evidence acknowledgment, and idempotent repeat.
- Repeat required inbound-only, outbound-only, and two-role topologies as
  specified by the existing work order/tests.
- A server-backed card with no evidence-backed alias must report teardown
  unavailable and must never send `encounter_id` to the alias boundary.
- Include an unswiped-peer positive control. Never describe a short silent
  interval as durable no-redial.

Android may exercise shared Dart regressions but cannot satisfy these native iOS
acceptance gates.

#### 9. Commit sanitized evidence and run the final blinded panel

Commit no raw logs. The sanctioned hardware evidence tree must contain only:

- the exact candidate source SHA and ancestry;
- final evidence SHA;
- signed diagnostic artifact hash and production artifact hashes;
- value-free device roles/OS versions;
- sanitized per-device/per-case JSONL;
- schema/join/sequence/positive-control validator output;
- commands, exits, exact test counts, zero skips, CI URL/status, and documented
  infra retry;
- changed-file and artifact manifest;
- disagreement/follow-up ledger and the separate PR-integration/W5-enablement
  decisions.

After hardware passes, commit the sanitized evidence and final exit manifest on
the convergence line. This produces `FINAL_EVIDENCE_SHA`. Prove that executable
source/config trees are byte-identical to the frozen artifact source SHA; rerun
the full non-device validation at `FINAL_EVIDENCE_SHA`. If executable code
changed, invalidate the artifact and all hardware evidence and repeat from the
new source SHA.

Run the final panel blinded in separate clean worktrees:

- use `kimi -m kimi-code/k3` for Kimi 3;
- use `codex` only after it self-reports the intended GPT Sol backend;
- use genuine Opus 5 if available, otherwise the already-authorized
  `claude-opus-4-8` substitute;
- an author never approves its own lane;
- each reviewer independently receives the source SHA, final evidence SHA,
  artifact hashes, work orders, controlling HOLD report, manifest, validators,
  and sanitized evidence—but not another verdict;
- each must execute its decisive fixtures, state its strongest falsification,
  and issue binary per-predicate verdicts;
- feed every reproducible in-scope finding back into repair immediately. Do not
  stop with “awaiting another panel.” Repeat until all exact-SHA verdicts are
  clean or a genuine external blocker remains.

Commit two fresh exact-SHA non-author attestations plus the coordinator's final
attestation on the docs branch, with tool/backend identity, commands/exits,
falsification, artifact hashes, and verdict. Mark the old `0af42a1` attestation
files withdrawn or superseded. Supply privacy-sanitized native logs whose
published hashes can be recomputed. Do not mutate the signed implementation or
final evidence SHA with after-the-fact attestation prose.

#### 10. Advance draft PR #11 and both remotes

Only after the code, artifact, preflight, matrix, sanitized evidence, and blinded
panel gates are satisfied—and either exact-SHA CI passes or the exact-current
zero-step billing blocker is documented under the existing R6 external-blocker
clause:

1. prove `c816f09` is an ancestor of `FINAL_EVIDENCE_SHA`;
2. non-force push the final convergence branch to `inrangeai`;
3. non-force fast-forward PR #11's head branch
   `integ/mac-hardening-2026-08-01` to `FINAL_EVIDENCE_SHA`;
4. update the draft PR #11 description with exact source/evidence SHAs, artifact
   hashes, test/matrix summary, and links to sanitized evidence/attestations;
5. push the docs branch and mirror the corresponding final branches to
   `hazypiff` using only already-authorized credentials;
6. verify both remote refs and PR head after push.

If billing remains the sole unmet gate, advancing the **draft** PR is authorized
so its sanitized evidence and completed code are reviewable, but the PR body
must say `CI_EXTERNAL_BLOCKER` and it is not `MERGE_READY`. The terminal response
in that state is the precise `EXTERNAL_BLOCKER`, not success. Only an exact-SHA
green CI run can remove that final qualification.

If the mirror returns 403, do not seek or repurpose credentials. Record that one
external mirror blocker after the authoritative `inrangeai` push. Keep PR #11
draft. Do not merge, deploy, force-push, rewrite history, or enable W5.

### Genuine blocker rules

You may stop only with one of these:

- `PHYSICAL_ACTION_REQUIRED` — every independent task is complete and one
  consolidated human-only cable/unlock/trust/jetsam setup action is required;
- `EXTERNAL_BLOCKER` — every independent task is complete and an exact missing
  permission, credential, GitHub billing state, unavailable external service,
  or unresolved product decision prevents the final gate;
- `MERGE_READY <FINAL_EVIDENCE_SHA>` — every success criterion passed, both
  remotes/PR were updated as authorized, and the final packet is complete.

A blocker response must name: the single blocked predicate; exact command and
exit/annotation; why no safe local substitute satisfies it; everything completed
around it; and the one owner action that unblocks it. “Still working,”
“checkpoint,” `PARTIAL`, `WAVE_A_READY`, `PREFLIGHT_READY`, `MATRIX_READY`, or
“awaiting panel” are forbidden terminal responses.

GitHub Actions billing is already a known possible external condition. Attempt
the exact final workflow once. If it still fails with zero steps for billing,
finish local builds, artifact inspection, physical preflight, matrix, evidence,
review, and the authorized draft PR update before returning that **single**
remaining external blocker. Never call the workflow green or claim it ran at a
SHA that has no run.

### Final deliverable

Return one terminal packet containing:

- `MERGE_READY <FINAL_EVIDENCE_SHA>` or one precise allowed blocker;
- a criterion-by-criterion PASS table;
- exact source SHA, final evidence SHA, ancestry, branch tips, and PR #11 head;
- every file created/modified and every logical commit;
- exact commands, exits, analyzer/test counts, failures, skips, and retries;
- production/diagnostic artifact hashes, signing identity, and whole-bundle
  inspection inventory;
- one-phone preflight and Cases 1–4 required-vs-observed event chains with
  positive controls;
- privacy/sanitization proof and recomputable evidence/log hashes;
- three independent reviewer attestations and disagreement dispositions;
- how to build, install, test, and review the draft PR;
- separate recommendations for **PR integration while W5 remains disabled** and
  **W5 release enablement**;
- known limitations and only genuinely deferred, out-of-scope follow-ups.

Begin now by outputting your numbered plan. Then execute end-to-end without
checking in until `MERGE_READY` or genuinely blocked under the rules above.

## Copy/paste prompt ends here
