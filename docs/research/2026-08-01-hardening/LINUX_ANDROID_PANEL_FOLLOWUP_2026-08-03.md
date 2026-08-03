# Linux/Android panel follow-up — 2026-08-03

This is an evidence correction and handoff for draft PR
[#11](https://github.com/inrangeai/in-range/pull/11). It was prepared on Linux
after independent read-only reviews by headless Claude and Kimi, direct code
tracing, CI inspection, and tests on the available Android fleet.

No merge, deployment, PR-head rewrite, or production mutation was performed.
No device serial, raw peer token, credential, run secret, or unsanitized device
log is included in this document.

## 1. Executive verdict

- **PR #11 release isolation:** no new evidence shows W5 entering a production
  build. The branch remains a clean draft with all current GitHub checks green,
  and W5 is compile-disabled outside `INRANGE_DIAG`. That makes the integration
  merge decision separable from W5 release enablement.
- **W5 release enablement:** **NOT APPROVED.** The current evidence cannot prove
  hardware cases 1–3, Case 4 has an identifier/semantics defect, and the
  diagnostic harness needs privacy, attribution, persistence, and CI repairs.
- **Prior hardware claim correction:** none of the four iPhone cases is proven
  by committed, attributable evidence. In particular, the statement that Case
  4 is proven is withdrawn.
- **Android contribution:** the exact PR-tip app passes analysis, Dart tests,
  Android unit tests, install/runtime checks, and a real BLE
  advertise/scan/foreground-service smoke test. Android has no W5/CA5E lease
  implementation, so these results cannot validate the native iOS election,
  restoration, grace, or teardown behavior.
- **Newly confirmed integration gap:** `SwipeCard.id` is not uniformly a W5
  token alias. A server card sends `encounter_id` to native `dropPeer`, whose
  lookup is alias-keyed, so teardown is normally a no-op. A local card sends a
  token alias and can tear down the current lease, but no durable native veto
  survives teardown; a later discovery can mint a new lease. Therefore
  “rejection prevents redial” is not a well-defined or implemented invariant.

## 2. Exact review target and current remote state

| Item | Value |
|---|---|
| Repository | `inrangeai/in-range` |
| Draft PR | `#11` |
| PR head branch | `integ/mac-hardening-2026-08-01` |
| PR base branch | `fix/w5-encounter-lease` |
| PR tip reviewed | `53ed423ede6eda472e00ce7339d7c050ff9d4930` |
| Code SHA immediately below tip docs | `98279de40ec04b40e76a8acc016ca5e9d6566f78` |
| Review branch | `docs/android-panel-assist-2026-08-03` |
| PR state at recheck | open draft; merge state `CLEAN` |
| GitHub checks at recheck | all six reported checks green |

The delta from `98279de` to `53ed423` consists only of
`MAC_EVIDENCE_PACKET.md` and `MAC_EXIT_PACKET.md`. This means `98279de` is the
exact code reviewed while `53ed423` is the exact branch tip and documentation
state reviewed. PR #11 itself is a stacked code-and-doc integration relative to
its feature-branch base; “docs-only” applies only to those last two SHAs.

Current checks reported green for two `analyze + test` runs, two Android unit
test runs, `test-ios`, and `build-ios`. A green check is recorded as evidence,
not treated as proof of paths that the workflow does not execute.

## 3. How the two-reviewer panel was used

Claude and Kimi were given the same exact SHA and source ranges, asked to review
read-only, and required to distinguish facts, inference, and unverified device
behavior. Their initial conclusions were compared only after independent
passes. Each reviewer then received the other review's strongest counterexample
and had to accept, rebut, or narrow it with source evidence.

The reconciliation materially changed the result:

- Kimi withdrew its initial endorsement of the short two-phone rejection test
  after tracing the five-minute retry floor and token tiebreak.
- Claude narrowed its locked-file “truncation” claim from definite to plausible:
  locked reopen most likely loses a sample, while an unrelated first-write
  fallback can replace an existing file after an open failure.
- Both rejected raw or per-launch-only token prefixes for multi-phone evidence.
  The accepted design uses an ephemeral shared run secret and HMAC-derived
  handles so devices can be joined without committing raw identifiers.
- Both agreed user force-quit is the wrong restoration stimulus. Apple documents
  that an app force-quit by the user is not relaunched for Bluetooth state
  restoration.
- Direct code tracing after the panel found that Case 4 also crosses incompatible
  identifiers and has no durable rejection ledger. Both reviewers independently
  confirmed those two code facts from the exact ranges. What the unpushed Mac
  run exercised remains unresolved until its exact code and artifacts are
  available: a local-card run can prove current-lease teardown, while a
  server-card run normally exercises the silent identifier-miss path.

This is a useful panel pattern: independent evidence first, explicit
disagreement ledger second, and separate verdicts for “safe to merge while
disabled” versus “safe to enable.” A vote count by itself would not be enough.

## 4. Findings that change the hardware plan

### 4.1 H-W5-6 is narrower than the packet says

The relevant path is:

1. `SwipeCard.id` is documented as a server `encounter_id` or local
   correlation ID (`lib/features/encounters/swipe_card.dart:24-25`).
2. Server cards construct it from `row['encounter_id']`; local cards use
   `LocalEncounter.correlationId`, which is the observed 32-hex token
   (`swipe_card.dart:85-133`, `beacon_service.dart:2041-2050,2179-2222`).
3. `_doPass` always calls `dropPeer(c.id)`
   (`lib/features/encounters/swipe_feed.dart:105-120`).
4. Native `dropPeerByToken` and `W5LinkController.dropPeer(alias:)` resolve only
   by token/alias (`BackgroundBeacon.swift:1357-1364`,
   `W5LinkController.swift:401-419`).

Consequences:

- A server-backed card normally supplies an encounter ID, not the token alias
  required by the native lookup. The immediate radio teardown is therefore a
  likely no-op.
- A local card can supply the right current alias. `onTeardown` closes live
  links and erases the lease (`W5Ownership.swift:636-640`). That proves current
  lease teardown only.
- After teardown, `onDiscovered` has no rejection ledger to consult and creates
  a new encounter when no lease exists (`W5Ownership.swift:383-413`). The
  separate `lastConnectAttempt` map suppresses attempts for five minutes, but
  is not a durable rejection rule (`BackgroundBeacon.swift:81-82,1049-1065`).
- Source comments explicitly call W5 session state “never a permanent ledger,”
  and the Dart swipe comment says the next natural contact may re-establish.
  Other comments and the matrix instead say the app cannot redial a dismissed
  user. Those contracts conflict.

The packet's `H-W5-6: FIXED` claim must be narrowed to **“current alias/lease
teardown implemented; product identifier plumbing, evidence, and redial horizon
unresolved.”** It must not be used as proof that a rejected person cannot be
redialed.

### 4.2 The four iPhone cases are not yet proven

| Case | Honest status | Why | Required proof |
|---|---|---|---|
| 1. Three peers / third peer during dial | **Unproven**; a clean convergence run is only a scoped smoke pass | Normal timing need not hit the connect-to-`HELLO_ACK` race fixed by H-W5-3; current wake lines do not identify the peer/lease | A diag-only deterministic pre-ACK stall, explicit pending-dial creation/expiry, and successful later commit on a fresh peer |
| 2. Keeper drop + token rotation + reconnect inside 120 s | **Unproven** | Current logs cannot independently establish drop, rotation before reconnect, lost/suppressed `ALIAS_ROLL`, and reuse of the same lease | All four events attributed to the same HMAC peer/lease handles and ordered by monotonic timestamps |
| 3. Restoration + committed lease + stale generation | **Unproven** | No unconditional restoration-entry marker; user force-quit prevents the relaunch being tested; a cold launch is not restoration | System memory removal/jetsam or a controlled diag crash while suspended, `willRestoreState` entry/result markers, restored-object counts, characteristic rebind evidence, and stale-gen rejection |
| 4. Rejection prevents redial | **Withdrawn / contract unresolved** | A server card passes the wrong identifier; a local teardown has no durable veto; a short no-redial window is explained by the five-minute retry floor and token tiebreak | First decide the intended horizon and identity. Then prove immediate teardown separately for local and server-backed cards, include a positive dial control, and test beyond every incidental suppression window only if durable no-redial is the chosen product rule |

For Case 1, silence after a forced stall is not a pass. The harness must show
the stale pending dial was reclaimed and then show a subsequent valid peer can
commit. For Case 4, a third phone or role reversal is needed to demonstrate
that the observer can detect a dial at all; otherwise “no dial” can simply mean
the tested phone lost the token ordering tiebreak.

### 4.3 Current wake logging cannot support cases 1–3

`logWake(_ kind: String)` compiles its body only under `INRANGE_DIAG`, but Swift
evaluates a normal `String` argument before entering the function. Adding
interpolated token/lease data to its call sites would therefore still evaluate
that sensitive expression in a production build even though no line is written.

Use both layers of defense:

1. change the logging API to an `@autoclosure` or a compile-gated structured
   helper so unused diagnostic payloads are lazy; and
2. place every call that constructs a sensitive event behind
   `#if INRANGE_DIAG` (or inside a helper whose entire implementation and call
   payload are compiled only for diag).

Then prove the contract with a release-binary negative check and a diag-binary
positive control. A source grep alone is insufficient.

The event schema needs at least:

- schema version, `runId`, boot/launch epoch;
- wall-clock and monotonic timestamps;
- event, role, result/reason;
- HMAC-derived peer, lease, link, and peripheral handles where applicable;
- explicit entries for dial decision, dial start/failure, `HELLO`,
  `HELLO_ACK`, pending-dial creation/sweep, link down, grace enter/bypass/expiry,
  alias roll send/receive, owns/ended, `dropPeer` input class and lookup result,
  central/peripheral `willRestoreState` entry, and rebind result.

Do not use raw prefixes. Generate one random shared secret for the hardware run,
inject it into all three diag iOS builds through a diag-only Swift-visible
configuration, and compute truncated HMAC-SHA256 handles (12–16 hex is enough
for this bounded test). The secret must never be persisted, logged, or
committed. A Dart `--dart-define` does not automatically make the value visible
to native Swift; the Mac agent must wire the diag xcconfig/Info.plist or another
compile-gated native test channel explicitly.

### 4.4 The evidence storage claims are too strong

- `bb_wake_log.txt` is created in Documents without a file-protection option or
  backup exclusion (`BackgroundBeacon.swift:732-765`). The packet's blanket
  “backup-excluded/file-protected log writes” statement is false for this file.
- `w5_rssi_log.jsonl` contains plaintext raw tokens
  (`W5LinkController.swift:805-812`). It is W5/diag-only in normal control flow,
  but is still sensitive test data and must be sanitized before committing.
- Its first-write fallback uses `.completeFileProtectionUnlessOpen`, then closes
  the file after every append. Under lock, reopening a closed protected file can
  fail, which can silently lose samples. Apple documents that a file with this
  protection remains accessible while held open, but cannot be reopened while
  locked.
- The generic `FileHandle(forWritingTo:)` failure path treats every failure like
  “first write” and writes `data` to the existing URL. When the file is
  accessible but opening fails for another transient reason, that replacement
  path can truncate prior data. The locked path is more likely to fail the
  fallback too and lose a sample; truncation while locked is not claimed as
  proven.
- Rotation writes do not reapply protection/backup metadata to every new file.

Before the matrix, run a one-phone integrity test: write at least 100 numbered
events, lock and background through a scheduled write window, unlock and pull,
verify monotonically increasing sequence/line counts, and force cap/rotation.
The selected protection class must match the purpose of a locked-state
diagnostic log; document the privacy-versus-availability choice.

Apple references:

- [Bluetooth state-restoration app relaunch rules (TN3115)](https://developer.apple.com/documentation/technotes/tn3115-bluetooth-state-restoration-app-relaunch-rules)
- [`centralManager(_:willRestoreState:)`](https://developer.apple.com/documentation/corebluetooth/cbcentralmanagerdelegate/centralmanager%28_%3Awillrestorestate%3A%29)
- [`NSFileProtectionCompleteUnlessOpen`](https://developer.apple.com/documentation/foundation/fileprotectiontype/completeunlessopen)
- [`isExcludedFromBackup`](https://developer.apple.com/documentation/foundation/urlresourcevalues/isexcludedfrombackup)
- [Optimizing app data for iCloud backup](https://developer.apple.com/documentation/foundation/optimizing-your-app-s-data-for-icloud-backup)

### 4.5 Flavor wipe and CI do not cover the claimed state

- The cross-flavor wipe removes `bb.w5rssi.off` but omits the persisted
  `bb.w5.snapshot` payload and the RSSI file itself
  (`BackgroundBeacon.swift:144-165`; snapshot key written at
  `W5LinkController.swift:627-652`). Resetting only the offset can redrain old
  plaintext token history after a flavor change.
- `ReleaseIsolationTests` hard-codes production assertions. The diag scheme now
  includes the same test bundle under `Debug-diag`; four of its five tests
  contain production-only expectations, so “the same bundle proves the diag
  suffix path” is not an executable positive-control design.
- CI runs `Runner`/`Debug` tests only. It does not execute the diag scheme. The
  build-settings script is useful and fail-closed for flag queries, but it does
  not prove that sensitive strings or diagnostic behavior are absent from the
  final binary.
- `build-ios` has no dependency on `test-ios`; a release artifact can be produced
  independently of test success.

The Mac work order addresses these as evidence/enablement blockers. They are not
evidence that W5 is live in the current production release.

## 5. Linux and Android evidence

### 5.1 Static and host-side results

All commands were run from the isolated review worktree at `53ed423` before this
docs-only handoff:

| Check | Result |
|---|---|
| `flutter analyze` | PASS; no issues |
| `flutter test` | PASS; 249/249 |
| Gradle `:app:testDebugUnitTest` | PASS; `BUILD SUCCESSFUL` |
| Current PR checks | PASS; six checks green |

### 5.2 Exact Android artifact

The configured multi-ABI debug APK used the repository's local `.env` defines
without recording their values.

| Property | Value |
|---|---|
| Package | `io.inrange.app` |
| Version | `0.1.0-53ed423` |
| min / target / compile SDK | 24 / 36 / 36 |
| APK SHA-256 | `d23cb6e45e2ca9e45dcc9ccef288846631933a0e78f0fb290ebf70b8caf35b74` |

### 5.3 Device handling and runtime result

Three authorized Samsung Galaxy S9 devices on Android 10/API 29 were visible
after reconnection. They are referred to only as A, B, and C:

- A and C are test-eligible. The exact APK above was already installed on both;
  both still reported the exact version, Bluetooth ON, USB power, 100% battery,
  and a live app process at the final recheck.
- B is repository-designated as protected by multiple device scripts. It was
  kept strictly read-only: no install, launch, force-stop, input, settings
  change, or app-data change was performed.
- One additional unauthorized USB entry appeared at the final enumeration. It
  was excluded and untouched.

Observed runtime behavior on A:

- The configured app launched without a fatal crash.
- Beacon ON started a Bluetooth scan, BLE advertising, and the foreground
  service/notification.
- The UI truthfully reported local BLE operation because the cloud claim did not
  sync for that local session.
- After 15 seconds backgrounded, the process and two service records remained
  alive. This proves process/service survival over that interval, not continuous
  advertising for every instant of it.
- Returning to foreground exposed the Beacon Off control; shutdown completed and
  the UI reported Beacon OFF.

C was at the authentication surface, so it could not serve as a second in-app
peer without changing account state. One earlier cold launch emitted a single
Riverpod “cannot use ref functions after dependency changed before provider
rebuilt” RSSI-flush retry warning. A clean-log second cold launch did not
reproduce it and no crash followed. It is recorded as a nonreproduced Android
observation, not a W5 blocker.

### 5.4 What the Androids can and cannot prove

Android can support:

- configured build/install/runtime regressions;
- permission and foreground-service lifecycle checks;
- BLE advertising/scanning smoke tests;
- passive observation of iOS advert/token timing;
- the B1 negative control that Android manufacturer-data adverts never enter an
  iOS GATT/W5 connect path.

Android cannot prove:

- iOS CA5E GATT control/keepalive behavior;
- W5 election, ownership lease, contender, or `HELLO_ACK` behavior;
- CoreBluetooth state restoration;
- iOS grace-window discovery bypass;
- multi-iPhone teardown/redial semantics.

No Android result should be counted as a substitute vote for an iOS hardware
case.

## 6. Merge and enablement gates

### Gate A — PR #11 integration while W5 is disabled

The current code remains compile-gated off in non-diag builds and all reported
checks are green. The owner may evaluate merging the stacked integration into
its feature base independently of the hardware matrix. Before treating its
documentation as a sign-off, correct or explicitly supersede these claims:

- H-W5-2 “HW-verified”;
- Case 4 “proven”;
- H-W5-6 “rejection prevents redial”;
- the blanket file-protected/backup-excluded logging claim;
- the claim that the current diag test bundle provides a runtime positive
  control.

This report is the erratum; it does not rewrite the signed exit packet in place.

### Gate B — enabling W5 in a release

Blocked until all of the following are complete:

1. Decide and implement the Case 4 identity/horizon contract.
2. Add compile-safe, privacy-preserving, attributable diag events.
3. Fix or explicitly retire the flavor-wipe, snapshot, log-protection,
   append-integrity, and backup-isolation gaps.
4. Make release/diag isolation tests flavor-aware and execute both flavors in
   CI with final-binary negative and positive controls.
5. Pass the one-phone logging integrity preflight.
6. Re-run all four iPhone cases with committed, sanitized, attributable
   artifacts and explicit positive controls.
7. Have the Mac panel review the exact tested SHA and artifact manifest, not a
   later untested tip.

The separate work order in
`MAC_HARDWARE_PANEL_WORK_ORDER_2026-08-03.md` is the executable handoff.

## 7. Subsequent four-case hardware claim — not yet remotely auditable

At 13:46 EDT on 2026-08-03, the Mac side reported all four cases as passed,
named a new diagnostic instrumentation commit `f989231`, and said sanitized,
attributed evidence had been committed locally. The claim also reported a
field observation of `state-stamp-adopted-legacy`.

That report is useful new information, but it does not yet change the evidence
verdict. After fetching both remotes and querying GitHub:

- `f989231` was absent from the local object database and both GitHub
  repositories;
- both remote `integ/mac-hardening-2026-08-01` refs still resolved to
  `53ed423ede6eda472e00ce7339d7c050ff9d4930`;
- PR #11 still resolved to `53ed423` and exposed no hardware-evidence commits.

The final panel must audit the pushed exact tip and resolve these case-specific
questions:

1. **Case 1:** “zero TTL sweeps” is not itself proof of H-W5-3. The evidence
   must show a pending dial was created, the pre-`HELLO_ACK` failure/reject path
   actually reclaimed it (for example through `onDialFailed`), and a later
   fresh dial could commit. A four-second delay followed by normal success only
   widens timing; it does not exercise the leak.
2. **Case 2:** a Kimi judgment and committed vector are useful corroboration,
   not hardware evidence. The sanitized event chain must independently prove
   drop, rotation before reconnect, inability to deliver `ALIAS_ROLL`, and the
   same lease handle rejoined inside 120 seconds.
3. **Case 3:** the evidence must show a genuine `willRestoreState` relaunch
   epoch, restored objects and both notify-character rebinds before successful
   recommit. It must also state the termination method and rule out user
   force-quit/cold-launch reconstruction.
4. **Case 4:** “lease erased” can prove the narrow current-alias teardown
   contract. “No redial in two-phone isolation” still cannot prove a durable
   veto without resolving server-card identifier mismatch, token tiebreak, the
   five-minute retry floor, test horizon, and the source's explicit
   non-permanent-ledger contract.
5. **H-DIAG-3:** `state-stamp-adopted-legacy` proves the nil-stamp adoption
   branch ran. It does not prove a known diag-to-production foreign stamp wipes
   the W5 snapshot and physical log files.

Required next sequence: push the exact instrumentation/evidence commits, publish
their artifact manifest, fetch this erratum, run independent reviewers against
that exact SHA, reconcile disagreements, and only then update the exit packet.

## 8. Evidence hygiene

- Raw Android logs remain local and uncommitted.
- No raw iOS token, peripheral UUID, device serial, access token, JWT, run
  secret, location, or account identifier belongs in Git.
- Sanitized hardware evidence must retain event ordering and joinability through
  run-scoped HMAC handles; redaction must not destroy the assertions being made.
- Every final claim must name the exact code SHA, build configuration, app
  artifact hash, device role, and artifact path that supports it.
