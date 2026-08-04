# Phase 1–4 exact-SHA panel review — 2026-08-03

## Decision

**HOLD.** Commit `357053c8506017840d7203f732a3464ed81312ee` is
not ready for the one-phone log-integrity preflight or the three-iPhone Phase-5
matrix. Do not install it on a phone, advance PR #11, merge, or deploy it.

The Phase-1 identifier split is a useful correction, and the exact-tip Dart and
Android checks are green. The statement that code Phases 1–4 are complete is
nevertheless an overclaim: required event chains are missing, the evidence
writers still have the exact locked/open-failure defects the work order called
out, and release isolation is not wired into CI.

## Pinned target and independent checks

- Repository: `inrangeai/in-range`
- Implementation branch: `fix/w5-hardware-evidence-2026-08-03`
- Exact remote tip: `357053c8506017840d7203f732a3464ed81312ee`
- Reviewed base: `c816f09df433bb9d3c80ad222ae2d88a63b8ed10`
- PR #11 remains a draft at `c816f09`; it was not advanced.
- The review used a clean detached worktree at the exact remote object.
- Linux reproduced `flutter analyze` clean and `flutter test` 252/252.
- GitHub run `30854551524` passed the exact SHA's Dart and Android jobs.
- The three new shell scripts pass `bash -n`.
- Linux cannot reproduce Xcode, simulator, signing, final-binary, or the reported
  53/53 native results. This branch received no `ios-build.yml` push run, so the
  Mac-only counts and `nm` counts remain local evidence rather than independent
  CI corroboration.

Claude and Kimi reviewed independently before seeing one another's verdict.
Both returned **NOT READY FOR PHASE 5**, **W5 ENABLEMENT BLOCKED**, and only a
conditional, separate view of PR #11 while W5 remains disabled.

## Release-enablement blockers

### B1 — Phase 1 does not yet carry a trustworthy current alias end to end

The identifier-domain correction is real: server cards set `radioAlias` to
null and no longer pass `encounter_id` to the alias-keyed native method
(`lib/features/encounters/swipe_card.dart:95-135` and
`lib/features/encounters/swipe_feed.dart:116-125`).

The local path still treats every stored correlation token as current. A local
card can live for 24 hours (`local_encounter_store.dart:38-49`), while tokens
rotate every 15 minutes (`ephemeral_token_generator.dart:20-31`) and native's
alias TTL is 15 minutes (`W5LinkController.swift:94`). Concrete failure path:

1. a peer is seen and a local card persists;
2. its token rotates and the prior native alias expires;
3. the user passes the old card;
4. `dropPeer(alias:)` misses at `W5LinkController.swift:466-472`;
5. `BeaconService.dropPeer` discards the structured future/result
   (`beacon_service.dart:2171-2176`), so the pass still looks successful.

The server-card null path is also silent: it records neither an explicit
`unavailable` result nor a positive proof that no server identifier crossed the
native boundary. Existing Dart tests pin card construction, not `_doPass` or
the platform-channel call. Swift teardown tests reconstruct the ownership
helper rather than executing the real controller/channel path.

Required correction: define alias freshness, await and propagate the native
result through `BeaconService`, record `unavailable` for a server card, and add
executable Dart/Swift tests for the actual call path and stale/miss outcomes.

### B2 — The structured event layer cannot prove Cases 1–3

`W5Diag.Event` declares the requested vocabulary
(`ios/Runner/W5Diag.swift:21-31`), but declarations are not instrumentation.
There are no emit call sites for at least:

- discovery and tiebreak decision/reason;
- physical dial start, connection result, or dial failure;
- PROPOSE or ACK;
- grace expiry;
- alias-roll send or previous-alias expiry;
- cold-launch marker or ownership-snapshot load result.

Consequences:

- Case 1's forced disconnect can reclaim through `onDialFailed`, but no
  `dialFail` event proves that reclamation; zero sweeps is still not proof.
- Case 2 cannot prove alias-roll delivery was impossible or previous-alias
  expiry from the new JSONL alone.
- Case 3 cannot distinguish cold launch from restoration or prove snapshot
  acceptance and handle continuity.
- The commit event omits selected role (`W5LinkController.swift:599-603`), and
  `dropPeer` logs only a role count, not the closed roles (`:481-482`).

The fault hook is present only as a native method-channel case
(`BackgroundBeacon.swift:372-376`); there is no Dart wrapper/control path in
`lib/`, so the diagnostic app has no committed way to arm a selected peer.

The release no-op body also is not the two-layer construction the order
required: `emit` takes eager arguments (`W5Diag.swift:39-44`) and sensitive call
sites are not individually compile-gated.

### B3 — Run/handle continuity across restoration is unproven

`W5Diag` reads `INRANGE_DIAG_RUN_SECRET` only from the process environment and
otherwise generates a per-process secret (`W5Diag.swift:104-118`). Neither the
diag scheme nor `scripts/build_diag_artifact.sh` injects that value. An
iOS-spawned CoreBluetooth restoration process therefore has no repository-
proven way to receive the same secret. If it falls back, every HMAC handle
changes at the exact boundary Case 3 must join.

Do not assume Xcode/devicectl launch-environment retention across an OS
restoration relaunch. Wire and validate the real launch path, or explicitly
amend the evidence design. The one-phone preflight may empirically validate the
chosen mechanism, but the full matrix remains blocked until it does.

### B4 — Phase 3 did not unify or harden the evidence writers

There are three separate file writers with different behavior:

1. `W5Diag.write` opens and closes on every event. If `FileHandle` open fails,
   it writes the new line directly without first distinguishing absent from
   existing-but-inaccessible (`W5Diag.swift:160-190`). That can replace an
   existing log with one line—the exact Phase-3.3 defect.
2. `logWake` has the same fallback and has no explicit protection or backup
   exclusion on create, append, or rotation
   (`BackgroundBeacon.swift:775-809`). It still receives raw token prefixes at
   call sites such as `:1187` and `:1394-1397`.
3. The RSSI writer stores the full raw token and has the same ambiguous-create
   fallback (`W5LinkController.swift:862-907`). It is runtime-unreachable in a
   production build at this SHA because `w5LinksEnabled` is compile-time false
   outside DIAG (`BackgroundBeacon.swift:120-130`), but enabling W5 would make
   it live unchanged.

`completeUnlessOpen` plus per-event open/close is also structurally hostile to
locked-state evidence: an existing protected file cannot be reopened while
locked. Only `W5Diag` failures increment the new bounded counter; wake/RSSI
failures remain silent. The mandatory locked-phone integrity preflight would
therefore fail or yield incomplete evidence today.

Required correction: one serialized diagnostic writer (or equivalent shared
primitive), explicit absent-versus-inaccessible handling, attributes and
backup exclusion verified after every replacement/rotation, no raw identifiers
or prefixes in committed evidence, and bounded failure accounting for every
file family.

### B5 — Phase 4 is local scaffolding, not an executable CI gate

No workflow changed in `c816f09..357053c`.

- `ios-build.yml:47-59` runs only `-scheme Runner`; it never runs the diag
  scheme or the diag-side flavor assertions.
- `build-ios` begins independently at `ios-build.yml:68` with no
  `needs: test-ios`, then uploads the release IPA even if tests fail.
- `scripts/check_final_binary_isolation.sh:21-41` gates only on `W5Diag` symbol
  count. Its strings scan is informational, even though the work order requires
  negative checks for event names, evidence filenames, hook controls, and the
  run-secret key.
- The production source intentionally still contains the `armW5Fault` channel
  string and diagnostic filenames, so the stated Phase-4 negative requirement
  is not met.

Required correction: execute both schemes plus build-settings and final-binary
negative/positive controls in CI, and make release artifact production depend
on that job. The negative control must enforce the agreed production contract,
not merely print the contradicting strings.

### B6 — Baseline/evidence hygiene needs correction before mirroring

`PHASE0_BASELINE.md` records an already dirty tree after implementation files
existed, omits the mandated pre-change command outputs, iOS versions, artifact
hashes, and complete merge-base data, and combines Phases 3+4 in one commit
despite the requested separability.

It also contains three unexplained device-identifier fragments and names a
different third-phone model from the owner-confirmed fleet. The work order
forbids device serials/identifiers in commits and LLM packets. Do not repeat the
values. Remove them from the branch tip, correct the fleet record, and ask the
owner before any history rewrite/force-push. Do not mirror this implementation
branch to `hazypiff` until that is resolved.

## Requirement ledger

| Area | Verdict at `357053c` |
|---|---|
| Phase 1 identifier-domain separation | PASS |
| Phase 1 current-alias trust + observable result | PARTIAL |
| Phase 1 end-to-end test matrix | PARTIAL |
| Phase 2 schema/HMAC primitive | PARTIAL |
| Phase 2 mandatory event coverage | FAIL |
| Phase 2 restoration/run continuity | UNPROVEN |
| Phase 3 protection, append, rotation, counters | FAIL |
| Phase 3 legacy/foreign-state helper | PARTIAL; helper-only proof |
| Phase 4 flavor-aware source tests | PASS locally claimed; exact Mac result not independently reproduced |
| Phase 4 both schemes and final binary in CI | FAIL |
| Phase 4 gated release artifact | FAIL |
| Phase 4 real-device flavor transitions | NOT YET TESTED |
| Phase-5 preflight/matrix | BLOCKED |
| W5 release enablement | BLOCKED |

## Panel reconciliation

The reviewers corrected one overstatement from the first pass: raw-token RSSI
code and literals ship, but the writer is not runtime-reachable in production
at this SHA because the native getter is compile-time false outside DIAG. It
becomes an enablement blocker, not a current production compromise.

The flavor-wipe branch is likewise not a current cross-flavor compromise:
production and diag use different bundle identifiers and defaults domains.
Under those configurations the foreign-stamp branch is redundant/unreachable;
the direct unit test proves the delete helper, not `reconcileStateStamp`'s
trigger. Narrow the claim and test whichever same-bundle/legacy scenario is
actually supported.

There is no substantive disagreement on the stop decision.

## Required next Mac checkpoint

1. Make a docs-only privacy correction first; propose, but do not autonomously
   force-push, any history-redaction plan.
2. Finish the Phase-1 current-alias/result path and executable tests.
3. Finish every mandated Phase-2 event, the actual fault-control path, and the
   shared run/restoration mechanism.
4. Replace/harden all evidence writers and add locked/rotation/attribute tests.
5. Wire both schemes and final-binary controls into CI; gate artifact upload.
6. Keep corrections in reviewable, separable commits. Run the complete suite,
   push a new exact SHA, and stop for another blinded panel review.
7. Only after that review may the Mac run the one-phone log-integrity preflight.
   If it fails, stop; do not begin Cases 1–4.

PR #11 stays frozen. No merge, deploy, fast-forward, implementation-branch
mirror, or physical-device action is authorized by this review.
