# W5 native integration — independent audit of `dfb4b99` (2026-07-31)

**Verifier:** Kimi (Linux-side second opinion), auditing the Task #6 completion report against
`dfb4b99` (PR #9 head, `fix/w5-encounter-lease`).
**Method:** static review of the commit and git/PR/CI state; full Dart suite executed locally in a
clean worktree; native test bundle **not** executed here (no Xcode on Linux). Line numbers are
approximate — verify against the commit before quoting elsewhere.

## Verdict

The Task #6 report is **accurate in substance**. Every checkable claim verified except one partial
("CA5E untouched" — see C2) and one numeric slip (C1). No code defects found by static review.
The two self-corrections in the report (ReleaseIsolationTests registration, in-memory-only scope)
are both genuine. Five gaps worth fixing are listed below — F1/F2 are real CI-holes, F3 is an
active decision, F4/F5 are housekeeping.

## Claims verified

| # | Claim | Evidence at `dfb4b99` |
|---|-------|----------------------|
| 1 | `dfb4b99` pushed, PR #9 updated | `headRefOid` on PR #9 == `dfb4b999…`; PR open/draft/mergeable, updated 07:41:51Z |
| 2 | W5LinkController, own file, minimal BackgroundBeacon churn | `ios/Runner/W5LinkController.swift` new; commit touches 3 iOS files only (+788/−17) |
| 3 | CA6E registered `[.notify, .write]` alongside CA7E/CA5E | BackgroundBeacon diff: `service.characteristics = [char /* CA7E */, keepalive /* CA5E */, control]` |
| 4 | HELLO after subscribe-confirm; fresh 128-bit linkId; candidate; current+prev alias; HELLO_ACK by notify | `controlSubscribeConfirmed` (W5LinkController.swift:156) sends `.hello(linkId: mintHex() /* 16B SecRandom */, … currentAlias, prevAlias)`; `helloAck` via `notifyControl` |
| 5 | All five control frames decoded + dispatched with physical source identity | W5Codec.swift:22-26 (`propose 0x03` … `bye 0x07`); `w5Decode` (188-226); `feedPropose` passes `sourceHandle` (`out:`/`in:`+UUID) + `sourceRole` |
| 6 | 120 s grace, 8 s retransmit | W5LinkController.swift:55-56 (`reconnectGrace = 120`, `retransmit = 8`) |
| 7 | Role-correct effects | `closeOutbound` → `cancelPeripheralConnection`; `rejectInbound` → REJECT notify ("a peripheral cannot cancel a CBCentral") |
| 8 | In-band ALIAS_ROLL on rotation; rolls update oracle alias table + session token | `reconfigureAdvertising` → `advertisedTokenChanged` (BackgroundBeacon.swift:391); `ownership.onAliasRoll` + `w5UpdateSessionToken` |
| 9 | Legacy fallback is executable | No-CA6E → `w5c-legacy` path; MTU guards both directions (`maximumWriteValueLength(for:)`, `maximumUpdateValueLength` vs `kW5MaxFrame`) |
| 10 | RSSI root cause + fix; zero Dart changes | Old path: 500-entry UserDefaults buffer (BackgroundBeacon.swift:71). New: `w5_rssi_log.jsonl`, 4 MB cap, trim-half at line boundary, same drain/ack channel (UD first, then file; snapshot-offset acking; at-least-once). Commit touches no `.dart` files |
| 11 | ReleaseIsolationTests correction is real | pbxproj diff adds PBXBuildFile + PBXFileReference + RunnerTests Sources-phase entry; correction comment posted on PR #9 (07:41:51Z) |
| 12 | Diag writer absent from production builds | `#if INRANGE_DIAG`; the flag appears in `SWIFT_ACTIVE_COMPILATION_CONDITIONS` only in `Debug-diag`/`Release-diag`/`Profile-diag` (bundle id `io.inrange.inRange.diag`) |
| 13 | Ownership in-memory only; restoration schema absent | Header comment (W5LinkController.swift:17); no persistence writes in W5Ownership.swift |
| 14 | Flag-gated end-to-end | `INRANGE_W5_LINKS` dart-define → `setW5Links` → `bb.w5links`; every `w5Link` entry point gated by `w5LinksEnabled` |
| 15 | IDs cross the adapter as 16-byte lowercase hex | `hex()` `%02x`; `hexToData` requires `hex.count == 32` |

**Independent executable gates added by this audit:**

- Dart suite at `dfb4b99` in a clean Linux worktree: **201/201 passed** (worktree removed after).
- Public-fork CI (`hazypiff/in-range`, run `30644943496`): **analyze + test green** — the first
  GitHub-side gate on this commit (inrangeai CI is billing-blocked; see F3).
- Fork iOS build (`30645041806`, manually dispatched — see F1): **green** — the native
  integration compiles in release on a clean macOS runner. Note it is compile+package only,
  no test execution (see F2).

## Corrections to the report (both minor)

- **C1.** `W5LinkController.swift` is **684 lines**, not "~530".
- **C2.** "CA5E keepalive is UNTOUCHED" is behaviorally true (cadence and notify path unchanged)
  but textually false: `didReceiveWrite` was edited to route CA6E (accept predicate widened to
  `!= keepalive && != control → fail`; keepalive guard added). Benign — but future reports should
  say "behavior preserved", not "untouched".

## Gaps / recommended fixes

- **F1 — `ios-build.yml` never runs on PR branches.** It triggers only on `push` to `main` (path-filtered) and `workflow_dispatch`, so PR-class Swift work gets no automatic compile gate before human review. Add `pull_request:` (or a branch pattern) to the trigger. For this audit the build had to be dispatched by hand.
- **F2 — `RunnerTests` never execute in CI.** `ios-build.yml` only builds and packages an unsigned IPA. The "30/30" native bundle has zero CI corroboration; every native-green claim rests on one Mac simulator run. Add an `xcodebuild test` step (simulator destination) to `ios-build.yml` or a sibling workflow.
- **F3 — inrangeai CI is zero-signal, not red-on-code.** All recent runs fail with "job was not started because recent account payments have failed" — no runner, no steps. Until billing propagates, the only GitHub-side gates are (a) the public fork's free minutes — the branch was pushed there at hazypiff's explicit instruction on 2026-07-31 and CI is green — and (b) local runs. Decide: keep fork-CI as the interim gate, or re-run inrangeai CI after billing clears. Treat the W5 design as public from the fork push onward.
- **F4 — the review trail exists only on the Mac, uncommitted.** `docs/ISSUES_AUDIT_2026-07-31*.md` and its `KIMI_REVIEW` are absent from both repos on every ref checked (`origin/main`, `hazypiff/main`, this branch). Commit them somewhere (this branch or a docs branch) so the audit/review history survives the Mac session.
- **F5 — housekeeping (non-blocking).** `hazypiff/in-range` main is ~8 commits behind; the Linux checkout's main is 3 behind `origin/main`; stray worktree `/tmp/in-range-pr9-r6.GB9b2U` at `602cbc7` remains from the round-6 review — remove when done with it.

## Still unverifiable from Linux (consistent with the report's own honesty)

- 30/30 native bundle (needs Xcode). Registration is real; the pass claim is unverified here.
- All hardware acceptance: rotation/churn/3-phone/cold repeats/overnight soak (diag flavor), iPhone-13-side soak readout, #8 upgrade-over-diag install.
- Persisted restoration schema (design §Restoration) — tracked as Task #8.

## Process notes

- hazypiff queue unchanged since the report: round-7 review of v5.2+, `prevAlias` ratification
  (question posted on PR #9 at 05:38:31Z), responses to PR #5/#6 reviews. No hazypiff activity on
  PR #9 since the round-6 comment (03:27:45Z).
