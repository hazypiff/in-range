# Wave A panel review — `9bf4583`

Date: 2026-08-05

Reviewed implementation SHA: `9bf45831c30401a574de2279a208f015cb259c9c`

Branch: `fix/w5-convergence-2026-08-04` on `inrangeai/in-range`

Baseline: `adb475c47042f76948ef111fe31d2a762388137a`

Decision: **HOLD — Wave A is not complete and `CODE_READY` is not authorized.**

Device action: **not authorized.**

PR #11: verified frozen at `c816f09df433bb9d3c80ad222ae2d88a63b8ed10`.

This is a bounded Wave A decision, not a request to reopen the whole repository audit. The implementation contains useful B3 improvements, but the committed code, tests, and ledger do not satisfy the frozen B3/B4 predicates. The Mac coordinator may develop later waves in isolated worktrees, but must not integrate them into the convergence branch or claim Wave A / `CODE_READY` until the exit packet below passes on one new exact SHA.

## Exact-state checks

- The remote branch still resolved to the reviewed SHA when this report was finalized.
- The two Wave A commits are `7811171` and `9bf4583`.
- The Wave A diff changes seven files. It does **not** change `W5EvidenceWriter.swift`, `W5LinkController.swift`, or `hw_matrix_pull.sh`, although those are controlling B4 surfaces.
- Linux verification at the exact SHA: `flutter analyze` clean; `flutter test` 274/274 passed; `git diff --check` clean; review worktree clean.
- Native Xcode results were not independently rerun on Linux. The reported 69 diagnostic and 55 production cases are not accepted as proof of the mandatory predicates because one controlling diagnostic test can skip and required adversarial tests are absent.
- No merge, PR movement, workflow dispatch, device action, history rewrite, or implementation-branch edit was performed by this review.

## Accepted improvements

The following work is real and should be preserved:

- `W5Diag.emit` now derives peer, lease, link, and peripheral handles from one `{secret, keyEpoch, caseEpoch}` snapshot while the event-writer boundary is held.
- Normal provisioning and event emission use the same `eventWriter -> runSecret` lock order; no inversion was found on those paths.
- `resetCase` retains the fleet secret, rotates the public case epoch, resets event sequence, and clears the current fault/delay state on its direct path.
- Nil and empty fault targets fail closed.
- Short, odd-length, and non-hex secrets covered by the present tests are rejected without mutating the cached key.
- Owner provenance is value-free and durable. The ledger also honestly states that cross-review and B4 tests continue; that statement must not be upgraded to Wave A closure.

## Controlling blockers

### A1 — Secret destruction bypasses the atomic session boundary

`W5Diag.destroySessionSecret` takes `runSecretLock`, but not `eventWriter`; it clears the secret and changes `keyEpoch` without wiping/rotating evidence, resetting sequence, or clearing fault/delay state (`ios/Runner/W5Diag.swift:180-189`). This permits a deterministic one-file/two-key result:

1. provision key A;
2. emit an attributed event;
3. destroy while reported inactive;
4. emit another attributed event;
5. observe handles derived from A and a generated replacement key in the same JSONL lifecycle.

A concurrent emit can additionally observe a secret/epoch transition outside the serialized append boundary.

The native guard is not an actual stopped-state proof. `BackgroundBeacon` passes the persisted `w5LinksEnabled` feature flag (`BackgroundBeacon.swift:408-413`), not live managers, sessions, timers, or controller state. The current test supplies `true` or `false` directly (`W5DiagTests.swift:151-161`) and therefore does not exercise the real guard.

Required repair: route destruction through the same global session/writer boundary; prove actual W5 quiescence; wipe/rotate every evidence family; clear dependent state; return a structured durable result. Add a real-controller stopped/live test plus sequential and concurrent one-file/one-key tests.

### A2 — Reset is not atomic across evidence writers and does not acknowledge wipe failure

`resetCase` holds only the event writer and calls a raw global wipe (`W5Diag.swift:143-173`). Wake and RSSI writers own different locks, so either can append while reset unlinks files. Wake handles can also be computed before the wake-writer append boundary, allowing an old-key handle to land after reset.

The wipe inventory in `BackgroundBeacon.swift:153-162` omits `w5_rssi_log.1.jsonl`, even though `hw_matrix_pull.sh:32-33` treats it as an evidence artifact. Removal uses silent `try?`, yet reset returns success and clears persisted loss counters. `runLabel` and `bootEpoch` remain immutable process constants (`W5Diag.swift:288,355-357`) despite the frozen run-state reset contract.

Fault-control mutation and its evidence are also separate transactions. `armFault` or `disarmFault` changes state, releases the writer boundary, and emits afterward (`W5Diag.swift:207-236`). A reset/provision can interleave, producing a new-case `armed` event while the actual state is disarmed.

Required repair: one ordered session boundary must own every evidence family and lifecycle control; mutation plus its acknowledgment event must be one transaction; wipe must use a complete declared inventory and return typed per-operation outcomes; counters may clear only after durable acknowledgment. Add barrier-driven reset-vs-append and control-vs-reset tests, including every rotated file.

### A3 — Startup/restoration remains start-before-provision and provisioning is not fail closed

Dart invokes native `start` before `setDiagRunSecret` (`lib/features/beacon/beacon_service.dart:1018-1028`). Native start creates or restarts managers immediately. Boot/restoration events can therefore resolve a fallback key before Dart supplies the fleet key; later provisioning can rotate and wipe the evidence needed to prove restoration.

The bridge discards the native structured acknowledgment: `BackgroundBeacon.swift:378-383` returns `nil`, while `BackgroundBeaconChannel.setDiagRunSecret` exposes `Future<void>` and swallows failure (`background_beacon_channel.dart:354-365`). W5 enablement proceeds even if provisioning was rejected or persistence failed. The Dart test accepts `null` and verifies only a method call.

Environment precedence creates another repeat-rotation case: when injected key A exists and Dart provisions B, subsequent provisioning compares against A again, can rotate/wipe repeatedly, and relaunch resolves back to A.

Required repair: install or resolve the fleet key before any native manager can emit, including restoration; otherwise hold managers behind an explicit key-ready gate. Return and await a structured provisioning acknowledgment and fail closed before W5 enablement. Define one precedence rule for injected/provisioned keys. Add restore-before-Dart, rejected-provision, persistence-failure, repeated-provision, and startup-readiness tests.

### A4 — The B4 evidence writer and extraction/publish chain are still open

The controlling B4 files are unchanged from the baseline. Current defects therefore remain:

- file-size lookup, close, old-rotation removal, RSSI trim/read/delete, and portions of wipe silently discard failures;
- `noteOpFailure(_ kind:)` discards the operation kind, so accounting is not typed by operation;
- rotated-family failures are not reliably attributed;
- prior loss counters are erased before the boot evidence append is durably acknowledged;
- file operations are not injectable, and the required rotate/protect/backup/trim/delete/close/wipe/boot-record failure tests do not exist;
- `hw_matrix_pull.sh` creates output and contacts the phone before fully validating the fleet key;
- the puller accepts a weaker length-only key check, treats transport failure as optional absence, has no mandatory primary artifact, and falls back from malformed JSON to regex rewriting;
- the puller has no strict schema/epoch/sequence validation, staging directory, raw-identifier post-scan, atomic publication, or fake-`xcrun` failure harness.

Required repair: complete B4 exactly as frozen—one injectable serialized I/O owner; typed retained-until-ack failures for every operation/family; strict pre-contact validation; mandatory artifact semantics; strict JSON parse and join validation; fail-closed sanitization; raw-ID post-scan; staged atomic publish; fake-device-tool tests for every failure class.

### A5 — The reported native suite can be green while a mandatory test skips

`W5DiagTests.testHandleUsesInjectedRunSecret` explicitly skips when `INRANGE_DIAG_RUN_SECRET` is absent (`W5DiagTests.swift:80-85`). The diagnostic scheme and exact workflow do not inject that environment variable into the test process. Consequently, a reported 69/69 suite does not establish that the injected-key path executed. Production Runner tests compile diagnostic behavior out and cannot substitute for that proof.

The repair commit `9bf4583` adds no tests for the three predicates its reviewers reportedly found. Mandatory missing tests include:

- concurrent provision versus multi-field emit;
- one file/key epoch never containing two secret domains;
- reset versus in-flight event/wake/RSSI append;
- complete current/rotated artifact wipe with injected failure;
- real live/stopped destruction through the controller boundary;
- restoration before Dart startup and startup key readiness;
- an injected-secret test that demonstrably runs rather than skips;
- every B4 file-operation and pull/publish failure.

Required repair: commit a deterministic red reproduction before each high-risk repair, then the green implementation. Record exact commands, exit status, named cases, pass/skip counts, SHA, and relevant artifact hashes. A controlling skip is a blocker, regardless of workflow conclusion.

### A6 — Reviewer/model provenance and closure artifacts do not meet the requested panel contract

The ledger records `claude-opus-4-8`, not the requested Opus 5. It records `kimi 1.49.0` and `codex 0.146.0`, which are CLI versions rather than backend model identities; those strings do not prove Kimi 3 or GPT Sol ran. Honest disclosure is good, but it is not model substitution authorization.

No committed independent attestation contains each non-author's strongest falsification attempt, reproducer, red/green result, and exact-SHA decision. The ledger itself says cross-review and B4 tests continue. The reported review-found repairs landed without verifier-owned regression tests.

Required repair: invoke the requested backends and record both tool version and backend/model identity. If a requested backend is unavailable, emit `EXTERNAL_BLOCKER` instead of silently substituting. Store signed attestations on the documentation branch so signing does not mutate the reviewed implementation SHA.

## Later-wave dependency, not charged as a Wave A blocker

New `resetW5Case` and `destroyW5Secret` method strings/cases compile outside a diagnostic guard in Swift and Dart, while the current isolation checker does not scan them. This must be closed by the frozen paired B5/C2 production-canary gate before `CODE_READY`; it does not independently change this Wave A HOLD.

Native key validation also accepts 32-character hex while the frozen artifact/puller contract requires at least 64. Align the threshold now so a native-accepted key cannot make later extraction fail closed.

## Single Wave A exit packet

Do not answer this review with another narrative checkpoint. Return one exact implementation SHA only after all of the following are true:

1. A1–A5 are repaired with committed red-before/green-after tests.
2. B4 writer, sanitization, and staged pull/publish behavior is implemented rather than deferred.
3. All mandatory native and Dart tests run with zero controlling skips; exact commands and counts are recorded.
4. Two non-author requested-model reviewers independently run their strongest falsification attempts and approve the same exact implementation SHA.
5. A value-free manifest names every changed file, test, artifact hash, reviewer identity, and backend model identity.
6. The implementation branch is pushed; PR #11 remains frozen; no device action, merge, deploy, mirror rewrite, or history rewrite occurs.

Allowed terminal states are:

- `WAVE_A_READY <exact-sha>` with every item above attached; or
- `EXTERNAL_BLOCKER <unavailable-model-or-permission>` with the exact unavailable dependency and all other runnable work complete.

Do not start the physical preflight or hardware matrix. Do not broaden the response into later-wave findings. Once Wave A is accepted, continue the already-frozen build/attack/repair sequence toward `CODE_READY` without asking the owner for routine implementation decisions.

## Panel disposition

- Codex/root exact-SHA audit: **HOLD**.
- Independent runtime/concurrency reviewer: **HOLD**.
- Independent isolation/privacy/evidence reviewer: **HOLD**.
- Headless Claude review: **HOLD**.
- Headless Kimi CLI review: **HOLD** (backend Kimi 3 identity was not independently established).

The reviewers independently converged on startup provisioning, destruction/reset serialization, unchanged B4 failure handling, and false-green test coverage as the controlling blockers. No reviewer finding requires phone access to reproduce or repair.

## Verbatim coordinator dispatch

> Panel decision on exact SHA `9bf45831c30401a574de2279a208f015cb259c9c`: `WAVE_A: HOLD`. Preserve the accepted B3 work, but return to Wave A now. Your committed ledger itself says B4 tests continue, and the controlling B4 files/puller are unchanged. Do not integrate Wave B/C into the convergence branch and do not request phone work yet; isolated later-wave development may continue without changing this reviewed branch.
>
> Close A1–A5 from `WAVE_A_PANEL_REVIEW_9BF4583_2026-08-05.md`: serialize destruction and all reset/wipe/control operations across every evidence writer; prove real W5 quiescence; provision/acknowledge the fleet key before any manager can emit; implement the complete injectable B4 failure-accounting and strict staged pull/sanitize/publish chain; eliminate the controlling injected-secret skip. Add deterministic verifier-owned red-before/green-after tests for every listed predicate. Do not weaken the frozen predicates or answer with another progress narrative.
>
> Use the requested Opus 5, Kimi 3, and GPT Sol backends and record backend identity separately from CLI version. If any requested backend is unavailable, report `EXTERNAL_BLOCKER` rather than substituting. Have both non-authors run their strongest falsification attempt against the same new exact SHA and store attestations on the docs branch so they do not mutate the implementation SHA.
>
> Continue autonomously through repair, adversarial tests, full local validation, exact-SHA CI/artifact evidence available without owner action, push, and independent re-verification. Return only `WAVE_A_READY <exact-sha>` with the complete exit packet, or `EXTERNAL_BLOCKER <dependency>` after all other runnable work is complete. Keep PR #11 frozen. No merge, deploy, force-push, history rewrite, mirror rewrite, or device action.
