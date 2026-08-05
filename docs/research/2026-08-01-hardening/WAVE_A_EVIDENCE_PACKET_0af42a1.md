# Wave A evidence packet — A1–A5 closure (2026-08-05)

Convergence branch `fix/w5-convergence-2026-08-04`.
Implementation SHA (exact): **0af42a1c50952d6b97a3f6f6aaa062d4cb7567c3**
Parent (accepted partial foundation, per owner): `b1a292b`. PR #11 remains frozen
at `c816f09` — no merge, deploy, force-push, history rewrite, or device action.

Model assignment (owner ruling 2026-08-05): primary implementer/coordinator
`claude-opus-4-8` (authorized substitute for Opus 5). Independent non-author
reviewers: `kimi-code/k3` (kimi CLI 1.49.0) and `gpt-5.6-sol` (codex CLI
0.146.0). Attestations are stored on the documentation branch so they do not
mutate the reviewed implementation SHA.

## File manifest (SHA-256 at 0af42a1)

| File | SHA-256 |
|---|---|
| docs/research/2026-08-01-hardening/hw_matrix_pull.sh | 1322b45a1af29069f481b7618860f24a023708f36a0efda8e689eea0396e5c5c |
| docs/research/2026-08-01-hardening/hw_matrix_pull_test.sh | 1e1f13ea26f0cf1b1624d548dcd634bf90f38ccbcf843d8a21ffb4b5a6bc8317 |
| ios/Runner/BackgroundBeacon.swift | dcf0d813dd4ec8b40fbd088d215612be3f0597482704b452ff0b0711dbbe0a6d |
| ios/Runner/W5Diag.swift | 90b037061a4aa6e72fc993ab0ab2c70fdae2c0c66ff6f30fc481e473f9a978f3 |
| ios/Runner/W5EvidenceWriter.swift | 59b1ae797708a9fb5b049a9ae7df5e60a13cffbd3e820d8459e4c3c3c4f1f003 |
| ios/Runner/W5LinkController.swift | 897a7c4dec9a737c9369949695319daba838bc52cded9665d3a8c8d412ae617b |
| ios/RunnerTests/W5DiagTests.swift | 73062a80e5a93bd245bc731143bcc2ea5b1465ba486a48b731f05ab2953694ec |
| ios/RunnerTests/W5TeardownTests.swift | 86ff8e40d16e0eec4664710d1a61c41bd5af13368acaf570d3e553bb63972be1 |
| lib/features/beacon/background_beacon_channel.dart | 232845eb2033c39a6b27b0651d61070a781d22b2bea8c7874cc51afa36dd5b1f |
| lib/features/beacon/beacon_service.dart | 2652e89e3808dc021cbfa14ac2a41b46654c9bd4001b8d59bcd11b11f0822dbe |
| test/features/beacon/w5_diag_control_test.dart | bdee2f25924ffd8ee85493657b5628aab3749eaeaab568c41d7404de8183180d |

## Local validation at 0af42a1 (all green, zero controlling skips)

| Gate | Result |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` (full) | 278 passed, 0 failed |
| Native diag scheme (`RunnerTests`, INRANGE_DIAG) | 79 passed, 0 failed, 0 skipped |
| Native prod scheme (`RunnerTests`, no INRANGE_DIAG) | 55 passed, 0 failed, 0 skipped |
| `XCTSkip` count in test sources | 0 |
| Puller fake-xcrun harness | 44 asserts passed, 0 failed |
| `scripts/check_release_isolation.sh` | Release/Profile carry no INRANGE_DIAG; Release-diag positive control OK |
| `git diff --check` | clean |
| `bash -n` (Wave A scripts) | both parse OK |
| Exact-SHA CI (ci.yml: analyze+test, android unit) | triggered on each pushed SHA |

Note (CI scope): `ios-build.yml` (the executable binary-isolation gate) triggers
only on push-to-main or a pull_request touching ios/**, not on a feature-branch
push. PR #11 is frozen and no new PR was opened (per constraints), so that
workflow was NOT run in CI; the source-level isolation check ran locally and the
executable bundle gate remains a PR-gated step for a later gate.

## Predicate closure

- **A1** real-quiescence destruction serialization: `BackgroundBeacon.isW5Quiescent`
  from real state only (no flag short-circuit); `W5LinkController.isQuiescent`
  counts every link/lease/timer incl. `persistTimer` (cleared only AFTER the
  persist write, so quiescence is false for the whole write);
  `destroySessionSecret(w5Quiescent:)` through the one recursive session lock;
  `ok` reflects a partial wipe. Tests: real-controller stopped/live + concurrent
  reset/emit serialization.
- **A2** reset/append serialization: inventory-based wipe of every family's
  current + rotated artifact under one boundary; secret retained, only public
  case/run epoch rotates (frozen contract #7 "resets sequence/run"). Tests:
  wipe-all-incl-rotations, retain-secret, concurrency no-torn-line.
- **A3** key-ready gate: `setDiagRunSecret` returns+awaits native ack; Dart
  provisions + settles the W5 flag BEFORE native `start`; native `w5LinksEnabled`
  requires the flag AND `W5Diag.hasFleetKey` (injected/provisioned only) — fail
  closed even if a Dart→native call is lost. Tests: ack shapes + native gate.
- **A4** strict staged puller + writer accounting: secret validated (>=64 hex)
  before device contact; no partial pull (rm-before + delete-on-fail); mandatory
  primary; per-file JSONL schema (mandatory event-identity fields, seq strictly
  increasing, all three epochs constant) AND cross-file chain (all epochs match,
  rotated seq < current seq), NO regex fallback; residual-id post-scan; atomic
  os.replace symlink publish (successful-republish tested, legacy preserved);
  path-traversal-safe superseded-rev cleanup; native floor aligned to >=64;
  writer losses typed per (file,op) and snapshot-retained (a failure during the
  boot append survives; a failed-wipe counter survives a not-fully-ok reset).
  Fake-xcrun harness: 44 asserts. Injectable file-op fault tests for every op.
- **A5** no controlling skip: `testHandleUsesProvisionedRunSecret` provisions a
  known secret and asserts deterministically; zero `XCTSkip` in the suite.

## Red-before / green-after (captured)

- A2 inventory wipe: with `inventory` reduced to `[url]`,
  `testResetCaseWipesEveryFamilyIncludingRotations` FAILS (xcodebuild exit 65);
  restored to `[url, rotatedURL]` ⇒ green.
- A4 native floor: with the provisioning floor at >=32,
  `testProvisionRequires64HexMatchingPullerContract` FAILS (exit 65); at >=64 ⇒
  green.
- A1 / A5 / A4 typed accounting: the predicates' APIs and the removed XCTSkip do
  not exist / differ at the parent, so the new tests fail (compile/behaviour)
  against `b1a292b` and pass at the tip.

## Review history (A6) — two independent non-author backends, adversarial

Every round's findings were confirmed genuine and fixed with a committed test.

| SHA | gpt-5.6-sol | kimi-code/k3 | Fixed → |
|---|---|---|---|
| bcd71e7 | CHANGES-REQUESTED | CHANGES-REQUESTED | ce21df8 |
| ce21df8 | CHANGES-REQUESTED | — | f8b668c |
| f8b668c | CHANGES-REQUESTED | **APPROVE** | 6dd7438 |
| 6dd7438 | CHANGES-REQUESTED | (approved earlier) | b812b6d |
| b812b6d | CHANGES-REQUESTED | — | 2b19890 |
| 2b19890 | CHANGES-REQUESTED | — | c3b4ca7 |
| c3b4ca7 | CHANGES-REQUESTED | **APPROVE** | 0f9a637 |
| 0f9a637 | CHANGES-REQUESTED (4, exhaustive) | (superset approved) | ac77c57 |
| ac77c57 | CHANGES-REQUESTED (1, exhaustive) | (superset approved) | 538c1d8 |
| 538c1d8 | CHANGES-REQUESTED (1, exhaustive) | (superset approved) | bc9a4e4 |
| bc9a4e4 | CHANGES-REQUESTED (5, sweep) | (superset approved) | 467e371 |
| 467e371 | CHANGES-REQUESTED (3 native; A4/A5 PASS) | (superset approved) | 10b7168 |
| 10b7168 | CHANGES-REQUESTED (3 native/design) | **APPROVE** | 16b02b5 |
| 16b02b5 | CHANGES-REQUESTED (1: concurrent-merge lock) | **APPROVE** | 0af42a1 |
| 0af42a1 | **APPROVE** (A1-A5 all PASS, none) | **APPROVE** (A1-A5 all PASS, none) | — |

Findings resolved across rounds: A1 flag short-circuit / persistTimer omission /
persistTimer-cleared-too-early / partial-wipe masked as ok; A3 provision-after-
start / native fail-open; A4 non-atomic publish / mv-follow / legacy rm window /
untyped append losses / ack-during-append / cp-suppressed / path-traversal in
cleanup / cross-file epoch+seq chain / epoch constancy / partial-pull / mandatory
event-identity fields. All fixed.

### Reviewer attestations on 0af42a1

**Both independent non-author reviewers APPROVED the exact SHA `0af42a1c50952d6b97a3f6f6aaa062d4cb7567c3`** (A1-A5 all PASS, zero remaining defects). Raw verdicts are committed alongside this packet on the documentation branch (`WAVE_A_ATTESTATION_codex-gpt-5.6-sol.txt`, `WAVE_A_ATTESTATION_kimi-code-k3.txt`).

#### gpt-5.6-sol (codex CLI 0.146.0)

```
A1 VERDICT = PASS  
A2 VERDICT = PASS  
A3 VERDICT = PASS  
A4 VERDICT = PASS  
A5 VERDICT = PASS  

Complete list of remaining defects: none.

OVERALL = APPROVE
```

#### kimi-code/k3 (kimi CLI 1.49.0)

```
• Independent Review — Wave A (b1a292b..0af42a1)
══════════════════════════════════════════════

Read the full diff directly. Traced every predicate against the code and the t
wo committed harnesses (hw_matrix_pull_test.sh, W5DiagTests.swift additions),
including the new lock/publish path line by line.

Per-predicate verdicts
──────────────────────

A1 — real-quiescence destruction serialization: PASS isW5Quiescent (Background
Beacon.swift +30) reads live state only (w5/inflight/w5Link.isQuiescent incl.
persistTimer), deliberately ignoring the persisted flag. persistTimer = nil is
cleared only after the persist write completes (W5LinkController.swift +812),
closing the spurious-quiescent window. destroySessionSecret routes through res
etCaseLocked inside eventWriter.withLock and aborts — secret retained, keyEpoc
h unadvanced — on any wipe failure (W5Diag.swift +243). Covered by testDestroy
GatedByRealControllerQuiescence and testDestroyAbortsAndRetainsSecretWhenWipeF
ails.

A2 — reset wipes every family incl. rotations, secret retained, serialized, RS
SI ack epoch-guarded: PASS resetCaseLocked iterates [eventWriter, wakeWriter,
rssiWriter].wipeLocked(), and inventory is [url, rotatedURL] — all six artifac
ts. Transactional: any wipe failure returns ok:false with no epoch rotation, n
o control clear, no seq reset, no ack. Secret retained on all paths. lastDrain
CaseEpoch captured at drain and checked in ackFileSamples under the same sessi
on lock that reset's wipe takes (W5LinkController.swift +980, +1066). Covered
by testResetCaseWipesEveryFamilyIncludingRotations, testWipeFailureDuringReset
RetainsTypedCounter, testRssiAckDiscardedAfterCaseReset, testConcurrentResetAn
dEmitSerializeNoTornLine.

A3 — fail-closed native key gate, transactional rotation: PASS w5LinksEnabled
= flag AND hasFleetKey (injected or provisioned, never the fallback). Rotation
wipes old-key evidence before committing the new key; wipe failure → old key r
etained, epoch unadvanced, rotate-wipe-failed. Dart gate provisions and awaits
the ack before start(payload), asserts the flag either way, and fails to null/
OFF on channel error (beacon_service.dart +1018). 64-hex floor matches the pul
ler contract (testProvisionRequires64HexMatchingPullerContract). Close-failure
durability correctly forces ok=false so recordPriorLoss never acks an undurabl
e record (W5EvidenceWriter.swift +120).

A4 — strict staged puller incl. serialized 3-device merge: PASS Pre-contact se
cret validation (≥64 even hex); LABEL/CASE token validation before any path op
; partial-copy discard on devicectl failure; mandatory primary; strict JSONL s
chema with no regex fallback, duplicate-key and strict-UTF-8 rejection, per-ru
n seq monotonicity, intra-file epoch constancy, cross-rotation epoch equality
+ per-run seq ordering; residual-id post-scan; atomic symlink swap via os.repl
ace (no follow); tamper-safe superseded-rev cleanup; legacy dir move-aside wit
h restore-on-failure; and the new per-case mkdir lock serializes seed→swap so
concurrent same-case publishers cannot lost-update (test 31 proves both labels
survive; test 32 proves fail-closed exit 7 on a held lock). Lock released via
EXIT trap on all paths after acquisition.

A5 — no controlling skip: PASS testHandleUsesProvisionedRunSecret provisions a
known key deterministically and asserts handle equality plus re-key divergence
— no XCTSkip, no environment conditional. Dart A3 tests assert ack round-trip,
rejection, and channel-error fail-closed.

Remaining defects
─────────────────

none.

(Checked and cleared as non-defects: set -e &&-list semantics in the migration
/cleanup guards are correct — non-final test commands can't exit, final comman
ds failing is the intended fail-closed path; the python chain-check exit codes
propagate through set -e even where the explicit rc=$? is redundant; the seed-
merge dereferences <case> by design — <case> is only ever produced by this too
l pointing inside OUT_ROOT, and a foreign symlink is post-hoc tree tampering e
quivalent to editing any published file, with the deletion direction already g
uarded per test 14; in_range_local.db is pulled but intentionally unpublished,
wiped with staging.)

OVERALL = APPROVE
```
