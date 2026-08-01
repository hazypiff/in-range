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
