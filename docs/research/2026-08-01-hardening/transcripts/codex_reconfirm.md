OpenAI Codex v0.146.0
--------
workdir: /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
model: gpt-5.6-sol
provider: openai
approval: never
sandbox: read-only
reasoning effort: max
reasoning summaries: none
session id: 019fbee0-1d56-72f0-ab2f-ae2e09659c98
--------
user
Re-confirmation round. The owner reviewed the signed report and caught internal inconsistencies that we all missed, including me. I have amended the report. Because the amendments touch the signed document, I need your re-confirmation before it is committed and posted.

Report: /home/hazypiff/in-range/docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md

Three amendments, all in the VERDICT / FIX ORDER / SYSTEMIC sections:

**1. The Critical tier was described as homogeneous and it is not.** The old text read "one live in production and remotely exploitable by anyone, four exploitable today by any authenticated user with a modified client." That is wrong: C-SQL-3 (`beacon_token_batch` never purged) is a server-side retention defect that no user exploits — the harm is data at rest — and C-DIAG-1 is a device-local privacy defect in release binaries. Only C-SQL-1 and C-SQL-4 are user-exploitable. The tier is now split three ways: one remotely exploitable (C-PROD-1); two exploitable by an authenticated user with a modified client (C-SQL-1, C-SQL-4); two data-handling defects requiring no attacker (C-SQL-3, C-DIAG-1).

**2. The apparent contradiction between C-DIAG-1 being Critical and the W5 defects being High is now stated explicitly rather than left implicit.** New text: the W5 *feature* is gated by `INRANGE_W5_LINKS`, which is why its correctness defects are merge blockers; C-DIAG-1 is Critical for the opposite reason — `W5LinkController.swift` is *not* behind that compile-time flag, it is behind the persisted `bb.w5links` bool, so the code is compiled into every release binary and a value inherited from a prior diag install re-activates it before Dart can clear it. The severity convention now reads "*Critical* means reachable now — either exploitable today or present in shipped artifacts."

**3. A stale count.** The SYSTEMIC section claimed the three proposed tests "would have caught four Criticals at authoring time." After our downgrades that is false: they catch **two Criticals and one High** — C-SQL-3, C-PROD-1, and H-CONSENT-1 (which we demoted from Critical). Corrected.

Also corrected outside the report, for completeness: the FIX ORDER step 2 no longer says "all live" while including C-DIAG-1; and the Mac work order's stale pre-downgrade labels are fixed (its W5 items now read High/merge-blocking, C-DIAG-1 is marked as the one Critical in that queue, and the C-W5-1 mechanism paragraph now carries Kimi's correction that the `realId` fallback *finds* the encounter and processes it via the uncommitted path rather than treating it as fresh).

No finding was added, removed, or re-rated. This is descriptive accuracy only.

Two caveats are being carried into the PR post verbatim and must remain marked **unverified, not cleared**: (a) the `cron.job` retention schedule, since `0015` wraps `cron.schedule` in an exception-swallowing `DO` block, so a missing row would silently make every retention claim "forever"; and (b) privilege regressions across migrations 0020–0062, since the local container is at 0019.

Reply with one line — `RECONFIRMED` or `NOT RECONFIRMED` — and, if the latter, exactly what is still wrong.

codex
I’m checking the amended passages and their cited evidence before re-confirming.
exec
/bin/bash -lc "sed -n '1,240p' /home/hazypiff/.codex/RTK.md && git -C /home/hazypiff/in-range status --short && git -C /home/hazypiff/in-range diff -- docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md" in /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
 succeeded in 1ms:
# RTK - Rust Token Killer (Codex)

Compresses **noisy** shell output before it burns subscription tokens.

## When to use `rtk` (DO)

Prefix these families with `rtk`:

```bash
rtk git status
rtk git log -n 20
rtk git diff
rtk git branch -vv
rtk ls .
rtk find "*.ts" .
rtk rg "pattern" .
rtk grep "pattern" .
rtk test npm test
rtk test bun test
rtk test pytest
rtk cargo test
rtk cargo build
rtk npm run build
rtk docker ps
rtk docker logs <container>
rtk curl <url>
rtk gh pr list
```

## When NOT to use `rtk` (run RAW)

Never wrap these — they are interactive, device, or already small; wrapping dilutes savings:

- `adb`, `flutter`, `dart` device tooling
- `ssh`, `scp`, `rsync`, long-running tunnels
- `docker exec`, `kubectl exec`, database shells (`psql`, `mysql`)
- editors / pagers (`vim`, `less`, `top`)
- tiny one-liners (`true`, `echo ok`, pure `test -f`)

```bash
# good
adb -s DEVICE logcat -d | tail -100
ssh host 'uptime'

# bad (0% save, pollutes stats)
rtk adb ...
rtk proxy adb ...
rtk flutter ...
```

## Escape hatch

Full unfiltered output when debugging:

```bash
rtk proxy <cmd>
```

## Meta

```bash
rtk gain
rtk gain --history
rtk --version
```

## Remote boxes (Tokyo)

Never wrap `ssh` itself in rtk — but the Bash hook cannot see inside the quotes either, so put
`rtk` **inside** the remote command. rtk is installed on Tokyo at `/usr/local/bin/rtk`
(45.32.8.77, komodo host); non-interactive ssh finds it.

```bash
ssh root@45.32.8.77 'cd /opt/komodo-trade-desk && rtk git status'   # 235 -> 69 B
ssh root@45.32.8.77 'journalctl -u komodo-desk -n 300 --no-pager | rtk log'
```

rtk has **no `journalctl`/`systemctl` subcommand** — `rtk journalctl ...` passes through with zero
saving. Pipe into `rtk log` (counts only) or use `rtk err <cmd>`.
?? docs/research/2026-08-01-hardening/
?? docs/research/2026-08-01/

exec
/bin/bash -lc "test -d graphify-out && echo GRAPHIFY_PRESENT || echo NO_GRAPHIFY
rtk rg -n -C 5 'VERDICT|FIX ORDER|SYSTEMIC|Critical means|reachable now|C-SQL-3|C-DIAG-1|H-CONSENT-1|cron\\.job|unverified|not cleared|C-W5-1|all live' docs/research/2026-08-01-hardening docs/research/2026-08-01" in /home/hazypiff/in-range
 succeeded in 0ms:
GRAPHIFY_PRESENT
162 matches in 16 files:

docs/.../2026-08-01-hardening/CONSENSUS_DIALOGUE.md-69-`bigint`, killing the "presence oracle" sub-claim.
docs/.../2026-08-01-hardening/CONSENSUS_DIALOGUE.md-70-
docs/.../2026-08-01-hardening/CONSENSUS_DIALOGUE.md-71-`C-SQL-2` was **downgraded Critical → High** and its premise rewritten: the d...
docs/.../2026-08-01-hardening/CONSENSUS_DIALOGUE.md-72-evidence-class separation downstream, not an ungated forgery oracle.
docs/.../2026-08-01-hardening/CONSENSUS_DIALOGUE.md-73-
docs/.../2026-08-01-hardening/CONSENSUS_DIALOGUE.md:74:Also accepted from Kimi: `C-W5-1`'s *mechanism* was wrong (the `realId` looku...
docs/.../2026-08-01-hardening/CONSENSUS_DIALOGUE.md-75-processes it via the uncommitted path — "treated as fresh" was incorrect), th...
docs/.../2026-08-01-hardening/CONSENSUS_DIALOGUE.md:76:the fix are unchanged, so severity held at Critical. `C-CONSENT-1` → High. `C...
docs/.../2026-08-01-hardening/CONSENSUS_DIALOGUE.md-77-lapsed users. `H-W5-5` is "narrowly alive," not dead code. `H-DIAG-2`'s "cann...
docs/.../2026-08-01-hardening/CONSENSUS_DIALOGUE.md-78-And an internal contradiction: the production probe *proves* `verify_jwt` is ...
docs/.../2026-08-01-hardening/CONSENSUS_DIALOGUE.md-79-deployed builds, so `H-CFG-1` describing it as "currently true" contradicted ...
docs/.../2026-08-01-hardening/CONSENSUS_DIALOGUE.md-80-
docs/.../2026-08-01-hardening/CONSENSUS_DIALOGUE.md-81-### Claude pushes back on two
docs/.../2026-08-01-hardening/CONSENSUS_DIALOGUE.md-123-Corrections that only happened because the panel argued:
docs/.../2026-08-01-hardening/CONSENSUS_DIALOGUE.md-124-
  +33 more in docs/.../2026-08-01-hardening/CONSENSUS_DIALOGUE.md
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-15-**Baseline:** `flutter analyze` clean; `flutter test` 183/183 on `main`, 233/...
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-16-suites green — **no defect below is caught by an existing test.**
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-17-
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-18----
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-19-
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:20:## VERDICT
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-21-
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-22-**Not ready to trust in the wild.** Five Critical findings, which are **not**...
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:23:should not be summarised as "all live":
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-24-
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-25-- **one live in production, remotely exploitable by anyone** — C-PROD-1;
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-26-- **two exploitable today by any authenticated user with a modified client** ...
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:27:- **two data-handling defects that require no attacker at all** — C-SQL-3, a ...
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:28:leaving a de-anonymisable proximity graph at rest, and C-DIAG-1, a diagnostic...
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-29-release binaries that writes plaintext tokens to disk.
  +97 more in docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-17-- `docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md`
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-18-- `docs/research/2026-08-01-hardening/verified_findings_working.md`
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-19-
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-20-Five Critical findings total, and after the consensus round **none of them is...
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-21-those are rated High/merge-blocking because `INRANGE_W5_LINKS` ships default ...
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:22:(C-DIAG-1, which is Critical precisely because it is *not* behind that flag)....
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-23-High, and it still blocks the W5 merge and the Phase-5 matrix, so the order b...
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-24-Linux side has already taken the server, Android and web items, so do not spe...
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-25-is at the bottom of this message.
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-26-
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-27-Baseline before you start: `flutter analyze` is clean, `flutter test` is 233/...
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-93-violation, or a peer with no CA6E characteristic.
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-94-
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-95-Fix: branch on `link.established` in `linkDown`/`closeOutboundLink` — if fals...
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-96-`onDialFailed(linkId:)` instead of `onLinkDown`. Add a TTL sweep for `pending...
  +21 more in docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md
docs/.../transcripts/codex_audit_out.md-38-
docs/.../transcripts/codex_audit_out.md-39-6. Failure direction. The design's stated doctrine is fail-closed. Find any p...
docs/.../transcripts/codex_audit_out.md-40-
docs/.../transcripts/codex_audit_out.md-41-METHOD: read the code and trace concrete call paths. Do not infer behavior fr...
docs/.../transcripts/codex_audit_out.md-42-
docs/.../transcripts/codex_audit_out.md:43:OUTPUT FORMAT: a markdown report, most severe first. For each finding give: a...
docs/.../transcripts/codex_audit_out.md-44-
docs/.../transcripts/codex_audit_out.md-45-codex
docs/.../transcripts/codex_audit_out.md-46-I’ll trace the implementation against the v5.2 corrections and restoration re...
docs/.../transcripts/codex_audit_out.md-47-exec
docs/.../transcripts/codex_audit_out.md-48-/bin/bash -lc "pwd && sed -n '1,240p' /home/hazypiff/.codex/RTK.md && find .....
docs/.../transcripts/codex_audit_out.md-5870-59	- **F4 — the review trail exists only on the Mac, uncommitted.** `docs/ISS...
docs/.../transcripts/codex_audit_out.md-5871-60	- **F5 — housekeeping (non-blocking).** `hazypiff/in-range` main is ~8 com...
docs/.../transcripts/codex_audit_out.md-5872-61
docs/.../transcripts/codex_audit_out.md-5873-62	## Still unverifiable from Linux (consistent with the report's own honesty)
  +7 more in docs/.../transcripts/codex_audit_out.md
docs/.../transcripts/codex_audit_prompt.md-26-
docs/.../transcripts/codex_audit_prompt.md-27-6. Failure direction. The design's stated doctrine is fail-closed. Find any p...
docs/.../transcripts/codex_audit_prompt.md-28-
docs/.../transcripts/codex_audit_prompt.md-29-METHOD: read the code and trace concrete call paths. Do not infer behavior fr...
docs/.../transcripts/codex_audit_prompt.md-30-
docs/.../transcripts/codex_audit_prompt.md:31:OUTPUT FORMAT: a markdown report, most severe first. For each finding give: a...
docs/.../transcripts/codex_consensus_r1.md-30-3. MISSING FINDINGS. Anything materially dangerous the panel did not cover. B...
docs/.../transcripts/codex_consensus_r1.md-31-
docs/.../transcripts/codex_consensus_r1.md-32-4. WRONG OR INCOMPLETE FIXES. Any suggested fix that would not actually close...
docs/.../transcripts/codex_consensus_r1.md-33-
docs/.../transcripts/codex_consensus_r1.md-34-Two findings already carry corrections the coordinator applied to a reviewer'...
docs/.../transcripts/codex_consensus_r1.md:35:- C-DIAG-1: the reviewer said the RSSI file write has no gate; the coordinato...
docs/.../transcripts/codex_consensus_r1.md-36-- H-DIAG-3: the reviewer called pre-Dart restoration an unimplemented require...
docs/.../transcripts/codex_consensus_r1.md-37-
docs/.../transcripts/codex_consensus_r1.md-38-Also sanity-check the single highest-stakes claim in the report: that the dep...
docs/.../transcripts/codex_consensus_r1.md-39-
docs/.../transcripts/codex_consensus_r1.md-40-OUTPUT: a verdict line, then your disagreements.
docs/.../transcripts/codex_consensus_r1.md-1169-
docs/.../transcripts/codex_consensus_r1.md-1170-**Verification rule applied to every finding below:** nothing entered this re...
docs/.../transcripts/codex_consensus_r1.md-1171-say-so. Each finding was re-checked against the code by the coordinating agen...
docs/.../transcripts/codex_consensus_r1.md-1172-evidence is recorded in `verified_findings_working.md`. Reviewer claims that ...
  +725 more in docs/.../transcripts/codex_consensus_r1.md
docs/.../transcripts/codex_final.md-31-
docs/.../transcripts/codex_final.md-32-Corrected finding, now stronger: the round-8 transcript (`docs/research/2026-...
docs/.../transcripts/codex_final.md-33-
docs/.../transcripts/codex_final.md-34-## 3. Open severity dispute — both of you answer
docs/.../transcripts/codex_final.md-35-
docs/.../transcripts/codex_final.md:36:Codex argues that `C-W5-1`, `C-W5-2`, `C-W5-3` should be **High, not Critical...
docs/.../transcripts/codex_final.md-37-
docs/.../transcripts/codex_final.md-38-My adjudication, and I want you both to challenge it if you disagree: **I am ...
docs/.../transcripts/codex_final.md-39-
docs/.../transcripts/codex_final.md:40:That leaves the Critical tier as: C-PROD-1 (live, unauthenticated production ...
docs/.../transcripts/codex_final.md-41-
docs/.../transcripts/codex_final.md-42-Do you both agree with that final tier? If either of you thinks a demoted ite...
docs/.../transcripts/codex_final.md-43-
docs/.../transcripts/codex_final.md-44-## 4. Codex's REPORT-META objection — accepted, confirm the remedy
docs/.../transcripts/codex_final.md-45-
docs/.../transcripts/consensus_prompt.md-18-3. MISSING FINDINGS. Anything materially dangerous the panel did not cover. B...
docs/.../transcripts/consensus_prompt.md-19-
docs/.../transcripts/consensus_prompt.md-20-4. WRONG OR INCOMPLETE FIXES. Any suggested fix that would not actually close...
docs/.../transcripts/consensus_prompt.md-21-
docs/.../transcripts/consensus_prompt.md-22-Two findings already carry corrections the coordinator applied to a reviewer'...
docs/.../transcripts/consensus_prompt.md:23:- C-DIAG-1: the reviewer said the RSSI file write has no gate; the coordinato...
docs/.../transcripts/consensus_prompt.md-24-- H-DIAG-3: the reviewer called pre-Dart restoration an unimplemented require...
docs/.../transcripts/consensus_prompt.md-25-
docs/.../transcripts/consensus_prompt.md-26-Also sanity-check the single highest-stakes claim in the report: that the dep...
docs/.../transcripts/consensus_prompt.md-27-
docs/.../transcripts/consensus_prompt.md-28-OUTPUT: a verdict line, then your disagreements.
docs/.../transcripts/final_round.md-19-
docs/.../transcripts/final_round.md-20-Corrected finding, now stronger: the round-8 transcript (`docs/research/2026-...
docs/.../transcripts/final_round.md-21-
docs/.../transcripts/final_round.md-22-## 3. Open severity dispute — both of you answer
docs/.../transcripts/final_round.md-23-
docs/.../transcripts/final_round.md:24:Codex argues that `C-W5-1`, `C-W5-2`, `C-W5-3` should be **High, not Critical...
docs/.../transcripts/final_round.md-25-
docs/.../transcripts/final_round.md-26-My adjudication, and I want you both to challenge it if you disagree: **I am ...
docs/.../transcripts/final_round.md-27-
docs/.../transcripts/final_round.md:28:That leaves the Critical tier as: C-PROD-1 (live, unauthenticated production ...
docs/.../transcripts/final_round.md-29-
docs/.../transcripts/final_round.md-30-Do you both agree with that final tier? If either of you thinks a demoted ite...
docs/.../transcripts/final_round.md-31-
docs/.../transcripts/final_round.md-32-## 4. Codex's REPORT-META objection — accepted, confirm the remedy
docs/.../transcripts/final_round.md-33-
docs/.../transcripts/kimi_consensus_r1.md-1-• Let me read both documents first.I've read both documents. Now I need to in...
docs/.../transcripts/kimi_consensus_r1.md-2-
docs/.../transcripts/kimi_consensus_r1.md-3-Priority verification targets:
docs/.../transcripts/kimi_consensus_r1.md-4-1. C-PROD-1 reasoning: service_auth.ts requireServiceRole returns 405 on non-...
docs/.../transcripts/kimi_consensus_r1.md:5:2. C-DIAG-1 correction: BackgroundBeacon.swift:956 (sessions only form behind...
docs/.../transcripts/kimi_consensus_r1.md-6-3. H-DIAG-3 correction: AppDelegate.swift:12-17 comments, BackgroundBeacon.sw...
docs/.../transcripts/kimi_consensus_r1.md-7-4. C-SQL-2: correlate_miles_encounters latest definition — is 0048:251-360 re...
docs/.../transcripts/kimi_consensus_r1.md:8:5. C-SQL-3: cleanup_ephemeral_data latest (0059:477-580) — check no later red...
docs/.../transcripts/kimi_consensus_r1.md:9:6. C-W5-1: Dart w5_ownership.dart:321 vs 351, Swift W5Ownership.swift:250 vs ...
docs/.../transcripts/kimi_consensus_r1.md-10-7. C-W5-2: BackgroundBeacon.swift:736-751, :714-734.
docs/.../transcripts/kimi_consensus_r1.md-11-8. C-W5-3: W5LinkController.swift:240-254, W5Ownership.swift:516-530.
docs/.../transcripts/kimi_consensus_r1.md-12-9. C-RT-1: beacon_service.dart:417-422, :603, :2449-2483 (main repo).
docs/.../transcripts/kimi_consensus_r1.md-13-10. C-CONSENT-1: grep require_consent in 0056/0059 — quick.
docs/.../transcripts/kimi_consensus_r1.md-14-11. H-WL-1: 0062:100-104, :120-131 — check the unauthenticated cross-user UPD...
docs/.../transcripts/kimi_consensus_r1.md-26-- supabase/functions/_shared/service_auth.ts + photo-review/index.ts entry + ...
  +148 more in docs/.../transcripts/kimi_consensus_r1.md
docs/.../transcripts/kimi_consensus_r2.md-122-**CONSENSUS: AGREED WITH CORRECTIONS** — with these two adjudications folded ...
docs/.../transcripts/kimi_consensus_r2.md-123-
docs/.../transcripts/kimi_consensus_r2.md-124-- **H-PRIV-1 reinstated as modified**: `SubtleWakeCoordinator.swift`, cap 50,...
docs/.../transcripts/kimi_consensus_r2.md-125-- **H-RT-3 reinstated as written**, sharpened to name `range_estimator.dart:7...
docs/.../transcripts/kimi_consensus_r2.md-126-
docs/.../transcripts/kimi_consensus_r2.md:127:Everything else from round 1 stands as you've already accepted it (C-SQL-2 → ...
docs/.../transcripts/kimi_consensus_r2.md-128-
docs/.../transcripts/kimi_consensus_r2.md-129-To resume this session: kimi -r session_7d89f4bc-8080-4bd9-aaf2-66369260923e
docs/.../transcripts/kimi_final.md-22-zz_probe: no matches anywhere
docs/.../transcripts/kimi_final.md-23-• Point 1 verified: 0053:115-129 upserts the forward sighting with `received_...
docs/.../transcripts/kimi_final.md-24-
docs/.../transcripts/kimi_final.md-25-Point 2 verified: zz_probe_test.dart doesn't exist at W5 HEAD (8 tracked file...
docs/.../transcripts/kimi_final.md-26-
docs/.../transcripts/kimi_final.md:27:Point 3: agree with the tier. My own reasoning: the W5 trio is behind a defau...
docs/.../transcripts/kimi_final.md-28-
docs/.../transcripts/kimi_final.md-29-Point 4: confirm.
docs/.../transcripts/kimi_final.md-30-
docs/.../transcripts/kimi_final.md-31-Output: verdict + brief answers. CONSENSUS: AGREED.
docs/.../transcripts/kimi_final.md-32-
docs/.../transcripts/kimi_final.md-34-
docs/.../transcripts/kimi_final.md-35-**1. H-SQL-5 fix — I accept; my proposed comparison was a no-op.** Verified m...
docs/.../transcripts/kimi_final.md-36-
docs/.../transcripts/kimi_final.md-37-**2. H-ORCH-1 correction — accept.** Independently confirmed: `git ls-files t...
  +7 more in docs/.../transcripts/kimi_final.md
docs/.../transcripts/kimi_round2.md-6-
docs/.../transcripts/kimi_round2.md-7-I also confirmed the entry point is `record_location_ping` at `0040:156`, not...
docs/.../transcripts/kimi_round2.md-8-
docs/.../transcripts/kimi_round2.md-9-Downgrading C-SQL-2 to **High**, rewriting the premise as you suggest: the Lo...
docs/.../transcripts/kimi_round2.md-10-
docs/.../transcripts/kimi_round2.md:11:**C-W5-1 mechanism.** Accepted. `realId = min(my, peer) = peerCandidate` in t...
docs/.../transcripts/kimi_round2.md-12-
docs/.../transcripts/kimi_round2.md-13-**C-CONSENT-1 → High**, with your caveats recorded (0056 documents the gap as...
docs/.../transcripts/kimi_round2.md-14-
docs/.../transcripts/kimi_round2.md:15:**C-SQL-3 nuance** (bites fully only for lapsed users; active users rotate ou...
docs/.../transcripts/kimi_round2.md-16-
docs/.../transcripts/kimi_round2.md-17-Your three missing findings are accepted and added: `scan_relay_abuse`'s `cla...
docs/.../transcripts/kimi_round2.md-18-
docs/.../transcripts/kimi_round2.md-19-## DISPUTED — please re-check these two against the cited file
docs/.../transcripts/kimi_round2.md-20-
docs/.../2026-08-01-hardening/verified_findings_working.md-46-
docs/.../2026-08-01-hardening/verified_findings_working.md-47-**Confidence:** CERTAIN (reproduced every fact above on this machine).
docs/.../2026-08-01-hardening/verified_findings_working.md-48-
docs/.../2026-08-01-hardening/verified_findings_working.md-49----
docs/.../2026-08-01-hardening/verified_findings_working.md-50-
docs/.../2026-08-01-hardening/verified_findings_working.md:51:## C-DIAG-1 — Diagnostic W5 link layer + plaintext RSSI log ship in productio...
docs/.../2026-08-01-hardening/verified_findings_working.md-52-
docs/.../2026-08-01-hardening/verified_findings_working.md-53-**Severity:** Critical (privacy: plaintext proximity records written by a rel...
docs/.../2026-08-01-hardening/verified_findings_working.md-54-**Branch:** `fix/w5-encounter-lease`
docs/.../2026-08-01-hardening/verified_findings_working.md-55-
docs/.../2026-08-01-hardening/verified_findings_working.md-56-**Verified evidence:**
docs/.../2026-08-01-hardening/verified_findings_working.md-269-
docs/.../2026-08-01-hardening/verified_findings_working.md-270-**Confidence:** CERTAIN.
docs/.../2026-08-01-hardening/verified_findings_working.md-271-
docs/.../2026-08-01-hardening/verified_findings_working.md-272----
  +37 more in docs/.../2026-08-01-hardening/verified_findings_working.md
docs/research/2026-08-01/knowledge_round_kimi.md-17-**A2. Rewards for real-world physical behavior survive incentive removal (n=5...
docs/research/2026-08-01/knowledge_round_kimi.md-18-When Ontario cut Carrot Rewards' step incentives 90%, step counts fell only ~...
docs/research/2026-08-01/knowledge_round_kimi.md-19-*So what:* the strongest evidence yet for the "points for going out" economy ...
docs/research/2026-08-01/knowledge_round_kimi.md-20-
docs/research/2026-08-01/knowledge_round_kimi.md-21-**A3. Social-app streaks carry Snapchat-style compulsion risk — now litigatio...
docs/research/2026-08-01/knowledge_round_kimi.md:22:Peer-reviewed study links social streaks to FOMO and problematic use in adole...
docs/research/2026-08-01/knowledge_round_kimi.md-23-*So what:* streak freezes, non-punitive resets, and opt-in (not forced) leade...
docs/research/2026-08-01/knowledge_round_kimi.md-24-
docs/research/2026-08-01/knowledge_round_kimi.md-25-**A4. Location opt-in baseline is ~10%, not the 60–70% people quote.**
docs/research/2026-08-01/knowledge_round_kimi.md-26-Airship's 750M-user study: global location opt-in 10.7% (2020, highest in yea...
  +1 more in docs/research/2026-08-01/knowledge_round_kimi.md
+1 more files

exec
/bin/bash -lc "nl -ba docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md | sed -n '1,120p'
nl -ba docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md | sed -n '560,760p'
nl -ba docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md | sed -n '1,180p'" in /home/hazypiff/in-range
 succeeded in 0ms:
     1	# In Range — full-system hardening & bug-hunt audit, 2026-08-01
     2	
     3	**Scope:** stability, security, correctness. No UI/UX work.
     4	**Branches:** `main` @ `f2f948e`, `fix/w5-encounter-lease` @ `83890e6` (PR #9), `feat/gamification-phase-a` (PR #10).
     5	**Panel:** 7 independent Claude reviewers + Kimi K3 + Codex (`gpt-5.6-sol`, max reasoning), separate
     6	scopes, plus a live production probe. Three adversarial consensus rounds followed; the exchange is
     7	recorded in `CONSENSUS_DIALOGUE.md`.
     8	
     9	**Sign-off:** Codex — `CONSENSUS: AGREED`. Kimi — `AGREED WITH CORRECTIONS`, all folded in.
    10	
    11	**Evidence convention (corrected after Codex's objection):** every **Critical** and every **disputed**
    12	finding has a dedicated evidence section in `verified_findings_working.md` with reproduction commands.
    13	The High/Medium tier is summarized here with file:line inline, not separately sectioned.
    14	
    15	**Baseline:** `flutter analyze` clean; `flutter test` 183/183 on `main`, 233/233 on the W5 branch. Both
    16	suites green — **no defect below is caught by an existing test.**
    17	
    18	---
    19	
    20	## VERDICT
    21	
    22	**Not ready to trust in the wild.** Five Critical findings, which are **not** a homogeneous group and
    23	should not be summarised as "all live":
    24	
    25	- **one live in production, remotely exploitable by anyone** — C-PROD-1;
    26	- **two exploitable today by any authenticated user with a modified client** — C-SQL-1, C-SQL-4;
    27	- **two data-handling defects that require no attacker at all** — C-SQL-3, a server-side retention gap
    28	  leaving a de-anonymisable proximity graph at rest, and C-DIAG-1, a diagnostic subsystem compiled into
    29	  release binaries that writes plaintext tokens to disk.
    30	
    31	Plus a large High tier that blocks the W5 merge and the Phase-5 hardware matrix.
    32	
    33	**Severity convention, settled by the panel:** *Critical* means reachable **now** — either exploitable
    34	today or present in shipped artifacts. Defects in the W5 *state machine* are rated **High /
    35	merge-blocking** because `INRANGE_W5_LINKS` ships default OFF. This was Codex's argument; Claude adopted
    36	it and Kimi accepted. It changes no priorities — the W5 items remain first in the Mac queue — it just
    37	stops the tier from lying about reachability.
    38	
    39	**Why C-DIAG-1 is Critical while the W5 defects are High — these are not in tension.** The W5 *feature*
    40	is gated by `INRANGE_W5_LINKS`, which is why its correctness defects are merge blockers rather than live
    41	compromises. C-DIAG-1 is Critical for precisely the opposite reason: `W5LinkController.swift` is **not**
    42	behind that compile-time flag. It is behind a *persisted* `bb.w5links` boolean, so the diagnostic code is
    43	compiled into every release binary, and a value inherited from a prior diagnostic install re-activates it
    44	before Dart can clear it (issue #8's mechanism). Kimi's sign-off recorded this explicitly: C-DIAG-1
    45	"earns its place on privacy-in-release grounds rather than exploitability."
    46	
    47	**The structural finding:** the worst defects share one cause — *invariants enforced by hand-applied
    48	convention with nothing proving coverage.* Consent checks, retention purges, and service-role auth are
    49	each applied per-call-site by a human remembering. Three tests (§Systemic) would have caught **two
    50	Criticals and one High** at authoring time — C-SQL-3, C-PROD-1 (three weeks ago), and H-CONSENT-1.
    51	
    52	---
    53	
    54	## CRITICAL — live today
    55	
    56	### C-PROD-1 🔴 `photo-review` and `send-push` accept unauthenticated requests in production
    57	Deploy drift; the repo code is correct. Probed: `POST /photo-review` no auth → `200`; wrong bearer →
    58	`200`; **`GET` no auth → `200`**. `requireServiceRole` rejects non-POST with 405 *before* anything else,
    59	so a 200 on GET proves the deployed binary lacks the check. `POST /send-push` no auth → `200`,
    60	`{"processed":19}`. Control: `maintenance` → `401`.
    61	
    62	The gate landed in `45ef624` (2026-07-12) for all four functions; only `maintenance` (v5) and
    63	`miles-correlate` (v6) were redeployed (`SAFETY_RUNBOOK.md:31-32`). ~3 weeks of pre-hardening code live.
    64	`photo-review` reports `auto_approve: true` on the production host, and photo verification gates
    65	discoverability (0052) — a moderation step adjacent to child-safety obligations.
    66	
    67	**Fix now:** `supabase functions deploy send-push photo-review`; set `verify_jwt=false` for both; add the
    68	missing `[functions.proximity-wake]` block (it currently 404s).
    69	
    70	### C-SQL-1 🔴 `claim_token` overwrites another user's `token_claim_history` row
    71	`0060:149-159` — `ON CONFLICT (token) DO UPDATE` with **no `WHERE user_id = v_uid`**. The `COALESCE`
    72	"guard" is dead code: `0060:117-118` rejects NULL coordinates, so `EXCLUDED.approx_lat` always wins.
    73	Tokens are broadcast in plaintext over BLE. Neutralises the GPS veto — `correlate_encounter`
    74	(`0053:179-182`) compares against coordinates the attacker just wrote. The batch-membership check that
    75	would stop it sits behind `enforce_batch_tokens`, which is **0**.
    76	
    77	### C-SQL-3 🔴 `beacon_token_batch` has no scheduled purge — a permanent token→user_id map
    78	`cleanup_ephemeral_data()` (latest `0059:477-580`) purges 9 tables; not this one. Joining it to
    79	`rssi_samples` on the shared token yields a de-anonymised proximity graph. **Nuance accepted from Kimi:**
    80	active users' rows rotate out at next batch issue (~1–2 day window); it is **lapsed** users whose token
    81	set persists indefinitely. Two-line fix:
    82	`DELETE FROM public.beacon_token_batch WHERE valid_until < NOW() - INTERVAL '24 hours';`
    83	
    84	### C-SQL-4 🔴 Batch-pre-claimed tokens skip the GPS veto entirely *(found by Kimi)*
    85	`0053:179-182` wraps the veto in `IF ... v_claim.approx_lat IS NOT NULL ...`. `claim_token_batch`
    86	(`0060:25`) pre-claims with NULL location — the locked-phone path. For those tokens the veto never runs.
    87	Independent of C-SQL-1; fixing one does not close the other.
    88	**Fix:** treat a location-less claim as veto-*failing*, or compare the two sightings' `observer_lat/lon`
    89	to each other (always present).
    90	
    91	### C-DIAG-1 🔴 Diagnostic W5 link layer ships in release binaries
    92	Three `#if INRANGE_DIAG` sites exist in the whole iOS tree, all in `BackgroundBeacon.swift`.
    93	`W5LinkController.swift` has zero; its gate is the persisted bool `bb.w5links`, and `recordRssi`
    94	(`:633-650`) writes plaintext `{"token","rssi","ts"}` to `Documents/w5_rssi_log.jsonl`.
    95	*Coordinator correction (accepted by both):* the write **is** gated — by the persisted flag, via the
    96	universal guard at `BackgroundBeacon.swift:1118`. That is the finding: issue #8 says a persisted flag
    97	must not be what stands between a release binary and diagnostic behaviour.
    98	
    99	---
   100	
   101	## HIGH
   102	
   103	**Merge-blocking for W5 (Mac side):**
   104	- **H-W5-1** A committed encounter reached by `realId` bypasses the sticky-keeper branch. Dart
   105	  `w5_ownership.dart:321` vs `:351`; Swift `W5Ownership.swift:250` vs `:279`. *Mechanism corrected by
   106	  Kimi:* `realId` **finds** the encounter and processes it via the uncommitted path — the intruder link is
   107	  added with no winner comparison and no close, and `maybeCommit` no-ops on an already-committed
   108	  encounter. Executed outcome (keeper silently moves, no `owns`/`close` emitted) and fix (hoist `realId`
   109	  above the committed check) unchanged. Reproduces #7 with no attacker: `HELLO_ACK` has no `prevAlias`
   110	  field, so a rotated peer alias is unresolvable on the outbound path.
   111	- **H-W5-2** Peripheral restoration never re-binds `controlNotifyChar`/`keepaliveNotifyChar`
   112	  (`BackgroundBeacon.swift:736-751`), so the peripheral can never send another control message while
   113	  still appearing healthy. *Independently confirmed by Codex, same lines.*
   114	- **H-W5-3** A dial that connects but dies before HELLO_ACK leaks a `pendingDial` forever
   115	  (`W5LinkController.swift:240-254` → `W5Ownership.swift:390`): the encounter can never commit, never be
   116	  re-dialled, and never be erased.
   117	- **H-W5-4** No lease persistence; restoration re-handshakes restored links with *fresh* identity, which
   118	  the peer correctly rejects. Codex added the stale-generation sequence: A retains B's accepted
   119	  `peerViewGen`, B relaunches from zero, the encounter id does not change so `rekey` never fires, and
   120	  convergence stays stuck.
     1	# Work order for the Mac agent — hardening round 2026-08-01
     2	
     3	Paste the section below to the Mac agent. It is written to be self-contained.
     4	
     5	---
     6	
     7	## Prompt for the Mac agent
     8	
     9	We ran a full-system hardening and bug-hunt round on 2026-08-01 — no UI/UX work, pure stability,
    10	security and correctness. The panel was 7 independent Claude reviewers plus Kimi K3 and Codex
    11	(`gpt-5.6-sol`) on separate scopes, and every finding was re-verified against the code by the
    12	coordinating agent before it entered the report. Frontend work is **paused** until this queue is done.
    13	
    14	Read these two documents first — the second one carries the exact file:line evidence and the
    15	reproduction commands for each item:
    16	
    17	- `docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md`
    18	- `docs/research/2026-08-01-hardening/verified_findings_working.md`
    19	
    20	Five Critical findings total, and after the consensus round **none of them is a W5 state-machine defect** —
    21	those are rated High/merge-blocking because `INRANGE_W5_LINKS` ships default OFF. One Critical is yours
    22	(C-DIAG-1, which is Critical precisely because it is *not* behind that flag). The rest of your queue is
    23	High, and it still blocks the W5 merge and the Phase-5 matrix, so the order below is unchanged. The
    24	Linux side has already taken the server, Android and web items, so do not spend time there — the split
    25	is at the bottom of this message.
    26	
    27	Baseline before you start: `flutter analyze` is clean, `flutter test` is 233/233 on
    28	`fix/w5-encounter-lease` and 183/183 on `main`. Both suites are green, which means **not one of the
    29	defects below is caught by an existing test.** Every fix you land needs a test that fails before it and
    30	passes after.
    31	
    32	### Your queue, in the order we recommend
    33	
    34	**1. H-W5-1 (High, merge-blocking) — a committed encounter reached by `realId` bypasses the sticky-keeper branch.**
    35	This is the highest-leverage item in the entire round: it is a two-line hoist in each implementation and
    36	it reproduces the original #7 duplicate-keeper defect *in production with no attacker involved*.
    37	
    38	The committed check runs before the `realId` fallback in both languages:
    39	- Dart `lib/features/beacon/w5_ownership.dart:321` (`if (e != null && e.committed)`) vs `:351` (`e ??= _enc[realId];`)
    40	- Swift `ios/Runner/W5Ownership.swift:250` (`if let ec = e, ec.committed`) vs `:279` (`if e == nil { e = enc[realId] }`)
    41	
    42	`e` at the committed check comes only from `_locate(peerAlias, myCandidate)` plus the `peerPrevAlias`
    43	fallback. When the lease key is the peer's candidate (`peerCandidate < myCandidate`) and the incoming
    44	alias is not yet in `_aliasTo`, `_locate` misses and the committed branch is skipped. **Mechanism note,
    45	corrected during consensus (Kimi):** the `_enc[realId]` fallback then *finds* the encounter — it is not
    46	"treated as fresh". It is processed by the **uncommitted** path, so the intruder link is added with no
    47	winner comparison and no close, and `maybeCommit` no-ops because the encounter is already committed. A
    48	full fork only occurs when `myCandidate < peerCandidate`. A reviewer executed this against the Dart
    49	oracle: effects come back `[W5SendPropose]` — no close of the intruder, no `owns` — and the keeper moves
    50	`p1 → p2`, `linkId` `L5 → L0`. With the *known* alias the same probe correctly returns
    51	`[W5RejectInbound(p2)]` and the keeper holds, which isolates the cause to the `_locate` miss.
    52	
    53	This violates `docs/W5_ENCOUNTER_LEASE_DESIGN.md:295-296` ("A committed keeper is sticky … Committed
    54	leases never rekey").
    55	
    56	**Why it fires without an attacker, and this part matters for your fix:** `W5LinkController.swift:104`
    57	mints the local candidate per peer alias, and `HELLO_ACK` (`W5Codec.swift:50`) has **no `prevAlias` field
    58	at all** — the outbound call site at `:208-211` passes none. So on the outbound path a rotated peer token
    59	is unresolvable by construction. The inbound path at `:317` does pass `peerPrevAlias`, which is exactly
    60	why vector 2 is green and this stayed hidden. Consider whether `HELLO_ACK` needs a `prevAlias` field as
    61	part of the real fix; if you add one it is a wire change and needs codec vectors.
    62	
    63	Fix: hoist the `realId` resolution above the committed check in both implementations. Belt-and-braces,
    64	have `committedKeeper`/`committedLinkId` return a winner *stored at commit* rather than recomputing
    65	`winner()` from a mutable `links` map, so the keeper can never move without an effect being emitted.
    66	
    67	**2. H-W5-2 (High, merge-blocking) — peripheral restoration permanently nils the notify characteristics.**
    68	`ios/Runner/BackgroundBeacon.swift:736-751`. `willRestoreState` sets `didRestorePeripheral = true` and
    69	`serviceAdded = true` but never re-binds `controlNotifyChar` / `keepaliveNotifyChar`, which are created
    70	only inside `if !serviceAdded` in `reconfigureAdvertising` (`:396-421`). After a restoration relaunch both
    71	stay `nil` for the process lifetime.
    72	
    73	The device still advertises and still answers reads, so it looks healthy — but `notifyControl`
    74	(`W5LinkController.swift:531-536`) returns early on every call. A central connects, subscribes, writes
    75	HELLO, and we `respond(.success)` so it believes the write landed, while the HELLO_ACK is silently
    76	discarded. Both endpoints stall permanently. For an app whose entire design is "iOS relaunches us for BLE
    77	events," the restoration launch is the **normal** path, not an edge case.
    78	
    79	Fix: walk `svc.characteristics` in `willRestoreState` and re-bind both references; set
    80	`serviceAdded = false` to force a clean re-add if either cannot be recovered.
    81	
    82	**3. H-W5-3 (High, merge-blocking) — a dial that connects but dies before HELLO_ACK leaks a `pendingDial` forever.**
    83	`W5LinkController.swift:240-254`. Only `didFailToConnect` reaches `onDialFailed`. "Connected, then died
    84	before HELLO_ACK" arrives on `didDisconnectPeripheral` → `linkDown` → `onLinkDown`, whose first act is
    85	`handleTo.removeValue(forKey: handle)` — but the handle was never mapped, because mapping happens in
    86	`onControl` which requires HELLO_ACK. So it returns `[]` and `pendingDials` survives.
    87	
    88	Permanent result for that peer: `maybeCommit` bails on `!e.pendingDials.isEmpty` so the encounter can
    89	never commit; `onDiscovered` returns `[]` because `!e.inGrace` so you never dial again; and nothing
    90	erases the lease. If the peer later dials you, you broadcast an unmatchable PROPOSE **every 8 seconds for
    91	the life of the encounter**. Triggers are all mundane: peer walks out of range after `didConnect`, the 10s
    92	watchdog at `BackgroundBeacon.swift:967-973` cancelling without calling `dialFailed`, a CA6E decode
    93	violation, or a peer with no CA6E characteristic.
    94	
    95	Fix: branch on `link.established` in `linkDown`/`closeOutboundLink` — if false, feed
    96	`onDialFailed(linkId:)` instead of `onLinkDown`. Add a TTL sweep for `pendingDials`.
    97	
    98	**4. C-DIAG-1 (CRITICAL — the one Critical in your queue) — the diagnostic W5 link layer ships inside release binaries.**
    99	The whole iOS tree has **three** `#if INRANGE_DIAG` sites, all in `BackgroundBeacon.swift` (52, 68, 694).
   100	`W5LinkController.swift` has zero. Its gate is the persisted bool `bb.w5links` (`:120`), and `recordRssi`
   101	(`:633-650`) appends plaintext `{"token":"<hex>","rssi":N,"ts":…}` to `Documents/w5_rssi_log.jsonl`.
   102	
   103	Note the precise framing, because we corrected a reviewer on it: the file write *is* gated, by
   104	`bb.w5links` — the universal guard is at `BackgroundBeacon.swift:1118` (Codex's citation correction; the
   105	session-formation site at `:956` is one instance). That is the finding, not a
   106	mitigation — issue #8 says explicitly that a persisted flag must not be what stands between a release
   107	binary and diagnostic behaviour, because the stale persisted value is `true` until Dart overwrites it.
   108	
   109	Fix: `#if INRANGE_DIAG`-wrap `w5LinksEnabled` (`#else false`), wrap the `recordRssi` file branch, and
   110	ideally exclude `W5LinkController.swift` from the production target's Sources phase until W5 ships.
   111	
   112	**5. H-DIAG-2 (High) — the #8 guard proves far less than it appears to.**
   113	(Softened during consensus: "cannot fail" was too strong — `testProductionDomainCannotSeeDiagnosticState`
   114	is a genuine runtime check. Sharpened in the other direction: on `main` there is **no RunnerTests job in
   115	CI at all**; the simulator test job exists only on the W5 branch.)
   116	It asserts compile-time constants (`XCTAssertFalse(BackgroundBeacon.isDiagBuild)`), and CI runs the suite
   117	only under Debug (`.github/workflows/ios-build.yml:52`, `Runner.xcscheme:44`), where those constants are
   118	true by construction. **If someone added `INRANGE_DIAG` to the Release configuration, CI would stay
   119	green.** One of its three tests just restates Foundation's `UserDefaults` suite semantics. `diag.xcscheme`
   120	has an empty `<Testables>`, so nothing proves the `.diag` suffix works either.
   121	
   122	Fix: assert at build-settings level, not runtime — a CI step running
   123	`xcodebuild -showBuildSettings -configuration Release -target Runner` that fails if `INRANGE_DIAG`
   124	appears, for each production configuration; plus a mirrored diag-side test with a populated `<Testables>`
   125	as a positive control.
   126	
   127	**6. H-DIAG-3 (High) — pre-Dart restoration trusts persisted state, including a bearer token.**
   128	`BackgroundBeacon.swift:184` acts on persisted `bb.enabled`, and `sendWakePing()` (`:670-686`) reads a
   129	persisted endpoint URL *and* a persisted bearer token and POSTs to them from a BGTask, ungated.
   130	
   131	We corrected a reviewer here too, and the correction changes the fix: this is **deliberate**, not an
   132	oversight. `AppDelegate.swift:12-16` states the intent — pre-Dart boot is the entire point of the W2
   133	background-BLE wiring. So do **not** fix it by waiting for Dart. Persist a flavor/schema stamp
   134	(`bb.stateSchema`) beside the operational state and, on boot, wipe `bb.*` and skip `ensureManagers()`
   135	when the stamp is missing or foreign. Separately `#if`-gate `sendWakePing` and refuse token slots whose
   136	validity window runs past a sane horizon.
   137	
   138	**7. The vector suite — read this carefully, something is recorded wrong.**
   139	The brief for this round referred to "vectors 5+6 pinning the per-alias candidate mint (`candidateByAlias`)"
   140	as landed in `30619a1`. **`w5_ownership_vectors.json` contains four vectors.** Please re-check what
   141	actually landed, because the R8-F1 contract may not be pinned at all.
   142	
   143	Beyond that, the shared runners hard-code a 7-event vocabulary and cannot express six oracle entry points
   144	at all: `onBeaconOff`, `onDialFailed`, `onAliasRoll`, `onPrevAliasExpiry`, `onRetryTimer`,
   145	`debugSetViewGen`. `graceExpiry` is wired but no vector uses it. And `sendPropose`/`sendAck` are matched
   146	as **wildcards** on both sides, so v5.2 correction #5 (route identity — PROPOSE broadcasts over every
   147	negotiating link, ACK routes back over the source link) has zero coverage.
   148	
   149	Also worth knowing: Dart and Swift emit close/route effects in **different order** — Dart uses insertion
   150	order (`w5_ownership.dart:208-209`, `:607-609`), Swift sorts by handle (`W5Ownership.swift:142-145`,
   151	`:525-527`). Dart's own `_closeAllLinks` *is* sorted, which suggests the others are an oversight. No
   152	vector catches it today because none commits with ≥3 links inserted out of handle order — but the vector
   153	matcher compares effects by exact index, so the first vector that does will pass on exactly one platform.
   154	
   155	**8. H-ORCH-1 (High) — round-8's sign-off evidence is partly unreproducible.**
   156	That PASS cited "Dart 259/259" including Kimi's ported round-7 suite (16 tests) and 10 new probes. The
   157	branch yields 233/233 today, only 6 probes are committed (`test/features/beacon/zz_probe_test.dart`), and
   158	`/tmp/kimi-r7/.../w5_ownership_r7_kimi_test.dart` no longer exists and was never committed on any branch
   159	(`git log --all` finds no trace). 233 + 26 = 259 reconciles it exactly. So roughly twenty adversarial
   160	probes that pin the alias-stomp bug class are gone from CI, and the class can regress silently behind a
   161	green suite. Please reconstruct them as committed tests.
   162	
   163	Standing rule from here: **no review round may cite an uncommitted test file as sign-off evidence.**
   164	
   165	### Also yours, lower priority (detail in the working file)
   166	
   167	`H-W5-3` no lease persistence, and restoration actively re-handshakes restored links with fresh identity
   168	that the peer correctly rejects (≥5-min blackout plus a wedged lease) · `H-W5-4` `dropPeer` never erases
   169	the lease and does not disconnect an inbound keeper at all — `onTeardown` has **no production caller**, so
   170	the app can re-dial someone the user just rejected · `H-W5-5` the per-encounter candidate is keyed by peer
   171	alias, so token rotation mints a new one, making R7 fix #1 dead code in production · the `bb_wake_log.txt`
   172	writer has no cap or rotation and uses the **trapping** `FileHandle.write`, which is an uncatchable crash
   173	on a full disk — switch to `try h.write(contentsOf:)` · the RSSI log needs `isExcludedFromBackup` and a
   174	file-protection class.
   175	
   176	### What the Linux side is taking — do not duplicate
   177	
   178	Production Edge Function redeploy and `verify_jwt` config; the **three** SQL Criticals — `claim_token`
   179	cross-user overwrite (C-SQL-1), `beacon_token_batch` retention (C-SQL-3), and the GPS veto skipped for
   180	batch-pre-claimed tokens (C-SQL-4) — plus the two SQL findings the consensus round downgraded to High,

exec
/bin/bash -lc "wc -l docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md
rtk rg -n '"'^##|''^###|unverified|not cleared|cron'"\\.job|0019|0020|0062|all live|all five|four Critical|Criticals|FIX ORDER|SYSTEMIC' docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md
nl -ba docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md | sed -n '240,440p'" in /home/hazypiff/in-range
 succeeded in 0ms:
265 docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md
22 matches in 1 files:

20:## VERDICT
23:should not be summarised as "all live":
50:Criticals and one High** at authoring time — C-SQL-3, C-PROD-1 (three weeks a...
54:## CRITICAL — live today
56:### C-PROD-1 🔴 `photo-review` and `send-push` accept unauthenticated requests...
70:### C-SQL-1 🔴 `claim_token` overwrites another user's `token_claim_history` r...
77:### C-SQL-3 🔴 `beacon_token_batch` has no scheduled purge — a permanent token...
84:### C-SQL-4 🔴 Batch-pre-claimed tokens skip the GPS veto entirely *(found by ...
91:### C-DIAG-1 🔴 Diagnostic W5 link layer ships in release binaries
101:## HIGH
151:another person's `ref_code`, zone and position (`0062:100-104`, `:120-131`); ...
153:property, which 0055/0062 silently dropped while leaving the comment in place...
160:`other_user_id`") was **false**. `0019:2496-2527` revokes `correlate_miles_en...
164:original grep (`00[2-6]*`) excluded 0019 — an asserted verification that was ...
204:## MEDIUM / LOW (selected)
  +7 more in docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md
   240	
   241	## FIX ORDER
   242	
   243	1. **C-PROD-1** — redeploy, fix `verify_jwt`, add the `proximity-wake` entry.
   244	2. **C-SQL-1, C-SQL-3, C-SQL-4** — three small server-side SQL fixes, all reachable today.
   245	   Then **C-DIAG-1** (release-binary privacy; Mac side, compile-out + suite exclusion).
   246	3. **H-WL-1 / H-WL-2** — the only endpoints an anonymous attacker can reach.
   247	4. **H-W5-1** (two-line hoist + the vector that pins it), then **H-W5-5** *before* the Phase-5 matrix.
   248	5. **H-W5-2, H-W5-3, H-RT-1** — the wedges.
   249	6. Systemic tests, then the rest of the High tier.
   250	
   251	## COVERAGE AND LIMITATIONS
   252	
   253	- **Verified against production:** only the Edge Function auth probe. Everything else is source-verified.
   254	  The highest-value manual check remains `SELECT jobname, schedule FROM cron.job;` — `0015`'s
   255	  `cron.schedule` is wrapped in `DO $$ … EXCEPTION WHEN OTHERS THEN NULL`, so a failed schedule is silent,
   256	  and if that row is missing every retention claim here is "forever" rather than 24h.
   257	- **Not verified:** anything requiring Xcode (no Mac) — all Swift findings are static reads; hardware
   258	  frequency and behaviour; the deployed Edge Function *source*.
   259	- **The local Supabase container is at 0019.** Privilege regressions in 0020–0062 are therefore
   260	  **unverified, not cleared** — a caveat that also applies to Kimi's DB-derived "all clean" statement.
   261	- **Depth of each auditor's check, self-reported:** Codex re-read the source mechanism for every Critical
   262	  and summarized High finding including latest SQL definitions, and accepted rather than reproduced the
   263	  production HTTP observations, flag values, cron state and Flutter totals; it did not re-audit
   264	  Medium/Low item by item. Kimi personally re-read the grant/revoke lines it disputed and marked its
   265	  other checks as delegate-verified.

exec
/bin/bash -lc "nl -ba docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md | sed -n '190,265p'
nl -ba docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md | sed -n '160,230p'" in /home/hazypiff/in-range
 succeeded in 0ms:
   190	  `_lastForeignScanAt = DateTime.now()` (`:2220`). False "Close By", and a dead scanner looks healthy for
   191	  another watchdog cycle. *Kimi refuted this in round 1 and withdrew the refutation in round 2.*
   192	- **H-RT-4** `turnOffBeacon` is the only lifecycle path with no session-generation guard across 6 awaits.
   193	- **H-RT-5** `_hexTo16Bytes` throws on non-32-char hex and `_rotateToken`'s catch then silently disables
   194	  the beacon. *Kimi's sibling:* it also **silently truncates longer hex** — a quieter corruption mode.
   195	- **H-RT-6** The consent gate is a one-shot prefs flag; withdrawal never re-gates; `preciseLocation`
   196	  withdrawal does not stop the beacon's GPS; WiFi scanning is bound to no purpose at all.
   197	- **H-RT-7** `myEncountersProvider` is not user-scoped and is absent from `_clearUserRuntime` — user A's
   198	  encounters render for user B after an account switch.
   199	- **H-RT-8** Backgrounded-iPhone discovery is broken by Apple multi-AD blob offsets on Android 15/16; the
   200	  remedy exists in `apple_overflow_bit.dart` + `AdvertParser.kt` and **is never called from Dart**.
   201	- **H-RT-9** `LocalDb.open()` is unguarded in `main()` before `runApp`, with no `onDowngrade`.
   202	- **H-PRIV-2** Release-reachable PII in logs; the `piiSafe` helper a prior audit called for was never built.
   203	
   204	## MEDIUM / LOW (selected)
   205	
   206	**M-SQL-1** `scan_relay_abuse` attributes `relay_geo` to the **victim** (`0033:146`) — *demoted from High
   207	per Codex:* the runbook forbids punitive action (`RELAY_ABUSE_RUNBOOK.md:22`) and the attacker needs the
   208	victim's rotating token. Becomes Critical only if a mint consumer ignores the corroboration rule.
   209	**M-SQL-2** *(Kimi)* `scan_relay_abuse`'s `claim_teleport` CTE joins only location-bearing claims, so the
   210	NULL-coord batch-claim path — the dominant locked-phone shape — is **invisible to relay telemetry.**
   211	**M-PRIV-1** *(both auditors, independently)* `SubtleWakeCoordinator` buffer: cap 50, place-level SLC/
   212	`CLVisit` coordinates, count-cap only with no age bound. *Corrected:* it **is** cleared via the Dart
   213	drain+ack path, which is flag-blind (`subtle_wake_service.dart:306-346` checks only platform); what
   214	persists un-aged is only what accumulated while no engine existed.
   215	**M-W5-1** The "reactive cascade with no timer" claim has a timer-only liveness gap — the next write is
   216	scheduled by `asyncAfter`, which cannot run while suspended. The 10h38m soak may have survived because
   217	the phones kept being woken. Re-read the soak evidence before treating durability as proven.
   218	Plus: unsalted SHA-256 of client IP as a primary key; `venue_anchors` geohash precision uncontrained with
   219	14/30-day retention; `bb_wake_log.txt` uncapped with a **trapping** `FileHandle.write`; Dart↔Swift effect
   220	*ordering* divergence unpinned by any vector; `rssi_batch_rate` created without the house-style REVOKE;
   221	`points_ledger` needs `session_id` before the ledger is append-only in production.
   222	
   223	---
   224	
   225	## WHAT THE VECTORS DO NOT PIN
   226	
   227	`w5_ownership_vectors.json` contains **four** vectors. The round-8 record refers to "vectors 5+6 pinning
   228	the per-alias candidate mint" — **re-check what actually landed in `30619a1`.** The shared runners cannot
   229	express six oracle entry points (`onBeaconOff`, `onDialFailed`, `onAliasRoll`, `onPrevAliasExpiry`,
   230	`onRetryTimer`, `debugSetViewGen`); `graceExpiry` is wired but unused; `sendPropose`/`sendAck` are matched
   231	as **wildcards**, so v5.2 correction #5 has zero coverage.
   232	
   233	## SYSTEMIC — three tests that would have caught two Criticals and one High
   234	
   235	1. pgTAP: every RPC inserting into a user-scoped table calls `require_consent` → catches H-CONSENT-1.
   236	2. A retention test that fails when a table is added without a `cleanup_ephemeral_data` entry → catches
   237	   C-SQL-3 and the `venue_anchors`/`proximity_wake_requests` overruns.
   238	3. A deploy-parity probe asserting `405` on `GET` for every service-role function → catches C-PROD-1, and
   239	   would have caught it three weeks ago.
   240	
   241	## FIX ORDER
   242	
   243	1. **C-PROD-1** — redeploy, fix `verify_jwt`, add the `proximity-wake` entry.
   244	2. **C-SQL-1, C-SQL-3, C-SQL-4** — three small server-side SQL fixes, all reachable today.
   245	   Then **C-DIAG-1** (release-binary privacy; Mac side, compile-out + suite exclusion).
   246	3. **H-WL-1 / H-WL-2** — the only endpoints an anonymous attacker can reach.
   247	4. **H-W5-1** (two-line hoist + the vector that pins it), then **H-W5-5** *before* the Phase-5 matrix.
   248	5. **H-W5-2, H-W5-3, H-RT-1** — the wedges.
   249	6. Systemic tests, then the rest of the High tier.
   250	
   251	## COVERAGE AND LIMITATIONS
   252	
   253	- **Verified against production:** only the Edge Function auth probe. Everything else is source-verified.
   254	  The highest-value manual check remains `SELECT jobname, schedule FROM cron.job;` — `0015`'s
   255	  `cron.schedule` is wrapped in `DO $$ … EXCEPTION WHEN OTHERS THEN NULL`, so a failed schedule is silent,
   256	  and if that row is missing every retention claim here is "forever" rather than 24h.
   257	- **Not verified:** anything requiring Xcode (no Mac) — all Swift findings are static reads; hardware
   258	  frequency and behaviour; the deployed Edge Function *source*.
   259	- **The local Supabase container is at 0019.** Privilege regressions in 0020–0062 are therefore
   260	  **unverified, not cleared** — a caveat that also applies to Kimi's DB-derived "all clean" statement.
   261	- **Depth of each auditor's check, self-reported:** Codex re-read the source mechanism for every Critical
   262	  and summarized High finding including latest SQL definitions, and accepted rather than reproduced the
   263	  production HTTP observations, flag values, cron state and Flutter totals; it did not re-audit
   264	  Medium/Low item by item. Kimi personally re-read the grant/revoke lines it disputed and marked its
   265	  other checks as delegate-verified.
   160	probes that pin the alias-stomp bug class are gone from CI, and the class can regress silently behind a
   161	green suite. Please reconstruct them as committed tests.
   162	
   163	Standing rule from here: **no review round may cite an uncommitted test file as sign-off evidence.**
   164	
   165	### Also yours, lower priority (detail in the working file)
   166	
   167	`H-W5-3` no lease persistence, and restoration actively re-handshakes restored links with fresh identity
   168	that the peer correctly rejects (≥5-min blackout plus a wedged lease) · `H-W5-4` `dropPeer` never erases
   169	the lease and does not disconnect an inbound keeper at all — `onTeardown` has **no production caller**, so
   170	the app can re-dial someone the user just rejected · `H-W5-5` the per-encounter candidate is keyed by peer
   171	alias, so token rotation mints a new one, making R7 fix #1 dead code in production · the `bb_wake_log.txt`
   172	writer has no cap or rotation and uses the **trapping** `FileHandle.write`, which is an uncatchable crash
   173	on a full disk — switch to `try h.write(contentsOf:)` · the RSSI log needs `isExcludedFromBackup` and a
   174	file-protection class.
   175	
   176	### What the Linux side is taking — do not duplicate
   177	
   178	Production Edge Function redeploy and `verify_jwt` config; the **three** SQL Criticals — `claim_token`
   179	cross-user overwrite (C-SQL-1), `beacon_token_batch` retention (C-SQL-3), and the GPS veto skipped for
   180	batch-pre-claimed tokens (C-SQL-4) — plus the two SQL findings the consensus round downgraded to High,
   181	`correlate_miles_encounters` encounter fabrication (H-SQL-2) and missing `require_consent` on the three
   182	newest write paths (H-CONSENT-1); the waitlist endpoint's unauthenticated
   183	cross-user write and its email-enumeration oracle; `scan_relay_abuse` victim-attribution; proximity-wake
   184	authorization; the Android Apple-multi-AD advert parser wiring; and the three systemic tests (a pgTAP
   185	assertion that every user-scoped-table RPC calls `require_consent`, a retention test that fails when a
   186	table is added without a `cleanup_ephemeral_data` entry, and a deploy-parity probe asserting `405` on
   187	`GET` for every service-role function).
   188	
   189	### Shared Dart runtime — tell us which you want
   190	
   191	These live in `lib/` and affect both platforms, so say which you'd rather own and Linux takes the rest:
   192	`C-RT-1` `_flushSightings` has no re-entrancy guard and `turnOffBeacon` awaits it, so the user can tap
   193	"off" and have BLE keep running for up to 83 minutes on a bad network · `H-RT-3` natively-buffered
   194	sightings replay into the live 90s window with *fresh* timestamps, producing a false "Close By" for a peer
   195	who was near 20 minutes ago and masking a dead scanner from the watchdog · `H-RT-4` `turnOffBeacon` is the
   196	only lifecycle path with no session-generation guard across six awaits · `H-RT-5` an unvalidated server
   197	token crashes the beacon and `_rotateToken`'s catch then silently disables it · `H-RT-7`
   198	`myEncountersProvider` is not user-scoped, so user A's encounters render for user B after an account
   199	switch.
   200	
   201	### Working agreement
   202	
   203	Branch off `fix/w5-encounter-lease`. Every fix needs a test that fails before and passes after — that is
   204	what this round exists to establish, given all suites were green while nine Criticals were live. Watch
   205	every rebase: a previous one silently dropped three third-party commits, so verify `git log origin..HEAD`
   206	still contains everything that is not yours before any force-push. Post findings and questions on PR #9;
   207	if anything above does not match what you see in the code, say so on the thread rather than adapting to
   208	it silently — we would rather hear that a finding is wrong than have you work around it.

exec
/bin/bash -lc "nl -ba docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md | sed -n '118,205p'
rtk rg -n '\\bC-W5-[1-9]\\b|\\bC-CONSENT-1\\b|\\bC-RT-1\\b|nine Critical|Criticals were live|CRITICAL — live|all live|Critical' docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md" in /home/hazypiff/in-range
 succeeded in 0ms:
   118	  the peer correctly rejects. Codex added the stale-generation sequence: A retains B's accepted
   119	  `peerViewGen`, B relaunches from zero, the encounter id does not change so `rekey` never fires, and
   120	  convergence stays stuck.
   121	- **H-W5-5** The 120s reconnect grace is normally unreachable — `tokenCacheTTL` 900s and
   122	  `connectRetryFloor` 300s (`BackgroundBeacon.swift:81-82`) gate the dial before the lease authority is
   123	  consulted (`:1002-1012`). *Found by Codex, rated Medium; raised to High here* because the grace is why
   124	  the lease exists and "rotation-during-grace" is the Phase-5 priority case — **fix this before the
   125	  hardware matrix, or it will measure a path the app does not take.**
   126	- **H-W5-6** `dropPeer` never erases the lease and does not disconnect an inbound keeper;
   127	  `onTeardown` has **no production caller** — the app can re-dial someone the user rejected.
   128	- **H-W5-7** The per-encounter candidate is keyed by peer alias, so rotation mints a new one; R7 fix #1 is
   129	  *narrowly alive* (Kimi's correction — it still covers an evicted-`aliasTo`-but-live-`candidateByAlias`
   130	  rediscovery), not dead code.
   131	- **H-DIAG-2** `ReleaseIsolationTests` asserts compile-time constants and CI runs Debug only
   132	  (`ios-build.yml:52`). *Softened per Kimi:* one test is a genuine runtime check. *Worsened per Kimi:* on
   133	  `main` there is **no RunnerTests job in CI at all**.
   134	- **H-DIAG-3** Pre-Dart restoration trusts persisted state incl. a bearer token in `sendWakePing`.
   135	  Deliberate by design (`AppDelegate.swift:13`, `BackgroundBeacon.swift:153`) — fix is a flavor/schema
   136	  stamp with legacy-state invalidation, **not** waiting for Dart. *Both auditors confirmed this framing.*
   137	- **H-ORCH-1** Round-8 sign-off evidence is unreproducible. The transcript
   138	  (`docs/research/2026-07-31/claude_kimi_chat_2026-07-31.md:386`) records
   139	  `/tmp/kimi-r8/…/w5_ownership_r8_kimi_test.dart`, **26 tests**, "259/259" against a committed 233. So
   140	  **26 adversarial probes were cited as sign-off evidence and zero were committed.**
   141	  *Correction of record:* an earlier draft claimed 6 survived in `zz_probe_test.dart`. Codex showed no
   142	  such file exists at HEAD or in `git log --all` — it was a temporary artifact created by one of this
   143	  audit's own subagents and mistaken for committed code. **Standing rule: no review round may cite an
   144	  uncommitted test file as sign-off evidence.**
   145	
   146	**Server / web (Linux side):**
   147	- **H-CFG-1** `verify_jwt` is **true in config but not yet effective** on the deployed builds (the probe
   148	  proves the gateway is not enforcing). On redeploy it *would* take effect and lock out the legitimate
   149	  `sb_secret_` caller. `proximity-wake` has no config entry at all.
   150	- **H-WL-1 / H-WL-2** `waitlist-join` performs an **unauthenticated cross-user UPDATE** and returns
   151	  another person's `ref_code`, zone and position (`0062:100-104`, `:120-131`); and it is an **email
   152	  enumeration oracle** — `0054:74-76` shipped `RETURNS VOID` with a comment promising exactly that
   153	  property, which 0055/0062 silently dropped while leaving the comment in place. The RPC *is* revoked
   154	  from `anon`/`authenticated` (Kimi), but the public Edge Function calls it as service-role, so the
   155	  revoke is not a mitigation.
   156	- **H-SQL-2** *(was C-SQL-2, downgraded)* The Locals path inserts `encounters` with NULL `trust_level`
   157	  and no reciprocity (`0048:337-346`), and `get_locals_feed` unlocks on any active row past the reveal
   158	  delay with no trust-level discrimination (`0048:443-451`).
   159	  **Correction of record:** the earlier premise ("granted to `authenticated`, never revoked; returns raw
   160	  `other_user_id`") was **false**. `0019:2496-2527` revokes `correlate_miles_encounters` from
   161	  `PUBLIC, anon, authenticated, service_role` and the re-grant list omits it (DB confirms
   162	  `{postgres=X/postgres}`); the entry point is `record_location_ping` at `0040:156`, which enforces
   163	  `current_user_can_discover()` and `require_consent(…,'precise_location')` and returns `bigint`. The
   164	  original grep (`00[2-6]*`) excluded 0019 — an asserted verification that was never performed.
   165	- **H-SQL-3** The reciprocity gate binds each direction to `now()`, never to the other, so a "mutual"
   166	  encounter can be assembled from evidence ~30–50 min apart. **Fix corrected by Codex:** comparing reverse
   167	  `received_at` to *forward* `received_at` is a **no-op**, because `record_sighting` upserts the forward
   168	  row with `received_at = v_now` (`0053:119`, `:123`) immediately before calling `correlate_encounter`
   169	  (`:138`). The real fix is to compare the two `observed_at` **capture** times and bind observations to
   170	  the token's validity interval. *Two of Kimi's original fix items survive the refutation and should ship
   171	  with it:* reject `p_observed_at` outside the token's `[valid_from, valid_until]` slot, and stop
   172	  refreshing `received_at` on weaker-RSSI upserts (`0053:123` refreshes unconditionally, which keeps a
   173	  forward sighting reciprocity-eligible indefinitely by re-upsert).
   174	- **H-CONSENT-1** *(downgraded from Critical)* `require_consent` appears **zero times** in 0056 and 0059;
   175	  `venue_anchors` has no RPC at all. Bounded today (0056 documents the gap as deliberate pre-rollout,
   176	  `INRANGE_CALIB_SCAN` defaults false, 0059 is undeployed) — but withdrawal effectiveness must be
   177	  server-side against a stale or modified client.
   178	- **H-PW-1** `enqueue_proximity_wake` accepts any geohash with no proof the caller is there, and
   179	  `findLikelyPeers` performs no blocks/discoverability/consent check. Not live (0059 undeployed).
   180	- **H-RT-1** *(was C-RT-1, downgraded per Codex — a local availability failure, not a security-boundary
   181	  compromise)* `_flushSightings` has no re-entrancy guard (`beacon_service.dart:417-422`); one pass over
   182	  500 records at a 10s timeout is ~83 min and the 45s timer starts 111 more. **Codex's fix is better than
   183	  the original:** a timeout does not cancel the underlying flush — `_stopBle()` must happen *before*
   184	  network draining (`:603`), with a generation check and bounded batches.
   185	- **H-RT-2** RH-1 unfixed on all three counts, and the FGS heartbeat runs in a separate engine so the
   186	  notification clock ticks over a dead scanner.
   187	- **H-RT-3** Buffered sightings reach the classifier with fresh timestamps. The drain *does* preserve
   188	  capture time (`beacon_service.dart:340-343`), but `_ingestForeignSample` discards it at the estimator
   189	  boundary — `range_estimator.dart:75/79` has no timestamp parameter and stamps `_now()` — and sets
   190	  `_lastForeignScanAt = DateTime.now()` (`:2220`). False "Close By", and a dead scanner looks healthy for
   191	  another watchdog cycle. *Kimi refuted this in round 1 and withdrew the refutation in round 2.*
   192	- **H-RT-4** `turnOffBeacon` is the only lifecycle path with no session-generation guard across 6 awaits.
   193	- **H-RT-5** `_hexTo16Bytes` throws on non-32-char hex and `_rotateToken`'s catch then silently disables
   194	  the beacon. *Kimi's sibling:* it also **silently truncates longer hex** — a quieter corruption mode.
   195	- **H-RT-6** The consent gate is a one-shot prefs flag; withdrawal never re-gates; `preciseLocation`
   196	  withdrawal does not stop the beacon's GPS; WiFi scanning is bound to no purpose at all.
   197	- **H-RT-7** `myEncountersProvider` is not user-scoped and is absent from `_clearUserRuntime` — user A's
   198	  encounters render for user B after an account switch.
   199	- **H-RT-8** Backgrounded-iPhone discovery is broken by Apple multi-AD blob offsets on Android 15/16; the
   200	  remedy exists in `apple_overflow_bit.dart` + `AdvertParser.kt` and **is never called from Dart**.
   201	- **H-RT-9** `LocalDb.open()` is unguarded in `main()` before `runApp`, with no `onDowngrade`.
   202	- **H-PRIV-2** Release-reachable PII in logs; the `piiSafe` helper a prior audit called for was never built.
   203	
   204	## MEDIUM / LOW (selected)
   205	
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:20:Five Critical findings total, and after the consensus round **none of them is a W5 state-machine defect** —
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:21:those are rated High/merge-blocking because `INRANGE_W5_LINKS` ships default OFF. One Critical is yours
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:22:(C-DIAG-1, which is Critical precisely because it is *not* behind that flag). The rest of your queue is
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:98:**4. C-DIAG-1 (CRITICAL — the one Critical in your queue) — the diagnostic W5 link layer ships inside release binaries.**
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:178:Production Edge Function redeploy and `verify_jwt` config; the **three** SQL Criticals — `claim_token`
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:192:`C-RT-1` `_flushSightings` has no re-entrancy guard and `turnOffBeacon` awaits it, so the user can tap
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:204:what this round exists to establish, given all suites were green while nine Criticals were live. Watch
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:11:**Evidence convention (corrected after Codex's objection):** every **Critical** and every **disputed**
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:22:**Not ready to trust in the wild.** Five Critical findings, which are **not** a homogeneous group and
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:23:should not be summarised as "all live":
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:33:**Severity convention, settled by the panel:** *Critical* means reachable **now** — either exploitable
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:39:**Why C-DIAG-1 is Critical while the W5 defects are High — these are not in tension.** The W5 *feature*
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:41:compromises. C-DIAG-1 is Critical for precisely the opposite reason: `W5LinkController.swift` is **not**
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:50:Criticals and one High** at authoring time — C-SQL-3, C-PROD-1 (three weeks ago), and H-CONSENT-1.
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:54:## CRITICAL — live today
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:174:- **H-CONSENT-1** *(downgraded from Critical)* `require_consent` appears **zero times** in 0056 and 0059;
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:180:- **H-RT-1** *(was C-RT-1, downgraded per Codex — a local availability failure, not a security-boundary
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:208:victim's rotating token. Becomes Critical only if a mint consumer ignores the corroboration rule.
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:233:## SYSTEMIC — three tests that would have caught two Criticals and one High
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:261:- **Depth of each auditor's check, self-reported:** Codex re-read the source mechanism for every Critical

exec
/bin/bash -lc "nl -ba docs/research/2026-08-01-hardening/transcripts/final_round.md | sed -n '1,100p'
nl -ba docs/research/2026-08-01-hardening/transcripts/codex_final.md | sed -n '1,130p'
nl -ba docs/research/2026-08-01-hardening/CONSENSUS_DIALOGUE.md | sed -n '115,180p'" in /home/hazypiff/in-range
 succeeded in 0ms:
     1	Final round. You have each reviewed this audit independently. I am now putting the other's position in front of you on the points where you disagree, plus my adjudications. Answer only these; everything else is settled.
     2	
     3	Report: /home/hazypiff/in-range/docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md
     4	Evidence: /home/hazypiff/in-range/docs/research/2026-08-01-hardening/verified_findings_working.md
     5	Repo: /home/hazypiff/in-range · W5 worktree: /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
     6	
     7	## 1. Adjudicated in Codex's favour — Kimi, do you accept?
     8	
     9	**H-SQL-5's proposed fix is a no-op.** Kimi proposed: "require the reverse sighting's `received_at` within W of the *forward* sighting's `received_at`, not of `now()`." Codex refuted this, and I verified Codex is right:
    10	`record_sighting` upserts the forward row with `received_at = v_now` (0053:119 on insert, 0053:123 on the conflict path) and only *then* calls `correlate_encounter` (0053:138). So at correlation time the forward row's `received_at` **is** `now()`, and the proposed comparison is identical to the existing predicate.
    11	
    12	Codex's alternative: the real defect is that the two `observed_at` **capture** times are never compared to each other, and observations are not bound to the token's validity interval. Fix those fields instead.
    13	
    14	Kimi: do you accept this? The finding survives; only your fix was wrong.
    15	
    16	## 2. Adjudicated in Codex's favour — a correction to MY finding
    17	
    18	**H-ORCH-1 was wrong, and wrong in my favour, which is worse.** I claimed "only 6 probes are committed, in `test/features/beacon/zz_probe_test.dart`." Codex checked and found no such file at W5 HEAD and none in `git log --all`. I verified: the worktree is clean, `git ls-files` lists 8 tracked files in that directory, and `zz_probe_test.dart` does not exist. It was a **temporary artifact created by one of my own subagents mid-audit**, which I observed and mistook for committed code before that agent deleted it. I cited my own tooling as repository evidence.
    19	
    20	Corrected finding, now stronger: the round-8 transcript (`docs/research/2026-07-31/claude_kimi_chat_2026-07-31.md:386`) records `/tmp/kimi-r8/test/features/beacon/w5_ownership_r8_kimi_test.dart`, **26 tests**, and "full suite at head: 259/259." The committed suite is 233. So **26 adversarial probes were cited as sign-off evidence and zero of them were committed** — not "roughly 20 of 26." My baseline of 233 stands (it was measured before the artifact existed).
    21	
    22	## 3. Open severity dispute — both of you answer
    23	
    24	Codex argues that `C-W5-1`, `C-W5-2`, `C-W5-3` should be **High, not Critical**, because `INRANGE_W5_LINKS` is default OFF and W5 is unreleased — they are pre-merge/rollout blockers rather than live compromises. Kimi rated the class Critical and did not raise the flag argument.
    25	
    26	My adjudication, and I want you both to challenge it if you disagree: **I am adopting Codex's position.** In a report whose top finding is a live, unauthenticated production endpoint, "Critical" should mean *exploitable now*. Reclassifying the W5 defects as **High / merge-blocking** is more honest and costs nothing operationally — they stay at the top of the Mac agent's queue either way. The same logic moves `H-SQL-4` to Medium (the runbook forbids punitive action on `relay_geo`, and the attacker needs the victim's rotating token) and confirms `H-PRIV-1` at Medium, which you both independently reached.
    27	
    28	That leaves the Critical tier as: C-PROD-1 (live, unauthenticated production endpoints), C-SQL-1 (cross-user `token_claim_history` overwrite), C-SQL-3 (`beacon_token_batch` never purged), C-SQL-4 (GPS veto skipped for batch-pre-claimed tokens), C-DIAG-1 (diagnostic layer in release binaries), C-RT-1 — and Codex argues C-RT-1 is also High, being a local availability failure rather than a security-boundary compromise. I am inclined to accept that too, which would leave **five Criticals, all server-side or live**.
    29	
    30	Do you both agree with that final tier? If either of you thinks a demoted item belongs back at Critical, say which and why.
    31	
    32	## 4. Codex's REPORT-META objection — accepted, confirm the remedy
    33	
    34	Codex is right that the report overstates its own evidence: most summarized High findings have no dedicated section in the working file, and the "two tests" section lists three. I am fixing both — the claim will read that Criticals and disputed findings carry full evidence sections, while the High tier is summarized with file:line inline, and the count will say three.
    35	
    36	## Output
    37	
    38	A final verdict line — `CONSENSUS: AGREED`, `AGREED WITH CORRECTIONS`, or `DISPUTED` — then only your remaining disagreements, if any, with the line that settles each. Be brief. If you agree, say so without inventing new objections; if you still disagree on the severity tier, say so plainly and it will ship as a recorded dissent.
     1	OpenAI Codex v0.146.0
     2	--------
     3	workdir: /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
     4	model: gpt-5.6-sol
     5	provider: openai
     6	approval: never
     7	sandbox: read-only
     8	reasoning effort: max
     9	reasoning summaries: none
    10	session id: 019fbecf-119e-76d3-afe3-bacd77c8a66e
    11	--------
    12	user
    13	Final round. You have each reviewed this audit independently. I am now putting the other's position in front of you on the points where you disagree, plus my adjudications. Answer only these; everything else is settled.
    14	
    15	Report: /home/hazypiff/in-range/docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md
    16	Evidence: /home/hazypiff/in-range/docs/research/2026-08-01-hardening/verified_findings_working.md
    17	Repo: /home/hazypiff/in-range · W5 worktree: /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
    18	
    19	## 1. Adjudicated in Codex's favour — Kimi, do you accept?
    20	
    21	**H-SQL-5's proposed fix is a no-op.** Kimi proposed: "require the reverse sighting's `received_at` within W of the *forward* sighting's `received_at`, not of `now()`." Codex refuted this, and I verified Codex is right:
    22	`record_sighting` upserts the forward row with `received_at = v_now` (0053:119 on insert, 0053:123 on the conflict path) and only *then* calls `correlate_encounter` (0053:138). So at correlation time the forward row's `received_at` **is** `now()`, and the proposed comparison is identical to the existing predicate.
    23	
    24	Codex's alternative: the real defect is that the two `observed_at` **capture** times are never compared to each other, and observations are not bound to the token's validity interval. Fix those fields instead.
    25	
    26	Kimi: do you accept this? The finding survives; only your fix was wrong.
    27	
    28	## 2. Adjudicated in Codex's favour — a correction to MY finding
    29	
    30	**H-ORCH-1 was wrong, and wrong in my favour, which is worse.** I claimed "only 6 probes are committed, in `test/features/beacon/zz_probe_test.dart`." Codex checked and found no such file at W5 HEAD and none in `git log --all`. I verified: the worktree is clean, `git ls-files` lists 8 tracked files in that directory, and `zz_probe_test.dart` does not exist. It was a **temporary artifact created by one of my own subagents mid-audit**, which I observed and mistook for committed code before that agent deleted it. I cited my own tooling as repository evidence.
    31	
    32	Corrected finding, now stronger: the round-8 transcript (`docs/research/2026-07-31/claude_kimi_chat_2026-07-31.md:386`) records `/tmp/kimi-r8/test/features/beacon/w5_ownership_r8_kimi_test.dart`, **26 tests**, and "full suite at head: 259/259." The committed suite is 233. So **26 adversarial probes were cited as sign-off evidence and zero of them were committed** — not "roughly 20 of 26." My baseline of 233 stands (it was measured before the artifact existed).
    33	
    34	## 3. Open severity dispute — both of you answer
    35	
    36	Codex argues that `C-W5-1`, `C-W5-2`, `C-W5-3` should be **High, not Critical**, because `INRANGE_W5_LINKS` is default OFF and W5 is unreleased — they are pre-merge/rollout blockers rather than live compromises. Kimi rated the class Critical and did not raise the flag argument.
    37	
    38	My adjudication, and I want you both to challenge it if you disagree: **I am adopting Codex's position.** In a report whose top finding is a live, unauthenticated production endpoint, "Critical" should mean *exploitable now*. Reclassifying the W5 defects as **High / merge-blocking** is more honest and costs nothing operationally — they stay at the top of the Mac agent's queue either way. The same logic moves `H-SQL-4` to Medium (the runbook forbids punitive action on `relay_geo`, and the attacker needs the victim's rotating token) and confirms `H-PRIV-1` at Medium, which you both independently reached.
    39	
    40	That leaves the Critical tier as: C-PROD-1 (live, unauthenticated production endpoints), C-SQL-1 (cross-user `token_claim_history` overwrite), C-SQL-3 (`beacon_token_batch` never purged), C-SQL-4 (GPS veto skipped for batch-pre-claimed tokens), C-DIAG-1 (diagnostic layer in release binaries), C-RT-1 — and Codex argues C-RT-1 is also High, being a local availability failure rather than a security-boundary compromise. I am inclined to accept that too, which would leave **five Criticals, all server-side or live**.
    41	
    42	Do you both agree with that final tier? If either of you thinks a demoted item belongs back at Critical, say which and why.
    43	
    44	## 4. Codex's REPORT-META objection — accepted, confirm the remedy
    45	
    46	Codex is right that the report overstates its own evidence: most summarized High findings have no dedicated section in the working file, and the "two tests" section lists three. I am fixing both — the claim will read that Criticals and disputed findings carry full evidence sections, while the High tier is summarized with file:line inline, and the count will say three.
    47	
    48	## Output
    49	
    50	A final verdict line — `CONSENSUS: AGREED`, `AGREED WITH CORRECTIONS`, or `DISPUTED` — then only your remaining disagreements, if any, with the line that settles each. Be brief. If you agree, say so without inventing new objections; if you still disagree on the severity tier, say so plainly and it will ship as a recorded dissent.
    51	
    52	2026-08-01T19:31:14.304687Z ERROR codex_models_manager::manager: failed to refresh available models: timeout waiting for child process to exit
    53	codex
    54	CONSENSUS: AGREED
    55	tokens used
    56	4,531
    57	CONSENSUS: AGREED
   115	
   116	**Severity: Kimi said Medium, Claude had said High. Claude moved to Medium** — with the clear-on-launch
   117	path established and the precision claim corrected, the factual basis for High was gone.
   118	
   119	---
   120	
   121	## Net effect of the dialogue
   122	
   123	Corrections that only happened because the panel argued:
   124	
   125	| Finding | Before | After | Who moved |
   126	|---|---|---|---|
   127	| C-SQL-2 | Critical, "never revoked" | High, premise rewritten | Claude conceded to Kimi |
   128	| C-W5-1 | Critical, wrong mechanism | Critical, mechanism rewritten | Claude conceded to Kimi |
   129	| C-CONSENT-1 | Critical | High | Claude conceded to Kimi |
   130	| H-PRIV-1 | High, "never cleared" | Medium, rewritten | Both moved; Kimi conceded file, Claude conceded severity |
   131	| H-RT-3 | High | High, sharpened | Kimi withdrew its refutation |
   132	| H-W5-6 (grace unreachable) | Medium (Codex) | High | Claude raised Codex's rating |
   133	| C-SQL-4 (veto skip) | not found | Critical | Kimi found it |
   134	
   135	Three of the panel's members each found something the others missed, and three findings were corrected
   136	or downgraded that a single reviewer would have shipped wrong.
   137	
   138	---
   139	
   140	## Round 3 — Codex challenges the report, and corrects Claude twice
   141	
   142	Verdict: Codex found most of what was wrong with **Claude's own work**.
   143	
   144	### Codex caught Claude citing its own tooling as repository evidence
   145	
   146	> At audited W5 HEAD there is no `zz_probe_test.dart`, and no such file appears in `git log --all`.
   147	
   148	**Claude verified and conceded.** The worktree is clean, `git ls-files` lists 8 tracked files in that
   149	directory, and the file does not exist. It was a **temporary artifact created by one of this audit's own
   150	subagents**, observed mid-run and mistaken for committed code before that agent deleted it.
   151	
   152	Codex then located the real record — `claude_kimi_chat_2026-07-31.md:386` naming
   153	`/tmp/kimi-r8/…/w5_ownership_r8_kimi_test.dart`, 26 tests, "259/259" — which makes the finding *stronger*:
   154	**26 probes cited as sign-off evidence, zero committed**, not "roughly 20 of 26." Claude's 233 baseline
   155	survives, having been measured before the artifact existed.
   156	
   157	### Codex settled the one direct Kimi-vs-Codex conflict
   158	
   159	Kimi's proposed fix for the reciprocity window — compare reverse `received_at` to *forward*
   160	`received_at` — was refuted as a no-op:
   161	
   162	> Because the current forward row is upserted with `received_at=now()` immediately before correlation at
   163	> 0053:122, comparing reverse receipt time to forward receipt time is effectively the existing predicate.
   164	
   165	Claude verified `0053:119`, `:123`, `:138` and ruled for Codex. **Kimi accepted in round 4:**
   166	
   167	> I accept; my proposed comparison was a no-op. Verified myself … Codex's redirect is correct.
   168	
   169	Kimi also salvaged the two parts of its fix that survive independently: bind `p_observed_at` to the
   170	token's validity slot, and stop refreshing `received_at` on weaker-RSSI upserts.
   171	
   172	### Codex caught the report overstating its own evidence
   173	
   174	> The working file has no dedicated sections for most summarized High findings … The "two tests" section
   175	> actually lists three.
   176	
   177	Both accurate; both fixed.
   178	
   179	### The severity argument that reshaped the report
   180	

exec
/bin/bash -lc "nl -ba docs/research/2026-08-01-hardening/CONSENSUS_DIALOGUE.md | sed -n '172,250p'
rtk rg -n 'C-W5|C-RT-1|nine Critical|nine|all server-side or live|five Critical|all live|Criticals' docs/research/2026-08-01-hardening --glob '"'!transcripts/**'"'" in /home/hazypiff/in-range
 succeeded in 0ms:
   172	### Codex caught the report overstating its own evidence
   173	
   174	> The working file has no dedicated sections for most summarized High findings … The "two tests" section
   175	> actually lists three.
   176	
   177	Both accurate; both fixed.
   178	
   179	### The severity argument that reshaped the report
   180	
   181	Codex argued `C-W5-1/2/3` and `C-RT-1` are **High, not Critical**, because `INRANGE_W5_LINKS` is
   182	default-off on an unreleased branch — merge blockers, not live compromises. Claude adopted it: in a report
   183	whose top finding is a live unauthenticated production endpoint, *Critical* should mean **exploitable
   184	now**. Kimi agreed and said why its own rating had been wrong:
   185	
   186	> My Critical rating of the W5 class did not weigh the flag, and it should have … the same discipline I
   187	> applied when I argued C-CONSENT-1 down on flag-gating grounds.
   188	
   189	---
   190	
   191	## Round 4 — final verdicts
   192	
   193	- **Codex: `CONSENSUS: AGREED`** — no remaining disagreements.
   194	- **Kimi: `CONSENSUS: AGREED`** — "No remaining disagreements. The report as amended … has my
   195	  co-signature."
   196	
   197	## Final disagreement ledger
   198	
   199	| Finding | Before | After | Who moved, and to whom |
   200	|---|---|---|---|
   201	| C-SQL-2 → H-SQL-2 | Critical, "never revoked" | High, premise rewritten | Claude → Kimi (Claude's own verification error) |
   202	| H-ORCH-1 | "~20 of 26 lost, 6 committed" | 26 cited, **0** committed | Claude → Codex (Claude cited its own subagent's artifact) |
   203	| H-SQL-3 fix | compare receipt times | compare **capture** times + bind to token validity | Kimi → Codex |
   204	| C-W5-1/2/3 | Critical | High / merge-blocking | Claude + Kimi → Codex |
   205	| C-RT-1 → H-RT-1 | Critical | High | Claude + Kimi → Codex |
   206	| C-W5-1 mechanism | "treated as fresh" | uncommitted-path processing | Claude → Kimi |
   207	| C-CONSENT-1 | Critical | High | Claude → Kimi |
   208	| H-SQL-4 | High | Medium | Claude → Codex |
   209	| H-PRIV-1 | High, "never cleared" | Medium, rewritten | Kimi conceded file; Claude conceded severity + clear path |
   210	| H-RT-3 | High | High, sharpened | Kimi withdrew its own refutation |
   211	| H-W5-5 (grace) | not found | High | Codex found it; Claude raised it above Codex's own rating |
   212	| C-SQL-4 (veto skip) | not found | Critical | Kimi found it |
   213	
   214	**Every participant was corrected by another, and every participant corrected someone.** Three findings
   215	would have shipped wrong from any single reviewer; two Criticals would have been missed entirely.
122 matches in 11 files:

docs/.../2026-08-01-hardening/CONSENSUS_DIALOGUE.md:36:**Codex independently confirmed `C-W5-2`** (restored peripheral loses both no...
docs/.../2026-08-01-hardening/CONSENSUS_DIALOGUE.md:74:Also accepted from Kimi: `C-W5-1`'s *mechanism* was wrong (the `realId` looku...
docs/.../2026-08-01-hardening/CONSENSUS_DIALOGUE.md:128:| C-W5-1 | Critical, wrong mechanism | Critical, mechanism rewritten | Claude...
docs/.../2026-08-01-hardening/CONSENSUS_DIALOGUE.md:181:Codex argued `C-W5-1/2/3` and `C-RT-1` are **High, not Critical**, because `I...
docs/.../2026-08-01-hardening/CONSENSUS_DIALOGUE.md:204:| C-W5-1/2/3 | Critical | High / merge-blocking | Claude + Kimi → Codex |
docs/.../2026-08-01-hardening/CONSENSUS_DIALOGUE.md:205:| C-RT-1 → H-RT-1 | Critical | High | Claude + Kimi → Codex |
docs/.../2026-08-01-hardening/CONSENSUS_DIALOGUE.md:206:| C-W5-1 mechanism | "treated as fresh" | uncommitted-path processing | Claud...
docs/.../2026-08-01-hardening/CONSENSUS_DIALOGUE.md:215:would have shipped wrong from any single reviewer; two Criticals would have b...
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:23:should not be summarised as "all live":
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:50:Criticals and one High** at authoring time — C-SQL-3, C-PROD-1 (three weeks a...
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:180:- **H-RT-1** *(was C-RT-1, downgraded per Codex — a local availability failur...
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:233:## SYSTEMIC — three tests that would have caught two Criticals and one High
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:178:Production Edge Function redeploy and `verify_jwt` config; the **three** SQL ...
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:192:`C-RT-1` `_flushSightings` has no re-entrancy guard and `turnOffBeacon` await...
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:204:what this round exists to establish, given all suites were green while five C...
docs/.../transcripts/codex_consensus_r1.md:1191:Criticals at authoring time.
docs/.../transcripts/codex_consensus_r1.md:1265:### C-W5-1 🔴 A committed encounter reached by `realId` bypasses the sticky-ke...
docs/.../transcripts/codex_consensus_r1.md:1274:### C-W5-2 🔴 Peripheral restoration permanently nils the notify characteristi...
docs/.../transcripts/codex_consensus_r1.md:1281:### C-RT-1 🔴 `_flushSightings` has no re-entrancy guard; "turn beacon off" ca...
docs/.../transcripts/codex_consensus_r1.md:1366:## SYSTEMIC — the two tests that would have caught five Criticals
docs/.../transcripts/codex_consensus_r1.md:1378:2. **C-SQL-1, C-SQL-2, C-SQL-3, C-CONSENT-1** — four SQL fixes, all small, al...
docs/.../transcripts/codex_consensus_r1.md:1380:4. **C-W5-1** — two-line hoist in each implementation + the vector that pins ...
docs/.../transcripts/codex_consensus_r1.md:1381:5. **C-W5-2, C-W5-3, C-RT-1** — the three wedges.
docs/.../transcripts/codex_consensus_r1.md:1741:## 🔴 C-W5-1 — A committed encounter reached by `realId` bypasses the sticky-k...
docs/.../transcripts/codex_consensus_r1.md:1788:## 🔴 C-W5-2 — Peripheral restoration permanently nils the notify characterist...
docs/.../transcripts/codex_consensus_r1.md:1815:## 🔴 C-W5-3 — A dial that connects but dies before HELLO_ACK leaks a `pending...
docs/.../transcripts/codex_consensus_r1.md:1843:## 🔴 C-RT-1 — `_flushSightings` has no re-entrancy guard: one flush loop comp...
docs/.../transcripts/codex_consensus_r1.md:2022:- **C-W5-2** (restored peripheral loses both notify characteristics) — confir...
docs/.../transcripts/codex_consensus_r1.md:16407:## 🔴 C-W5-2 — Peripheral restoration permanently nils the notify characterist...
docs/.../transcripts/codex_consensus_r1.md:16434:## 🔴 C-W5-3 — A dial that connects but dies before HELLO_ACK leaks a `pending...
  +57 more in docs/.../transcripts/codex_consensus_r1.md
docs/.../transcripts/codex_final.md:36:Codex argues that `C-W5-1`, `C-W5-2`, `C-W5-3` should be **High, not Critical...
docs/.../transcripts/codex_final.md:40:That leaves the Critical tier as: C-PROD-1 (live, unauthenticated production ...
docs/.../transcripts/codex_final.md:46:Codex is right that the report overstates its own evidence: most summarized H...
docs/.../transcripts/final_round.md:24:Codex argues that `C-W5-1`, `C-W5-2`, `C-W5-3` should be **High, not Critical...
docs/.../transcripts/final_round.md:28:That leaves the Critical tier as: C-PROD-1 (live, unauthenticated production ...
docs/.../transcripts/final_round.md:34:Codex is right that the report overstates its own evidence: most summarized H...
docs/.../transcripts/kimi_consensus_r1.md:9:6. C-W5-1: Dart w5_ownership.dart:321 vs 351, Swift W5Ownership.swift:250 vs ...
docs/.../transcripts/kimi_consensus_r1.md:10:7. C-W5-2: BackgroundBeacon.swift:736-751, :714-734.
docs/.../transcripts/kimi_consensus_r1.md:11:8. C-W5-3: W5LinkController.swift:240-254, W5Ownership.swift:516-530.
docs/.../transcripts/kimi_consensus_r1.md:12:9. C-RT-1: beacon_service.dart:417-422, :603, :2449-2483 (main repo).
docs/.../transcripts/kimi_consensus_r1.md:31:Subagent 1 (explore): verify all W5/iOS findings (C-W5-1, C-W5-2, C-W5-3, C-D...
docs/.../transcripts/kimi_consensus_r1.md:33:Subagent 2 (explore): verify Dart/runtime findings (C-RT-1, H-RT-2..H-RT-9) a...
docs/.../transcripts/kimi_consensus_r1.md:103:- C-W5-1 OVERSTATED: the claimed mechanism ("treated as fresh, keeper silentl...
docs/.../transcripts/kimi_consensus_r1.md:108:- C-W5-2, C-W5-3, H-W5-3, H-W5-4 confirmed.
docs/.../transcripts/kimi_consensus_r1.md:134:Verdict: AGREED WITH CORRECTIONS. Load-bearing findings (C-PROD-1, C-SQL-1, C...
docs/.../transcripts/kimi_consensus_r1.md:144:4. **C-W5-1 — mechanism wrong, defect real.** The claimed "both lookups miss ...
docs/.../transcripts/kimi_consensus_r1.md:168:Also C-RT-1 confirmed with bound (needs 500 located records vs blackholing se...
docs/.../transcripts/kimi_consensus_r1.md:170:Depth statement: personally re-verified: C-PROD-1 reasoning (service_auth.ts,...
docs/.../transcripts/kimi_consensus_r1.md:172:Verdict: AGREED WITH CORRECTIONS. No load-bearing finding is wrong; C-PROD-1,...
docs/.../transcripts/kimi_consensus_r1.md:178:The load-bearing spine holds: C-PROD-1, C-SQL-1, C-SQL-3, C-SQL-4, C-CONSENT-...
docs/.../transcripts/kimi_consensus_r1.md:184:**Delegate-verified** (three independent adversarial passes, each instructed ...
  +2 more in docs/.../transcripts/kimi_consensus_r1.md
docs/.../transcripts/kimi_consensus_r2.md:127:Everything else from round 1 stands as you've already accepted it (C-SQL-2 → ...
docs/.../transcripts/kimi_final.md:5:Point 3: severity tier — my position: agree with the demotions. In my own fir...
docs/.../transcripts/kimi_final.md:27:Point 3: agree with the tier. My own reasoning: the W5 trio is behind a defau...
docs/.../transcripts/kimi_final.md:39:**3. Severity tier — I agree, including C-RT-1.** My Critical rating of the W...
docs/.../transcripts/kimi_final.md:41:**4. REPORT-META remedy — confirmed.** "Criticals and disputed findings carry...
docs/.../transcripts/kimi_final.md:43:No remaining disagreements. The report as amended — five Criticals, the corre...
docs/.../transcripts/kimi_round2.md:11:**C-W5-1 mechanism.** Accepted. `realId = min(my, peer) = peerCandidate` in t...
docs/.../2026-08-01-hardening/verified_findings_working.md:338:## 🔴 C-W5-1 — A committed encounter reached by `realId` bypasses the sticky-k...
docs/.../2026-08-01-hardening/verified_findings_working.md:385:## 🔴 C-W5-2 — Peripheral restoration permanently nils the notify characterist...
docs/.../2026-08-01-hardening/verified_findings_working.md:412:## 🔴 C-W5-3 — A dial that connects but dies before HELLO_ACK leaks a `pending...
docs/.../2026-08-01-hardening/verified_findings_working.md:440:## 🔴 C-RT-1 — `_flushSightings` has no re-entrancy guard: one flush loop comp...
docs/.../2026-08-01-hardening/verified_findings_working.md:615:- **C-W5-2** (restored peripheral loses both notify characteristics) — confir...

exec
/bin/bash -lc "nl -ba docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md | sed -n '160,210p'
stat -c '%y %s %n' docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md" in /home/hazypiff/in-range
 succeeded in 0ms:
   160	probes that pin the alias-stomp bug class are gone from CI, and the class can regress silently behind a
   161	green suite. Please reconstruct them as committed tests.
   162	
   163	Standing rule from here: **no review round may cite an uncommitted test file as sign-off evidence.**
   164	
   165	### Also yours, lower priority (detail in the working file)
   166	
   167	`H-W5-3` no lease persistence, and restoration actively re-handshakes restored links with fresh identity
   168	that the peer correctly rejects (≥5-min blackout plus a wedged lease) · `H-W5-4` `dropPeer` never erases
   169	the lease and does not disconnect an inbound keeper at all — `onTeardown` has **no production caller**, so
   170	the app can re-dial someone the user just rejected · `H-W5-5` the per-encounter candidate is keyed by peer
   171	alias, so token rotation mints a new one, making R7 fix #1 dead code in production · the `bb_wake_log.txt`
   172	writer has no cap or rotation and uses the **trapping** `FileHandle.write`, which is an uncatchable crash
   173	on a full disk — switch to `try h.write(contentsOf:)` · the RSSI log needs `isExcludedFromBackup` and a
   174	file-protection class.
   175	
   176	### What the Linux side is taking — do not duplicate
   177	
   178	Production Edge Function redeploy and `verify_jwt` config; the **three** SQL Criticals — `claim_token`
   179	cross-user overwrite (C-SQL-1), `beacon_token_batch` retention (C-SQL-3), and the GPS veto skipped for
   180	batch-pre-claimed tokens (C-SQL-4) — plus the two SQL findings the consensus round downgraded to High,
   181	`correlate_miles_encounters` encounter fabrication (H-SQL-2) and missing `require_consent` on the three
   182	newest write paths (H-CONSENT-1); the waitlist endpoint's unauthenticated
   183	cross-user write and its email-enumeration oracle; `scan_relay_abuse` victim-attribution; proximity-wake
   184	authorization; the Android Apple-multi-AD advert parser wiring; and the three systemic tests (a pgTAP
   185	assertion that every user-scoped-table RPC calls `require_consent`, a retention test that fails when a
   186	table is added without a `cleanup_ephemeral_data` entry, and a deploy-parity probe asserting `405` on
   187	`GET` for every service-role function).
   188	
   189	### Shared Dart runtime — tell us which you want
   190	
   191	These live in `lib/` and affect both platforms, so say which you'd rather own and Linux takes the rest:
   192	`C-RT-1` `_flushSightings` has no re-entrancy guard and `turnOffBeacon` awaits it, so the user can tap
   193	"off" and have BLE keep running for up to 83 minutes on a bad network · `H-RT-3` natively-buffered
   194	sightings replay into the live 90s window with *fresh* timestamps, producing a false "Close By" for a peer
   195	who was near 20 minutes ago and masking a dead scanner from the watchdog · `H-RT-4` `turnOffBeacon` is the
   196	only lifecycle path with no session-generation guard across six awaits · `H-RT-5` an unvalidated server
   197	token crashes the beacon and `_rotateToken`'s catch then silently disables it · `H-RT-7`
   198	`myEncountersProvider` is not user-scoped, so user A's encounters render for user B after an account
   199	switch.
   200	
   201	### Working agreement
   202	
   203	Branch off `fix/w5-encounter-lease`. Every fix needs a test that fails before and passes after — that is
   204	what this round exists to establish, given all suites were green while five Criticals and the entire
   205	High tier below were present in the code. Watch
   206	every rebase: a previous one silently dropped three third-party commits, so verify `git log origin..HEAD`
   207	still contains everything that is not yours before any force-push. Post findings and questions on PR #9;
   208	if anything above does not match what you see in the code, say so on the thread rather than adapting to
   209	it silently — we would rather hear that a finding is wrong than have you work around it.
2026-08-01 15:49:58.732533428 -0400 20113 docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md
2026-08-01 15:50:54.036011051 -0400 15456 docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md

exec
/bin/bash -lc "date '+%Y-%m-%d %H:%M:%S.%N %z'
stat -c '%y %s %n' docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md" in /home/hazypiff/in-range
 succeeded in 0ms:
2026-08-01 15:51:36.707191522 -0400
2026-08-01 15:49:58.732533428 -0400 20113 docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md
2026-08-01 15:50:54.036011051 -0400 15456 docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md

exec
/bin/bash -lc "nl -ba docs/research/2026-08-01-hardening/verified_findings_working.md | sed -n '1,90p'
nl -ba docs/research/2026-08-01-hardening/verified_findings_working.md | sed -n '320,470p'
nl -ba docs/research/2026-08-01-hardening/verified_findings_working.md | sed -n '590,640p'
rtk rg -n '"'^## .*W5|''^## .*RT-1|Severity:|downgrad|reclass|final'"' docs/research/2026-08-01-hardening/verified_findings_working.md" in /home/hazypiff/in-range
 succeeded in 0ms:
     1	# Hardening round 2026-08-01 — verified findings (working file)
     2	
     3	Findings below are verified by me directly against code/repo state, not taken on a
     4	reviewer's word. Each carries the evidence command or file:line that proves it.
     5	
     6	---
     7	
     8	## H-ORCH-1 — Round-8 sign-off evidence is partially unreproducible; ~20 adversarial probes lost
     9	
    10	**Severity:** High (process / regression-coverage, not a runtime defect)
    11	**Branch:** `fix/w5-encounter-lease` @ `83890e6`
    12	
    13	**Claim on record (PR #9, round-8 PASS comment + project memory):** executable evidence
    14	for the software green-light was "Kimi ported round-7 suite 16/16 (probe-4 gone) + 10 new
    15	adversarial probes; Claude re-ran 26/26; Dart 259/259". The regression file was recorded as
    16	`/tmp/kimi-r7/test/features/beacon/w5_ownership_r7_kimi_test.dart` and explicitly noted as
    17	"uncommitted, machine-local".
    18	
    19	**Verified state today (2026-08-01):**
    20	
    21	| Fact | Evidence |
    22	|---|---|
    23	| W5 branch Dart suite = **233/233**, not 259 | `flutter test` on worktree of `fix/w5-encounter-lease` |
    24	| main Dart suite = **183/183** | `flutter test` on `/home/hazypiff/in-range` |
    25	| Kimi r7 suite file **does not exist** | `ls /tmp/kimi-r7/...` → missing (tmp cleared) |
    26	| It was **never committed on any branch** | `git log --all --oneline --name-only \| grep -i 'r7_kimi\|w5_ownership_r7'` → no match |
    27	| Only **6** probes are committed | `test/features/beacon/zz_probe_test.dart` = 6 `test(` cases |
    28	
    29	233 (committed) + 26 (machine-local) = 259 — which reconciles the sign-off number exactly and
    30	confirms the 26 probes were counted as evidence but never landed in the repo.
    31	
    32	**Why this matters.** The round-7 defect (probe-4 alias-stomp wedge: lost ALIAS_ROLL +
    33	keeper-down grace → `onDiscovered` stomps an in-grace `_Enc`, generation reset, permanent
    34	stale-gen wedge) was the single most severe correctness bug found in this subsystem. The tests
    35	that pin it are, for the most part, gone: ~20 of the 26 probes cited in the PASS are not in the
    36	repo, not in CI, and their source directory has been deleted. The bug class can regress silently
    37	and the next reviewer will see a green suite.
    38	
    39	This also means the round-8 PASS cannot be independently re-verified as written — an auditor
    40	today can reproduce 233 of the 259 claimed assertions.
    41	
    42	**Fix:** reconstruct the lost probes as committed tests under
    43	`test/features/beacon/` (they must run in CI), and adopt a standing rule that no review round
    44	may cite an uncommitted test file as sign-off evidence. Any probe that justifies a PASS must be
    45	committed in the same change that claims it.
    46	
    47	**Confidence:** CERTAIN (reproduced every fact above on this machine).
    48	
    49	---
    50	
    51	## C-DIAG-1 — Diagnostic W5 link layer + plaintext RSSI log ship in production binaries, gated only by a persisted bool
    52	
    53	**Severity:** Critical (privacy: plaintext proximity records written by a release build)
    54	**Branch:** `fix/w5-encounter-lease`
    55	
    56	**Verified evidence:**
    57	- The ENTIRE iOS tree contains exactly **three** `#if INRANGE_DIAG` sites, all in
    58	  `BackgroundBeacon.swift` (lines 52, 68, 694). `W5LinkController.swift` (701 lines,
    59	  the second diagnostic subsystem) has **zero**.
    60	  Proof: `grep -rn INRANGE_DIAG ios/Runner/ ios/RunnerTests/`
    61	- The W5 activation gate is a persisted runtime boolean, not a compile-time flag:
    62	  `BackgroundBeacon.swift:120` → `var w5LinksEnabled: Bool { defaults.bool(forKey: Self.keyW5Links) }`,
    63	  key `"bb.w5links"` (`:124`), written only from the Dart method channel (`:294`).
    64	- `W5LinkController.recordRssi()` (`:633-650`) appends
    65	  `{"token":"<hex>","rssi":N,"ts":<epoch ms>}` to `Documents/w5_rssi_log.jsonl`
    66	  whenever the app is not foreground-active. No compile-time gate.
    67	- Call site `BackgroundBeacon.swift:1227` (`didReadRSSI`) invokes it for any peer in the
    68	  W5 session map.
    69	
    70	**CORRECTION to the reviewer's framing (verified):** the reviewer wrote that `recordRssi`
    71	"has no gate at all". That overstates it. W5 sessions only enter the `w5[]` map behind
    72	`if w5LinksEnabled` (`BackgroundBeacon.swift:956`), so the effective gate on the file write
    73	IS `bb.w5links`. The finding survives the correction and is arguably worse framed correctly:
    74	issue #8's stated requirement is that a persisted flag must NOT be the thing standing between
    75	a release binary and diagnostic behavior, because the stale persisted value is `true` until
    76	Dart overwrites it. That is exactly this mechanism.
    77	
    78	**Impact:** a release build that inherits `bb.w5links=true` from a prior diag install forms
    79	W5 links and writes plaintext BLE token hex + RSSI + timestamps to `Documents/` before Dart
    80	attaches. Token hex + timestamp is proximity-linkable data in a build whose privacy posture
    81	says it is not collected.
    82	
    83	**Fix:** `#if INRANGE_DIAG`-wrap `w5LinksEnabled` (`#else false`), wrap the `recordRssi` file
    84	branch, and exclude `W5LinkController.swift` from the production target's Sources phase until
    85	W5 actually ships.
    86	
    87	**Confidence:** CERTAIN (every line above read directly).
    88	
    89	---
    90	
   320	that one checked the *wrong* purpose; these check *no* purpose.
   321	
   322	**Fix:** add `require_consent(v_uid,'ble_proximity')` to `record_rssi_batch`,
   323	`require_consent(v_uid,'precise_location')` to `enqueue_proximity_wake`, convert the `venue_anchors`
   324	insert to a SECURITY DEFINER RPC with the same check, and add a `preciseLocation` branch to
   325	`consent_screen.dart`'s withdrawal handler (it currently handles only `bleProximity` and
   326	`photoProcessing`).
   327	
   328	**Structural fix worth more than any of the above:** a pgTAP assertion that every RPC inserting into a
   329	user-scoped table calls `require_consent`, plus a retention test that fails when a new table is added
   330	without an entry in `cleanup_ephemeral_data`. Those two tests would have caught C-SQL-3 and
   331	C-CONSENT-1 at authoring time. Both defects exist because these invariants are enforced by hand-applied
   332	convention with nothing proving coverage.
   333	
   334	**Confidence:** CERTAIN.
   335	
   336	---
   337	
   338	## 🔴 C-W5-1 — A committed encounter reached by `realId` bypasses the sticky-keeper branch; the keeper is silently displaced
   339	
   340	**Severity:** Critical (reproduces the original #7 duplicate-keeper defect, no attacker required)
   341	**Branch:** `fix/w5-encounter-lease`
   342	
   343	**Verified structurally in BOTH implementations — the committed check precedes the `realId` lookup:**
   344	
   345	| | committed branch | `realId` fallback |
   346	|---|---|---|
   347	| Dart `lib/features/beacon/w5_ownership.dart` | `:321` `if (e != null && e.committed) {` | `:351` `e ??= _enc[realId];` |
   348	| Swift `ios/Runner/W5Ownership.swift` | `:250` `if let ec = e, ec.committed {` | `:279` `if e == nil { e = enc[realId] }` |
   349	
   350	`e` at the committed check comes only from `_locate(peerAlias, myCandidate)` plus the `peerPrevAlias`
   351	fallback. When the lease key is the **peer's** candidate (`peerCandidate < myCandidate`) and the incoming
   352	`peerAlias` is not yet in `_aliasTo`, both lookups miss, the committed branch is skipped, and the
   353	encounter is then picked up by `_enc[realId]` **as if it were a fresh negotiating encounter**.
   354	
   355	**Executed proof (reviewer ran this against the Dart oracle):** committed encounter with keeper `p1`/`L5`;
   356	a second `onControl` under a rotated (unknown) alias yields effects `[W5SendPropose]` — **no close of the
   357	intruder, no `owns`** — and `committedKeeper` moves `p1 → p2`, `linkId` `L5 → L0`. The control probe using
   358	the *known* alias correctly yields `[W5RejectInbound(p2)]` with the keeper unchanged, isolating the cause
   359	to the `_locate` miss.
   360	
   361	**This violates the design doc explicitly** (`docs/W5_ENCOUNTER_LEASE_DESIGN.md:295-296`):
   362	"A committed keeper is sticky … a smaller-central intruder is closed without displacing the winner.
   363	Committed leases never rekey."
   364	
   365	**Production trigger — no attacker needed.** `W5LinkController.swift:104` mints the local candidate
   366	per peer alias (`candidate(for: peerTokenHex)`). The peer rotates its ~15-minute token; `HELLO_ACK`
   367	(`W5Codec.swift:50`) has **no `prevAlias` field at all**, and the outbound call site
   368	(`W5LinkController.swift:208-211`) passes none — so on the outbound path a rotated peer alias is
   369	unresolvable by construction. The inbound path (`:317`) does pass `peerPrevAlias`, which is why the
   370	existing vector 2 is green and this stayed hidden.
   371	
   372	**Consequence:** two live physical links to one peer, both kept alive; the adapter still holds `owns(p1)`
   373	while the oracle reports `p2`, so the two endpoints can settle on **different** committed links — exactly
   374	the #7 duplicate-keeper / double-counted-RSSI failure this state machine exists to prevent.
   375	
   376	**Fix:** hoist the `realId` resolution above the committed check in both implementations (a two-line
   377	change each), so a committed encounter always enters the sticky branch however it was located.
   378	Belt-and-braces: have `committedKeeper`/`committedLinkId` return a winner *stored at commit* rather than
   379	recomputing `winner()` from a mutable `links` map.
   380	
   381	**Confidence:** CERTAIN (structure verified in both languages by direct read; behaviour executed in Dart).
   382	
   383	---
   384	
   385	## 🔴 C-W5-2 — Peripheral restoration permanently nils the notify characteristics: the peripheral can never send another control message
   386	
   387	**Severity:** Critical
   388	**File:** `ios/Runner/BackgroundBeacon.swift:736-751` (`willRestoreState`), `:714-734`, `:396-421`
   389	
   390	`willRestoreState` sets `didRestorePeripheral = true` and `serviceAdded = true` but never re-binds
   391	`controlNotifyChar` / `keepaliveNotifyChar` from the restored service's characteristics. Those objects are
   392	created **only** inside `if !serviceAdded` in `reconfigureAdvertising`, so after a restoration relaunch
   393	both stay `nil` for the entire process lifetime.
   394	
   395	The device still advertises and still answers reads, so it looks healthy — but `notifyControl`
   396	(`W5LinkController.swift:531-536`) returns early on every call. A central connects, subscribes, writes
   397	HELLO, and we `respond(.success)` to the ATT write so it believes the write landed — while **the HELLO_ACK
   398	is silently discarded**. Both endpoints stall permanently. Every `sendPropose`/`sendAck`/`sendReject` from
   399	the peripheral role is dropped.
   400	
   401	**Why this is the normal path, not an edge case:** for an app whose entire design is "iOS relaunches us
   402	for BLE events", the restoration launch is the common case. Recovery requires a Bluetooth power cycle or a
   403	non-restoration relaunch.
   404	
   405	**Fix:** in `willRestoreState`, walk `svc.characteristics` and re-bind both references; set
   406	`serviceAdded = false` (forcing a clean re-add) if either cannot be recovered.
   407	
   408	**Confidence:** CERTAIN.
   409	
   410	---
   411	
   412	## 🔴 C-W5-3 — A dial that connects but dies before HELLO_ACK leaks a `pendingDial` forever: the encounter can never commit and can never be erased
   413	
   414	**Severity:** Critical
   415	**Files:** `ios/Runner/W5LinkController.swift:240-254`; `ios/Runner/W5Ownership.swift:516-530`, `:390-406`
   416	
   417	Only `didFailToConnect` reaches `onDialFailed`. "Connected, then died before HELLO_ACK" arrives on
   418	`didDisconnectPeripheral` → `linkDown` → `onLinkDown`, whose first act is
   419	`handleTo.removeValue(forKey: handle)` — but the handle was never mapped (mapping happens in `onControl`,
   420	which requires HELLO_ACK), so it returns `[]` immediately. `pendingDials` and `dialInFlight` survive.
   421	
   422	Resulting permanent state for that peer: `maybeCommit` bails on `!e.pendingDials.isEmpty` so the encounter
   423	**can never commit**; `onDiscovered` returns `[]` because `!e.inGrace` so we **never dial again**; and
   424	nothing erases the lease (grace was never entered, `onDialFailed` never fires, `onTeardown` has no
   425	production caller). If the peer later dials us, we broadcast an unmatchable PROPOSE **every 8 seconds for
   426	the life of the encounter** while never committing — and because commit never happens, the loser-closing
   427	never runs, which is issue #7 reopened silently for that pair.
   428	
   429	The triggers are all mundane: peer walks out of range after `didConnect`; the 10s watchdog
   430	(`BackgroundBeacon.swift:967-973`) cancels the connection without calling `dialFailed`; a CA6E decode
   431	violation; a peer with no CA6E characteristic.
   432	
   433	**Fix:** in `linkDown`/`closeOutboundLink`, branch on `link.established` — if false, feed
   434	`onDialFailed(linkId:)` instead of `onLinkDown`. Add a TTL sweep for `pendingDials`.
   435	
   436	**Confidence:** CERTAIN.
   437	
   438	---
   439	
   440	## 🔴 C-RT-1 — `_flushSightings` has no re-entrancy guard: one flush loop compounds per 45s on a slow network, and "turn beacon off" hangs for up to 83 minutes
   441	
   442	**Severity:** Critical
   443	**File:** `lib/features/beacon/beacon_service.dart:417-422`, `:2449-2483` (main)
   444	
   445	The 45s periodic timer calls `_flushSightings()` without awaiting or guarding it. Each pass awaits up to
   446	500 RPCs **sequentially at a 10s timeout** — ~83 minutes per pass on the half-dead-network condition this
   447	same file documents twice ("with no/half-dead network this RPC *HANGS*"). The timer fires 111 more times
   448	inside that window, each starting another full pass over the same still-populated queue. Loops grow
   449	linearly with no ceiling.
   450	
   451	Every sibling drain in this codebase IS guarded — `RssiUploader.flush` has `if (_busy) return`,
   452	`_drainNativeBuffer` has `_nativeDrainInFlight`. The omission looks accidental.
   453	
   454	**User-visible consequence:** `turnOffBeacon` awaits this flush (`:603`), holding `BeaconController._busy`.
   455	**The user taps "off" and nothing happens for up to 83 minutes while BLE keeps running.**
   456	
   457	**Fix:** add a `_flushInFlight` guard with a pending-fold, mirroring `_drainNativeBuffer`; bound the
   458	per-pass record count; put a `.timeout()` on the flush inside `turnOffBeacon` so teardown can never be
   459	held hostage by the network.
   460	
   461	**Confidence:** CERTAIN (missing guard); LIKELY that this is a — possibly *the* — RH-1 wedge mechanism.
   462	
   463	---
   464	
   465	# ROUND 2 — Kimi K3 independent pass (verified additions)
   466	
   467	## 🔴 C-SQL-4 (NEW, from Kimi) — batch-pre-claimed tokens skip the GPS veto entirely
   468	
   469	**Severity:** Critical
   470	**File:** `0053_late_evidence_tolerance.sql:179-182`
   590	
   591	**Fix:** expose an `isInGrace(alias:)`/`isInGrace(peripheral:)` query and bypass `tokenCache` +
   592	`connectRetryFloor` for bounded W5 recovery, or clear those entries for that peripheral when the keeper
   593	drops.
   594	
   595	**Confidence:** CERTAIN (constants and both branches read directly).
   596	
   597	## M-W5-7 (NEW, from Codex) — the "reactive cascade with no timer" claim has a timer-only liveness gap
   598	
   599	`BackgroundBeacon.swift:1090`, `:1191`, `:1202`, `:792`. The peripheral emits its notification
   600	immediately in response to the central's write, so the central receives it while `lastBeatAt` is still
   601	inside the cadence guard and `w5MaybeBeat` returns. The **only** next write is then scheduled by an
   602	`asyncAfter` four seconds later. If iOS suspends the process before that block runs, no peer has a future
   603	BLE event pending to restart the cascade, and the connection eventually times out.
   604	
   605	**Why this matters beyond its severity:** `docs/W5_PERSISTENT_LINK_RESULTS_2026-07-29.md` describes W5 as
   606	"a reactive cascade with no timer, which is what lets it survive suspension." If the cascade actually
   607	depends on `asyncAfter` for its next step, that claim is weaker than written, and the 10h38m soak may
   608	have stayed alive because the phones kept getting woken rather than because the design is
   609	suspension-proof. Worth re-reading the soak evidence with this in mind before treating durability as
   610	proven.
   611	
   612	**Confidence:** LIKELY (Codex's own rating; mechanism traced, not executed on hardware).
   613	
   614	## Codex independent CONFIRMATIONS of Claude-panel findings
   615	- **C-W5-2** (restored peripheral loses both notify characteristics) — confirmed independently, same
   616	  file and lines, rated CERTAIN. Two models, separate scopes, same conclusion.
   617	- **H-W5-3** (no lease persistence; restoration mints fresh identity) — confirmed, with an added concrete
   618	  stale-generation sequence: A retains B's accepted `peerViewGen`; B relaunches from zero; if A's
   619	  candidate is still the minimum the encounter id does not change, so `rekey` is never called and A never
   620	  clears the remembered peer generation, leaving convergence stuck.
   621	- **Vacuous-test confirmation:** the tests named "restoration replay" (`W5OwnershipTests.swift:351`)
   622	  **reuse the same in-memory authority** and do not simulate process loss or serialization — they cannot
   623	  observe the defect they are named for.
   624	
   625	## M-W5-8 (from Codex) — unbounded `lastConnectAttempt` and `pendingControl`
   626	`lastConnectAttempt` gains an entry per encountered `CBPeripheral.identifier`, cleared only on beacon
   627	stop; `pendingControl` appends every refused notification with no cap, no coalescing, and no prune on
   628	unsubscribe. Long uptime, crowded venues and MAC churn retain entries indefinitely.
   629	
   630	## Codex "checked and found correct" (useful negative evidence)
   631	Queue confinement is coherent (both CB managers `queue: nil` → main; no W5 mutable field concurrently
   632	read/written); no synchronous delegate re-entry into the ownership machine; the CA6E decoder correctly
   633	rejects truncated headers, lying lengths, trailing bytes, oversized frames, over-cap/noncanonical
   634	contender sets and unknown types; no unchecked indexing or force-unwraps reachable from BLE input;
   635	peer-generation monotonicity, bijection, contender caps, canonical ordering and generation saturation are
   636	correctly implemented in the pure ownership layer.
   637	
   638	**Note:** this independently matches the Claude native reviewer's own "VERIFIED SOUND" list on threading
   639	and codec bounds. Two models agreeing on what is *correct* is worth as much here as agreement on defects.
22 matches in 1 files:

10:**Severity:** High (process / regression-coverage, not a runtime defect)
51:## C-DIAG-1 — Diagnostic W5 link layer + plaintext RSSI log ship in productio...
53:**Severity:** Critical (privacy: plaintext proximity records written by a rel...
93:**Severity:** High (false assurance)
122:**Severity:** High
148:**Severity:** CRITICAL — remotely exploitable by anyone on the internet, righ...
200:**Severity:** Critical (live today — the mitigating check is behind a flag th...
241:**Severity:** Critical (live, not gated by any rollout flag)
276:**Severity:** Critical (privacy)
308:**Severity:** Critical (compliance — withdrawal is not effective)
338:## 🔴 C-W5-1 — A committed encounter reached by `realId` bypasses the sticky-k...
340:**Severity:** Critical (reproduces the original #7 duplicate-keeper defect, n...
385:## 🔴 C-W5-2 — Peripheral restoration permanently nils the notify characterist...
387:**Severity:** Critical
412:## 🔴 C-W5-3 — A dial that connects but dies before HELLO_ACK leaks a `pending...
  +7 more in docs/.../2026-08-01-hardening/verified_findings_working.md

exec
/bin/bash -lc 'graphify query "How are INRANGE_W5_LINKS, INRANGE_DIAG, the persisted bb.w5links setting, W5LinkController creation, and recordRssi related in iOS release builds? Cite files and symbols."' in /home/hazypiff/in-range
 succeeded in 458ms:
Traversal: BFS depth=2 | Start: ['Files', 'iOS', '.buildSettings()', 'FlutterImplicitEngineBridge', 'Release/deployment notes', 'settings_screen.dart', 'w5LinksEnabled'] | 180 nodes found

NODE beacon_service.dart [src=lib/features/beacon/beacon_service.dart loc=None community=0]
NODE app_session.dart [src=lib/core/session/app_session.dart loc=None community=2]
NODE match_store.dart [src=lib/features/matches/match_store.dart loc=None community=1]
NODE venue_matcher.dart [src=lib/features/beacon/venue_matcher.dart loc=None community=40]
NODE auth_screen.dart [src=lib/features/auth/auth_screen.dart loc=None community=6]
NODE local_encounter_store.dart [src=lib/features/encounters/local_encounter_store.dart loc=None community=10]
NODE consent_screen.dart [src=lib/features/consent/consent_screen.dart loc=None community=51]
NODE swipe_feed.dart [src=lib/features/encounters/swipe_feed.dart loc=None community=212]
NODE locals_service.dart [src=lib/features/locals/locals_service.dart loc=None community=9]
NODE subtle_wake_service.dart [src=lib/features/beacon/subtle_wake_service.dart loc=None community=132]
NODE beacon_provider.dart [src=lib/features/beacon/beacon_provider.dart loc=None community=15]
NODE safety_store.dart [src=lib/core/privacy/safety_store.dart loc=None community=8]
NODE background_beacon_channel.dart [src=lib/features/beacon/background_beacon_channel.dart loc=None community=153]
NODE locals_screen.dart [src=lib/features/locals/locals_screen.dart loc=None community=21]
NODE package:flutter_riverpod/flutter_riverpod.dart [src=None loc=None community=214]
NODE main.dart [src=lib/main.dart loc=None community=148]
NODE messages_screen.dart [src=lib/features/chat/messages_screen.dart loc=None community=16]
NODE location_keepalive.dart [src=lib/features/beacon/location_keepalive.dart loc=None community=233]
NODE settings_screen.dart [src=lib/features/settings/settings_screen.dart loc=None community=214]
NODE profile_setup_screen.dart [src=lib/features/profile/profile_setup_screen.dart loc=None community=25]
NODE swipe_card.dart [src=lib/features/encounters/swipe_card.dart loc=None community=13]
NODE package:in_range/core/config/app_config.dart [src=None loc=None community=176]
NODE ephemeral_token_generator.dart [src=lib/features/beacon/ephemeral_token_generator.dart loc=None community=12]
NODE auth_service.dart [src=lib/shared/services/auth_service.dart loc=None community=76]
NODE chat_sync_service.dart [src=lib/shared/services/chat_sync_service.dart loc=None community=22]
NODE matchStoreProvider [src=lib/features/matches/match_store.dart loc=None community=236]
NODE home_shell.dart [src=lib/features/home/home_shell.dart loc=None community=197]
NODE venue_anchor_service.dart [src=lib/features/beacon/venue_anchor_service.dart loc=None community=171]
NODE package:flutter/material.dart [src=None loc=None community=214]
NODE consent_gate.dart [src=lib/features/consent/consent_gate.dart loc=None community=195]
NODE app_root.dart [src=lib/app_root.dart loc=None community=214]
NODE wifi_scanner.dart [src=lib/features/beacon/wifi_scanner.dart loc=None community=33]
NODE onboarding_flow.dart [src=lib/features/onboarding/onboarding_flow.dart loc=None community=168]
NODE beacon_screen.dart [src=lib/features/beacon/beacon_screen.dart loc=None community=106]
NODE push_service.dart [src=lib/core/notifications/push_service.dart loc=None community=29]
NODE profile_sync_service.dart [src=lib/shared/services/profile_sync_service.dart loc=None community=38]
NODE permission_service.dart [src=lib/core/permissions/permission_service.dart loc=None community=210]
NODE AdvertScanner [src=android/app/src/main/kotlin/io/inrange/app/AdvertScanner.kt loc=L71 community=47]
NODE backend_status.dart [src=lib/core/backend/backend_status.dart loc=None community=11]
NODE encounters_api.dart [src=lib/shared/services/encounters_api.dart loc=None community=24]
NODE safetyStoreProvider [src=lib/core/privacy/safety_store.dart loc=None community=236]
NODE apns_token_service.dart [src=lib/core/notifications/apns_token_service.dart loc=None community=240]
NODE lighthouse_beacon.dart [src=lib/features/beacon/lighthouse_beacon.dart loc=None community=44]
NODE encounters_screen.dart [src=lib/features/encounters/encounters_screen.dart loc=None community=227]
NODE consent_gate_test.dart [src=test/consent_gate_test.dart loc=None community=180]
NODE app_config.dart [src=lib/core/config/app_config.dart loc=None community=154]
NODE iOS Proximity Upgrade — Research and Agent Handoff [src=docs/IOS_PROXIMITY_RESEARCH_2026-07-24.md loc=L1 community=4]
NODE app_prefs.dart [src=lib/core/prefs/app_prefs.dart loc=None community=228]
NODE encounters_provider.dart [src=lib/features/encounters/encounters_provider.dart loc=None community=20]
NODE dart:io [src=None loc=None community=240]
NODE .attach() [src=ios/Runner/BackgroundBeacon.swift loc=L193 community=207]
NODE package:in_range/core/session/app_session.dart [src=None loc=None community=148]
NODE match_profile_screen.dart [src=lib/features/matches/match_profile_screen.dart loc=None community=214]
NODE In Range — Ultimate Audit, Remediation, and Verification Report [src=docs/ULTIMATE_AUDIT_REPORT_2026-07-12.md loc=L1 community=26]
NODE consent_service.dart [src=lib/shared/services/consent_service.dart loc=None community=176]
NODE package:flutter/services.dart [src=None loc=None community=115]
NODE package:in_range/features/encounters/local_encounter_store.dart [src=None loc=None community=148]
NODE localsControllerProvider [src=lib/features/locals/locals_service.dart loc=None community=236]
NODE sessionControllerProvider [src=lib/core/session/app_session.dart loc=None community=25]
NODE wifi_assist.dart [src=lib/features/beacon/wifi_assist.dart loc=None community=241]
NODE package:in_range/features/matches/match_store.dart [src=None loc=None community=214]
NODE localEncounterStoreProvider [src=lib/features/encounters/local_encounter_store.dart loc=None community=236]
NODE subtle_wake_test.dart [src=test/subtle_wake_test.dart loc=None community=115]
NODE supabase_client.dart [src=lib/core/network/supabase_client.dart loc=None community=256]
... (truncated — 116 more nodes cut by ~2000-token budget. Narrow with context_filter=['call'] or use get_node for a specific symbol)

exec
/bin/bash -lc "rtk git status --short --branch
rtk rg -n -C 4 'INRANGE_W5_LINKS|INRANGE_DIAG|bb\\.w5links|w5LinksEnabled|recordRssi|ensureManagers' ios/Runner ios/Runner.xcodeproj lib | head -n 260" in /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
 succeeded in 0ms:
## fix/w5-encounter-lease...origin/fix/w5-encounter-lease [behind 1]

lib/core/config/app_config.dart-34-        'INRANGE_SUBTLE_WAKE' =>
lib/core/config/app_config.dart-35-          const String.fromEnvironment('INRANGE_SUBTLE_WAKE'),
lib/core/config/app_config.dart-36-        'INRANGE_LOCATION_RESIDENCY' =>
lib/core/config/app_config.dart-37-          const String.fromEnvironment('INRANGE_LOCATION_RESIDENCY'),
lib/core/config/app_config.dart:38:        'INRANGE_W5_LINKS' =>
lib/core/config/app_config.dart:39:          const String.fromEnvironment('INRANGE_W5_LINKS'),
lib/core/config/app_config.dart-40-        'AUTH_REDIRECT_URL' =>
lib/core/config/app_config.dart-41-          const String.fromEnvironment('AUTH_REDIRECT_URL'),
lib/core/config/app_config.dart-42-        'GOOGLE_WEB_CLIENT_ID' =>
lib/core/config/app_config.dart-43-          const String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
lib/core/config/app_config.dart-63-  }
lib/core/config/app_config.dart-64-
lib/core/config/app_config.dart-65-  /// Test-only gate for W5 persistent GATT links (iOS). Default OFF — W5 is
lib/core/config/app_config.dart-66-  /// unproven through the awake gates, so it must never touch production
lib/core/config/app_config.dart:67:  /// behavior until it passes. Enable per build: --dart-define=INRANGE_W5_LINKS=true
lib/core/config/app_config.dart:68:  static bool get w5LinksEnabled =>
lib/core/config/app_config.dart:69:      _env('INRANGE_W5_LINKS').toLowerCase() == 'true';
lib/core/config/app_config.dart-70-
lib/core/config/app_config.dart-71-  static String get supabaseAnonKey {
lib/core/config/app_config.dart-72-    final k = _env('SUPABASE_PUBLISHABLE_KEY');
lib/core/config/app_config.dart-73-    if (k.isNotEmpty) return k;
ios/Runner.xcodeproj/project.pbxproj-512-					"@executable_path/Frameworks",
ios/Runner.xcodeproj/project.pbxproj-513-				);
ios/Runner.xcodeproj/project.pbxproj-514-				PRODUCT_BUNDLE_IDENTIFIER = io.inrange.inRange.diag;
ios/Runner.xcodeproj/project.pbxproj-515-				PRODUCT_NAME = "$(TARGET_NAME)";
ios/Runner.xcodeproj/project.pbxproj:516:				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "$(inherited) INRANGE_DIAG";
ios/Runner.xcodeproj/project.pbxproj-517-				SWIFT_OBJC_BRIDGING_HEADER = "Runner/Runner-Bridging-Header.h";
ios/Runner.xcodeproj/project.pbxproj-518-				SWIFT_VERSION = 5.0;
ios/Runner.xcodeproj/project.pbxproj-519-				VERSIONING_SYSTEM = "apple-generic";
ios/Runner.xcodeproj/project.pbxproj-520-			};
ios/Runner.xcodeproj/project.pbxproj-679-					"@executable_path/Frameworks",
ios/Runner.xcodeproj/project.pbxproj-680-				);
ios/Runner.xcodeproj/project.pbxproj-681-				PRODUCT_BUNDLE_IDENTIFIER = io.inrange.inRange.diag;
ios/Runner.xcodeproj/project.pbxproj-682-				PRODUCT_NAME = "$(TARGET_NAME)";
ios/Runner.xcodeproj/project.pbxproj:683:				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "$(inherited) INRANGE_DIAG";
ios/Runner.xcodeproj/project.pbxproj-684-				SWIFT_OBJC_BRIDGING_HEADER = "Runner/Runner-Bridging-Header.h";
ios/Runner.xcodeproj/project.pbxproj-685-				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
ios/Runner.xcodeproj/project.pbxproj-686-				SWIFT_VERSION = 5.0;
ios/Runner.xcodeproj/project.pbxproj-687-				VERSIONING_SYSTEM = "apple-generic";
ios/Runner.xcodeproj/project.pbxproj-1000-					"@executable_path/Frameworks",
ios/Runner.xcodeproj/project.pbxproj-1001-				);
ios/Runner.xcodeproj/project.pbxproj-1002-				PRODUCT_BUNDLE_IDENTIFIER = io.inrange.inRange.diag;
ios/Runner.xcodeproj/project.pbxproj-1003-				PRODUCT_NAME = "$(TARGET_NAME)";
ios/Runner.xcodeproj/project.pbxproj:1004:				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "$(inherited) INRANGE_DIAG";
ios/Runner.xcodeproj/project.pbxproj-1005-				SWIFT_OBJC_BRIDGING_HEADER = "Runner/Runner-Bridging-Header.h";
ios/Runner.xcodeproj/project.pbxproj-1006-				SWIFT_VERSION = 5.0;
ios/Runner.xcodeproj/project.pbxproj-1007-				VERSIONING_SYSTEM = "apple-generic";
ios/Runner.xcodeproj/project.pbxproj-1008-			};
lib/features/beacon/background_beacon_channel.dart-336-      debugPrint('BackgroundBeacon setWakePing failed: $e');
lib/features/beacon/background_beacon_channel.dart-337-    }
lib/features/beacon/background_beacon_channel.dart-338-  }
lib/features/beacon/background_beacon_channel.dart-339-
lib/features/beacon/background_beacon_channel.dart:340:  /// Test-only gate for W5 persistent links (INRANGE_W5_LINKS).
lib/features/beacon/background_beacon_channel.dart-341-  Future<void> setW5Links(bool enabled) async {
lib/features/beacon/background_beacon_channel.dart-342-    try {
lib/features/beacon/background_beacon_channel.dart-343-      await _channel.invokeMethod<void>('setW5Links', enabled);
lib/features/beacon/background_beacon_channel.dart-344-    } catch (e) {
ios/Runner/W5LinkController.swift-5-/// CA6E control-plane adapter (#7 / PR #9): translates CoreBluetooth callbacks
ios/Runner/W5LinkController.swift-6-/// into `W5Ownership` events and ownership effects back into GATT operations,
ios/Runner/W5LinkController.swift-7-/// using `W5Codec` for exact bytes. BackgroundBeacon owns exactly one
ios/Runner/W5LinkController.swift-8-/// instance; every entry point runs on the main queue (both CB managers are
ios/Runner/W5LinkController.swift:9:/// main-queue). Nothing here runs unless Dart set INRANGE_W5_LINKS.
ios/Runner/W5LinkController.swift-10-///
ios/Runner/W5LinkController.swift-11-/// Identity plumbing: all protocol ids (aliases, candidates, linkIds,
ios/Runner/W5LinkController.swift-12-/// encounterIds) cross this adapter as 16-byte lowercase-hex strings — the
ios/Runner/W5LinkController.swift-13-/// oracle's opaque-string ordering over hex equals byte ordering over the
ios/Runner/W5LinkController.swift-629-
ios/Runner/W5LinkController.swift-630-  /// Live push when Dart can hear it; file-append otherwise. The 500-entry
ios/Runner/W5LinkController.swift-631-  /// UserDefaults sighting buffer truncated the 07-29 soak to its last ~35
ios/Runner/W5LinkController.swift-632-  /// minutes — W5 samples get a real log with a real cap.
ios/Runner/W5LinkController.swift:633:  func recordRssi(tokenHex: String, rssi: Int) {
ios/Runner/W5LinkController.swift-634-    let ts = Int(Date().timeIntervalSince1970 * 1000)
ios/Runner/W5LinkController.swift-635-    if UIApplication.shared.applicationState == .active, let ch = bb.channel {
ios/Runner/W5LinkController.swift-636-      ch.invokeMethod("onSighting", arguments: ["token": tokenHex, "rssi": rssi, "ts": ts])
ios/Runner/W5LinkController.swift-637-      return
lib/features/beacon/beacon_service.dart-1016-        currentUntil: _currentToken!.expiresAt,
lib/features/beacon/beacon_service.dart-1017-      );
lib/features/beacon/beacon_service.dart-1018-      final ok = await _bgBeacon.start(payload);
lib/features/beacon/beacon_service.dart-1019-      // W5 test gate: only establish persistent links when the build opts in.
lib/features/beacon/beacon_service.dart:1020:      unawaited(_bgBeacon.setW5Links(AppConfig.w5LinksEnabled));
lib/features/beacon/beacon_service.dart-1021-      // Crack #1: refresh the native wake-ping endpoint + JWT on every
lib/features/beacon/beacon_service.dart-1022-      // (re)start — rotation re-enters here every ~15 min, keeping the
lib/features/beacon/beacon_service.dart-1023-      // stored token fresh. Endpoint is null until the server half (issue
lib/features/beacon/beacon_service.dart-1024-      // #4) ships, which keeps the native side silent.
ios/Runner/BackgroundBeacon.swift-40-  // ever suspends while the session lives.
ios/Runner/BackgroundBeacon.swift-41-  private static let keepaliveCharUUID = CBUUID(string: "CA5E")
ios/Runner/BackgroundBeacon.swift-42-  // W5 encounter-lease control plane (#7/PR #9): versioned bidirectional
ios/Runner/BackgroundBeacon.swift-43-  // exchange — central writes .withResponse, peripheral notifies. Wired by
ios/Runner/BackgroundBeacon.swift:44:  // W5LinkController; inert unless INRANGE_W5_LINKS.
ios/Runner/BackgroundBeacon.swift-45-  static let controlCharUUID = CBUUID(string: "CA6E")
ios/Runner/BackgroundBeacon.swift-46-
ios/Runner/BackgroundBeacon.swift-47-  // #8 release isolation: diagnostic builds live in their own persistence
ios/Runner/BackgroundBeacon.swift-48-  // universe — separate bundle id (build config), separate UserDefaults suite,
ios/Runner/BackgroundBeacon.swift-49-  // separate CoreBluetooth restoration identifiers — so nothing a diagnostic
ios/Runner/BackgroundBeacon.swift-50-  // build persists (token slots, flags, logs) can ever be restored by a
ios/Runner/BackgroundBeacon.swift:51:  // production build. INRANGE_DIAG is set ONLY by the diag build flavor.
ios/Runner/BackgroundBeacon.swift:52:  #if INRANGE_DIAG
ios/Runner/BackgroundBeacon.swift-53-    static let isDiagBuild = true
ios/Runner/BackgroundBeacon.swift-54-    static let restoreIDSuffix = ".diag"
ios/Runner/BackgroundBeacon.swift-55-  #else
ios/Runner/BackgroundBeacon.swift-56-    static let isDiagBuild = false
ios/Runner/BackgroundBeacon.swift-64-  /// The operational persistence domain. Diagnostic builds write to their own
ios/Runner/BackgroundBeacon.swift-65-  /// suite; production compiles to UserDefaults.standard with no code path
ios/Runner/BackgroundBeacon.swift-66-  /// that reads the diag suite.
ios/Runner/BackgroundBeacon.swift-67-  static func operationalDefaults() -> UserDefaults {
ios/Runner/BackgroundBeacon.swift:68:    #if INRANGE_DIAG
ios/Runner/BackgroundBeacon.swift-69-      return UserDefaults(suiteName: diagSuiteName) ?? .standard
ios/Runner/BackgroundBeacon.swift-70-    #else
ios/Runner/BackgroundBeacon.swift-71-      return UserDefaults.standard
ios/Runner/BackgroundBeacon.swift-72-    #endif
ios/Runner/BackgroundBeacon.swift-114-  /// Peripheral-side: a notify that updateValue refused (queue full) — retried
ios/Runner/BackgroundBeacon.swift-115-  /// only from peripheralManagerIsReady(toUpdateSubscribers:).
ios/Runner/BackgroundBeacon.swift-116-  private var pendingNotify = false
ios/Runner/BackgroundBeacon.swift-117-  /// W5 is a TEST-ONLY link layer until proven through the awake gates; gated
ios/Runner/BackgroundBeacon.swift:118:  /// by the INRANGE_W5_LINKS dart-define (persisted here by Dart). Off = pure
ios/Runner/BackgroundBeacon.swift-119-  /// token-read behavior, no persistent connections.
ios/Runner/BackgroundBeacon.swift:120:  var w5LinksEnabled: Bool { defaults.bool(forKey: Self.keyW5Links) }
ios/Runner/BackgroundBeacon.swift-121-  // Callback-primed cadence: after a write CONFIRMS (didWriteValueFor), the
ios/Runner/BackgroundBeacon.swift-122-  // next beat is scheduled ~4 s out. Herald-shaped — not an instant loop.
ios/Runner/BackgroundBeacon.swift-123-  private static let w5Cadence: TimeInterval = 4
ios/Runner/BackgroundBeacon.swift:124:  private static let keyW5Links = "bb.w5links"
ios/Runner/BackgroundBeacon.swift-125-
ios/Runner/BackgroundBeacon.swift-126-  // peripheral.identifier → (tokenHex, cachedAt)
ios/Runner/BackgroundBeacon.swift-127-  private var tokenCache: [UUID: (hex: String, at: Date)] = [:]
ios/Runner/BackgroundBeacon.swift-128-  // peripherals we're currently connected/connecting to, kept strongly.
ios/Runner/BackgroundBeacon.swift-181-    ) { [weak self] _ in
ios/Runner/BackgroundBeacon.swift-182-      self?.scheduleWake()
ios/Runner/BackgroundBeacon.swift-183-    }
ios/Runner/BackgroundBeacon.swift-184-    if defaults.bool(forKey: Self.keyEnabled) {
ios/Runner/BackgroundBeacon.swift:185:      ensureManagers()
ios/Runner/BackgroundBeacon.swift-186-      scheduleWake()
ios/Runner/BackgroundBeacon.swift-187-    }
ios/Runner/BackgroundBeacon.swift-188-  }
ios/Runner/BackgroundBeacon.swift-189-
ios/Runner/BackgroundBeacon.swift-234-      switch call.method {
ios/Runner/BackgroundBeacon.swift-235-      case "start":
ios/Runner/BackgroundBeacon.swift-236-        self.storeSlots(call.arguments)
ios/Runner/BackgroundBeacon.swift-237-        self.defaults.set(true, forKey: Self.keyEnabled)
ios/Runner/BackgroundBeacon.swift:238:        self.ensureManagers()
ios/Runner/BackgroundBeacon.swift-239-        self.reconfigureAdvertising()
ios/Runner/BackgroundBeacon.swift-240-        self.ensureScanning()
ios/Runner/BackgroundBeacon.swift-241-        self.notifyBufferReady()
ios/Runner/BackgroundBeacon.swift-242-        // Hand Dart a full snapshot immediately — the bool below only says
ios/Runner/BackgroundBeacon.swift-289-          self.defaults.set(args["auth"] as? String, forKey: Self.keyPingAuth)
ios/Runner/BackgroundBeacon.swift-290-        }
ios/Runner/BackgroundBeacon.swift-291-        result(nil)
ios/Runner/BackgroundBeacon.swift-292-      case "setW5Links":
ios/Runner/BackgroundBeacon.swift:293:        // Test-only gate for W5 persistent links (INRANGE_W5_LINKS).
ios/Runner/BackgroundBeacon.swift-294-        self.defaults.set((call.arguments as? Bool) ?? false, forKey: Self.keyW5Links)
ios/Runner/BackgroundBeacon.swift-295-        result(nil)
ios/Runner/BackgroundBeacon.swift-296-      default:
ios/Runner/BackgroundBeacon.swift-297-        result(FlutterMethodNotImplemented)
ios/Runner/BackgroundBeacon.swift-300-  }
ios/Runner/BackgroundBeacon.swift-301-
ios/Runner/BackgroundBeacon.swift-302-  private var enabled: Bool { defaults.bool(forKey: Self.keyEnabled) }
ios/Runner/BackgroundBeacon.swift-303-
ios/Runner/BackgroundBeacon.swift:304:  private func ensureManagers() {
ios/Runner/BackgroundBeacon.swift-305-    if peripheralMgr == nil {
ios/Runner/BackgroundBeacon.swift-306-      peripheralMgr = CBPeripheralManager(
ios/Runner/BackgroundBeacon.swift-307-        delegate: self, queue: nil,
ios/Runner/BackgroundBeacon.swift-308-        options: [CBPeripheralManagerOptionRestoreIdentifierKey: Self.peripheralRestoreID])
ios/Runner/BackgroundBeacon.swift-426-    var uuids: [CBUUID] = [Self.serviceUUID]
ios/Runner/BackgroundBeacon.swift-427-    if let hex = currentTokenHex(), let data = Self.hexToData(hex) {
ios/Runner/BackgroundBeacon.swift-428-      uuids.append(CBUUID(data: data))
ios/Runner/BackgroundBeacon.swift-429-      // Rotation: tell every established W5 link in-band (ALIAS_ROLL).
ios/Runner/BackgroundBeacon.swift:430:      if w5LinksEnabled { w5Link.advertisedTokenChanged(hex) }
ios/Runner/BackgroundBeacon.swift-431-    }
ios/Runner/BackgroundBeacon.swift-432-    pm.startAdvertising([CBAdvertisementDataServiceUUIDsKey: uuids])
ios/Runner/BackgroundBeacon.swift-433-  }
ios/Runner/BackgroundBeacon.swift-434-
ios/Runner/BackgroundBeacon.swift-690-  /// in Documents so a USB pull can show whether iOS granted windows at
ios/Runner/BackgroundBeacon.swift-691-  /// all, separately from whether scans saw anything during them.
ios/Runner/BackgroundBeacon.swift-692-  /// #8: diagnostic-only — compiled out of production entirely.
ios/Runner/BackgroundBeacon.swift-693-  func logWake(_ kind: String) {
ios/Runner/BackgroundBeacon.swift:694:    #if INRANGE_DIAG
ios/Runner/BackgroundBeacon.swift-695-      let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
ios/Runner/BackgroundBeacon.swift-696-      let url = docs.appendingPathComponent("bb_wake_log.txt")
ios/Runner/BackgroundBeacon.swift-697-      let line = "\(Int(Date().timeIntervalSince1970 * 1000)) \(kind)\n"
ios/Runner/BackgroundBeacon.swift-698-      if let data = line.data(using: .utf8) {
ios/Runner/BackgroundBeacon.swift-779-    guard ok else { return }
ios/Runner/BackgroundBeacon.swift-780-    // CA6E control writes → the ownership adapter; CA5E falls through to the
ios/Runner/BackgroundBeacon.swift-781-    // keepalive notify below (unchanged, the proven heartbeat).
ios/Runner/BackgroundBeacon.swift-782-    for request in requests where request.characteristic.uuid == Self.controlCharUUID {
ios/Runner/BackgroundBeacon.swift:783:      if w5LinksEnabled, let value = request.value {
ios/Runner/BackgroundBeacon.swift-784-        w5Link.controlWrite(request.central, value)
ios/Runner/BackgroundBeacon.swift-785-      }
ios/Runner/BackgroundBeacon.swift-786-    }
ios/Runner/BackgroundBeacon.swift-787-    guard requests.contains(where: { $0.characteristic.uuid == Self.keepaliveCharUUID })
ios/Runner/BackgroundBeacon.swift-807-    _ peripheral: CBPeripheralManager, central: CBCentral,
ios/Runner/BackgroundBeacon.swift-808-    didSubscribeTo characteristic: CBCharacteristic
ios/Runner/BackgroundBeacon.swift-809-  ) {
ios/Runner/BackgroundBeacon.swift-810-    if characteristic.uuid == Self.controlCharUUID {
ios/Runner/BackgroundBeacon.swift:811:      if w5LinksEnabled { w5Link.controlSubscribed(central) }
ios/Runner/BackgroundBeacon.swift-812-      return
ios/Runner/BackgroundBeacon.swift-813-    }
ios/Runner/BackgroundBeacon.swift-814-    guard characteristic.uuid == Self.keepaliveCharUUID,
ios/Runner/BackgroundBeacon.swift-815-          let ch = keepaliveNotifyChar else { return }
ios/Runner/BackgroundBeacon.swift-822-    _ peripheral: CBPeripheralManager, central: CBCentral,
ios/Runner/BackgroundBeacon.swift-823-    didUnsubscribeFrom characteristic: CBCharacteristic
ios/Runner/BackgroundBeacon.swift-824-  ) {
ios/Runner/BackgroundBeacon.swift-825-    // The inbound physical link is gone (peer central left / powered off).
ios/Runner/BackgroundBeacon.swift:826:    if characteristic.uuid == Self.controlCharUUID, w5LinksEnabled {
ios/Runner/BackgroundBeacon.swift-827-      w5Link.inboundGone(central)
ios/Runner/BackgroundBeacon.swift-828-    }
ios/Runner/BackgroundBeacon.swift-829-  }
ios/Runner/BackgroundBeacon.swift-830-
ios/Runner/BackgroundBeacon.swift-952-      // lock). Single-initiator tiebreak: the side whose current advertised
ios/Runner/BackgroundBeacon.swift-953-      // token sorts lower dials; the peer computes the mirror and stands
ios/Runner/BackgroundBeacon.swift-954-      // down — no double connect. Skip if a session/attempt already exists.
ios/Runner/BackgroundBeacon.swift-955-      let id = peripheral.identifier
ios/Runner/BackgroundBeacon.swift:956:      if w5LinksEnabled, w5[id] == nil, inflight[id] == nil,
ios/Runner/BackgroundBeacon.swift-957-         let myToken = currentTokenHex(), myToken < peerToken {
ios/Runner/BackgroundBeacon.swift-958-        let recent = lastConnectAttempt[id].map {
ios/Runner/BackgroundBeacon.swift-959-          Date().timeIntervalSince($0) < Self.connectRetryFloor } ?? false
ios/Runner/BackgroundBeacon.swift-960-        if !recent, w5Link.willDial(peerTokenHex: peerToken, peripheralID: id) {
ios/Runner/BackgroundBeacon.swift-1032-    _ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?
ios/Runner/BackgroundBeacon.swift-1033-  ) {
ios/Runner/BackgroundBeacon.swift-1034-    inflight.removeValue(forKey: peripheral.identifier)
ios/Runner/BackgroundBeacon.swift-1035-    inflightRSSI.removeValue(forKey: peripheral.identifier)
ios/Runner/BackgroundBeacon.swift:1036:    if w5LinksEnabled { w5Link.dialFailed(peripheral.identifier) }
ios/Runner/BackgroundBeacon.swift-1037-    scheduleScanRestart()
ios/Runner/BackgroundBeacon.swift-1038-  }
ios/Runner/BackgroundBeacon.swift-1039-
ios/Runner/BackgroundBeacon.swift-1040-  func centralManager(
ios/Runner/BackgroundBeacon.swift-1050-      let e = error as NSError?
ios/Runner/BackgroundBeacon.swift-1051-      let reason = e.map { "\($0.domain):\($0.code)" } ?? "clean"
ios/Runner/BackgroundBeacon.swift-1052-      logWake("w5-parted-\(reason)-seq\(s.seq)-op:\(s.lastGattOp)")
ios/Runner/BackgroundBeacon.swift-1053-    }
ios/Runner/BackgroundBeacon.swift:1054:    if w5LinksEnabled { w5Link.linkDown(peripheral.identifier) }
ios/Runner/BackgroundBeacon.swift-1055-    scheduleScanRestart()
ios/Runner/BackgroundBeacon.swift-1056-  }
ios/Runner/BackgroundBeacon.swift-1057-
ios/Runner/BackgroundBeacon.swift-1058-  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
ios/Runner/BackgroundBeacon.swift-1094-      w5MaybeBeat(id)
ios/Runner/BackgroundBeacon.swift-1095-      return
ios/Runner/BackgroundBeacon.swift-1096-    }
ios/Runner/BackgroundBeacon.swift-1097-    if characteristic.uuid == Self.controlCharUUID {
ios/Runner/BackgroundBeacon.swift:1098:      guard w5LinksEnabled, let data = characteristic.value else { return }
ios/Runner/BackgroundBeacon.swift-1099-      w5Link.controlNotify(peripheral, data)
ios/Runner/BackgroundBeacon.swift-1100-      return
ios/Runner/BackgroundBeacon.swift-1101-    }
ios/Runner/BackgroundBeacon.swift-1102-    guard characteristic.uuid == Self.tokenCharUUID,
ios/Runner/BackgroundBeacon.swift-1110-      let cutoff = Date().addingTimeInterval(-Self.tokenCacheTTL)
ios/Runner/BackgroundBeacon.swift-1111-      tokenCache = tokenCache.filter { $0.value.at > cutoff }
ios/Runner/BackgroundBeacon.swift-1112-    }
ios/Runner/BackgroundBeacon.swift-1113-    emitSighting(tokenHex: hex, rssi: inflightRSSI[id] ?? -85)
ios/Runner/BackgroundBeacon.swift:1114:    // W5 (test-only, INRANGE_W5_LINKS): token read = session start. Subscribe
ios/Runner/BackgroundBeacon.swift-1115-    // to the peer's keepalive; the first beat waits for
ios/Runner/BackgroundBeacon.swift-1116-    // didUpdateNotificationStateFor. If W5 is gated off, disconnect after the
ios/Runner/BackgroundBeacon.swift-1117-    // read (pure token-read behavior).
ios/Runner/BackgroundBeacon.swift:1118:    guard w5LinksEnabled else {
ios/Runner/BackgroundBeacon.swift-1119-      centralMgr?.cancelPeripheralConnection(peripheral)
ios/Runner/BackgroundBeacon.swift-1120-      return
ios/Runner/BackgroundBeacon.swift-1121-    }
ios/Runner/BackgroundBeacon.swift-1122-    if w5[id] == nil {
ios/Runner/BackgroundBeacon.swift-1153-    let id = peripheral.identifier
ios/Runner/BackgroundBeacon.swift-1154-    if characteristic.uuid == Self.controlCharUUID {
ios/Runner/BackgroundBeacon.swift-1155-      // CA6E subscription confirmed → the HELLO can go out (its HELLO_ACK
ios/Runner/BackgroundBeacon.swift-1156-      // rides this notify channel).
ios/Runner/BackgroundBeacon.swift:1157:      if w5LinksEnabled, error == nil, characteristic.isNotifying {

exec
/bin/bash -lc "rtk rg -n -C 2 'W5LinkController\\.swift|W5Ownership\\.swift|W5Codec\\.swift' ios/Runner.xcodeproj/project.pbxproj
sed -n '628,656p' ios/Runner/W5LinkController.swift
sed -n '104,132p' ios/Runner/BackgroundBeacon.swift
sed -n '176,190p' ios/Runner/BackgroundBeacon.swift
sed -n '286,298p' ios/Runner/BackgroundBeacon.swift" in /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
 succeeded in 0ms:
9-/* Begin PBXBuildFile section */
10-		1498D2341E8E89220040F4C2 /* GeneratedPluginRegistrant.m in Sources */ = {isa = PBXBuildFile; fileRef = 1498D2331E8E89220040F4C2 /* GeneratedPluginRegistrant.m */; };
11:		1D5D796CDE5E573CF93AD5AD /* W5Ownership.swift in Sources */ = {isa = PBXBuildFile; fileRef = C536136C02CC816DE0F902C8 /* W5Ownership.swift */; };
12-		20D1FDA977A94261F5BBD45D /* ReleaseIsolationTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = A2F1AE50F9AED8ED2D1B72F8 /* ReleaseIsolationTests.swift */; };
13-		210BCA184DC4B36765A5EBBD /* W5OwnershipTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = A0DDD56893B45D823A63196F /* W5OwnershipTests.swift */; };
15-		331C808B294A63AB00263BE5 /* RunnerTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = 331C807B294A618700263BE5 /* RunnerTests.swift */; };
16-		3B3967161E833CAA004F5970 /* AppFrameworkInfo.plist in Resources */ = {isa = PBXBuildFile; fileRef = 3B3967151E833CAA004F5970 /* AppFrameworkInfo.plist */; };
17:		45EB553EEE99C8F286FD526F /* W5LinkController.swift in Sources */ = {isa = PBXBuildFile; fileRef = 598A86B3693CF1494482B6E4 /* W5LinkController.swift */; };
18-		6771B1168BA4E96FC1431CD3 /* w5_ownership_vectors.json in Resources */ = {isa = PBXBuildFile; fileRef = 6050FFDD9F31701406C99703 /* w5_ownership_vectors.json */; };
19:		69430F77CCFD8B350655823E /* W5Codec.swift in Sources */ = {isa = PBXBuildFile; fileRef = AE99188F4754602D6DC1B25D /* W5Codec.swift */; };
20-		74858FAF1ED2DC5600515810 /* AppDelegate.swift in Sources */ = {isa = PBXBuildFile; fileRef = 74858FAE1ED2DC5600515810 /* AppDelegate.swift */; };
21-		78A318202AECB46A00862997 /* FlutterGeneratedPluginSwiftPackage in Frameworks */ = {isa = PBXBuildFile; productRef = 78A3181F2AECB46A00862997 /* FlutterGeneratedPluginSwiftPackage */; };
65-		3B3967151E833CAA004F5970 /* AppFrameworkInfo.plist */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = text.plist.xml; name = AppFrameworkInfo.plist; path = Flutter/AppFrameworkInfo.plist; sourceTree = "<group>"; };
66-		4CC0FC048A3AEF352FAE375F /* Pods-RunnerTests.release.xcconfig */ = {isa = PBXFileReference; includeInIndex = 1; lastKnownFileType = text.xcconfig; name = "Pods-RunnerTests.release.xcconfig"; path = "Target Support Files/Pods-RunnerTests/Pods-RunnerTests.release.xcconfig"; sourceTree = "<group>"; };
67:		598A86B3693CF1494482B6E4 /* W5LinkController.swift */ = {isa = PBXFileReference; includeInIndex = 1; lastKnownFileType = sourcecode.swift; path = W5LinkController.swift; sourceTree = "<group>"; };
68-		6050FFDD9F31701406C99703 /* w5_ownership_vectors.json */ = {isa = PBXFileReference; includeInIndex = 1; name = w5_ownership_vectors.json; path = ../../test/features/beacon/w5_ownership_vectors.json; sourceTree = "<group>"; };
69-		6C04DCDA59CA6A672B49510C /* Pods_Runner.framework */ = {isa = PBXFileReference; explicitFileType = wrapper.framework; includeInIndex = 0; path = Pods_Runner.framework; sourceTree = BUILT_PRODUCTS_DIR; };
88-		A2F1AE50F9AED8ED2D1B72F8 /* ReleaseIsolationTests.swift */ = {isa = PBXFileReference; includeInIndex = 1; lastKnownFileType = sourcecode.swift; path = ReleaseIsolationTests.swift; sourceTree = "<group>"; };
89-		ABB44680B2813D8A36D331B1 /* Pods-RunnerTests.debug.xcconfig */ = {isa = PBXFileReference; includeInIndex = 1; lastKnownFileType = text.xcconfig; name = "Pods-RunnerTests.debug.xcconfig"; path = "Target Support Files/Pods-RunnerTests/Pods-RunnerTests.debug.xcconfig"; sourceTree = "<group>"; };
90:		AE99188F4754602D6DC1B25D /* W5Codec.swift */ = {isa = PBXFileReference; includeInIndex = 1; lastKnownFileType = sourcecode.swift; path = W5Codec.swift; sourceTree = "<group>"; };
91-		B2A113871E58F216DB1B806B /* Pods-Runner.release.xcconfig */ = {isa = PBXFileReference; includeInIndex = 1; lastKnownFileType = text.xcconfig; name = "Pods-Runner.release.xcconfig"; path = "Target Support Files/Pods-Runner/Pods-Runner.release.xcconfig"; sourceTree = "<group>"; };
92-		B6A71666D91D92A314920F59 /* w5_codec_vectors.json */ = {isa = PBXFileReference; includeInIndex = 1; name = w5_codec_vectors.json; path = ../../test/features/beacon/w5_codec_vectors.json; sourceTree = "<group>"; };
97-		BDB930659C362D8AC393BE46 /* Profile-diag.xcconfig */ = {isa = PBXFileReference; includeInIndex = 1; lastKnownFileType = text.xcconfig; name = "Profile-diag.xcconfig"; path = "Flutter/Profile-diag.xcconfig"; sourceTree = "<group>"; };
98-		C0FFEE01000000000000001A /* PrivacyInfo.xcprivacy */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = PrivacyInfo.xcprivacy; sourceTree = "<group>"; };
99:		C536136C02CC816DE0F902C8 /* W5Ownership.swift */ = {isa = PBXFileReference; includeInIndex = 1; lastKnownFileType = sourcecode.swift; path = W5Ownership.swift; sourceTree = "<group>"; };
100-		C87AECABD1768B2DECA0125C /* Pods-Runner.profile.xcconfig */ = {isa = PBXFileReference; includeInIndex = 1; lastKnownFileType = text.xcconfig; name = "Pods-Runner.profile.xcconfig"; path = "Target Support Files/Pods-Runner/Pods-Runner.profile.xcconfig"; sourceTree = "<group>"; };
101-		D3C839FC6DC9F3FE47DEE62C /* Pods-Runner.debug.xcconfig */ = {isa = PBXFileReference; includeInIndex = 1; lastKnownFileType = text.xcconfig; name = "Pods-Runner.debug.xcconfig"; path = "Target Support Files/Pods-Runner/Pods-Runner.debug.xcconfig"; sourceTree = "<group>"; };
223-				BB07BEAC24C0FFEE00000007 /* SubtleWakeCoordinator.swift */,
224-				74858FAD1ED2DC5600515810 /* Runner-Bridging-Header.h */,
225:				C536136C02CC816DE0F902C8 /* W5Ownership.swift */,
226:				AE99188F4754602D6DC1B25D /* W5Codec.swift */,
227:				598A86B3693CF1494482B6E4 /* W5LinkController.swift */,
228-			);
229-			path = Runner;
461-				BB07BEAC24C0FFEE00000008 /* SubtleWakeCoordinator.swift in Sources */,
462-				1498D2341E8E89220040F4C2 /* GeneratedPluginRegistrant.m in Sources */,
463:				1D5D796CDE5E573CF93AD5AD /* W5Ownership.swift in Sources */,
464:				69430F77CCFD8B350655823E /* W5Codec.swift in Sources */,
465:				45EB553EEE99C8F286FD526F /* W5LinkController.swift in Sources */,
466-			);
467-			runOnlyForDeploymentPostprocessing = 0;
  private var lastDrainLineEnds: [UInt64] = []

  /// Live push when Dart can hear it; file-append otherwise. The 500-entry
  /// UserDefaults sighting buffer truncated the 07-29 soak to its last ~35
  /// minutes — W5 samples get a real log with a real cap.
  func recordRssi(tokenHex: String, rssi: Int) {
    let ts = Int(Date().timeIntervalSince1970 * 1000)
    if UIApplication.shared.applicationState == .active, let ch = bb.channel {
      ch.invokeMethod("onSighting", arguments: ["token": tokenHex, "rssi": rssi, "ts": ts])
      return
    }
    let line = "{\"token\":\"\(tokenHex)\",\"rssi\":\(rssi),\"ts\":\(ts)}\n"
    guard let data = line.data(using: .utf8) else { return }
    let url = rssiFileURL
    if let h = try? FileHandle(forWritingTo: url) {
      h.seekToEndOfFile()
      h.write(data)
      try? h.close()
    } else {
      try? data.write(to: url)
    }
    trimRssiFileIfNeeded()
  }

  private func trimRssiFileIfNeeded() {
    let url = rssiFileURL
    guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size])
        as? Int, size > Self.rssiFileCap,
      let all = try? Data(contentsOf: url)
    var lastBeatAt: Date
    var writeInFlight: Bool  // exactly one .withResponse write outstanding
    var notifyReady: Bool    // didUpdateNotificationStateFor confirmed
    var seq: Int             // beat sequence number (logging)
    var lastGattOp: String   // last GATT op attempted (logging)
  }
  private var w5: [UUID: W5Session] = [:]
  private var keepaliveNotifyChar: CBMutableCharacteristic?
  var controlNotifyChar: CBMutableCharacteristic?
  lazy var w5Link = W5LinkController(bb: self)
  /// Peripheral-side: a notify that updateValue refused (queue full) — retried
  /// only from peripheralManagerIsReady(toUpdateSubscribers:).
  private var pendingNotify = false
  /// W5 is a TEST-ONLY link layer until proven through the awake gates; gated
  /// by the INRANGE_W5_LINKS dart-define (persisted here by Dart). Off = pure
  /// token-read behavior, no persistent connections.
  var w5LinksEnabled: Bool { defaults.bool(forKey: Self.keyW5Links) }
  // Callback-primed cadence: after a write CONFIRMS (didWriteValueFor), the
  // next beat is scheduled ~4 s out. Herald-shaped — not an instant loop.
  private static let w5Cadence: TimeInterval = 4
  private static let keyW5Links = "bb.w5links"

  // peripheral.identifier → (tokenHex, cachedAt)
  private var tokenCache: [UUID: (hex: String, at: Date)] = [:]
  // peripherals we're currently connected/connecting to, kept strongly.
  private var inflight: [UUID: CBPeripheral] = [:]
  private var inflightRSSI: [UUID: Int] = [:]
  private var lastConnectAttempt: [UUID: Date] = [:]
  private var lastScanRestart = Date.distantPast
      self?.handleWake(task: task)
    }
    NotificationCenter.default.addObserver(
      forName: UIApplication.didEnterBackgroundNotification, object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.scheduleWake()
    }
    if defaults.bool(forKey: Self.keyEnabled) {
      ensureManagers()
      scheduleWake()
    }
  }

  private static let wakeTaskID = "io.inrange.beacon.wake"
        // no url stored → no pings. Server half is hazypiff's.
        if let args = call.arguments as? [String: Any] {
          self.defaults.set(args["url"] as? String, forKey: Self.keyPingURL)
          self.defaults.set(args["auth"] as? String, forKey: Self.keyPingAuth)
        }
        result(nil)
      case "setW5Links":
        // Test-only gate for W5 persistent links (INRANGE_W5_LINKS).
        self.defaults.set((call.arguments as? Bool) ?? false, forKey: Self.keyW5Links)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }

exec
/bin/bash -lc "rtk rg -n -C 4 'CREATE OR REPLACE FUNCTION public\\.cleanup_ephemeral_data|beacon_token_batch|CREATE OR REPLACE FUNCTION public\\.claim_token\\(|ON CONFLICT \\(token\\)|CREATE OR REPLACE FUNCTION public\\.claim_token_batch|approx_lat IS NOT NULL|enforce_batch_tokens' supabase/migrations | tail -n 320" in /home/hazypiff/in-range
 succeeded in 0ms:
76 matches in 29 files:

supabase/migrations/0001_init.sql-235-
supabase/migrations/0001_init.sql-236--- -----------------------------------------------------------------------------
supabase/migrations/0001_init.sql-237--- claim_token: Client calls this periodically while Beacon is ON
supabase/migrations/0001_init.sql-238--- -----------------------------------------------------------------------------
supabase/migrations/0001_init.sql:239:CREATE OR REPLACE FUNCTION public.claim_token(
supabase/migrations/0001_init.sql-240-p_token TEXT,
supabase/migrations/0001_init.sql-241-p_valid_until TIMESTAMPTZ,
supabase/migrations/0001_init.sql-242-p_lat DOUBLE PRECISION DEFAULT NULL,
supabase/migrations/0001_init.sql-243-p_lon DOUBLE PRECISION DEFAULT NULL,
supabase/migrations/0001_init.sql-378-ORDER BY tc.valid_from DESC
supabase/migrations/0001_init.sql-379-LIMIT 5
supabase/migrations/0001_init.sql-380-LOOP
supabase/migrations/0001_init.sql-381--- Compute distance using PostGIS
supabase/migrations/0001_init.sql:382:IF v_claim.approx_lat IS NOT NULL AND v_claim.approx_lon IS NOT NULL THEN
supabase/migrations/0001_init.sql-383-v_distance := ST_Distance(
  +3 more in supabase/migrations/0001_init.sql
supabase/migrations/0002_location_pings_realtime_storage.sql-181--- ----------------------------------------------------------------------------
supabase/migrations/0002_location_pings_realtime_storage.sql-182--- Safe to run from a Supabase scheduled function (pg_cron) or a backend job.
supabase/migrations/0002_location_pings_realtime_storage.sql-183--- Recommended schedule: every 15 minutes.
supabase/migrations/0002_location_pings_realtime_storage.sql-184-
supabase/migrations/0002_location_pings_realtime_storage.sql:185:CREATE OR REPLACE FUNCTION public.cleanup_ephemeral_data()
supabase/migrations/0002_location_pings_realtime_storage.sql-186-RETURNS VOID
supabase/migrations/0002_location_pings_realtime_storage.sql-187-LANGUAGE sql
supabase/migrations/0002_location_pings_realtime_storage.sql-188-SECURITY DEFINER
supabase/migrations/0002_location_pings_realtime_storage.sql-189-SET search_path = public
supabase/migrations/0003_correlation_fixes.sql-61-ORDER BY tc.valid_from DESC
supabase/migrations/0003_correlation_fixes.sql-62-LIMIT 5
supabase/migrations/0003_correlation_fixes.sql-63-LOOP
supabase/migrations/0003_correlation_fixes.sql-64--- Compute distance using PostGIS (longitude first in ST_MakePoint)
supabase/migrations/0003_correlation_fixes.sql:65:IF v_claim.approx_lat IS NOT NULL AND v_claim.approx_lon IS NOT NULL THEN
supabase/migrations/0003_correlation_fixes.sql-66-v_distance := ST_Distance(
supabase/migrations/0003_correlation_fixes.sql-67-ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography,
supabase/migrations/0003_correlation_fixes.sql-68-ST_SetSRID(ST_MakePoint(v_claim.approx_lon, v_claim.approx_lat), 4326)::geogr...
supabase/migrations/0003_correlation_fixes.sql-69-);
supabase/migrations/0012_correlate_grace_dedupe.sql-42-AND tc.valid_until > NOW() - interval '5 minutes'
supabase/migrations/0012_correlate_grace_dedupe.sql-43-ORDER BY tc.valid_from DESC
supabase/migrations/0012_correlate_grace_dedupe.sql-44-LIMIT 5
supabase/migrations/0012_correlate_grace_dedupe.sql-45-LOOP
supabase/migrations/0012_correlate_grace_dedupe.sql:46:IF v_claim.approx_lat IS NOT NULL AND v_claim.approx_lon IS NOT NULL THEN
supabase/migrations/0012_correlate_grace_dedupe.sql-47-v_distance := ST_Distance(
supabase/migrations/0012_correlate_grace_dedupe.sql-48-ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography,
supabase/migrations/0012_correlate_grace_dedupe.sql-49-ST_SetSRID(ST_MakePoint(v_claim.approx_lon, v_claim.approx_lat), 4326)::geogr...
supabase/migrations/0012_correlate_grace_dedupe.sql-50-);
supabase/migrations/0018_security_correlate_photos.sql-154-AND NOT public.is_blocked_pair(v_observer_id, tc.user_id)
supabase/migrations/0018_security_correlate_photos.sql-155-ORDER BY tc.valid_from DESC
supabase/migrations/0018_security_correlate_photos.sql-156-LIMIT 5
supabase/migrations/0018_security_correlate_photos.sql-157-LOOP
supabase/migrations/0018_security_correlate_photos.sql:158:IF v_claim.approx_lat IS NOT NULL AND v_claim.approx_lon IS NOT NULL THEN
supabase/migrations/0018_security_correlate_photos.sql-159-v_distance := ST_Distance(
supabase/migrations/0018_security_correlate_photos.sql-160-ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography,
supabase/migrations/0018_security_correlate_photos.sql-161-ST_SetSRID(ST_MakePoint(v_claim.approx_lon, v_claim.approx_lat), 4326)::geogr...
supabase/migrations/0018_security_correlate_photos.sql-162-);
supabase/migrations/0019_beta_security_hardening.sql-807--- -----------------------------------------------------------------------------
supabase/migrations/0019_beta_security_hardening.sql-808--- 4. Ephemeral claims and BLE sightings
supabase/migrations/0019_beta_security_hardening.sql-809--- -----------------------------------------------------------------------------
supabase/migrations/0019_beta_security_hardening.sql-810-
supabase/migrations/0019_beta_security_hardening.sql:811:CREATE OR REPLACE FUNCTION public.claim_token(
supabase/migrations/0019_beta_security_hardening.sql-812-p_token TEXT,
supabase/migrations/0019_beta_security_hardening.sql-813-p_valid_until TIMESTAMPTZ,
supabase/migrations/0019_beta_security_hardening.sql-814-p_lat DOUBLE PRECISION DEFAULT NULL,
supabase/migrations/0019_beta_security_hardening.sql-815-p_lon DOUBLE PRECISION DEFAULT NULL,
supabase/migrations/0019_beta_security_hardening.sql-1045-RETURN;
supabase/migrations/0019_beta_security_hardening.sql-1046-END IF;
supabase/migrations/0019_beta_security_hardening.sql-1047-
supabase/migrations/0019_beta_security_hardening.sql-1048-IF p_lat IS NOT NULL AND p_lon IS NOT NULL
supabase/migrations/0019_beta_security_hardening.sql:1049:AND v_claim.approx_lat IS NOT NULL AND v_claim.approx_lon IS NOT NULL THEN
supabase/migrations/0019_beta_security_hardening.sql-1050-v_distance := ST_Distance(
  +12 more in supabase/migrations/0019_beta_security_hardening.sql
supabase/migrations/0022_encounter_band_from_sighting.sql-83-RETURN;
supabase/migrations/0022_encounter_band_from_sighting.sql-84-END IF;
supabase/migrations/0022_encounter_band_from_sighting.sql-85-
supabase/migrations/0022_encounter_band_from_sighting.sql-86-IF p_lat IS NOT NULL AND p_lon IS NOT NULL
supabase/migrations/0022_encounter_band_from_sighting.sql:87:AND v_claim.approx_lat IS NOT NULL AND v_claim.approx_lon IS NOT NULL THEN
supabase/migrations/0022_encounter_band_from_sighting.sql-88-v_distance := ST_Distance(
supabase/migrations/0022_encounter_band_from_sighting.sql-89-ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography,
supabase/migrations/0022_encounter_band_from_sighting.sql-90-ST_SetSRID(ST_MakePoint(v_claim.approx_lon, v_claim.approx_lat), 4326)::geogr...
supabase/migrations/0022_encounter_band_from_sighting.sql-91-);
supabase/migrations/0024_accuracy_aware_correlation.sql-210-RETURN;
supabase/migrations/0024_accuracy_aware_correlation.sql-211-END IF;
supabase/migrations/0024_accuracy_aware_correlation.sql-212-
supabase/migrations/0024_accuracy_aware_correlation.sql-213-IF p_lat IS NOT NULL AND p_lon IS NOT NULL
supabase/migrations/0024_accuracy_aware_correlation.sql:214:AND v_claim.approx_lat IS NOT NULL AND v_claim.approx_lon IS NOT NULL THEN
supabase/migrations/0024_accuracy_aware_correlation.sql-215-v_distance := ST_Distance(
supabase/migrations/0024_accuracy_aware_correlation.sql-216-ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography,
supabase/migrations/0024_accuracy_aware_correlation.sql-217-ST_SetSRID(ST_MakePoint(v_claim.approx_lon, v_claim.approx_lat), 4326)::geogr...
supabase/migrations/0024_accuracy_aware_correlation.sql-218-);
supabase/migrations/0024_accuracy_aware_correlation.sql-287-DROP FUNCTION IF EXISTS public.claim_token(
supabase/migrations/0024_accuracy_aware_correlation.sql-288-TEXT, TIMESTAMPTZ, DOUBLE PRECISION, DOUBLE PRECISION, public.range_type
supabase/migrations/0024_accuracy_aware_correlation.sql-289-);
supabase/migrations/0024_accuracy_aware_correlation.sql-290-
supabase/migrations/0024_accuracy_aware_correlation.sql:291:CREATE OR REPLACE FUNCTION public.claim_token(
supabase/migrations/0024_accuracy_aware_correlation.sql-292-p_token TEXT,
  +3 more in supabase/migrations/0024_accuracy_aware_correlation.sql
supabase/migrations/0025_encounter_recurrence.sql-145-RETURN;
supabase/migrations/0025_encounter_recurrence.sql-146-END IF;
supabase/migrations/0025_encounter_recurrence.sql-147-
supabase/migrations/0025_encounter_recurrence.sql-148-IF p_lat IS NOT NULL AND p_lon IS NOT NULL
supabase/migrations/0025_encounter_recurrence.sql:149:AND v_claim.approx_lat IS NOT NULL AND v_claim.approx_lon IS NOT NULL THEN
supabase/migrations/0025_encounter_recurrence.sql-150-v_distance := ST_Distance(
supabase/migrations/0025_encounter_recurrence.sql-151-ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography,
supabase/migrations/0025_encounter_recurrence.sql-152-ST_SetSRID(ST_MakePoint(v_claim.approx_lon, v_claim.approx_lat), 4326)::geogr...
supabase/migrations/0025_encounter_recurrence.sql-153-);
supabase/migrations/0027_durable_recurrence_pairs.sql-136-WHEN 'feet_10' THEN -75 WHEN 'feet_20' THEN -85 ELSE -95 END;
supabase/migrations/0027_durable_recurrence_pairs.sql-137-IF v_rssi IS NULL OR v_rssi < v_min_rssi THEN RETURN; END IF;
supabase/migrations/0027_durable_recurrence_pairs.sql-138-
supabase/migrations/0027_durable_recurrence_pairs.sql-139-IF p_lat IS NOT NULL AND p_lon IS NOT NULL
supabase/migrations/0027_durable_recurrence_pairs.sql:140:AND v_claim.approx_lat IS NOT NULL AND v_claim.approx_lon IS NOT NULL THEN
supabase/migrations/0027_durable_recurrence_pairs.sql-141-v_distance := ST_Distance(
supabase/migrations/0027_durable_recurrence_pairs.sql-142-ST_SetSRID(ST_MakePoint(p_lon, p_lat),4326)::geography,
supabase/migrations/0027_durable_recurrence_pairs.sql-143-ST_SetSRID(ST_MakePoint(v_claim.approx_lon, v_claim.approx_lat),4326)::geogra...
supabase/migrations/0027_durable_recurrence_pairs.sql-144-IF v_distance > LEAST(400.0, GREATEST(5.0, p_radius_meters)) THEN RETURN; END...
supabase/migrations/0028_token_claim_history.sql-33-INSERT INTO public.token_claim_history
supabase/migrations/0028_token_claim_history.sql-34-(token, user_id, valid_from, valid_until, approx_lat, approx_lon, range_type,...
supabase/migrations/0028_token_claim_history.sql-35-SELECT token, user_id, valid_from, valid_until, approx_lat, approx_lon, range...
supabase/migrations/0028_token_claim_history.sql-36-FROM public.token_claims
supabase/migrations/0028_token_claim_history.sql:37:ON CONFLICT (token) DO NOTHING;
supabase/migrations/0028_token_claim_history.sql-38-
supabase/migrations/0028_token_claim_history.sql-39--- claim_token: write to history in addition to the live one-row-per-user claim.
supabase/migrations/0028_token_claim_history.sql:40:CREATE OR REPLACE FUNCTION public.claim_token(
supabase/migrations/0028_token_claim_history.sql-41-p_token TEXT, p_valid_until TIMESTAMPTZ,
supabase/migrations/0028_token_claim_history.sql-42-p_lat DOUBLE PRECISION DEFAULT NULL, p_lon DOUBLE PRECISION DEFAULT NULL,
supabase/migrations/0028_token_claim_history.sql-43-p_range public.range_type DEFAULT 'miles_10', p_accuracy DOUBLE PRECISION DEF...
supabase/migrations/0028_token_claim_history.sql-44-)
supabase/migrations/0028_token_claim_history.sql-82--- resolves for valid_until + grace even after the next rotation/release.
supabase/migrations/0028_token_claim_history.sql-83-INSERT INTO public.token_claim_history
supabase/migrations/0028_token_claim_history.sql-84-(token, user_id, valid_from, valid_until, approx_lat, approx_lon, range_type,...
  +15 more in supabase/migrations/0028_token_claim_history.sql
supabase/migrations/0029_reciprocal_confirmation.sql-126-ORDER BY s.observed_at DESC LIMIT 1;
supabase/migrations/0029_reciprocal_confirmation.sql-127-v_min_rssi := CASE COALESCE(v_claim.range_type,'feet_10') WHEN 'feet_10' THEN...
supabase/migrations/0029_reciprocal_confirmation.sql-128-IF v_rssi IS NULL OR v_rssi < v_min_rssi THEN RETURN; END IF;
supabase/migrations/0029_reciprocal_confirmation.sql-129-
supabase/migrations/0029_reciprocal_confirmation.sql:130:IF p_lat IS NOT NULL AND p_lon IS NOT NULL AND v_claim.approx_lat IS NOT NULL...
supabase/migrations/0029_reciprocal_confirmation.sql-131-v_distance := ST_Distance(ST_SetSRID(ST_MakePoint(p_lon, p_lat),4326)::geogra...
supabase/migrations/0029_reciprocal_confirmation.sql-132-IF v_distance > LEAST(400.0, GREATEST(5.0, p_radius_meters)) THEN RETURN; END...
supabase/migrations/0029_reciprocal_confirmation.sql-133-END IF;
supabase/migrations/0029_reciprocal_confirmation.sql-134-
supabase/migrations/0030_correlate_valid_from_grace.sql-45-ORDER BY s.observed_at DESC LIMIT 1;
supabase/migrations/0030_correlate_valid_from_grace.sql-46-v_min_rssi := CASE COALESCE(v_claim.range_type,'feet_10') WHEN 'feet_10' THEN...
supabase/migrations/0030_correlate_valid_from_grace.sql-47-IF v_rssi IS NULL OR v_rssi < v_min_rssi THEN RETURN; END IF;
supabase/migrations/0030_correlate_valid_from_grace.sql-48-
supabase/migrations/0030_correlate_valid_from_grace.sql:49:IF p_lat IS NOT NULL AND p_lon IS NOT NULL AND v_claim.approx_lat IS NOT NULL...
supabase/migrations/0030_correlate_valid_from_grace.sql-50-v_distance := ST_Distance(ST_SetSRID(ST_MakePoint(p_lon, p_lat),4326)::geogra...
supabase/migrations/0030_correlate_valid_from_grace.sql-51-IF v_distance > LEAST(400.0, GREATEST(5.0, p_radius_meters)) THEN RETURN; END...
supabase/migrations/0030_correlate_valid_from_grace.sql-52-END IF;
supabase/migrations/0030_correlate_valid_from_grace.sql-53-
supabase/migrations/0031_server_issued_token_batches.sql-14--- foundation for attesting issuance (App Attest / Play Integrity, step 3),
supabase/migrations/0031_server_issued_token_batches.sql-15--- detecting token fan-out abuse (step 4), and revocation.
supabase/migrations/0031_server_issued_token_batches.sql-16---
supabase/migrations/0031_server_issued_token_batches.sql-17--- Rollout is non-breaking: claim_token still accepts a self-minted token while
supabase/migrations/0031_server_issued_token_batches.sql:18:-- the flag `enforce_batch_tokens` is 0 (default). After the batch-aware client
supabase/migrations/0031_server_issued_token_batches.sql-19--- ships, flip the flag to 1 (a data change, no migration) to require batch
supabase/migrations/0031_server_issued_token_batches.sql-20--- membership. Observer-side offline scanning is unchanged (resolution is still
supabase/migrations/0031_server_issued_token_batches.sql-21--- via token_claim_history).
supabase/migrations/0031_server_issued_token_batches.sql-22-
supabase/migrations/0031_server_issued_token_batches.sql-23--- Enforcement flag — OFF by default so this deploy cannot break current clie...
supabase/migrations/0031_server_issued_token_batches.sql:24:INSERT INTO public.app_settings (key, value_num) VALUES ('enforce_batch_token...
supabase/migrations/0031_server_issued_token_batches.sql-25-ON CONFLICT (key) DO NOTHING;
supabase/migrations/0031_server_issued_token_batches.sql-26-
supabase/migrations/0031_server_issued_token_batches.sql:27:CREATE TABLE IF NOT EXISTS public.beacon_token_batch (
supabase/migrations/0031_server_issued_token_batches.sql-28-token       TEXT PRIMARY KEY,               -- opaque 32 hex chars (128-bit)
  +78 more in supabase/migrations/0031_server_issued_token_batches.sql
supabase/migrations/0032_relay_abuse_detection.sql-66-LAG(valid_from)  OVER w AS prev_from,
supabase/migrations/0032_relay_abuse_detection.sql-67-LAG(approx_lat)  OVER w AS prev_lat,
supabase/migrations/0032_relay_abuse_detection.sql-68-LAG(approx_lon)  OVER w AS prev_lon
supabase/migrations/0032_relay_abuse_detection.sql-69-FROM public.token_claim_history
supabase/migrations/0032_relay_abuse_detection.sql:70:WHERE valid_from > NOW() - p_since AND approx_lat IS NOT NULL AND approx_lon ...
supabase/migrations/0032_relay_abuse_detection.sql-71-WINDOW w AS (PARTITION BY user_id ORDER BY valid_from)
supabase/migrations/0032_relay_abuse_detection.sql-72-)
supabase/migrations/0032_relay_abuse_detection.sql-73-SELECT user_id,
supabase/migrations/0032_relay_abuse_detection.sql-74-ST_Distance(ST_SetSRID(ST_MakePoint(prev_lon, prev_lat),4326)::geography,
supabase/migrations/0032_relay_abuse_detection.sql-95-count(DISTINCT s.observer_user_id) AS observers
supabase/migrations/0032_relay_abuse_detection.sql-96-FROM public.token_claim_history h
supabase/migrations/0032_relay_abuse_detection.sql-97-JOIN public.sightings s ON s.observed_token = h.token
supabase/migrations/0032_relay_abuse_detection.sql-98-WHERE h.valid_from > NOW() - p_since
supabase/migrations/0032_relay_abuse_detection.sql:99:AND h.approx_lat IS NOT NULL AND h.approx_lon IS NOT NULL
supabase/migrations/0032_relay_abuse_detection.sql-100-AND s.observer_lat IS NOT NULL AND s.observer_lon IS NOT NULL
  +3 more in supabase/migrations/0032_relay_abuse_detection.sql
supabase/migrations/0033_relay_abuse_response_surface.sql-105-LAG(approx_lat) OVER w AS prev_lat,
supabase/migrations/0033_relay_abuse_response_surface.sql-106-LAG(approx_lon) OVER w AS prev_lon
supabase/migrations/0033_relay_abuse_response_surface.sql-107-FROM public.token_claim_history
supabase/migrations/0033_relay_abuse_response_surface.sql-108-WHERE valid_from > NOW() - p_since
supabase/migrations/0033_relay_abuse_response_surface.sql:109:AND approx_lat IS NOT NULL
supabase/migrations/0033_relay_abuse_response_surface.sql-110-AND approx_lon IS NOT NULL
supabase/migrations/0033_relay_abuse_response_surface.sql-111-WINDOW w AS (PARTITION BY user_id ORDER BY valid_from, token)
supabase/migrations/0033_relay_abuse_response_surface.sql-112-)
supabase/migrations/0033_relay_abuse_response_surface.sql-113-SELECT
supabase/migrations/0033_relay_abuse_response_surface.sql-155-count(DISTINCT s.observer_user_id) AS observers
supabase/migrations/0033_relay_abuse_response_surface.sql-156-FROM public.token_claim_history h
supabase/migrations/0033_relay_abuse_response_surface.sql-157-JOIN public.sightings s ON s.observed_token = h.token
supabase/migrations/0033_relay_abuse_response_surface.sql-158-WHERE h.valid_from > NOW() - p_since
supabase/migrations/0033_relay_abuse_response_surface.sql:159:AND h.approx_lat IS NOT NULL
supabase/migrations/0033_relay_abuse_response_surface.sql-160-AND h.approx_lon IS NOT NULL
  +3 more in supabase/migrations/0033_relay_abuse_response_surface.sql
supabase/migrations/0034_device_attestation_scaffold.sql-8--- verifying, calls record_device_attestation() (service role) to record the
supabase/migrations/0034_device_attestation_scaffold.sql-9--- verdict; issue_token_batch then requires a fresh attestation when the
supabase/migrations/0034_device_attestation_scaffold.sql-10--- `require_attestation` flag is on.
supabase/migrations/0034_device_attestation_scaffold.sql-11---
supabase/migrations/0034_device_attestation_scaffold.sql:12:-- Non-breaking rollout, mirroring enforce_batch_tokens (step 2):
supabase/migrations/0034_device_attestation_scaffold.sql-13---   flag defaults 0 -> issue_token_batch behaves exactly as before. After the
supabase/migrations/0034_device_attestation_scaffold.sql-14---   verifier + attesting client ship to devices, flip to 1 (a data change, no
supabase/migrations/0034_device_attestation_scaffold.sql-15---   migration) to require attestation. Rollback: set it back to 0.
supabase/migrations/0034_device_attestation_scaffold.sql-16---
supabase/migrations/0034_device_attestation_scaffold.sql-101-
supabase/migrations/0034_device_attestation_scaffold.sql-102--- Housekeeping + abuse guard: drop the caller's stale batches, then cap how
supabase/migrations/0034_device_attestation_scaffold.sql-103--- many distinct live days one user may hold (a relay farm requesting many
supabase/migrations/0034_device_attestation_scaffold.sql-104--- days of tokens would trip this).
supabase/migrations/0034_device_attestation_scaffold.sql:105:DELETE FROM public.beacon_token_batch WHERE user_id = v_uid AND batch_day < C...
  +26 more in supabase/migrations/0034_device_attestation_scaffold.sql
+12 more files

exec
/bin/bash -lc "sed -n '450,590p' supabase/migrations/0059_proximity_wake.sql
sed -n '90,175p' supabase/migrations/0060_batch_claim_and_rotation.sql
sed -n '1,70p' supabase/migrations/0060_batch_claim_and_rotation.sql
sed -n '160,195p' supabase/migrations/0053_late_evidence_tolerance.sql
sed -n '1,120p' supabase/migrations/0015_automation_audit.sql" in /home/hazypiff/in-range
 exited 2 in 0ms:
sed: can't read supabase/migrations/0059_proximity_wake.sql: No such file or directory
sed: can't read supabase/migrations/0060_batch_claim_and_rotation.sql: No such file or directory
sed: can't read supabase/migrations/0060_batch_claim_and_rotation.sql: No such file or directory
  v_late INTERVAL := public.late_evidence_window();
  v_late_min INT := (EXTRACT(EPOCH FROM public.late_evidence_window()) / 60)::INT;
BEGIN
  IF v_uid IS NULL OR NOT public.current_user_can_discover() THEN RETURN; END IF;
  SELECT * INTO v_claim FROM public.token_claim_history tc
  WHERE tc.token = lower(p_observed_token) AND tc.user_id <> v_uid
    -- Floor so a late-window-valid, end-of-life token is never excluded
    -- (token life <=21 min + late window; +2 slack). valid_until is the gate.
    AND tc.valid_from > NOW() - make_interval(mins => GREATEST(23 + v_late_min, LEAST(30, GREATEST(1, p_time_window_minutes))))
    AND tc.valid_until > NOW() - v_late ORDER BY tc.valid_from DESC LIMIT 1;
  IF NOT FOUND OR NOT public.is_discoverable_user(v_claim.user_id) THEN RETURN; END IF;
  IF public.is_blocked_pair(v_uid, v_claim.user_id) THEN RETURN; END IF;

  SELECT s.rssi, s.range_type INTO v_rssi, v_sight_range FROM public.sightings s
  WHERE s.observer_user_id = v_uid AND s.observed_token = lower(p_observed_token)
  ORDER BY s.observed_at DESC LIMIT 1;
  v_min_rssi := CASE COALESCE(v_claim.range_type,'feet_10') WHEN 'feet_10' THEN -75 WHEN 'feet_20' THEN -85 ELSE -95 END;
  IF v_rssi IS NULL OR v_rssi < v_min_rssi THEN RETURN; END IF;

  IF p_lat IS NOT NULL AND p_lon IS NOT NULL AND v_claim.approx_lat IS NOT NULL AND v_claim.approx_lon IS NOT NULL THEN
    v_distance := ST_Distance(ST_SetSRID(ST_MakePoint(p_lon, p_lat),4326)::geography, ST_SetSRID(ST_MakePoint(v_claim.approx_lon, v_claim.approx_lat),4326)::geography);
    IF v_distance > LEAST(400.0, GREATEST(5.0, p_radius_meters)) THEN RETURN; END IF;
  END IF;

  IF v_sight_range IS NOT NULL AND v_sight_range::TEXT LIKE 'feet_%' THEN v_band := v_sight_range; ELSE v_band := COALESCE(v_claim.range_type, 'feet_10'); END IF;

  -- Reciprocity gate (server-receipt window; caller-supplied values ignored).
  -- 0053: widened from a fixed 3 min — the other side's evidence may be a
  -- locked phone's wake-burst upload from earlier in the same co-presence.
  SELECT rs.range_type INTO v_reverse_band FROM public.sightings rs
  WHERE rs.observer_user_id = v_claim.user_id AND rs.observed_user_id = v_uid
    AND rs.received_at > NOW() - v_late
  ORDER BY rs.received_at DESC LIMIT 1;
  IF NOT FOUND THEN RETURN; END IF;

  IF v_reverse_band IS NOT NULL AND v_reverse_band::TEXT LIKE 'feet_%' AND v_band::TEXT LIKE 'feet_%'
sed: can't read supabase/migrations/0015_automation_audit.sql: No such file or directory

exec
/bin/bash -lc "rtk rg --files supabase/migrations | rg '/(0015|0053|0059|0060)_'" in /home/hazypiff/in-range
 succeeded in 0ms:
supabase/migrations/0060_batch_token_preclaim.sql
supabase/migrations/0059_proximity_wake_producer.sql
supabase/migrations/0015_audit_remaining_fixes.sql
supabase/migrations/0053_late_evidence_tolerance.sql

exec
/bin/bash -lc "sed -n '450,590p' supabase/migrations/0059_proximity_wake_producer.sql
sed -n '90,175p' supabase/migrations/0060_batch_token_preclaim.sql
sed -n '1,70p' supabase/migrations/0060_batch_token_preclaim.sql
sed -n '1,100p' supabase/migrations/0015_audit_remaining_fixes.sql" in /home/hazypiff/in-range
 succeeded in 0ms:
    ), '[]'::jsonb),

    -- Registered push destinations, by platform and provider only -- the token
    -- itself is a device credential, not user-facing data.
    'push_devices', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'platform', d.platform, 'provider', d.provider, 'created_at', d.created_at))
        FROM public.device_push_tokens d WHERE d.user_id = v_uid
    ), '[]'::jsonb)
  ) INTO v_out;

  RETURN v_out;
END;
$$;

COMMENT ON FUNCTION public.export_my_data IS
  'Right-of-access export of the calling user''s own data. Counterparts appear only as opaque user ids; reports filed about the caller are excluded to protect reporters.';

REVOKE ALL ON FUNCTION public.export_my_data() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.export_my_data() TO authenticated;

-- ---------------------------------------------------------------------------
-- 5. Retention (cleanup_ephemeral_data)
-- ---------------------------------------------------------------------------
-- Body as of 0058_subtle_wake_privacy.sql:334, unchanged. proximity_wake_requests
-- retention already covers both user_id and recipient_user_id rows.

CREATE OR REPLACE FUNCTION public.cleanup_ephemeral_data()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_holds BOOLEAN := EXISTS (
    SELECT 1 FROM public.legal_holds
     WHERE released_at IS NULL
       AND (expires_at IS NULL OR expires_at > NOW()));
BEGIN
  IF v_holds THEN
    DELETE FROM public.token_claims tc
     WHERE tc.valid_until < NOW() - INTERVAL '30 minutes'
       AND NOT public.has_legal_hold(tc.user_id);

    DELETE FROM public.sightings s
     WHERE s.observed_at < NOW() - INTERVAL '24 hours'
       AND NOT public.has_legal_hold(s.observer_user_id)
       AND NOT EXISTS (
         SELECT 1 FROM public.token_claims tc
          WHERE tc.token = s.observed_token
            AND public.has_legal_hold(tc.user_id));

    DELETE FROM public.location_pings lp
     WHERE lp.created_at < NOW() - INTERVAL '24 hours'
       AND NOT public.has_legal_hold(lp.user_id);

    -- 0047: token_claim_history is ephemeral too; it was never pruned.
    DELETE FROM public.token_claim_history h
     WHERE h.valid_until < NOW() - INTERVAL '24 hours'
       AND NOT public.has_legal_hold(h.user_id);

    -- 0056
    DELETE FROM public.rssi_samples rs
     WHERE rs.received_at < NOW() - INTERVAL '30 days'
       AND NOT public.has_legal_hold(rs.user_id);

    -- 0058
    DELETE FROM public.venue_anchors va
     WHERE va.updated_at < NOW() - INTERVAL '14 days'
       AND NOT public.has_legal_hold(va.user_id);

    DELETE FROM public.proximity_wake_requests pwr
     WHERE (pwr.status IN ('sent', 'skipped') AND pwr.created_at < NOW() - INTERVAL '30 days')
        OR (pwr.status = 'failed' AND pwr.created_at < NOW() - INTERVAL '7 days');
  ELSE
    DELETE FROM public.token_claims
     WHERE valid_until < NOW() - INTERVAL '30 minutes';

    DELETE FROM public.sightings
     WHERE observed_at < NOW() - INTERVAL '24 hours';

    DELETE FROM public.location_pings
     WHERE created_at < NOW() - INTERVAL '24 hours';

    -- 0047: token_claim_history is ephemeral too; it was never pruned.
    DELETE FROM public.token_claim_history
     WHERE valid_until < NOW() - INTERVAL '24 hours';

    -- 0056
    DELETE FROM public.rssi_samples
     WHERE received_at < NOW() - INTERVAL '30 days';

    -- 0058
    DELETE FROM public.venue_anchors
     WHERE updated_at < NOW() - INTERVAL '14 days';

    DELETE FROM public.proximity_wake_requests
     WHERE (status IN ('sent', 'skipped') AND created_at < NOW() - INTERVAL '30 days')
        OR (status = 'failed' AND created_at < NOW() - INTERVAL '7 days');
  END IF;

  -- Rate buckets outlive their window by definition; drop idle ones.
  DELETE FROM public.rssi_batch_rate
   WHERE window_start < NOW() - INTERVAL '1 day';

  -- Recover a worker that died after atomically claiming a batch.
  UPDATE public.notification_outbox
     SET status = CASE WHEN attempts < 5 THEN 'pending' ELSE 'failed' END,
         last_error = 'stale_processing_recovered',
         processing_at = NULL
   WHERE status = 'processing'
     AND processing_at < NOW() - INTERVAL '10 minutes';

  DELETE FROM public.notification_outbox
   WHERE (status IN ('sent', 'skipped') AND created_at < NOW() - INTERVAL '30 days')
      OR (status = 'failed' AND created_at < NOW() - INTERVAL '7 days');

  DELETE FROM public.ai_events WHERE created_at < NOW() - INTERVAL '90 days';
  DELETE FROM public.ai_runs   WHERE created_at < NOW() - INTERVAL '90 days';

  -- Evidence snapshots: 1 year, unless the subject is still held or the
  -- snapshot backs an unexpired (or unfiled) CyberTipline obligation.
  DELETE FROM public.report_evidence e
   WHERE e.captured_at < NOW() - INTERVAL '1 year'
     AND (e.subject_user IS NULL OR NOT public.has_legal_hold(e.subject_user))
     AND NOT EXISTS (
       SELECT 1 FROM public.cybertipline_queue q
        WHERE q.report_id = e.report_id
          AND (q.preserve_until IS NULL OR q.preserve_until > NOW()));
END;
$$;

COMMENT ON FUNCTION public.cleanup_ephemeral_data IS
  'Sweeps ephemeral tables: location_pings (24 h), sightings (24 h), token_claim_history (24 h), rssi_samples (30 d), venue_anchors (14 d), proximity_wake_requests (30 d sent / 7 d failed), notification_outbox, AI events/runs (90 d), report_evidence (1 y). Honors legal holds.';

COMMIT;
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_now TIMESTAMPTZ := clock_timestamp();
  v_last TIMESTAMPTZ;
  v_in_batch BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;
  IF NOT public.current_user_can_discover() THEN
    RAISE EXCEPTION 'Complete age and photo verification before using Beacon' USING ERRCODE='42501'; END IF;
  -- Consent gate (0040). No-op unless app_settings.enforce_consent = 1.
  PERFORM public.require_consent(v_uid, 'ble_proximity');
  -- 0048: the consent UI scopes GPS to precise_location ("deleted after 24h").
  -- Beacon mandatorily uploads coordinates, so a user who withdrew precise
  -- location must not keep feeding GPS through it, even while ble_proximity
  -- is still granted. Explicit withdrawal denies regardless of enforce_consent.
  IF public.consent_withdrawn(v_uid, 'precise_location') THEN
    RAISE EXCEPTION 'Location sharing was turned off' USING ERRCODE='42501'; END IF;
  IF p_token IS NULL OR p_token !~ '^[0-9a-f]{32}$' THEN
    RAISE EXCEPTION 'Invalid beacon token' USING ERRCODE='22023'; END IF;
  IF p_valid_until IS NULL OR p_valid_until <= v_now + INTERVAL '1 minute'
     OR p_valid_until > v_now + INTERVAL '21 minutes' THEN
    RAISE EXCEPTION 'Token validity must end within 1..21 minutes' USING ERRCODE='22023'; END IF;
  IF p_lat IS NULL OR p_lon IS NULL THEN
    RAISE EXCEPTION 'Fresh coordinates are required' USING ERRCODE='22023'; END IF;
  IF p_lat NOT BETWEEN -90 AND 90 OR p_lon NOT BETWEEN -180 AND 180 THEN
    RAISE EXCEPTION 'Invalid coordinates' USING ERRCODE='22023'; END IF;
  IF p_accuracy IS NOT NULL AND (p_accuracy < 0 OR p_accuracy > 10000) THEN
    RAISE EXCEPTION 'Invalid accuracy' USING ERRCODE='22023'; END IF;

  -- #6 step 2: the token must be one the server issued to THIS user. Consume it
  -- (observability); enforce membership only when the flag is on so the
  -- batch-aware client can roll out first.
  UPDATE public.beacon_token_batch b SET consumed_at = COALESCE(b.consumed_at, v_now)
  WHERE b.token = lower(p_token) AND b.user_id = v_uid
  RETURNING TRUE INTO v_in_batch;
  IF NOT COALESCE(v_in_batch, FALSE)
     AND COALESCE((SELECT value_num FROM public.app_settings WHERE key='enforce_batch_tokens'), 0) >= 1 THEN
    RAISE EXCEPTION 'Beacon token was not issued to this account' USING ERRCODE='22023';
  END IF;

  SELECT last_claimed_at INTO v_last FROM public.token_claims WHERE user_id = v_uid;
  IF v_last IS NOT NULL AND v_last > v_now - INTERVAL '5 seconds' THEN
    RAISE EXCEPTION 'Beacon claim rate limit' USING ERRCODE='54000'; END IF;

  INSERT INTO public.token_claims (
    user_id, token, valid_from, valid_until, approx_lat, approx_lon,
    range_type, accuracy_m, created_at, last_claimed_at)
  VALUES (v_uid, lower(p_token), v_now, p_valid_until, p_lat, p_lon, p_range, p_accuracy, v_now, v_now)
  ON CONFLICT (user_id) DO UPDATE SET
    token = EXCLUDED.token, valid_from = EXCLUDED.valid_from, valid_until = EXCLUDED.valid_until,
    approx_lat = EXCLUDED.approx_lat, approx_lon = EXCLUDED.approx_lon,
    range_type = EXCLUDED.range_type, accuracy_m = EXCLUDED.accuracy_m,
    last_claimed_at = EXCLUDED.last_claimed_at;

  INSERT INTO public.token_claim_history
    (token, user_id, valid_from, valid_until, approx_lat, approx_lon, range_type, accuracy_m, created_at)
  VALUES (lower(p_token), v_uid, v_now, p_valid_until, p_lat, p_lon, p_range, p_accuracy, v_now)
  ON CONFLICT (token) DO UPDATE SET
    valid_until = EXCLUDED.valid_until,
    -- 0060: fill geo fields on a batch-pre-claimed (NULL-location) row; never
    -- blank out a fix an earlier single claim already wrote.
    approx_lat = COALESCE(EXCLUDED.approx_lat, public.token_claim_history.approx_lat),
    approx_lon = COALESCE(EXCLUDED.approx_lon, public.token_claim_history.approx_lon),
    range_type = COALESCE(EXCLUDED.range_type, public.token_claim_history.range_type),
    accuracy_m = COALESCE(EXCLUDED.accuracy_m, public.token_claim_history.accuracy_m);
END;
$function$;
-- 0060: close the native-token resolution gap (audit 2026-07-25, critical #2).
--
-- A locked iPhone's native BackgroundBeacon serves GATT reads from its
-- persisted day batch, rotating slots on its own schedule. Only Dart's
-- claim_token wrote token_claim_history — and record_sighting resolves
-- exclusively through that table — so once Dart was suspended or evicted,
-- every later slot the native side served was unresolvable: a peer could
-- hear the beacon and never map it to a person.
--
-- Fix: claim_token_batch pre-claims every still-live slot the server issued
-- to the caller (today + tomorrow, per issue_token_batch), so any token the
-- native carrier can serve is already resolvable. Rows are written WITHOUT
-- coordinates on purpose: a fix stamped at session start would make
-- correlate_encounter's 400 m plausibility veto reject real encounters after
-- the user travels (the reviewer-#7 failure shape), and NULL location is
-- both the safer product choice (a dark, locked phone records no GPS trail)
-- and handled by the veto, which only applies when a claim carries
-- coordinates. When Dart is alive and later single-claims a slot, the
-- claim_token conflict merge below fills the geo fields back in, so the
-- veto returns for the slots that have a fresh fix.

-- ---------------------------------------------------------------------------
-- 1. claim_token_batch: pre-claim the caller's own issued slots.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.claim_token_batch(
  p_range public.range_type DEFAULT 'feet_60'
)
RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_now TIMESTAMPTZ := clock_timestamp();
  v_rows INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;
  IF NOT public.current_user_can_discover() THEN
    RAISE EXCEPTION 'Complete age and photo verification before using Beacon' USING ERRCODE='42501'; END IF;
  -- Consent gate (0040), same as claim_token. No precise_location check: this
  -- function stores NO coordinates, so there is nothing location-shaped to
  -- withdraw from.
  PERFORM public.require_consent(v_uid, 'ble_proximity');

  -- Throttle: one batch claim per minute per user. Only batch-originated rows
  -- (NULL location) count, so the per-rotation single claims never trip it.
  IF EXISTS (
    SELECT 1 FROM public.token_claim_history h
    WHERE h.user_id = v_uid AND h.approx_lat IS NULL
      AND h.created_at > v_now - INTERVAL '1 minute'
  ) THEN
    RAISE EXCEPTION 'Beacon claim rate limit' USING ERRCODE='54000';
  END IF;

  -- Only tokens the server issued to THIS caller (beacon_token_batch
  -- membership) — no user can claim another's tokens, and far-future mining
  -- is already bounded by issue_token_batch's day cap. valid_from/valid_until
  -- are the slot's real window, so resolution and expiry line up with what
  -- the native carrier actually serves. ON CONFLICT DO NOTHING: a slot the
  -- live client already single-claimed keeps its location-bearing row.
  INSERT INTO public.token_claim_history
    (token, user_id, valid_from, valid_until, approx_lat, approx_lon,
     range_type, accuracy_m, created_at)
  SELECT b.token, v_uid, b.valid_from, b.valid_until, NULL, NULL,
         p_range, NULL, v_now
  FROM public.beacon_token_batch b
  WHERE b.user_id = v_uid AND b.valid_until > v_now
  ON CONFLICT (token) DO NOTHING;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows;
END;
-- =============================================================================
-- Migration 0015: Remaining full-stack audit items (F1, P3, M6, M8)
-- =============================================================================
-- F1  Note: migration 0003 CASE used feet_100/feet_500 (not in enum). Superseded
--     by range_radius_meters() in 0008 / single_sighting in 0011 — no runtime path.
-- M6  Drop dead nearby_location_pings (use get_locals_feed).
-- M8  is_blocked_pair: only participants (or service_role / null auth) may probe.
-- P3  Schedule run_maintenance every 15 min when pg_cron is available.
-- =============================================================================

-- ----------------------------------------------------------------------------
-- M6: Drop deprecated nearby_location_pings overloads
-- ----------------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'nearby_location_pings'
  LOOP
    EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig || ' CASCADE';
  END LOOP;
END $$;

-- ----------------------------------------------------------------------------
-- M8: Harden is_blocked_pair — no arbitrary pair probing by third parties
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_blocked_pair(a UUID, b UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Authenticated callers may only check pairs they belong to.
  -- service_role / background jobs often have auth.uid() IS NULL — allow.
  IF auth.uid() IS NOT NULL
     AND auth.uid() IS DISTINCT FROM a
     AND auth.uid() IS DISTINCT FROM b THEN
    RAISE EXCEPTION 'Not authorized to probe block status'
      USING ERRCODE = '42501';
  END IF;

  RETURN EXISTS (
    SELECT 1 FROM public.blocks
    WHERE (blocker_id = a AND blocked_id = b)
       OR (blocker_id = b AND blocked_id = a)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.is_blocked_pair(UUID, UUID)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.is_blocked_pair(UUID, UUID) IS
  'True if either user blocked the other. Caller must be a participant (or service).';

-- ----------------------------------------------------------------------------
-- P3: Feet expiry + cleanup cron (best-effort when pg_cron available)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  -- Supabase: enable pg_cron in Dashboard → Database → Extensions if this fails.
  CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'pg_cron not available: % — schedule Edge Function maintenance instead', SQLERRM;
END $$;

DO $$
BEGIN
  -- Unschedule prior job if re-running
  PERFORM cron.unschedule(jobid)
  FROM cron.job
  WHERE jobname = 'in-range-maintenance';
EXCEPTION
  WHEN undefined_table THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  PERFORM cron.schedule(
    'in-range-maintenance',
    '*/15 * * * *',
    $cron$ SELECT public.run_maintenance(); $cron$
  );
  RAISE NOTICE 'Scheduled in-range-maintenance every 15 minutes';
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Could not schedule cron: % — use Edge Function maintenance cron in Dashboard', SQLERRM;
END $$;

-- ----------------------------------------------------------------------------
-- F1 documentation
-- ----------------------------------------------------------------------------

exec
/bin/bash -lc "rtk rg -n -o '\\b[CHM]-[A-Z]+-[0-9]+\\b' docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md" in /home/hazypiff/in-range
 succeeded in 0ms:
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:22:C-DIAG-1
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:98:C-DIAG-1
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:112:H-DIAG-2
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:127:H-DIAG-3
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:155:H-ORCH-1
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:179:C-SQL-1
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:179:C-SQL-3
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:180:C-SQL-4
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:181:H-SQL-2
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:182:H-CONSENT-1
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:192:C-RT-1
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:193:H-RT-3
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:195:H-RT-4
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:196:H-RT-5
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:197:H-RT-7
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:25:C-PROD-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:26:C-SQL-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:26:C-SQL-4
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:27:C-SQL-3
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:28:C-DIAG-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:39:C-DIAG-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:41:C-DIAG-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:44:C-DIAG-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:50:C-SQL-3
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:50:C-PROD-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:50:H-CONSENT-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:56:C-PROD-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:70:C-SQL-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:77:C-SQL-3
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:84:C-SQL-4
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:87:C-SQL-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:91:C-DIAG-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:131:H-DIAG-2
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:134:H-DIAG-3
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:137:H-ORCH-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:147:H-CFG-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:150:H-WL-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:150:H-WL-2
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:156:H-SQL-2
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:156:C-SQL-2
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:165:H-SQL-3
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:174:H-CONSENT-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:178:H-PW-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:180:H-RT-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:180:C-RT-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:185:H-RT-2
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:187:H-RT-3
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:192:H-RT-4
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:193:H-RT-5
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:195:H-RT-6
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:197:H-RT-7
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:199:H-RT-8
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:201:H-RT-9
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:202:H-PRIV-2
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:206:M-SQL-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:209:M-SQL-2
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:211:M-PRIV-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:235:H-CONSENT-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:237:C-SQL-3
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:238:C-PROD-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:243:C-PROD-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:244:C-SQL-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:244:C-SQL-3
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:244:C-SQL-4
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:245:C-DIAG-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:246:H-WL-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:246:H-WL-2
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:248:H-RT-1

exec
/bin/bash -lc "rg -n -o '\\b[CHM]-[A-Z0-9]+-[0-9]+\\b' docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md" in /home/hazypiff/in-range
 succeeded in 0ms:
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:22:C-DIAG-1
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:34:H-W5-1
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:67:H-W5-2
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:82:H-W5-3
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:98:C-DIAG-1
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:112:H-DIAG-2
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:127:H-DIAG-3
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:155:H-ORCH-1
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:167:H-W5-3
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:168:H-W5-4
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:170:H-W5-5
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:179:C-SQL-1
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:179:C-SQL-3
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:180:C-SQL-4
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:181:H-SQL-2
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:182:H-CONSENT-1
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:192:C-RT-1
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:193:H-RT-3
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:195:H-RT-4
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:196:H-RT-5
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:197:H-RT-7
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:25:C-PROD-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:26:C-SQL-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:26:C-SQL-4
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:27:C-SQL-3
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:28:C-DIAG-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:39:C-DIAG-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:41:C-DIAG-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:44:C-DIAG-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:50:C-SQL-3
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:50:C-PROD-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:50:H-CONSENT-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:56:C-PROD-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:70:C-SQL-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:77:C-SQL-3
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:84:C-SQL-4
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:87:C-SQL-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:91:C-DIAG-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:104:H-W5-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:111:H-W5-2
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:114:H-W5-3
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:117:H-W5-4
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:121:H-W5-5
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:126:H-W5-6
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:128:H-W5-7
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:131:H-DIAG-2
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:134:H-DIAG-3
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:137:H-ORCH-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:147:H-CFG-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:150:H-WL-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:150:H-WL-2
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:156:H-SQL-2
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:156:C-SQL-2
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:165:H-SQL-3
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:174:H-CONSENT-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:178:H-PW-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:180:H-RT-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:180:C-RT-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:185:H-RT-2
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:187:H-RT-3
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:192:H-RT-4
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:193:H-RT-5
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:195:H-RT-6
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:197:H-RT-7
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:199:H-RT-8
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:201:H-RT-9
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:202:H-PRIV-2
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:206:M-SQL-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:209:M-SQL-2
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:211:M-PRIV-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:215:M-W5-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:235:H-CONSENT-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:237:C-SQL-3
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:238:C-PROD-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:243:C-PROD-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:244:C-SQL-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:244:C-SQL-3
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:244:C-SQL-4
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:245:C-DIAG-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:246:H-WL-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:246:H-WL-2
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:247:H-W5-1
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:247:H-W5-5
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:248:H-W5-2
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:248:H-W5-3
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:248:H-RT-1

exec
/bin/bash -lc "date '+%H:%M:%S.%N'
stat -c '%y %s %n' docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md
rg -n 'CRITICAL —|H-W5-[34567]|C-RT-1|five Criticals|nine Criticals|unverified, not cleared|cron\\.job' docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md" in /home/hazypiff/in-range
 succeeded in 0ms:
15:53:23.934149274
2026-08-01 15:49:58.732533428 -0400 20113 docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md
2026-08-01 15:50:54.036011051 -0400 15456 docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:82:**3. H-W5-3 (High, merge-blocking) — a dial that connects but dies before HELLO_ACK leaks a `pendingDial` forever.**
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:98:**4. C-DIAG-1 (CRITICAL — the one Critical in your queue) — the diagnostic W5 link layer ships inside release binaries.**
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:167:`H-W5-3` no lease persistence, and restoration actively re-handshakes restored links with fresh identity
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:168:that the peer correctly rejects (≥5-min blackout plus a wedged lease) · `H-W5-4` `dropPeer` never erases
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:170:the app can re-dial someone the user just rejected · `H-W5-5` the per-encounter candidate is keyed by peer
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:192:`C-RT-1` `_flushSightings` has no re-entrancy guard and `turnOffBeacon` awaits it, so the user can tap
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:204:what this round exists to establish, given all suites were green while five Criticals and the entire
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:54:## CRITICAL — live today
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:114:- **H-W5-3** A dial that connects but dies before HELLO_ACK leaks a `pendingDial` forever
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:117:- **H-W5-4** No lease persistence; restoration re-handshakes restored links with *fresh* identity, which
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:121:- **H-W5-5** The 120s reconnect grace is normally unreachable — `tokenCacheTTL` 900s and
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:126:- **H-W5-6** `dropPeer` never erases the lease and does not disconnect an inbound keeper;
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:128:- **H-W5-7** The per-encounter candidate is keyed by peer alias, so rotation mints a new one; R7 fix #1 is
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:180:- **H-RT-1** *(was C-RT-1, downgraded per Codex — a local availability failure, not a security-boundary
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:247:4. **H-W5-1** (two-line hoist + the vector that pins it), then **H-W5-5** *before* the Phase-5 matrix.
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:248:5. **H-W5-2, H-W5-3, H-RT-1** — the wedges.
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:254:  The highest-value manual check remains `SELECT jobname, schedule FROM cron.job;` — `0015`'s
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:260:  **unverified, not cleared** — a caveat that also applies to Kimi's DB-derived "all clean" statement.

exec
/bin/bash -lc "git branch --show-current
git rev-parse --short HEAD
test -f ios/Runner/W5LinkController.swift && echo W5_CONTROLLER_PRESENT || echo W5_CONTROLLER_ABSENT
git ls-files ios/Runner/W5LinkController.swift ios/Runner/BackgroundBeacon.swift ios/Runner.xcodeproj/project.pbxproj
rg -n 'W5LinkController|bb\\.w5links|INRANGE_W5_LINKS' ios/Runner ios/Runner.xcodeproj/project.pbxproj lib/core/config/app_config.dart lib/features/beacon/beacon_service.dart 2>/dev/null | head -n 80" in /home/hazypiff/in-range
 succeeded in 0ms:
main
f2f948e
W5_CONTROLLER_ABSENT
ios/Runner.xcodeproj/project.pbxproj
ios/Runner/BackgroundBeacon.swift
lib/core/config/app_config.dart:38:        'INRANGE_W5_LINKS' =>
lib/core/config/app_config.dart:39:          const String.fromEnvironment('INRANGE_W5_LINKS'),
lib/core/config/app_config.dart:67:  /// behavior until it passes. Enable per build: --dart-define=INRANGE_W5_LINKS=true
lib/core/config/app_config.dart:69:      _env('INRANGE_W5_LINKS').toLowerCase() == 'true';
ios/Runner/BackgroundBeacon.swift:86:  /// by the INRANGE_W5_LINKS dart-define (persisted here by Dart). Off = pure
ios/Runner/BackgroundBeacon.swift:92:  private static let keyW5Links = "bb.w5links"
ios/Runner/BackgroundBeacon.swift:254:        // Test-only gate for W5 persistent links (INRANGE_W5_LINKS).
ios/Runner/BackgroundBeacon.swift:1030:    // W5 (test-only, INRANGE_W5_LINKS): token read = session start. Subscribe

exec
/bin/bash -lc "sed -n '1,120p' ios/Runner/BackgroundBeacon.swift
sed -n '1010,1060p' ios/Runner/BackgroundBeacon.swift
rg -n 'recordRssi|w5Link|W5Ownership|controlCharUUID' ios/Runner/BackgroundBeacon.swift ios/Runner.xcodeproj/project.pbxproj" in /home/hazypiff/in-range
 succeeded in 0ms:
import BackgroundTasks
import CoreBluetooth
import Flutter
import UIKit

/// W2 of docs/IOS_BACKGROUND_BLE_WIRING.md — the locked-phone BLE carrier.
///
/// Peripheral side: advertises the fixed 0xCAFE discovery marker (+ the
/// rotating token as a second 128-bit service UUID for the foreground
/// fast path) and hosts a GATT service (CAFE) with one read-only
/// characteristic (CA7E) whose value is computed PER READ from the stored
/// token batch — background reads wake the app, so no timer ever fires.
///
/// Central side: filtered scan for CAFE (the only scan shape iOS delivers
/// in background). Token comes from the advert when present — as the second
/// service UUID from an iOS peer, or as manufacturer data from an Android peer
/// (finding B1, 2026-07-26: a filtered iOS scan still delivers manufacturer
/// data, and Android's 16-byte token is already in it, so that direction needs
/// no connect at all) — otherwise connect → read CA7E → disconnect, with a
/// per-peripheral token cache.
///
/// Survives relaunch: managers use CoreBluetooth state restoration, and the
/// batch + enabled flag persist in UserDefaults so a BT-relaunched process
/// can serve reads and buffer sightings before the Flutter engine attaches.
final class BackgroundBeacon: NSObject {
  static let shared = BackgroundBeacon()

  // 0000CAFE-…: app-wide discovery marker (beacon_service.dart).
  private static let serviceUUID = CBUUID(string: "CAFE")
  private static let tokenCharUUID = CBUUID(string: "CA7E")
  /// in-range's BLE company identifier, mirrored from beacon_service.dart's
  /// `_inRangeManufacturerId`. Android's advert carries the 16-byte
  /// correlation token under this id; CoreBluetooth hands the field back with
  /// the company id still on the front, little-endian. Finding B1.
  private static let inRangeCompanyID: UInt16 = 0xFFFF
  // W5 keepalive channel (contract proposed issue #3): central writes a
  // 1-byte heartbeat every ~8 s, peripheral notifies back — the Herald
  // ping-pong. Each incoming BLE event grants ~10 s of background
  // execution, inside which the next outgoing beat is sent: neither side
  // ever suspends while the session lives.
  private static let keepaliveCharUUID = CBUUID(string: "CA5E")
  private static let peripheralRestoreID = "io.inrange.beacon.peripheral"
  private static let centralRestoreID = "io.inrange.beacon.central"

  private static let keyEnabled = "bb.enabled"
  private static let keySlots = "bb.slots"
  private static let keyBuffer = "bb.buffer"
  private static let keyPingURL = "bb.pingUrl"
  private static let keyPingAuth = "bb.pingAuth"
  private static let bufferCap = 500
  private static let tokenCacheTTL: TimeInterval = 15 * 60
  private static let connectRetryFloor: TimeInterval = 5 * 60
  private static let scanRestartFloor: TimeInterval = 4

  private var peripheralMgr: CBPeripheralManager?
  private var centralMgr: CBCentralManager?
  private var channel: FlutterMethodChannel?
  private var serviceAdded = false
  /// Set by peripheralManager(_:willRestoreState:) — which fires BEFORE
  /// peripheralManagerDidUpdateState on a restoration relaunch — so the state
  /// callback does not clobber the restored service registration (audit
  /// 2026-07-25, critical #3).
  private var didRestorePeripheral = false

  // W5 live sessions: peripheral.identifier → session state. Session-scoped
  // by OWNER RULE (2026-07-24): hold while the encounter is live, drop on
  // part/reject — never a permanent ledger (matches token-rotation privacy).
  private struct W5Session {
    let peripheral: CBPeripheral
    var tokenHex: String
    var lastEvent: Date
    var keepaliveChar: CBCharacteristic?
    var lastRssiAt: Date
    var lastBeatAt: Date
    var writeInFlight: Bool  // exactly one .withResponse write outstanding
    var notifyReady: Bool    // didUpdateNotificationStateFor confirmed
    var seq: Int             // beat sequence number (logging)
    var lastGattOp: String   // last GATT op attempted (logging)
  }
  private var w5: [UUID: W5Session] = [:]
  private var keepaliveNotifyChar: CBMutableCharacteristic?
  /// Peripheral-side: a notify that updateValue refused (queue full) — retried
  /// only from peripheralManagerIsReady(toUpdateSubscribers:).
  private var pendingNotify = false
  /// W5 is a TEST-ONLY link layer until proven through the awake gates; gated
  /// by the INRANGE_W5_LINKS dart-define (persisted here by Dart). Off = pure
  /// token-read behavior, no persistent connections.
  private var w5LinksEnabled: Bool { defaults.bool(forKey: Self.keyW5Links) }
  // Callback-primed cadence: after a write CONFIRMS (didWriteValueFor), the
  // next beat is scheduled ~4 s out. Herald-shaped — not an instant loop.
  private static let w5Cadence: TimeInterval = 4
  private static let keyW5Links = "bb.w5links"

  // peripheral.identifier → (tokenHex, cachedAt)
  private var tokenCache: [UUID: (hex: String, at: Date)] = [:]
  // peripherals we're currently connected/connecting to, kept strongly.
  private var inflight: [UUID: CBPeripheral] = [:]
  private var inflightRSSI: [UUID: Int] = [:]
  private var lastConnectAttempt: [UUID: Date] = [:]
  private var lastScanRestart = Date.distantPast
  private var scanHeartbeat: Timer?

  /// Last verdict from peripheralManagerDidStartAdvertising, retained so the
  /// state snapshot can be rebuilt on demand: an invokeMethod issued while
  /// backgrounded is silently dropped by a suspended engine (same hazard as
  /// the sighting buffer), so Dart re-pulls the truth via `bleState`.
  /// Prior-art review 2026-07-26, finding 1.3.
  private var advertisingActive = false
  private var advertisingError: String?
  /// role → last state name written to bb_wake_log.txt, so W5 logs
  /// transitions rather than re-logging a steady state.
  private var lastLoggedManagerState: [String: String] = [:]

  private var defaults: UserDefaults { UserDefaults.standard }

  // MARK: - Lifecycle

  /// Called from AppDelegate on EVERY launch. When iOS relaunched us for a
  /// bluetooth event (or the user had the beacon on before a jetsam), the
  /// persisted enabled flag brings both managers straight back up — no
    // one-write-at-a-time. No synchronous unacked write here.
    if characteristic.uuid == Self.keepaliveCharUUID {
      guard w5[id] != nil else { return }
      w5[id]?.lastEvent = Date()
      w5MaybeReadRSSI(id)
      w5MaybeBeat(id)
      return
    }
    guard characteristic.uuid == Self.tokenCharUUID,
          let data = characteristic.value, data.count == 16 else {
      centralMgr?.cancelPeripheralConnection(peripheral)
      return
    }
    let hex = data.map { String(format: "%02x", $0) }.joined()
    tokenCache[id] = (hex, Date())
    if tokenCache.count > 64 {
      let cutoff = Date().addingTimeInterval(-Self.tokenCacheTTL)
      tokenCache = tokenCache.filter { $0.value.at > cutoff }
    }
    emitSighting(tokenHex: hex, rssi: inflightRSSI[id] ?? -85)
    // W5 (test-only, INRANGE_W5_LINKS): token read = session start. Subscribe
    // to the peer's keepalive; the first beat waits for
    // didUpdateNotificationStateFor. If W5 is gated off, disconnect after the
    // read (pure token-read behavior).
    guard w5LinksEnabled else {
      centralMgr?.cancelPeripheralConnection(peripheral)
      return
    }
    if w5[id] == nil {
      let ka = peripheral.services?
        .first(where: { $0.uuid == Self.serviceUUID })?.characteristics?
        .first(where: { $0.uuid == Self.keepaliveCharUUID })
      w5[id] = W5Session(
        peripheral: peripheral, tokenHex: hex, lastEvent: Date(),
        keepaliveChar: ka, lastRssiAt: .distantPast, lastBeatAt: .distantPast,
        writeInFlight: false, notifyReady: false, seq: 0, lastGattOp: "start")
      logWake("w5-start")
      inflight.removeValue(forKey: id)  // session owns the peripheral now
      if let ka = ka {
        // Subscribe first; the first beat fires from didUpdateNotificationState.
        peripheral.setNotifyValue(true, for: ka)
      }
      peripheral.readRSSI()
    } else {
      w5[id]?.tokenHex = hex  // rotation refresh on the open connection
    }
  }

  /// didUpdateNotificationStateFor: the subscription is confirmed — only now
  /// is it safe to send the first beat.
  func peripheral(
ios/Runner/BackgroundBeacon.swift:88:  private var w5LinksEnabled: Bool { defaults.bool(forKey: Self.keyW5Links) }
ios/Runner/BackgroundBeacon.swift:880:      if w5LinksEnabled, w5[id] == nil, inflight[id] == nil,
ios/Runner/BackgroundBeacon.swift:1034:    guard w5LinksEnabled else {
ios/Runner/BackgroundBeacon.swift:1103:    guard w5LinksEnabled, var s = w5[id], s.peripheral.state == .connected,

exec
/bin/bash -lc "rtk rg -n -C 3 'C-DIAG-1|W5LinkController|release binar|shipped artifact|prior diag install|bb\\.w5links|issue #8' docs/research/2026-08-01-hardening docs/ISSUE* docs 2>/dev/null | head -n 360" in /home/hazypiff/in-range
 succeeded in 0ms:
928 matches in 13 files:

docs/.../2026-07-31/claude_kimi_chat_2026-07-31.md-21-### Link layer / W5
docs/.../2026-07-31/claude_kimi_chat_2026-07-31.md-22-- N1. **Divergent W5 iOS lines.** origin/main got `ec7856e` (persistent-link ...
docs/.../2026-07-31/claude_kimi_chat_2026-07-31.md-23-flag-gated, bench-proven single-pair) directly, while PR #9's branch holds the
docs/.../2026-07-31/claude_kimi_chat_2026-07-31.md:24:W5LinkController/W5Ownership/W5Codec stack (+2697/−44 vs main, BackgroundBeac...
docs/.../2026-07-31/claude_kimi_chat_2026-07-31.md-25-168 lines) and does NOT contain ec7856e. Two parallel W5 native implementatio...
docs/.../2026-07-31/claude_kimi_chat_2026-07-31.md-26-reconciled before either flag turns on. Merge-order risk compounds with PR #5...
docs/.../2026-07-31/claude_kimi_chat_2026-07-31.md-27-beacon stack).
docs/.../2026-07-31/claude_kimi_chat_2026-07-31.md-108-
docs/.../2026-07-31/claude_kimi_chat_2026-07-31.md-109-## Per-item verdicts
docs/.../2026-07-31/claude_kimi_chat_2026-07-31.md-110-
docs/.../2026-07-31/claude_kimi_chat_2026-07-31.md:111:**N1 — DISPUTE (core premise), numbers updated.** The "two parallel W5 native...
docs/.../2026-07-31/claude_kimi_chat_2026-07-31.md-112-
docs/.../2026-07-31/claude_kimi_chat_2026-07-31.md-113-**N2 — CONFIRM with refinement.** The gate is real but "no activity since rou...
docs/.../2026-07-31/claude_kimi_chat_2026-07-31.md-114-
docs/.../2026-07-31/claude_kimi_chat_2026-07-31.md-313-FAIL test line-by-line — honest (smoking-gun assertions: viewGen reset provin...
  +21 more in docs/.../2026-07-31/claude_kimi_chat_2026-07-31.md
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-25-- **one live in production, remotely exploitable by anyone** — C-PROD-1;
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-26-- **two exploitable today by any authenticated user with a modified client** ...
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-27-- **two data-handling defects that require no attacker at all** — C-SQL-3, a ...
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:28:leaving a de-anonymisable proximity graph at rest, and C-DIAG-1, a diagnostic...
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:29:release binaries that writes plaintext tokens to disk.
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-30-
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-31-Plus a large High tier that blocks the W5 merge and the Phase-5 hardware matrix.
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-32-
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-33-**Severity convention, settled by the panel:** *Critical* means reachable **n...
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:34:today or present in shipped artifacts. Defects in the W5 *state machine* are ...
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-35-merge-blocking** because `INRANGE_W5_LINKS` ships default OFF. This was Codex...
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-36-it and Kimi accepted. It changes no priorities — the W5 items remain first in...
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-37-stops the tier from lying about reachability.
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-38-
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:39:**Why C-DIAG-1 is Critical while the W5 defects are High — these are not in t...
  +85 more in docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-19-
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-20-Five Critical findings total, and after the consensus round **none of them is...
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-21-those are rated High/merge-blocking because `INRANGE_W5_LINKS` ships default ...
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:22:(C-DIAG-1, which is Critical precisely because it is *not* behind that flag)....
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-23-High, and it still blocks the W5 merge and the Phase-5 matrix, so the order b...
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-24-Linux side has already taken the server, Android and web items, so do not spe...
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-25-is at the bottom of this message.
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-53-This violates `docs/W5_ENCOUNTER_LEASE_DESIGN.md:295-296` ("A committed keepe...
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-54-leases never rekey").
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-55-
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:56:**Why it fires without an attacker, and this part matters for your fix:** `W5...
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-57-mints the local candidate per peer alias, and `HELLO_ACK` (`W5Codec.swift:50`...
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-58-at all** — the outbound call site at `:208-211` passes none. So on the outbou...
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-59-is unresolvable by construction. The inbound path at `:317` does pass `peerPr...
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-71-stay `nil` for the process lifetime.
  +79 more in docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md
docs/.../transcripts/codex_audit_out.md-18-
docs/.../transcripts/codex_audit_out.md-19-FILES IN SCOPE (all under ios/):
docs/.../transcripts/codex_audit_out.md-20-- Runner/BackgroundBeacon.swift (~1254 lines) — the BLE central/peripheral ma...
docs/.../transcripts/codex_audit_out.md:21:- Runner/W5LinkController.swift (~701 lines) — link lifecycle, keepalive, dia...
docs/.../transcripts/codex_audit_out.md-22-- Runner/W5Ownership.swift (~565 lines) — the ownership/lease state machine
docs/.../transcripts/codex_audit_out.md-23-- Runner/W5Codec.swift — the binary wire codec for control messages
docs/.../transcripts/codex_audit_out.md-24-- Runner/SubtleWakeCoordinator.swift
docs/.../transcripts/codex_audit_out.md-165-bff57fa feat(ios): W5 ownership authority — Swift mirror of the v5.2 oracle +...
docs/.../transcripts/codex_audit_out.md-166-
docs/.../transcripts/codex_audit_out.md-167-exec
docs/.../transcripts/codex_audit_out.md:168:/bin/bash -lc "rtk rg -n \"v5\\.2|Restoration / persistence|Restoration|persi...
docs/.../transcripts/codex_audit_out.md-169-succeeded in 0ms:
docs/.../transcripts/codex_audit_out.md-170-1:# W5 encounter-lease — design v5.2 (fix for #7)
docs/.../transcripts/codex_audit_out.md-171-7:## v5.2 corrections (PR #9 round 6)
docs/.../transcripts/codex_audit_out.md-173-372:## Restoration / persistence (native)
  +831 more in docs/.../transcripts/codex_audit_out.md
docs/.../transcripts/codex_audit_prompt.md-6-
docs/.../transcripts/codex_audit_prompt.md-7-FILES IN SCOPE (all under ios/):
docs/.../transcripts/codex_audit_prompt.md-8-- Runner/BackgroundBeacon.swift (~1254 lines) — the BLE central/peripheral ma...
docs/.../transcripts/codex_audit_prompt.md:9:- Runner/W5LinkController.swift (~701 lines) — link lifecycle, keepalive, dia...
docs/.../transcripts/codex_audit_prompt.md-10-- Runner/W5Ownership.swift (~565 lines) — the ownership/lease state machine
docs/.../transcripts/codex_audit_prompt.md-11-- Runner/W5Codec.swift — the binary wire codec for control messages
docs/.../transcripts/codex_audit_prompt.md-12-- Runner/SubtleWakeCoordinator.swift
docs/.../transcripts/codex_audit_prompt.md-6-
docs/.../transcripts/codex_audit_prompt.md-7-FILES IN SCOPE (all under ios/):
docs/.../transcripts/codex_audit_prompt.md-8-- Runner/BackgroundBeacon.swift (~1254 lines) — the BLE central/peripheral ma...
docs/.../transcripts/codex_audit_prompt.md:9:- Runner/W5LinkController.swift (~701 lines) — link lifecycle, keepalive, dia...
docs/.../transcripts/codex_audit_prompt.md-10-- Runner/W5Ownership.swift (~565 lines) — the ownership/lease state machine
docs/.../transcripts/codex_audit_prompt.md-11-- Runner/W5Codec.swift — the binary wire codec for control messages
docs/.../transcripts/codex_audit_prompt.md-12-- Runner/SubtleWakeCoordinator.swift
docs/.../transcripts/codex_consensus_r1.md-32-4. WRONG OR INCOMPLETE FIXES. Any suggested fix that would not actually close...
docs/.../transcripts/codex_consensus_r1.md-33-
docs/.../transcripts/codex_consensus_r1.md-34-Two findings already carry corrections the coordinator applied to a reviewer'...
docs/.../transcripts/codex_consensus_r1.md:35:- C-DIAG-1: the reviewer said the RSSI file write has no gate; the coordinato...
docs/.../transcripts/codex_consensus_r1.md-36-- H-DIAG-3: the reviewer called pre-Dart restoration an unimplemented require...
docs/.../transcripts/codex_consensus_r1.md-37-
docs/.../transcripts/codex_consensus_r1.md-38-Also sanity-check the single highest-stakes claim in the report: that the dep...
docs/.../transcripts/codex_consensus_r1.md-1171-say-so. Each finding was re-checked against the code by the coordinating agen...
docs/.../transcripts/codex_consensus_r1.md-1172-evidence is recorded in `verified_findings_working.md`. Reviewer claims that ...
docs/.../transcripts/codex_consensus_r1.md-1173-verification were corrected or dropped, and the corrections are noted inline....
docs/.../transcripts/codex_consensus_r1.md:1174:material enough to change how a finding should be read (C-DIAG-1 and H-DIAG-3).
docs/.../transcripts/codex_consensus_r1.md-1175-
docs/.../transcripts/codex_consensus_r1.md-1176-**Baseline established:** `flutter analyze` clean; `flutter test` 183/183 on ...
docs/.../transcripts/codex_consensus_r1.md-1177-branch. Both suites are green — none of the defects below is caught by an exi...
docs/.../transcripts/codex_consensus_r1.md-1252-throttle — no purpose. `venue_anchors` has no RPC at all; the client writes t...
  +1893 more in docs/.../transcripts/codex_consensus_r1.md
docs/.../transcripts/codex_final.md-37-
docs/.../transcripts/codex_final.md-38-My adjudication, and I want you both to challenge it if you disagree: **I am ...
docs/.../transcripts/codex_final.md-39-
docs/.../transcripts/codex_final.md:40:That leaves the Critical tier as: C-PROD-1 (live, unauthenticated production ...
docs/.../transcripts/codex_final.md-41-
docs/.../transcripts/codex_final.md-42-Do you both agree with that final tier? If either of you thinks a demoted ite...
docs/.../transcripts/codex_final.md-43-
docs/.../transcripts/codex_final.md-37-
docs/.../transcripts/codex_final.md-38-My adjudication, and I want you both to challenge it if you disagree: **I am ...
docs/.../transcripts/codex_final.md-39-
docs/.../transcripts/codex_final.md:40:That leaves the Critical tier as: C-PROD-1 (live, unauthenticated production ...
docs/.../transcripts/codex_final.md-41-
docs/.../transcripts/codex_final.md-42-Do you both agree with that final tier? If either of you thinks a demoted ite...
docs/.../transcripts/codex_final.md-43-
docs/.../transcripts/consensus_prompt.md-20-4. WRONG OR INCOMPLETE FIXES. Any suggested fix that would not actually close...
docs/.../transcripts/consensus_prompt.md-21-
docs/.../transcripts/consensus_prompt.md-22-Two findings already carry corrections the coordinator applied to a reviewer'...
docs/.../transcripts/consensus_prompt.md:23:- C-DIAG-1: the reviewer said the RSSI file write has no gate; the coordinato...
docs/.../transcripts/consensus_prompt.md-24-- H-DIAG-3: the reviewer called pre-Dart restoration an unimplemented require...
docs/.../transcripts/consensus_prompt.md-25-
docs/.../transcripts/consensus_prompt.md-26-Also sanity-check the single highest-stakes claim in the report: that the dep...
docs/.../transcripts/consensus_prompt.md-20-4. WRONG OR INCOMPLETE FIXES. Any suggested fix that would not actually close...
docs/.../transcripts/consensus_prompt.md-21-
docs/.../transcripts/consensus_prompt.md-22-Two findings already carry corrections the coordinator applied to a reviewer'...
docs/.../transcripts/consensus_prompt.md:23:- C-DIAG-1: the reviewer said the RSSI file write has no gate; the coordinato...
docs/.../transcripts/consensus_prompt.md-24-- H-DIAG-3: the reviewer called pre-Dart restoration an unimplemented require...
docs/.../transcripts/consensus_prompt.md-25-
docs/.../transcripts/consensus_prompt.md-26-Also sanity-check the single highest-stakes claim in the report: that the dep...
docs/.../transcripts/final_round.md-25-
docs/.../transcripts/final_round.md-26-My adjudication, and I want you both to challenge it if you disagree: **I am ...
docs/.../transcripts/final_round.md-27-
docs/.../transcripts/final_round.md:28:That leaves the Critical tier as: C-PROD-1 (live, unauthenticated production ...
docs/.../transcripts/final_round.md-29-
docs/.../transcripts/final_round.md-30-Do you both agree with that final tier? If either of you thinks a demoted ite...
docs/.../transcripts/final_round.md-31-
docs/.../transcripts/final_round.md-25-
docs/.../transcripts/final_round.md-26-My adjudication, and I want you both to challenge it if you disagree: **I am ...
docs/.../transcripts/final_round.md-27-
docs/.../transcripts/final_round.md:28:That leaves the Critical tier as: C-PROD-1 (live, unauthenticated production ...
docs/.../transcripts/final_round.md-29-
docs/.../transcripts/final_round.md-30-Do you both agree with that final tier? If either of you thinks a demoted ite...
docs/.../transcripts/final_round.md-31-
docs/.../transcripts/kimi_consensus_r1.md-2-
docs/.../transcripts/kimi_consensus_r1.md-3-Priority verification targets:
docs/.../transcripts/kimi_consensus_r1.md-4-1. C-PROD-1 reasoning: service_auth.ts requireServiceRole returns 405 on non-...
docs/.../transcripts/kimi_consensus_r1.md:5:2. C-DIAG-1 correction: BackgroundBeacon.swift:956 (sessions only form behind...
docs/.../transcripts/kimi_consensus_r1.md-6-3. H-DIAG-3 correction: AppDelegate.swift:12-17 comments, BackgroundBeacon.sw...
docs/.../transcripts/kimi_consensus_r1.md-7-4. C-SQL-2: correlate_miles_encounters latest definition — is 0048:251-360 re...
docs/.../transcripts/kimi_consensus_r1.md-8-5. C-SQL-3: cleanup_ephemeral_data latest (0059:477-580) — check no later red...
docs/.../transcripts/kimi_consensus_r1.md-9-6. C-W5-1: Dart w5_ownership.dart:321 vs 351, Swift W5Ownership.swift:250 vs ...
docs/.../transcripts/kimi_consensus_r1.md-10-7. C-W5-2: BackgroundBeacon.swift:736-751, :714-734.
docs/.../transcripts/kimi_consensus_r1.md:11:8. C-W5-3: W5LinkController.swift:240-254, W5Ownership.swift:516-530.
docs/.../transcripts/kimi_consensus_r1.md-12-9. C-RT-1: beacon_service.dart:417-422, :603, :2449-2483 (main repo).
docs/.../transcripts/kimi_consensus_r1.md-13-10. C-CONSENT-1: grep require_consent in 0056/0059 — quick.
docs/.../transcripts/kimi_consensus_r1.md-14-11. H-WL-1: 0062:100-104, :120-131 — check the unauthenticated cross-user UPD...
docs/.../transcripts/kimi_consensus_r1.md-28-- Worktree: BackgroundBeacon.swift:956, :120-124, :633-650; AppDelegate.swift...
docs/.../transcripts/kimi_consensus_r1.md-29-- Grep latest definitions: correlate_miles_encounters, cleanup_ephemeral_data...
  +121 more in docs/.../transcripts/kimi_consensus_r1.md
docs/.../transcripts/kimi_consensus_r2.md-67-
docs/.../transcripts/kimi_consensus_r2.md-68-So the coordinator is right on dispute 2: my refutation was wrong in conclusi...
docs/.../transcripts/kimi_consensus_r2.md-69-
docs/.../transcripts/kimi_consensus_r2.md:70:Remaining nuance: is the effect as stated? "false Close By for a peer who was...
docs/.../transcripts/kimi_consensus_r2.md-71-
docs/.../transcripts/kimi_consensus_r2.md-72-So verdict on dispute 2: I agree — withdraw my refutation. H-RT-3 stands, arg...
docs/.../transcripts/kimi_consensus_r2.md-73-
docs/.../transcripts/kimi_consensus_r2.md-67-
docs/.../transcripts/kimi_consensus_r2.md-68-So the coordinator is right on dispute 2: my refutation was wrong in conclusi...
docs/.../transcripts/kimi_consensus_r2.md-69-
docs/.../transcripts/kimi_consensus_r2.md:70:Remaining nuance: is the effect as stated? "false Close By for a peer who was...
docs/.../transcripts/kimi_consensus_r2.md-71-
docs/.../transcripts/kimi_consensus_r2.md-72-So verdict on dispute 2: I agree — withdraw my refutation. H-RT-3 stands, arg...
docs/.../transcripts/kimi_consensus_r2.md-73-
docs/.../transcripts/kimi_final.md-36-
docs/.../transcripts/kimi_final.md-37-**2. H-ORCH-1 correction — accept.** Independently confirmed: `git ls-files t...
docs/.../transcripts/kimi_final.md-38-
docs/.../transcripts/kimi_final.md:39:**3. Severity tier — I agree, including C-RT-1.** My Critical rating of the W...
docs/.../transcripts/kimi_final.md-40-
docs/.../transcripts/kimi_final.md-41-**4. REPORT-META remedy — confirmed.** "Criticals and disputed findings carry...
docs/.../transcripts/kimi_final.md-42-
docs/.../transcripts/kimi_final.md-36-
docs/.../transcripts/kimi_final.md-37-**2. H-ORCH-1 correction — accept.** Independently confirmed: `git ls-files t...
docs/.../transcripts/kimi_final.md-38-
docs/.../transcripts/kimi_final.md:39:**3. Severity tier — I agree, including C-RT-1.** My Critical rating of the W...
docs/.../transcripts/kimi_final.md-40-
docs/.../transcripts/kimi_final.md-41-**4. REPORT-META remedy — confirmed.** "Criticals and disputed findings carry...
docs/.../transcripts/kimi_final.md-42-
docs/.../2026-08-01-hardening/verified_findings_working.md-48-
docs/.../2026-08-01-hardening/verified_findings_working.md-49----
docs/.../2026-08-01-hardening/verified_findings_working.md-50-
docs/.../2026-08-01-hardening/verified_findings_working.md:51:## C-DIAG-1 — Diagnostic W5 link layer + plaintext RSSI log ship in productio...
docs/.../2026-08-01-hardening/verified_findings_working.md-52-
docs/.../2026-08-01-hardening/verified_findings_working.md-53-**Severity:** Critical (privacy: plaintext proximity records written by a rel...
docs/.../2026-08-01-hardening/verified_findings_working.md-54-**Branch:** `fix/w5-encounter-lease`
docs/.../2026-08-01-hardening/verified_findings_working.md-55-
docs/.../2026-08-01-hardening/verified_findings_working.md-56-**Verified evidence:**
docs/.../2026-08-01-hardening/verified_findings_working.md-57-- The ENTIRE iOS tree contains exactly **three** `#if INRANGE_DIAG` sites, al...
docs/.../2026-08-01-hardening/verified_findings_working.md:58:`BackgroundBeacon.swift` (lines 52, 68, 694). `W5LinkController.swift` (701 l...
docs/.../2026-08-01-hardening/verified_findings_working.md-59-the second diagnostic subsystem) has **zero**.
docs/.../2026-08-01-hardening/verified_findings_working.md-60-Proof: `grep -rn INRANGE_DIAG ios/Runner/ ios/RunnerTests/`
docs/.../2026-08-01-hardening/verified_findings_working.md-61-- The W5 activation gate is a persisted runtime boolean, not a compile-time f...
docs/.../2026-08-01-hardening/verified_findings_working.md-62-`BackgroundBeacon.swift:120` → `var w5LinksEnabled: Bool { defaults.bool(forK...
  +137 more in docs/.../2026-08-01-hardening/verified_findings_working.md

exec
/bin/bash -lc "rtk rg -n -C 3 'TestFlight|shipped|release build|production build|installed|diag install|prior diagnostic|bundle id|fix/w5-encounter-lease' docs/research/2026-07-31 docs/research/2026-08-01-hardening docs/ISSUE_8* docs 2>/dev/null | head -n 500" in /home/hazypiff/in-range
 succeeded in 0ms:
424 matches in 43 files:

docs/ADVERSARIAL_REVIEW_2026-07-15.md-40->
docs/ADVERSARIAL_REVIEW_2026-07-15.md-41-> **#6 step 2 — server-issued opaque token batches (0031 + client), SHIPPED.**
docs/ADVERSARIAL_REVIEW_2026-07-15.md-42-> Beacon tokens are now minted by the SERVER (`issue_token_batch`: 96 opaque
docs/ADVERSARIAL_REVIEW_2026-07-15.md:43:> 122-bit tokens/day) instead of derived client-side from an HMAC secret shipped
docs/ADVERSARIAL_REVIEW_2026-07-15.md-44-> in the app (which was cosmetic — anyone with the binary could compute it). ...
docs/ADVERSARIAL_REVIEW_2026-07-15.md-45-> client fetches a day's batch and advertises the slot covering now
docs/ADVERSARIAL_REVIEW_2026-07-15.md-46-> (`BatchTokenSource`, replacing `EphemeralTokenGenerator`); it still claims per
docs/ADVERSARIAL_REVIEW_2026-07-15.md-75-> privileges. See `docs/RELAY_ABUSE_RUNBOOK.md`.
docs/ADVERSARIAL_REVIEW_2026-07-15.md-76->
docs/ADVERSARIAL_REVIEW_2026-07-15.md-77-> **Remaining #6 roadmap:** (3) App Attest / Play Integrity — **server scaffo...
docs/ADVERSARIAL_REVIEW_2026-07-15.md:78:> shipped** (`0034`: `device_attestations` + service-role writer +
docs/ADVERSARIAL_REVIEW_2026-07-15.md-79-> `require_attestation`-gated `issue_token_batch`, flag OFF, harness T12); still
docs/ADVERSARIAL_REVIEW_2026-07-15.md-80-> needs the Edge Function verifier + client attestation call + platform
docs/ADVERSARIAL_REVIEW_2026-07-15.md-81-> credentials + devices (see handoff Task C). (5) UWB `secure_ranged` — needs...
docs/ADVERSARIAL_REVIEW_2026-07-15.md-165-- **Severity:** correctness-bug
  +13 more in docs/ADVERSARIAL_REVIEW_2026-07-15.md
docs/APP_STORE_COMPLIANCE_2026-07-25.md-5-marked. Nothing here is speculative — where I could not verify something, it
docs/APP_STORE_COMPLIANCE_2026-07-25.md-6-says so.
docs/APP_STORE_COMPLIANCE_2026-07-25.md-7-
docs/APP_STORE_COMPLIANCE_2026-07-25.md:8:Fix C1 before any TestFlight or App Store build. The rest are paperwork-shaped
docs/APP_STORE_COMPLIANCE_2026-07-25.md-9-but two of them are rejection causes on their own.
docs/APP_STORE_COMPLIANCE_2026-07-25.md-10-
docs/APP_STORE_COMPLIANCE_2026-07-25.md-11----
docs/APP_STORE_COMPLIANCE_2026-07-25.md-34-It is correct to leave `true` for calibration walks. It must be `false` for
docs/APP_STORE_COMPLIANCE_2026-07-25.md-35-anything distributed.
docs/APP_STORE_COMPLIANCE_2026-07-25.md-36-
docs/APP_STORE_COMPLIANCE_2026-07-25.md:37:**Fix:** set `INRANGE_CALIB_SCAN=false` before any TestFlight/App Store archive.
docs/APP_STORE_COMPLIANCE_2026-07-25.md:38:Better: make the release build refuse to proceed while it is true — a check in
docs/APP_STORE_COMPLIANCE_2026-07-25.md-39-`build-install-ios.sh` when `--release` is passed costs three lines and removes
docs/APP_STORE_COMPLIANCE_2026-07-25.md-40-the failure mode permanently.
docs/APP_STORE_COMPLIANCE_2026-07-25.md-41-
  +7 more in docs/APP_STORE_COMPLIANCE_2026-07-25.md
docs/CALIBRATION_FREEZE_2026-07-23.md-58-| Extractor defaults | `scripts/extract_walk.py` | trim 20 s, max AP age 60 s...
docs/CALIBRATION_FREEZE_2026-07-23.md-59-| Walk protocol | `docs/WALK4_PROTOCOL.md` at tag | stop-and-return, explicit...
docs/CALIBRATION_FREEZE_2026-07-23.md-60-| Capture | `scripts/walk_capture.sh` | 64M verified buffer + explicit clear,...
docs/CALIBRATION_FREEZE_2026-07-23.md:61:| Installed S9 builds (324c…498, 513…498) | this box, debug multi-ABI | built...
docs/CALIBRATION_FREEZE_2026-07-23.md:62:| **Rahul's devices (S22, iPhone 15 Plus)** | Mac side | **REINSTALL REQUIRED...
docs/CALIBRATION_FREEZE_2026-07-23.md-63-| Server (prod riigipzlyqeaadyvbuty) | migrations ledger | `0053` — `late_evi...
docs/CALIBRATION_FREEZE_2026-07-23.md-64-
docs/CALIBRATION_FREEZE_2026-07-23.md-65-## New in this round vs 07-18b
docs/CLOUD_RSSI_UPLOAD_SPEC.md-56-what retention runs on.
docs/CLOUD_RSSI_UPLOAD_SPEC.md-57-
docs/CLOUD_RSSI_UPLOAD_SPEC.md-58-**The RPC returns rows *inserted*, not rows offered.** A replayed batch retur...
docs/CLOUD_RSSI_UPLOAD_SPEC.md:59:is how the client tells "already shipped" from "shipped now".
docs/CLOUD_RSSI_UPLOAD_SPEC.md-60-
docs/CLOUD_RSSI_UPLOAD_SPEC.md-61-**Rate limiting is metered before the empty-batch short-circuit.** Metering o...
docs/CLOUD_RSSI_UPLOAD_SPEC.md-62-that carry rows would leave an empty-array flood entirely unmetered — the sam...
docs/DEVICE_TESTING_JOURNAL.md-97-- Diagnostic leverage: that failure message fires **only** on the
docs/DEVICE_TESTING_JOURNAL.md-98-silent-denial path — config/crypto/sign-in failures throw `StateError` and
docs/DEVICE_TESTING_JOURNAL.md-99-render a different message. That is what narrowed the search.
docs/DEVICE_TESTING_JOURNAL.md:100:- Verified NOT the cause: same failure on debug **and** release builds (so not
docs/DEVICE_TESTING_JOURNAL.md-101-a build-mode artifact); Podfile `PERMISSION_*` macros verified present in
docs/DEVICE_TESTING_JOURNAL.md-102-`Pods.xcodeproj` (12 build configs). Those macros were a genuine latent bug
docs/DEVICE_TESTING_JOURNAL.md-103-in their own right (permission_handler compiles handlers out without them)
docs/FINANCIAL_RESEARCH_MONETIZATION_2026-07-31_JOINT.md-154-## 5. Launch acquisition (NYC + DMV, ~$60–100k/4mo envelope)
docs/FINANCIAL_RESEARCH_MONETIZATION_2026-07-31_JOINT.md-155-
docs/FINANCIAL_RESEARCH_MONETIZATION_2026-07-31_JOINT.md-156-Blended target: **$4–8 per activated user** [EST] vs $10–15+ going paid-first...
docs/FINANCIAL_RESEARCH_MONETIZATION_2026-07-31_JOINT.md:157:"Activated" = installed + profile + ≥1 session in a launch zone.
docs/FINANCIAL_RESEARCH_MONETIZATION_2026-07-31_JOINT.md-158-
docs/FINANCIAL_RESEARCH_MONETIZATION_2026-07-31_JOINT.md-159-| Channel | Share | $/activated [EST] |
docs/FINANCIAL_RESEARCH_MONETIZATION_2026-07-31_JOINT.md-160-|---|---|---|
docs/GAMIFICATION_SOCIAL_BLUEPRINT_2026-07-31_JOINT.md-6-encounters, bigger rewards for live video / recorded encounters, and a feed w...
docs/GAMIFICATION_SOCIAL_BLUEPRINT_2026-07-31_JOINT.md-7-watch streams and Moments (the social-media layer). Inspiration: Pokémon Go /...
docs/GAMIFICATION_SOCIAL_BLUEPRINT_2026-07-31_JOINT.md-8-**Evidence base:** repo @ main (post-PR#5, W5 green-lit round 8), migrations ...
docs/GAMIFICATION_SOCIAL_BLUEPRINT_2026-07-31_JOINT.md:9:policy pages shipped 2026-07-31 (`web/privacy.html`, `web/terms.html`, `web/p...
docs/GAMIFICATION_SOCIAL_BLUEPRINT_2026-07-31_JOINT.md-10-
docs/GAMIFICATION_SOCIAL_BLUEPRINT_2026-07-31_JOINT.md-11----
docs/GAMIFICATION_SOCIAL_BLUEPRINT_2026-07-31_JOINT.md-12-
docs/GAMIFICATION_SOCIAL_BLUEPRINT_2026-07-31_JOINT.md-182-
docs/GAMIFICATION_SOCIAL_BLUEPRINT_2026-07-31_JOINT.md-183-## 7. Policy & legal deltas (each scheduled BEFORE the phase that triggers it)
docs/GAMIFICATION_SOCIAL_BLUEPRINT_2026-07-31_JOINT.md-184-
docs/GAMIFICATION_SOCIAL_BLUEPRINT_2026-07-31_JOINT.md:185:Line-referenced conflicts with our own pages shipped 2026-07-31:
docs/GAMIFICATION_SOCIAL_BLUEPRINT_2026-07-31_JOINT.md-186-
docs/GAMIFICATION_SOCIAL_BLUEPRINT_2026-07-31_JOINT.md-187-1. **`privacy.html:67, :113-116` "no advertising" absolute vs sponsored Range...
docs/GAMIFICATION_SOCIAL_BLUEPRINT_2026-07-31_JOINT.md-188-OWNER DECISION.** Options: (a) drop venue sponsorship; (b) amend honestly: "No
docs/GAMIFICATION_SOCIAL_BLUEPRINT_2026-07-31_JOINT.md-285----
  +6 more in docs/GAMIFICATION_SOCIAL_BLUEPRINT_2026-07-31_JOINT.md
docs/IN_RANGE_IPHONE_COMPLETION_PLAN.md-63-| **P0 — Freeze hygiene** | Capture the 2026-07-25 walk honestly; document wh...
docs/IN_RANGE_IPHONE_COMPLETION_PLAN.md-64-| **P1 — Telemetry & platform guards** | Add source-tagged observations, iOS ...
docs/IN_RANGE_IPHONE_COMPLETION_PLAN.md-65-| **P2 — W5 warm-link BLE continuity** | Persistent GATT + `readRSSI()` on iO...
docs/IN_RANGE_IPHONE_COMPLETION_PLAN.md:66:| **P3a — W6 spike** | Bench Live Activity + Nearby Interaction + server-brok...
docs/IN_RANGE_IPHONE_COMPLETION_PLAN.md-67-| **P3b — W6 active-session assist** | Only if spike passes 18/20 gate: Live ...
docs/IN_RANGE_IPHONE_COMPLETION_PLAN.md-68-| **P4 — Fusion & retraining** | Train source-aware model only on post-W5/W6 ...
docs/IN_RANGE_IPHONE_COMPLETION_PLAN.md-69-| **P5 — Harden & ship** | Consent, App Review, production freeze, staged rol...
docs/IN_RANGE_IPHONE_COMPLETION_PLAN.md-282-
docs/IN_RANGE_IPHONE_COMPLETION_PLAN.md-283-## 7. P3 — W6: active-session assist (Live Activity + Nearby Interaction)
docs/IN_RANGE_IPHONE_COMPLETION_PLAN.md-284-
docs/IN_RANGE_IPHONE_COMPLETION_PLAN.md:285:**Gate first, build second.** Research showed no iPhone↔Android UWB interop, ...
docs/IN_RANGE_IPHONE_COMPLETION_PLAN.md-286-
docs/IN_RANGE_IPHONE_COMPLETION_PLAN.md-287-This is the path that can make iPhones feel "active" with UWB distance while ...
docs/IN_RANGE_IPHONE_COMPLETION_PLAN.md-288-
docs/IN_RANGE_IPHONE_COMPLETION_PLAN.md-371-
  +6 more in docs/IN_RANGE_IPHONE_COMPLETION_PLAN.md
docs/IOS_CARRIER_DECISION_2026-07-16.md-168-**iPhone ↔ iPhone** in the foreground.
docs/IOS_CARRIER_DECISION_2026-07-16.md-169-3. **Production (design first):** choose the filterable-discovery approach
docs/IOS_CARRIER_DECISION_2026-07-16.md-170-(GATT (a), or accept foreground-only), then validate background behavior on a
docs/IOS_CARRIER_DECISION_2026-07-16.md:171:walk before calling iOS a shipped carrier.
docs/IOS_CARRIER_DECISION_2026-07-16.md-172-4. **Unchanged:** #6 server + `BatchTokenSource` need no changes for any carr...
docs/IOS_CARRIER_DECISION_2026-07-16.md-173-`_currentCorrelationId` stays the raw 16 bytes of the server token; only the AD
docs/IOS_CARRIER_DECISION_2026-07-16.md-174-field changes. Security harness unaffected (SQL layer never sees the carrier).
docs/IOS_LOCATION_RESIDENCY_REVIEW_2026-07-24.md-102-3. calls `Permission.locationAlways.request()`; and
docs/IOS_LOCATION_RESIDENCY_REVIEW_2026-07-24.md-103-4. tells a denied user to grant “Allow all the time” in Settings.
docs/IOS_LOCATION_RESIDENCY_REVIEW_2026-07-24.md-104-
docs/IOS_LOCATION_RESIDENCY_REVIEW_2026-07-24.md:105:Therefore, “CLBeaconRegion is a heavier permission than what just shipped” is...
docs/IOS_LOCATION_RESIDENCY_REVIEW_2026-07-24.md-106-not accurate for the present repository. It is a heavier product commitment
docs/IOS_LOCATION_RESIDENCY_REVIEW_2026-07-24.md-107-and review justification, but not a new permission class.
docs/IOS_LOCATION_RESIDENCY_REVIEW_2026-07-24.md-108-
docs/IOS_PROXIMITY_RESEARCH_2026-07-24.md-361-- Unsupported device or iOS version: fall back to W5/fusion.
docs/IOS_PROXIMITY_RESEARCH_2026-07-24.md-362-- NI warm session: NI distance/direction is the preferred geometric input.
docs/IOS_PROXIMITY_RESEARCH_2026-07-24.md-363-- NI unavailable/suspended: degrade to connected RSSI, then advertisement/fus...
docs/IOS_PROXIMITY_RESEARCH_2026-07-24.md:364:- Peer token unavailable: NI cannot start. A token may arrive through BLE or ...
docs/IOS_PROXIMITY_RESEARCH_2026-07-24.md-365-- Live Activity dismissed/expired: surface degraded state in telemetry; do no...
docs/IOS_PROXIMITY_RESEARCH_2026-07-24.md-366-
docs/IOS_PROXIMITY_RESEARCH_2026-07-24.md-367-## W7 decision gate — Core Location screen-lit assist
docs/IOS_PROXIMITY_RESEARCH_2026-07-24.md-523-The device-install blocker is not resolved merely by creating the tag. The
docs/IOS_PROXIMITY_RESEARCH_2026-07-24.md-524-freeze document records:
docs/IOS_PROXIMITY_RESEARCH_2026-07-24.md-525-
docs/IOS_PROXIMITY_RESEARCH_2026-07-24.md:526:- the installed S9 builds predate build stamping and must be rebuilt;
docs/IOS_PROXIMITY_RESEARCH_2026-07-24.md:527:- the S22 and iPhone 15 Plus must be reinstalled from at least the current na...
docs/IOS_PROXIMITY_RESEARCH_2026-07-24.md-528-- `walk_capture.sh prep` intentionally rejects a mismatched client build.
docs/IOS_PROXIMITY_RESEARCH_2026-07-24.md-529-- IG-fleet S9 `3931395a4d583398` is protected by default and is not part of the
docs/IOS_PROXIMITY_RESEARCH_2026-07-24.md-530-In Range walk rig.
docs/IOS_SCREEN_OFF_FUSION_2026-07-24.md-290-
docs/IOS_SCREEN_OFF_FUSION_2026-07-24.md-291-It is **not a current production plan**:
docs/IOS_SCREEN_OFF_FUSION_2026-07-24.md-292-
docs/IOS_SCREEN_OFF_FUSION_2026-07-24.md:293:- on iOS 26 the DL-TDoA entitlement supports development and Ad Hoc builds on...
docs/IOS_SCREEN_OFF_FUSION_2026-07-24.md-294-- Apple says iOS 27 removes the entitlement requirement, but the current API/...
docs/IOS_SCREEN_OFF_FUSION_2026-07-24.md-295-- background behavior for this exact configuration must be tested rather than...
docs/IOS_SCREEN_OFF_FUSION_2026-07-24.md-296-
docs/IPHONE_BEACON_COMPLETION_HANDOFF.md-12-
docs/IPHONE_BEACON_COMPLETION_HANDOFF.md-13-> **2026-07-25 update (audit-criticals round, HEAD `e8ad7b9`):** A full audit...
docs/IPHONE_BEACON_COMPLETION_HANDOFF.md-14-
docs/IPHONE_BEACON_COMPLETION_HANDOFF.md:15:> **2026-07-25 update (compliance round 3, HEAD `f6bf21e`):** A four-agent re...
docs/IPHONE_BEACON_COMPLETION_HANDOFF.md-16-
docs/IPHONE_BEACON_COMPLETION_HANDOFF.md-17----
docs/IPHONE_BEACON_COMPLETION_HANDOFF.md-18-
docs/IPHONE_BEACON_COMPLETION_HANDOFF.md-33-5. **Server-coordinated burst scheduling** — when phone A wakes, the Edge Fun...
docs/IPHONE_BEACON_COMPLETION_HANDOFF.md-34-6. **BSSID salt rotation** — the venue-hint BSSID hash currently uses the sta...
docs/IPHONE_BEACON_COMPLETION_HANDOFF.md-35-7. **Region radius vs geohash cell** — the 2 km anchor radius does not cover ...
docs/IPHONE_BEACON_COMPLETION_HANDOFF.md:36:8. **INRANGE_LOCATION_RESIDENCY governance** — now `true` in the dev `.env` (...
docs/IPHONE_BEACON_COMPLETION_HANDOFF.md:37:9. **CI release lane with the intended test profile** — `ios-build.yml` compi...
docs/IPHONE_BEACON_COMPLETION_HANDOFF.md-38-10. **Durable ID-based outbox** — the drains are serialized (the overlap-ack ...
docs/IPHONE_BEACON_COMPLETION_HANDOFF.md-39-
docs/IPHONE_BEACON_COMPLETION_HANDOFF.md-40-### 16.3 Confirmed absent (keep absent — this is the compliance edge)
  +7 more in docs/IPHONE_BEACON_COMPLETION_HANDOFF.md
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-51-**Contamination rules — violations produce a false pass, which is worse
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-52-than no data:**
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-53-
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md:54:- Install the release build, then **detach the debugger** and launch from
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-55-the home screen. A debugger-attached process changes background-push
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-56-throttling (Apple, forums 745188), and silent pushes are capped at ~2-3
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-57-per hour regardless — this test measures production behavior or it
docs/MAC_SETUP.md-3-Goal: from a Mac powering on to the app running on a connected iPhone, with the
docs/MAC_SETUP.md-4-fewest steps. **The iOS project is already configured** — permission strings ...
docs/MAC_SETUP.md-5-BLE background modes are in `ios/Runner/Info.plist`, the `permission_handler`
docs/MAC_SETUP.md:6:macros are in `ios/Podfile`, the bundle id is `io.inrange.inRange`, and there is
docs/MAC_SETUP.md-7-**no Firebase** to wire. What the Mac needs is the toolchain, your signing
docs/MAC_SETUP.md-8-identity, and the gitignored `.env`. Do §0 and §1 tonight; §2–§4 take minutes...
docs/MAC_SETUP.md-9-
docs/MAC_SETUP.md-47-build gets a different `versionName` and both S9s plus the iPhone would no lo...
docs/MAC_SETUP.md-48-be on one freeze.
docs/MAC_SETUP.md-49-
docs/MAC_SETUP.md:50:Both S9s are already installed and verified at `0582633`, and the iOS build is
docs/MAC_SETUP.md-51-green at that exact commit on macos-latest. Building the iPhone from the same...
docs/MAC_SETUP.md-52-is what keeps the walk one freeze.
docs/MAC_SETUP.md-53-
docs/MAC_SETUP.md-93-2. `flutter devices` should now list the iPhone.
  +31 more in docs/MAC_SETUP.md
docs/MARKETING_PLAN.md-146-
docs/MARKETING_PLAN.md-147-### 4.2. App-Gated Launch Events (Tinder mechanic, Thursday economics)
docs/MARKETING_PLAN.md-148-
docs/MARKETING_PLAN.md:149:- Launch party at the anchor venue partner: **entry = app installed +
docs/MARKETING_PLAN.md-150-waitlist position shown at the door**. Thursday's Dubai template: one
docs/MARKETING_PLAN.md-151-~150-cap event, sell it out in advance (110+ tickets in 2 weeks), raise
docs/MARKETING_PLAN.md-152-capacity, then adjacent areas.
docs/MARKETING_PLAN.md-459-| **Subscription entitlements** | ❌ UNBLOCKED | tiers $9.99/$19.99+/annual + ...
docs/MARKETING_PLAN.md-460-| **Promoted Places (venue product)** | ❌ | venue account + placement flag + ...
docs/MARKETING_PLAN.md-461-| **In Range Nights (events)** | ❌ **NEW** | event entity + ticketing (web, S...
docs/MARKETING_PLAN.md:462:| **App-gated entry** | ❌ NEW | door-mode screen: show waitlist position / in...
docs/MARKETING_PLAN.md-463-| Boosts (IAP) | ❌ | consumable IAP + time-boxed visibility multiplier; abuse...
docs/MARKETING_PLAN.md-464-| Aggregate insights (B2B) | ❌ GUARDED | k-anonymous coarse buckets only per ...
docs/MARKETING_PLAN.md-465-| Invite group chat / share cards | ❌ | share-sheet flow + QR deep link; card...
docs/MARKETING_PRELAUNCH_2026-07-31_JOINT.md-135-both-phones-agree, 24h purge, public honesty-fix history). No corporate
docs/MARKETING_PRELAUNCH_2026-07-31_JOINT.md-136-voice, no unprovable superlatives, no fake urgency.
docs/MARKETING_PRELAUNCH_2026-07-31_JOINT.md-137-
docs/MARKETING_PRELAUNCH_2026-07-31_JOINT.md:138:## 6. Site changes shipped in this round
docs/MARKETING_PRELAUNCH_2026-07-31_JOINT.md-139-
docs/MARKETING_PRELAUNCH_2026-07-31_JOINT.md-140-All copy passed both parties' guardrail checks (§3 rules):
docs/MARKETING_PRELAUNCH_2026-07-31_JOINT.md-141-1. **Meta/OG/Twitter descriptions** → new angle + named geography ("Points for
docs/MARKETING_PRELAUNCH_2026-07-31_JOINT.md-184-- Claude's "Go outside. It literally pays." — **rejected by Kimi** (contradic...
docs/MARKETING_PRELAUNCH_2026-07-31_JOINT.md-185-Terms virtual-items clause + X6); replaced with "Go out. It counts."
docs/MARKETING_PRELAUNCH_2026-07-31_JOINT.md-186-- Claude's zero-migration zone hack (ride the `source` field) — **rejected by
docs/MARKETING_PRELAUNCH_2026-07-31_JOINT.md:187:Kimi**; proper migration 0062 shipped instead. (Claude verified Kimi's schema
docs/MARKETING_PRELAUNCH_2026-07-31_JOINT.md-188-claims against 0054/0055 + the edge fn before accepting.)
docs/MARKETING_PRELAUNCH_2026-07-31_JOINT.md-189-- Claude's "~80% college students quit apps" and "~90% prefer offline" —
docs/MARKETING_PRELAUNCH_2026-07-31_JOINT.md-190-**flagged unverifiable by Kimi**; tagged SOFT, kept off all public copy.
docs/POST_WALK_UPGRADE_QUEUE.md-1-# Post-walk upgrade queue — execute after the 2026-07-27 walk
docs/POST_WALK_UPGRADE_QUEUE.md-2-
docs/POST_WALK_UPGRADE_QUEUE.md:3:Every item below was deliberately **not** shipped before the walk, because ea...
docs/POST_WALK_UPGRADE_QUEUE.md-4-changes radio behaviour and the walk exists to measure the current behaviour....
docs/POST_WALK_UPGRADE_QUEUE.md-5-document says what to build, in what order, and — the important part — **whic...
docs/POST_WALK_UPGRADE_QUEUE.md-6-measurement decides it.** Several entries can be *deleted* rather than built,
docs/POST_WALK_UPGRADE_QUEUE.md-12-read its "Post-implementation corrections" section before acting on a finding
docs/POST_WALK_UPGRADE_QUEUE.md-13-there; it retracts several of its own claims.**
docs/POST_WALK_UPGRADE_QUEUE.md-14-
docs/POST_WALK_UPGRADE_QUEUE.md:15:## What already shipped (do not redo)
  +3 more in docs/POST_WALK_UPGRADE_QUEUE.md
+25 more files

exec
/bin/bash -lc "rtk rg --files docs/research/2026-08-01-hardening | sort
rtk rg -n -C 2 'cron\\.job|unverified, not cleared|PR post|pull request|HARDENING' docs/research/2026-08-01-hardening --glob '"'!transcripts/**'"'" in /home/hazypiff/in-range
 succeeded in 0ms:
docs/research/2026-08-01-hardening/CONSENSUS_DIALOGUE.md
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md
docs/research/2026-08-01-hardening/transcripts/codex_audit_prompt.md
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md
docs/research/2026-08-01-hardening/transcripts/codex_final.md
docs/research/2026-08-01-hardening/transcripts/consensus_prompt.md
docs/research/2026-08-01-hardening/transcripts/final_round.md
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md
docs/research/2026-08-01-hardening/transcripts/kimi_audit_prompt.md
docs/research/2026-08-01-hardening/transcripts/kimi_consensus_r1.md
docs/research/2026-08-01-hardening/transcripts/kimi_consensus_r2.md
docs/research/2026-08-01-hardening/transcripts/kimi_final.md
docs/research/2026-08-01-hardening/transcripts/kimi_round2.md
docs/research/2026-08-01-hardening/verified_findings_working.md
107 matches in 6 files:

docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-252-
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-253-- **Verified against production:** only the Edge Function auth probe. Everyth...
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:254:The highest-value manual check remains `SELECT jobname, schedule FROM cron.jo...
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-255-`cron.schedule` is wrapped in `DO $$ … EXCEPTION WHEN OTHERS THEN NULL`, so a...
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-256-and if that row is missing every retention claim here is "forever" rather tha...
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-258-frequency and behaviour; the deployed Edge Function *source*.
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-259-- **The local Supabase container is at 0019.** Privilege regressions in 0020–...
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:260:**unverified, not cleared** — a caveat that also applies to Kimi's DB-derived...
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-261-- **Depth of each auditor's check, self-reported:** Codex re-read the source ...
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-262-and summarized High finding including latest SQL definitions, and accepted ra...
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-15-reproduction commands for each item:
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-16-
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:17:- `docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md`
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-18-- `docs/research/2026-08-01-hardening/verified_findings_working.md`
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-19-
docs/.../transcripts/codex_consensus_r1.md-14-
docs/.../transcripts/codex_consensus_r1.md-15-The full report is at:
docs/.../transcripts/codex_consensus_r1.md:16:/home/hazypiff/in-range/docs/research/2026-08-01-hardening/HARDENING_AUDIT_20...
docs/.../transcripts/codex_consensus_r1.md-17-
docs/.../transcripts/codex_consensus_r1.md-18-The per-finding evidence, with the exact file:line and reproduction commands,...
docs/.../transcripts/codex_consensus_r1.md-1147-
docs/.../transcripts/codex_consensus_r1.md-1148-exec
docs/.../transcripts/codex_consensus_r1.md:1149:/bin/bash -lc 'wc -l /home/hazypiff/in-range/docs/research/2026-08-01-hardeni...
docs/.../transcripts/codex_consensus_r1.md-1150-rtk git status --short --branch' in /home/hazypiff/in-range
docs/.../transcripts/codex_consensus_r1.md-1151-succeeded in 0ms:
docs/.../transcripts/codex_consensus_r1.md:1152:234 /home/hazypiff/in-range/docs/research/2026-08-01-hardening/HARDENING_AUDI...
docs/.../transcripts/codex_consensus_r1.md-1153-639 /home/hazypiff/in-range/docs/research/2026-08-01-hardening/verified_findi...
docs/.../transcripts/codex_consensus_r1.md-1154-873 total
docs/.../transcripts/codex_consensus_r1.md-1158-
docs/.../transcripts/codex_consensus_r1.md-1159-exec
  +183 more in docs/.../transcripts/codex_consensus_r1.md
docs/.../transcripts/codex_final.md-13-Final round. You have each reviewed this audit independently. I am now puttin...
docs/.../transcripts/codex_final.md-14-
docs/.../transcripts/codex_final.md:15:Report: /home/hazypiff/in-range/docs/research/2026-08-01-hardening/HARDENING_...
docs/.../transcripts/codex_final.md-16-Evidence: /home/hazypiff/in-range/docs/research/2026-08-01-hardening/verified...
docs/.../transcripts/codex_final.md-17-Repo: /home/hazypiff/in-range · W5 worktree: /tmp/claude-1000/-home-hazypiff/...
docs/.../transcripts/consensus_prompt.md-2-
docs/.../transcripts/consensus_prompt.md-3-The full report is at:
docs/.../transcripts/consensus_prompt.md:4:/home/hazypiff/in-range/docs/research/2026-08-01-hardening/HARDENING_AUDIT_20...
docs/.../transcripts/consensus_prompt.md-5-
docs/.../transcripts/consensus_prompt.md-6-The per-finding evidence, with the exact file:line and reproduction commands,...
docs/.../transcripts/final_round.md-1-Final round. You have each reviewed this audit independently. I am now puttin...
docs/.../transcripts/final_round.md-2-
docs/.../transcripts/final_round.md:3:Report: /home/hazypiff/in-range/docs/research/2026-08-01-hardening/HARDENING_...
docs/.../transcripts/final_round.md-4-Evidence: /home/hazypiff/in-range/docs/research/2026-08-01-hardening/verified...
docs/.../transcripts/final_round.md-5-Repo: /home/hazypiff/in-range · W5 worktree: /tmp/claude-1000/-home-hazypiff/...

exec
/bin/bash -lc "rg -n '"'^##|''^'"\\*\\*Severity:' docs/research/2026-08-01-hardening/verified_findings_working.md" in /home/hazypiff/in-range
 succeeded in 0ms:
8:## H-ORCH-1 — Round-8 sign-off evidence is partially unreproducible; ~20 adversarial probes lost
10:**Severity:** High (process / regression-coverage, not a runtime defect)
51:## C-DIAG-1 — Diagnostic W5 link layer + plaintext RSSI log ship in production binaries, gated only by a persisted bool
53:**Severity:** Critical (privacy: plaintext proximity records written by a release build)
91:## H-DIAG-2 — `ReleaseIsolationTests` cannot fail; the #8 guard is not a guard
93:**Severity:** High (false assurance)
120:## H-DIAG-3 — Pre-Dart restoration trusts persisted operational state (issue #8 leg (c) unimplemented)
122:**Severity:** High
146:## 🔴 C-PROD-1 — LIVE: `photo-review` and `send-push` accept UNAUTHENTICATED requests in production
148:**Severity:** CRITICAL — remotely exploitable by anyone on the internet, right now.
198:## 🔴 C-SQL-1 — `claim_token` lets any authenticated user overwrite ANOTHER user's `token_claim_history` row
200:**Severity:** Critical (live today — the mitigating check is behind a flag that is OFF)
239:## 🔴 C-SQL-2 — `correlate_miles_encounters` fabricates encounters from arbitrary GPS, bypassing the entire 0029 reciprocity gate
241:**Severity:** Critical (live, not gated by any rollout flag)
274:## 🔴 C-SQL-3 — `beacon_token_batch` has NO scheduled purge: a permanent token→user_id map that de-anonymises 30 days of `rssi_samples`
276:**Severity:** Critical (privacy)
306:## 🔴 C-CONSENT-1 — The three newest telemetry write paths have NO consent check at all
308:**Severity:** Critical (compliance — withdrawal is not effective)
338:## 🔴 C-W5-1 — A committed encounter reached by `realId` bypasses the sticky-keeper branch; the keeper is silently displaced
340:**Severity:** Critical (reproduces the original #7 duplicate-keeper defect, no attacker required)
385:## 🔴 C-W5-2 — Peripheral restoration permanently nils the notify characteristics: the peripheral can never send another control message
387:**Severity:** Critical
412:## 🔴 C-W5-3 — A dial that connects but dies before HELLO_ACK leaks a `pendingDial` forever: the encounter can never commit and can never be erased
414:**Severity:** Critical
440:## 🔴 C-RT-1 — `_flushSightings` has no re-entrancy guard: one flush loop compounds per 45s on a slow network, and "turn beacon off" hangs for up to 83 minutes
442:**Severity:** Critical
467:## 🔴 C-SQL-4 (NEW, from Kimi) — batch-pre-claimed tokens skip the GPS veto entirely
469:**Severity:** Critical
495:## H-SQL-5 (NEW, from Kimi) — the two reciprocity directions are never bound to each other
510:## Additional Kimi items accepted (lower severity)
520:## METHODOLOGICAL CAVEAT on Kimi's pass — recorded because it affects how much weight its "clean" verdict carries
540:## Cross-check: Kimi vs the Edge-Function reviewer on `join_waitlist` — both are right
555:## H-W5-6 (NEW, from Codex; severity RAISED by coordinator Medium → High) — the 120s reconnect grace is normally unreachable, blocked by 5- and 15-minute discovery caches
597:## M-W5-7 (NEW, from Codex) — the "reactive cascade with no timer" claim has a timer-only liveness gap
614:## Codex independent CONFIRMATIONS of Claude-panel findings
625:## M-W5-8 (from Codex) — unbounded `lastConnectAttempt` and `pendingControl`
630:## Codex "checked and found correct" (useful negative evidence)

exec
/bin/bash -lc "date '+%H:%M:%S'
stat -c '%y %s %n' docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md docs/research/2026-08-01-hardening/verified_findings_working.md
rg -n 'CRITICAL — live today|H-W5-3"'` no lease|H-W5-4` `dropPeer|H-W5-5` the per-encounter|`C-RT-1`|five Criticals and|cron'"\\.job|unverified, not cleared' docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md" in /home/hazypiff/in-range
 succeeded in 0ms:
15:55:21
2026-08-01 15:49:58.732533428 -0400 20113 docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md
2026-08-01 15:50:54.036011051 -0400 15456 docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md
2026-08-01 14:48:06.222349164 -0400 37910 docs/research/2026-08-01-hardening/verified_findings_working.md
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:167:`H-W5-3` no lease persistence, and restoration actively re-handshakes restored links with fresh identity
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:168:that the peer correctly rejects (≥5-min blackout plus a wedged lease) · `H-W5-4` `dropPeer` never erases
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:170:the app can re-dial someone the user just rejected · `H-W5-5` the per-encounter candidate is keyed by peer
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:192:`C-RT-1` `_flushSightings` has no re-entrancy guard and `turnOffBeacon` awaits it, so the user can tap
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:204:what this round exists to establish, given all suites were green while five Criticals and the entire
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:54:## CRITICAL — live today
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:254:  The highest-value manual check remains `SELECT jobname, schedule FROM cron.job;` — `0015`'s
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:260:  **unverified, not cleared** — a caveat that also applies to Kimi's DB-derived "all clean" statement.

exec
/bin/bash -lc "rtk rg -n -C 4 '83890e6|30619a1|bff57fa|W5LinkController|release|installed|install|build' docs/W5* docs/research/2026-07-31/claude_kimi_chat_2026-07-31.md | head -n 600" in /home/hazypiff/in-range
 succeeded in 0ms:
21 matches in 1 files:

docs/.../2026-07-31/claude_kimi_chat_2026-07-31.md-20-
docs/.../2026-07-31/claude_kimi_chat_2026-07-31.md-21-### Link layer / W5
docs/.../2026-07-31/claude_kimi_chat_2026-07-31.md-22-- N1. **Divergent W5 iOS lines.** origin/main got `ec7856e` (persistent-link ...
docs/.../2026-07-31/claude_kimi_chat_2026-07-31.md-23-flag-gated, bench-proven single-pair) directly, while PR #9's branch holds the
docs/.../2026-07-31/claude_kimi_chat_2026-07-31.md:24:W5LinkController/W5Ownership/W5Codec stack (+2697/−44 vs main, BackgroundBeac...
docs/.../2026-07-31/claude_kimi_chat_2026-07-31.md-25-168 lines) and does NOT contain ec7856e. Two parallel W5 native implementatio...
docs/.../2026-07-31/claude_kimi_chat_2026-07-31.md-26-reconciled before either flag turns on. Merge-order risk compounds with PR #5...
docs/.../2026-07-31/claude_kimi_chat_2026-07-31.md-27-beacon stack).
docs/.../2026-07-31/claude_kimi_chat_2026-07-31.md-28-- N2. **PR #9 is gated on human review**: round-7 review of v5.2+, prevAlias ...
docs/.../2026-07-31/claude_kimi_chat_2026-07-31.md-64-for APNs silent-push wake (tier 4)" landed on main 2026-07-30/31; no soak/fie...
docs/.../2026-07-31/claude_kimi_chat_2026-07-31.md-65-wake tiers yet.
docs/.../2026-07-31/claude_kimi_chat_2026-07-31.md-66-
docs/.../2026-07-31/claude_kimi_chat_2026-07-31.md-67-### Verification infrastructure
docs/.../2026-07-31/claude_kimi_chat_2026-07-31.md:68:- N15. Your F1 (ios-build.yml not PR-triggered) and F2 (RunnerTests never in ...
docs/.../2026-07-31/claude_kimi_chat_2026-07-31.md-69-still open on main's workflows; native 30/30 still rests on the Mac sim run a...
  +158 more in docs/.../2026-07-31/claude_kimi_chat_2026-07-31.md

exec
/bin/bash -lc "rg --files docs | rg 'W5|PERSISTENT|DARK_PAIR|TEST' | sort" in /home/hazypiff/in-range
 succeeded in 0ms:
docs/DEVICE_TESTING_JOURNAL.md
docs/FEET_TEST_PLAN_2026-07-22.md
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md
docs/W5_PERSISTENT_LINK_RESULTS_2026-07-29.md

exec
/bin/bash -lc "rg -n -C 3 'release|install|build|commit|branch|W5LinkController|bb\\.w5links|diag' docs/W5_PERSISTENT_LINK_RESULTS_2026-07-29.md docs/DEVICE_TESTING_JOURNAL.md docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md | head -n 500" in /home/hazypiff/in-range
 succeeded in 0ms:
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-33-   `nonce`, not `wake`).
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-34-6. **Build box `.env`**: `INRANGE_SUBTLE_WAKE=true`,
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-35-   `INRANGE_LOCATION_RESIDENCY=true`, `INRANGE_CALIB_SCAN=false`.
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md:36:   `build-install-ios.sh --release` accepts this without the walk override
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-37-   (calib is off).
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-38-7. **Two accounts**, both fully discoverable (age + photo verified —
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-39-   `current_user_can_discover()` is a hard gate on every RPC in this path).
--
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-51-**Contamination rules — violations produce a false pass, which is worse
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-52-than no data:**
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-53-
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md:54:- Install the release build, then **detach the debugger** and launch from
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-55-  the home screen. A debugger-attached process changes background-push
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-56-  throttling (Apple, forums 745188), and silent pushes are capped at ~2-3
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-57-  per hour regardless — this test measures production behavior or it
--
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-93-
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-94-> Tiers live for this run: BLE (tier 0-1) ☐ · SLC/regions/CLVisit (tier 2-3)
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-95-> ☐ · silent push (tier 4 — cron armed AND verified per §0.3) ☐
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md:96:> `.env` flags on the build: SUBTLE_WAKE=__ RESIDENCY=__
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-97-
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-98-A run with tier 4 inert is still a genuinely useful measurement — it is the
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-99-floor without silent push — but the table must say that is what it was, or
--
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-118-re-separated between trials), reported as success rate plus median/worst
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-119-latency — never as the best trial.
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-120-
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md:121:The wake-log timestamps are what make "nothing happened" diagnosable:
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-122-
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-123-- **Zero wakes on both** → iOS granted no windows. The entitlement/cron
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-124-  chain is suspect before the BLE path is.
--
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-130-
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-131-## 3. Arms and controls
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-132-
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md:133:**Arms (each needs its own ≥3 trials — different builds, different
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-134-questions):**
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-135-
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-136-- **Arm R-on**: `INRANGE_LOCATION_RESIDENCY=true` on both phones. The
--
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-157-
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-158-- **Detection within ≤10 min of co-location, both directions, ≥3/3 trials
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-159-  of at least one arm** → the screen-off gap is closed for the
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md:160:  stationary-venue case. Ship the capability commit, move to the
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-161-  persistent-GATT bench (handoff §16.2 #3) for latency, and start drafting
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-162-  the honest number — success rate + median/worst, per arm — into the
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-163-  product copy.
--
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-172-- **Zero detections with zero wakes** → entitlement/capability problem,
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-173-  not BLE. Re-check §0.
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-174-- **Zero detections with wakes present** → BLE background carrier problem.
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md:175:  That is a real architecture finding: escalate before building anything
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-176-  else on top.
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-177-
docs/IPHONE_DARK_PAIR_TEST_2026-07-26.md-178-Report the table + wake logs back before any further native work. Every
--
docs/DEVICE_TESTING_JOURNAL.md-13-| Test device | iPhone 14 (iPhone14,7), iOS 26.5.2 | (fill in: Galaxy S9 lab device + others) |
docs/DEVICE_TESTING_JOURNAL.md-14-| Deploy | `flutter run` via USB; free-team signing (**re-deploy every 7 days**) | adb / `flutter run` |
docs/DEVICE_TESTING_JOURNAL.md-15-| Log capture | `flutter run` console; Xcode devices window | `adb logcat` (rtk-filtered, ~86% compressed) |
docs/DEVICE_TESTING_JOURNAL.md:16:| First deployed | 2026-07-15 (In Range 0.1.0, build 1) | (predates journal — walks #1–4) |
docs/DEVICE_TESTING_JOURNAL.md-17-
docs/DEVICE_TESTING_JOURNAL.md-18-## Known platform differences to test around (BLE proximity)
docs/DEVICE_TESTING_JOURNAL.md-19-
--
docs/DEVICE_TESTING_JOURNAL.md-34-4. **Permission UX**: iOS asks Bluetooth + location separately with our
docs/DEVICE_TESTING_JOURNAL.md-35-   Info.plist strings; Android 12+ needs BLUETOOTH_SCAN/ADVERTISE runtime
docs/DEVICE_TESTING_JOURNAL.md-36-   grants. Note any silent-denial states.
docs/DEVICE_TESTING_JOURNAL.md:37:5. **7-day build expiry (iOS free signing)**: a "dead app" on walk day may
docs/DEVICE_TESTING_JOURNAL.md-38-   just be an expired provisioning profile.
docs/DEVICE_TESTING_JOURNAL.md-39-
docs/DEVICE_TESTING_JOURNAL.md-40-## Entry template
--
docs/DEVICE_TESTING_JOURNAL.md-42-```
docs/DEVICE_TESTING_JOURNAL.md-43-### YYYY-MM-DD — <short title>
docs/DEVICE_TESTING_JOURNAL.md-44-- Platform(s): iOS / Android / cross
docs/DEVICE_TESTING_JOURNAL.md:45:- Devices: <model, OS version, app build>
docs/DEVICE_TESTING_JOURNAL.md-46-- Setup: <foreground/background, screen on/off, pocket/hand, distance protocol>
docs/DEVICE_TESTING_JOURNAL.md-47-- What we did:
docs/DEVICE_TESTING_JOURNAL.md-48-- Numbers: <RSSI ranges, detection latency, drop rate — or link to run_logs/>
--
docs/DEVICE_TESTING_JOURNAL.md-57-### 2026-07-15 — iOS rig online; first iPhone deployment
docs/DEVICE_TESTING_JOURNAL.md-58-- Platform(s): iOS
docs/DEVICE_TESTING_JOURNAL.md-59-- Devices: iPhone 14 (iOS 26.5.2), In Range 0.1.0+1 debug, free-team signed
docs/DEVICE_TESTING_JOURNAL.md:60:- Setup: first install via USB from the Mac; fallback config (`.env.example`,
docs/DEVICE_TESTING_JOURNAL.md-61-  no cloud) — local-only operation
docs/DEVICE_TESTING_JOURNAL.md-62-- What we did: stood up the full iOS toolchain (Tahoe upgrade → Xcode 26.5 →
docs/DEVICE_TESTING_JOURNAL.md:63:  CocoaPods 1.17) and deployed the first iOS build. Info.plist configured for
docs/DEVICE_TESTING_JOURNAL.md-64-  BLE central+peripheral, location always, background modes
docs/DEVICE_TESTING_JOURNAL.md-65-  (bluetooth-central, bluetooth-peripheral, location, processing).
docs/DEVICE_TESTING_JOURNAL.md-66-- Numbers: n/a (bring-up session, no proximity data)
--
docs/DEVICE_TESTING_JOURNAL.md-82-  The root cause itself is also recorded in `IOS_CARRIER_DECISION_2026-07-16.md`;
docs/DEVICE_TESTING_JOURNAL.md-83-  what follows is the evidence and the tooling lessons that existed only in the
docs/DEVICE_TESTING_JOURNAL.md-84-  audit doc.)*
docs/DEVICE_TESTING_JOURNAL.md:85:- On-screen diagnostic that cracked it:
docs/DEVICE_TESTING_JOURNAL.md-86-  `loc=granted locAlways=permanentlyDenied btScan=denied btAdv=denied btConn=denied bt=granted`
docs/DEVICE_TESTING_JOURNAL.md-87-- **Root cause:** `PermissionService.requestForegroundBle()` required
docs/DEVICE_TESTING_JOURNAL.md-88-  `bluetoothScan` + `bluetoothAdvertise` to be *granted*. Those are
docs/DEVICE_TESTING_JOURNAL.md-89-  **Android 12+ only** permissions; on iOS `permission_handler` returns them
docs/DEVICE_TESTING_JOURNAL.md-90-  permanently `denied`, so the gate could never pass on any iPhone — the beacon
docs/DEVICE_TESTING_JOURNAL.md:91:  was unreachable on iOS regardless of build or settings. The real iOS
docs/DEVICE_TESTING_JOURNAL.md-92-  permission (`bluetooth`) was granted the whole time. Fixed by
docs/DEVICE_TESTING_JOURNAL.md:93:  platform-branching the gate (iOS checks `Permission.bluetooth` only).
docs/DEVICE_TESTING_JOURNAL.md-94-- History: the iOS beacon had **never** been on. The previous day's blocker was
docs/DEVICE_TESTING_JOURNAL.md-95-  missing crypto secrets; after fixing that with the shared `.env`, this
docs/DEVICE_TESTING_JOURNAL.md-96-  surfaced. Android beacon worked throughout.
docs/DEVICE_TESTING_JOURNAL.md-97-- Diagnostic leverage: that failure message fires **only** on the
docs/DEVICE_TESTING_JOURNAL.md-98-  silent-denial path — config/crypto/sign-in failures throw `StateError` and
docs/DEVICE_TESTING_JOURNAL.md-99-  render a different message. That is what narrowed the search.
docs/DEVICE_TESTING_JOURNAL.md:100:- Verified NOT the cause: same failure on debug **and** release builds (so not
docs/DEVICE_TESTING_JOURNAL.md:101:  a build-mode artifact); Podfile `PERMISSION_*` macros verified present in
docs/DEVICE_TESTING_JOURNAL.md:102:  `Pods.xcodeproj` (12 build configs). Those macros were a genuine latent bug
docs/DEVICE_TESTING_JOURNAL.md-103-  in their own right (permission_handler compiles handlers out without them)
docs/DEVICE_TESTING_JOURNAL.md-104-  and were kept.
docs/DEVICE_TESTING_JOURNAL.md-105-- **Tooling lesson:** the `strings`-based binary gate used mid-debug is
--
docs/DEVICE_TESTING_JOURNAL.md-166-  stop-and-return with id baselines is the reliable method. (3) Keep both phones
docs/DEVICE_TESTING_JOURNAL.md-167-  same orientation/height every station (±20 dB otherwise). (4) rssi=127 = BLE
docs/DEVICE_TESTING_JOURNAL.md-168-  invalid sentinel, filter rssi<0.
docs/DEVICE_TESTING_JOURNAL.md:169:- **Beacon lag bug found + FIXED (commit pending):** the iPhone 14 beacon
docs/DEVICE_TESTING_JOURNAL.md-170-  intermittently needed 2–3 toggle presses / errored after many on/off cycles.
docs/DEVICE_TESTING_JOURNAL.md-171-  Root cause: the BLE-adapter-ready wait used adapterState.firstWhere (emits only
docs/DEVICE_TESTING_JOURNAL.md-172-  on CHANGE) — if BT flipped to `on` between the check and subscribe, the event
--
docs/DEVICE_TESTING_JOURNAL.md-255-  detection ceiling ≈175–200 ft (iPhone-observing side dies first at 200).
docs/DEVICE_TESTING_JOURNAL.md-256-- Field casualties fixed mid-walk (all pushed): un-timeouted RPCs hanging
docs/DEVICE_TESTING_JOURNAL.md-257-  beacon on/off on a half-dead network (issue_token_batch, claim_token,
docs/DEVICE_TESTING_JOURNAL.md:258:  release_token, record_sighting), and the FGS handshake holding the toggle
docs/DEVICE_TESTING_JOURNAL.md-259-  hostage with the radio already live. Every network await in the beacon
docs/DEVICE_TESTING_JOURNAL.md-260-  lifecycle is now bounded. Known cosmetic bug queued: stale red error text
docs/DEVICE_TESTING_JOURNAL.md-261-  persists after a successful delayed start; beacon start needs a visible
--
docs/W5_PERSISTENT_LINK_RESULTS_2026-07-29.md-5-changes until the flag is deliberately enabled.
docs/W5_PERSISTENT_LINK_RESULTS_2026-07-29.md-6-
docs/W5_PERSISTENT_LINK_RESULTS_2026-07-29.md-7-**Rig:** iPhone 14 (iPhone14,7, iOS 18.6.2) + iPhone 13 (iPhone14,5, iOS
docs/W5_PERSISTENT_LINK_RESULTS_2026-07-29.md:8:18.6.2). Paid team `JHK29L6A78`. Code at commit `ec7856e` (this doc's
docs/W5_PERSISTENT_LINK_RESULTS_2026-07-29.md:9:numbers corrected in the follow-up commit). Native events →
docs/W5_PERSISTENT_LINK_RESULTS_2026-07-29.md-10-`Documents/bb_wake_log.txt`; RSSI → `rssi_log(id,at_ms,correlation_id,
docs/W5_PERSISTENT_LINK_RESULTS_2026-07-29.md-11-rssi,power)`. RSSI is a **proximity proxy, not calibrated distance.**
docs/W5_PERSISTENT_LINK_RESULTS_2026-07-29.md-12-

exec
/bin/bash -lc 'rtk git diff --stat main...HEAD -- ios/Runner ios/Runner.xcodeproj/project.pbxproj
rtk git log -n 12 --oneline --decorate' in /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
 succeeded in 0ms:
ios/Runner.xcodeproj/project.pbxproj | 375 ++++++++++++++++++-
 ios/Runner/BackgroundBeacon.swift    | 171 +++++++--
 ios/Runner/W5Codec.swift             | 228 ++++++++++++
 ios/Runner/W5LinkController.swift    | 701 +++++++++++++++++++++++++++++++++++
 ios/Runner/W5Ownership.swift         | 565 ++++++++++++++++++++++++++++
 5 files changed, 1997 insertions(+), 43 deletions(-)
83890e6 (HEAD -> fix/w5-encounter-lease, hazypiff/fix/w5-encounter-lease) ci: run RunnerTests on a simulator + trigge...
ca924bd docs: joint tracking-system completion-readiness audit (Claude+Kimi, co-signed)
51c7842 docs: independent audit of dfb4b99 native integration (Kimi, Linux-side)
399b26e fix(w5): round-7 — stomp fixes, prevAlias resolution, W5Ended contract, ownership vectors (#7)
c1183db feat(ios): wire W5Ownership + CA6E codec into BackgroundBeacon; native W5 RSSI log (#7)
cf3d0df feat(w5): CA6E binary codec — Dart + Swift, pinned by shared conformance vectors (#7)
0332c5e feat(ios): #8 release isolation — diag build flavor, compile-time diag exclusion
bff57fa feat(ios): W5 ownership authority — Swift mirror of the v5.2 oracle + XCTest suite (#7)
3ee77e7 docs(W5): overnight durability soak results — 10h38m both-locked, 0 disconnects
860c2ed fix(w5): enforce viewGen saturation at every bump site + saturation/3-peer tests (#7)
5e55fbc fix(w5): v5.2 — peer-gen tracking, global bijection, cap, injective encoding (#7)
0527bdf fix(w5): v5.1 parity — typed 2-phase protocol + linkId↔handle bijection (#7)

exec
/bin/bash -lc "date '+%H:%M:%S'
stat -c '%y %s %n' docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md" in /home/hazypiff/in-range
 succeeded in 0ms:
15:56:14
2026-08-01 15:49:58.732533428 -0400 20113 docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md
2026-08-01 15:50:54.036011051 -0400 15456 docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md

codex
NOT RECONFIRMED — `INRANGE_W5_LINKS` only supplies the value Dart later writes to `bb.w5links`; all native W5/state-machine paths use that same persisted bool, so stale `true` reactivates both C-DIAG-1 and the H-W5 defects before Dart. Also: the report still says “CRITICAL — live today”; `W5LinkController.swift` exists only on unmerged PR #9, so “present in shipped artifacts” is unestablished; the cron caveat is not explicitly marked “unverified, not cleared”; the Mac order mislabels H-W5-4/6/7 as H-W5-3/4/5, omits actual H-W5-5, and retains `C-RT-1`; and `verified_findings_working.md` retains pre-downgrade labels, the refuted C-W5-1 mechanism, and obsolete H-ORCH-1 counts.
tokens used
148,153
NOT RECONFIRMED — `INRANGE_W5_LINKS` only supplies the value Dart later writes to `bb.w5links`; all native W5/state-machine paths use that same persisted bool, so stale `true` reactivates both C-DIAG-1 and the H-W5 defects before Dart. Also: the report still says “CRITICAL — live today”; `W5LinkController.swift` exists only on unmerged PR #9, so “present in shipped artifacts” is unestablished; the cron caveat is not explicitly marked “unverified, not cleared”; the Mac order mislabels H-W5-4/6/7 as H-W5-3/4/5, omits actual H-W5-5, and retains `C-RT-1`; and `verified_findings_working.md` retains pre-downgrade labels, the refuted C-W5-1 mechanism, and obsolete H-ORCH-1 counts.
