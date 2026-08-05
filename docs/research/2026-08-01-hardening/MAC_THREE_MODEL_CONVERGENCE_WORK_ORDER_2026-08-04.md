# Mac three-model convergence work order — 2026-08-04

This is the replacement dispatch for the Mac coordinator with access to Kimi3,
Claude Opus 5, GPT Sol, Xcode, and the three registered iPhones. It supersedes
the earlier pattern of making a patch, asking for another audit, and returning
to the owner with a new partial checkpoint.

The objective is not another review. The objective is to **implement, attack,
repair, integrate, and verify until one exact SHA earns an executable green
light**.

## Copy/paste dispatch to the Mac coordinator

> Fetch `origin/docs/android-panel-assist-2026-08-03` and read
> `docs/research/2026-08-01-hardening/MAC_THREE_MODEL_CONVERGENCE_WORK_ORDER_2026-08-04.md`
> plus the exact Round-4 report
> `PHASES_1_4_PANEL_REVIEW_ADB475C_2026-08-04.md`. Execute the work order in
> full using Kimi3, Claude Opus 5, and GPT Sol as named below.
>
> Do not stop after reporting findings. Once the acceptance ledger is frozen,
> continue autonomously through implementation, adversarial tests, integration,
> full local validation, exact-SHA CI, production-artifact inspection, and
> independent re-verification. A new finding is work to assign and close, not a
> reason to return another narrative checkpoint.
>
> Ask the owner only for an actual product decision, unavailable credential or
> permission, destructive history operation, or physical-device interaction.
> Test failures, reviewer findings, implementation difficulty, merge conflicts
> between your own lane branches, and additional non-destructive commits are not
> stop conditions.
>
> Start from exact implementation commit
> `adb475c47042f76948ef111fe31d2a762388137a`. Keep PR #11 frozen at
> `c816f09`. Create and push a new convergence branch; do not stack it, merge,
> deploy, rewrite history, or install on phones until the corresponding gate in
> this work order authorizes that action.
>
> **OWNER RULING — ratified by sending this dispatch:** for the diagnostic
> matrix, the shared fleet key persists across relaunch/restoration and case
> resets. `resetCase` retains it and rotates only the public evidence epoch;
> destructive secret clearing is a separate operation allowed only while W5 is
> stopped. Record this exact value-free ruling as owner provenance—never the key.

## Fixed inputs and scope

- Repository: `inrangeai/in-range`.
- Implementation baseline:
  `adb475c47042f76948ef111fe31d2a762388137a` on
  `fix/w5-hardware-evidence-2026-08-03`.
- Controlling independent report commit:
  `88892d3b3407ce9991ff71bc0fa3bdde47f9d0f0` on
  `docs/android-panel-assist-2026-08-03`.
- Controlling report:
  `PHASES_1_4_PANEL_REVIEW_ADB475C_2026-08-04.md`.
- Suggested new implementation branch:
  `fix/w5-convergence-2026-08-04`.
- PR #11 remains open/draft/frozen at `c816f09`; it is not the validation branch.
- W5 remains release-disabled until the final gate. These are release-enablement
  and evidence-integrity blockers, not a claim of a live production compromise.

Before editing, fetch both remotes and prove that the baseline object exists,
that the implementation branch still names it, and that the worktree is clean.
If upstream has moved, preserve the reported object and record the graph; do not
silently rebase the evidence. Create separate clean worktrees for each model and
one coordinator-owned integration worktree.

Record the exact model/product identifiers and invocation mode for Kimi3, Opus
5, and GPT Sol. Do not silently substitute a smaller model. Do not put secrets,
raw device identifiers, tokens, UUIDs, account data, or unsanitized logs into an
LLM prompt or transcript.

## Four distinct green lights

There is no generic “looks good” verdict. The only gates are:

1. **`CODE_READY`** — every frozen B1–B6 predicate and the full local integration
   suite pass on one exact code SHA, and the two non-authors approve every lane.
   This is an internal gate, not a reason to stop or install.
2. **`PREFLIGHT_READY`** — `CODE_READY` plus exact-SHA CI, independent production
   artifact inspection, a separately clean-built and inspected signed diagnostic
   artifact, three final code signatures, and a dry-validated consolidated
   operator checklist. This authorizes installation on one iPhone for the
   combined preflight, not the three-phone matrix.
3. **`MATRIX_READY`** — the one-phone preflight passes against the exact signed
   diagnostic artifact named in the `PREFLIGHT_READY` manifest, which binds its
   hash to the `CODE_READY` code SHA, and its sanitized evidence validates
   mechanically.
4. **`MERGE_READY`** — the three-iPhone matrix passes, the final evidence bundle
   names the same code and artifact hashes, and all three models independently
   sign the exact SHA and manifest. Only this gate can support a separate owner
   decision to move PRs or enable W5.

`PARTIAL`, `SCOPED PASS`, an inferred event chain, a green workflow with a
controlling skip, or “no remaining objections” satisfies none of these gates.

## Contract freeze — do not reopen these decisions

The panel must copy this ledger into its working manifest before changing code.
Tests may strengthen it but may not weaken or reinterpret it to turn red green.

- W5 and every diagnostic control remain compile-gated and absent from
  production behavior and artifacts.
- A server `encounter_id` never crosses an alias-keyed native boundary.
- An evidence-backed stale radio alias may be attempted, but freshness and the
  exact native outcome must be reported. Never fabricate an alias.
- A raw-session-only reap is not a teardown miss.
- Native-unavailable cannot be described as natively persisted evidence.
- A pass implements immediate teardown of the currently mapped radio lease when
  a trustworthy alias exists. It does not create a durable no-redial identity
  ledger.
- One shared fleet secret spans one diagnostic matrix run. A case reset retains
  that secret, wipes/rotates the evidence epoch, clears controls, and resets
  sequence/run state. Secret destruction is a separate stopped-W5 operation.
- No wildcard fault or delay target is allowed.
- The v1 wire format remains frozen; no `HELLO_ACK prevAlias` field is added.
- H-W5-7 stable-identity re-key remains a separate release-enablement design
  gate. Do not disguise it as an instrumentation fix.
- Do not execute a history rewrite or force-push. Only repair the value-free
  proposal.

If implementation genuinely requires changing one of these product contracts,
that is an owner decision and the sole affected lane may pause. Other lanes must
continue.

## Model ownership and anti-collusion

All three models first receive only the exact baseline, frozen ledger, and their
lane requirements. Each records its own reproduction and proposed acceptance
tests before reading another model's verdict.

| Wave | Primary implementer | Non-author verifiers | Scope |
|---|---|---|---|
| A | Claude Opus 5 | Kimi3 + GPT Sol | B3/B4 atomic session, writer, reset, extraction substrate |
| B | Kimi3 | Opus 5 + GPT Sol | B2 installed selected-peer controls and attributable proof graph |
| C1 | GPT Sol | Kimi3 + Opus 5 | B1 SwipeFeed → native → durable result chain |
| C2 | Opus 5 | Kimi3 + GPT Sol | B5 paired release/diag isolation gate |
| C3 | Kimi3 | Opus 5 + GPT Sol | B6 tip hygiene, executable scan, rewrite proposal |
| Final | coordinator integrates | all three independently | unknown-unknown sweep and exact-SHA gate |

Waves A and B are sequential because they overlap in Swift state and event
schema. C1–C3 may proceed in parallel only after both A and B are integrated and
only in separate worktrees. The coordinator alone cherry-picks reviewed commits
into the integration branch and resolves overlap by rerunning every affected
lane's tests.

An author cannot approve its own lane. Each non-author must inspect the patch,
run the decisive tests, and state its strongest falsification attempt. At least
one verifier-owned regression or mutation must be demonstrably red before each
B1–B6 fix and green afterward. Repository prose and an implementer's self-
reported counts are not evidence.

## Wave A — B3/B4 atomic evidence substrate

Implement one serialized diagnostic-session boundary covering the current
secret, public case epoch, sequence, fault, delay, run label, and every evidence
file operation.

### B3 required behavior

1. Native must possess the matrix fleet key before W5 managers can emit a keyed
   event. On first launch, either provision before native start or hold W5
   fail-closed until provisioning succeeds. Restoration must recover the same
   persisted/injected key before restored managers emit.
2. One event snapshots one immutable `{secret, keyEpoch, caseEpoch}` and derives
   every peer/lease/link/peripheral handle from that snapshot inside the
   serialized boundary. A key cannot change between fields or silently inside
   one file epoch.
3. Provisioning a different key while an evidence epoch is active must either
   be rejected or atomically close/rotate/wipe and begin a visibly new key
   epoch. Never continue the same JSONL invisibly.
4. `resetCase` retains the fleet secret, waits for in-flight writes, wipes every
   current and rotated artifact, clears fault/delay, resets sequence/run state,
   and rotates a non-secret case epoch.
5. `destroySessionSecret` requires W5 stopped and is distinct from case reset.
6. Provision, reset, and destroy return structured acknowledgments. No silent
   `try?`; no comments that contradict the executable lifecycle.

Mandatory tests include:

- concurrent provision cannot mix keys within one event;
- one file/key epoch never contains two secrets;
- reset retains the fleet secret and rotates case epoch;
- reset clears fault, delay, sequence, run label, and all rotations;
- reset serializes with an in-flight append;
- secret destruction is rejected while W5 is active;
- short, odd-length, or non-hex secrets do not mutate state;
- restoration before Dart uses the persisted fleet key;
- startup cannot emit before the key is ready;
- the injected-secret test executes in normal and exact-SHA CI—no skip.

### B4 required behavior

1. One writer abstraction owns append, rotate, trim, replacement, close,
   protection, backup exclusion, delete, reset, and the authoritative artifact
   inventory, including every `.1` rotation.
2. Replacement/rotation reapplies and verifies protection and backup exclusion.
   Every failure is typed and counted by file family and operation.
3. Loss counters use `peek → durable evidence record → acknowledge`. A failed
   boot append cannot erase prior loss.
4. Wipe/reset executes under writer/session locks and cannot race append or
   trim.
5. File-size/read/close failures are accounted where their loss matters.
6. Injectable file operations cover rotate, protect, backup, trim, delete,
   close, wipe, and boot-record failure.

Required tests must prove successful behavior and each injected failure. A test
that skips attribute assertions on simulator does not close the physical
attribute preflight; it only closes logic.

### Fail-closed pull/sanitize/publish chain

Before creating an output directory or contacting a phone, require an
even-length hexadecimal secret of at least 64 characters. Pull into a fresh
staging directory. Treat primary event evidence and case-required artifacts as
mandatory; distinguish an absent optional rotation from transport, permission,
container, and parse failures.

Strictly parse JSONL and reject malformed/torn lines, sequence regression,
mixed epochs, domain mismatch, unexpected raw identifiers, or missing required
event fields. Post-scan sanitized output, then publish atomically. A failed run
must leave neither partial output nor stale content under the requested label.
State whether a database is raw scratch or produce a sanctioned sanitized
export; never label a raw copy sanitized.

Commit a fake-`xcrun` test harness proving invalid input performs zero pulls and
creates zero output, transport/permission failures are nonzero, optional `.1`
absence is accepted, missing primary evidence fails, native and puller HMACs
match fixtures, malformed JSON never falls back to regex text, raw-ID post-scan
fails, and stale destination content cannot survive a failed run.

Wave A closes only when both non-authors agree that no call can change key,
epoch, control state, sequence, or file lifecycle outside the serialized
boundary.

The coordinator must also preserve a durable, value-free owner decision record
for fleet-key persistence. If the work order arrived in an owner-sent message,
the `OWNER RULING` in the copy/paste dispatch is that record's source; archive
the exact ruling and message reference without claiming the coordinator wrote
it. If the work order was fetched without an owner-issued dispatch, request this
single ruling as `EXTERNAL_BLOCKER` immediately while all code lanes continue.
It must be resolved before `PREFLIGHT_READY`, not used to pause implementation.

## Wave B — B2 installed control and machine-verifiable proof graph

Build an installed, diag-only surface that can drive the exact physical cases.
It must not expose raw identifiers.

1. Native returns the currently eligible peers as run-scoped handles and retains
   the private mapping internally. Dart selects a handle, never a raw token.
2. One atomic call arms a **peer-scoped**, one-shot pre-ACK fault plus optional
   HELLO delay for that selected peer. Unknown/stale/nil/empty/wildcard targets
   fail closed.
3. The installed surface displays structured native acknowledgment and current
   status, and supports explicit disarm and case reset.
4. Every operation is reachable through `BeaconService`; no low-level channel
   method without an application caller counts.
5. Production builds contain neither the surface nor its event/control names.

Complete the evidence join graph before hardware:

- token resolution joins `peripheral + peer + link` for a locked/no-token dial;
- physical drop records `peripheral + peer + link + lease` before state is
  removed;
- HELLO, HELLO_ACK, PROPOSE, ACK, and REJECT record direction, role, peer, link,
  lease, and result wherever known;
- alias rotation, grace entry/bypass/recommit, and retry/cache bypass remain
  joinable through the same lease and old/new peer handles;
- restoration records actual `willRestoreState`, restored counts,
  characteristic rebind, both subscriptions, resumed traffic, and ownership;
- the cold-launch marker occurs at a deterministic, tested point relative to
  manager construction and restoration callbacks, so it cannot masquerade as
  or obscure a restoration launch;
- arm, delay consumption, fault firing, disarm, and reset carry the selected
  peer and applicable link.

Commit a schema/event-chain validator with positive and deliberately broken
fixtures for Cases 1–3. It must reject missing or mismatched handles rather than
infer identity from timestamps.

Tests must cover the installed widget, two simultaneous peers, wrong-peer
non-consumption, exactly-once consumption, stale selection, explicit disarm,
reset clearing, join completeness, and production invisibility.

## Wave C1 — B1 complete pass effect chain

Make the real `SwipeFeed` path executable in tests and truthful in evidence.

1. `_doPass` must await the required dismissal/server action, native teardown,
   and durable evidence acknowledgment in the frozen order. Document and test
   the order; do not use `unawaited` for the controlling outcome.
2. Outcomes distinguish lease-ended, raw-session-reaped-without-lease, genuine
   miss, server-alias-unavailable, native-unavailable, and evidence-write-failed.
3. `rawSessionsReaped > 0` cannot be reported as a miss. Native-unavailable must
   report `evidenceRecorded=false`.
4. The native result contains no raw identifier. Raw-session cleanup is tested
   with an injected registry/connection adapter, not a field-soak assertion.
5. Fresh versus stale alias classification remains visible and matches actual
   resolver behavior.

Required tests:

- a real `SwipeFeed` widget pass on a fresh local card sends only `radioAlias`,
  reaches the real platform seam, awaits the structured result, and persists a
  durable acknowledgment;
- a server card dismisses by `encounter_id` but never sends that ID to native;
- stale alias hit/miss is labeled honestly;
- native unavailable remains unrecorded;
- raw-session-only reap is not a miss;
- inbound-only, outbound-only, two-role, committed-plus-raw, and idempotent
  repeat outcomes;
- the registered platform handler exercises the same router used by `attach`.

## Wave C2 — B5 non-vacuous whole-bundle isolation

Use one generated, public, non-secret 64-hex canary for a paired build:

- production receives the canary through every supported diagnostic-secret
  input but does **not** enable `INRANGE_DIAG`;
- diagnostic receives the same canary and enables only the diagnostic
  compile/flavor input;
- production contains zero canary/key-label/control/event/evidence-name hits;
- diagnostic contains the expected positive markers and canary.

Recursively enumerate every Mach-O in the `.app`, including Runner, Flutter,
App, plugins, nested frameworks/dylibs, and extensions. Run symbol and string
checks on every executable, assert the inventory is nonempty and includes the
expected core binaries, and fail on every `file`, `nm`, `strings`, discovery, or
missing-binary error. Keep an explicit key-label check in addition to the value
check.

Add mutation-kill controls in disposable worktrees or bundle fixtures:

- bypass the Dart compile gate and prove production fails;
- add a nested Mach-O diagnostic symbol and prove the gate fails;
- place the canary in a nested executable and prove the gate fails;
- remove an expected binary or force enumeration/tool failure and prove the
  gate fails closed.

Restore and prove the exact source tree clean afterward. Use a clean boundary
between public-canary controls and the real diagnostic artifact. The shipping
production command is built and inspected independently of the paired control.

## Wave C3 — B6 whole-tip privacy and executable hygiene

Create or extend an executable, allowlisted whole-tip scanner. It reports only
paths, line numbers, categories, and counts—never sensitive values. Scan:

- current and legacy iOS device-ID candidates;
- Android serials and contextual hardcoding near device commands/variables;
- CoreBluetooth UUIDs in logs/evidence;
- raw token formats in text and logical SQLite columns;
- user-specific macOS/Linux absolute paths;
- committed diagnostic-secret values in schemes/configuration;
- sensitive tracked filenames.

Functional BLE/service UUIDs, Git object IDs, dependency hashes, and synthetic
test vectors require narrow documented allowlists. Query every tracked SQLite
database logically and print counts only. Run `bash -n` on every tracked shell
script and repair `scripts/GO.sh` so its device placeholder cannot parse as
redirection; prefer a required environment variable.

In a disposable fixture/tree, plant one synthetic canary for every scanner
category plus an allowlist-bypass attempt. A non-author must prove each canary
is detected before cleanup and absent afterward. The test output contains only
category/path/count, not the planted values.

Update the value-free history proposal to cover all affected reachable
refs/history, including introductions before `f989231`, `f989231` itself, and
every descendant through the eventual rewritten refs. Cover PR/shared ancestry,
both remotes, tags, artifacts, collaborator coordination, SHA invalidation, and
mandatory post-rewrite re-verification. Do not express the range as
`f989231..TIP`, and do not execute or authorize the rewrite.

A Git commit cannot truthfully embed its own SHA. Remove any stale claim that an
ancestor is the “current tip”; do not manufacture a self-referential hash. The
final docs-branch attestation must instead bind the exact reviewed code SHA to
the proposal blob hash and state the symbolic affected-ref set the owner would
resolve immediately before an authorized rewrite.

Rerun the scanner after the final documentation/proposal commit. A clean prior
code commit does not prove the final tip clean.

## Per-lane build–attack–repair loop

For every lane, the coordinator must enforce this loop without returning to the
owner:

1. Freeze the lane predicates and verifier-owned acceptance tests.
2. Commit a failing reproduction/test or mutation separately.
3. Primary implementer fixes the lane in a separable commit.
4. Run focused tests and record command, exit status, named tests, counts, SHA,
   and generated-artifact hashes.
5. Give both non-authors the exact SHA, requirement ledger, diff, and fixtures,
   without the author's verdict.
6. Each verifier runs its strongest falsification and records each item as
   `OPEN`, `REFUTED_WITH_REPRODUCTION`, or `FIXED_AT_SHA`.
7. Assign every reproducible finding immediately. Fix and rerun the lane.
8. Repeat against the changed exact SHA until both non-authors return binary
   `PASS` and no frozen predicate is open.

Two failed repair attempts against the same predicate trigger a focused
three-model root-cause conference: agree one design, name one patch owner, and
continue. Do not restart the entire audit and do not ask the owner merely
because the work is difficult.

That conference may agree on a falsifiable predicate, constraints, and design,
not shared patch text. One model remains the patch author. The other two must
each create a fresh verifier-owned mutation that is red before and green after;
their approval is invalid if they co-authored the patch. Record the conference,
roles, predicate, and mutations in the disagreement ledger.

A post-freeze discovery may block only when it has a deterministic reproduction
and materially invalidates release isolation, behavior, privacy, or evidence.
Cosmetic, speculative, unrelated, and future-hardening observations go into a
follow-up ledger. Never lower a contract to manufacture PASS.

## Integration, `CODE_READY`, and `PREFLIGHT_READY`

The coordinator cherry-picks only lane commits approved by both non-authors.
After each pick, rerun affected lanes. Once B1–B6 are integrated, run one
whole-diff unknown-unknown sweep. Any material new blocker must include an
executable reproducer, be fixed in-round, and receive two non-author checks. A
material fix changes the reviewed diff, so rerun the sweep against the changed
SHA until one sweep returns no material blocker. This is not permission to
reopen already-closed predicates without a new deterministic reproduction.
Record every sweep SHA and outcome.

At the final implementation tip run at least:

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
# Run the committed puller, privacy, and mutation-test entry points added above.
git diff --check
```

Also syntax-check every tracked shell script. No controlling test may be skipped.
Run suites serially if simulator-clone contention makes a parallel run flaky;
record infra retries rather than hiding them.

When those local gates and all two-non-author lane approvals pass on the same
SHA, record the internal **`CODE_READY`** gate and continue—do not stop for an
owner checkpoint.

Push the new named branch non-forcefully and dispatch the iOS workflow against
that exact ref. Verify the Actions `head_sha`, job conclusions, test counts, and
skips. Download the uploaded production IPA, hash it, recursively enumerate its
Mach-Os, and independently repeat the production symbol/key/canary/name scans.
Hash Runner and App AOT as well. A green workflow log without artifact inspection
is insufficient.

The controlling native/diag suites must report discovered equals passed with
zero skips; the log must name `testHandleUsesInjectedRunSecret` (or its stronger
replacement) as executed and passed. Any controlling skip is `BLOCKED`, even
when the workflow conclusion is green.

Build the signed diagnostic artifact that will be installed in a separate clean
detached worktree at the exact `CODE_READY` SHA. That tree must never have run
the public-canary mutation controls. Supply the real fleet key only through the
approved untracked/environment build input; never print or commit it. Record the
artifact SHA-256, Mach-O inventory, signing identity, source SHA, and successful
diag positive controls in the `PREFLIGHT_READY` manifest, and prove the public
C2 canary is absent. A dirty, canary-bearing, differently sourced, or unhashed
diagnostic artifact may not be installed.

Then perform three fresh final reviews in separate detached worktrees. Each
model must state its strongest counterexample and return `CODE_READY` or
`BLOCKED` for every frozen predicate. The author of a lane still needs both
non-author signatures. All signatures name the same code SHA, CI run, and IPA
hash. Store attestations on the docs branch after signing so documentation does
not mutate the reviewed code SHA.

Only unanimous binary PASS across B1–B6 plus the exact CI/artifact/checklist
requirements authorizes **`PREFLIGHT_READY`** and the one-phone preflight. Do not
install at the earlier internal `CODE_READY` point.

## One-phone combined preflight

Prepare one consolidated operator checklist before asking for a phone so the
owner is not interrupted piecemeal. After `PREFLIGHT_READY`, install the exact
hashed diagnostic artifact on one phone and prove in one session:

1. key continuity from native restoration/start through Flutter attachment;
2. case reset retains the key, rotates the public epoch, resets sequence and
   controls, and leaves no old/current rotated file;
3. selected-peer UI lists handles only and returns structured arm/status/disarm;
4. wrong peer cannot consume the target; the right peer consumes once;
5. 100+ foreground/background/locked events remain monotonic and attributable;
6. forced rotation preserves sequence/integrity and required attributes;
7. injected writer failure increments the correct counter and survives until a
   durable acknowledgment;
8. extraction fails closed on a deliberate negative, then succeeds, sanitizes,
   validates, post-scans, and atomically publishes;
9. the install command uses the signed diagnostic artifact whose hash is
   recorded in the `PREFLIGHT_READY` manifest, and that manifest binds it to the
   `CODE_READY` code SHA.

If any item fails, keep the same panel session active, assign and fix it, then
re-derive the full gate chain against the changed SHA: `CODE_READY`, exact-SHA
CI with zero controlling skips, production-artifact inspection, a fresh
clean-worktree signed diagnostic build, three fresh final code signatures, and
a re-dry-validated consolidated operator checklist. Issue a **new**
`PREFLIGHT_READY` manifest binding the new artifact hash to the new code SHA.
Only that new manifest authorizes reinstall and another preflight; never reuse a
superseded manifest. Return to the owner only if a new physical interaction is
actually required.

A successful preflight yields `MATRIX_READY`.

## Frozen three-iPhone matrix

Run all cases against the exact diagnostic artifact that passed preflight and
the exact `MATRIX_READY` validator. Device roles are iPhone 14, iPhone 13, and
iPhone 15 Plus; commit no serial/UDID.

1. **Selected-peer pre-ACK reclamation:** arm the target, prove the intended
   pending dial reached the fault, prove failure or TTL reclamation on the same
   peer/link, then prove a later clean commit and no leaked contender. A normal
   three-peer convergence is only smoke.
2. **Grace reconnect with rotation:** independently prove drop, rotation before
   reconnect, inability to deliver `ALIAS_ROLL` on the dropped link, same-lease
   recommit within 120 seconds, and both token-cache and retry-floor bypass.
3. **Real CoreBluetooth restoration:** use genuine OS restoration/jetsam—not
   app-switcher force-quit or a developer-process kill—and prove
   `willRestoreState`, restored objects, both notify subscriptions, snapshot and
   lease continuity, resumed traffic, stale-generation rejection, and a current
   positive control.
4. **Narrow mapped-lease teardown:** prove trustworthy alias, structured lookup,
   all applicable roles closed, lease ended, and idempotent repeat for the local
   card. A server card with no evidence-backed alias must honestly return
   unavailable. Include an unswiped-peer positive control; do not call short
   no-redial silence durable rejection.

Every negative assertion needs a positive control showing the observer could
have seen the prohibited event. Android may validate shared Dart behavior but
cannot satisfy an iOS-native gate.

## Final evidence and `MERGE_READY`

The sanitized manifest must contain:

- exact code SHA and ancestry;
- every commit and lane disposition;
- exact model identities and independent attestations;
- commands, exits, test names/counts/skips;
- CI URL and verified `head_sha`;
- production and diagnostic artifact hashes plus Mach-O inventory;
- one-phone preflight assertions;
- per-case event-chain validator output and positive controls;
- sanitized JSONL only, with no raw source logs;
- disagreement/follow-up ledger;
- explicit separate decisions for PR integration while W5 is disabled and W5
  release enablement.

Run all validators and privacy scans on the frozen evidence/manifest commit.
Then commit only a value-free attestation on the docs branch naming that scanned
tree hash, commands, and exit statuses. Post-scan the attestation commit and put
that final exit result in the `MERGE_READY` message rather than committing a new
self-referential report. Then each model performs a fresh independent evidence
review. A changed implementation SHA or artifact invalidates prior code
signatures; changed evidence requires evidence signatures to be rerun.

The panel may return **`MERGE_READY`** only when all three independently sign the
same code SHA, IPA hash, and evidence manifest with every frozen predicate and
all four hardware cases proven. Otherwise it must keep working on reproducible,
in-scope failures or name the exact external blocker.

Even `MERGE_READY` is a recommendation, not permission to merge, deploy,
force-push, rewrite history, or enable W5. Those remain explicit owner actions.

## Allowed terminal responses

The Mac coordinator may contact the owner only with one of these:

1. `EXTERNAL_BLOCKER` — exact missing permission/credential/product decision,
   after all independent lanes that do not need it have continued;
2. `PHYSICAL_ACTION_REQUIRED` — an unexpected physical action arising after
   `PREFLIGHT_READY` that is not the standard request in item 3 or 4,
   consolidated into one step-by-step request; never emit this at the internal
   `CODE_READY` gate;
3. `PREFLIGHT_READY` — exact SHA/CI/artifact packet plus one consolidated phone
   request for the combined preflight;
4. `MATRIX_READY` — preflight evidence plus one consolidated three-phone matrix
   session;
5. `MERGE_READY` — final exact-SHA/artifact/evidence signatures and the separate
   PR/W5 recommendations.

“Still working,” “here are more findings,” “PARTIAL,” and “awaiting another
panel” are progress states, not handoff states.
