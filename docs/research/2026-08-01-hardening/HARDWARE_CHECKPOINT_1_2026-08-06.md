# Hardware checkpoint 1 — two-phone provisional evidence (2026-08-06)

**PROVISIONAL. NOT `MATRIX_READY`, NOT final PASS.** Per
`MAC_HARDWARE_CHECKPOINT_RULING_2026-08-06.md` (`c20dbb8`), two-phone on-device
observations are provisional until each case's complete joined sanitized fact
chain is proven. This bundle publishes tonight's slotA+slotB evidence so it can
be audited; it does not claim the cases are proven. Case 1 and the closing of
the Case-2/3/4 fact gaps are the next session's work.

## Source + artifact binding

- source SHA under test: `c4ecb01` (fix/w5-convergence-2026-08-04).
- **byte-identical app source**: `git diff b9993fc c4ecb01 -- ios lib pubspec.yaml
  pubspec.lock` is EMPTY. The only delta b9993fc..c4ecb01 is the evidence puller
  (`hw_matrix_pull.sh` + its test). So the installed artifact — built at `b9993fc`
  — has byte-identical executable app source/config to `c4ecb01`; no reinstall.
- signed diagnostic artifact (`build/ios/iphoneos/Runner.app`):
  - bundle id: `io.inrange.inRange.diag`
  - SHA-256(Runner): `990ae561169fcc93d0c227c36c19005ae09ac9f34f6c645be43e965dc2b8ec2f`
  - signing identity: Apple Development (team `JHK29L6A78`, cert fingerprint `JLS673GYCJ`)
  - Mach-O inventory: Runner ; Frameworks/Flutter.framework/Flutter ;
    Frameworks/App.framework/App ; Frameworks/flutter_background_service_ios.framework/…
  - diag positive control on the SIGNED artifact: diag-syms(Runner)=246 (>0).
- fleet (models only, no device identifiers): iPhone 14 = slotA ; iPhone 13 = slotB ;
  both iOS 18.6.2, developer mode enabled. slotC (iPhone 15 Plus) NOT cabled.
- fleet-key fingerprint (sha256[:12], NOT the value): shared run secret provisioned
  via `--dart-define` (Dart-provision path), NOT as a native boot env authority.

## Per-case status vs the ruling's required fact chains

### Preflight — observed, artifact binding above
Signed build installed on both phones, ran, and formed a real BLE lease
(discover → propose/ack → tiebreak → dialStart → connectResult → hello →
helloAck → **commit**). Evidence: `hardware_evidence/preflight/`.

### Case 2 — PROVISIONAL (not all 7 facts joined)
Observed on slotA: `graceBypass(reason=retryFloor)` [fact 6], fast reconnect
(~2 s), single keeper. NOT yet proven on joined handles: committed keeper drop [1],
token rotation before reconnect [2], ALIAS_ROLL could-not-traverse [3], SAME-lease
recommit <120 s [4] (a NEW lease id formed on the toggle — needs a fault-injected
run that suppresses ALIAS_ROLL to show same-lease resume), token-cache bypass [5],
current-message positive control [7]. Evidence: `hardware_evidence/case2/`.

### Case 3 — PROVISIONAL; genuine-jetsam termination reason MISSING
Observed on slotA: real CoreBluetooth restoration (`restorePeriph`,
`restoreCentral`), `snapshotLoad(reason=key-unconfirmed)` → deferred → re-drive
(D1 path; boot authority was NOT the env key) → `snapshotLoad(reason=rebind=0)` →
`dialStart(tokenRead)` → `hello` → `helloAck` (a helloAck proves a delivered
notify — notify rebind resumed; no wedge). **GAP**: the termination was a device
**reboot**, which yields a cold launch + CB restoration but is NOT a proven OS
memory-pressure **jetsam**. The ruling requires a sanitized system termination
reason proving genuine jetsam, plus stale-generation rejection [6] and a
current-generation positive control [7]. Those are not in this bundle. Evidence:
`hardware_evidence/case3/`.

### Case 4 — NOT mechanically proven (silence only)
Observed: reject via ✕ fires `dropPeer(reason=passOutcome)` per card; active lease
`linkDown`; rejected person did not reappear as an encounter; and in a clean run
(no restart) ZERO re-dial/re-commit to the rejected peer over 90 s with the app
confirmed still running. **This proves SILENCE, not the required chain**: no
attributed post-reject rediscovery of the rejected peer while the scanner is
demonstrably live [4], no explicit sanitized suppression reason [5], and no
same-run unswiped-peer positive control [6]. Closing Case 4 needs those facts and
likely the smallest compile-gated structured events to emit them. The redial
observed AFTER a full radio restart is consistent with the ratified narrow
contract (pass tears down the mapped lease; not a durable identity veto) — tracked
separately, NOT a Case-4 blocker. Evidence: `hardware_evidence/case4/`.

### Case 1 — PHYSICAL_ACTION_REQUIRED (slotC)
Not run. Needs the third owner-confirmed iPhone (15 Plus) + the same frozen
artifact.

## Findings preserved for panel triage (NOT self-labeled non-blocking)
- The single iPhone 13 surfaced as ~7 encounter cards; the 7 `dropPeer` handles
  correspond to B's rotated radio aliases across the evening — evidence suggests
  ONE peer shown multiple times (possible duplicate-identity/UI defect). Final
  panel to classify one-peer-vs-distinct-encounters.
- Deferred "Always location" prompt: with only "While Using," the backgrounded
  radio was throttled and the post-relaunch session stayed idle until Always was
  granted. Exact permission-state contract to be recorded in the follow-up ledger.

## Honest terminal state
`PHYSICAL_ACTION_REQUIRED` — the single blocking action is cable/unlock/trust the
third phone (slotC). No merge/deploy/force-push/history-rewrite/device-erase/W5
enablement performed; draft PR #11 remains frozen at `c816f09`.
