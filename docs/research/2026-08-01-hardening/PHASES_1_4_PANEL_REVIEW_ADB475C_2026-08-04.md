# Phase 1–4 Round-4 exact-SHA panel review of `adb475c` — 2026-08-04

## Decision

**HOLD.** Commit `adb475c47042f76948ef111fe31d2a762388137a` is not
ready for the one-phone log-integrity preflight or the three-iPhone Phase-5
matrix. Do not install this build, advance PR #11, stack this branch into PR
#11, merge, deploy, mirror the implementation branch, rewrite history, or begin
hardware evidence collection.

Round 4 contains real improvements. The server-ID/radio-alias split remains
sound; a committed lease now reaches the real native `dropPeerByToken` boundary;
the HELLO delay is no longer always on; the event writer has a genuine
concurrency test; the common Dart configuration switch no longer retains the
diagnostic key label; recursive Mach-O discovery exists; the scheme and build
logs no longer carry a fleet-secret value; the tracked field-test DBs and known
device identifiers are sanitized at the tip.

Those improvements do not close the controlling contracts. The B5 production
negative is tautological because it never supplies the known value it claims to
prove was folded out. Reset can erase the only native copy of the fleet key and
then change keys inside one evidence file. The installed app still cannot arm a
selected-peer Case-1 fault/delay. RSSI trim/delete and evidence reset still
bypass failure accounting and writer locks. B1 has no real SwipeFeed test and
can misreport a reaped raw session as a teardown miss. The whole-tip cleanup
also missed user-specific paths, left a stale rewrite range, and broke
`scripts/GO.sh` syntax.

These are **release-enablement and evidence-integrity blockers**, not evidence of
a live production compromise. W5 remains compile/runtime gated, default-off, and
unreleased.

## Pinned state and independently reproduced checks

- Repository reviewed: `inrangeai/in-range`.
- Implementation branch: `fix/w5-hardware-evidence-2026-08-03`.
- Exact fetched origin tip:
  `adb475c47042f76948ef111fe31d2a762388137a`.
- Prior reviewed SHA:
  `d83b826154fb72f41d614e6e9a4c5a01e0b32004`.
- The reviewed tip descends from the prior SHA. Round 4 adds commits `7fe75c1`,
  `0094ca5`, and `adb475c`: 36 changed files, 570 insertions, 174 deletions.
- Review occurred in three clean detached worktrees at the exact object.
- Linux independently reproduced `flutter analyze` clean and `flutter test`
  273/273.
- A fresh multi-ABI Android debug APK built successfully: 159,345,992 bytes,
  SHA-256 `0e1992429c3230531873ee28543765a61a1cad94fed9197f5407f6569c647a3f`.
- Two Androids were visible, only one authorized; the requested three-device set
  was not present. No APK was installed and no device state changed. The
  controlling changes are iOS-native/diagnostic; the Dart/off-iOS seams are in
  the 273-test suite.
- `git diff --check` passed. Shell syntax passed for every changed shell script
  except `scripts/GO.sh`, whose Round-4 placeholder is a syntax error.
- Exact-SHA GitHub Actions run
  [30969924417](https://github.com/inrangeai/in-range/actions/runs/30969924417)
  ran Runner 55/55 and diag 68 discovered / 67 passed / 1 skipped. The skipped
  case is `testHandleUsesInjectedRunSecret`, so exact CI does not exercise the
  injected fleet-key path after removing the scheme value.
- The exact isolation job completed green and reported production 0 diagnostic
  Runner symbols / 0 known run-secret values across four discovered Mach-Os;
  diag reported 93 Runner symbols / 1 known value in `App.framework`.
- The workflow's uploaded production IPA is 8,847,785 bytes, SHA-256
  `e39446d24a960c15ed8beacab2a98de9fff095d6ca930e649a0e70eafd87fa76`.
  An independent read-only scan found four Mach-Os (Runner, App, Flutter, and
  `flutter_background_service_ios`); every one contained zero
  `INRANGE_DIAG_RUN_SECRET` labels, zero known diagnostic-control values, and
  zero `W5Diag`/`W5EvidenceWriter` names. This supports cleanliness of this exact
  production artifact; it does not make the automated negative regression-proof.
- PR #11 was independently rechecked: open, draft, head `c816f09`, base
  `fix/w5-encounter-lease`. It contains none of Round 4 and remains frozen.
- The committed Round-4 checkpoint still contains `<DART>`, `<RUNNER>`, and
  `<DIAG>` placeholders. The independent counts above supersede them.

No physical-iPhone result is inferred from Linux, Android, simulator, CI, or
artifact inspection.

## B5 — the current source improved, but the claimed true bundle gate still fails

Accepted:

- `AppConfig.diagRunSecret` is behind compile-time `kDiagBuild`, and the common
  `_dartDefine` switch no longer contains the diagnostic key label
  (`lib/core/config/app_config.dart:40-44,76-90`).
- The Dart caller is independently gated (`beacon_service.dart:1019-1026`).
- `bundle_machos` recursively discovers Mach-Os, including nested frameworks,
  dylibs, and extensions (`check_final_binary_isolation.sh:29-38`).
- The diag positive value control is real: exact CI found the known value once
  in the diag Dart AOT.

The controlling failures are in the checker:

1. Production is built without `INRANGE_DIAG_RUN_SECRET`, while only the diag
   build receives `KNOWN_DIAG_SECRET` (`check_final_binary_isolation.sh:69-92`).
   Its production zero therefore proves only that a never-supplied value is
   absent. An unconditional or accidentally ungated `String.fromEnvironment`
   regression would still pass. A paired negative must give both builds the
   same known value and vary only `INRANGE_DIAG`/the flavor.
2. The stated contract says zero diagnostic symbols across the whole bundle,
   but `symcount` runs `nm` only on `Runner.app/Runner` (`:9-12,48-49`). A
   framework or extension escapes that symbol gate.
3. The checkpoint and script header still describe a key/key-reference control,
   but the executable check measures only one chosen value. Reintroducing the
   runtime key label—the exact Round-3 failure mode—would not fail this gate.
   Independent artifact inspection found the label absent at this SHA, but CI
   does not enforce that result (`:9-21,40-63`).
4. Empty Mach-O discovery or `file`/`nm`/`strings` failure can collapse to zero;
   the script asserts only that `Runner` exists, not that the expected bundle
   executables were successfully inspected (`:33-38,49-63,73-81`).
5. `build_diag_artifact.sh` runs the isolation checker, which leaves a diag
   bundle built with the public known value, then builds the real-secret artifact
   without a clean boundary (`build_diag_artifact.sh:21-42`).

The green exact job corroborates this code path's reported counts; it does not
repair the negative control's logic. An independent clean production artifact
scan can show that this exact artifact is clean, but the executable regression
gate remains false-green.

**B5 verdict: source-level isolation likely PASS for this exact artifact;
automated whole-bundle gate FAIL; aggregate FAIL.**

## B3 — re-resolvable cache introduces an unmarked mixed-key lifecycle

Accepted:

- The header now admits persistence, the committed scheme value is gone, the
  artifact builder validates a high-entropy hex input and prints only a short
  fingerprint, and Dart awaits provisioning before it enables W5 links.
- `runSecret` is protected by a lock and `provisionRunSecret` updates the running
  cache (`W5Diag.swift:91-100,228-267`).

The lifecycle remains unsafe for matrix evidence:

1. The artifact's fleet key is a Dart compile-time define. Native
   `resolveRunSecret` cannot read it from `ProcessInfo.environment` on an ordinary
   device launch; native learns it only when Flutter invokes
   `setDiagRunSecret` (`build_diag_artifact.sh:39-42`, `W5Diag.swift:249-266`).
2. Dart still calls `_bgBeacon.start(payload)` *before* provisioning
   (`beacon_service.dart:1014-1026`). On a fresh install, native start enables
   managers/scanning; an immediate discovery can create a handle under a
   generated key before the awaited provisioning call replaces it. The comment
   that the key lands "before any W5 event can emit" is false. The channel does
   not require start, so Dart can provision before start.
3. `resetDiagSession` removes both persisted keys and clears the cache
   (`W5Diag.swift:129-140`). The app's reset wrapper does not synchronously
   reprovision. The next native/restoration handle can therefore generate a
   per-install key; later Dart provisioning replaces it with the fleet key while
   the same `w5_events.jsonl`, run label, and boot epoch remain active. The new
   unit test actually proves that the first post-reset handle differs from the
   provisioned fleet handle (`W5DiagTests.swift:129-142`).
4. Provision/reset can change `_cachedRunSecret` while a file remains open, with
   no `kid`, key epoch, rotation, or provision marker. `emit` also calculates
   peer, lease, link, and peripheral handles separately *before* acquiring the
   event-writer lock (`W5Diag.swift:54-83`). Under concurrency, even fields in
   one JSON object can be keyed differently.
5. Reset does not clear `faultPeerHandle`, `helloDelayPending`, `seqCounter`, or
   `bootEpoch`/`runLabel` (`W5Diag.swift:129-140,213-216,269-271`). A control from
   one case can fire in the next.
6. `resetW5Diag` wipes files outside every writer lock
   (`BackgroundBeacon.swift:405-410`; `W5EvidenceWriter.swift:177-184`). An emit,
   trim, or append can race the reset.
7. Exact CI skips the only injected-secret test. Existing tests cover helper
   transitions, not reset -> OS restoration -> reprovision on a device.

The prose remains internally inconsistent: it describes a process-fixed key and
an already-resolved `let` while the implementation intentionally mutates and
clears a cache (`W5Diag.swift:103-128`). Repository evidence also still lacks a
durable owner-authored record of the persistence decision. That is missing
evidence, not proof the owner never made the decision; the implementation
defects stand independently.

**B3 verdict: FAIL.**

## B2 — two fixes land, but Cases 1–3 remain neither operable nor joinable

Accepted:

- The HELLO delay is consumed once and defaults to zero when unarmed
  (`W5Diag.swift:177-194`; `W5LinkController.swift:262-279`).
- The locked/no-token dial now emits a peripheral-attributed `dialStart`
  (`BackgroundBeacon.swift:1194-1199`).

Controlling gaps:

- There is no installed selected-peer arm/status/disarm/reset surface.
  `armW5HelloDelay` has no `BeaconService` method, application caller, or test;
  the fault/disarm/reset service methods likewise have definitions but no app
  caller. Removing the always-on delay without shipping the control means the
  installed build cannot construct Case 1.
- The delay is global "next HELLO," not peer-scoped. The fault still permits and
  tests a nil-target wildcard (`W5Diag.swift:144-155,177-190`;
  `W5DiagTests.swift:33-36`). Separate arm calls are not one atomic selected-peer
  operation, so another concurrent link can consume the delay.
- The token-read `dialStart` carries peripheral only; later HELLO/lease events
  carry peer/link but no peripheral. Physical `.parted` carries peripheral,
  while `.graceEnter` carries lease. Those domains cannot be joined to prove
  which peer dropped (`BackgroundBeacon.swift:1194-1213,1242-1248`;
  `W5LinkController.swift:255-260,878-887`).
- Inbound HELLO_ACK and REJECT sends have no structured send event. PROPOSE and
  ACK send events lack the peer, role, and route needed for a multi-peer story
  (`W5LinkController.swift:431-454,701-740`).
- `coldLaunch` still emits before manager creation, so its relationship to
  restoration callbacks remains structurally unreliable
  (`BackgroundBeacon.swift:260-268`).

**B2 verdict: FAIL. Cases 1–3 are not provable from the current installed app.**

## B4 — atomic append passes; evidence integrity remains preflight-blocking

Accepted:

- Event sequence assignment plus append occur in one critical section.
- `completeUntilFirstUserAuthentication` is the appropriate locked-state class
  after first unlock.
- The new 16 x 40 concurrent append test is meaningful and exact CI runs it.
- Missing/short puller secret now aborts instead of generating unkeyed
  commit-ready tags, and the JSON field-domain map matches the named native
  domains for recognized fields.

Remaining integrity defects:

1. RSSI trim replacement and fully-consumed deletion still use silent `try?`
   paths outside the writer's protection/backup/accounting operation
   (`W5LinkController.swift:999-1012,1039-1051`). A trim can fail silently, and
   the replacement is not reverified through `applyProtection`.
2. File-size reads and `FileHandle.close()` also remain unaccounted
   (`W5EvidenceWriter.swift:71-82,101-119`). `noteOpFailure(kind)` ignores
   `kind`, so rotation, protection, and backup failures collapse into one
   indistinguishable per-file integer (`:171-175`).
3. Prior counters are removed before the boot evidence line is durably appended.
   If the boot append fails, the original total is lost and only the new failure
   remains (`BackgroundBeacon.swift:253-259`;
   `W5EvidenceWriter.swift:218-226`).
4. `wipeDiagnosticFiles` silently deletes outside writer locks and omits
   `w5_rssi_log.1.jsonl`, even though the puller names that artifact
   (`BackgroundBeacon.swift:153-161`; `hw_matrix_pull.sh:32-33`). Stale evidence
   can race or cross a claimed reset boundary.
5. The puller validates its key only after creating output paths and attempting
   every raw pull. Every `devicectl` error becomes optional "no file," so a
   transport/permission failure can return a successful empty evidence run
   (`hw_matrix_pull.sh:14-34,49-53`). Its minimum/hex validation also differs
   from the artifact builder.
6. Malformed JSONL falls back to plain-text regex sanitation and is still
   published; mandatory structured evidence is not parsed and post-scanned
   fail-closed (`hw_matrix_pull.sh:64-87`). The raw DB is copied only into
   scratch and no sanitized DB artifact is produced.
7. There are no injected tests for rotate, protection, backup, trim, delete,
   reset/wipe, counter-report failure, malformed sanitizer input, or mandatory
   pull failure. Simulator attribute assertions explicitly skip what the
   simulator cannot report.

**B4 verdict: PARTIAL; preflight-blocking.**

## B1 — identifier safety and native committed hit pass; end-to-end proof is partial

Accepted:

- Server cards still never fabricate a radio alias; fresh/stale local aliases
  use only the radio domain.
- The new diag test commits a real lease and calls
  `BackgroundBeacon.dropPeerByToken`, the native method reached by the platform
  channel (`W5TeardownTests.swift:156-180`).

Open defects:

- No test renders `SwipeFeed` or triggers `_doPass`; Dart tests cover extracted
  helpers and mocked seams. The raw CA5E reap path is also untested—the committed
  hit seeds no `CBPeripheral` and asserts zero reaped (`W5TeardownTests.swift:173-175`).
- `_doPass` awaits teardown but sends its evidence record with `unawaited`, and
  `recordW5Teardown` has no test or durable sequence/ack
  (`swipe_feed.dart:137-146`). A native-unavailable outcome cannot reliably be
  persisted through the same unavailable channel.
- `dropPeerByToken` can reap a matching raw W5 session even when lease lookup
  misses (`BackgroundBeacon.swift:1446-1465`). Dart defines a tear only as a
  lease lookup hit and ignores `rawSessionsReaped` when classifying a miss
  (`pass_teardown.dart:78-95`). It can therefore report "miss" while native
  actually disconnected a raw session.
- Comments still say only a "still-FRESH" alias is attempted while the resolver
  deliberately sends both fresh and stale aliases
  (`swipe_feed.dart:123-135`; `pass_teardown.dart:127-135`).

**B1 verdict: identifier-domain safety PASS; native committed-hit boundary PASS;
aggregate PARTIAL.**

## B6 — known identifiers are scrubbed at the tip; whole-tip/proposal contract fails

Accepted:

- No checked modern iOS device-ID pattern remains at the exact tip.
- The known session-document IDs are removed, the diag scheme carries no fleet
  value, and the tracked field-test DBs contain only short `id:` tags rather
  than raw 32-hex correlation values.
- The history proposal is now value-free, and the hardware-evidence subtree is
  clean for the checked device-ID/raw-token formats.

Remaining failures:

- Five user-specific absolute path occurrences remain on three lines in
  `docs/ADVERSARIAL_REVIEW_2026-07-15.md:174,182,302`.
- The proposal still calls `357053c` the current tip, 15 commits behind
  `adb475c`. Its proposed range `f989231..357053c` excludes the named introducing
  commit itself and cannot cover older sensitive introductions or the later
  descendants (`PRIVACY_REDACTION_PROPOSAL.md:35-79`). It does not specify an
  executable all-affected-refs rewrite.
- The scrub changed `scripts/GO.sh:43` to unquoted
  `flutter run -d <device-serial>`. `bash -n` fails. This line is attributed to
  Round-4 privacy commit `7fe75c1`.

History rewrite remains owner-only and was neither required nor authorized in
this review.

**B6 verdict: known current device-ID/token cleanup PASS; whole-tip and rewrite
inventory FAIL; aggregate FAIL.**

## Three-reviewer reconciliation

Claude, Kimi, and Codex independently reviewed detached worktrees at the exact
SHA before seeing each other's conclusions. Their independent aggregate labels
differed only where a genuine improvement and a controlling defect coexist:
Kimi initially called B3/B5/B6 partial, while Claude and Codex called the
controlling contracts failures. The panel resolved that without hiding either
side of the evidence:

- B5 exact production-artifact inspection passes; the automated whole-bundle
  regression gate fails; aggregate **FAIL**.
- B3 cache mechanics and committed-value removal pass; the evidence-session
  key/epoch lifecycle fails; aggregate **FAIL**.
- B6 known identifier/DB-value cleanup passes; whole-tip/proposal/executable
  hygiene fails; aggregate **FAIL**.
- B1 is **PARTIAL**, B2 **FAIL**, and B4 **PARTIAL but preflight-blocking**.
- Exact CI is green only when reported honestly as Runner 55/55 and diag 67/68
  with the injected-secret test named as skipped. It does not close B3.

Claude and Kimi then received the reproduced facts and proposed split labels in
a concise reconciliation round. Both replied **`CONSENSUS: AGREED`**. Codex
co-signs the same resolution. The unanimous controlling decision is **HOLD**:
preflight not ready, matrix not authorized, PR #11 frozen, no stacking, and W5
release enablement blocked. No reviewer classifies these blockers as a live
production compromise.

## Requirement ledger

| Area | Verdict at `adb475c` |
|---|---|
| B1 identifier-domain safety | PASS |
| B1 committed hit through real native boundary | PASS |
| B1 SwipeFeed/raw-session/observable chain | PARTIAL |
| B2 one-shot armed-conditional delay implementation | PASS |
| B2 selected-peer installed control | FAIL |
| B2 joinable Case 1–3 transition evidence | FAIL |
| B3 cache update and committed-value removal | PASS |
| B3 reset/restoration/fleet-key lifecycle | FAIL |
| B3 one-key-per-event/file contract | FAIL |
| B3 durable owner-decision provenance | Missing evidence |
| B4 atomic seq+append and concurrency test | PASS |
| B4 locked-state/operation failure accounting | FAIL |
| B4 pull/sanitize/publish fail-closed chain | FAIL |
| B4 aggregate | PARTIAL; preflight-blocking |
| B5 exact production artifact negative scan | PASS for checked labels/value/names |
| B5 automated production negative control | FAIL |
| B5 whole-bundle symbol contract | FAIL |
| B6 known tip identifiers and tracked DB values | PASS |
| B6 whole-tip/proposal/executable hygiene | FAIL |
| One-phone log-integrity preflight | **NOT READY** |
| Three-iPhone Phase-5 matrix | **NOT AUTHORIZED** |
| W5 release enablement | **BLOCKED** |

## Decision separation

- **One-phone preflight:** not ready. B2 cannot drive or join the required
  selected-peer event chains; B3 cannot guarantee one fleet key per evidence
  epoch; B4 cannot guarantee complete, accounted, fail-closed artifacts.
- **Full matrix:** not authorized. It remains downstream of a successful
  preflight and another exact-SHA READY panel.
- **PR #11 frozen at `c816f09`:** out of scope. This report neither authorizes
  nor invalidates its prior exact-SHA result.
- **Stacking `adb475c` into PR #11:** not authorized.
- **W5 release enablement:** blocked. No live production compromise is inferred
  from the disabled runtime.

## Required next Mac checkpoint

Complete these without installing on phones:

1. **B5 real paired gate:** pass the same known secret to production and diag;
   vary only the diag compile/flavor input; assert expected Mach-O discovery;
   scan diagnostic symbols across every Mach-O; fail on tool/discovery errors;
   clean before building the real diagnostic artifact.
2. **B3 atomic evidence epoch:** establish the native fleet key before managers
   can emit keyed events, or make reset atomically accept/reinstall that key.
   Snapshot one key per event; rotate/wipe on key changes; carry a non-secret key
   epoch; reset fault/delay/sequence/run state and files under the relevant locks.
3. **B2 installed selected-peer control:** ship a diag-only surface that selects
   a peer and atomically arms status + fault + HELLO delay, with explicit
   disarm/reset and no wildcard. Complete peer/lease/link/peripheral/role joins
   for physical drop, HELLO_ACK, REJECT, PROPOSE, ACK, and restoration.
4. **B4 writer/puller integrity:** route trim/delete/wipe through injected,
   testable writer operations; preserve counters until durably acknowledged;
   validate before pulling; require primary artifacts; parse and post-scan
   structured output; stage then atomically publish; add failure-injection tests.
5. **B1 effect chain:** await a durable outcome record; classify raw-session
   reaps honestly; add a real SwipeFeed pass widget/integration test and a raw
   session reap test.
6. **B6 cleanup:** remove the remaining user path occurrences, repair `GO.sh`,
   and replace the stale range with a value-free, all-affected-refs proposal
   through the eventual clean tip. Do not execute the rewrite.
7. Run the full suite, push one exact SHA plus a filled manifest, dispatch exact
   CI, inspect its final IPA, and stop for another blinded three-reviewer panel.

## Reply for the Mac agent

Panel verdict on `adb475c` is **HOLD**. Accepted as real: identifier-domain
safety, the committed hit through `BackgroundBeacon.dropPeerByToken`, one-shot
HELLO-delay mechanics, token-read `dialStart`, atomic seq+append, the 16 x 40
writer test, removal of committed/baked/printed fleet values, recursive Mach-O
discovery, known device-ID/DB cleanup, and exact CI's green Runner/diag runs.

The headline DONE labels do not hold. B5's production check never supplies the
known value, so zero is tautological; its symbol scan still covers Runner only.
B3 reset erases native's fleet key, can change HMAC keys inside one JSONL, and
does not reset fault/delay state under writer locks. B4 leaves RSSI trim/delete,
counter acknowledgment, reset, and mandatory extraction fail-open. B2 has no
installed selected-peer control and still lacks joinable transition evidence.
B1 has no SwipeFeed/raw-session effect-chain test and can record a miss after
actually reaping a raw session. B6 retains three user-path lines, a stale rewrite
range, and a Round-4 `GO.sh` syntax regression.

One-phone preflight is **NOT READY**; matrix **NOT AUTHORIZED**; PR #11 stays
frozen; no stacking, device install, merge, mirror, deploy, or history rewrite.
Complete the seven-item checkpoint above, push one new exact SHA, and stop for
another blinded panel.
