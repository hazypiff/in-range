# Phase 1–4 Round-2 exact-SHA panel review of `bb9d5cd` — 2026-08-04

## Decision

**HOLD.** Commit `bb9d5cde8096609590aa05108f4f0ffcf459b582` is not
ready for the one-phone log-integrity preflight or the three-iPhone Phase-5
matrix. Do not install this build, advance PR #11, stack this branch into PR
#11, merge, deploy, mirror the implementation branch, rewrite history, or begin
hardware evidence collection.

Round 2 contains real progress. The hardware-evidence directory is clean of the
identifier formats checked, the production/diag isolation build now succeeds
unsigned, a real controller object exercises a live teardown hit, the platform
channel wrapper is covered, the file protection class now supports writes after
first unlock, RSSI operations use the writer lock, and the puller includes the
primary event files and rotations. Those improvements do not close the
controlling B1–B6 contracts. Several mandatory Round-1 corrections were left
unchanged, while B3 was replaced with a branch-authored contract that has no
owner approval.

## Pinned state and checks

- Repository: `inrangeai/in-range`
- Implementation branch content: `fix/w5-hardware-evidence-2026-08-03`
- Exact remote tip reviewed:
  `bb9d5cde8096609590aa05108f4f0ffcf459b582`
- Rejected Round-1 base:
  `9775960c78fb9d5ac9d4d0956551502b54205049`
- The four new commits change 23 files, with 450 insertions and 82 deletions.
- PR #11 was independently verified still open and draft at
  `c816f09df433bb9d3c80ad222ae2d88a63b8ed10`. It contains none of this round.
- Review occurred in clean detached worktrees at the exact remote object.
- Linux independently reproduced `flutter analyze` clean and `flutter test`
  267/267.
- Exact-SHA normal CI run `30940225943` passed.
- A multi-ABI Android debug APK built successfully from the exact SHA
  (159,343,144 bytes; SHA-256
  `3abf95476583b1c7c48926a59e247fe43e6ce867ecd0232f0355924e57a848e4`).
  Two authorized Android phones and one unauthorized phone were visible. No APK
  was installed: the changed behavior is iOS-native, no Android device test
  exercises it, and installation would alter device state without testing a
  blocker.
- `git diff --check` and shell syntax checks over the changed scripts passed.
- This reviewer successfully dispatched exact-SHA iOS run `30941040241`, which
  the Mac account could not dispatch. The full workflow passed: Runner 55/55,
  diag 64/64, `isolation-ios` production 0 diagnostic symbols/0 run-secret-env
  reads with the diag positive controls firing, and the gated unsigned iOS
  artifact built and uploaded. The checker also reported nine production
  machinery strings as allowed/informational; that narrower contract is
  addressed under B5.

No physical-iPhone result is inferred from Linux, Android, simulator, or CI.

## B1 — improved real boundaries, but the claimed end-to-end contract is partial

The identifier split remains sound: server cards do not fabricate a radio
alias, and the new Dart tests drive `resolvePassTeardown` through the real
`BackgroundBeaconChannel.dropPeer` wrapper. The new Swift test also calls the
real `W5LinkController.dropPeer`, not the old helper reconstruction.

Three claims remain overstated:

1. The test seed calls `ownership.onControl` and then asserts only one active
   lease (`W5LinkController.swift:504-527`, `W5TeardownTests.swift:132-150`).
   `onControl` cannot commit by itself: `maybeCommit` requires a matching peer
   proposal and ACK (`W5Ownership.swift:415-510,723-738`). The test proves a
   real active-hit teardown, but not the checkpoint's “real committed lease.”
2. The Dart tests invoke the helper directly with a mocked method-channel
   messenger (`pass_teardown_test.dart:106-152`). They do not render
   `SwipeFeed`, trigger `_doPass`, or cross into native Swift. Conversely, the
   Swift real-hit test bypasses `BackgroundBeacon.dropPeerByToken`; its channel
   entry test remains miss-only. No test spans UI action → resolver → channel →
   real native hit and raw-session cleanup.
3. Server-card `unavailable` remains private/test-only state and is excluded
   from the sole debug output (`swipe_feed.dart:25-38,112-140`). No sanitized
   operational event records fresh/stale/server/native-unavailable outcomes.

The stale-alias attempt is deliberate best-effort behavior in the branch's own
fix note, with native authoritative on hit/miss. It is not itself a safety bug,
but its comments and the still-fresh work-order wording remain inconsistent.

Required correction: test a genuinely committed lease through the actual
`dropPeerByToken` boundary, add a widget/integration test that triggers
`_doPass`, make every outcome observable through the sanitized diagnostic
layer, and settle the stale semantics in the controlling contract.

## B2 — Round-2 additions do not make Cases 1–3 provable

The `.parted` event and disarm operation are useful but do not close the
enumerated Round-1 gaps:

- `coldLaunch` still emits before manager creation
  (`BackgroundBeacon.swift:265-273`), so its stated restoration discriminator is
  structurally unreliable.
- Successful restoration rebind still emits nothing; `.restoreRebind` exists
  only on the forced-rebuild branch (`BackgroundBeacon.swift:844-888`).
- The locked/no-token connection still calls `central.connect` without a
  `dialStart` (`BackgroundBeacon.swift:1158-1184`).
- The new `.parted` event describes the legacy CA5E session removed from
  `BackgroundBeacon.w5`. It does not repair the established W5 ownership
  `linkDown` path, which still enters grace silently; `.linkDown` remains an
  ended-cleanup event rather than a physical-drop event
  (`BackgroundBeacon.swift:1213-1233`, `W5LinkController.swift:342-365,898`).
- The previously listed role-correct HELLO_ACK/rejection/tiebreak events remain
  incomplete.
- `armW5Fault`, `disarmW5Fault`, and `resetW5Diag` have channel/service methods
  and tests, but no committed application caller. An installed release-mode
  diagnostic artifact still has no operator control surface. Source search finds
  only definitions and tests.
- The API still accepts and tests a nil-peer wildcard; adding disarm does not
  make arming require a selected peer (`W5Diag.swift:112-145`,
  `w5_diag_control_test.dart:30-50`).
- Every diagnostic outbound dial still receives the global four-second HELLO
  delay, armed or not (`BackgroundBeacon.swift:135-141`,
  `W5LinkController.swift:262-276`).
- Sensitive channel cases and emit sites are still not independently
  `#if INRANGE_DIAG` guarded (`BackgroundBeacon.swift:383-404`).

Required correction: implement every previously enumerated transition at its
real state change, expose an installed-app selected-peer arm/status/disarm/reset
surface with no wildcard default, make delay one-shot and fault-conditional,
and compile-gate sensitive cases/call sites independently.

## B3 — the self-declared persisted-secret contract is not owner authorization

Round 1 required an owner decision before replacing “random ephemeral, never
persisted or printed” with another lifecycle. No owner decision is present.
`PANEL_FIXES_ROUND2_2026-08-04.md` documents what the branch author chose; it
cannot authorize its own exception.

The original violations remain:

- the shared Xcode scheme still contains enabled committed run-secret values;
- `build_diag_artifact.sh:25-46` still bakes the secret into Dart and prints it;
- `W5Diag` still persists provisioned/generated secrets in plaintext
  UserDefaults (`W5Diag.swift:74-109,167-206`); and
- the file header still says the secret is never persisted or printed
  (`W5Diag.swift:15-17`).

`resetDiagSession` removes defaults and counters, but the in-process secret is a
static `let`; reset explicitly takes effect only after another launch. It does
not prevent new events from being written with the old key between reset and
termination. The reset/fault methods also have no application caller.

Initialization remains unproven. Native boot occurs before Flutter attaches
(`AppDelegate.swift:9-35`), while Dart provisions only after awaiting native
start and does so unawaited (`beacon_service.dart:1011-1023`). After reset, a
restoration callback can materialize the fallback secret before Dart
re-provisions the fleet key, pinning the wrong static key for that process. The
tests use an Xcode launch environment, skip when it is absent, and separately
prove persistence; they do not exercise the release-diag artifact's reset → OS
restoration → provision ordering.

Required correction: present the lifecycle choice to the owner. Until approved,
remove committed, printed, and baked values. Then implement and test the chosen
secure provisioning/storage/expiry/destruction design across real restoration,
including first-use ordering and reset behavior.

## B4 — protection, locking, and extraction improved; integrity remains partial

Changing to `completeUntilFirstUserAuthentication` is appropriate for writes
after the first unlock, `withLock` serializes RSSI file operations against
append, and the puller now retrieves the primary JSONL files plus rotations.
The committed hardware logs also pass the checked raw-UUID and bare-token scans.

Remaining defects:

- event sequence allocation still uses `seqLock`, then appends under a different
  writer lock (`W5Diag.swift:242-255`). Concurrent emitters can write sequence
  numbers out of file order. The new “order” test is a single-threaded loop, so
  it cannot detect this (`W5DiagTests.swift:217-227`).
- RSSI trim, offset update, and deletion now run under the lock, but trim/write,
  delete, protection, backup-exclusion, and rotation errors still use `try?` and
  never increment the family counter (`W5LinkController.swift:979-1031`,
  `W5EvidenceWriter.swift:113-133`). Trim also does not reapply the declared
  protection/backup attributes after replacement.
- `rotateDotOne` can fail and append can proceed without reporting loss. The
  checkpoint's “every integrity failure observable” claim is still false.
- Simulator assertions remain conditional when protection metadata is absent;
  there is no concurrent writer test, locked-device assertion, or injected
  failure test.
- The puller maps identifiers with an unkeyed stable six-hex SHA-256 tag, not a
  run-scoped HMAC. This preserves correlation beyond a single diagnostic run and
  does not meet the prior sanitization contract.

Required correction: allocate sequence and append atomically, make every file
operation return and account failure, reapply/verify attributes after every
replacement, add concurrent and injected-failure tests, and use a run-scoped
keyed sanitizer.

## B5 — the exact gate now runs, but the required binary contract is weaker

The `--no-codesign` change repairs the operational production-build failure:
exact-SHA run `30941040241` is fully green, including both native schemes,
`isolation-ios`, and the gated unsigned artifact. That is meaningful closure of
the red-CI portion of B5.

The checker still declares diagnostic filenames and the
`armW5Fault`/`setDiagRunSecret` channel machinery allowed in production and
reports them only informationally (`check_final_binary_isolation.sh:7-18,26-31`).
It checks two type-name patterns and one environment key, not the required event
names, every evidence filename/control hook/configuration key, or surviving W5
link-layer code. No owner decision relaxes the strict Round-1 negative contract.

The committed checkpoint also says a branch push triggers `ios-build.yml`, but
the workflow triggers only on `main`, pull requests, or manual dispatch
(`ios-build.yml:3-19`). This exact run exists because the Linux reviewer
manually dispatched it.

Required correction: resolve the foreign-wipe-versus-zero-string design with the
owner, then enforce every agreed discriminator with paired positive controls.
Keep the now-working unsigned exact-SHA CI path.

## B6 — branch-created logs are cleaner, but the current tip is not clean

Round 2 successfully removed the 23 peripheral UUID occurrences from the six
branch-created wake logs, renamed the slot-C evidence files, and left no checked
raw UUID or bare 32-hex token in `hardware_evidence/`.

The whole-tip requirement still fails:

- `PRIVACY_REDACTION_PROPOSAL.md:35-36` still restates three forbidden
  hardware-identifier fragments.
- Two older tracked files still contain three full device identifiers
  (`scripts/ios_station_check.sh:17-18`, `docs/PROXIMITY_TIERS.md:209`). Do not
  copy their values into another document or prompt.
- Two older tracked SQLite field-test files contain seven bare 32-hex values.
  They predate this branch and contain no UUID-form values, but a “clean tip”
  inventory must classify them as synthetic fixtures or sanitize/remove them;
  this review does not assume that opaque values are safe.
- The proposal's rewrite range and “current tip” stop at `357053c`, excluding
  later contaminated descendants and the current correction round.
- The extractor's stable unkeyed tag is not run-scoped, as noted under B4.

Required correction: perform a value-free whole-tip inventory, sanitize all
tracked occurrences, remove the proposal fragments, use run-scoped keyed tags,
and update the proposed rewrite through the eventual clean descendant. History
rewrite and coordinated force-push remain owner-only decisions and are not
authorized by this review.

## Three-reviewer panel reconciliation

Claude, Kimi, and Codex independently inspected clean worktrees at the exact SHA
before reconciliation. All three reproduced analyze/test success and all three
reached HOLD before seeing the others' prose. Exact-SHA workflow `30941040241`
then completed fully green, so the panel explicitly separated operational CI
closure from the remaining source contracts.

The disagreement ledger resolved unanimously:

- **D1 / B1:** Claude corrected its first-pass “committed lease” description.
  `testSeedOutboundLink` calls only `onControl`; it supplies neither the peer
  proposal nor ACK required by `maybeCommit`. The test proves a real active,
  established hit—not a committed-keeper hit. B1 remains PARTIAL.
- **D2 / B3:** reset does not create the claimed independent session. The
  process retains its static key, while the scheme/artifact supplies the same
  shared value again after relaunch. More fundamentally, the committed,
  baked, printed, and persisted design still lacks owner authorization. B3
  remains FAIL.
- **D3 / B4:** the puller is complete for the named files, but its stable
  unkeyed truncated SHA is not the required run-scoped HMAC. Sequence and append
  also retain separate locks, and the new test is sequential. B4 remains
  PARTIAL and independently blocks preflight.
- **D4 / B5:** the full exact-SHA workflow is green: Runner 55/55, diag 64/64,
  isolation controls, and unsigned artifact. Operational B5 is PASS. The
  checker still enforces a self-selected weaker negative contract without an
  owner ruling, so aggregate B5 remains PARTIAL.
- **D5 / B6:** the branch-created evidence is clean for the checked formats,
  but the whole tip still has definite identifier violations, seven unclassified
  opaque values in tracked field-test databases, and a stale history proposal.
  B6 remains FAIL.
- **D6 / PR scope:** this review neither authorizes nor invalidates frozen PR
  #11 because it is a different exact SHA. Its prior verdict stands. Stacking
  `bb9d5cd` into it is not authorized.

Final consensus: B1 PARTIAL, B2 FAIL, B3 FAIL, B4 PARTIAL, B5 PARTIAL, B6 FAIL;
one-phone preflight NOT READY; full matrix NOT AUTHORIZED; stacking refused;
W5 enablement BLOCKED. Raw panel transcripts are intentionally not committed
because the tools encountered sensitive source values; all report claims were
rechecked directly without reproducing those values.

## Requirement ledger

| Area | Verdict at `bb9d5cd` |
|---|---|
| B1 identifier-domain safety | PASS |
| B1 committed/live real-boundary and operational evidence | PARTIAL |
| B2 Case 1–3 event completeness | FAIL |
| B2 installed-app selected-peer fault control | FAIL |
| B2 independent compile gating | FAIL |
| B3 owner-approved secret lifecycle | FAIL |
| B3 confidentiality, initialization, and reset semantics | FAIL |
| B4 locked-state protection class | PARTIAL; device assertion still required |
| B4 serialization, ordering, and failure accounting | PARTIAL |
| B4 extraction completeness | PASS for named files; sanitizer contract PARTIAL |
| B5 exact-SHA operational workflow | PASS |
| B5 strict final-binary negative contract | FAIL |
| B6 branch-created hardware-evidence tip content | PASS for checked formats |
| B6 whole current tip and rewrite inventory | FAIL |
| One-phone log-integrity preflight | **NOT READY** |
| Three-iPhone Phase-5 matrix | **NOT AUTHORIZED** |
| W5 release enablement | **BLOCKED** |

## Decision separation

- **One-phone preflight:** not ready. The run cannot establish the required
  Case 1–3 chains, operator controls, cross-restoration handle continuity, or
  ordered/accounted evidence from this source.
- **Full matrix:** not authorized. It remains downstream of a successful
  preflight and a new exact-SHA panel READY verdict.
- **PR #11 as frozen:** out of scope. This review neither authorizes nor
  invalidates it; its prior exact-SHA verdict stands and it remains frozen.
- **Stacking `bb9d5cd` into PR #11:** not authorized. Shared Dart, diagnostic,
  CI, and privacy defects remain even while W5 runtime is disabled.
- **W5 enablement:** blocked. No live production compromise is inferred from the
  disabled W5 runtime, but these are release-enablement blockers.

## Required next Mac checkpoint

1. Sanitize B6 across the entire current tip and update—but do not execute—the
   value-free history proposal through the eventual new tip.
2. Obtain an explicit owner decision for B3; do not treat another checkpoint
   document as authorization. Remove all committed/printed/baked keys in either
   case and close the first-use/reset race with executable tests.
3. Finish every B2 transition and provide an installed-app selected-peer
   control with conditional one-shot delay and independent compile gates.
4. Make B4 sequence+append atomic and account/verify every trim, replace,
   rotate, attribute, and delete operation; add concurrent/failure tests.
5. Finish B1 with a committed lease through `dropPeerByToken`, a real `_doPass`
   widget/integration test, and sanitized result evidence.
6. Enforce the owner-approved strict B5 discriminator list while preserving the
   now-green unsigned exact-SHA CI path.
7. Push one exact new SHA plus manifest and stop for another three-reviewer
   blinded panel. Only a later READY verdict may authorize one-phone preflight.

No merge, deploy, PR advance, implementation mirror, history rewrite,
force-push, or physical-device action is authorized by this report.
