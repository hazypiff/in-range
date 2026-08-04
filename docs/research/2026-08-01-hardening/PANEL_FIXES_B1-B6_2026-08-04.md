# Panel-fix checkpoint — blockers B1–B6 (2026-08-04)

Response to the exact-SHA panel review of `357053c`
(`PHASES_1_4_PANEL_REVIEW_2026-08-03.md`, decision **HOLD**). One separable
commit per blocker, full Dart/native/isolation suite run after each. Branch
`fix/w5-hardware-evidence-2026-08-03`; **PR #11 stays frozen** at `c816f09`.
Stopped before any physical-device install / preflight / matrix rerun — this SHA
is for the next blinded panel review.

## Commits (one per blocker)

| SHA | Blocker | Summary |
|---|---|---|
| `c141003` | B6 | scrub device serials from the tip; correct fleet to owner-confirmed iPhone 14/13/15 Plus; stage `PRIVACY_REDACTION_PROPOSAL.md` (no force-push) |
| `1e05dd6` | B1 | current-alias trust (fresh/stale/unavailable vs 24h card); await + propagate the native teardown result; server-card `unavailable`; executable Dart + real-controller-path Swift tests |
| `772a670` | B2+B3 | every missing emit site; committed Dart fault-control path; two-layer `@autoclosure` emit; restoration-surviving run secret (env→provisioned→per-install persisted) + diag-scheme/artifact injection |
| `2f7cc33` | B4 | one serialized `W5EvidenceWriter`: absent-vs-inaccessible, protection+backup after every op, per-family bounded drop counters; wake log de-identified; RSSI hardened |
| _(this)_ | B5 | both schemes + build-settings + final-binary negative/positive controls in CI; release IPA gated on `[test-ios, isolation-ios]` |

## Blocker-by-blocker

### B1 — current-alias trust + observable result
A local card lives 24h (`local_encounter_store.dart`) while its radio token
rotates ~15 min (`ephemeral_token_generator.dart`, native `aliasTTL`). Treating
a stored token as current made a pass **look** successful when native tore
nothing down.
- `SwipeCard.radioAliasSeenAt` + `radioAliasStateAt()` → `unavailable` (server
  card) / `fresh` / `stale` (seen beyond the alias TTL). Freshness is judged
  against last-seen, NOT the 24h card lifetime.
- `resolvePassTeardown` (pure, unit-tested) never hands a non-radio id to native,
  **awaits** the structured result, and returns an honest `TeardownOutcome`
  (unavailable / stale-miss / native-unavailable / tore). `BeaconService.dropPeer`
  now returns the native `Future<Map?>`; `_doPass` consumes and reports it.
- Tests: `pass_teardown_test.dart` (fresh hit hands the ALIAS not the id; stale →
  miss; server → unavailable, native never called; null native → not a false
  success). Swift `W5TeardownTests` now drives the REAL
  `W5LinkController.dropPeer` and `BackgroundBeacon.dropPeerByToken` (a server
  encounter_id is inert through the actual controller/channel path), not a
  reconstruction of the ownership helper.

### B2 — mandatory event coverage + fault-control path
Declarations were not instrumentation. Added emit sites: `discover`,
`tiebreak(hold|dial)`, `dialStart`, `connectResult(connected|failed|legacy)`,
`dialFail(connectFailed|downPreAck)` (the pending-dial reclamation Case 1 needs),
`propose`/`ack` (send+recv, match/mismatch), `graceExpiry`, `aliasRollSend`
(+recipient count), `prevAliasExpiry` (peer+self), `coldLaunch`
(snapshotPresent|fresh), `snapshotLoad` (loaded|empty|reject + lease/rebind
counts). `commit` now carries the selected role; `dropPeer` carries the closed
roles, not just a count. Two-layer construction: `emit`'s sensitive args are
`@autoclosure`, so a Release build never even evaluates a raw-id expression.
Committed Dart fault-control path: `BeaconService.armW5Fault` →
`BackgroundBeaconChannel.armW5Fault` → native (diag-gated).

### B3 — run/handle continuity across restoration
An OS-spawned CoreBluetooth restoration relaunch does NOT inherit the Xcode
launch environment, so an env-only run secret would rotate at the exact boundary
Case 3 must join across. Fix: the run secret resolves
`env → provisioned(dart-define, persisted) → per-install persisted → generate`,
all in the diag suite (never `standard`). Persisting keeps HMAC handles
continuous across restoration; the diag scheme injects `INRANGE_DIAG_RUN_SECRET`
(Test+Launch) and `build_diag_artifact.sh` bakes/records a fleet secret via
dart-define (wired Dart→native `setDiagRunSecret`) so a fleet built from one
artifact aligns. Cross-device real-device alignment is via that baked secret;
per-install fallback covers restoration continuity. Swift test proves handles use
the injected secret; provisioning persists + validates. Full cross-restoration
continuity is device-only → validated in the one-phone preflight the panel
authorized.

### B4 — one serialized, hardened evidence writer
`W5EvidenceWriter` (diag-only) replaces three ad-hoc writers. A missing file is
created (protected, backup-excluded); an existing file that cannot be opened is
**inaccessible** → the line is dropped, never overwriting it (the Phase-3.3
defect). Protection + backup exclusion reapplied after every create/append/
rotate. Per-family bounded drop counters, summed + reset at boot
(`drainPriorDroppedWrites`). All three families (events, wake, RSSI) route
through it; the wake log no longer carries raw token fragments
(`W5Diag.shortHandle`). Foreign-flavor wipe clears the new keys + persisted run
secrets. Tests: absent→create, inaccessible→drop-not-overwrite, rotation→`.1`,
drain sums+resets.

### B5 — executable CI gate
`ios-build.yml`: `test-ios` now runs BOTH schemes (Runner + diag flavor
assertions) serially + the build-settings check; new `isolation-ios` job runs the
final-binary negative/positive controls; `build-ios` gains
`needs: [test-ios, isolation-ios]` so the release IPA is produced only when both
pass. `check_final_binary_isolation.sh` now ENFORCES the contract, not prints it:
production must have **0** diagnostic symbols (`W5Diag`/`W5EvidenceWriter`) AND
**0** `INRANGE_DIAG_RUN_SECRET` reads; the diag build must have both (positive
control proves the discriminators fire). Contract-allowed channel/wipe-machinery
strings are reported informationally.

### B6 — privacy / evidence hygiene
Device serials/UDIDs removed from the tip across `PHASE0_BASELINE`,
`HW_MATRIX_PROTOCOL`, `HW_MATRIX_REVIEW_REQUEST`, `MAC_EXIT_PACKET`, case
1/2/4 `RESULT.md`, `hw_matrix_pull.sh`; fleet corrected to the owner-confirmed
iPhone 14 / 13 / 15 Plus (slot C noted only as a substitute unit).
`PHASE0_BASELINE` annotated with its known limitations (dirty capture, missing
pre-change outputs, combined Phase 3+4 commit). `PRIVACY_REDACTION_PROPOSAL.md`
stages the history rewrite for owner sign-off — **not executed**, no force-push,
no hazypiff mirror.

## Test evidence at this checkpoint

- `flutter analyze` clean; `flutter test` 263 passed.
- RunnerTests: Runner scheme `TEST SUCCEEDED` (54); diag scheme
  `TEST SUCCEEDED` (61), run serially, 0 failures.
- `check_release_isolation.sh`: pass. `check_final_binary_isolation.sh`:
  production diag-syms=0 / run-secret-env=0; diag diag-syms>0 / run-secret-env>0.

## Still NOT done (panel-gated)

Physical-device install / preflight / three-iPhone matrix rerun (forced Case 1
via the fault hook, real-jetsam Case 3, narrow Case 4), evidence bundle, and the
blinded panel on the post-run SHA. No merge, deploy, fast-forward, mirror, or
device action. Awaiting the next blinded panel review of this exact SHA.
