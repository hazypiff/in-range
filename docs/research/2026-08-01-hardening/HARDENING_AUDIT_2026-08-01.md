# In Range — full-system hardening & bug-hunt audit, 2026-08-01

**Scope:** stability, security, correctness. No UI/UX work.
**Audit snapshot:** `main` @ `f2f948e`, `fix/w5-encounter-lease` @ `83890e6` (PR #9),
`feat/gamification-phase-a` (PR #10). **Current remediation baseline:** `main` @ `c5398e7`; PR #9 @
`810875a`. **Linux round-2 working tree:** `fix/hardening-linux-round-2` (uncommitted; not pushed).
**Panel:** 7 independent Claude reviewers + Kimi K3 + Codex (`gpt-5.6-sol`, max reasoning), separate
scopes, plus a live production probe. Three adversarial consensus rounds followed; the exchange is
recorded in `CONSENSUS_DIALOGUE.md`.

**Historical sign-off:** Codex — `CONSENSUS: AGREED`. Kimi — `AGREED WITH CORRECTIONS`, all folded in.
Those signatures cover the report committed at **`d1b8c38` only**. This file was substantively amended at
`c5398e7` after sign-off and is therefore **AMENDED — NOT RE-SIGNED** pending exact-text reconfirmation.

**Evidence convention (corrected after Codex's objection):** every **Critical** and every **disputed**
finding has a dedicated evidence section in `verified_findings_working.md` with reproduction commands.
The High/Medium tier is summarized here with file:line inline, not separately sectioned.

## 🔴🔴 SEVERITY CORRECTION — PRODUCTION IS AT 0055+0062, NOT 0063

**Verified after sign-off, and it lowers the live severity of all three SQL Criticals.**
`supabase migration list --linked` shows prod at **0001–0055 + 0062**; **0056–0061 are NOT applied.**
A `supabase db dump --linked` of the live schema confirms the consequences:

| Claim in this report | Production reality |
|---|---|
| C-SQL-1: `claim_token` overwrites another user's **coordinates** | Prod's conflict clause is `ON CONFLICT (token) DO UPDATE SET valid_until = EXCLUDED.valid_until;` — the 0048-era version. **The coordinate overwrite does not exist in prod.** Cross-user `valid_until` extension IS live (a token stays resolvable longer than its owner intended), but the GPS-veto-neutralisation harm is **not**. It arrives with 0060. |
| C-SQL-3: unpurged map de-anonymises 30 days of `rssi_samples` | `beacon_token_batch` is present and unpurged (**real**), but **`rssi_samples` is ABSENT from prod** (0056). The join target does not exist yet, so the proximity-graph harm arrives with 0056. |
| C-SQL-4: batch-pre-claimed tokens skip the GPS veto | The claim-coordinate-gated veto **is** live in prod, but the only writer of NULL-coordinate claim rows is `claim_token_batch` (0060, **absent**), and prod's `claim_token` raises on NULL coordinates. **No prod code path produces a veto-skipping row.** It arrives with 0060. |

**So the accurate statement is:** these three are **live in `main` and become live in production on the app
rollout** (when 0056–0061 ship). They are not currently exploitable against production users. C-PROD-1
remains the only finding that was genuinely live in production, and it is now fixed.

**Why this correction exists:** this report warned the panel that migrations are cumulative and that prod
must be verified rather than inferred — and then rated three findings from migration files without
checking the deployed ledger. Third time this project has hit that trap; first time it was this report
doing it.

## ⛔ DEPLOYMENT BLOCKER — THE 0056→0064 BATCH MUST STAY ORDERED

`0063` modifies `cleanup_ephemeral_data` using **0059's body**, which references `rssi_samples`,
`venue_anchors` and `proximity_wake_requests`. Verified: prod's current `cleanup_ephemeral_data` has
**zero** references to those tables and **none of them exist in prod**. Pushing 0063 by itself would
install a function referencing non-existent tables and **break `run_maintenance` in production** — the job
that performs every retention purge. `0063` ships **only** as part of the ordered 0056→0064 batch.
`0064_token_claim_ownership_repair.sql` is an append-only follow-up that closes the foreign batch-token
squat which remained in the final `0063`; it also must not be deployed independently. (The 0063
deployment hazard was caught by Kimi during migration review.)

---

**REMEDIATION STATUS (updated after sign-off):**
- **C-PROD-1 — FIXED AND VERIFIED IN PRODUCTION.** `send-push` and `photo-review` redeployed with the auth
  gate; `config.toml` corrected (`verify_jwt=false` on both, plus the missing `[functions.proximity-wake]`
  block). Re-probed: unauthenticated `POST` → `401`, `GET` → `405`, wrong bearer → `401`. Hole closed.
- **C-SQL-1 / C-SQL-3 / C-SQL-4 — PATCHED LOCALLY BY THE ORDERED `0063` + `0064` SET, NOT DEPLOYED, and
  MUST NOT be deployed piecemeal (see DEPLOYMENT BLOCKER above).** `0064` closes the squat-first
  residual in `0063`: authoritative `beacon_token_batch` ownership is checked even while the rollout
  flag is off, and only the proven owner can repair poisoned `token_claims` and
  `token_claim_history` rows. If the foreign rows are under legal hold, repair instead fails before any
  write and preserves both rows; a released hold permits the next owner claim to repair them. The squat
  rejection arm was observed red on `0063`; owner recovery, poisoned-row repair, hold preservation and
  post-release repair all pass on `0064` (the latter pre-fix failures are statically traced, not separately
  observed red). `run_security_tests.sh` replays 0020→0064 in order through raw `psql`, then passes the
  privilege/RLS suite and its existing encounter advisory-lock race; that race does **not** exercise
  0064's `FOR KEY SHARE`. A standard local migration run now records ledger head `0064`.
  **Review status:** Kimi and Codex reviewed only a 313-line draft of `0063` and returned
  `SAFE WITH CHANGES`; neither approved its committed 380-line final bytes. Kimi K3 and Claude Opus each
  returned `SAFE WITH EXACT CHANGES` on the first 0064 working-tree packet, then withdrew two incorrect
  objections during adversarial exchange (legacy compatibility and cross-account token caching). Their
  legal-hold disagreement produced the conservative fail-before-write behavior now in the file. This
  changed the bytes, so exact-final-packet re-review is still required. No consensus or deployment
  approval may be claimed until both reviewers see that final packet.
- **H-RT-5 / H-RT-7 — PATCHED LOCALLY, NOT PUSHED.** Batch tokens are filtered through one canonical
  32-lowercase-hex decoder before they reach BLE, and encounter queries now rebuild on active-user
  changes and return no data while signed out. Seven new Dart regressions bring this working tree to
  190/190 with `flutter analyze` clean.
- The High tier remains open except H-CFG-1's deployment/config defect (closed with C-PROD-1) and
  H-ORCH-1's missing-probe defect (remediated on PR #9 at `810875a`).

**Historical baseline:** `flutter analyze` clean; `flutter test` 183/183 on `main`, 233/233 on the
pre-reconstruction W5 branch. Those suites were green while every finding below existed. The current
Linux round-2 working tree is 190/190 after adding regressions for H-RT-5 and H-RT-7.

---

## CURRENT VERDICT — amended after production verification

**Not ready to trust in the wild or ship the pending migration batch.** The original audit found four
server-side Criticals on the release path. Post-sign-off verification changed their current status:

- **C-PROD-1 was the only finding live in production; it is fixed and re-probed.**
- **C-SQL-1, C-SQL-3 and C-SQL-4 exist on `main`'s pending app-rollout path, not in the deployed schema.**
  The local `0063` + `0064` set attempts to fix them and the newly proven squat residual, but is
  undeployed, must ship only as the ordered 0056→0064 batch, and lacks exact-final-diff panel approval.
- No known Critical from this report remains live in production, based on the post-sign-off migration
  ledger/schema verification. The `cron.job` schedule and production privilege sweep remain unverified,
  so this is not a blanket production clearance.

Plus a large High tier that blocks the W5 merge and the Phase-5 hardware matrix.

**Severity convention, settled by the panel:** *Critical* means reachable **now, on `main`**. Everything
that exists only on the unmerged `fix/w5-encounter-lease` branch is **High / merge-blocking**, however
severe, because it cannot harm a user until PR #9 lands. This was Codex's argument; Claude adopted it and
Kimi accepted. It changes no priorities — those items remain first in the Mac queue.

**Correction of record (Codex, re-confirmation round).** An earlier draft rated the diagnostic-layer
finding (formerly C-DIAG-1, now **H-DIAG-1**) as Critical on the grounds that it was "present in shipped
artifacts." That was wrong and is withdrawn: `ios/Runner/W5LinkController.swift` — which contains
`recordRssi` and the `Documents/w5_rssi_log.jsonl` writer — **does not exist on `main`**
(`git ls-tree main --name-only ios/Runner/` returns no W5 files). No release binary writes that log today.
It becomes true the moment PR #9 merges, so it is a merge blocker.

**A related nuance Codex raised, which does survive on `main`.** `INRANGE_W5_LINKS` is only the value Dart
later writes to the persisted `bb.w5links` boolean; the native code reads the *persisted bool*, not the
build flag. On `main` that bool already gates live native paths (`BackgroundBeacon.swift:88, 92, 880,
1034, 1103`). So "the feature is default-off" is a weaker guarantee than it sounds: a stale `true`
inherited from a prior diagnostic install re-activates those native paths **before Dart can clear it**.
That is issue #8's mechanism, and it applies to shipped code today even though the RSSI-log writer does
not. Tracked as **H-DIAG-4**.

**The structural finding:** the worst defects share one cause — *invariants enforced by hand-applied
convention with nothing proving coverage.* Consent checks, retention purges, and service-role auth are
each applied per-call-site by a human remembering. Three tests (§Systemic) would have caught **two
Criticals and one High** at authoring time — C-SQL-3, C-PROD-1 (three weeks ago), and H-CONSENT-1.

---

## ORIGINAL CRITICAL FINDINGS — current status above overrides historical wording

### C-PROD-1 🔴 `photo-review` and `send-push` accept unauthenticated requests in production
**Current status: FIXED AND RE-PROBED after sign-off.** The paragraphs below preserve the original
finding and evidence.
Deploy drift; the repo code is correct. Probed: `POST /photo-review` no auth → `200`; wrong bearer →
`200`; **`GET` no auth → `200`**. `requireServiceRole` rejects non-POST with 405 *before* anything else,
so a 200 on GET proves the deployed binary lacks the check. `POST /send-push` no auth → `200`,
`{"processed":19}`. Control: `maintenance` → `401`.

The gate landed in `45ef624` (2026-07-12) for all four functions; only `maintenance` (v5) and
`miles-correlate` (v6) were redeployed (`SAFETY_RUNBOOK.md:31-32`). ~3 weeks of pre-hardening code live.
`photo-review` reports `auto_approve: true` on the production host, and photo verification gates
discoverability (0052) — a moderation step adjacent to child-safety obligations.

**Fix now:** `supabase functions deploy send-push photo-review`; set `verify_jwt=false` for both; add the
missing `[functions.proximity-wake]` block (it currently 404s).

### C-SQL-1 🔴 `claim_token` overwrites another user's `token_claim_history` row
**Current status: present in migration 0060 on `main`, absent from the deployed schema; patched in the
local undeployed 0063+0064 set and awaiting exact-final-diff review.**
`0060:149-159` — `ON CONFLICT (token) DO UPDATE` with **no `WHERE user_id = v_uid`**. The `COALESCE`
"guard" is dead code: `0060:117-118` rejects NULL coordinates, so `EXCLUDED.approx_lat` always wins.
Tokens are broadcast in plaintext over BLE. Neutralises the GPS veto — `correlate_encounter`
(`0053:179-182`) compares against coordinates the attacker just wrote. The batch-membership check that
would stop it sits behind `enforce_batch_tokens`, which is **0**.

### C-SQL-3 🔴 `beacon_token_batch` has no scheduled purge — a permanent token→user_id map
**Current status: the unpurged table exists in production, but its `rssi_samples` join target does not;
the full harm arrives with 0056. Patched in undeployed 0063; ordered-batch review remains open.**
`cleanup_ephemeral_data()` (latest `0059:477-580`) purges 9 tables; not this one. Joining it to
`rssi_samples` on the shared token yields a de-anonymised proximity graph. **Nuance accepted from Kimi:**
active users' rows rotate out at next batch issue (~1–2 day window); it is **lapsed** users whose token
set persists indefinitely. Two-line fix:
`DELETE FROM public.beacon_token_batch WHERE valid_until < NOW() - INTERVAL '24 hours';`

### C-SQL-4 🔴 Batch-pre-claimed tokens skip the GPS veto entirely *(found by Kimi)*
**Current status: reachable on `main` through undeployed 0060, not through the deployed schema; attempted
fix in undeployed 0063; ordered-batch review remains open.**
`0053:179-182` wraps the veto in `IF ... v_claim.approx_lat IS NOT NULL ...`. `claim_token_batch`
(`0060:25`) pre-claims with NULL location — the locked-phone path. For those tokens the veto never runs.
Independent of C-SQL-1; fixing one does not close the other.
**Fix:** treat a location-less claim as veto-*failing*, or compare the two sightings' `observer_lat/lon`
to each other (always present).

---

## HIGH

**Merge-blocking for W5 (Mac side):**
- **H-W5-1** A committed encounter reached by `realId` bypasses the sticky-keeper branch. Dart
  `w5_ownership.dart:321` vs `:351`; Swift `W5Ownership.swift:250` vs `:279`. *Mechanism corrected by
  Kimi:* `realId` **finds** the encounter and processes it via the uncommitted path — the intruder link is
  added with no winner comparison and no close, and `maybeCommit` no-ops on an already-committed
  encounter. Executed outcome (keeper silently moves, no `owns`/`close` emitted) and fix (hoist `realId`
  above the committed check) unchanged. Reproduces #7 with no attacker: `HELLO_ACK` has no `prevAlias`
  field, so a rotated peer alias is unresolvable on the outbound path.
- **H-W5-2** Peripheral restoration never re-binds `controlNotifyChar`/`keepaliveNotifyChar`
  (`BackgroundBeacon.swift:736-751`), so the peripheral can never send another control message while
  still appearing healthy. *Independently confirmed by Codex, same lines.*
- **H-W5-3** A dial that connects but dies before HELLO_ACK leaks a `pendingDial` forever
  (`W5LinkController.swift:240-254` → `W5Ownership.swift:390`): the encounter can never commit, never be
  re-dialled, and never be erased.
- **H-W5-4** No lease persistence; restoration re-handshakes restored links with *fresh* identity, which
  the peer correctly rejects. Codex added the stale-generation sequence: A retains B's accepted
  `peerViewGen`, B relaunches from zero, the encounter id does not change so `rekey` never fires, and
  convergence stays stuck.
- **H-W5-5** The 120s reconnect grace is normally unreachable — `tokenCacheTTL` 900s and
  `connectRetryFloor` 300s (`BackgroundBeacon.swift:81-82`) gate the dial before the lease authority is
  consulted (`:1002-1012`). *Found by Codex, rated Medium; raised to High here* because the grace is why
  the lease exists and "rotation-during-grace" is the Phase-5 priority case — **fix this before the
  hardware matrix, or it will measure a path the app does not take.**
- **H-W5-6** `dropPeer` never erases the lease and does not disconnect an inbound keeper;
  `onTeardown` has **no production caller** — the app can re-dial someone the user rejected.
- **H-W5-7** The per-encounter candidate is keyed by peer alias, so rotation mints a new one; R7 fix #1 is
  *narrowly alive* (Kimi's correction — it still covers an evicted-`aliasTo`-but-live-`candidateByAlias`
  rediscovery), not dead code.
- **H-DIAG-1** *(was C-DIAG-1; demoted during re-confirmation)* The diagnostic W5 link layer is not
  behind the compile-time flag. The whole iOS tree has three `#if INRANGE_DIAG` sites, all in
  `BackgroundBeacon.swift`; `W5LinkController.swift` has zero. Its gate is the persisted bool
  `bb.w5links` (universal guard at `BackgroundBeacon.swift:1118`), and `recordRssi` (`:633-650`) writes
  plaintext `{"token","rssi","ts"}` to `Documents/w5_rssi_log.jsonl`. Issue #8 says a persisted flag must
  not be what stands between a release binary and diagnostic behaviour — that is the finding.
  **Not live:** `W5LinkController.swift` does not exist on `main`, so no shipped binary writes that log
  today; it lands with PR #9. **Fix:** `#if INRANGE_DIAG`-wrap `w5LinksEnabled` (`#else false`), wrap the
  `recordRssi` file branch, and exclude the file from the production target until W5 ships.
- **H-DIAG-4** *(new, Codex)* On `main`, `INRANGE_W5_LINKS` is only the value Dart later writes to the
  persisted `bb.w5links`; native code reads the **persisted bool**, not the build flag
  (`BackgroundBeacon.swift:88, 92, 880, 1034, 1103`). A stale `true` inherited from a prior diagnostic
  install therefore re-activates those native W5 paths **before Dart attaches and can clear it**. This is
  issue #8's mechanism operating on shipped code, and it means "the feature is default-off" is a weaker
  guarantee than it reads. The flavor/schema stamp in H-DIAG-3 is the same fix.
- **H-DIAG-2** `ReleaseIsolationTests` asserts compile-time constants and CI runs Debug only
  (`ios-build.yml:52`). *Softened per Kimi:* one test is a genuine runtime check. *Worsened per Kimi:* on
  `main` there is **no RunnerTests job in CI at all**.
- **H-DIAG-3** Pre-Dart restoration trusts persisted state incl. a bearer token in `sendWakePing`.
  Deliberate by design (`AppDelegate.swift:13`, `BackgroundBeacon.swift:153`) — fix is a flavor/schema
  stamp with legacy-state invalidation, **not** waiting for Dart. *Both auditors confirmed this framing.*
- **H-ORCH-1** Round-8 sign-off evidence is unreproducible. The transcript
  (`docs/research/2026-07-31/claude_kimi_chat_2026-07-31.md:386`) records
  `/tmp/kimi-r8/…/w5_ownership_r8_kimi_test.dart`, **26 tests**, "259/259" against a committed 233. So
  **26 adversarial probes were cited as sign-off evidence and zero were committed.**
  *Correction of record:* an earlier draft claimed 6 survived in `zz_probe_test.dart`. Codex showed no
  such file exists at HEAD or in `git log --all` — it was a temporary artifact created by one of this
  audit's own subagents and mistaken for committed code. **Standing rule: no review round may cite an
  uncommitted test file as sign-off evidence.**
  **Remediation:** PR #9 commit `810875a` reconstructs nine recorded probe classes as committed tests;
  this closes the missing-regression artifact, not the historical overclaim.

**Server / web (Linux side):**
- **H-CFG-1** `verify_jwt` is **true in config but not yet effective** on the deployed builds (the probe
  proves the gateway is not enforcing). On redeploy it *would* take effect and lock out the legitimate
  `sb_secret_` caller. `proximity-wake` has no config entry at all.
  **Remediation:** closed after sign-off in `c5398e7`; all three config entries were corrected and the two
  exposed functions redeployed/re-probed.
- **H-WL-1 / H-WL-2** `waitlist-join` performs an **unauthenticated cross-user UPDATE** and returns
  another person's `ref_code`, zone and position (`0062:100-104`, `:120-131`); and it is an **email
  enumeration oracle** — `0054:74-76` shipped `RETURNS VOID` with a comment promising exactly that
  property, which 0055/0062 silently dropped while leaving the comment in place. The RPC *is* revoked
  from `anon`/`authenticated` (Kimi), but the public Edge Function calls it as service-role, so the
  revoke is not a mitigation.
- **H-SQL-2** *(was C-SQL-2, downgraded)* The Locals path inserts `encounters` with NULL `trust_level`
  and no reciprocity (`0048:337-346`), and `get_locals_feed` unlocks on any active row past the reveal
  delay with no trust-level discrimination (`0048:443-451`).
  **Correction of record:** the earlier premise ("granted to `authenticated`, never revoked; returns raw
  `other_user_id`") was **false**. `0019:2496-2527` revokes `correlate_miles_encounters` from
  `PUBLIC, anon, authenticated, service_role` and the re-grant list omits it (DB confirms
  `{postgres=X/postgres}`); the entry point is `record_location_ping` at `0040:156`, which enforces
  `current_user_can_discover()` and `require_consent(…,'precise_location')` and returns `bigint`. The
  original grep (`00[2-6]*`) excluded 0019 — an asserted verification that was never performed.
- **H-SQL-3** The reciprocity gate binds each direction to `now()`, never to the other, so a "mutual"
  encounter can be assembled from evidence ~30–50 min apart. **Fix corrected by Codex:** comparing reverse
  `received_at` to *forward* `received_at` is a **no-op**, because `record_sighting` upserts the forward
  row with `received_at = v_now` (`0053:119`, `:123`) immediately before calling `correlate_encounter`
  (`:138`). The real fix is to compare the two `observed_at` **capture** times and bind observations to
  the token's validity interval. *Two of Kimi's original fix items survive the refutation and should ship
  with it:* reject `p_observed_at` outside the token's `[valid_from, valid_until]` slot, and stop
  refreshing `received_at` on weaker-RSSI upserts (`0053:123` refreshes unconditionally, which keeps a
  forward sighting reciprocity-eligible indefinitely by re-upsert).
- **H-CONSENT-1** *(downgraded from Critical)* `require_consent` appears **zero times** in 0056 and 0059;
  `venue_anchors` has no RPC at all. Bounded today (0056 documents the gap as deliberate pre-rollout,
  `INRANGE_CALIB_SCAN` defaults false, 0059 is undeployed) — but withdrawal effectiveness must be
  server-side against a stale or modified client.
- **H-PW-1** `enqueue_proximity_wake` accepts any geohash with no proof the caller is there, and
  `findLikelyPeers` performs no blocks/discoverability/consent check. Not live (0059 undeployed).
- **H-RT-1** *(was C-RT-1, downgraded per Codex — a local availability failure, not a security-boundary
  compromise)* `_flushSightings` has no re-entrancy guard (`beacon_service.dart:417-422`); one pass over
  500 records at a 10s timeout is ~83 min and the 45s timer starts 111 more. **Codex's fix is better than
  the original:** a timeout does not cancel the underlying flush — `_stopBle()` must happen *before*
  network draining (`:603`), with a generation check and bounded batches.
- **H-RT-2** RH-1 unfixed on all three counts, and the FGS heartbeat runs in a separate engine so the
  notification clock ticks over a dead scanner.
- **H-RT-3** Buffered sightings reach the classifier with fresh timestamps. The drain *does* preserve
  capture time (`beacon_service.dart:340-343`), but `_ingestForeignSample` discards it at the estimator
  boundary — `range_estimator.dart:75/79` has no timestamp parameter and stamps `_now()` — and sets
  `_lastForeignScanAt = DateTime.now()` (`:2220`). False "Close By", and a dead scanner looks healthy for
  another watchdog cycle. *Kimi refuted this in round 1 and withdrew the refutation in round 2.*
- **H-RT-4** `turnOffBeacon` is the only lifecycle path with no session-generation guard across 6 awaits.
- **H-RT-5** `_hexTo16Bytes` throws on non-32-char hex and `_rotateToken`'s catch then silently disables
  the beacon. *Kimi's sibling:* it also **silently truncates longer hex** — a quieter corruption mode.
- **H-RT-6** The consent gate is a one-shot prefs flag; withdrawal never re-gates; `preciseLocation`
  withdrawal does not stop the beacon's GPS; WiFi scanning is bound to no purpose at all.
- **H-RT-7** `myEncountersProvider` is not user-scoped and is absent from `_clearUserRuntime` — user A's
  encounters render for user B after an account switch.
- **H-RT-8** Backgrounded-iPhone discovery is broken by Apple multi-AD blob offsets on Android 15/16; the
  remedy exists in `apple_overflow_bit.dart` + `AdvertParser.kt` and **is never called from Dart**.
- **H-RT-9** `LocalDb.open()` is unguarded in `main()` before `runApp`, with no `onDowngrade`.
- **H-PRIV-2** Release-reachable PII in logs; the `piiSafe` helper a prior audit called for was never built.

## MEDIUM / LOW (selected)

**M-SQL-1** `scan_relay_abuse` attributes `relay_geo` to the **victim** (`0033:146`) — *demoted from High
per Codex:* the runbook forbids punitive action (`RELAY_ABUSE_RUNBOOK.md:22`) and the attacker needs the
victim's rotating token. Becomes Critical only if a mint consumer ignores the corroboration rule.
**M-SQL-2** *(Kimi)* `scan_relay_abuse`'s `claim_teleport` CTE joins only location-bearing claims, so the
NULL-coord batch-claim path — the dominant locked-phone shape — is **invisible to relay telemetry.**
**M-PRIV-1** *(both auditors, independently)* `SubtleWakeCoordinator` buffer: cap 50, place-level SLC/
`CLVisit` coordinates, count-cap only with no age bound. *Corrected:* it **is** cleared via the Dart
drain+ack path, which is flag-blind (`subtle_wake_service.dart:306-346` checks only platform); what
persists un-aged is only what accumulated while no engine existed.
**M-W5-1** The "reactive cascade with no timer" claim has a timer-only liveness gap — the next write is
scheduled by `asyncAfter`, which cannot run while suspended. The 10h38m soak may have survived because
the phones kept being woken. Re-read the soak evidence before treating durability as proven.
Plus: unsalted SHA-256 of client IP as a primary key; `venue_anchors` geohash precision uncontrained with
14/30-day retention; `bb_wake_log.txt` uncapped with a **trapping** `FileHandle.write`; Dart↔Swift effect
*ordering* divergence unpinned by any vector; `rssi_batch_rate` created without the house-style REVOKE;
`points_ledger` needs `session_id` before the ledger is append-only in production.

---

## WHAT THE VECTORS DO NOT PIN

`w5_ownership_vectors.json` contains **four** vectors. The round-8 record refers to "vectors 5+6 pinning
the per-alias candidate mint" — **re-check what actually landed in `30619a1`.** The shared runners cannot
express six oracle entry points (`onBeaconOff`, `onDialFailed`, `onAliasRoll`, `onPrevAliasExpiry`,
`onRetryTimer`, `debugSetViewGen`); `graceExpiry` is wired but unused; `sendPropose`/`sendAck` are matched
as **wildcards**, so v5.2 correction #5 has zero coverage.

## SYSTEMIC — three tests that would have caught two Criticals and one High

1. pgTAP: every RPC inserting into a user-scoped table calls `require_consent` → catches H-CONSENT-1.
2. A retention test that fails when a table is added without a `cleanup_ephemeral_data` entry → catches
   C-SQL-3 and the `venue_anchors`/`proximity_wake_requests` overruns.
3. A deploy-parity probe asserting `405` on `GET` for every service-role function → catches C-PROD-1, and
   would have caught it three weeks ago.

## CURRENT FIX ORDER

1. **Re-review the exact final `0063` + local `0064` repair and expanded T9.** Generic `22023` is the
   recorded choice; the held-squat path now preserves both rows and fails before any write. Do not deploy
   either migration alone; any production action is the ordered 0056→0064 batch with owner approval.
2. **H-WL-1 / H-WL-2** — the remaining live anonymous endpoint exposure; its status/recovery response
   needs an authenticated receipt or a deliberately generic public response.
3. **H-W5-1** (two-line hoist + the vector that pins it), then **H-W5-5** *before* the Phase-5 matrix.
4. **H-W5-2, H-W5-3, H-RT-1** — the wedges. H-RT-5 and H-RT-7 are patched locally with regressions.
   Then **H-DIAG-1 / H-DIAG-4** (compile-out + flavor stamp).
5. Systemic tests, then the rest of the High tier. C-PROD-1 and H-CFG-1 are closed; H-ORCH-1 is
   remediated on PR #9.

## COVERAGE AND LIMITATIONS

- **Verified against production:** the Edge Function auth re-probe plus the migration ledger/live-schema
  dump used by the severity correction. Application behaviour, `cron.job`, and the privilege sweep are
  not thereby cleared.
- **⚠️ UNVERIFIED, NOT CLEARED — the `cron.job` retention schedule.** Every retention claim in this report
  assumes `run_maintenance` is actually scheduled. `0015`'s `cron.schedule` is wrapped in
  `DO $$ … EXCEPTION WHEN OTHERS THEN NULL`, so a failed schedule fails **silently**. Nobody on this panel
  could query production. If that row is missing, every "24h" in this document is in fact "forever."
  Required manual check: `SELECT jobname, schedule FROM cron.job;`. **Do not treat this as cleared.**
- **Not verified:** anything requiring Xcode (no Mac) — all Swift findings are static reads; hardware
  frequency and behaviour; the deployed Edge Function *source*.
- **⚠️ NARROWED BUT NOT CLEARED — privilege regressions across migrations 0020–0062.** At sign-off the
  local container was at **0019**, making every DB-derived statement about later migrations unsupported.
  It has since been advanced to **0063** and swept: **0** anon-executable SECURITY DEFINER functions,
  **0** `USING(true)` policies reachable by `authenticated`, and RLS enabled on every application table
  (sole exception: PostGIS's own `spatial_ref_sys`, not app data). That verifies **the migration chain**.
  It does **not** verify **production**, and C-PROD-1 is direct proof that this project's prod state can
  diverge from its repo for weeks without anyone noticing. **Still not cleared** — it needs the same
  sweep run against prod.
- **Depth of each auditor's check, self-reported:** Codex re-read the source mechanism for every Critical
  and summarized High finding including latest SQL definitions, and accepted rather than reproduced the
  production HTTP observations, flag values, cron state and Flutter totals; it did not re-audit
  Medium/Low item by item. Kimi personally re-read the grant/revoke lines it disputed and marked its
  other checks as delegate-verified.
