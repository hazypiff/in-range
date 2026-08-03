# Mac hardware + LLM panel work order — 2026-08-03

Use this as the self-contained dispatch for the Mac agent that has the three
registered iPhones and access to its own LLM panel.

Read first:

- `LINUX_ANDROID_PANEL_FOLLOWUP_2026-08-03.md`
- `MAC_EVIDENCE_PACKET.md`
- `MAC_EXIT_PACKET.md`

The follow-up is an erratum. Where the earlier packets call H-W5-2
“HW-verified,” Case 4 proven, H-W5-6 a durable no-redial guarantee, all logs
protected/backup-excluded, or the diag runtime positive control complete, use
the follow-up's narrower status.

## Objective

Build an attributable, privacy-preserving diagnostic harness; correct the
identified identifier, persistence, logging, and CI gaps; and produce honest
three-iPhone evidence for W5 cases 1–4.

Keep two decisions separate:

1. whether draft PR #11 is safe to integrate while W5 remains compile-disabled;
2. whether W5 is safe to enable in any release.

The second decision remains blocked until this work order passes. Do not merge,
deploy, fast-forward PR #9, or force-update PR #11 as part of this dispatch.

## Fixed review target

- Repository: `inrangeai/in-range`
- PR #11 head: `integ/mac-hardening-2026-08-01`
- Expected PR tip before this docs handoff:
  `53ed423ede6eda472e00ce7339d7c050ff9d4930`
- Exact reviewed code ancestor:
  `98279de40ec04b40e76a8acc016ca5e9d6566f78`
- Linux report branch: `docs/android-panel-assist-2026-08-03`

Fetch both remotes, read the report commit, and record the new report SHA before
starting. Create a fresh stacked implementation branch from the report branch
tip; suggested name: `fix/w5-hardware-evidence-2026-08-03`. Do not reuse a dirty
worktree. If any expected SHA or ancestry check fails, stop and document the
actual graph rather than silently rebasing the evidence.

### Local Mac results reported after this work order began

The Mac side subsequently reported four hardware passes and named instrumentation
commit `f989231`, but at the Linux recheck neither GitHub repository contained
that object and PR #11 still pointed to `53ed423`. Preserve the local commits;
before changing the exit packet or starting panel sign-off:

1. push the instrumentation and sanitized evidence to a named branch;
2. provide the exact tip SHA and artifact manifest;
3. fetch the Linux erratum branch and address its Case 1–4 objections;
4. run reviewers against the pushed exact tip, not the verbal summary.

Specifically, require Case 1 to show actual pending-dial reclamation rather than
only a four-second delay with zero sweeps; require Case 4 to distinguish narrow
current-alias lease teardown from an unimplemented durable no-redial rule. The
reported `state-stamp-adopted-legacy` event proves legacy adoption only, not the
foreign-flavor snapshot/file wipe.

## Safety rules

- Use only diagnostic builds for W5 hardware tests.
- Do not add raw peer tokens, peripheral UUIDs, link IDs, device serials,
  coordinates, account IDs, credentials, or the run secret to a log, screenshot,
  transcript, commit, PR body, or LLM prompt.
- Do not assume a Dart `--dart-define` reaches Swift. Wire native diag values
  explicitly through a diag-only xcconfig/Info.plist or another compile-gated
  test channel.
- Do not swipe the app away for restoration testing. Apple documents that user
  force-quit prevents CoreBluetooth restoration relaunch.
- Do not weaken production file protection merely to make the test pass. Any
  diagnostic-only availability tradeoff must be explicit and compile-isolated.
- Preserve user changes and unrelated branches. No destructive Git commands.

## Phase 0 — freeze the baseline

Record in the evidence manifest:

- report branch tip and implementation branch base;
- `git merge-base` with PR #11 head and PR #11 base;
- clean worktree status;
- Xcode, Swift, Flutter, CocoaPods, macOS, and iOS versions;
- the three fleet roles: iPhone 14, iPhone 13, iPhone 15 Plus;
- artifact SHA-256 and build configuration for every installed app.

Before code changes, reproduce:

- `flutter analyze`;
- full `flutter test`;
- `xcodebuild test` for the normal Runner scheme;
- `scripts/check_release_isolation.sh`;
- an unsigned production release build;
- final-binary string/symbol inspection for existing diagnostic markers.

Do not call the baseline “safe” merely because it matches the earlier packet;
record any discrepancy.

## Phase 1 — settle H-W5-6's executable contract

The current source crosses two identifier domains:

- a server `SwipeCard.id` is `encounter_id`;
- a local `SwipeCard.id` is the observed token/correlation hex;
- native `dropPeer` expects a token alias.

The current native lease is intentionally not a permanent rejection ledger.
`onTeardown` erases it, and a future `onDiscovered` can create another one.

Implement the narrow, evidence-backed contract unless the owner explicitly
chooses a different product rule:

> A pass tears down the currently mapped W5 radio lease immediately when a
> trustworthy current radio alias is available. Durable user-level pass/block
> behavior belongs to the app/server identity layer; W5 does not infer stable
> identity from a rotating alias.

Required changes:

1. Separate the feed card's dismissal/server identifier from its optional
   current radio alias. Do not pass `encounter_id` to an alias-keyed native API.
2. Propagate a radio alias only from an evidence-backed mapping. If a server row
   cannot supply one safely, make teardown explicitly unavailable/best-effort
   and do not claim it occurred.
3. Make native `dropPeer` return a structured diagnostic result: lookup hit or
   miss, number/roles of live links closed, and whether the lease ended. Do not
   return raw identifiers.
4. Add Dart and Swift tests for local hit, server-ID-not-treated-as-alias, alias
   miss, inbound-only link, outbound-only link, and two-role teardown.
5. Rename Case 4 from “rejection prevents redial” to “current mapped lease is
   torn down on pass” under this contract.

If the owner instead requires durable no-redial, stop before implementing an
alias ledger. Write a privacy-reviewed design using a stable, server-resolved
peer identity, specify the retention/undo/block semantics, and test across both
the five-minute retry floor and token rotation. Raw rotating aliases are not a
sound durable identity.

## Phase 2 — build a compile-safe diagnostic event layer

Replace free-form event strings with a structured event API whose payload is
lazy and diagnostic-only.

Use defense in depth:

1. make the payload `@autoclosure` or construct it entirely inside a helper
   compiled under `#if INRANGE_DIAG`; and
2. compile-gate every call site that supplies sensitive peer/lease/link data.

Minimum JSONL fields:

| Field | Requirement |
|---|---|
| `v` | schema version |
| `run` | run-scoped public label, not the secret |
| `epoch` | boot/launch epoch so relaunches are distinguishable |
| `wallMs` | UTC wall time for cross-device alignment |
| `monoNs` | monotonic time for local ordering |
| `seq` | per-process monotonic sequence |
| `event` | stable enum-like event name |
| `role` | central/outbound, peripheral/inbound, or app |
| `peer`, `lease`, `link`, `peripheral` | optional run-scoped HMAC handles |
| `result`, `reason`, `count` | non-sensitive structured outcome |

Use one random, ephemeral shared run secret across all three phones. Derive each
handle as truncated HMAC-SHA256 over a domain-separated raw identifier, for
example `peer\0<token>` versus `lease\0<leaseId>`. Keep 12–16 hex characters.
The secret is injected into diagnostic Swift configuration only, never
persisted or printed, and destroyed after sanitized artifacts are produced.

Instrument at least:

- discovery/tiebreak decision and reason;
- pending dial create, physical dial start, connection result, failure, and TTL
  sweep;
- `HELLO`, `HELLO_ACK`, `PROPOSE`, ACK, and protocol rejection at the state
  transition level (never raw frames);
- ownership commit and selected role;
- link down, grace enter, grace-recovery bypass, and grace expiry;
- alias-roll send/receive and previous-alias expiry;
- `dropPeer` input class, lookup hit/miss, close roles, and ended result;
- central and peripheral `willRestoreState` entry, restored-object counts,
  snapshot load result, characteristic rebind result, and cold-launch marker.

Add a one-shot deterministic `#if INRANGE_DIAG` hook that stalls or drops the
target connection before `HELLO_ACK`. It must be scoped to a run/peer handle and
auto-clear. The pass condition is stale-state reclamation followed by a
successful commit with a fresh peer, not mere silence.

## Phase 3 — repair evidence persistence and flavor isolation

1. Move diagnostic evidence to a documented diagnostic-only location.
2. Apply the chosen file-protection and backup-exclusion attributes on create,
   append/replacement, and rotation. Reapply `isExcludedFromBackup` after every
   operation that can replace a file.
3. Replace the `FileHandle`-open failure fallback with an append/create path that
   distinguishes “file absent” from “existing file temporarily inaccessible.”
   Never replace an existing log with one line merely because opening failed.
4. Make failures observable with bounded non-sensitive counters so a missing
   line is not silently interpreted as a protocol event that never happened.
5. On a foreign non-nil flavor stamp, atomically clear the W5 snapshot, RSSI
   file, wake file/rotation, offsets, tokens, W5 flag, and associated operational
   state. Do not clear only the RSSI offset while retaining the file.
6. Decide and document legacy unstamped upgrade behavior separately from a
   known cross-flavor transition.
7. Ensure raw-token RSSI content can never be included in a release build or
   unsanitized evidence bundle.

### Mandatory one-phone log-integrity preflight

Before cases 1–4:

1. write at least 100 numbered events;
2. establish an active Bluetooth condition that should produce locked-state
   events;
3. lock/background through scheduled writes;
4. unlock and pull the file;
5. assert sequence and line counts are monotonic and missing-event counters are
   zero or explicitly explained;
6. force cap/rotation and repeat the assertions across both files;
7. verify file protection and backup exclusion on each resulting file.

If this preflight fails, stop the matrix. Do not infer hardware behavior from an
unreliable logger.

## Phase 4 — make release isolation executable

1. Split `ReleaseIsolationTests` into flavor-aware assertions or create separate
   production and diag suites. Production asserts `isDiagBuild == false` and
   unsuffixed restoration IDs; diag asserts the inverse and `.diag` IDs.
2. Execute both schemes/configurations in CI. Merely populating diag
   `<Testables>` is not a pass if the tests contain production-only assertions.
3. Keep the fail-closed build-settings check and its diag positive control.
4. Add final-binary inspection:
   - production artifact must contain none of the diagnostic event names,
     evidence filenames, test-hook controls, or run-secret configuration keys;
   - diagnostic artifact must contain a safe marker as a positive control so an
     empty/broken inspection cannot pass.
5. Make release artifact production depend on the required test/isolation gate,
   or combine them in one job whose artifact upload occurs only after success.
6. Verify clean-install production, clean-install diag, diag-to-production
   upgrade, and production-to-diag transition on a real device without adopting
   foreign operational state.

## Phase 5 — execute the three-iPhone matrix

Record the election role and HMAC handles on all devices before evaluating a
case. Every negative assertion needs a positive control proving the observer
could have seen the prohibited event.

### Case 1 — third peer during a pre-ACK dial

1. Use the deterministic one-shot hook to hold or drop a selected dial before
   `HELLO_ACK`.
2. Introduce the third phone during that interval.
3. Prove which pending dial was created, that the intended race was reached,
   and that the stale dial was reclaimed by failure or the 20-second sweep.
4. Clear the hook and demonstrate a successful later commit with a fresh peer.
5. Assert no leaked pending dial, no contender over-cap, and one keeper for each
   valid encounter.

A normal three-peer convergence without the forced race is only a smoke pass.

### Case 2 — keeper drop, rotate, reconnect inside 120 seconds

Independently prove all four facts:

1. the committed keeper link dropped;
2. the peer token rotated before reconnect;
3. `ALIAS_ROLL` could not be delivered on the dropped link; and
4. reconnect inside 120 seconds reused the same lease rather than minting a new
   one.

Also prove the discovery path actually bypassed both the 15-minute token cache
and five-minute retry floor for an in-grace lease.

### Case 3 — CoreBluetooth restoration and stale generation

1. Record the fleet iOS versions and confirm TN3115 eligibility, including any
   iOS 26 constraints that apply.
2. Establish and log a committed lease with a pending CoreBluetooth reason for
   restoration.
3. Background the app, then use system memory removal/jetsam or a controlled
   diagnostic crash/termination while suspended. Do not use the app switcher.
4. Require a new launch epoch whose first relevant event is
   `willRestoreState`, not a cold-start reconstruction mislabeled as restore.
5. Prove restored central/peripheral objects, snapshot acceptance, control and
   keepalive characteristic rebind, and lease continuity.
6. Inject/send a stale-generation message and prove it is ignored without
   damaging the restored keeper; then prove a valid current message still
   succeeds.

### Case 4 — current mapped lease teardown on pass

Under the recommended narrow contract:

1. Establish a committed local-token lease.
2. Pass the corresponding local card.
3. Prove the Dart card carried the separate current radio alias, native lookup
   hit, every live role received its close effect, the physical session ended,
   and the ownership lease was erased.
4. Repeat with inbound-only, outbound-only, and simultaneous two-role topology.
5. Exercise a server-backed card. Prove a correct alias mapping if one exists;
   otherwise prove the code does not mislabel `encounter_id` as an alias and
   reports teardown unavailable/miss honestly.
6. Include a positive control where an unswiped peer dials and commits under the
   same token ordering/environment.

Do not use a short “no redial” interval as proof: the five-minute retry floor
and lower-token initiator rule confound it. If the owner chooses durable
no-redial instead, add tests beyond five minutes and across at least one token
rotation, using the approved stable identity design.

## Phase 6 — evidence bundle and commits

Create a sanitized directory such as:

`docs/research/2026-08-01-hardening/hardware/2026-08-03/`

Include:

- `MANIFEST.md`: exact code/build SHAs, artifact hashes, device roles/OS,
  commands, timestamps, and pass/fail summary;
- one sanitized JSONL per device and case;
- a validation output that checks schema, HMAC-handle format, sequence gaps,
  cross-device joins, and required event assertions;
- normal and diag native test summaries;
- release/diag build-settings and final-binary isolation outputs;
- log-integrity/rotation test result;
- no raw source logs.

Create separable commits in this order:

1. identifier/contract tests and fix;
2. diagnostic event + persistence/isolation fixes;
3. CI and release-isolation tests;
4. sanitized hardware evidence and final verdict.

Run the full suite after the final code commit and again against the exact SHA
named in the manifest. Push the branch to `inrangeai` and mirror to `hazypiff`
only when authorized. If a remote denies the push, report the 403 and stop; do
not attempt to obtain or repurpose another account's credentials.

## Phase 7 — blinded LLM panel prompt

Give each reviewer the exact tested SHA, this work order, the follow-up report,
the manifest, validation output, and sanitized artifacts. Do not give a reviewer
another reviewer's verdict until its first pass is frozen.

Use this prompt:

> Review read-only. Do not edit, push, merge, deploy, or delegate. Treat every
> claim as unproven until you name the exact source line, test assertion, or
> sanitized event sequence supporting it. Independently answer:
>
> 1. Does the production artifact exclude W5, diagnostic filenames/events,
>    hooks, and run-secret plumbing, with a working diag positive control?
> 2. Does the logger preserve attributable evidence while locked, across
>    rotation, relaunch, and three devices without exposing raw identifiers?
> 3. For each hardware case 1–4, list the required event chain, the observed
>    chain, missing links, confounders, and verdict: PROVEN, SCOPED PASS,
>    UNPROVEN, or FAILED.
> 4. Does Case 4 keep server encounter IDs, local rotating aliases, ownership
>    lease IDs, and stable user identity distinct? Does the code implement only
>    immediate current-lease teardown or a documented durable veto?
> 5. Can PR #11 be integrated while W5 is disabled? Separately, can W5 be
>    enabled? State the narrowest blocking reason for each answer.
> 6. Give the strongest counterargument to your own verdict and resolve it with
>    evidence. Mark every remaining inference explicitly.

After independent passes, run one reconciliation round. For each disagreement,
record the original claim, counterexample, final disposition, and which evidence
changed. Do not manufacture consensus. A split verdict is acceptable and must
remain visible.

## Exit criteria

The Mac agent may report **PR-INTEGRATION SAFE WHILE W5 DISABLED** if the exact
artifact and state isolation remain clean, even if hardware evidence is still
blocked.

The Mac agent and panel may report **W5 RELEASE-ENABLEMENT SAFE** only if:

- the H-W5-6 identifier/contract issue is resolved and tested;
- log integrity, privacy, flavor wipe, and final-binary isolation all pass;
- cases 1–4 have attributable committed evidence with positive controls;
- no case relies on user force-quit, untagged log inference, retry-floor silence,
  token-tiebreak silence, or Android as a substitute for native iOS behavior;
- the exact tested code SHA equals the SHA being approved.

Otherwise report the narrow blocked status and preserve the evidence. Do not
upgrade a scoped smoke pass into hardware verification.
