# Wave A READY claim — exact-SHA panel review

Date: 2026-08-05

Implementation SHA: `0af42a1c50952d6b97a3f6f6aaa062d4cb7567c3`

Evidence SHA: `c625633f4e8469ca47e19fbfabbb397e50b63a19`

Branch: `fix/w5-convergence-2026-08-04`

Decision: **HOLD — the `WAVE_A_READY` claim is refuted.**

Device action: **not authorized.**

PR #11: independently verified open, draft, and frozen at `c816f09df433bb9d3c80ad222ae2d88a63b8ed10`.

This is a bounded review of A1–A5 and the claimed closure packet. It does not reopen later Waves B/C. The implementation makes substantial progress, but the current harness proves a representation the native writer never produces, mandatory B4 operations still bypass the writer abstraction, and the real-quiescence and key-readiness predicates remain false in deterministic states.

## Panel disposition

- Codex/root exact-SHA audit: **HOLD**.
- Independent A1–A3 runtime/concurrency reviewer: **HOLD**.
- Independent A4/B4 writer/puller reviewer: **HOLD**.
- Independent A5/evidence/provenance reviewer: **HOLD**.
- Fresh targeted Kimi 3 (`kimi -m kimi-code/k3`) falsification: **HOLD**.

The targeted Kimi 3 run confirmed all seven supplied reproductions and explicitly withdrew its earlier PASS attestation for `0af42a1`. That earlier approval must not be counted toward two-reviewer closure.

## Exact state and independently reproduced passes

- Remote implementation tip resolved to `0af42a1c50952d6b97a3f6f6aaa062d4cb7567c3`.
- Remote evidence tip resolved to `c625633f4e8469ca47e19fbfabbb397e50b63a19`.
- All eleven file SHA-256 values in the evidence packet match the exact implementation tree.
- `flutter analyze`: clean.
- `flutter test`: 278/278 passed.
- `hw_matrix_pull_test.sh`: 44/44 passed.
- `bash -n` on both Wave A shell scripts: passed.
- `git diff --check b1a292b..0af42a1`: clean.
- Exact-SHA GitHub CI run `31035228578`: green Linux analyze/test and Android unit jobs.
- Review worktrees remained clean. No implementation edit, PR/workflow mutation, device action, merge, deploy, force-push, or history rewrite was performed.

These passes are retained. The controlling problem is that several tests do not model the production data/state they claim to prove.

## Controlling blockers

### R1 — The committed join test uses an impossible native event shape

`W5Diag.handle` returns a bare 14-hex handle (`ios/Runner/W5Diag.swift:455-478`), and `emit` writes that value into event identity fields. The puller instead emits `id:` plus 14 hex when hashing raw RSSI identifiers (`hw_matrix_pull.sh:125-137`). Its sanitizer rewrites only 32-hex or UUID values, so a real native 14-hex event handle remains bare.

The committed harness places a raw 32-hex value in `w5_events.jsonl` (`hw_matrix_pull_test.sh:71-82`). Native `W5Diag.emit` cannot produce that fixture: it HMACs the raw peer before writing. Because the impossible event fixture and RSSI fixture both contain raw 32-hex, the harness prefixes both and reports a false join.

Executed reproduction using the same fleet-key test vector and a native-shaped event fixture:

```text
native event peer handle: f55d95f9f0f37a
puller exit:              0
published event peer:    f55d95f9f0f37a
published RSSI token:    id:f55d95f9f0f37a
join:                     FAIL
```

This directly refutes the packet's assertion that live event and RSSI handles align.

Required repair:

1. Choose one canonical published representation for every domain handle.
2. Validate real event fields as native-produced handles; do not test by feeding raw identifiers into a layer that never writes them.
3. Make RSSI and wake sanitization produce the identical representation.
4. Replace the fixture with native-shaped event output and add an end-to-end join assertion that fails on the current code.

### R2 — The puller still accepts transport failure and imports unvalidated prior content

`pull()` converts every nonzero `devicectl` result into `(no file)` and returns success (`hw_matrix_pull.sh:83-105`). Only the primary event file is mandatory. A permission, transport, container, or partial-copy failure for an optional/case-required artifact is indistinguishable from legitimate absence.

Executed reproduction: the fake device tool returned a transport-style nonzero for optional artifacts while successfully returning the primary. The puller printed the files as absent, returned `0`, and published the case. The 44-test harness maps optional absence and transport failure to the same generic nonzero and therefore never tests the frozen distinction.

There is a second publish-boundary bypass. Raw-ID post-scan runs over `$SAN` before existing labels are carried into `$REV` (`hw_matrix_pull.sh:313-324,361-373`). If the existing case symlink points outside `hardware_evidence`, the puller follows it and copies arbitrary files into the new revision without canonical-path validation, schema validation, or a second post-scan. An executed reproduction carried an outside `private.txt` containing a raw 32-hex identifier into a successful publication.

Python's default JSON parser also accepts `NaN`; the current strict parser republishes it even though it is not valid strict JSON.

Required repair:

- distinguish a specifically verified optional-not-found result from every transport, permission, container, and copy failure;
- define and enforce case-required artifacts;
- require the prior case target to be a canonical local revision with regular sanctioned files only;
- validate and post-scan the complete merged revision after carry-over;
- reject non-finite JSON constants and serialize with non-finite values disabled;
- add fake-device tests for each failure and the hostile-prior-symlink case.

### R3 — Mandatory B4 file operations still bypass `W5EvidenceWriter`

RSSI operations remain direct silent `try?` calls in `W5LinkController`:

- size/read/trim replacement: `W5LinkController.swift:1021-1035`;
- drain read: `W5LinkController.swift:1039-1059`;
- acknowledgment size/delete: `W5LinkController.swift:1080-1085`.

They are outside the required writer operation abstraction, have no typed failure accounting, have no injected failure seam, and do not reapply/verify protection and backup exclusion after trim replacement. Current injected tests cover rotate, rotate-unlink, protect, backup, close, and wipe, but not mandatory stat/read/trim/replace/delete operations (`W5DiagTests.swift:599-643`).

The foreign-flavor wipe also bypasses the writer inventory, silently deletes, and still omits `w5_rssi_log.1.jsonl` (`BackgroundBeacon.swift:165-180`). A partially failed reset can delete RSSI without changing `caseEpoch`; an old drain acknowledgment then passes the epoch-only guard and can apply stale offsets to newly appended evidence.

Required repair: put stat/read/trim/replace/delete and foreign-flavor wipe behind the same injected, typed, session-locked owner; reapply and read-back-verify attributes after replacement; give RSSI drains a generation invalidated by any wipe attempt, including a partial failed reset; add deterministic failure tests for every operation.

### R4 — Real-quiescence has a live-lease false positive

`W5LinkController.isQuiescent` checks adapter maps/timers but omits `ownership.activeLeases` (`W5LinkController.swift:79-87`; `W5Ownership.swift:231`). A normal link-down removes the link/handle and places the encounter in grace. Restoration can restore that live in-grace encounter with no handles and no returned peripheral. `leaseByHandle`, link maps, and timers then remain empty while `ownership.activeLeases == 1`; `BackgroundBeacon.isW5Quiescent` reports true and authorizes secret destruction.

Deterministic native regression:

1. create and commit an outbound lease;
2. drive link-down and persist the in-grace snapshot;
3. create a new controller and restore with no peripherals;
4. assert `activeLeases == 1` and current `isW5Quiescent == true`;
5. prove destruction is currently accepted, then make the repaired result reject it.

Restoration must also re-arm or otherwise account for the grace deadline; the restored live encounter currently has no grace timer.

### R5 — The session/key-ready transaction remains split

Three previously frozen defects remain:

1. `armFault`/`disarmFault` mutate control state under the session lock and emit their acknowledgment only after releasing it (`W5Diag.swift:269-298`). Reset can interleave, leaving a new-case `armed` event while the actual state is disarmed.
2. `shortHandle` derives under `runSecretLock`, outside `sessionLock`; callers interpolate the result before `wakeWriter.append` acquires the session lock (`W5Diag.swift:552-558`; `BackgroundBeacon.swift:833-840,1342,1448`). Rotation can therefore append an old-key handle after the new-case wipe.
3. Dart `setW5Links` catches a platform error and returns normally (`background_beacon_channel.dart:345-352`), after which `BeaconService` always calls native start (`beacon_service.dart:1027-1042`). With stale `bb.w5links=true` and an older valid provisioned key, a failed provision followed by a swallowed disable failure starts W5 under the stale key.

The supported environment-key path is also internally contradictory. `persistedSecretLocked` always prefers environment key A, while provisioning B stores B only in defaults/cache (`W5Diag.swift:107-145,416-435`). Repeated provisioning of B compares against A every time, wipes evidence, and advances `keyEpoch`; relaunch resolves A again. `destroySessionSecret` can report `secretDestroyed:true` while the immutable environment key remains authoritative and `hasFleetKey` stays true.

Required repair:

- make control mutation plus evidence acknowledgment one locked transaction;
- derive wake handles and append the line inside one session transaction;
- make W5 configuration/start a structured acknowledged native transaction, or abort start when the requested disable/configuration is not acknowledged;
- define one env-versus-provisioned precedence rule: mismatch must fail closed before wipe, repeated same-key configuration must be idempotent, and destroy must reject an immutable environment key or report truthful semantics;
- add barrier-driven control/reset and wake/rotation tests plus stale-flag/channel-failure and env-A/provision-B tests.

### R6 — Exact native zero-skip and independent-signature evidence is not closed

The exact-SHA GitHub run contains only Linux/Android jobs. `ios-build.yml` is manually dispatchable (`workflow_dispatch`), contrary to the packet's claim that it can run only on main or a PR. Its native steps merely grep for `TEST SUCCEEDED`; they do not enforce discovered equals passed, zero skipped, or execution of the named A5 test.

The packet says 79 diagnostic tests while the return message says 82. No exact command transcript, sanitized native log, `.xcresult` hash, or CI artifact resolves the discrepancy. The Codex attestation is nine verdict lines with no strongest falsification attempt, command, exit status, reproducer, red/green result, or artifact hash. Kimi's earlier detailed approval is now explicitly withdrawn by a fresh `kimi-code/k3` review.

The implementation ledger also still says the Opus substitution awaits owner resolution, while the evidence packet says it was authorized. Record the value-free owner ruling consistently on the documentation branch.

Whole-bundle binary isolation and physical attribute enforcement remain later `CODE_READY`/`PREFLIGHT_READY` gates. Their absence does not independently block this Wave A decision.

## Single repair/return packet

Do not respond with another progress narrative and do not broaden into Waves B/C. Return one new exact implementation SHA only after:

1. R1–R5 are repaired with deterministic red-before/green-after tests, including the executed native-shaped join and optional-transport reproductions.
2. The full Dart/native/puller suites pass with zero controlling skips.
3. The manually dispatchable exact-SHA iOS workflow is run, or a precise permission blocker is reported after every other repair is complete; retain sanitized logs and hashes.
4. Both fresh non-author reviewers attack the same real-format fixtures and state transitions, record commands/exits/artifact hashes, and approve the same SHA.
5. The corrected evidence packet reports one authoritative native count and records the owner model-substitution ruling consistently.

Allowed terminal states:

- `WAVE_A_READY <new-exact-sha>` with the complete corrected packet; or
- `EXTERNAL_BLOCKER <exact-permission>` after all code and locally runnable proof is complete.

Keep PR #11 frozen. No phones, merge, deploy, force-push, mirror rewrite, or history rewrite.
