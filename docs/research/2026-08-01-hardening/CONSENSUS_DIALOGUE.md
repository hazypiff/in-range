# Consensus dialogue — hardening audit 2026-08-01

> **Post-sign-off status:** this dialogue records the exact consensus reached for commit `d1b8c38`.
> The report was substantively amended at `c5398e7` after production-ledger verification; those changes
> have not been re-confirmed by either external auditor. A later read-only Kimi K3 / Claude Opus round
> found that the final 0063 bytes were never approved and identified its foreign batch-token squat
> residual; the local 0064 repair is also awaiting exact-diff review. Statements below that all four
> Criticals were live are historical and superseded by the amended report's production-severity
> correction. Nothing after `d1b8c38` is signed consensus yet.

Three participants, each with independent tooling and separate scopes:

- **Claude** (coordinator; 7 subordinate reviewers on separate scopes, plus a live production probe)
- **Kimi K3** (`default_model = "kimi-code/k3"`, resumable session `session_7d89f4bc-…`)
- **Codex** (`gpt-5.6-sol`, `model_reasoning_effort = "max"`, read-only sandbox)

The rule for this round: **a recorded disagreement beats a manufactured agreement.** Every participant
was asked to state which findings they re-verified in code versus accepted on presented evidence.

Full transcripts in `transcripts/`. Below is the substance, with the exchange preserved in order.

---

## Round 1 — independent passes

Kimi and Codex each reviewed a scope of their own before seeing the consolidated report, so their first
contributions are genuinely independent rather than reactions.

**Kimi found a Critical the seven-agent Claude panel missed** — `C-SQL-4`, the GPS veto skip:

> The spatial veto executes only when the claim row carries coordinates … for batch-pre-claimed
> (locked-phone) tokens the spatial veto does not execute at all.

Claude verified `0053:179-182` and accepted it. It is independent of `C-SQL-1`: fixing the cross-user
overwrite does not close it.

**Codex found a High the panel and Kimi both missed** — the 120-second reconnect grace is normally
unreachable, because `tokenCacheTTL` (900 s) and `connectRetryFloor` (300 s) both gate the dial before
the lease authority is consulted. Codex rated it Medium; **Claude raised it to High** on the grounds that
the grace is the reason the lease exists and "rotation-during-grace on hardware" is the designated
Phase-5 priority case — if the path is unreachable, the hardware matrix would measure a code path the
app does not normally take.

**Codex independently confirmed `C-W5-2`** (restored peripheral loses both notify-characteristic
references) from a separate scope, same file, same lines, rated CERTAIN. Two models converging on an
identical defect was the strongest single signal of the round.

Codex also challenged a project claim treated as settled — that W5 is "a reactive cascade with no timer":

> The peripheral's notification is emitted immediately in response to the central write … the write-
> confirmation callback then schedules the only next write four seconds later. If iOS suspends the
> process before that delayed block executes, no peer has a future BLE event pending to restart the
> cascade.

Implication recorded: the 10h38m soak may have survived because the phones kept being woken, not because
the design is suspension-proof.

---

## Round 2 — Kimi challenges the consolidated report

Verdict: **AGREED WITH CORRECTIONS.** Kimi refuted two findings outright and overstated-flagged five.

### The error Kimi caught in Claude's own work

> "granted to `authenticated` at `0008:263`, **never revoked**" is false. `0019:2496-2527` revokes ALL on
> `correlate_miles_encounters` from `PUBLIC, anon, authenticated, service_role` … The working file
> records "verified: no later migration revokes it" — that verification is wrong, and the report's own
> methodology caveat even notes the DB shows `proacl = {postgres=X/postgres}` — the report refutes
> itself internally.

**Claude conceded in full.** The grep run was `00[2-6]*`, which excludes 0019. This was an asserted
verification that had not actually been performed, on the exact trap the report warned the panel about
(0019 is later than 0008). Kimi additionally established that the real entry point is
`record_location_ping` at `0040:156` — not the `0019:1159` definition a Claude reviewer cited — and that
it enforces `current_user_can_discover()` and `require_consent(…,'precise_location')`, and returns
`bigint`, killing the "presence oracle" sub-claim.

`C-SQL-2` was **downgraded Critical → High** and its premise rewritten: the defect is missing
evidence-class separation downstream, not an ungated forgery oracle.

Also accepted from Kimi: `C-W5-1`'s *mechanism* was wrong (the `realId` lookup **finds** the encounter and
processes it via the uncommitted path — "treated as fresh" was incorrect), though the executed outcome and
the fix are unchanged, so severity held at Critical. `C-CONSENT-1` → High. `C-SQL-3` bites fully only for
lapsed users. `H-W5-5` is "narrowly alive," not dead code. `H-DIAG-2`'s "cannot fail" was too strong.
And an internal contradiction: the production probe *proves* `verify_jwt` is not being enforced on the
deployed builds, so `H-CFG-1` describing it as "currently true" contradicted Claude's own evidence.

### Claude pushes back on two

Claude disputed `H-PRIV-1` and `H-RT-3`, arguing Kimi had checked adjacent code:

> Your refutation cites `BackgroundLocationCoordinator.swift` — cap 100, `kCLLocationAccuracyThreeKilometers`,
> cleared in `drainBuffer()`. I verified all of that and it is correct **for that file**. But the finding
> is about `SubtleWakeCoordinator.swift` … `bufferCap = 50` (this is where the "50" in the report comes
> from).

and

> You are right that `_drainNativeBuffer` preserves capture time … But the finding is about what happens
> *next*: `rangeEstimator.addObservation` … **has no timestamp parameter at all** and stamps `_now()`
> internally.

### Kimi's adjudication — it conceded one, and corrected Claude on the other

On `H-RT-3` it **withdrew its refutation completely**:

> I withdraw my refutation. You are right. … My earlier pass saw the same lines and mislabeled it
> "deliberate late-evidence design" … I endorsed that mislabeling in round 1 — that was the error, and
> it's mine.

On `H-PRIV-1` it conceded the file but **corrected two of Claude's supporting claims**:

> "Dart's `drainBufferedWakes` returns early unless `isSupported`" — **false.** I read the body:
> `subtle_wake_service.dart:306-346` checks only `_platform != TargetPlatform.iOS` … The drain is
> flag-blind. … **"No path ever clears it" should be struck.**

**Claude verified and conceded.** `drainBufferedWakes` checks only the platform; the handler is
registered in the constructor; the ack fires for every entry including malformed ones. The finding was
rewritten to "cleared only via the Dart drain+ack path; entries buffered while engine-less persist until
the next engine run, with no age bound," and Claude had already independently conceded that SLC/`CLVisit`
coordinates are place-level rather than "raw GPS."

**Severity: Kimi said Medium, Claude had said High. Claude moved to Medium** — with the clear-on-launch
path established and the precision claim corrected, the factual basis for High was gone.

---

## Net effect of the dialogue

Corrections that only happened because the panel argued:

| Finding | Before | After | Who moved |
|---|---|---|---|
| C-SQL-2 | Critical, "never revoked" | High, premise rewritten | Claude conceded to Kimi |
| C-W5-1 | Critical, wrong mechanism | Critical, mechanism rewritten | Claude conceded to Kimi |
| C-CONSENT-1 | Critical | High | Claude conceded to Kimi |
| H-PRIV-1 | High, "never cleared" | Medium, rewritten | Both moved; Kimi conceded file, Claude conceded severity |
| H-RT-3 | High | High, sharpened | Kimi withdrew its refutation |
| H-W5-6 (grace unreachable) | Medium (Codex) | High | Claude raised Codex's rating |
| C-SQL-4 (veto skip) | not found | Critical | Kimi found it |

Three of the panel's members each found something the others missed, and three findings were corrected
or downgraded that a single reviewer would have shipped wrong.

---

## Round 3 — Codex challenges the report, and corrects Claude twice

Verdict: Codex found most of what was wrong with **Claude's own work**.

### Codex caught Claude citing its own tooling as repository evidence

> At audited W5 HEAD there is no `zz_probe_test.dart`, and no such file appears in `git log --all`.

**Claude verified and conceded.** The worktree is clean, `git ls-files` lists 8 tracked files in that
directory, and the file does not exist. It was a **temporary artifact created by one of this audit's own
subagents**, observed mid-run and mistaken for committed code before that agent deleted it.

Codex then located the real record — `claude_kimi_chat_2026-07-31.md:386` naming
`/tmp/kimi-r8/…/w5_ownership_r8_kimi_test.dart`, 26 tests, "259/259" — which makes the finding *stronger*:
**26 probes cited as sign-off evidence, zero committed**, not "roughly 20 of 26." Claude's 233 baseline
survives, having been measured before the artifact existed.

### Codex settled the one direct Kimi-vs-Codex conflict

Kimi's proposed fix for the reciprocity window — compare reverse `received_at` to *forward*
`received_at` — was refuted as a no-op:

> Because the current forward row is upserted with `received_at=now()` immediately before correlation at
> 0053:122, comparing reverse receipt time to forward receipt time is effectively the existing predicate.

Claude verified `0053:119`, `:123`, `:138` and ruled for Codex. **Kimi accepted in round 4:**

> I accept; my proposed comparison was a no-op. Verified myself … Codex's redirect is correct.

Kimi also salvaged the two parts of its fix that survive independently: bind `p_observed_at` to the
token's validity slot, and stop refreshing `received_at` on weaker-RSSI upserts.

### Codex caught the report overstating its own evidence

> The working file has no dedicated sections for most summarized High findings … The "two tests" section
> actually lists three.

Both accurate; both fixed.

### The severity argument that reshaped the report

Codex argued `C-W5-1/2/3` and `C-RT-1` are **High, not Critical**, because `INRANGE_W5_LINKS` is
default-off on an unreleased branch — merge blockers, not live compromises. Claude adopted it: in a report
whose top finding is a live unauthenticated production endpoint, *Critical* should mean **exploitable
now**. Kimi agreed and said why its own rating had been wrong:

> My Critical rating of the W5 class did not weigh the flag, and it should have … the same discipline I
> applied when I argued C-CONSENT-1 down on flag-gating grounds.

---

## Round 4 — final verdicts

- **Codex: `CONSENSUS: AGREED`** — no remaining disagreements.
- **Kimi: `CONSENSUS: AGREED`** — "No remaining disagreements. The report as amended … has my
  co-signature."

## Final disagreement ledger

| Finding | Before | After | Who moved, and to whom |
|---|---|---|---|
| C-SQL-2 → H-SQL-2 | Critical, "never revoked" | High, premise rewritten | Claude → Kimi (Claude's own verification error) |
| H-ORCH-1 | "~20 of 26 lost, 6 committed" | 26 cited, **0** committed | Claude → Codex (Claude cited its own subagent's artifact) |
| H-SQL-3 fix | compare receipt times | compare **capture** times + bind to token validity | Kimi → Codex |
| C-W5-1/2/3 | Critical | High / merge-blocking | Claude + Kimi → Codex |
| C-RT-1 → H-RT-1 | Critical | High | Claude + Kimi → Codex |
| C-W5-1 mechanism | "treated as fresh" | uncommitted-path processing | Claude → Kimi |
| C-CONSENT-1 | Critical | High | Claude → Kimi |
| H-SQL-4 | High | Medium | Claude → Codex |
| H-PRIV-1 | High, "never cleared" | Medium, rewritten | Kimi conceded file; Claude conceded severity + clear path |
| H-RT-3 | High | High, sharpened | Kimi withdrew its own refutation |
| H-W5-5 (grace) | not found | High | Codex found it; Claude raised it above Codex's own rating |
| C-SQL-4 (veto skip) | not found | Critical | Kimi found it |

**Every participant was corrected by another, and every participant corrected someone.** Three findings
would have shipped wrong from any single reviewer; two Criticals would have been missed entirely.

---

## Round 5 — owner review, and Codex blocks the sign-off

The owner reviewed the signed report and caught two internal inconsistencies the whole panel had missed:
"five Criticals, all live" conflicted with W5 being an unreleased default-off branch, and "four SQL
Criticals" did not match an enumerated list containing three. Claude amended, and both auditors were asked
to re-confirm because the amendments touched a signed document.

**Kimi: NOT RECONFIRMED**, on one residual — Claude had fixed the verdict sentence but left the section
heading reading "three tests that would have caught four Criticals," contradicting the amended text two
screens earlier. Fixed; Kimi then **RECONFIRMED**.

**Codex: NOT RECONFIRMED**, on six, and the first two were decisive:

> `INRANGE_W5_LINKS` only supplies the value Dart later writes to `bb.w5links`; all native W5/state-machine
> paths use that same persisted bool, so stale `true` reactivates both C-DIAG-1 and the H-W5 defects
> before Dart. Also: the report still says "CRITICAL — live today"; `W5LinkController.swift` exists only
> on unmerged PR #9, so "present in shipped artifacts" is unestablished.

**Claude verified and conceded both.** `git ls-tree main --name-only ios/Runner/` returns no W5 files —
`W5LinkController.swift` is branch-only, so **no shipped binary writes `w5_rssi_log.jsonl` today**. The
Critical rating rested on "present in shipped artifacts," which was never established. C-DIAG-1 was
demoted to **H-DIAG-1 (merge-blocking)** and the Critical tier dropped from five to **four, all
server-side and all live**.

Codex's first point survived separately and became a new finding: `bb.w5links` **does** exist on `main`
(`BackgroundBeacon.swift:88, 92, 880, 1034, 1103`), and native code reads the persisted bool rather than
the build flag — so "the feature is default-off" is a weaker guarantee than it reads, and a stale `true`
re-activates shipped native paths before Dart attaches. Recorded as **H-DIAG-4**.

Its remaining four objections were also upheld and fixed: the cron and 0020–0062 caveats were not marked
"unverified, not cleared" as required; the Mac work order mislabelled H-W5-4/6/7 as H-W5-3/4/5, omitted
H-W5-5 (the unreachable reconnect grace) entirely, and still referenced `C-RT-1`; and
`verified_findings_working.md` retained pre-downgrade labels, the refuted C-W5-1 mechanism, and the
obsolete H-ORCH-1 counts. That file now opens with a superseding amendment table rather than being
rewritten, so the corrections stay auditable.

**Note on the labels used earlier in this document.** Rounds 1–4 above refer to `C-DIAG-1`, `C-W5-1/2/3`,
`C-SQL-2`, `C-RT-1` and `C-CONSENT-1`. Those were the labels in play at the time and are left unchanged;
the mapping to their final identifiers is in the amendment table at the top of
`verified_findings_working.md`.

**Historical final state at `d1b8c38`: four Criticals, all described as server-side and live. Both
auditors re-confirmed that text. Superseded after sign-off by `c5398e7`; the amended text is not yet
re-signed.**
