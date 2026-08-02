# Mac agent + LLM panel dispatch — hardening continuation, 2026-08-01

This is the current dispatch. It supplements the longer `MAC_AGENT_WORK_ORDER.md`; where they differ,
this file wins. Do not infer authority to deploy, merge, push, post to GitHub, erase devices, or change
production. Prepare reviewed local commits and an evidence packet for the owner.

## Authority and current state

- Production's only verified live Critical, C-PROD-1, was fixed and re-probed. Do not redeploy it.
- Production is at migrations 0001–0055 + 0062. The pending server work must be an ordered 0056→0064
  batch and remains Linux/owner territory.
- The hardening report's signatures cover `d1b8c38` only. Its later text is amended and not re-signed.
- PR #9 is a draft and must not merge. Its current remote head is
  `810875a9b33ed2ff3a9ec226d67b8f429c589007`.
- `origin/feat/w5-lease-persistence` is a sibling branch at
  `8355c41c6919eb33c046ac6d8df1d7f8131da552`. It forks at `30619a1` and therefore does **not** contain
  PR #9's reconstructed-probe commit `810875a`.
- Linux round-2 changes are on an uncommitted, unpushed `fix/hardening-linux-round-2` working tree. Do
  not claim to have reviewed them until an exact diff or commit is actually supplied.

## Preflight — record before changing anything

1. Record `git status --short --branch`, `git rev-parse HEAD`, and `git branch -vv`.
2. Fetch remotes, but do not reset or force-update any branch.
3. Confirm the two remote heads and their merge-base:
   `origin/fix/w5-encounter-lease`, `origin/feat/w5-lease-persistence`, and `30619a1`.
4. Inventory committed tests with `git ls-files`; a temporary or untracked probe never counts as
   evidence.
5. Record the attached fleet with `xcrun devicectl list devices` or `xcrun xctrace list devices`.
   Expected iOS fleet: iPhone 14, iPhone 13, iPhone 15 Plus. Stop and report any mismatch; do not erase
   or re-enrol a phone.

## Branch integration — preserve both lines of evidence

Create a new local integration branch from exact PR #9 head `810875a`. Integrate, without rewriting or
dropping, these persistence commits from the sibling branch:

- `13733ef` — ownership snapshot/restore with TTL expiry
- `4583864` — controller persistence and BackgroundBeacon restore wiring
- `84a6b49` — XCTest snapshot/restore, idempotence and expiry coverage
- `8355c41` — restoration persistence documentation

After integration, prove that `810875a` and all four persistence commits are ancestors of the local
head. Resolve conflicts semantically and show the resulting diff to the panel. Do not force-push PR #9.

## Mac implementation queue

Work in this order; every correction needs a regression that is committed beside it.

1. **H-W5-1 — sticky keeper across alias resolution.** Hoist `realId` resolution above the committed
   branch in both Dart and Swift. Decide explicitly whether `HELLO_ACK` needs `prevAlias`; any wire
   change needs version handling and shared codec vectors. Persist the committed winner rather than
   recomputing it from a mutable link map.
2. **H-W5-5 — make 120-second grace reachable before hardware testing.** During bounded W5 recovery,
   bypass or clear the 900-second token cache and 300-second retry floor. Pin rotation-during-grace.
3. **H-W5-2 — restoration notify references.** Rebind `controlNotifyChar` and
   `keepaliveNotifyChar` from the restored service, or force a clean service rebuild if either is absent.
4. **H-W5-3 — pre-HELLO_ACK disconnect.** Route an unestablished outbound disconnect through
   `onDialFailed`, add a bounded `pendingDials` expiry, and prove a third peer can later negotiate.
5. **H-W5-4 — persistence.** Review the four persistence commits above rather than reimplementing them.
   Verify TTL expiry, idempotent restore, stale-generation recovery, and restored-link behaviour against
   the current integrated ownership code.
6. **H-W5-6 / H-W5-7 — teardown and stable candidate identity.** Give `onTeardown` a production caller,
   erase the lease and disconnect inbound keepers on peer rejection, and key the encounter candidate to
   stable encounter identity rather than the rotating alias.
7. **H-DIAG-1 / H-DIAG-4 — release isolation first.** Compile diagnostic W5/log-writing paths out of
   production. A stale persisted `bb.w5links=true` must not reactivate them before Dart attaches. Add a
   flavor/schema stamp and wipe foreign or unstamped `bb.*` state before manager restoration.
8. **H-DIAG-2 / H-DIAG-3 — prove the boundary.** Add Release build-setting checks that fail if
   `INRANGE_DIAG` enters a production configuration, add a real diagnostic positive control, gate the
   pre-Dart wake-ping secret path appropriately, and bound persisted-token validity. Cap/rotate native
   log files, use non-trapping writes, set file protection, and exclude diagnostics from backup.
9. **Shared vector gaps.** Add the missing oracle entry points (`onBeaconOff`, `onDialFailed`,
   `onAliasRoll`, `onPrevAliasExpiry`, `onRetryTimer`, `debugSetViewGen`), use `graceExpiry`, validate
   PROPOSE/ACK route identities instead of wildcards, and make Dart/Swift effect ordering identical.

## Required Mac verification

- `flutter analyze` and the complete committed Flutter suite.
- Swift unit tests on a simulator, including both ownership implementations and shared vectors.
- Production Release build and diagnostic build as separate artifacts.
- `xcodebuild -showBuildSettings` assertions for every production configuration; absence of
  `INRANGE_DIAG` is a build-property check, not merely a Debug runtime assertion.
- A clean-install test and an upgrade-from-diagnostic test proving stale `bb.*` state cannot activate
  release behaviour.
- Restoration test proving both notify characteristics work after relaunch.
- Three-iPhone hardware matrix:
  1. third peer arrives while the first dial is between connect and HELLO_ACK;
  2. keeper disconnects, token rotates, and reconnect succeeds inside 120 seconds;
  3. process restoration with a committed lease and stale-generation inputs;
  4. rejection/teardown prevents any redial.

Capture timestamps, device model/OS, exact build SHA, and sanitized logs for each run. The iPhone 13 was
used in the 2026-07-29 run and is part of the current three-phone fleet. Current hardware does not cover
more than three iOS peers. Android has no W5 implementation and is not a substitute participant.

## LLM panel protocol

The coordinator must enforce these stages; do not collapse them into a group prompt.

### Stage 1 — independent, blinded passes

Give at least two reviewers the same exact evidence packet, but do not show either reviewer the other's
analysis. Record model, session ID, scope, base SHA, head SHA, `git status`, and SHA-256 hashes for any
uncommitted files. Assign one reviewer ownership/protocol correctness and one restoration/release
isolation; both must inspect tests and branch topology.

Each reviewer must label every conclusion as one of:

- verified directly in code or executed output;
- inferred, with the inference stated;
- unverified because evidence or hardware is unavailable.

### Stage 2 — adversarial exchange

Only after both independent memos exist, exchange them. Require each reviewer to identify:

- at least one claim they agree with and independently rechecked;
- every disagreement in mechanism, severity, fix, or test sufficiency;
- any claimed test that is not committed at the reviewed head;
- any patch that would be a no-op, introduce a protocol fork, or only test its own mock.

Keep a disagreement ledger with `OPEN`, `RESOLVED`, or `OWNER DECISION` status. Do not manufacture
consensus; an unresolved disagreement is a valid result.

### Stage 3 — exact-final-patch review

After fixes from Stage 2, regenerate the evidence packet. Both reviewers must review the **new exact
head**, rerun the relevant tests themselves, and state a verdict tied to that SHA. Any code, test, doc,
scheme, project-file, or migration change after a verdict invalidates it until re-confirmed.

Allowed verdicts:

- `SAFE AT <sha> FOR MAC HARDENING SCOPE`
- `SAFE WITH EXACT CHANGES` followed by unresolved required changes
- `NOT SAFE`

Do not write `CONSENSUS: AGREED` unless every named signer has reviewed the same final SHA and exact
report text. Historical sign-off at `d1b8c38` cannot be extended by implication.

### Separate SQL/audit packet when Linux supplies it

Review these exact items together, not 0063 alone:

- `0063_audit_2026_08_01_critical_fixes.sql`
- `0064_token_claim_ownership_repair.sql`
- the expanded T9 in `reciprocity_security_test.sql`
- the complete migration-harness output
- the amended hardening report and disagreement ledger

Challenge specifically: authoritative ownership under flag-off rollout, the generic `22023` choice
versus silent no-op, owner-only repair, concurrent claims/cleanup locking, legal-hold implications, and
proof that the test fails on 0063 before passing on 0064. The Mac panel may recommend; production access
and deployment approval remain owner-only.

## Exit packet to return to the owner

Return one concise packet containing:

1. exact base/head SHAs and a clean/dirty worktree statement;
2. commits integrated and commits created;
3. finding-by-finding status with file/line evidence;
4. test commands, exact counts, and committed test paths;
5. three-iPhone run matrix and sanitized artifacts;
6. both independent panel memos and the disagreement ledger;
7. exact-final verdicts tied to one SHA;
8. anything unverified, especially unavailable hardware or a Linux diff not actually received.

Stop before push, PR comment, merge, or deployment and ask the owner for the next action.
