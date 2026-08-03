# Mac hardening evidence packet — 2026-08-01

Prepared for the blinded LLM panel and the owner exit. **No push / PR / comment /
merge / deploy performed** — per MAC_AGENT_PANEL_WORK_ORDER §Exit.

## 1. SHAs and worktree

- Base (PR #9 head): `810875a9b33ed2ff3a9ec226d67b8f429c589007`
- Integration branch: `integ/mac-hardening-2026-08-01`
- Head under review: `e022eaf0943ea3324641c4d51707c2b9e5b4c201`
- Worktree: clean except two untracked pre-existing audit docs
  (`docs/ISSUES_AUDIT_2026-07-31*.md`), not part of this work.
- Ancestry proven: `810875a` (PR #9 probes) and all four persistence commits
  (`13733ef 4583864 84a6b49 8355c41`) are ancestors of head.

## 2. Commits created (on top of the integrated base)

| SHA | Finding | Summary |
|---|---|---|
| `e39bdb2` | H-W5-1 | realId resolves before the committed branch; winner stored at commit (both oracles); persisted in snapshot |
| `1daaaed` | H-W5-5 | in-grace leases bypass the 15-min token cache + 5-min retry floor |
| `5fba7c0` | H-W5-2, H-W5-3 | restoration re-binds both notify chars; pre-HELLO_ACK disconnect → onDialFailed + pendingDial TTL sweep |
| `31f133b` | H-DIAG-1/2/3/4 | W5 link layer compile-gated (`#if INRANGE_DIAG`, else false); flavor/schema stamp wipes foreign bb.* on boot; build-settings isolation guard + CI step + populated diag `<Testables>`; non-trapping/backup-excluded/file-protected log writes |
| `e022eaf` | H-W5-6 + parity | dropPeer routes through onTeardown; Dart effect order sorted to match Swift; 6 vector entry points + route identity + 2 new vectors |

## 3. Finding-by-finding status

| Finding | Severity | Status | Evidence |
|---|---|---|---|
| H-W5-1 | High / merge-block | **FIXED** | `w5_ownership.dart` realId hoist + `committedWinner`; Swift mirror; probe `realId-resolved committed encounter keeps its sticky keeper` (Dart+Swift) |
| H-W5-2 | High / merge-block | **FIXED** (native, HW-verified) | `BackgroundBeacon.swift` willRestoreState re-binds `controlNotifyChar`/`keepaliveNotifyChar`, forces rebuild if absent. Unit-untestable (CB); covered by restoration hardware case 3 |
| H-W5-3 | High / merge-block | **FIXED** | `linkDown` routes un-established → `onDialFailed`; 20 s pendingDial TTL sweep on scan cadence. Dart probe `unestablished pending dial is reclaimed`; native sweep by HW case 1 |
| H-W5-4 | Medium | **REVIEWED + integrated** | the four persistence commits verified against integrated ownership; snapshot round-trip incl. committedWinner (native test) |
| H-W5-5 | High | **FIXED** (logic) | `isInGrace` + `wantsGraceRecovery`; didDiscover bypass on both paths. Grace-lifecycle probe (Dart+Swift); discovery bypass by HW case 2 |
| H-W5-6 | Medium | **FIXED** | `dropPeer(alias:)` → `onTeardown` erases lease + closes both roles; vector 4/7 pin teardown closes |
| H-W5-7 | Medium | **PANEL ITEM** | candidate keyed by alias; re-keying to stable identity is high-risk on the working election — not attempted this round, flagged for decision |
| H-DIAG-1 | High / merge-block | **FIXED** | `w5LinksEnabled` `#if INRANGE_DIAG … #else false` |
| H-DIAG-2 | High | **FIXED** | `scripts/check_release_isolation.sh` (build-settings, positive control); CI step; diag `<Testables>` populated |
| H-DIAG-3 | High | **FIXED (schema stamp)**; sendWakePing gating **DECLINED** | `reconcileStateStamp()` wipes foreign bb.* pre-restoration. Did NOT `#if`-gate sendWakePing — it is crack #1 (issue #4), a production feature; stamp closes the stale-credential vector. **Panel/owner disagreement flagged.** |
| H-DIAG-4 | High / affects shipped | **FIXED** | same compile-gate + stamp; native no longer trusts the bare persisted bool |
| effect ordering | latent cross-lang | **FIXED** | Dart sorts by handle (maybeCommit + routes); vector 7 pins ≥3-link order across both |
| vector gaps | High | **FIXED** | 6 entry points added to both runners; route-identity assertions; R8-F1 pair confirmed present (vectors 5+6); now 8 vectors |
| H-ORCH-1 | High | **FIXED (prior commit 810875a)** | 9 reconstructed probes committed; process rule adopted |

## 4. Test evidence (exact, at `e022eaf`)

- `flutter analyze`: **No issues found**.
- `flutter test` (full repo): **249 passed, 0 failed**.
- Beacon suites alone: 73 (ownership 26 + probes 11 + vectors 8 + others).
- `xcodebuild test … -only-testing:RunnerTests` (iPhone 17 sim, Debug):
  **`** TEST SUCCEEDED **`, 42 cases, 0 failures** (ownership 26, vectors 1,
  codec 5, isolation 4, stub).
- `scripts/check_release_isolation.sh`: Release ✓ no INRANGE_DIAG, Profile ✓ no
  INRANGE_DIAG, Release-diag ✓ carries it (positive control passes).
- Production `flutter build ios --release`: **green**; `strings Runner` → **0**
  hits for `bb_wake_log` or `INRANGE_DIAG`.
- Committed test paths: `test/features/beacon/w5_ownership_probes_test.dart`,
  `…/w5_ownership_vectors_test.dart`, `…/w5_ownership_vectors.json`,
  `ios/RunnerTests/{W5OwnershipTests,W5OwnershipVectorTests,ReleaseIsolationTests}.swift`.

## 5. Three-iPhone hardware matrix — NOT RUN (phones uncabled)

Fleet confirmed in `devicectl` (iPhone 14, iPhone 13, iPhone 15 Plus), all
`unavailable`/uncabled at run time. The four matrix cases (3rd peer mid-dial;
keeper-drop+rotate+reconnect <120 s; restoration with committed lease +
stale-gen; rejection prevents redial) are **owed** and are the gate items that
turn the native-only fixes (H-W5-2, the H-W5-5 discovery bypass, the H-W5-3
sweep) from logic-verified to behavior-verified.

## 6. Unverified / owed

- Hardware matrix above (needs phones cabled).
- H-W5-7 decision.
- H-DIAG-3 sendWakePing gating (owner call: is the schema-stamp wipe sufficient,
  or should crack #1's pre-Dart ping be additionally gated?).
- HELLO_ACK `prevAlias` wire question (H-W5-1 belt): not added; rationale in the
  commit — panel to confirm the candidate-stability argument.
- Linux SQL/audit packet (0063+0064) — separate review track, owner/prod only.
