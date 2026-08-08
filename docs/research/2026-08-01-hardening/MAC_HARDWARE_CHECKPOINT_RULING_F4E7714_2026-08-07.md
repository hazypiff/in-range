# Mac hardware checkpoint ruling — `f4e7714` (2026-08-07)

## Decision

**CONTINUE. `HARDWARE_GATE: HOLD`.**

Checkpoint `f4e77140d185842869b58807d49bb5826da82995` is accepted as a
privacy-clean mid-matrix evidence publication for the signed artifact built from
source `d90801cdffaa8c092fef55f5f5561a6a059b813d`. It does not advance draft
PR #11, merge, deploy, or enable W5.

| Item | Ruling |
|---|---|
| Three-phone preflight | **ACCEPTED** |
| Case 1 pairwise TTL reclamation | **ACCEPTED AS ONE SUBPREDICATE** |
| Case 1 full hardware case | **INCOMPLETE — rerun with slotC introduced during the forced window** |
| Case 2 | **NOT ACCEPTED — the committed stream shows a new lease after the drop** |
| slotC | **Use the connected iPhone 16 Pro Max as slotC for this matrix** |
| Case 3 | **AUTHORIZED under the genuine-jetsam procedure below** |

The current signed artifact remains usable: this ruling is documentation on the
review lane and does not change its source or bytes.

## Case 1 — the TTL proof is valid, but the third-phone predicate remains

The alternate `faultInject(preAckDrop) -> dialFail(downPreAck)` path is **not
required**. The frozen directive permits the selected pending dial to terminate
by an explicit failure **or** the 20-second TTL sweep.

The slotA stream mechanically supports the TTL alternative:

- seq 19 arms the selected peer;
- seq 23–27 create the same attributed link and enter `helloDelay(count=30)`;
- seq 28–29 record `linkDown(ended)` followed by
  `ttlSweep(result=reclaimed)` for that peer/link;
- after disarm, seq 33–45 create a new link to the same peer and reach a clean
  commit;
- neither submitted phone stream contains `reject` or `dialFail`.

That proves forced reclamation and non-wedging. It does **not** close full Case 1,
because the controlling protocol requires slotC to arrive while the selected
A-to-B dial is inside that forced pre-ACK window. The earlier three-phone
preflight is not a substitute.

Run Case 1 once more with slotA as the selected dialer, slotB as its selected
target, and slotC introduced during `helloDelay`. Join the selected peer/link
through pending creation and reclamation, then prove the later clean commit and
one keeper per valid encounter. The pairwise run may remain as supporting
evidence; do not relabel it as the complete Case 1.

## Case 2 — pairwise topology is correct, but this run changes lease identity

Case 2 is intentionally a two-phone case; slotC may remain off. The submitted
facts nevertheless do not prove its same-lease contract:

- Case 1 ends with lease `id:af0b6839b818e7` committed on both slotA and slotB.
- In the Case-2 slotA stream, seq 2–3 record the physical drop and
  `graceEnter` for that same `id:af0b6839b818e7` lease.
- The reconnect then reaches `helloAck`/`commit` as
  `id:4546d131f3d7be` on slotA (seq 11–16) and slotB (seq 3–8).

Agreement on `id:4546d13...` after reconnect proves that both endpoints agreed
on the **new** lease. It does not prove preservation of the pre-drop lease. The
absence of `aliasRollRecv` is useful, but cannot repair that identity change.
The submitted Case-2 files also do not contain the required fresh-artifact
token-cache bypass, retry-floor bypass, and current-message positive control.

Rerun Case 2 on slotA+slotB. Before the drop, capture the exact committed lease
`L` on both phones. Then join, in one case epoch:

1. physical drop of the committed keeper `L`;
2. rotation while the link is down and `aliasRollSend` without a corresponding
   in-window `aliasRollRecv`;
3. reconnect inside 120 seconds with `hello(reason=hasPrev)`;
4. `helloAck` and `commit` on both phones with the exact same pre-drop `L` and
   no second keeper;
5. token-cache bypass and retry-floor bypass;
6. a current-message positive control.

If the post-reconnect lease differs from `L`, record Case 2 as FAIL and diagnose
the lease remint; do not call cross-phone agreement “same-lease preservation.”

## slotC ruling

For the `d90801c` matrix, the physically connected iPhone 16 Pro Max is the
approved slotC substitute. The older iPhone 15 Plus rows are stale fleet
metadata for this run. Preserve history and correct this forward in the final
manifest. Keep filenames and joined evidence role-labelled `slotA`, `slotB`, and
`slotC`; record only model and OS version in the value-free manifest.

## Case 3 — preferred genuine-jetsam procedure

Do not change the InRange source or add an InRange memory-hog control; that would
invalidate the reviewed artifact. There is no public, Apple-supported host
command that deterministically jetsams an arbitrary app on a physical iPhone.
Xcode's simulated memory warning is a Simulator warning, not a physical-device
jetsam.

Use real system pressure on the suspended diagnostic app:

1. Save/close unrelated work on the test phone. Establish a committed slotA↔slotB
   keeper, record the exact lease/handles and cutoff time, and detach any
   debugger.
2. Send the victim app to the background normally. Do **not** swipe it away,
   stop it from Xcode, use `devicectl` to kill it, crash it, or reboot.
3. Generate foreground memory pressure on that phone. A separate temporary
   pressure-generator app is the most repeatable option because it leaves the
   frozen InRange artifact unchanged; a manual high-memory app workload is
   acceptable but less deterministic. Continue only until iOS evicts the
   suspended InRange process.
4. Retrieve the newly timestamped `JetsamEvent` from the device's Analytics Data
   or Xcode's device logs. The attempt counts only if the InRange/`Runner`
   process entry itself has the report's `reason` field. `largestProcess`, a
   reason attached to another process, a memory warning, or process absence by
   itself is not proof.
5. Keep the raw report only in protected scratch storage. Commit only a minimal
   sanitized derivative containing the event time, target process identity,
   suspended/background state, and exact jetsam reason; remove device IDs,
   incident IDs, unrelated process inventory, and other machine-local values.
6. Without manually opening InRange, use the peer's BLE activity to cause the
   CoreBluetooth relaunch. Join the jetsam time to a new launch epoch and prove
   actual `willRestoreState`, central/peripheral restoration, D1
   `key-unconfirmed` deferral followed by provision-time re-drive, notify rebind,
   both subscriptions, the same lease/keeper, and resumed traffic.
7. In the same acceptance packet, prove stale-generation rejection and then a
   current-generation positive control.

Apple documents that a jetsam report describes the low-memory termination and
that only the jettisoned process carries the `reason` key. It also documents the
on-device `JetsamEvent_<DateTime>` retrieval path:

- <https://developer.apple.com/documentation/xcode/identifying-high-memory-use-with-jetsam-event-reports>
- <https://developer.apple.com/documentation/xcode/acquiring-crash-reports-and-diagnostic-logs>
- <https://developer.apple.com/documentation/uikit/responding-to-memory-warnings>

If bounded pressure attempts do not produce a report whose target process owns
the reason, stop calling the attempt Case 3. Do not substitute a developer kill
or reboot; preserve the completed work and report the precise physical jetsam
blocker.

## Required continuation order

1. Correct the Case-2 claim forward; do not rewrite `f4e7714`.
2. Rerun full three-phone Case 1 with slotC introduced during the forced window.
3. Rerun pairwise Case 2 with the exact before/after lease and all bypass/control
   facts joined.
4. Execute Case 3 under the genuine-jetsam procedure and then the frozen narrow
   Case 4.
5. Pull, sanitize, mechanically validate, and commit the complete three-device
   evidence tuple; run the final blinded panel.

Until those predicates pass, `HARDWARE_GATE` remains **HOLD** and draft PR #11
remains frozen at `c816f09`.
