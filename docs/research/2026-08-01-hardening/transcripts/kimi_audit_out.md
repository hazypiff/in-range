• This is a large adversarial audit task. Review-only. I need to plan my approach. This is a big, multi-part investigation — good candidate for delegating to subagents, but the task is complex and requires tracing function redefinitions across migrations. Let me think about strategy.

  The repo is at /home/hazypiff/in-range, branch main. Worktree at /tmp/.../scratchpad/w5 for the W5 feature branch. The task focuses on supabase/migrations, docs/GAMIFICATION_SOCIAL_BLUEPRINT.

  Given the scale, I should probably do some key investigation myself (since findings need precision) and possibly delegate parallel chunks. But delegating adversarial review risks losing precision. The instructions say subagent result comes back as conclusion — good for keeping context small. However, the task demands a detailed findings report with file/line refs. Subagents can produce those.

  Plan: split into ~4 parallel explore/coder agents:

  1. Agent A: Encounter forgery chain — trace issue_token_batch (0031), 0060 preclaim, claim_token, record_sighting, correlate_encounter, 0029 reciprocal gate, 0053 late evidence, 0032 relay-abuse. Latest definitions only. Report findings.

  2. Agent B: Points economy design review — read blueprint doc sections 2-4, X1-X9, evaluate against schema.

  3. Agent C: Privilege/oracle surface — migrations 0056-0062 and all since 0029: SECURITY DEFINER, PUBLIC grants, REVOKE, RLS policies. Also can query local Postgres container read-only.

  Then I synthesize. But I should also verify key claims myself for the most critical findings... The instruction says don't redo subagent searches. I'll trust but spot-check.

  Actually, given the CRITICAL METHOD NOTE about cumulative migrations, each agent must find latest definitions. I'll emphasize that.

  Also check if the postgres container is running — agent C can do that.

  Should I use plan mode? No — this is a review/research task, output is a report. Not code changes. So just do it.

  Let me first do a quick orientation myself: list migrations, check the docs file exists, check container status. Then launch agents.

  Actually to keep my context lean, I'll launch the swarm quickly with precise prompts. But the guidance says "Do not delegate understanding. If the task hinges on a file path or line number, find it yourself first." I know paths: supabase/migrations/, docs/GAMIFICATION_SOCIAL_BLUEPRINT_2026-07-31_JOINT.md. Let me quickly list the migrations directory to give agents exact filenames.

  Let me do minimal recon: ls supabase/migrations, check docker container running.

• I'll start with quick recon of the migrations layout and the local DB, then split the audit into parallel focused investigations.

• RTK guard. Retry with the replacements.0023_gps_accuracy_aware_gate.sql  1.8K
0024_accuracy_aware_correlation.sql  12.7K
0025_encounter_recurrence.sql  13.5K
0026_sighting_idempotency_ratelimit.sql  6.0K
0027_durable_recurrence_pairs.sql  10.2K
0028_token_claim_history.sql  12.8K
0029_reciprocal_confirmation.sql  10.6K
0030_correlate_valid_from_grace.sql  5.2K
0031_server_issued_token_batches.sql  8.6K
0032_relay_abuse_detection.sql  5.7K
0033_relay_abuse_response_surface.sql  8.8K
0034_device_attestation_scaffold.sql  6.8K
0035_account_deletion_completeness.sql  13.1K
0036_data_export.sql  7.0K
0037_legal_hold.sql  10.2K
0038_ncii_takedown.sql  11.8K
0039_consent_records.sql  9.4K
0040_wire_consent_gates.sql  15.7K
0041_cybertipline_escalation.sql  8.7K
0042_privilege_hardening.sql  1.7K
0043_media_hash_ownership.sql  2.2K
0044_evidence_preservation.sql  19.6K
0045_withdrawal_effectiveness.sql  8.7K
0046_withdrawal_enforcement.sql  31.8K
0047_privilege_retention_consent.sql  14.9K
0048_gps_scope_and_retention.sql  20.2K
0049_schedule_maintenance_edge_worker.sql  3.1K
0050_ncii_per_ip_ratelimit.sql  3.0K
0051_harden_pg_net_and_ncii_rate.sql  1.8K
0052_photo_review_queue.sql  3.6K
0053_late_evidence_tolerance.sql  13.4K
0054_waitlist.sql  3.6K
0055_waitlist_referral.sql  4.4K
0056_calibration_rssi_samples.sql  23.9K
0057_subtle_wake_support.sql  6.3K
0058_subtle_wake_privacy.sql  19.5K
0059_proximity_wake_producer.sql  23.3K
0060_batch_token_preclaim.sql  8.9K
0061_close_wake_batch_privilege_hole.sql  6.6K
0062_waitlist_zone.sql  4.8K
supabase_db_in-range Up 2 hours (healthy) 0.0.0.0:54322->5432/tcp, [::]:54322->5432/tcp
DB is running. Now launch parallel subagents. Three angles:

  1. Encounter forgery chain (Agent A, explore → but needs deep analysis; use coder? Read-only task — explore is read-only and fits). Actually for a detailed audit report, explore agents are "fast codebase exploration" — might be too shallow? They have Read/Grep/Bash. The task is read-only analysis, so explore fits, but I want thoroughness. I'll specify "thorough".

  2. Points economy design review (needs the docs file + schema) — explore, thorough.

  3. Privilege/oracle surface across migrations + DB queries — explore with Bash (can run psql read-only). Thorough.

  I should give each agent strong briefs: repo path, threat model, the critical method note about latest definitions, output format (file:line, exploit steps, flag gating, root cause, fix, confidence), and instruction to refute their own findings.

  Also the mutual_ble proof statement — agent A should feed that, but I'll write the final synthesis.

  DB connection: supabase local default postgres://postgres:postgres@localhost:54322/postgres. READ-ONLY queries only.

  One concern: subagent 30-min timeout; these are big tasks but should be OK.

  Let me also consider whether the W5 worktree matters — the task says the worktree exists at /tmp/...; prior rounds were on PR #9. This round is broader on main. Agents should review main (the repo), maybe cross-check the worktree for W5-related changes. I'll mention it in agent A's brief since encounter lease relates.

  Launch 3 explore agents in one message with subagent_type=explore, thorough. These are differently-shaped tasks → separate Agent calls in one message.Three reports are in. Now I need to synthesize. Some findings conflict across agents and I should reconcile:

  - Agent 0 refuted "Direct correlate_encounter RPC to bypass gates: no GRANT to authenticated exists" — claimed internal-only. Agent 1 (H1) says correlate_encounter is PUBLIC-executable by default since no GRANT/REVOKE exists. Agent 2's inventory says correlate_encounter has grants {P, –, –} i.e., no authenticated, no PUBLIC — verified in DB ("Every SECURITY DEFINER function in public has explicit proacl with no PUBLIC grant"). Hmm — but if no GRANT/REVOKE statement exists in any migration, proacl would be NULL (default PUBLIC), not explicit. Agent 2 says verified in DB: correlate_encounter / correlate_miles_encounters → P only, no A, no S, and claims "explicit proacl with no PUBLIC grant". Where would the REVOKE come from? Possibly 0061's sweep block ("The sweep block ... exists and is sound") — 0061 apparently contains a sweep revoking PUBLIC from all SECURITY DEFINER functions. That would explain it: 0061 closed the hole for ALL functions, including correlate_encounter. Agent 1 missed that because it only grepped for GRANT/REVOKE naming correlate_encounter specifically. Agent 2 verified in live DB. Agent 0 also said "post-0061's privilege regime it is internal-only". So Agent 1's H1 is partially wrong on the PUBLIC-executable claim (refuted by DB verification), but the caller-optional veto point stands as a design concern for when minting lands — though if it's internal-only, record_sighting passes p_lat/p_lon... Actually record_sighting calls correlate internally with what args? Agent 0 F1 says the veto applies only when claim row has coords. The caller-supplied coords flow through record_sighting. So H1's "attacker calls directly" is refuted, but the underlying veto-optional issue merges into F1.

  I should verify this one point myself since two agents disagree: check 0061's sweep and confirm correlate_encounter's grants in DB. Quick psql check.

  Also Agent 0's F1 says the GPS veto is skipped when claim has NULL coords (batch preclaim path) — and Agent 1 C3 sybil farm says distance veto passes with identical coords. Consistent.

  Agent 2 M1 (claim_token squat/geo-poisoning) vs Agent 0's refuted "token squatting": Agent 0 refuted full squatting because 0060 pre-claims at fetch time — "a sniffer can only learn a token after it's already claimed". But Agent 2's M1 says: with enforce_batch_tokens OFF, if victim hasn't claimed yet (e.g., victim's client doesn't preclaim — Android path? or token issued but client fetches lazily), attacker can still claim first, full hijack; and even against preclaimed tokens, geo-poisoning works via COALESCE(EXCLUDED.approx_lat, existing). Agent 0's refutation assumed all clients preclaim; Agent 2 notes the attack shape changed but isn't dead. Both can be true: M1 is the more careful statement. The geo-poisoning part arming the 400m veto against the victim is a nice catch and consistent with Agent 0's F1 (NULL-coord claims skip veto — poisoning fills coords, enabling griefing).

  Let me verify two things quickly in the DB (which lags — the scratch DB was created by agent 2; it said it left audit_scratch in place). I can query audit_scratch to check correlate_encounter grants and the claim_token ON CONFLICT clause. Actually simpler: read 0061 file and 0060 lines 145-160 myself. These are pivotal claims for my report. Let me do targeted reads:

  1. Read 0061_close_wake_batch_privilege_hole.sql (6.6K, small) — verify sweep block.
  2. Read 0060 lines ~85-165 — verify claim_token ON CONFLICT clause.
  3. Read 0053 lines ~170-215 — verify veto/reciprocity claims.

  That covers the crux claims. Then write the final report.

  Also cleanup: agent left audit_scratch db and /tmp/dump.sql in container. Should I drop it? It's a scratch DB in a local container. Leaving it is fine but polite to clean. The agent offered the drop command. It's a destructive action on a scratch resource the agent created — acceptable. I'll drop it to leave things clean... Actually, risk: none meaningful; it's a scratch DB created by the audit. I'll drop it.

  Let me do the three reads in parallel.

• The three angles are back. Two agents disagree on one pivotal point — whether `correlate_encounter` is still PUBLIC-executable (agent 1 says yes by default, agents 0 and 2 say 0061's sweep closed it). I'll verify that and the other crux claims directly before writing the report.

• Verified:

  1. 0061's sweep revokes from PUBLIC/anon only for SECURITY DEFINER functions anon can execute — it revokes `FROM PUBLIC, anon`, not `authenticated`. So for correlate_encounter: was it ever granted to authenticated? Agent 2 verified in DB: correlate_encounter grants {postgres} only — no authenticated. Where did that come from? Probably 0042_privilege_hardening or another migration revoked it, or 0019... Agent 1 claimed "no GRANT/REVOKE on correlate_encounter exists in any migration (0042 revoked sibling functions but not this one)". But agent 2 verified in live replayed DB that authenticated has no EXECUTE. Hmm, conflict. Actually wait — agent 2's inventory lists `correlate_encounter / correlate_miles_encounters` with P only. Agent 2 replayed all migrations 0020-0062 and checked proacl explicitly. If no GRANT/REVOKE ever touched it, proacl would be NULL → PUBLIC executable → anon too. But agent 2 says every SECURITY DEFINER has explicit proacl with no PUBLIC grant. The 0061 sweep revokes FROM PUBLIC, anon for anything anon can execute — that would set proacl (a REVOKE materializes an ACL). So even if correlate_encounter was PUBLIC-executable before 0061, the 0061 sweep revoked PUBLIC and anon. But authenticated? If the original default grant was only PUBLIC (proacl NULL), then after REVOKE FROM PUBLIC, authenticated has nothing → P only. That matches agent 2's inventory. So agent 1's H1 "publicly executable" is WRONG post-0061 — refuted by both the file (0061 sweep) and DB verification. Good — I'll drop H1's exploit claim but keep the underlying caller-optional veto note, which is already covered by F1/C3.

  Wait — but is the sweep durable? It only revokes at migration time. correlate_encounter was last redefined in 0053, before 0061. CREATE OR REPLACE preserves existing ACLs. So post-0061, correlate_encounter has PUBLIC revoked. And security_regression.sql asserts no SECURITY DEFINER function is anon-executable. But authenticated? The sweep revokes PUBLIC and anon, so authenticated inherits nothing. Confirmed internal-only. Drop H1's public-execution claim.

  2. 0060 claim_token ON CONFLICT (token) DO UPDATE — no ownership check on the conflicting row. Confirmed: lines 149-159. When flag OFF, an attacker can claim any hex token. If victim hasn't claimed → full hijack (user_id = attacker). If victim preclaimed (NULL geo) → row keeps user_id=victim but attacker fills approx_lat/lon and overwrites valid_until. M1 CERTAIN. Note the interesting interaction: attacker planting far-away coords on victim's claim ARMS the 400m veto → griefing. Also note: claim_token requires p_lat/p_lon NOT NULL (line 117-118), so the attacker always supplies coords. Also rate limit 1 claim/5s.

  But wait — the full-hijack path: token_claim_history ON CONFLICT (token) DO UPDATE keeps user_id? The UPDATE doesn't set user_id, so existing row's user_id stays victim. Hijack only if victim never claimed. With 0060 preclaim at batch fetch, the victim's client pre-claims all slots when fetching the batch — so tokens are claimed before broadcast, for users whose client runs the new code. Agent 0's refutation assumed this. But claim_token's hijack window: attacker can only sniff a token after it's broadcast, which is after preclaim. Unless victim uses old client or Android path. Agent 2 said "If the victim has not yet claimed token T" — possible for non-updated clients. And record_sighting resolves via token_claim_history — with user_id=attacker... wait no, hijack requires INSERT to succeed, which only happens if no row exists. OK.

  Actually there's another subtlety: does the attacker's claim_token call even matter for record_sighting resolution? record_sighting looks up token_claim_history by token, user_id <> observer. If attacker squatted, user_id=attacker, so victim's sightings... anyway, M1 stands as flag-gated.

  3. 0053 veto confirmed: line 179 — veto only when both p_lat/p_lon AND v_claim coords non-null. p_lat/p_lon here are the record_sighting caller's coords passed into correlate_encounter. Reciprocity at 189-193 keyed on received_at within v_late. Confirmed F1/F3.

  One more check on F1's claim about record_sighting passing p_lat: in record_sighting, when it calls correlate_encounter, does it pass the caller's coords? Presumably yes. Fine.

  Also agent 2's note about the local DB lagging and creating audit_scratch. Cleanup: drop audit_scratch. Let me do that, then write the final report.

  Now synthesize the final report. Structure: most severe first across all three angles, dedup:

  CRITICAL:
  1. Relay forgery of mutual_ble end-to-end (F1) — NULL-coord batch claims disable the only spatial veto; two-way relay produces genuine reciprocal evidence. CERTAIN.
  2. Points ledger design broken (C1+C2) — UNIQUE(pair_key, day, kind) self-collides on two-sided mints, day column missing, NULL pair_key never dedupes. CERTAIN (design).
  3. Sybil-pair farming (C3) — mint gate inputs all attacker-controlled; X4 is the load-bearing fix. CERTAIN as mechanics against today's gate.

  HIGH:
  4. Relay-abuse telemetry blind (F2). CERTAIN.
  5. Decay reset via account recreate; X3 not implementable as described (H3). CERTAIN.
  6. claim_token cross-user upsert geo-poisoning / squat while enforce_batch_tokens=0 (M1 agent2). CERTAIN, flag-gated.
  7. Concurrency: daily cap race / ON CONFLICT aborts (H2).

  MEDIUM:
  8. Late-evidence window replay budget (F3) — 32–42 min replay life, no cross-direction binding. CERTAIN.
  9. X9 zero-mint retroactive problem (M1 agent1). LIKELY.
  10. X2 device fingerprint no data source (M2). CERTAIN.
  11. Day/timezone spec silence (M3). LIKELY.

  LOW:
  12. require_attestation=0 multiplies per-account limits (F4).
  13. rssi_batch_rate missing REVOKE (L1 agent2).
  14. Distinct-error oracles (L2 agent2).
  15. Session multiplier column (L1 agent1), abuse flags cascade delete (L2 agent1).

  Positives verified: prior bug classes closed (0061 sweep + regression test; consent functions service_role-only; RLS clean; correlate_encounter internal-only post-0061 — refuting agent 1 H1's direct-RPC claim).

  Refuted/dropped: agent1 H1 direct-RPC (0061 sweep closes PUBLIC; verified), token squatting full-hijack against updated clients, direct correlate bypass, self-pair, batch mining, timezone multiplication (as long as server-derived day).

  Then the mutual_ble statement and the late-window quantification.

  Cleanup scratch DB first.dropped
Now write the final report. Keep it organized, most severe first, with file:line, exploit steps, flag gating, root cause, fix, confidence. End with the mutual_ble statement.

• # Adversarial Audit — Protocol & Economy Round (main @ f2f948e)

  Scope: encounter-forgery chain end to end, the unbuilt points economy, and the privilege/oracle surface 0029–0062. Function bodies were checked at their **latest** definition (correlate_encounter / record_sighting → `0053`; claim_token → `0060`; scan_relay_abuse → `0033`; issue_token_batch → `0034`). Grants and RLS were verified by replaying 0020–0062 into a scratch DB and testing `has_function_privilege` as `anon`/`authenticated` (the designated local DB's migration tracking is drifted — records 0001–0019 but contains objects up to ~0057). Scratch DB dropped after use. The W5 worktree changes **no migrations** (iOS/Dart only), so everything below applies to it unchanged.

  ---

  ## CRITICAL

  ### C1 — Two-way relay forges `mutual_ble` encounters between arbitrary users at arbitrary distance; the only spatial veto is *absent* for batch-claimed tokens
  **Files:** `supabase/migrations/0053_late_evidence_tolerance.sql:179-182` (veto guarded by `v_claim.approx_lat IS NOT NULL`); `supabase/migrations/0060_batch_token_preclaim.sql:60-67` (`claim_token_batch` inserts all pre-claimed slots with NULL coords, deliberately — header lines 13-20 acknowledge this disarms the veto).

  **Exploit:** Attacker A plants confederate C near victim V.
  1. V's locked phone serves batch tokens; its claim rows are all NULL-coord (0060 is the locked-iPhone fix, so this is the *dominant* path for exactly the at-risk population).
  2. C sniffs V's token, relays to A → A calls `record_sighting(T_v, lat=anything, rssi=-50)`. The 400 m veto at 0053:179 is skipped (claim has no coords). Accepted from anywhere on Earth.
  3. A's token is relayed to C, re-broadcast beside V; V's **honest** phone buffers it and flushes a genuine sighting with real GPS on wake (the late-flush path 0053 was built to accept).
  4. A single-claims its token within 400 m of V. Reciprocity (0053:189-193) now holds → `encounters` row with `trust_level='mutual_ble'` (0053:208-209) plus a durable recurrence-pair bump (0053:202) — fake "we keep crossing paths" familiarity that reveal/recurrence ranking treats as the strongest evidence class below UWB.

  Even when the veto *does* execute, it compares attacker-supplied observer coords against attacker-supplied-or-absent claim coords, caller-clamped radius (`LEAST(400, GREATEST(5, p_radius_meters))`, 0053:181) — a self-consistent liar passes it.

  **Flags:** none. Live today with all three flags at 0. `enforce_batch_tokens=1` does not help (preclaim exists regardless); `require_attestation=1` only raises account cost.
  **Root cause:** the protocol's only spatial check is conditional on data the normal locked-phone path deliberately never writes. The 0053 header's claim that "the GPS veto still bounds space… a replayed token confirms nothing from far away" is false for batch-claimed tokens.
  **Fix:** (a) when the claim row is NULL-coord, fall back to an **observer-vs-observer** veto (forward and reverse sightings' observer fixes must agree within the accuracy-aware radius — a relay fails this without also controlling the victim's GPS); (b) have `claim_token_batch` stamp coarse location (geohash-3, ~150 km) instead of NULL — enough for a cross-city veto, no meaningful privacy regression; (c) keep `mutual_ble` out of every trust/safety decision until `secure_ranged` (UWB) ships.
  **Confidence:** CERTAIN.

  ### C2 — The blueprint's §3.3 ledger sketch is internally broken: two-sided mints violate its own UNIQUE; `day` isn't declared
  **File:** `docs/GAMIFICATION_SOCIAL_BLUEPRINT_2026-07-31_JOINT.md` §3.3 (L92-97). Schema facts: `0053:200-215` writes both users' state in one tx.
  **Failure (not even an attack):** an encounter mint awards both parties, but the sketched table is per-user while uniqueness is pair-scoped `UNIQUE(pair_key, day, kind)` — A's and B's rows for the same encounter share the key → the second INSERT raises 23505 and aborts the whole `correlate_encounter` transaction, rolling back the encounter itself. The constraint also references a `day` column absent from the column list — the DDL doesn't parse.
  **Fix:** `day DATE GENERATED ALWAYS AS ((created_at AT TIME ZONE 'UTC')::date) STORED`; `UNIQUE (user_id, pair_key, day, kind)`; enforce pair decay by reading both users' rows or a separate pair-keyed decay table.
  **Confidence:** CERTAIN.

  ### C3 — Pair-scoped uniqueness silently fails for every non-pair mint kind (NULL `pair_key` never dedupes)
  **File:** blueprint §3.1 L51 (daily bonus), L55 (presence quest — "no other human"), §3.3 L95.
  **Exploit:** (a) presence quest has no pair → `pair_key` NULL → Postgres UNIQUE treats NULLs as distinct → retriggering the quest mints repeatedly. (b) "first encounter of the day" is per-user/day semantics but keyed per-pair → 3 different pairs = 3 daily bonuses.
  **Fix:** per-kind uniqueness scopes: encounter kinds `UNIQUE (user_id, pair_key, day, kind)`; per-user/day kinds `UNIQUE NULLS NOT DISTINCT (user_id, day, kind)` (PG15+) or a sentinel pair_key; presence quests `UNIQUE (user_id, day, kind, venue_cell)`.
  **Confidence:** CERTAIN.

  ### C4 — Sybil-pair farming mints against today's encounter gate with no relay, no spoofing infra, no detector trips
  **Files:** `0053:62-139` (record_sighting), `0053:147-217` (correlate), `0032:54-111` (scanner).
  **Exploit (one human, two emulators, couch):** register two accounts (photo review is a human queue, AI a stub — `0052:1-13`); both `issue_token_batch`/`claim_token`; each calls `record_sighting` with the other's token, fabricated `rssi=-40` (accepted -127..20, 0053:87; floor only -75 for feet_10, 0053:176) and identical fabricated GPS (0053:88-89 validates ranges only). Reciprocity satisfied within the window; veto passes (identical coords). Scanner only flags >300 m/s or >2 km inconsistency — a static, self-consistent trail trips nothing; `beacon_abuse_flags` stays empty. Each *fresh* pair pays full value; pair decay doesn't bind because pairs are new; per-account ceilings (120 sightings/min, 3 batch days) don't limit mints.
  **Root cause:** every mint-gate input (RSSI, GPS, both sighting directions) is attacker-controlled when the attacker owns both ends. The gate proves "two clients uploaded consistent stories," not co-presence — and the sybil case needs no relay at all.
  **Fix:** the real countermeasures are X4 account-age mint gating (implement first — `profiles.created_at` exists, `0001:86`) and a per-account daily mint cap (needs a counter table, see H2). Accept and document that base-value sybil minting is bounded only by account-creation cost until attestation ships; consider gating mint *eligibility* (not just multipliers) behind attestation once flipped.
  **Confidence:** CERTAIN (mechanics traced line-by-line).

  ---

  ## HIGH

  ### H1 — Relay-abuse telemetry (0032/0033) is blind to the C1 attack shape; it catches only inconsistent liars
  **File:** `supabase/migrations/0033_relay_abuse_response_surface.sql:108-111, 158-162`, constants at `:90-91` (300 m/s, 2 km).
  `claim_teleport` requires claims with `approx_lat IS NOT NULL` — batch-claimed (NULL-coord) rows never appear; and with 15-min claim rotation, even 270 km of linear spoofed movement between rotations is unflagged. `relay_geo` joins only location-bearing owner claims against observer coords the relay attacker chooses to keep consistent. In C1, **neither endpoint generates a row** — `beacon_abuse_flags` stays empty. Both heuristics are consistency checks over attacker-supplied coordinates; they flag the sloppy relay and structurally cannot see a careful one. Note 0053's header leans on this surface ("already tracked (docs/RELAY_ABUSE_RUNBOOK.md)") — overstated post-0060.
  **Fix:** add geometry that doesn't need owner claims — flag a token observed from two observer fixes >2 km apart inside one slot window, and run the teleport check over each *observer's* sighting geometry (catches emulator farms moving one account between relay endpoints). Keep the no-auto-restrict policy; just make the signal exist.
  **Confidence:** CERTAIN.

  ### H2 — `claim_token` cross-user upsert: token squat / geo-poisoning while `enforce_batch_tokens` = 0
  **File:** `supabase/migrations/0060_batch_token_preclaim.sql:127-133` (flag-gated membership check), `:149-159` (`ON CONFLICT (token) DO UPDATE` with no ownership guard).
  **Exploit (authenticated, verified account, sniffed token — verified EXECUTE for `authenticated`):**
  ```sql
  SELECT public.claim_token('<32-hex sniffed>', now() + interval '20 minutes',
                            40.7128, -74.0060, 'feet_60', 10);  -- 1 per 5 s
  ```
  - If the victim has not claimed the token (old client, non-preclaim path): attacker **inserts** the row with `user_id = attacker` → `record_sighting` resolves the victim's beacon to the attacker's account → encounter theft/impersonation.
  - If the victim batch-pre-claimed (NULL geo, the normal case): the update keeps `user_id = victim` but fills `approx_lat/lon` via `COALESCE(EXCLUDED.approx_lat, existing)` and unconditionally overwrites `valid_until`. The attacker plants arbitrary coordinates on the victim's claim, **arming** the 400 m veto against the victim (griefing/DoS of that slot's encounters) or shrinking its resolvable window.
  **Flags:** fully closed by `enforce_batch_tokens = 1`; wide open today. Note 0060 *changed the attack shape* (hijack → geo-poisoning for updated clients) rather than removing it.
  **Fix:** flip the flag on client rollout (planned); independently, make the upsert no-op unless the existing row belongs to the caller: `ON CONFLICT (token) DO UPDATE SET ... WHERE public.token_claim_history.user_id = v_uid`.
  **Confidence:** CERTAIN.

  ### H3 — Decay reset via delete/recreate works; X3 cannot be implemented as described
  **Files:** blueprint §3.2 X3 (L71-72); `0035:41, 230` (30-day grace, then `DELETE FROM auth.users`); `0034:23, 26-34` (flag 0; `device_attestations` PK `(user_id, platform)`, no device-id column).
  **Exploit:** farm pair into decay → delete account A → post-purge re-register → new `user_id` → new `pair_key` → full new-pair mint with every prior partner. (Block/unblock and consent cycles do **not** reset decay — verified, refuted.)
  **Why the stated fix fails:** "decay keyed to attestation device id" needs (a) the verifier Edge Function — explicitly unbuilt (`0034:1-20`); (b) a stable device-id column — absent; (c) Play Integrity delivers **no stable device identity** on Android (verdicts, not IDs; App Attest key id is iOS-only); (d) device-keyed decay surviving account purge conflicts with the deletion-completeness architecture (0035) and needs a documented retention exception in the privacy inventory.
  **Fix:** re-scope X3: iOS-only device-keyed decay via a new `device_key_id TEXT` column + `pair_decay_by_device` table with an explicit retention exception; interim reliance on 30-day grace + X4 age gating. State plainly Android has no equivalent.
  **Confidence:** CERTAIN.

  ### H4 — Concurrency: UNIQUE alone converts races into tx aborts; the per-account daily cap races past the pair lock
  **Files:** blueprint §3.2 X8, §3.3 L98; `0053:201` (pair advisory lock), `0053:92-97` (existing atomic counter pattern).
  1. Same-pair concurrency serializes correctly on `pg_advisory_xact_lock` (0053:201) — but any mint path that checks-then-inserts without that lock double-passes under concurrency; the UNIQUE then aborts the *entire* correlate tx (encounter row rolled back, 500s, retry storms). Must be `INSERT ... ON CONFLICT (user_id, pair_key, day, kind) DO NOTHING RETURNING id`, treating NULL return as "already minted."
  2. X1's daily cap is per-**user**; the pair lock doesn't serialize one user's encounters with different partners → two concurrent encounters both pass the count check. Needs a per-user daily counter upserted atomically (pattern exists at 0053:92-97) or a second per-user lock, with lock ordering specified (user before pair) to avoid deadlock.
  **Confidence:** CERTAIN (mechanics).

  ---

  ## MEDIUM

  ### M1 — The late-evidence window is a store-and-forward replay budget with no co-presence binding between directions
  **File:** `0053:86` (accepts `p_observed_at` back to now−W), `:102-105` (token resolvable while `valid_until > now−W`), `:189-193` (reciprocity on `received_at > now−W` only), `:122-123` (every upsert refreshes `received_at = now`).
  A captured token's replay life is remaining validity (≤17 min typical, ≤21 min cap, 0060:114-116) **plus** W → **32 min at default W=15, 42 min at clamp W=25**. The reciprocity gate compares nothing *between* the two directions — both receipts must independently be within W of the correlate call — so a "mutual" encounter can be assembled from evidence genuinely **~30 min apart (default) / ~50 min apart (clamp max)**, per 15-min rotation slot, indefinitely. A forward sighting can be kept reciprocity-eligible by re-upserting (slides `received_at` forward) while awaiting the victim's late flush. (Checked and confirmed sound: `p_observed_at` cannot itself widen the reciprocity window — that keys on server `received_at`.)
  **Fix:** reject `p_observed_at` outside the token's `[valid_from, valid_until]` slot; require the reverse sighting's `received_at` within W of the *forward* sighting's `received_at` (not of `now()`); stop refreshing `received_at` on weaker-RSSI upserts.
  **Confidence:** CERTAIN.

  ### M2 — X9 "zero mint on dismiss" can't be a mint-time check; retroactive zeroing is unspecified
  **Files:** blueprint §3.2 X9; `0001:58-61` (pass/like), `0005:96-103` (blocks). Blocks half is free (`is_blocked_pair` already gates at 0053:171). But a `pass` post-dates the mint → zeroing must be retroactive: reversal rows in the append-only ledger, `points_totals` triggers handling negatives, and recompute of everything the mint fed (daily bonus, streaks, quests, leaderboards, multiplier splits). Unbudgeted in the sketch. Also note double-zeroing punishes the stalking *target* — deliberate per the doc, but should be a conscious product call.
  **Fix:** spec the strike RPC now (reversal convention, invalidation order, idempotency); join `encounter_actions` at credit time if payout is deferred — converts most of it into a filter.
  **Confidence:** LIKELY.

  ### M3 — X2's "shared device fingerprint" has no data source
  **Files:** blueprint §3.2 X2; `0056:34, 60-63` (`rssi_samples.device_id` is caller-supplied TEXT that *must rotate* on wipe, by design comment). No stable server-side fingerprint exists anywhere in the schema; GPS-trail correlation alone is weak (farmers jitter). The attestation-tier multiplier is inert until the unbuilt verifier ships and the flag flips.
  **Fix:** drop the fingerprint claim or add an explicit signal with a privacy-inventory line; lean on photo review + age gating + trust tiering meanwhile.
  **Confidence:** CERTAIN.

  ### M4 — "Day" is never specified in the blueprint
  **Files:** blueprint §3.1, §3.3 (silent); `0027:88-90`, `0034:99` (session-TZ-dependent `CURRENT_DATE` — Supabase defaults UTC, so fine today, but accidental). If any boundary is ever derived from a client-supplied/per-request timezone, emulated clients TZ-shop across midnight: double daily bonuses, streak shields across gaps.
  **Fix:** write into §3.3: all caps/decay windows use `(NOW() AT TIME ZONE 'UTC')::date` server-side; streaks use a per-account TZ captured once at first mint.
  **Confidence:** LIKELY (spec gap, not yet a bug).

  ---

  ## LOW

  - **L1 — `require_attestation=0` leaves every limit per-account** (`0034:91-97`, flag shipped 0; `0053:92-97` 120 sightings/min, `0060:46-52,135-137` claim limits). Volume abuse scales linearly with an emulator farm and stays under every per-account threshold in the 0033 response surface. This is exactly the control the flag was built for. CERTAIN.
  - **L2 — `rssi_batch_rate` (0056:101-107) created without the house-style `REVOKE`** — under a `supabase_admin`-role deploy it silently inherits `arwdDxtm` for anon/authenticated (verified via `pg_default_acl`); currently backstopped by RLS-with-zero-policies, but one future permissive policy away from a rate-limit-bypass (`DELETE`/`UPDATE` own bucket). Add `REVOKE ALL ON TABLE public.rssi_batch_rate FROM PUBLIC, anon, authenticated;`. CERTAIN (omission) / SPECULATIVE (prod impact, role-dependent).
  - **L3 — Distinct-error oracles**: `swipe_user` ("User unavailable" vs "No eligible encounter") and `can_view_profile_photos` leak discoverable/not-blocked/relationship state for arbitrary UUIDs. No enumeration path (UUIDs unguessable); consider collapsing the errors. CERTAIN they exist; LOW.
  - **L4 — Economy ledger omissions**: no `session_id` column for X7's per-session multiplier cap (add now, cheap; retrofit is painful) — blueprint §3.1 L56/§3.3 L93; `beacon_abuse_flags ... ON DELETE CASCADE` (`0032:22`) gives returnees a clean abuse history, compounding H3. CERTAIN.

  ---

  ## Refuted candidates (checked, dropped)

  - **`correlate_encounter` directly RPC-able to skip the veto** — false post-0061: the §3 sweep (0061:98-121) revokes PUBLIC/anon on every SECURITY DEFINER function anon can reach; verified in DB that `authenticated` has no EXECUTE. It is internal-only, and `supabase/tests/security_regression.sql` asserts the invariant. (The caller-optional veto it would have exposed is real but already covered by C1/C4.)
  - **Token squatting against updated clients** — 0060 pre-claims the whole batch at fetch time; a sniffer learns a token only after it's claimed. The residual flag-off shapes are H2.
  - **Self-pair minting** — excluded at 0053:103/165 plus `CHECK (user_a < user_b)` (0027:21). **UUID canonicalization asymmetry** — `LEAST/GREATEST` on uuid is a total order, consistent with the lock key at 0053:200-201.
  - **Timezone multiplication of daily mints** — clients never supply `day` anywhere today (retained only as spec-silence warning M4).
  - **Batch mining beyond intended issuance** — bounded to today+tomorrow, ≤3 live days, idempotent slots (0034:99-111).

  ## Prior bug classes — systematically re-checked, both CLEAN

  Every SECURITY DEFINER function in `public` (93 incl. overloads) has explicit ACLs with **no PUBLIC grant**; anon can execute none (only PostGIS's extension-owned `st_estimatedextent` — not app code). 0061's fix is fully closed and durable (sweep + enumerating regression test). `consent_withdrawn`/`has_consent`/`require_consent`/`has_legal_hold` are service_role-only; where `record_sighting` consults consent internally, errors are collapsed to the same `'Unknown or expired beacon token'` — the earlier leak shape does not recur. RLS is enabled on all 42 app tables; no `USING(true)` reachable by `authenticated`; all INSERT/UPDATE policies carry matching `WITH CHECK (... = auth.uid())`; RPC-only tables hold no anon/authenticated grants. Every app SECURITY DEFINER sets `search_path`. `join_waitlist`'s email→position oracle (0062) is service_role-only (0062:135-136, verified).

  ---

  ## What `mutual_ble` is and is not proof of (paste-ready)

  > `trust_level = 'mutual_ble'` asserts only this: within a sliding server-receipt window (default 15 min, clamped 2–25 min), *both* accounts uploaded at least one sighting report that resolved to the other's currently-claimed beacon token, the observer-reported RSSI cleared a floor, and — **only where the token owner happened to file a location-bearing claim** — the two reported GPS fixes agreed within ≤400 m. It is therefore proof that **two authenticated clients caused mutually consistent rows to exist in the `sightings` table**, nothing more. It is **not** proof that the two devices were ever within BLE range of each other: the BLE frame is an unsigned bearer token that any receiver can copy and re-broadcast, and a two-endpoint relay that forwards both tokens makes both *honest* phones generate exactly the rows the gate checks (0029's header says this explicitly — do not describe `mutual_ble` as relay-proof). It is **not** proof of co-presence in time: the two directions are bound only by independent sliding receipt windows, not to each other — evidence up to ~50 min apart can satisfy it at the max clamp. And it is **not** proof of location: every coordinate, RSSI, and capture timestamp in the evidence is caller-supplied, and for batch-pre-claimed (locked-phone) tokens the spatial veto does not execute at all. Relay resistance requires secure ranging (UWB, the planned `secure_ranged` level); until then, `mutual_ble` must not gate any trust- or safety-sensitive decision.

  **Bottom line for build order:** fix the ledger uniqueness design (C2/C3) before Phase A writes SQL; treat X4 account-age gating + the per-account daily mint cap as the load-bearing sybil countermeasures (not the pair-key machinery); and ship the observer-vs-observer veto fallback (C1) before `mutual_ble` feeds anything a user can rely on.

To resume this session: kimi -r session_7d89f4bc-8080-4bd9-aaf2-66369260923e
