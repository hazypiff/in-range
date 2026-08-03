# Mac hardening — owner exit packet

**Status: COMPLETE — both Stage-3 signers SAFE at `98279de`.** No push / PR /
comment / merge / deploy performed. Everything is local on
`integ/mac-hardening-2026-08-01`, awaiting owner authorization.

**Consensus (both signers reviewed the exact same final SHA `98279de`):**
- Kimi (ownership/protocol): `SAFE AT 98279de FOR MAC HARDENING SCOPE`.
- Codex (restoration/release-isolation): `SAFE AT 98279de FOR MAC HARDENING SCOPE`,
  with the sendWakePing bearer explicitly logged as an accepted owner decision,
  not represented as fixed.

## 1. SHAs / worktree

- Base (PR #9 head): `810875a`
- Integration branch: `integ/mac-hardening-2026-08-01`
- **Final head under review: `98279de40ec04b40e76a8acc016ca5e9d6566f78`**
- Worktree clean except two unrelated untracked audit docs
  (`docs/ISSUES_AUDIT_2026-07-31*.md`).
- Ancestry proven: `810875a` + the four persistence commits
  (`13733ef 4583864 84a6b49 8355c41`) are all ancestors of the final head.

## 2. Commits created (on top of the integrated base)

| SHA | Findings | Summary |
|---|---|---|
| `e39bdb2` | H-W5-1 | realId hoisted above committed branch; winner stored at commit |
| `1daaaed` | H-W5-5 | in-grace leases bypass token cache + retry floor |
| `5fba7c0` | H-W5-2, H-W5-3 | restoration notify rebind; pre-HELLO_ACK disconnect → onDialFailed + TTL sweep |
| `31f133b` | H-DIAG-1/2/3/4 | W5 compile-gated; schema stamp; build-settings guard + CI; hardened log writes |
| `e022eaf` | H-W5-6 + parity | dropPeer→onTeardown; Dart effect order sorted to match Swift; 6 vector entry points + route identity + 2 vectors |
| `98279de` | Stage-2 panel fixes | Codex NOT-SAFE items (service removal, legacy-stamp adopt, non-trapping legacy log writes, fail-closed guard) + Kimi D1/D2 |

## 3. Finding disposition (at `98279de`)

| Finding | Severity | Disposition |
|---|---|---|
| H-W5-1 | High/merge-block | FIXED (both oracles + persistence + regression) |
| H-W5-2 | High/merge-block | FIXED — rebind + service-removal on rebuild (native; HW case 3) |
| H-W5-3 | High/merge-block | FIXED — onDialFailed routing + TTL sweep |
| H-W5-4 | Medium | REVIEWED + integrated (persistence commits) |
| H-W5-5 | High | FIXED (logic; discovery bypass = HW case 2) |
| H-W5-6 | Medium | FIXED — dropPeer→onTeardown |
| H-W5-7 | Medium | **OWNER ITEM** — candidate keyed by alias; re-key is high-risk on the working election; not attempted |
| H-DIAG-1 | High/merge-block | FIXED — `w5LinksEnabled` compile-gated false in production |
| H-DIAG-2 | High | FIXED — fail-closed build-settings guard + CI + populated diag `<Testables>` |
| H-DIAG-3 | High | FIXED (schema stamp, legacy-adopt); **sendWakePing gating = OWNER DECISION** |
| H-DIAG-4 | High/shipped | FIXED — same gate + stamp |
| effect ordering | latent x-lang | FIXED — Dart sorts by handle; vector 7 pins it |
| vector gaps | High | FIXED — 6 entry points, route identity, 8 vectors; R8-F1 pair confirmed present |
| H-ORCH-1 | High | FIXED (prior `810875a`) — 9 reconstructed probes committed |

## 4. Test evidence (exact, at `98279de`)

- `flutter analyze`: **No issues found.**
- `flutter test` (full repo): **249 passed, 0 failed.**
- `xcodebuild test … -only-testing:RunnerTests` (iPhone 17 sim, Debug):
  **`** TEST SUCCEEDED **`** (43 cases: ownership 26, vectors 1, codec 5,
  isolation 5, stub).
- `scripts/check_release_isolation.sh`: Release ✓ / Profile ✓ / Release-diag ✓
  (positive control), fail-closed on query error.
- Production `flutter build ios --release`: green; `strings Runner` → 0 hits
  for `bb_wake_log` / `INRANGE_DIAG` (verified pre-Stage-2; re-run advised
  post-merge).

## 5. Panel

- **Round 1 (Stage 1–2):** Kimi (ownership) = SAFE at e022eaf + D1/D2; Codex
  (isolation) = NOT SAFE at e022eaf, 5 items. All actionable items folded into
  `98279de`.
- **Round 2 (Stage 3, at `98279de`):**
  - **Kimi (ownership): `SAFE AT 98279de FOR MAC HARDENING SCOPE`** — D1 (both
    languages) + D2 verified applied; `committedWinner` confirmed cleared on
    every keeper-ending path (onLinkDown, teardown, saturate, beaconOff,
    graceExpiry); Stage-2 changes confirmed outside the ownership oracle (no
    regression); no new ownership defect.
  - **Codex (isolation): `SAFE AT 98279de FOR MAC HARDENING SCOPE`** — all five
    prior NOT-SAFE items verified-in-code: (1) willRestoreState now
    `removeAllServices` + clears both notify refs before rebuild; (2)
    reconcileStateStamp adopts a nil legacy stamp (upgrading production user
    NOT wiped), wipes only on a different non-nil stamp; (4) the guard
    captures xcodebuild failure separately and fail-closes on it; (5) both
    legacy <13.4 log branches off trapping `FileHandle.write`. Item (3)
    sendWakePing bearer "explicitly recorded as an accepted owner decision
    rather than represented as fixed." Note: Codex's sandbox could not run
    Xcode, so its script run hit the QUERY-FAIL branch and exited 1 — which
    independently demonstrates the fail-closed behavior; the Mac's real-machine
    run shows the safe (absent-setting) branch passing with the positive
    control. Both are consistent.

### Disagreement ledger

| # | Item | Positions | Status |
|---|---|---|---|
| DL-1 | sendWakePing stale bearer | Codex: schema-wipe insufficient, wants gating/expiry. Mac: it is crack #1 (issue #4), a production feature; gating breaks it. | **RESOLVED (owner, 2026-08-03)** |
| DL-2 | HELLO_ACK prevAlias wire field | Mac: not needed given candidate-stability rule. | **RESOLVED (owner, 2026-08-03)** |
| DL-3 | H-W5-7 candidate identity | Finding: "narrowly alive." Mac: re-key high-risk, deferred. | **RESOLVED (owner, 2026-08-03)** |

### Owner decisions (2026-08-03)

- **DL-1 → KEEP `sendWakePing` in this integration; do NOT compile-gate the
  production feature.** Scheduled **P1 follow-up** (separate work): JWT `exp`
  validation with clock-skew tolerance; credential clearing on
  sign-out / account change; credential clearing after a 401/403. Tracked
  below in §8.
- **DL-2 → CONFIRMED: no `prevAlias` in `HELLO_ACK`.** The v1 wire contract is
  unchanged (Dart + Swift). Retain the candidate-stability rule. Should DL-3
  later prove ACK needs `prevAlias`, introduce it ONLY as a versioned codec
  change with shared vectors and v1 fallback.
- **DL-3 → DEFER the H-W5-7 re-key from this integration, and make it a W5
  RELEASE-ENABLEMENT GATE.** `30619a1` treats per-alias candidates as the
  defense against cross-peer commit hijacking; re-key to stable identity only
  after a focused design + test proves stable identity without candidate
  reuse. The three-phone matrix must cover **lost `ALIAS_ROLL` + rotation
  during grace**.

## 6. Hardware matrix — RUN 2026-08-03, all four cases PASS

Diag flavor (instrumented, `f989231`), 3 iPhones (14, 13, 15 Pro Max substituted
for the 15 Plus — registered a device slot). Sanitized attributed logs in
`hardware_evidence/`. Final Kimi review `fb9b38ff`: gate MET; instrumentation
release-safe (confirmed from code + CI); delay hook cannot mask a leak.

| Case | Fix | Result |
|---|---|---|
| 1 — third peer / concurrency | H-W5-3 | **PASS (surrogate)** — 0 pendingdial-ttl + simultaneous-open race resolved cleanly across 4s-delayed windows; literal C-in-delay-window instant NOT staged (honestly qualified) |
| 2 — grace reconnect + rotation | H-W5-5 / DL-3 | **PASS (full)** — drop + rotation(f0a381→c0500b) + ALIAS_ROLL suppressed + prevAlias rejoin ~73s (<120s); rekey confirmed (Kimi + committed vector) |
| 3 — iOS state restoration | H-W5-2 | **PASS (full)** — devicectl system-kill → willRestoreState (w5-restored-periph n=1) → both notify chars recovered + re-subscribed → session re-committed |
| 4 — reject → no redial | H-W5-6 | **PASS (full)** — w5c-ended lease erase, 0 redial (2-phone isolation) |

Bonus field-verified: H-DIAG-3 `state-stamp-adopted-legacy` on device.

## 6b. Still owed / unverified

1. Case 1 literal instant (surrogate accepted per Kimi; deterministic re-run
   available via the delay hook if the criterion demands the exact staged moment).
2. Clean-install + upgrade-from-diagnostic tests (real devices) for H-DIAG-3
   legacy-adopt.
3. Linux SQL/audit packet (0063/0064) — separate track, owner/prod only.

## 7. Owner actions — RESOLVED 2026-08-03

1. DL-1/DL-2/DL-3 decided (see ledger above).
2. **Push authorized:** `integ/mac-hardening-2026-08-01` → both remotes; open a
   **fresh stacked draft PR based on `fix/w5-encounter-lease`** (exposes only
   the integration delta). **PR #9 left untouched — no fast-forward.** No merge
   until the exact branch is reviewed AND the three-iPhone matrix passes.

## 8. Scheduled follow-ups (post-integration, not in this branch)

- **P1 — sendWakePing credential lifecycle (DL-1):** JWT `exp` validation with
  clock-skew tolerance; clear `bb.pingAuth`/`bb.pingUrl` on sign-out and
  account change; clear after a 401/403 response.
- **W5 release-enablement gate (DL-3):** focused design + test that stable
  encounter identity holds without per-alias candidate reuse (no cross-peer
  commit hijack), before any re-key; three-phone matrix must include lost
  `ALIAS_ROLL` + rotation-during-grace.
- **Three-iPhone hardware matrix** (§6.1) when phones are cabled.
- **Clean-install + upgrade-from-diagnostic** device tests for the H-DIAG-3
  legacy-adopt path.
