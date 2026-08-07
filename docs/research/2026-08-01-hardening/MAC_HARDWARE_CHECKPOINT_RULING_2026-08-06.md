# Mac hardware checkpoint ruling — two-phone observations are provisional

This ruling supplements `MAC_FINAL_COMPLETION_DIRECTIVE_2026-08-05.md` and
`MAC_CONTINUATION_RULING_B5939CD_2026-08-06.md`.

## Pinned state

- Authoritative implementation ref on `inrangeai`:
  `fix/w5-convergence-2026-08-04` =
  `b9993fcd397bcf4dbf77d4065828adc4b043b740`.
- Authoritative docs ref on `inrangeai`:
  `docs/android-panel-assist-2026-08-03` =
  `826702f873853c7d4a1d5f51555b63943f294256`.
- Draft PR #11 remains at `c816f09df433bb9d3c80ad222ae2d88a63b8ed10`.
- The reported hardware-exposed puller fix `c4ecb01` and tonight's hardware
  evidence are not present on either fetched remote and cannot yet be audited.
- The `hazypiff` convergence mirror remains at `b5939cd`; it does not yet carry
  the A.1/scanner line or the reported puller fix.
- Exact-`b9993fc` iOS run `31128251903` acquired no runner and completed with
  zero-step cancellations. It is not a test result.

## Scanner/A.1 disposition

`b9993fc` is independently corroborated as the current tooling candidate. A
Linux clean worktree reproduced:

- all 12 privacy-scanner adversarial fixtures;
- whole-tip `PRIVACY SCAN CLEAN`;
- all sanitizer fixtures;
- all 11 exact/native-log assertion-gate fixtures;
- all 54 puller fixtures;
- `bash -n` and `git diff --check` clean.

Do not reopen those predicates absent a deterministic regression. Any later
puller/scanner change, including `c4ecb01`, must be pushed, receive its focused
red/green test, and be reviewed on its exact SHA.

## Hardware disposition

The on-device observations are valuable, but they are **provisional** until the
sanitized evidence tree, validator outputs, artifact binding, and source commit
are pushed. Do not label the current state `MATRIX_READY` or final PASS from the
narrative alone.

### Preflight

Provisionally observed: the signed diagnostic build installed, ran, and formed
a real BLE lease. Final acceptance still requires the signed artifact hash,
source SHA, signing identity/fingerprint, whole-bundle inspection, and preflight
validator output in the evidence bundle.

### Case 2 — provisional pending full fact chain

`graceBypass`, a short reconnect, and one keeper are not the complete predicate.
The committed evidence must independently join and prove:

1. committed keeper drop;
2. token rotation before reconnect;
3. `ALIAS_ROLL` could not traverse the dropped link;
4. same-lease recommit inside 120 seconds;
5. token-cache bypass;
6. retry-floor bypass; and
7. a current-message positive control.

If tonight's sanitized events already prove all seven on joined handles, no
rerun is needed. Otherwise supplement or rerun only the missing facts.

### Case 3 — provisional pending genuine-jetsam proof

“Real CoreBluetooth restoration” is necessary but not sufficient. The bundle
must contain a sanitized system termination reason proving genuine OS
memory-pressure/jetsam—not app-switcher force quit, `devicectl` kill, controlled
crash, or cold launch—and join the new launch epoch to:

1. actual `willRestoreState` entry for central and peripheral managers;
2. D1 refusal followed by the real Dart-provision re-drive path, using a device
   artifact/scheme without `INRANGE_DIAG_RUN_SECRET` as the boot authority;
3. control/keepalive characteristic recovery and both re-subscriptions;
4. accepted current snapshot/schema and the same valid lease/keeper;
5. resumed traffic;
6. stale-generation rejection; and
7. a current-generation positive control.

Do not infer jetsam merely from CoreBluetooth restoration callbacks.

### Case 4 — not yet mechanically proven by the described trace

A running app plus 90 seconds of **zero events** proves neither that scanning
continued nor that the rejected peer produced a post-reject discovery. Physical
proximity is not an attributed discovery event. Therefore the described trace
does not yet prove “no dial on the next discovery.”

Close Case 4 with one joined, same-run chain that proves:

1. trustworthy alias freshness and a committed matching lease;
2. native lookup hit and structured teardown result;
3. applicable inbound/outbound/raw roles closed, raw sessions reaped, physical
   link ended, ownership lease erased, and durable evidence acknowledged;
4. an attributed **post-reject rediscovery** of the rejected peer while the
   scanner is demonstrably live;
5. no dial/recommit for that peer after the proven rediscovery, preferably an
   explicit sanitized suppression reason rather than timestamp-only silence;
6. an unswiped-peer positive control in the same run showing discovery/dial
   instrumentation remains live; and
7. an idempotent repeat plus the required inbound-only, outbound-only, and
   two-role topology coverage.

If the existing diagnostic layer cannot emit facts 4–6, add the smallest
compile-gated structured event needed, rerun affected code/artifact gates, and
repeat Case 4. Do not promote silence to proof.

The observed redial after a full radio restart is consistent with the already
ratified narrow contract: pass tears down the currently mapped lease and is not
a durable identity veto. Track it separately; it is not a Case-4 blocker unless
the product contract is changed.

### Case 1 — physical action required

Case 1 still requires `slotC`, the third owner-confirmed test iPhone, and the
same frozen diagnostic artifact. Run the installed selected-peer fault during
the real pre-ACK window, prove pending-dial creation and explicit reclamation,
then prove disarm and a later clean commit with no leak and one keeper.

## Findings that still require triage

- “One phone showing approximately seven encounter cards” may indicate a real
  duplicate-identity/UI defect. Preserve sanitized reproduction facts and have
  the final panel classify it; do not self-label it non-blocking without showing
  whether the cards map to one peer or distinct legitimate encounters.
- The deferred “Always location” prompt may be out of this W5 gate, but record
  the exact permission state and expected product contract in the follow-up
  ledger.

## Consolidated next session

1. Cable/unlock/trust the third phone as `slotC`; disclose no device identifier.
2. Freeze and push `c4ecb01` or its successor with its red/green puller fixture,
   exact manifest, and proof that executable app source/config remains
   byte-identical to the installed artifact source. If it is not byte-identical,
   rebuild/reinstall and invalidate prior device evidence.
3. Close any missing Case-2/3 predicates and the Case-4 rediscovery/positive-
   control gap.
4. Execute Case 1 with the same frozen artifact.
5. Sanitize and mechanically validate the complete preflight/Cases-1–4 tree;
   commit it on the non-force convergence line and publish the exact artifact,
   source, and final evidence hashes.
6. Mirror the final candidate to `hazypiff`, then run the final exact-SHA iOS
   workflow there if `inrangeai` still cannot acquire a runner. Record the
   actual result; do not repeatedly dispatch the same SHA.
7. Run the final blinded Kimi 3 + GPT Sol + Opus/authorized substitute panel on
   one identical source/evidence/artifact tuple. Repair real findings in-round.
8. Only after clean signatures, non-force advance the draft PR #11 head and
   update its body. Do not merge, deploy, enable W5, force-push, rewrite history,
   or erase a device.

Until `slotC` is available, the honest terminal state is
`PHYSICAL_ACTION_REQUIRED` with that single cable/unlock/trust action—not
“everything complete” and not another owner decision about whether to test.
