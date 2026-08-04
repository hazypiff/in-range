# Phase 1–4 Round-3 exact-SHA panel review of `d83b826` — 2026-08-04

## Decision

**HOLD.** Commit `d83b826154fb72f41d614e6e9a4c5a01e0b32004` is not
ready for the one-phone log-integrity preflight or the three-iPhone Phase-5
matrix. Do not install this build, advance PR #11, stack this branch into PR
#11, merge, deploy, mirror the implementation branch, rewrite history, or begin
hardware evidence collection.

Round 3 contains real improvements: the controller test now reaches a genuinely
committed lease, clean restoration rebind is observable, and event sequence
allocation plus append are one atomic operation. The exact-SHA CI run is also
fully green. Those facts do not close the controlling evidence contracts.
Cases 1–3 remain incompletely attributable and not operable from the installed
app; the secret lifecycle still has a boot-before-provision race; file failures
remain silent; the sanitizer fails open; and the whole Git tip is not clean.

The exact uploaded production IPA also exposed a new false-green in B5: the
isolation checker scans only the native Runner executable. The Dart AOT
executable in `App.framework` still contains one production reference to the
run-secret configuration key. This is the **key name with an empty production
value**, not a leaked secret value and not a live compromise, but it violates
the stated zero-reference contract and proves the bundle check is incomplete.

## Pinned state and independently reproduced checks

- Repository reviewed: `inrangeai/in-range`
- Implementation branch: `fix/w5-hardware-evidence-2026-08-03`
- Exact fetched origin tip:
  `d83b826154fb72f41d614e6e9a4c5a01e0b32004`
- Prior reviewed SHA:
  `bb9d5cde8096609590aa05108f4f0ffcf459b582`
- Round-3 commits: `c438f1a` and `d83b826`; 16 changed files, 328
  insertions and 48 deletions.
- Review occurred in three clean detached worktrees at the exact object.
- Linux independently reproduced `flutter analyze` clean and `flutter test`
  273/273.
- A multi-ABI Android debug APK built successfully after clearing temporary
  build artifacts left by an initial tmpfs-full failure and stopping the stale
  Gradle daemon it left behind. Final artifact: 159,343,788 bytes, SHA-256
  `f55ba03059baf3e452d125e753db080a91cd30899e36452b645c46c4be247801`.
- At the final ADB inventory, one authorized and one unauthorized Android were
  visible; the requested three-device set was not present. No APK was installed:
  the controlling changes are iOS-native/diagnostic, and the off-iOS teardown
  path is covered in the 273-test suite. No device state changed.
- `git diff --check` and shell syntax checks over the changed scripts passed.
- Exact-SHA GitHub Actions run
  [30956862147](https://github.com/inrangeai/in-range/actions/runs/30956862147)
  completed successfully: Runner 55/55, diag 65/65, `isolation-ios`, and the
  gated unsigned iOS artifact all passed.
- The isolation job reported native Runner production `diag-syms=0` /
  `run-secret-env=0`; diag positive controls were 88/1.
- Read-only inspection of that run's uploaded IPA found:
  - native `Payload/Runner.app/Runner`: zero run-secret-key references;
  - Dart AOT `Payload/Runner.app/Frameworks/App.framework/App`: one
    run-secret-key reference.
  The checker names only `Runner.app/Runner`, so its production 0 result does
  not cover the final app bundle.
- The uploaded IPA was 8,848,257 bytes, SHA-256
  `e8655014a3b07c07afd8cd0cdacfe8d126a96cf2c3d1bb51adf6671b430c794a`.
- PR #11 was independently rechecked: open, draft, head `c816f09`, base
  `fix/w5-encounter-lease`. It contains none of this round and remains frozen.

No physical-iPhone result is inferred from Linux, Android, simulator, CI, or
artifact inspection.

## B1 — identifier split passes; end-to-end teardown evidence remains partial

The server-ID/radio-alias separation remains correct. Server cards do not
fabricate aliases, the real Flutter channel wrapper forwards the radio alias on
iOS and no-ops off-iOS, and the native controller seed now performs a matching
proposal plus ACK before asserting committed state
(`W5LinkController.swift:511-543`, `W5TeardownTests.swift:135-153`). This closes
the prior false “committed” test claim.

Three controlling items remain:

1. The committed hit test calls `W5LinkController.dropPeer` directly. The only
   `BackgroundBeacon.dropPeerByToken` test is still a server-ID miss
   (`W5TeardownTests.swift:156-168`). No test proves a committed hit plus raw
   session cleanup through the actual native boundary Dart invokes.
2. Tests exercise `reportPassTeardown` and the channel/service seams separately,
   but none renders `SwipeFeed` or triggers `_doPass`. The wiring at
   `swipe_feed.dart:112-155` therefore remains untested.
3. Outcomes are not operationally recorded in the sanitized evidence layer.
   Misses use `debugPrint`; real tears and server-card unavailable outcomes do
   not call the miss callback; `lastTeardownOutcome` has no consumer
   (`pass_teardown.dart:99-116`, `swipe_feed.dart:33-38,137-141`).

The comments also still say teardown uses only a “still-fresh” alias while the
resolver deliberately attempts stale aliases and lets native decide. That may
be an accepted best-effort policy, but the controlling contract and comments
must state it consistently.

**B1 verdict: identifier-domain safety PASS; aggregate PARTIAL.**

## B2 — two useful additions do not make Cases 1–3 provable

Round 3 correctly emits `restoreRebind(result: recovered)` on clean recovery,
and the fault layer now records arm, manual disarm, and fire events. The broader
Round-2 list remains open:

- `coldLaunch` still emits before `ensureManagers()` creates the restoration
  managers (`BackgroundBeacon.swift:265-273`), so its claim about preceding
  restoration events is structurally unreliable.
- The locked/no-token connect path still calls `central.connect` without a
  `dialStart` (`BackgroundBeacon.swift:1162-1188`).
- An established W5 physical drop enters grace without an attributed physical
  drop event. `.linkDown` remains the later ended-cleanup event, while `.parted`
  describes the legacy CA5E session (`W5LinkController.swift:342-365,914-916`;
  `BackgroundBeacon.swift:1217-1237`).
- HELLO_ACK/reject send paths and proposal/ACK send events remain incomplete or
  lack the role/peer/lease fields needed to join a multi-peer story
  (`W5LinkController.swift:431-471,559-572,698-738`).
- `armW5Fault`, `disarmW5Fault`, and `resetW5Diag` have channel/service methods
  and mock tests but no installed-application caller or status surface. Source
  search finds definitions only in the two beacon bridge files.
- A nil peer still arms the wildcard and is explicitly tested
  (`W5Diag.swift:127-138`, `w5_diag_control_test.dart:37-41`).
- Every outbound diagnostic dial still receives the global four-second HELLO
  delay, armed or not (`BackgroundBeacon.swift:135-142`,
  `W5LinkController.swift:262-276`). It is neither one-shot nor fault-conditional.
- Sensitive diagnostic channel cases remain outside independent
  `#if INRANGE_DIAG` guards (`BackgroundBeacon.swift:383-404`). An authenticated
  owner decision may allow their strings in production, but branch-authored
  prose cannot silently retire the source requirement.

**B2 verdict: FAIL.**

## B3 — the persistence choice does not repair confidentiality or ordering

The branch now states that the owner chose per-install persistence. This panel
cannot authenticate that out-of-band decision from repository evidence: the
claim appears only in unsigned, branch-authored commit `c438f1a`, its checkpoint,
and comments added by the same commit. The agent co-author trailer is not owner
authorization. This is absence of evidence, not proof that the decision never
occurred. An owner-authored PR/issue comment, signed record, or equivalent
durable source would settle provenance immediately.

Implementation defects remain regardless of that choice:

- `W5Diag.swift:15-17` still says the secret lives only in memory and is never
  persisted or printed. The same file persists it in the diag UserDefaults
  suite (`:89-123,191-228`).
- The shared diag Xcode scheme contains two enabled committed secret values.
- `build_diag_artifact.sh:25-46` bakes a fleet secret into Dart and prints it to
  build output for the evidence manifest.
- Native boot and its first diagnostic emits occur before Flutter attaches
  (`AppDelegate.swift:9-35`, `BackgroundBeacon.swift:257-270`). Dart provisions
  only after awaiting native `start`, and does so unawaited
  (`beacon_service.dart:1011-1023`). A first launch or post-reset restoration can
  therefore resolve the lazy static `runSecret` to a generated per-install key
  before the fleet key arrives; later provisioning updates storage but cannot
  change that process's static key.
- `resetDiagSession` clears storage but retains the in-process static key, so
  post-reset writes in the same process use the old key. Relaunching the same
  baked artifact can then reprovision the same fleet value, contradicting the
  claim that every reset necessarily makes matrix cases uncorrelatable.
- Existing tests prove individual persistence/injection helpers, not first
  launch or reset → OS restoration → provision ordering.

**B3 verdict: FAIL.**

## B4 — atomic ordering passes; integrity and sanitizer contracts still block

The sequence counter and event append now execute under the same event-writer
lock (`W5Diag.swift:69-81`, `W5EvidenceWriter.swift:59-64`). The implementation
fix is sound. The current sanitizable text logs happen to present raw 32-hex
values only as RSSI peer tokens; for that path the puller's HMAC construction
matches the live `peer` domain. The separately pulled raw database is not
sanitized or commit-ready.

The aggregate evidence contract remains incomplete:

- Missing/short secret falls back to a stable unkeyed tag and still writes
  “commit-safe” output (`hw_matrix_pull.sh:47-64`). This is fail-open and repeats
  the exact non-run-scoped behavior rejected in Round 2.
- The sanitizer hashes every regex match as domain `peer`, while the live layer
  domain-separates `peer`, `lease`, `link`, and `peripheral`
  (`W5Diag.swift:62-65,246-260`). The generic checkpoint claim that every
  committed identifier matches its live handle is false for UUID, lease, and
  link classes. It is correct for today's peer-token path only by artifact
  shape, not by a safe generic implementation.
- Rotation, protection, backup exclusion, close, RSSI trim, and RSSI delete
  still contain unaccounted `try?` paths
  (`W5EvidenceWriter.swift:71-143`, `W5LinkController.swift:996-1048`). A failed
  rotation can be followed by append; a failed trim replacement is silent; and
  trim does not reapply/verify protection and backup attributes.
- `testEventSeqMatchesFileOrder` remains a single-threaded six-emit loop. There
  is no true concurrent writer test, injected rotate/protection/trim failure
  test, or locked-device assertion (`W5DiagTests.swift:104-127,182-202`).
- The puller retrieves `in_range_local.db` into raw scratch but never produces a
  sanitized database artifact. Its scratch path is machine/user-specific.

All reviewers agree these failures independently block log-integrity preflight.
For aggregation, this report uses PARTIAL because atomic seq/append, protection
class, named-file pulling, and today's peer-token HMAC path pass; the sanitizer
and failure-accounting subcontracts are explicitly FAIL.

**B4 verdict: PARTIAL; preflight-blocking.**

## B5 — exact CI is green, but its final-bundle isolation result is false-green

Operational mechanics are real and accepted. Run `30956862147` passed both
native schemes, the isolation job, and the gated build. The checker correctly
finds zero diagnostic Swift symbols and zero native run-secret reads in the
production Runner executable, with positive controls firing in diag.

The checker defines `BIN` as only
`build/ios/iphoneos/Runner.app/Runner`
(`check_final_binary_isolation.sh:28`). Flutter's Dart AOT executable is a
separate Mach-O at `Runner.app/Frameworks/App.framework/App`; the exact uploaded
production IPA contains one run-secret-key reference there, originating from
the common `String.fromEnvironment` switch in `app_config.dart:40-41`.

This does not disclose a secret value—the production constant resolves empty—
but it fails even the branch's claimed “symbols + run-secret-env” zero-reference
contract. The green isolation job measured an incomplete target. The fix must
remove/gate the Dart-side key from production AOT and scan every executable in
the app bundle, with paired positive controls in the diag bundle.

The claimed owner relaxation also remains unauthenticated as described under
B3. Even if authenticated, the exact IPA fails its stated discriminator.

**B5 verdict: operational CI PASS; aggregate FAIL.**

## B6 — the branch evidence subtree is clean; the whole tip is not

The station-check script is now environment-driven, the proximity doc uses a
placeholder, and `hardware_evidence/` contains no checked raw device-ID or
32-hex token formats. Those corrections are genuine.

The whole-tip inventory still fails:

- `docs/sessions/2026-07-12-full-bug-run.md` contains one full iOS device
  identifier and two Android serials.
- `PRIVACY_REDACTION_PROPOSAL.md:46-47` repeats five forbidden identifier
  fragments. Its mechanism still ends at stale SHA `357053c` and omits later
  descendants.
- Read-only logical SQLite queries found two distinct 32-hex
  `sightings.correlation_id` values in each tracked field-test database—four
  unique values total. Raw-file scans see seven stored occurrences because
  indexes duplicate values. They remain unclassified as synthetic or real.
- The shared diag scheme retains the committed diagnostic secret values noted
  under B3.
- `hw_matrix_pull.sh:15` contains a user-specific absolute raw-evidence path;
  other older docs/scripts also retain absolute user paths.

History rewrite remains owner-only and is neither required nor authorized in
this turn. The proposal must be value-free and cover the eventual clean tip
before the owner considers it.

**B6 verdict: `hardware_evidence/` PASS for checked formats; whole tip FAIL.**

## Three-reviewer reconciliation

Claude, Kimi, and Codex independently reviewed clean worktrees at the exact SHA
before seeing the other reviews. Both headless reviewers independently
reproduced analyze/test success and reached HOLD. The exact-SHA CI and uploaded
IPA were then supplied for reconciliation.

| Disagreement | Resolution |
|---|---|
| B4 HMAC “exactness” | Exact for today's raw peer-token path, not for the generic four-domain claim. Missing-secret fallback still fails open. |
| B4 aggregate label | All agree it blocks preflight. Report records PARTIAL because several subcontracts pass; sanitizer and failure accounting remain FAIL. |
| B5 CI wording | Run is genuinely green. Its 0/0 isolation conclusion is false-green for the final bundle because App.framework was not scanned. Both statements are recorded. |
| B5 final verdict | Unanimously changed to aggregate FAIL after exact-IPA inspection. |
| B6 database count | Four unique logical values; seven stored occurrences. Earlier byte/string estimates are superseded. |
| Severity | Preflight/release-enablement blockers, not live production compromises; W5 remains off and unreleased. |
| Owner decisions | Repository provenance is absent; this does not prove the decisions never occurred. Implementation failures stand either way. |

Raw panel transcripts are intentionally not committed because reviewers
encountered sensitive values. Every report claim above was rechecked without
reproducing those values.

## Requirement ledger

| Area | Verdict at `d83b826` |
|---|---|
| B1 identifier-domain safety | PASS |
| B1 committed/native/UI/observable chain | PARTIAL |
| B2 Case 1–3 transitions and attribution | FAIL |
| B2 installed selected-peer control | FAIL |
| B2 wildcard/delay/compile isolation | FAIL or owner-decision pending where explicitly relaxed |
| B3 owner-approved lifecycle provenance | FAIL pending durable confirmation |
| B3 confidentiality, ordering, reset, tests | FAIL |
| B4 atomic seq+append | PASS |
| B4 failure accounting and concurrency/failure tests | FAIL |
| B4 current peer-token HMAC path | PASS with secret; missing-secret behavior FAIL |
| B4 generic multi-domain sanitizer claim | FAIL |
| B4 aggregate | PARTIAL; preflight-blocking |
| B5 exact-SHA workflow mechanics | PASS |
| B5 final-bundle negative contract | FAIL |
| B6 branch hardware-evidence subtree | PASS for checked formats |
| B6 whole tip and rewrite inventory | FAIL |
| One-phone log-integrity preflight | **NOT READY** |
| Three-iPhone Phase-5 matrix | **NOT AUTHORIZED** |
| W5 release enablement | **BLOCKED** |

## Decision separation

- **One-phone preflight:** not ready. B2 cannot construct the required event
  chains, B3 cannot guarantee cross-restoration/fleet handles, and B4 cannot
  guarantee complete/accounted/fail-closed evidence.
- **Full matrix:** not authorized. It remains downstream of a successful
  preflight and another exact-SHA READY panel.
- **PR #11 frozen at `c816f09`:** out of scope. This report neither authorizes
  nor invalidates its prior exact-SHA result.
- **Stacking `d83b826` into PR #11:** not authorized.
- **W5 release enablement:** blocked. No live production compromise is inferred
  from the disabled runtime.

## Required next Mac checkpoint

Complete these without installing on phones:

1. **B5 true bundle gate:** remove/gate the Dart run-secret-key read from
   production AOT; scan Runner and every framework executable in the final app;
   retain paired diag positive controls.
2. **B3 lifecycle:** obtain a durable owner record for the persistence choice;
   correct the contradictory header; remove committed, baked, and printed
   values; fix boot-before-provision/static-key and post-reset behavior; add
   first-launch and reset → restoration → provision tests.
3. **B2 proof surface:** fix restoration classification, no-token `dialStart`,
   established physical-drop attribution, and protocol send/role events; add an
   installed selected-peer arm/status/disarm/reset UI with no wildcard; make
   the delay one-shot and fault-conditional.
4. **B4 evidence integrity:** account every rotate/protection/backup/trim/delete
   failure; reapply and verify attributes after replacement; add truly
   concurrent and injected-failure tests; make the puller abort without a valid
   secret and map domains by field/artifact.
5. **B1 end-to-end proof:** add a committed real hit through
   `BackgroundBeacon.dropPeerByToken`, raw-session cleanup assertions, a
   `SwipeFeed` pass widget/integration test, and sanitized evidence for all four
   outcomes.
6. **B6 tip cleanup:** scrub the session document, proposal fragments, scheme
   fixture, tracked DB values, and user-specific paths; update the value-free
   rewrite proposal through the eventual new tip. Do not execute the rewrite.
7. Run the full local suite, push one exact SHA plus manifest, stop, and request
   the next blinded three-reviewer panel. Only that panel may authorize the
   one-phone preflight.

## Reply for the Mac agent

Panel consensus on `d83b826` is **HOLD**. Your committed-lease seed, clean
`restoreRebind`, and atomic seq+append fixes are accepted, and exact-SHA run
`30956862147` is genuinely green (Runner 55/55, diag 65/65, gated IPA). However,
the same uploaded production IPA proves B5 false-green: the checker scans only
the native Runner executable, while Dart `App.framework/App` retains one
run-secret-key reference. It is a key name with an empty value—not a secret
leak—but it violates the zero-reference contract. Final verdicts: B1 PARTIAL,
B2 FAIL, B3 FAIL, B4 PARTIAL/preflight-blocking, B5 FAIL, B6 FAIL. One-phone
preflight is NOT READY; matrix NOT AUTHORIZED; PR #11 stays frozen; no stacking,
device action, merge, mirror, deploy, or history rewrite. Complete the seven-item
checkpoint above, push one new exact SHA, and stop for another blinded panel.
