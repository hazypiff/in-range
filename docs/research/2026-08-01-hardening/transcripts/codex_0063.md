OpenAI Codex v0.146.0
--------
workdir: /home/hazypiff/in-range
model: gpt-5.6-sol
provider: openai
approval: never
sandbox: read-only
reasoning effort: max
reasoning summaries: none
session id: 019fbf14-d5e3-7843-99a0-e921b3e3d334
--------
user
Review a migration I just wrote, before it goes anywhere near production. Be adversarial — this fixes three Criticals from the audit you co-signed, and a bad fix here is worse than the bug.

File: /home/hazypiff/in-range/supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql
Audit: /home/hazypiff/in-range/docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md

It changes three functions, each extracted verbatim from its latest definition and modified only at marked sites:

1. **C-SQL-1** — `claim_token`: added `WHERE public.token_claim_history.user_id = v_uid` to the `ON CONFLICT (token) DO UPDATE`, and replaced the dead `COALESCE(EXCLUDED.x, existing.x)` guards with plain assignments, and made `valid_until` a `GREATEST(existing, excluded)` so a claim can never SHORTEN an existing window.

2. **C-SQL-3** — `cleanup_ephemeral_data`: added `DELETE FROM public.beacon_token_batch WHERE valid_until < NOW() - INTERVAL '24 hours';`

3. **C-SQL-4** — `correlate_encounter`: the GPS veto only ran when the claim row carried coordinates. Added `v_veto_ran` tracking; the reciprocity SELECT now also fetches the reverse sighting's `observer_lat/observer_lon`; and when the claim-based veto did not run, it falls back to comparing the caller's coordinates against the reverse observer's coordinates, failing CLOSED (RETURN) if either is missing.

Questions I specifically want answered:

a) **Does the C-SQL-4 fallback break the locked-phone path it is meant to protect?** That path exists precisely because a locked phone pre-claims tokens with NULL location. If `sightings.observer_lat/observer_lon` are ever NULL, or if the reverse sighting legitimately comes from a device with no fix, my fail-closed branch silently kills real encounters. Check the NOT NULL constraints and the real write paths before answering.

b) **Is `GREATEST(existing.valid_until, EXCLUDED.valid_until)` right, or does it introduce a new problem?** It stops a claim shortening a window, but it also means a token's resolvable life can only ever grow. Is that exploitable by the token's own owner?

c) **Does the `WHERE` on `DO UPDATE` silently swallow a case that should error instead?** A foreign-owned conflict now becomes a no-op, so the attacker gets a success response. Should it RAISE instead, and does raising leak an oracle ("this token belongs to someone else")?

d) Anything in the three bodies that I altered accidentally — i.e. any diff against the originals beyond the marked sites. The originals are in 0060 (claim_token), 0053 (correlate_encounter), 0059 (cleanup_ephemeral_data).

e) Ordering/transactional concerns: it is all one BEGIN/COMMIT. Any risk on a live database?

Rehearsal already done: migrations 0020..0063 apply cleanly in sequence on a local database that has the full Supabase scaffolding, and all three changes verify present via pg_get_functiondef. The local database is now at 0063.

Reply with: VERDICT (SAFE TO DEPLOY / SAFE WITH CHANGES / DO NOT DEPLOY), then your specific concerns with file:line.

codex
I’ll audit this against the exact prior function bodies and trace the schema/write paths that determine whether the GPS fallback is actually safe. I’ll also inspect privilege/error semantics, replay behavior, and live-DDL locking; I’ll treat the successful rehearsal as syntax coverage, not correctness evidence.
exec
/bin/bash -lc "sed -n '1,240p' /home/hazypiff/.codex/RTK.md && if [ -d graphify-out ]; then graphify query \"Where are claim_token, correlate_encounter, cleanup_ephemeral_data, sightings observer_lat observer_lon, and beacon_token_batch defined or written?\"; fi" in /home/hazypiff/in-range
 succeeded in 199ms:
Traversal: BFS depth=2 | Start: ['public.cleanup_ephemeral_data()', '10. Metrics & kill criteria (defined before building)', 'public.beacon_token_batch', 'public.claim_token()', 'public.correlate_encounter()', 'allSightings'] | 75 nodes found

NODE local_db.dart [src=lib/core/db/local_db.dart loc=None community=121]
NODE 0001_init.sql [src=supabase/migrations/0001_init.sql loc=None community=68]
NODE In Range — Gamification & Social Layer Blueprint (JOINT) [src=docs/GAMIFICATION_SOCIAL_BLUEPRINT_2026-07-31_JOINT.md loc=L1 community=31]
NODE static const String [src=None loc=None community=176]
NODE public.encounters [src=supabase/migrations/0001_init.sql loc=L166 community=68]
NODE 3. Point economy ("Sparks" — working name) [src=docs/GAMIFICATION_SOCIAL_BLUEPRINT_2026-07-31_JOINT.md loc=L43 community=31]
NODE 0048_gps_scope_and_retention.sql [src=supabase/migrations/0048_gps_scope_and_retention.sql loc=None community=161]
NODE 6. Media layer — Moments, Live, Feed (the social-media aspect) [src=docs/GAMIFICATION_SOCIAL_BLUEPRINT_2026-07-31_JOINT.md loc=L133 community=31]
NODE public.matches [src=supabase/migrations/0001_init.sql loc=L204 community=68]
NODE public.token_claim_history [src=supabase/migrations/0028_token_claim_history.sql loc=L14 community=125]
NODE 0031_server_issued_token_batches.sql [src=supabase/migrations/0031_server_issued_token_batches.sql loc=None community=142]
NODE package:uuid/uuid.dart [src=None loc=None community=22]
NODE public.get_my_encounters() [src=supabase/migrations/0001_init.sql loc=L442 community=68]
NODE 0028_token_claim_history.sql [src=supabase/migrations/0028_token_claim_history.sql loc=None community=125]
NODE public.correlate_encounter() [src=supabase/migrations/0001_init.sql loc=L336 community=68]
NODE public.encounter_actions [src=supabase/migrations/0001_init.sql loc=L189 community=68]
NODE public.token_claims [src=supabase/migrations/0001_init.sql loc=L108 community=68]
NODE public.record_sighting() [src=supabase/migrations/0028_token_claim_history.sql loc=L108 community=125]
NODE public.claim_token() [src=supabase/migrations/0028_token_claim_history.sql loc=L40 community=125]
NODE public.handle_updated_at() [src=supabase/migrations/0001_init.sql loc=L91 community=68]
NODE public.beacon_token_batch [src=supabase/migrations/0031_server_issued_token_batches.sql loc=L27 community=142]
NODE package:path/path.dart [src=None loc=None community=121]
NODE profiles_updated_at [src=supabase/migrations/0001_init.sql loc=L99 community=68]
NODE LocalDb [src=lib/core/db/local_db.dart loc=None community=121]
NODE public.messages [src=supabase/migrations/0001_init.sql loc=L218 community=68]
NODE public.issue_token_batch() [src=supabase/migrations/0031_server_issued_token_batches.sql loc=L44 community=142]
NODE GAMIFICATION_SOCIAL_BLUEPRINT_2026-07-31_JOINT.md [src=docs/GAMIFICATION_SOCIAL_BLUEPRINT_2026-07-31_JOINT.md loc=L1 community=31]
NODE samplesAfter [src=lib/core/db/local_db.dart loc=None community=121]
NODE 9. UX/UI surface spec (the Mac's frontend work order) [src=docs/GAMIFICATION_SOCIAL_BLUEPRINT_2026-07-31_JOINT.md loc=L232 community=31]
NODE static const Uuid [src=None loc=None community=121]
NODE setAlias [src=lib/core/db/local_db.dart loc=None community=121]
NODE public.record_sighting() [src=supabase/migrations/0048_gps_scope_and_retention.sql loc=L98 community=161]
NODE _onUpgrade [src=lib/core/db/local_db.dart loc=None community=121]
NODE public.correlate_miles_encounters() [src=supabase/migrations/0048_gps_scope_and_retention.sql loc=L251 community=161]
NODE Database [src=None loc=None community=121]
NODE clearAliases [src=lib/core/db/local_db.dart loc=None community=121]
NODE logRssiSample [src=lib/core/db/local_db.dart loc=None community=121]
NODE _meta [src=lib/core/db/local_db.dart loc=None community=121]
NODE _kUploadCursor [src=lib/core/db/local_db.dart loc=None community=121]
NODE setUploadCursor [src=lib/core/db/local_db.dart loc=None community=121]
NODE 4. Progression & status [src=docs/GAMIFICATION_SOCIAL_BLUEPRINT_2026-07-31_JOINT.md loc=L107 community=31]
NODE package:sqflite/sqflite.dart [src=None loc=None community=121]
NODE allSightings [src=lib/core/db/local_db.dart loc=None community=121]
NODE public.sightings [src=supabase/migrations/0001_init.sql loc=L134 community=68]
NODE deviceId [src=lib/core/db/local_db.dart loc=None community=121]
NODE 5. Quests & Range Nights (density manufacturing) [src=docs/GAMIFICATION_SOCIAL_BLUEPRINT_2026-07-31_JOINT.md loc=L119 community=31]
NODE clearRssiLog [src=lib/core/db/local_db.dart loc=None community=121]
NODE 2. Rule 1 — the economy's constitution [src=docs/GAMIFICATION_SOCIAL_BLUEPRINT_2026-07-31_JOINT.md loc=L29 community=31]
NODE 11. Decision log [src=docs/GAMIFICATION_SOCIAL_BLUEPRINT_2026-07-31_JOINT.md loc=L269 community=31]
NODE deleteSighting [src=lib/core/db/local_db.dart loc=None community=121]
NODE uploadCursor [src=lib/core/db/local_db.dart loc=None community=121]
NODE _createMeta [src=lib/core/db/local_db.dart loc=None community=121]
NODE _createRssiLog [src=lib/core/db/local_db.dart loc=None community=121]
NODE public.claim_token() [src=supabase/migrations/0031_server_issued_token_batches.sql loc=L102 community=142]
NODE 1. Why we can win where Niantic struggled [src=docs/GAMIFICATION_SOCIAL_BLUEPRINT_2026-07-31_JOINT.md loc=L13 community=31]
NODE _kDeviceId [src=lib/core/db/local_db.dart loc=None community=121]
NODE public.claim_token() [src=supabase/migrations/0048_gps_scope_and_retention.sql loc=L30 community=161]
NODE 8. Phasing (revised after review) [src=docs/GAMIFICATION_SOCIAL_BLUEPRINT_2026-07-31_JOINT.md loc=L219 community=31]
NODE wipeAll [src=lib/core/db/local_db.dart loc=None community=121]
NODE allRssiSamples [src=lib/core/db/local_db.dart loc=None community=121]
NODE upsertSighting [src=lib/core/db/local_db.dart loc=None community=121]
NODE allAliases [src=lib/core/db/local_db.dart loc=None community=121]
NODE _setMeta [src=lib/core/db/local_db.dart loc=None community=121]
NODE _onCreate [src=lib/core/db/local_db.dart loc=None community=121]
NODE open [src=lib/core/db/local_db.dart loc=None community=121]
... (truncated — 10 more nodes cut by ~2000-token budget. Narrow with context_filter=['call'] or use get_node for a specific symbol)

  → Inspect migration, audit findings, and exact predecessor function definitions
  • Trace schema constraints and all real coordinate/token write paths
  • Analyze conflict, lifetime, privilege, locking, and transactional behavior
  • Report adversarial verdict with file:line findings
exec
/bin/bash -lc 'wc -l supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql supabase/migrations/0060_fix_remaining_prelaunch_bugs.sql supabase/migrations/0053_fix_locked_phone_encounters.sql supabase/migrations/0059_cleanup_cron_and_claim_policy.sql docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md
nl -ba supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql
rtk rg -n -C 8 "C-SQL-(1|3|4)|claim_token|cleanup_ephemeral_data|correlate_encounter" docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md
rtk git status --short
rtk git diff -- supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql' in /home/hazypiff/in-range
 succeeded in 0ms:
  313 supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql
wc: supabase/migrations/0060_fix_remaining_prelaunch_bugs.sql: No such file or directory
wc: supabase/migrations/0053_fix_locked_phone_encounters.sql: No such file or directory
wc: supabase/migrations/0059_cleanup_cron_and_claim_policy.sql: No such file or directory
  279 docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md
  592 total
     1	-- 0063_audit_2026_08_01_critical_fixes.sql
     2	--
     3	-- Fixes three of the four Criticals from the 2026-08-01 tri-model hardening
     4	-- audit (docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md,
     5	-- commit d1b8c38). The fourth (C-PROD-1) was a deploy-drift defect and was
     6	-- closed by redeploying send-push + photo-review; no schema change.
     7	--
     8	--   C-SQL-1  claim_token could overwrite ANOTHER user's token_claim_history row
     9	--   C-SQL-3  beacon_token_batch had no scheduled purge
    10	--   C-SQL-4  batch-pre-claimed (NULL-location) tokens skipped the GPS veto
    11	--
    12	-- Function bodies below were extracted VERBATIM from their latest definitions
    13	-- (claim_token 0060, correlate_encounter 0053, cleanup_ephemeral_data 0059) and
    14	-- modified only at the marked sites, to avoid transcription drift.
    15	--
    16	-- REVIEW STATUS: written by the Linux side after the audit; NOT yet reviewed by
    17	-- Kimi/Codex and NOT yet applied to production. Rehearse on a full-chain local
    18	-- database before pushing -- the local container is at 0019, so this migration
    19	-- could not be executed end-to-end during authoring.
    20	
    21	BEGIN;
    22	
    23	CREATE OR REPLACE FUNCTION public.claim_token(p_token text, p_valid_until timestamp with time zone, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_range range_type DEFAULT 'miles_10'::range_type, p_accuracy double precision DEFAULT NULL::double precision)
    24	 RETURNS void
    25	 LANGUAGE plpgsql
    26	 SECURITY DEFINER
    27	 SET search_path TO 'pg_catalog', 'public'
    28	AS $function$
    29	DECLARE
    30	  v_uid UUID := auth.uid();
    31	  v_now TIMESTAMPTZ := clock_timestamp();
    32	  v_last TIMESTAMPTZ;
    33	  v_in_batch BOOLEAN;
    34	BEGIN
    35	  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;
    36	  IF NOT public.current_user_can_discover() THEN
    37	    RAISE EXCEPTION 'Complete age and photo verification before using Beacon' USING ERRCODE='42501'; END IF;
    38	  -- Consent gate (0040). No-op unless app_settings.enforce_consent = 1.
    39	  PERFORM public.require_consent(v_uid, 'ble_proximity');
    40	  -- 0048: the consent UI scopes GPS to precise_location ("deleted after 24h").
    41	  -- Beacon mandatorily uploads coordinates, so a user who withdrew precise
    42	  -- location must not keep feeding GPS through it, even while ble_proximity
    43	  -- is still granted. Explicit withdrawal denies regardless of enforce_consent.
    44	  IF public.consent_withdrawn(v_uid, 'precise_location') THEN
    45	    RAISE EXCEPTION 'Location sharing was turned off' USING ERRCODE='42501'; END IF;
    46	  IF p_token IS NULL OR p_token !~ '^[0-9a-f]{32}$' THEN
    47	    RAISE EXCEPTION 'Invalid beacon token' USING ERRCODE='22023'; END IF;
    48	  IF p_valid_until IS NULL OR p_valid_until <= v_now + INTERVAL '1 minute'
    49	     OR p_valid_until > v_now + INTERVAL '21 minutes' THEN
    50	    RAISE EXCEPTION 'Token validity must end within 1..21 minutes' USING ERRCODE='22023'; END IF;
    51	  IF p_lat IS NULL OR p_lon IS NULL THEN
    52	    RAISE EXCEPTION 'Fresh coordinates are required' USING ERRCODE='22023'; END IF;
    53	  IF p_lat NOT BETWEEN -90 AND 90 OR p_lon NOT BETWEEN -180 AND 180 THEN
    54	    RAISE EXCEPTION 'Invalid coordinates' USING ERRCODE='22023'; END IF;
    55	  IF p_accuracy IS NOT NULL AND (p_accuracy < 0 OR p_accuracy > 10000) THEN
    56	    RAISE EXCEPTION 'Invalid accuracy' USING ERRCODE='22023'; END IF;
    57	
    58	  -- #6 step 2: the token must be one the server issued to THIS user. Consume it
    59	  -- (observability); enforce membership only when the flag is on so the
    60	  -- batch-aware client can roll out first.
    61	  UPDATE public.beacon_token_batch b SET consumed_at = COALESCE(b.consumed_at, v_now)
    62	  WHERE b.token = lower(p_token) AND b.user_id = v_uid
    63	  RETURNING TRUE INTO v_in_batch;
    64	  IF NOT COALESCE(v_in_batch, FALSE)
    65	     AND COALESCE((SELECT value_num FROM public.app_settings WHERE key='enforce_batch_tokens'), 0) >= 1 THEN
    66	    RAISE EXCEPTION 'Beacon token was not issued to this account' USING ERRCODE='22023';
    67	  END IF;
    68	
    69	  SELECT last_claimed_at INTO v_last FROM public.token_claims WHERE user_id = v_uid;
    70	  IF v_last IS NOT NULL AND v_last > v_now - INTERVAL '5 seconds' THEN
    71	    RAISE EXCEPTION 'Beacon claim rate limit' USING ERRCODE='54000'; END IF;
    72	
    73	  INSERT INTO public.token_claims (
    74	    user_id, token, valid_from, valid_until, approx_lat, approx_lon,
    75	    range_type, accuracy_m, created_at, last_claimed_at)
    76	  VALUES (v_uid, lower(p_token), v_now, p_valid_until, p_lat, p_lon, p_range, p_accuracy, v_now, v_now)
    77	  ON CONFLICT (user_id) DO UPDATE SET
    78	    token = EXCLUDED.token, valid_from = EXCLUDED.valid_from, valid_until = EXCLUDED.valid_until,
    79	    approx_lat = EXCLUDED.approx_lat, approx_lon = EXCLUDED.approx_lon,
    80	    range_type = EXCLUDED.range_type, accuracy_m = EXCLUDED.accuracy_m,
    81	    last_claimed_at = EXCLUDED.last_claimed_at;
    82	
    83	  INSERT INTO public.token_claim_history
    84	    (token, user_id, valid_from, valid_until, approx_lat, approx_lon, range_type, accuracy_m, created_at)
    85	  VALUES (lower(p_token), v_uid, v_now, p_valid_until, p_lat, p_lon, p_range, p_accuracy, v_now)
    86	  ON CONFLICT (token) DO UPDATE SET
    87	    valid_until = GREATEST(public.token_claim_history.valid_until, EXCLUDED.valid_until),
    88	    approx_lat = EXCLUDED.approx_lat,
    89	    approx_lon = EXCLUDED.approx_lon,
    90	    range_type = EXCLUDED.range_type,
    91	    accuracy_m = EXCLUDED.accuracy_m
    92	  -- 0063 (audit C-SQL-1): the conflict target is the TOKEN, but the
    93	  -- security-relevant key is (token, owner). Without this predicate any
    94	  -- authenticated caller who sniffed a token off the air could rewrite the
    95	  -- owner's row -- including approx_lat/lon, which correlate_encounter's GPS
    96	  -- veto compares against -- and could extend valid_until indefinitely.
    97	  -- A foreign-owned conflict is now a silent no-op.
    98	  -- NOTE: the previous COALESCE(EXCLUDED.x, existing.x) guard was dead code:
    99	  -- this function RAISEs on NULL p_lat/p_lon above, so EXCLUDED.* was never
   100	  -- NULL and the caller's value always won. Restored as a plain assignment so
   101	  -- the intent is not misread again.
   102	  WHERE public.token_claim_history.user_id = v_uid;
   103	END;
   104	$function$;
   105	
   106	CREATE OR REPLACE FUNCTION public.correlate_encounter(
   107	  p_observed_token TEXT, p_lat DOUBLE PRECISION, p_lon DOUBLE PRECISION,
   108	  p_radius_meters DOUBLE PRECISION DEFAULT 50, p_time_window_minutes INT DEFAULT 60
   109	)
   110	RETURNS TABLE (encounter_id BIGINT, other_user_id UUID, created_new BOOLEAN)
   111	LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
   112	AS $$
   113	DECLARE
   114	  v_uid UUID := auth.uid(); v_claim public.token_claim_history%ROWTYPE;
   115	  v_user_a UUID; v_user_b UUID; v_enc_id BIGINT;
   116	  v_distance DOUBLE PRECISION; v_rssi INTEGER; v_min_rssi INTEGER;
   117	  v_new BOOLEAN := FALSE; v_sight_range public.range_type; v_band public.range_type;
   118	  v_reverse_band public.range_type; v_now TIMESTAMPTZ := NOW();
   119	  v_late INTERVAL := public.late_evidence_window();
   120	  v_late_min INT := (EXTRACT(EPOCH FROM public.late_evidence_window()) / 60)::INT;
   121	  -- 0063 (audit C-SQL-4)
   122	  v_rev_lat DOUBLE PRECISION; v_rev_lon DOUBLE PRECISION;
   123	  v_veto_ran BOOLEAN := FALSE;
   124	BEGIN
   125	  IF v_uid IS NULL OR NOT public.current_user_can_discover() THEN RETURN; END IF;
   126	  SELECT * INTO v_claim FROM public.token_claim_history tc
   127	  WHERE tc.token = lower(p_observed_token) AND tc.user_id <> v_uid
   128	    -- Floor so a late-window-valid, end-of-life token is never excluded
   129	    -- (token life <=21 min + late window; +2 slack). valid_until is the gate.
   130	    AND tc.valid_from > NOW() - make_interval(mins => GREATEST(23 + v_late_min, LEAST(30, GREATEST(1, p_time_window_minutes))))
   131	    AND tc.valid_until > NOW() - v_late ORDER BY tc.valid_from DESC LIMIT 1;
   132	  IF NOT FOUND OR NOT public.is_discoverable_user(v_claim.user_id) THEN RETURN; END IF;
   133	  IF public.is_blocked_pair(v_uid, v_claim.user_id) THEN RETURN; END IF;
   134	
   135	  SELECT s.rssi, s.range_type INTO v_rssi, v_sight_range FROM public.sightings s
   136	  WHERE s.observer_user_id = v_uid AND s.observed_token = lower(p_observed_token)
   137	  ORDER BY s.observed_at DESC LIMIT 1;
   138	  v_min_rssi := CASE COALESCE(v_claim.range_type,'feet_10') WHEN 'feet_10' THEN -75 WHEN 'feet_20' THEN -85 ELSE -95 END;
   139	  IF v_rssi IS NULL OR v_rssi < v_min_rssi THEN RETURN; END IF;
   140	
   141	  IF p_lat IS NOT NULL AND p_lon IS NOT NULL AND v_claim.approx_lat IS NOT NULL AND v_claim.approx_lon IS NOT NULL THEN
   142	    v_distance := ST_Distance(ST_SetSRID(ST_MakePoint(p_lon, p_lat),4326)::geography, ST_SetSRID(ST_MakePoint(v_claim.approx_lon, v_claim.approx_lat),4326)::geography);
   143	    IF v_distance > LEAST(400.0, GREATEST(5.0, p_radius_meters)) THEN RETURN; END IF;
   144	    v_veto_ran := TRUE;
   145	  END IF;
   146	
   147	  IF v_sight_range IS NOT NULL AND v_sight_range::TEXT LIKE 'feet_%' THEN v_band := v_sight_range; ELSE v_band := COALESCE(v_claim.range_type, 'feet_10'); END IF;
   148	
   149	  -- Reciprocity gate (server-receipt window; caller-supplied values ignored).
   150	  -- 0053: widened from a fixed 3 min — the other side's evidence may be a
   151	  -- locked phone's wake-burst upload from earlier in the same co-presence.
   152	  SELECT rs.range_type, rs.observer_lat, rs.observer_lon
   153	    INTO v_reverse_band, v_rev_lat, v_rev_lon
   154	  FROM public.sightings rs
   155	  WHERE rs.observer_user_id = v_claim.user_id AND rs.observed_user_id = v_uid
   156	    AND rs.received_at > NOW() - v_late
   157	  ORDER BY rs.received_at DESC LIMIT 1;
   158	  IF NOT FOUND THEN RETURN; END IF;
   159	
   160	  -- 0063 (audit C-SQL-4): the veto above runs ONLY when the claim row carries
   161	  -- coordinates. claim_token requires them, but claim_token_batch (0060)
   162	  -- pre-claims the whole batch with NULL location -- the locked-phone path --
   163	  -- so for those tokens the spatial bound never executed at all. Fall back to
   164	  -- comparing the two OBSERVERS' own recorded positions, which are NOT NULL on
   165	  -- every sightings row, and fail CLOSED if neither comparison is possible.
   166	  IF NOT v_veto_ran THEN
   167	    IF p_lat IS NULL OR p_lon IS NULL OR v_rev_lat IS NULL OR v_rev_lon IS NULL THEN
   168	      RETURN;
   169	    END IF;
   170	    v_distance := ST_Distance(
   171	      ST_SetSRID(ST_MakePoint(p_lon, p_lat),4326)::geography,
   172	      ST_SetSRID(ST_MakePoint(v_rev_lon, v_rev_lat),4326)::geography);
   173	    IF v_distance > LEAST(400.0, GREATEST(5.0, p_radius_meters)) THEN RETURN; END IF;
   174	  END IF;
   175	
   176	  IF v_reverse_band IS NOT NULL AND v_reverse_band::TEXT LIKE 'feet_%' AND v_band::TEXT LIKE 'feet_%'
   177	     AND public.range_band_rank(v_reverse_band) > public.range_band_rank(v_band) THEN
   178	    v_band := v_reverse_band;
   179	  END IF;
   180	
   181	  v_user_a := LEAST(v_uid, v_claim.user_id); v_user_b := GREATEST(v_uid, v_claim.user_id);
   182	  PERFORM pg_advisory_xact_lock(hashtextextended(v_user_a::TEXT || v_user_b::TEXT, 0));
   183	  PERFORM public.bump_encounter_pair(v_user_a, v_user_b, v_band);
   184	  UPDATE public.encounter_pairs SET trust_level = COALESCE(trust_level, 'mutual_ble')
   185	    WHERE user_a = v_user_a AND user_b = v_user_b;
   186	
   187	  SELECT id INTO v_enc_id FROM public.encounters WHERE user_a = v_user_a AND user_b = v_user_b AND status = 'active' ORDER BY encounter_time DESC LIMIT 1 FOR UPDATE;
   188	  IF v_enc_id IS NULL THEN
   189	    INSERT INTO public.encounters (user_a,user_b,neighborhood,encounter_time,last_seen_at,range_type,confidence,status,trust_level)
   190	    VALUES (v_user_a,v_user_b,'Near you',v_now,v_now,v_band,0.8,'active','mutual_ble') RETURNING id INTO v_enc_id; v_new := TRUE;
   191	  ELSE
   192	    UPDATE public.encounters e SET last_seen_at = v_now, trust_level = COALESCE(e.trust_level,'mutual_ble'),
   193	      range_type = CASE WHEN e.range_type::TEXT LIKE 'feet_%' AND v_band::TEXT LIKE 'feet_%' AND public.range_band_rank(v_band) < public.range_band_rank(e.range_type) THEN v_band ELSE e.range_type END
   194	    WHERE e.id = v_enc_id;
   195	  END IF;
   196	  encounter_id := v_enc_id; other_user_id := v_claim.user_id; created_new := v_new; RETURN NEXT;
   197	END;
   198	$$;
   199	
   200	CREATE OR REPLACE FUNCTION public.cleanup_ephemeral_data()
   201	RETURNS VOID
   202	LANGUAGE plpgsql
   203	SECURITY DEFINER
   204	SET search_path = pg_catalog, public
   205	AS $$
   206	DECLARE
   207	  v_holds BOOLEAN := EXISTS (
   208	    SELECT 1 FROM public.legal_holds
   209	     WHERE released_at IS NULL
   210	       AND (expires_at IS NULL OR expires_at > NOW()));
   211	BEGIN
   212	  IF v_holds THEN
   213	    DELETE FROM public.token_claims tc
   214	     WHERE tc.valid_until < NOW() - INTERVAL '30 minutes'
   215	       AND NOT public.has_legal_hold(tc.user_id);
   216	
   217	    DELETE FROM public.sightings s
   218	     WHERE s.observed_at < NOW() - INTERVAL '24 hours'
   219	       AND NOT public.has_legal_hold(s.observer_user_id)
   220	       AND NOT EXISTS (
   221	         SELECT 1 FROM public.token_claims tc
   222	          WHERE tc.token = s.observed_token
   223	            AND public.has_legal_hold(tc.user_id));
   224	
   225	    DELETE FROM public.location_pings lp
   226	     WHERE lp.created_at < NOW() - INTERVAL '24 hours'
   227	       AND NOT public.has_legal_hold(lp.user_id);
   228	
   229	    -- 0047: token_claim_history is ephemeral too; it was never pruned.
   230	    DELETE FROM public.token_claim_history h
   231	     WHERE h.valid_until < NOW() - INTERVAL '24 hours'
   232	       AND NOT public.has_legal_hold(h.user_id);
   233	
   234	    -- 0056
   235	    DELETE FROM public.rssi_samples rs
   236	     WHERE rs.received_at < NOW() - INTERVAL '30 days'
   237	       AND NOT public.has_legal_hold(rs.user_id);
   238	
   239	    -- 0058
   240	    DELETE FROM public.venue_anchors va
   241	     WHERE va.updated_at < NOW() - INTERVAL '14 days'
   242	       AND NOT public.has_legal_hold(va.user_id);
   243	
   244	    DELETE FROM public.proximity_wake_requests pwr
   245	     WHERE (pwr.status IN ('sent', 'skipped') AND pwr.created_at < NOW() - INTERVAL '30 days')
   246	        OR (pwr.status = 'failed' AND pwr.created_at < NOW() - INTERVAL '7 days');
   247	  ELSE
   248	    DELETE FROM public.token_claims
   249	     WHERE valid_until < NOW() - INTERVAL '30 minutes';
   250	
   251	    DELETE FROM public.sightings
   252	     WHERE observed_at < NOW() - INTERVAL '24 hours';
   253	
   254	    DELETE FROM public.location_pings
   255	     WHERE created_at < NOW() - INTERVAL '24 hours';
   256	
   257	    -- 0047: token_claim_history is ephemeral too; it was never pruned.
   258	    DELETE FROM public.token_claim_history
   259	     WHERE valid_until < NOW() - INTERVAL '24 hours';
   260	
   261	    -- 0056
   262	    DELETE FROM public.rssi_samples
   263	     WHERE received_at < NOW() - INTERVAL '30 days';
   264	
   265	    -- 0058
   266	    DELETE FROM public.venue_anchors
   267	     WHERE updated_at < NOW() - INTERVAL '14 days';
   268	
   269	    DELETE FROM public.proximity_wake_requests
   270	     WHERE (status IN ('sent', 'skipped') AND created_at < NOW() - INTERVAL '30 days')
   271	        OR (status = 'failed' AND created_at < NOW() - INTERVAL '7 days');
   272	  END IF;
   273	
   274	  -- Rate buckets outlive their window by definition; drop idle ones.
   275	  -- 0063 (audit C-SQL-3): beacon_token_batch was purged NOWHERE on a schedule.
   276	  -- Its only DELETEs were self-scoped inside issue_token_batch (runs only when
   277	  -- that same user next requests a batch, so a lapsed user's rows persisted
   278	  -- forever) and the account-deletion paths. The table maps token -> user_id,
   279	  -- and rssi_samples.correlation_id is the same value space, so an unpurged
   280	  -- copy de-anonymises up to 30 days of proximity data at rest.
   281	  DELETE FROM public.beacon_token_batch WHERE valid_until < NOW() - INTERVAL '24 hours';
   282	
   283	  DELETE FROM public.rssi_batch_rate
   284	   WHERE window_start < NOW() - INTERVAL '1 day';
   285	
   286	  -- Recover a worker that died after atomically claiming a batch.
   287	  UPDATE public.notification_outbox
   288	     SET status = CASE WHEN attempts < 5 THEN 'pending' ELSE 'failed' END,
   289	         last_error = 'stale_processing_recovered',
   290	         processing_at = NULL
   291	   WHERE status = 'processing'
   292	     AND processing_at < NOW() - INTERVAL '10 minutes';
   293	
   294	  DELETE FROM public.notification_outbox
   295	   WHERE (status IN ('sent', 'skipped') AND created_at < NOW() - INTERVAL '30 days')
   296	      OR (status = 'failed' AND created_at < NOW() - INTERVAL '7 days');
   297	
   298	  DELETE FROM public.ai_events WHERE created_at < NOW() - INTERVAL '90 days';
   299	  DELETE FROM public.ai_runs   WHERE created_at < NOW() - INTERVAL '90 days';
   300	
   301	  -- Evidence snapshots: 1 year, unless the subject is still held or the
   302	  -- snapshot backs an unexpired (or unfiled) CyberTipline obligation.
   303	  DELETE FROM public.report_evidence e
   304	   WHERE e.captured_at < NOW() - INTERVAL '1 year'
   305	     AND (e.subject_user IS NULL OR NOT public.has_legal_hold(e.subject_user))
   306	     AND NOT EXISTS (
   307	       SELECT 1 FROM public.cybertipline_queue q
   308	        WHERE q.report_id = e.report_id
   309	          AND (q.preserve_until IS NULL OR q.preserve_until > NOW()));
   310	END;
   311	$$;
   312	
   313	COMMIT;
17-
18----
19-
20-## VERDICT
21-
22-**Not ready to trust in the wild.** **Four** Critical findings, all server-side and all reachable today:
23-
24-- **one live in production, remotely exploitable by anyone** — C-PROD-1;
25:- **two exploitable today by any authenticated user with a modified client** — C-SQL-1, C-SQL-4;
26:- **one server-side retention defect requiring no attacker** — C-SQL-3, which leaves a de-anonymisable
27-  proximity graph at rest.
28-
29-Plus a large High tier that blocks the W5 merge and the Phase-5 hardware matrix.
30-
31-**Severity convention, settled by the panel:** *Critical* means reachable **now, on `main`**. Everything
32-that exists only on the unmerged `fix/w5-encounter-lease` branch is **High / merge-blocking**, however
33-severe, because it cannot harm a user until PR #9 lands. This was Codex's argument; Claude adopted it and
34-Kimi accepted. It changes no priorities — those items remain first in the Mac queue.
46-1034, 1103`). So "the feature is default-off" is a weaker guarantee than it sounds: a stale `true`
47-inherited from a prior diagnostic install re-activates those native paths **before Dart can clear it**.
48-That is issue #8's mechanism, and it applies to shipped code today even though the RSSI-log writer does
49-not. Tracked as **H-DIAG-4**.
50-
51-**The structural finding:** the worst defects share one cause — *invariants enforced by hand-applied
52-convention with nothing proving coverage.* Consent checks, retention purges, and service-role auth are
53-each applied per-call-site by a human remembering. Three tests (§Systemic) would have caught **two
54:Criticals and one High** at authoring time — C-SQL-3, C-PROD-1 (three weeks ago), and H-CONSENT-1.
55-
56----
57-
58-## CRITICAL — reachable today on `main`
59-
60-### C-PROD-1 🔴 `photo-review` and `send-push` accept unauthenticated requests in production
61-Deploy drift; the repo code is correct. Probed: `POST /photo-review` no auth → `200`; wrong bearer →
62-`200`; **`GET` no auth → `200`**. `requireServiceRole` rejects non-POST with 405 *before* anything else,
66-The gate landed in `45ef624` (2026-07-12) for all four functions; only `maintenance` (v5) and
67-`miles-correlate` (v6) were redeployed (`SAFETY_RUNBOOK.md:31-32`). ~3 weeks of pre-hardening code live.
68-`photo-review` reports `auto_approve: true` on the production host, and photo verification gates
69-discoverability (0052) — a moderation step adjacent to child-safety obligations.
70-
71-**Fix now:** `supabase functions deploy send-push photo-review`; set `verify_jwt=false` for both; add the
72-missing `[functions.proximity-wake]` block (it currently 404s).
73-
74:### C-SQL-1 🔴 `claim_token` overwrites another user's `token_claim_history` row
75-`0060:149-159` — `ON CONFLICT (token) DO UPDATE` with **no `WHERE user_id = v_uid`**. The `COALESCE`
76-"guard" is dead code: `0060:117-118` rejects NULL coordinates, so `EXCLUDED.approx_lat` always wins.
77:Tokens are broadcast in plaintext over BLE. Neutralises the GPS veto — `correlate_encounter`
78-(`0053:179-182`) compares against coordinates the attacker just wrote. The batch-membership check that
79-would stop it sits behind `enforce_batch_tokens`, which is **0**.
80-
81:### C-SQL-3 🔴 `beacon_token_batch` has no scheduled purge — a permanent token→user_id map
82:`cleanup_ephemeral_data()` (latest `0059:477-580`) purges 9 tables; not this one. Joining it to
83-`rssi_samples` on the shared token yields a de-anonymised proximity graph. **Nuance accepted from Kimi:**
84-active users' rows rotate out at next batch issue (~1–2 day window); it is **lapsed** users whose token
85-set persists indefinitely. Two-line fix:
86-`DELETE FROM public.beacon_token_batch WHERE valid_until < NOW() - INTERVAL '24 hours';`
87-
88:### C-SQL-4 🔴 Batch-pre-claimed tokens skip the GPS veto entirely *(found by Kimi)*
89:`0053:179-182` wraps the veto in `IF ... v_claim.approx_lat IS NOT NULL ...`. `claim_token_batch`
90-(`0060:25`) pre-claims with NULL location — the locked-phone path. For those tokens the veto never runs.
91:Independent of C-SQL-1; fixing one does not close the other.
92-**Fix:** treat a location-less claim as veto-*failing*, or compare the two sightings' `observer_lat/lon`
93-to each other (always present).
94-
95----
96-
97-## HIGH
98-
99-**Merge-blocking for W5 (Mac side):**
171-  `other_user_id`") was **false**. `0019:2496-2527` revokes `correlate_miles_encounters` from
172-  `PUBLIC, anon, authenticated, service_role` and the re-grant list omits it (DB confirms
173-  `{postgres=X/postgres}`); the entry point is `record_location_ping` at `0040:156`, which enforces
174-  `current_user_can_discover()` and `require_consent(…,'precise_location')` and returns `bigint`. The
175-  original grep (`00[2-6]*`) excluded 0019 — an asserted verification that was never performed.
176-- **H-SQL-3** The reciprocity gate binds each direction to `now()`, never to the other, so a "mutual"
177-  encounter can be assembled from evidence ~30–50 min apart. **Fix corrected by Codex:** comparing reverse
178-  `received_at` to *forward* `received_at` is a **no-op**, because `record_sighting` upserts the forward
179:  row with `received_at = v_now` (`0053:119`, `:123`) immediately before calling `correlate_encounter`
180-  (`:138`). The real fix is to compare the two `observed_at` **capture** times and bind observations to
181-  the token's validity interval. *Two of Kimi's original fix items survive the refutation and should ship
182-  with it:* reject `p_observed_at` outside the token's `[valid_from, valid_until]` slot, and stop
183-  refreshing `received_at` on weaker-RSSI upserts (`0053:123` refreshes unconditionally, which keeps a
184-  forward sighting reciprocity-eligible indefinitely by re-upsert).
185-- **H-CONSENT-1** *(downgraded from Critical)* `require_consent` appears **zero times** in 0056 and 0059;
186-  `venue_anchors` has no RPC at all. Bounded today (0056 documents the gap as deliberate pre-rollout,
187-  `INRANGE_CALIB_SCAN` defaults false, 0059 is undeployed) — but withdrawal effectiveness must be
239-the per-alias candidate mint" — **re-check what actually landed in `30619a1`.** The shared runners cannot
240-express six oracle entry points (`onBeaconOff`, `onDialFailed`, `onAliasRoll`, `onPrevAliasExpiry`,
241-`onRetryTimer`, `debugSetViewGen`); `graceExpiry` is wired but unused; `sendPropose`/`sendAck` are matched
242-as **wildcards**, so v5.2 correction #5 has zero coverage.
243-
244-## SYSTEMIC — three tests that would have caught two Criticals and one High
245-
246-1. pgTAP: every RPC inserting into a user-scoped table calls `require_consent` → catches H-CONSENT-1.
247:2. A retention test that fails when a table is added without a `cleanup_ephemeral_data` entry → catches
248:   C-SQL-3 and the `venue_anchors`/`proximity_wake_requests` overruns.
249-3. A deploy-parity probe asserting `405` on `GET` for every service-role function → catches C-PROD-1, and
250-   would have caught it three weeks ago.
251-
252-## FIX ORDER
253-
254-1. **C-PROD-1** — redeploy, fix `verify_jwt`, add the `proximity-wake` entry.
255:2. **C-SQL-1, C-SQL-3, C-SQL-4** — three small server-side SQL fixes, all reachable today.
256-3. **H-WL-1 / H-WL-2** — the only endpoints an anonymous attacker can reach.
257-4. **H-W5-1** (two-line hoist + the vector that pins it), then **H-W5-5** *before* the Phase-5 matrix.
258-5. **H-W5-2, H-W5-3, H-RT-1** — the wedges. Then **H-DIAG-1 / H-DIAG-4** (compile-out + flavor stamp).
259-6. Systemic tests, then the rest of the High tier.
260-
261-## COVERAGE AND LIMITATIONS
262-
263-- **Verified against production:** only the Edge Function auth probe. Everything else is source-verified.
 M supabase/config.toml
?? docs/research/2026-08-01/
?? supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql

codex
The first pass exposes the key dependency for (a): the migration asserts that every `sightings` row has observer coordinates, but that claim must be proven from both DDL and every RPC/upsert path. I’m now checking that invariant and mechanically diffing each replacement body against its true predecessor.
exec
/bin/bash -lc "rtk ls supabase/migrations
rtk rg -n \"CREATE OR REPLACE FUNCTION public\\.(claim_token|claim_token_batch|correlate_encounter|record_sighting|cleanup_ephemeral_data)|CREATE TABLE( IF NOT EXISTS)? public\\.(sightings|token_claim_history|beacon_token_batch)|ALTER TABLE public\\.sightings|observer_lat|observer_lon\" supabase/migrations lib supabase/functions test integration_test
rtk rg -n \"rpc\\(['\\\"](record_sighting|claim_token|claim_token_batch|correlate_encounter)['\\\"]|record_sighting|claim_token_batch|claim_token\" lib test integration_test" in /home/hazypiff/in-range
 exited 2 in 0ms:
0001_init.sql  20.5K
0002_location_pings_realtime_storage.sql  8.1K
0003_correlation_fixes.sql  5.8K
0004_encounter_reveal_delay.sql  2.2K
0005_safety_monetization_fcm.sql  14.8K
0006_photo_storage_chat_media.sql  10.3K
0007_swipe_match_chat_rpcs.sql  16.1K
0008_miles_correlation.sql  15.8K
0009_auth_profile_account.sql  12.2K
0010_realtime_grants_cleanup.sql  6.6K
0011_record_sighting_single_sig.sql  1.8K
0012_correlate_grace_dedupe.sql  3.5K
0013_photo_verification_gating.sql  5.8K
0014_restrict_profile_read.sql  1.6K
0015_audit_remaining_fixes.sql  3.9K
0016_swipe_user_and_feed_wire.sql  2.2K
0017_ai_ops_metadata_feedback.sql  11.7K
0018_security_correlate_photos.sql  10.3K
0019_beta_security_hardening.sql  85.1K
0020_feet_60_range.sql  498B
0021_feet_60_range_maps.sql  1.3K
0022_encounter_band_from_sighting.sql  4.7K
0023_gps_accuracy_aware_gate.sql  1.8K
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
0063_audit_2026_08_01_critical_fixes.sql  15.7K
rg: integration_test: No such file or directory (os error 2)
supabase/migrations/0019_beta_security_hardening.sql:811:CREATE OR REPLACE FUNCTION public.claim_token(
supabase/migrations/0019_beta_security_hardening.sql:886:CREATE OR REPLACE FUNCTION public.record_sighting(
supabase/migrations/0019_beta_security_hardening.sql:957:      observer_lat, observer_lon, range_type
supabase/migrations/0019_beta_security_hardening.sql:965:        observer_lat = COALESCE(p_lat, observer_lat),
supabase/migrations/0019_beta_security_hardening.sql:966:        observer_lon = COALESCE(p_lon, observer_lon),
supabase/migrations/0019_beta_security_hardening.sql:986:CREATE OR REPLACE FUNCTION public.correlate_encounter(
supabase/migrations/0019_beta_security_hardening.sql:2394:CREATE OR REPLACE FUNCTION public.cleanup_ephemeral_data()
supabase/migrations/0056_calibration_rssi_samples.sql:478:CREATE OR REPLACE FUNCTION public.cleanup_ephemeral_data()
supabase/migrations/0030_correlate_valid_from_grace.sql:19:CREATE OR REPLACE FUNCTION public.correlate_encounter(
supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql:23:CREATE OR REPLACE FUNCTION public.claim_token(p_token text, p_valid_until timestamp with time zone, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_range range_type DEFAULT 'miles_10'::range_type, p_accuracy double precision DEFAULT NULL::double precision)
supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql:106:CREATE OR REPLACE FUNCTION public.correlate_encounter(
supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql:152:  SELECT rs.range_type, rs.observer_lat, rs.observer_lon
supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql:200:CREATE OR REPLACE FUNCTION public.cleanup_ephemeral_data()
supabase/migrations/0026_sighting_idempotency_ratelimit.sql:33:CREATE OR REPLACE FUNCTION public.record_sighting(
supabase/migrations/0026_sighting_idempotency_ratelimit.sql:112:    observer_lat, observer_lon, range_type, observer_accuracy_m
supabase/migrations/0026_sighting_idempotency_ratelimit.sql:120:        observer_lat = CASE WHEN p_rssi > s.rssi THEN p_lat ELSE s.observer_lat END,
supabase/migrations/0026_sighting_idempotency_ratelimit.sql:121:        observer_lon = CASE WHEN p_rssi > s.rssi THEN p_lon ELSE s.observer_lon END,
supabase/migrations/0060_batch_token_preclaim.sql:25:CREATE OR REPLACE FUNCTION public.claim_token_batch(
supabase/migrations/0060_batch_token_preclaim.sql:89:CREATE OR REPLACE FUNCTION public.claim_token(p_token text, p_valid_until timestamp with time zone, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_range range_type DEFAULT 'miles_10'::range_type, p_accuracy double precision DEFAULT NULL::double precision)
supabase/migrations/0025_encounter_recurrence.sql:80:CREATE OR REPLACE FUNCTION public.correlate_encounter(
supabase/migrations/0032_relay_abuse_detection.sql:94:             ST_SetSRID(ST_MakePoint(s.observer_lon, s.observer_lat),4326)::geography)) AS max_m,
supabase/migrations/0032_relay_abuse_detection.sql:100:      AND s.observer_lat IS NOT NULL AND s.observer_lon IS NOT NULL
supabase/migrations/0033_relay_abuse_response_surface.sql:153:        ST_SetSRID(ST_MakePoint(s.observer_lon, s.observer_lat), 4326)::geography
supabase/migrations/0033_relay_abuse_response_surface.sql:161:      AND s.observer_lat IS NOT NULL
supabase/migrations/0033_relay_abuse_response_surface.sql:162:      AND s.observer_lon IS NOT NULL
supabase/migrations/0003_correlation_fixes.sql:16:CREATE OR REPLACE FUNCTION public.correlate_encounter(
supabase/migrations/0003_correlation_fixes.sql:127:CREATE OR REPLACE FUNCTION public.record_sighting(
supabase/migrations/0003_correlation_fixes.sql:155:    observer_lat,
supabase/migrations/0003_correlation_fixes.sql:156:    observer_lon,
supabase/migrations/0008_miles_correlation.sql:376:CREATE OR REPLACE FUNCTION public.record_sighting(
supabase/migrations/0008_miles_correlation.sql:407:    observer_lat,
supabase/migrations/0008_miles_correlation.sql:408:    observer_lon,
supabase/migrations/0011_record_sighting_single_sig.sql:15:CREATE OR REPLACE FUNCTION public.record_sighting(
supabase/migrations/0011_record_sighting_single_sig.sql:43:    observer_lat, observer_lon, range_type
supabase/migrations/0058_subtle_wake_privacy.sql:360:CREATE OR REPLACE FUNCTION public.cleanup_ephemeral_data()
supabase/migrations/0047_privilege_retention_consent.sql:104:CREATE OR REPLACE FUNCTION public.cleanup_ephemeral_data()
supabase/migrations/0059_proximity_wake_producer.sql:477:CREATE OR REPLACE FUNCTION public.cleanup_ephemeral_data()
supabase/migrations/0018_security_correlate_photos.sql:99:CREATE OR REPLACE FUNCTION public.correlate_encounter(
supabase/migrations/0027_durable_recurrence_pairs.sql:106:CREATE OR REPLACE FUNCTION public.correlate_encounter(
supabase/migrations/0040_wire_consent_gates.sql:29:CREATE OR REPLACE FUNCTION public.claim_token(p_token text, p_valid_until timestamp with time zone, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_range range_type DEFAULT 'miles_10'::range_type, p_accuracy double precision DEFAULT NULL::double precision)
supabase/migrations/0040_wire_consent_gates.sql:91:CREATE OR REPLACE FUNCTION public.record_sighting(p_observed_token text, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_rssi integer DEFAULT NULL::integer, p_observed_at timestamp with time zone DEFAULT now(), p_range range_type DEFAULT NULL::range_type, p_accuracy double precision DEFAULT NULL::double precision)
supabase/migrations/0040_wire_consent_gates.sql:130:    rssi, observed_at, observer_lat, observer_lon, range_type, observer_accuracy_m
supabase/migrations/0040_wire_consent_gates.sql:138:        observer_lat = CASE WHEN p_rssi > s.rssi THEN p_lat ELSE s.observer_lat END,
supabase/migrations/0040_wire_consent_gates.sql:139:        observer_lon = CASE WHEN p_rssi > s.rssi THEN p_lon ELSE s.observer_lon END,
supabase/migrations/0053_late_evidence_tolerance.sql:62:CREATE OR REPLACE FUNCTION public.record_sighting(p_observed_token text, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_rssi integer DEFAULT NULL::integer, p_observed_at timestamp with time zone DEFAULT now(), p_range range_type DEFAULT NULL::range_type, p_accuracy double precision DEFAULT NULL::double precision)
supabase/migrations/0053_late_evidence_tolerance.sql:117:    rssi, observed_at, observer_lat, observer_lon, range_type, observer_accuracy_m
supabase/migrations/0053_late_evidence_tolerance.sql:125:        observer_lat = CASE WHEN p_rssi > s.rssi THEN p_lat ELSE s.observer_lat END,
supabase/migrations/0053_late_evidence_tolerance.sql:126:        observer_lon = CASE WHEN p_rssi > s.rssi THEN p_lon ELSE s.observer_lon END,
supabase/migrations/0053_late_evidence_tolerance.sql:147:CREATE OR REPLACE FUNCTION public.correlate_encounter(
supabase/migrations/0048_gps_scope_and_retention.sql:5:--      sightings (observer_lat/lon, NOT NULL) and token_claim_history
supabase/migrations/0048_gps_scope_and_retention.sql:30:CREATE OR REPLACE FUNCTION public.claim_token(p_token text, p_valid_until timestamp with time zone, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_range range_type DEFAULT 'miles_10'::range_type, p_accuracy double precision DEFAULT NULL::double precision)
supabase/migrations/0048_gps_scope_and_retention.sql:98:CREATE OR REPLACE FUNCTION public.record_sighting(p_observed_token text, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_rssi integer DEFAULT NULL::integer, p_observed_at timestamp with time zone DEFAULT now(), p_range range_type DEFAULT NULL::range_type, p_accuracy double precision DEFAULT NULL::double precision)
supabase/migrations/0048_gps_scope_and_retention.sql:148:    rssi, observed_at, observer_lat, observer_lon, range_type, observer_accuracy_m
supabase/migrations/0048_gps_scope_and_retention.sql:156:        observer_lat = CASE WHEN p_rssi > s.rssi THEN p_lat ELSE s.observer_lat END,
supabase/migrations/0048_gps_scope_and_retention.sql:157:        observer_lon = CASE WHEN p_rssi > s.rssi THEN p_lon ELSE s.observer_lon END,
supabase/migrations/0048_gps_scope_and_retention.sql:175:CREATE OR REPLACE FUNCTION public.cleanup_ephemeral_data()
supabase/migrations/0046_withdrawal_enforcement.sql:257:CREATE OR REPLACE FUNCTION public.record_sighting(p_observed_token text, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_rssi integer DEFAULT NULL::integer, p_observed_at timestamp with time zone DEFAULT now(), p_range range_type DEFAULT NULL::range_type, p_accuracy double precision DEFAULT NULL::double precision)
supabase/migrations/0046_withdrawal_enforcement.sql:299:    rssi, observed_at, observer_lat, observer_lon, range_type, observer_accuracy_m
supabase/migrations/0046_withdrawal_enforcement.sql:307:        observer_lat = CASE WHEN p_rssi > s.rssi THEN p_lat ELSE s.observer_lat END,
supabase/migrations/0046_withdrawal_enforcement.sql:308:        observer_lon = CASE WHEN p_rssi > s.rssi THEN p_lon ELSE s.observer_lon END,
supabase/migrations/0022_encounter_band_from_sighting.sql:22:CREATE OR REPLACE FUNCTION public.correlate_encounter(
supabase/migrations/0028_token_claim_history.sql:14:CREATE TABLE IF NOT EXISTS public.token_claim_history (
supabase/migrations/0028_token_claim_history.sql:40:CREATE OR REPLACE FUNCTION public.claim_token(
supabase/migrations/0028_token_claim_history.sql:108:CREATE OR REPLACE FUNCTION public.record_sighting(
supabase/migrations/0028_token_claim_history.sql:143:  INSERT INTO public.sightings AS s (observer_user_id, observed_token, rssi, observed_at, observer_lat, observer_lon, range_type, observer_accuracy_m)
supabase/migrations/0028_token_claim_history.sql:148:        observer_lat = CASE WHEN p_rssi > s.rssi THEN p_lat ELSE s.observer_lat END,
supabase/migrations/0028_token_claim_history.sql:149:        observer_lon = CASE WHEN p_rssi > s.rssi THEN p_lon ELSE s.observer_lon END,
supabase/migrations/0028_token_claim_history.sql:167:CREATE OR REPLACE FUNCTION public.correlate_encounter(
supabase/migrations/0001_init.sql:134:CREATE TABLE public.sightings (
supabase/migrations/0001_init.sql:140:  observer_lat        DOUBLE PRECISION NOT NULL,
supabase/migrations/0001_init.sql:141:  observer_lon        DOUBLE PRECISION NOT NULL,
supabase/migrations/0001_init.sql:143:    ST_SetSRID(ST_MakePoint(observer_lon, observer_lat), 4326)::geography
supabase/migrations/0001_init.sql:239:CREATE OR REPLACE FUNCTION public.claim_token(
supabase/migrations/0001_init.sql:277:CREATE OR REPLACE FUNCTION public.record_sighting(
supabase/migrations/0001_init.sql:303:    observer_lat,
supabase/migrations/0001_init.sql:304:    observer_lon,
supabase/migrations/0001_init.sql:336:CREATE OR REPLACE FUNCTION public.correlate_encounter(
supabase/migrations/0001_init.sql:483:ALTER TABLE public.sightings ENABLE ROW LEVEL SECURITY;
supabase/migrations/0002_location_pings_realtime_storage.sql:185:CREATE OR REPLACE FUNCTION public.cleanup_ephemeral_data()
supabase/migrations/0012_correlate_grace_dedupe.sql:2:CREATE OR REPLACE FUNCTION public.correlate_encounter(
supabase/migrations/0024_accuracy_aware_correlation.sql:23:CREATE OR REPLACE FUNCTION public.record_sighting(
supabase/migrations/0024_accuracy_aware_correlation.sql:99:      observer_lat, observer_lon, range_type, observer_accuracy_m
supabase/migrations/0024_accuracy_aware_correlation.sql:115:        observer_lat = CASE WHEN p_rssi > rssi THEN p_lat ELSE observer_lat END,
supabase/migrations/0024_accuracy_aware_correlation.sql:116:        observer_lon = CASE WHEN p_rssi > rssi THEN p_lon ELSE observer_lon END,
supabase/migrations/0024_accuracy_aware_correlation.sql:149:CREATE OR REPLACE FUNCTION public.correlate_encounter(
supabase/migrations/0024_accuracy_aware_correlation.sql:291:CREATE OR REPLACE FUNCTION public.claim_token(
supabase/migrations/0031_server_issued_token_batches.sql:27:CREATE TABLE IF NOT EXISTS public.beacon_token_batch (
supabase/migrations/0031_server_issued_token_batches.sql:102:CREATE OR REPLACE FUNCTION public.claim_token(
supabase/migrations/0023_gps_accuracy_aware_gate.sql:23:ALTER TABLE public.sightings
supabase/migrations/0044_evidence_preservation.sql:349:CREATE OR REPLACE FUNCTION public.cleanup_ephemeral_data()
supabase/migrations/0029_reciprocal_confirmation.sql:21:ALTER TABLE public.sightings
supabase/migrations/0029_reciprocal_confirmation.sql:36:CREATE OR REPLACE FUNCTION public.record_sighting(
supabase/migrations/0029_reciprocal_confirmation.sql:74:    rssi, observed_at, observer_lat, observer_lon, range_type, observer_accuracy_m
supabase/migrations/0029_reciprocal_confirmation.sql:82:        observer_lat = CASE WHEN p_rssi > s.rssi THEN p_lat ELSE s.observer_lat END,
supabase/migrations/0029_reciprocal_confirmation.sql:83:        observer_lon = CASE WHEN p_rssi > s.rssi THEN p_lon ELSE s.observer_lon END,
supabase/migrations/0029_reciprocal_confirmation.sql:102:CREATE OR REPLACE FUNCTION public.correlate_encounter(
rg: integration_test: No such file or directory (os error 2)
lib/features/beacon/beacon_service.dart:2289:    // record_sighting's required lat/lon) but only REMOVES a record after a
lib/features/beacon/beacon_service.dart:2462:        await InRangeSupabase.client.rpc('record_sighting', params: {
lib/features/beacon/beacon_service.dart:2474:        debugPrint('record_sighting OK rssi=${s.rssi}');
lib/features/beacon/beacon_service.dart:2548:      debugPrint('claim_token skipped (no real Supabase — local BLE mode)');
lib/features/beacon/beacon_service.dart:2566:  /// One claim_token_batch RPC per 6 h (migration 0060): makes every slot
lib/features/beacon/beacon_service.dart:2579:      await InRangeSupabase.client.rpc('claim_token_batch', params: {
lib/features/beacon/beacon_service.dart:2583:      debugPrint('claim_token_batch OK');
lib/features/beacon/beacon_service.dart:2585:      debugPrint('claim_token_batch failed: $e');
lib/features/beacon/beacon_service.dart:2589:  /// One claim_token RPC for the current token/location. Throws on failure so
lib/features/beacon/beacon_service.dart:2605:    await InRangeSupabase.client.rpc('claim_token', params: {
lib/features/beacon/beacon_service.dart:2613:    debugPrint('claim_token OK until=${until.toIso8601String()}');
lib/features/beacon/ephemeral_token_generator.dart:25:/// rotation the client must call `claim_token` again on the server.
lib/shared/services/encounters_api.dart:134:      await InRangeSupabase.client.rpc('claim_token', params: {
lib/shared/services/encounters_api.dart:142:      debugPrint('claim_token: $e');
lib/shared/services/encounters_api.dart:156:      await InRangeSupabase.client.rpc('record_sighting', params: {
lib/shared/services/encounters_api.dart:166:      debugPrint('record_sighting: $e');

exec
/bin/bash -lc "nl -ba supabase/migrations/0060_batch_token_preclaim.sql | sed -n '1,220p'
nl -ba supabase/migrations/0053_late_evidence_tolerance.sql | sed -n '1,270p'
nl -ba supabase/migrations/0059_proximity_wake_producer.sql | sed -n '430,620p'
nl -ba supabase/migrations/0001_init.sql | sed -n '100,175p'
nl -ba supabase/migrations/0023_gps_accuracy_aware_gate.sql | sed -n '1,100p'
nl -ba supabase/migrations/0029_reciprocal_confirmation.sql | sed -n '1,55p'" in /home/hazypiff/in-range
 succeeded in 0ms:
     1	-- 0060: close the native-token resolution gap (audit 2026-07-25, critical #2).
     2	--
     3	-- A locked iPhone's native BackgroundBeacon serves GATT reads from its
     4	-- persisted day batch, rotating slots on its own schedule. Only Dart's
     5	-- claim_token wrote token_claim_history — and record_sighting resolves
     6	-- exclusively through that table — so once Dart was suspended or evicted,
     7	-- every later slot the native side served was unresolvable: a peer could
     8	-- hear the beacon and never map it to a person.
     9	--
    10	-- Fix: claim_token_batch pre-claims every still-live slot the server issued
    11	-- to the caller (today + tomorrow, per issue_token_batch), so any token the
    12	-- native carrier can serve is already resolvable. Rows are written WITHOUT
    13	-- coordinates on purpose: a fix stamped at session start would make
    14	-- correlate_encounter's 400 m plausibility veto reject real encounters after
    15	-- the user travels (the reviewer-#7 failure shape), and NULL location is
    16	-- both the safer product choice (a dark, locked phone records no GPS trail)
    17	-- and handled by the veto, which only applies when a claim carries
    18	-- coordinates. When Dart is alive and later single-claims a slot, the
    19	-- claim_token conflict merge below fills the geo fields back in, so the
    20	-- veto returns for the slots that have a fresh fix.
    21	
    22	-- ---------------------------------------------------------------------------
    23	-- 1. claim_token_batch: pre-claim the caller's own issued slots.
    24	-- ---------------------------------------------------------------------------
    25	CREATE OR REPLACE FUNCTION public.claim_token_batch(
    26	  p_range public.range_type DEFAULT 'feet_60'
    27	)
    28	RETURNS INT
    29	LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
    30	AS $function$
    31	DECLARE
    32	  v_uid UUID := auth.uid();
    33	  v_now TIMESTAMPTZ := clock_timestamp();
    34	  v_rows INT;
    35	BEGIN
    36	  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;
    37	  IF NOT public.current_user_can_discover() THEN
    38	    RAISE EXCEPTION 'Complete age and photo verification before using Beacon' USING ERRCODE='42501'; END IF;
    39	  -- Consent gate (0040), same as claim_token. No precise_location check: this
    40	  -- function stores NO coordinates, so there is nothing location-shaped to
    41	  -- withdraw from.
    42	  PERFORM public.require_consent(v_uid, 'ble_proximity');
    43	
    44	  -- Throttle: one batch claim per minute per user. Only batch-originated rows
    45	  -- (NULL location) count, so the per-rotation single claims never trip it.
    46	  IF EXISTS (
    47	    SELECT 1 FROM public.token_claim_history h
    48	    WHERE h.user_id = v_uid AND h.approx_lat IS NULL
    49	      AND h.created_at > v_now - INTERVAL '1 minute'
    50	  ) THEN
    51	    RAISE EXCEPTION 'Beacon claim rate limit' USING ERRCODE='54000';
    52	  END IF;
    53	
    54	  -- Only tokens the server issued to THIS caller (beacon_token_batch
    55	  -- membership) — no user can claim another's tokens, and far-future mining
    56	  -- is already bounded by issue_token_batch's day cap. valid_from/valid_until
    57	  -- are the slot's real window, so resolution and expiry line up with what
    58	  -- the native carrier actually serves. ON CONFLICT DO NOTHING: a slot the
    59	  -- live client already single-claimed keeps its location-bearing row.
    60	  INSERT INTO public.token_claim_history
    61	    (token, user_id, valid_from, valid_until, approx_lat, approx_lon,
    62	     range_type, accuracy_m, created_at)
    63	  SELECT b.token, v_uid, b.valid_from, b.valid_until, NULL, NULL,
    64	         p_range, NULL, v_now
    65	  FROM public.beacon_token_batch b
    66	  WHERE b.user_id = v_uid AND b.valid_until > v_now
    67	  ON CONFLICT (token) DO NOTHING;
    68	  GET DIAGNOSTICS v_rows = ROW_COUNT;
    69	  RETURN v_rows;
    70	END;
    71	$function$;
    72	
    73	COMMENT ON FUNCTION public.claim_token_batch(public.range_type) IS
    74	  'Pre-claims every still-live server-issued batch slot for the caller into token_claim_history (NULL location by design), so tokens served natively by a locked/evicted phone stay resolvable. Returns rows claimed.';
    75	
    76	REVOKE ALL ON FUNCTION public.claim_token_batch(public.range_type)
    77	  FROM PUBLIC, anon;
    78	GRANT EXECUTE ON FUNCTION public.claim_token_batch(public.range_type)
    79	  TO authenticated;
    80	
    81	-- ---------------------------------------------------------------------------
    82	-- 2. claim_token: merge geo fields into a batch-pre-claimed row.
    83	-- ---------------------------------------------------------------------------
    84	-- Body is verbatim 0048 except the token_claim_history conflict clause: a
    85	-- slot first claimed by claim_token_batch carries NULL location; when the
    86	-- live client later single-claims that same slot with a fresh fix, fill the
    87	-- geo fields (never overwriting existing ones) so correlate_encounter's
    88	-- plausibility veto applies to that slot again.
    89	CREATE OR REPLACE FUNCTION public.claim_token(p_token text, p_valid_until timestamp with time zone, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_range range_type DEFAULT 'miles_10'::range_type, p_accuracy double precision DEFAULT NULL::double precision)
    90	 RETURNS void
    91	 LANGUAGE plpgsql
    92	 SECURITY DEFINER
    93	 SET search_path TO 'pg_catalog', 'public'
    94	AS $function$
    95	DECLARE
    96	  v_uid UUID := auth.uid();
    97	  v_now TIMESTAMPTZ := clock_timestamp();
    98	  v_last TIMESTAMPTZ;
    99	  v_in_batch BOOLEAN;
   100	BEGIN
   101	  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;
   102	  IF NOT public.current_user_can_discover() THEN
   103	    RAISE EXCEPTION 'Complete age and photo verification before using Beacon' USING ERRCODE='42501'; END IF;
   104	  -- Consent gate (0040). No-op unless app_settings.enforce_consent = 1.
   105	  PERFORM public.require_consent(v_uid, 'ble_proximity');
   106	  -- 0048: the consent UI scopes GPS to precise_location ("deleted after 24h").
   107	  -- Beacon mandatorily uploads coordinates, so a user who withdrew precise
   108	  -- location must not keep feeding GPS through it, even while ble_proximity
   109	  -- is still granted. Explicit withdrawal denies regardless of enforce_consent.
   110	  IF public.consent_withdrawn(v_uid, 'precise_location') THEN
   111	    RAISE EXCEPTION 'Location sharing was turned off' USING ERRCODE='42501'; END IF;
   112	  IF p_token IS NULL OR p_token !~ '^[0-9a-f]{32}$' THEN
   113	    RAISE EXCEPTION 'Invalid beacon token' USING ERRCODE='22023'; END IF;
   114	  IF p_valid_until IS NULL OR p_valid_until <= v_now + INTERVAL '1 minute'
   115	     OR p_valid_until > v_now + INTERVAL '21 minutes' THEN
   116	    RAISE EXCEPTION 'Token validity must end within 1..21 minutes' USING ERRCODE='22023'; END IF;
   117	  IF p_lat IS NULL OR p_lon IS NULL THEN
   118	    RAISE EXCEPTION 'Fresh coordinates are required' USING ERRCODE='22023'; END IF;
   119	  IF p_lat NOT BETWEEN -90 AND 90 OR p_lon NOT BETWEEN -180 AND 180 THEN
   120	    RAISE EXCEPTION 'Invalid coordinates' USING ERRCODE='22023'; END IF;
   121	  IF p_accuracy IS NOT NULL AND (p_accuracy < 0 OR p_accuracy > 10000) THEN
   122	    RAISE EXCEPTION 'Invalid accuracy' USING ERRCODE='22023'; END IF;
   123	
   124	  -- #6 step 2: the token must be one the server issued to THIS user. Consume it
   125	  -- (observability); enforce membership only when the flag is on so the
   126	  -- batch-aware client can roll out first.
   127	  UPDATE public.beacon_token_batch b SET consumed_at = COALESCE(b.consumed_at, v_now)
   128	  WHERE b.token = lower(p_token) AND b.user_id = v_uid
   129	  RETURNING TRUE INTO v_in_batch;
   130	  IF NOT COALESCE(v_in_batch, FALSE)
   131	     AND COALESCE((SELECT value_num FROM public.app_settings WHERE key='enforce_batch_tokens'), 0) >= 1 THEN
   132	    RAISE EXCEPTION 'Beacon token was not issued to this account' USING ERRCODE='22023';
   133	  END IF;
   134	
   135	  SELECT last_claimed_at INTO v_last FROM public.token_claims WHERE user_id = v_uid;
   136	  IF v_last IS NOT NULL AND v_last > v_now - INTERVAL '5 seconds' THEN
   137	    RAISE EXCEPTION 'Beacon claim rate limit' USING ERRCODE='54000'; END IF;
   138	
   139	  INSERT INTO public.token_claims (
   140	    user_id, token, valid_from, valid_until, approx_lat, approx_lon,
   141	    range_type, accuracy_m, created_at, last_claimed_at)
   142	  VALUES (v_uid, lower(p_token), v_now, p_valid_until, p_lat, p_lon, p_range, p_accuracy, v_now, v_now)
   143	  ON CONFLICT (user_id) DO UPDATE SET
   144	    token = EXCLUDED.token, valid_from = EXCLUDED.valid_from, valid_until = EXCLUDED.valid_until,
   145	    approx_lat = EXCLUDED.approx_lat, approx_lon = EXCLUDED.approx_lon,
   146	    range_type = EXCLUDED.range_type, accuracy_m = EXCLUDED.accuracy_m,
   147	    last_claimed_at = EXCLUDED.last_claimed_at;
   148	
   149	  INSERT INTO public.token_claim_history
   150	    (token, user_id, valid_from, valid_until, approx_lat, approx_lon, range_type, accuracy_m, created_at)
   151	  VALUES (lower(p_token), v_uid, v_now, p_valid_until, p_lat, p_lon, p_range, p_accuracy, v_now)
   152	  ON CONFLICT (token) DO UPDATE SET
   153	    valid_until = EXCLUDED.valid_until,
   154	    -- 0060: fill geo fields on a batch-pre-claimed (NULL-location) row; never
   155	    -- blank out a fix an earlier single claim already wrote.
   156	    approx_lat = COALESCE(EXCLUDED.approx_lat, public.token_claim_history.approx_lat),
   157	    approx_lon = COALESCE(EXCLUDED.approx_lon, public.token_claim_history.approx_lon),
   158	    range_type = COALESCE(EXCLUDED.range_type, public.token_claim_history.range_type),
   159	    accuracy_m = COALESCE(EXCLUDED.accuracy_m, public.token_claim_history.accuracy_m);
   160	END;
   161	$function$;
     1	-- 0053: late-evidence tolerance — reciprocity must survive asymmetric uploads.
     2	--
     3	-- WHY (locked-iPhone reality, bench-measured 2026-07-23, see
     4	-- docs/IOS_BACKGROUND_BLE_WIRING.md): an Android peer uploads rich, timely
     5	-- sightings of a locked iPhone (overflow scan + GATT reads), but the locked
     6	-- iPhone buffers its own sightings natively and only flushes them when the
     7	-- user wakes the phone — minutes later. Three server gates then killed the
     8	-- flush, so the pair could NEVER confirm:
     9	--   1. record_sighting: p_observed_at older than 10 min  -> 'Invalid sighting time'
    10	--   2. record_sighting + correlate_encounter: observed token more than 2 min
    11	--      past valid_until -> 'Unknown or expired beacon token'
    12	--   3. correlate_encounter reciprocity: reverse sighting received_at within
    13	--      3 min -> the other side's last upload is often older by the flush time
    14	--
    15	-- CHANGE: one knob, app_settings.late_evidence_window_minutes (default 15,
    16	-- server-clamped to [2, 25]), replaces all three constants. 2 preserves the
    17	-- old grace as the floor; 25 keeps every window inside a token lifetime
    18	-- (claim_token enforces valid_until <= now + 21 min), so evidence can never
    19	-- outlive the token that anchors it by more than the clamp.
    20	--
    21	-- WHAT DOES NOT CHANGE (the anti-forgery envelope):
    22	--   - Reciprocity still keys on SERVER received_at; caller-supplied
    23	--     timestamps still cannot widen anything (harness T2).
    24	--   - The GPS veto still bounds space: correlate refuses when the caller's
    25	--     coords are farther than the (<=400 m) radius from the claim's coords —
    26	--     a replayed token confirms nothing from far away.
    27	--   - Both directions must still be real uploads by both accounts; nothing
    28	--     here lets one device fabricate the other's evidence.
    29	--   Widening is therefore purely temporal: "both saw each other within ~15
    30	--   min at the same place" instead of "within 3 min". The sniffed-token
    31	--   replay window grows from 2 to <=25 min; that surface is already tracked
    32	--   (docs/RELAY_ABUSE_RUNBOOK.md, attestation scaffold 0034) and stays
    33	--   GPS-bounded.
    34	--
    35	-- Harness: T2/T6 fixtures updated (stale means beyond-the-window now),
    36	-- new T48 proves the full locked-iPhone late-flush confirms.
    37	
    38	-- ---------------------------------------------------------------------------
    39	-- The knob + its reader. STABLE: one read per statement is fine; the clamp
    40	-- lives here so a bad/absent setting can never widen past a token lifetime.
    41	-- ---------------------------------------------------------------------------
    42	INSERT INTO public.app_settings (key, value_num)
    43	VALUES ('late_evidence_window_minutes', 15)
    44	ON CONFLICT (key) DO NOTHING;
    45	
    46	CREATE OR REPLACE FUNCTION public.late_evidence_window()
    47	RETURNS INTERVAL
    48	LANGUAGE sql STABLE
    49	SET search_path = pg_catalog, public
    50	AS $$
    51	  SELECT make_interval(mins => GREATEST(2, LEAST(25, COALESCE(
    52	    (SELECT value_num FROM public.app_settings
    53	      WHERE key = 'late_evidence_window_minutes'), 15)))::INT);
    54	$$;
    55	
    56	-- Internal helper: called only inside SECURITY DEFINER functions.
    57	REVOKE EXECUTE ON FUNCTION public.late_evidence_window() FROM PUBLIC, anon, authenticated;
    58	
    59	-- ---------------------------------------------------------------------------
    60	-- record_sighting: gates 1 + 2. Verbatim 0048 body except the two windows.
    61	-- ---------------------------------------------------------------------------
    62	CREATE OR REPLACE FUNCTION public.record_sighting(p_observed_token text, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_rssi integer DEFAULT NULL::integer, p_observed_at timestamp with time zone DEFAULT now(), p_range range_type DEFAULT NULL::range_type, p_accuracy double precision DEFAULT NULL::double precision)
    63	 RETURNS bigint
    64	 LANGUAGE plpgsql
    65	 SECURITY DEFINER
    66	 SET search_path TO 'pg_catalog', 'public'
    67	AS $function$
    68	DECLARE
    69	  v_uid UUID := auth.uid(); v_now TIMESTAMPTZ := clock_timestamp(); v_id BIGINT;
    70	  v_range public.range_type := COALESCE(p_range,'feet_10');
    71	  v_radius DOUBLE PRECISION; v_window INT; v_claim_acc DOUBLE PRECISION; v_calls INT;
    72	  v_observed_uid UUID;
    73	  v_late INTERVAL := public.late_evidence_window();
    74	BEGIN
    75	  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;
    76	  IF NOT public.current_user_can_discover() THEN RAISE EXCEPTION 'Account is not discoverable' USING ERRCODE='42501'; END IF;
    77	  -- Consent gate (0040). No-op unless app_settings.enforce_consent = 1.
    78	  PERFORM public.require_consent(v_uid, 'ble_proximity');
    79	  -- 0048: the observer uploads their OWN GPS here; a caller who withdrew
    80	  -- precise_location must not keep doing so via Beacon.
    81	  IF public.consent_withdrawn(v_uid, 'precise_location') THEN
    82	    RAISE EXCEPTION 'Location sharing was turned off' USING ERRCODE='42501'; END IF;
    83	  IF p_observed_token IS NULL OR lower(p_observed_token) !~ '^[0-9a-f]{32}$' THEN RAISE EXCEPTION 'Invalid beacon token' USING ERRCODE='22023'; END IF;
    84	  -- 0053: was a fixed 10 min — a locked iPhone's natively-buffered sightings
    85	  -- flush with their ORIGINAL capture timestamps when the user wakes it.
    86	  IF p_observed_at IS NULL OR p_observed_at < v_now - v_late OR p_observed_at > v_now + INTERVAL '1 minute' THEN RAISE EXCEPTION 'Invalid sighting time' USING ERRCODE='22023'; END IF;
    87	  IF p_rssi IS NULL OR p_rssi NOT BETWEEN -127 AND 20 THEN RAISE EXCEPTION 'Invalid RSSI' USING ERRCODE='22023'; END IF;
    88	  IF p_lat IS NULL OR p_lon IS NULL THEN RAISE EXCEPTION 'Fresh coordinates are required' USING ERRCODE='22023'; END IF;
    89	  IF p_lat NOT BETWEEN -90 AND 90 OR p_lon NOT BETWEEN -180 AND 180 THEN RAISE EXCEPTION 'Invalid coordinates' USING ERRCODE='22023'; END IF;
    90	  IF p_accuracy IS NOT NULL AND (p_accuracy < 0 OR p_accuracy > 10000) THEN RAISE EXCEPTION 'Invalid accuracy' USING ERRCODE='22023'; END IF;
    91	
    92	  INSERT INTO public.sighting_call_rate AS r (user_id, window_start, calls) VALUES (v_uid, v_now, 1)
    93	  ON CONFLICT (user_id) DO UPDATE
    94	    SET window_start = CASE WHEN r.window_start < v_now - INTERVAL '1 minute' THEN v_now ELSE r.window_start END,
    95	        calls = CASE WHEN r.window_start < v_now - INTERVAL '1 minute' THEN 1 ELSE r.calls + 1 END
    96	  RETURNING calls INTO v_calls;
    97	  IF v_calls > 120 THEN RAISE EXCEPTION 'Sighting rate limit' USING ERRCODE='54000'; END IF;
    98	
    99	  -- Resolve who this token belongs to (history-aware; survives rotation).
   100	  -- 0053: grace widened from 2 min to the late-evidence window — a flushed
   101	  -- sighting may reference a token that expired while the phone slept.
   102	  SELECT h.user_id INTO v_observed_uid FROM public.token_claim_history h
   103	  WHERE h.token = lower(p_observed_token) AND h.user_id <> v_uid
   104	    AND h.valid_until > v_now - v_late
   105	  ORDER BY h.valid_from DESC LIMIT 1;
   106	  IF v_observed_uid IS NULL THEN RAISE EXCEPTION 'Unknown or expired beacon token' USING ERRCODE='22023'; END IF;
   107	  -- 0046: an observed user who withdrew BLE consent must not generate new
   108	  -- evidence, even from a token preserved in history under a legal hold.
   109	  -- 0048: an observed user who withdrew EITHER ble_proximity or precise_location
   110	  -- must not generate new location-correlated evidence.
   111	  IF public.consent_withdrawn(v_observed_uid, 'ble_proximity')
   112	     OR public.consent_withdrawn(v_observed_uid, 'precise_location') THEN
   113	    RAISE EXCEPTION 'Unknown or expired beacon token' USING ERRCODE='22023'; END IF;
   114	
   115	  INSERT INTO public.sightings AS s (
   116	    observer_user_id, observed_token, observed_user_id, received_at,
   117	    rssi, observed_at, observer_lat, observer_lon, range_type, observer_accuracy_m
   118	  ) VALUES (
   119	    v_uid, lower(p_observed_token), v_observed_uid, v_now,
   120	    p_rssi, p_observed_at, p_lat, p_lon, v_range, p_accuracy
   121	  )
   122	  ON CONFLICT (observer_user_id, observed_token) DO UPDATE
   123	    SET observed_at = p_observed_at, received_at = v_now, observed_user_id = v_observed_uid,
   124	        rssi = CASE WHEN p_rssi > s.rssi THEN p_rssi ELSE s.rssi END,
   125	        observer_lat = CASE WHEN p_rssi > s.rssi THEN p_lat ELSE s.observer_lat END,
   126	        observer_lon = CASE WHEN p_rssi > s.rssi THEN p_lon ELSE s.observer_lon END,
   127	        observer_accuracy_m = CASE WHEN p_rssi > s.rssi THEN p_accuracy ELSE s.observer_accuracy_m END,
   128	        range_type = CASE WHEN p_rssi > s.rssi THEN v_range ELSE s.range_type END
   129	  RETURNING id INTO v_id;
   130	
   131	  v_window := LEAST(30, public.range_time_window_minutes(v_range));
   132	  IF v_range::TEXT LIKE 'feet_%' THEN
   133	    SELECT h.accuracy_m INTO v_claim_acc FROM public.token_claim_history h WHERE h.token = lower(p_observed_token) ORDER BY h.valid_from DESC LIMIT 1;
   134	    v_radius := public.gps_veto_radius_meters(p_accuracy, v_claim_acc);
   135	  ELSE v_radius := GREATEST(5.0, public.range_radius_meters(v_range)); END IF;
   136	
   137	  PERFORM public.correlate_encounter(lower(p_observed_token), p_lat, p_lon, v_radius, v_window);
   138	  RETURN v_id;
   139	END;
   140	$function$;
   141	
   142	-- ---------------------------------------------------------------------------
   143	-- correlate_encounter: gate 3 (+ the same claim grace, + a valid_from floor
   144	-- that can never exclude a late-window-valid claim). Verbatim 0030 body
   145	-- except the three window expressions.
   146	-- ---------------------------------------------------------------------------
   147	CREATE OR REPLACE FUNCTION public.correlate_encounter(
   148	  p_observed_token TEXT, p_lat DOUBLE PRECISION, p_lon DOUBLE PRECISION,
   149	  p_radius_meters DOUBLE PRECISION DEFAULT 50, p_time_window_minutes INT DEFAULT 60
   150	)
   151	RETURNS TABLE (encounter_id BIGINT, other_user_id UUID, created_new BOOLEAN)
   152	LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
   153	AS $$
   154	DECLARE
   155	  v_uid UUID := auth.uid(); v_claim public.token_claim_history%ROWTYPE;
   156	  v_user_a UUID; v_user_b UUID; v_enc_id BIGINT;
   157	  v_distance DOUBLE PRECISION; v_rssi INTEGER; v_min_rssi INTEGER;
   158	  v_new BOOLEAN := FALSE; v_sight_range public.range_type; v_band public.range_type;
   159	  v_reverse_band public.range_type; v_now TIMESTAMPTZ := NOW();
   160	  v_late INTERVAL := public.late_evidence_window();
   161	  v_late_min INT := (EXTRACT(EPOCH FROM public.late_evidence_window()) / 60)::INT;
   162	BEGIN
   163	  IF v_uid IS NULL OR NOT public.current_user_can_discover() THEN RETURN; END IF;
   164	  SELECT * INTO v_claim FROM public.token_claim_history tc
   165	  WHERE tc.token = lower(p_observed_token) AND tc.user_id <> v_uid
   166	    -- Floor so a late-window-valid, end-of-life token is never excluded
   167	    -- (token life <=21 min + late window; +2 slack). valid_until is the gate.
   168	    AND tc.valid_from > NOW() - make_interval(mins => GREATEST(23 + v_late_min, LEAST(30, GREATEST(1, p_time_window_minutes))))
   169	    AND tc.valid_until > NOW() - v_late ORDER BY tc.valid_from DESC LIMIT 1;
   170	  IF NOT FOUND OR NOT public.is_discoverable_user(v_claim.user_id) THEN RETURN; END IF;
   171	  IF public.is_blocked_pair(v_uid, v_claim.user_id) THEN RETURN; END IF;
   172	
   173	  SELECT s.rssi, s.range_type INTO v_rssi, v_sight_range FROM public.sightings s
   174	  WHERE s.observer_user_id = v_uid AND s.observed_token = lower(p_observed_token)
   175	  ORDER BY s.observed_at DESC LIMIT 1;
   176	  v_min_rssi := CASE COALESCE(v_claim.range_type,'feet_10') WHEN 'feet_10' THEN -75 WHEN 'feet_20' THEN -85 ELSE -95 END;
   177	  IF v_rssi IS NULL OR v_rssi < v_min_rssi THEN RETURN; END IF;
   178	
   179	  IF p_lat IS NOT NULL AND p_lon IS NOT NULL AND v_claim.approx_lat IS NOT NULL AND v_claim.approx_lon IS NOT NULL THEN
   180	    v_distance := ST_Distance(ST_SetSRID(ST_MakePoint(p_lon, p_lat),4326)::geography, ST_SetSRID(ST_MakePoint(v_claim.approx_lon, v_claim.approx_lat),4326)::geography);
   181	    IF v_distance > LEAST(400.0, GREATEST(5.0, p_radius_meters)) THEN RETURN; END IF;
   182	  END IF;
   183	
   184	  IF v_sight_range IS NOT NULL AND v_sight_range::TEXT LIKE 'feet_%' THEN v_band := v_sight_range; ELSE v_band := COALESCE(v_claim.range_type, 'feet_10'); END IF;
   185	
   186	  -- Reciprocity gate (server-receipt window; caller-supplied values ignored).
   187	  -- 0053: widened from a fixed 3 min — the other side's evidence may be a
   188	  -- locked phone's wake-burst upload from earlier in the same co-presence.
   189	  SELECT rs.range_type INTO v_reverse_band FROM public.sightings rs
   190	  WHERE rs.observer_user_id = v_claim.user_id AND rs.observed_user_id = v_uid
   191	    AND rs.received_at > NOW() - v_late
   192	  ORDER BY rs.received_at DESC LIMIT 1;
   193	  IF NOT FOUND THEN RETURN; END IF;
   194	
   195	  IF v_reverse_band IS NOT NULL AND v_reverse_band::TEXT LIKE 'feet_%' AND v_band::TEXT LIKE 'feet_%'
   196	     AND public.range_band_rank(v_reverse_band) > public.range_band_rank(v_band) THEN
   197	    v_band := v_reverse_band;
   198	  END IF;
   199	
   200	  v_user_a := LEAST(v_uid, v_claim.user_id); v_user_b := GREATEST(v_uid, v_claim.user_id);
   201	  PERFORM pg_advisory_xact_lock(hashtextextended(v_user_a::TEXT || v_user_b::TEXT, 0));
   202	  PERFORM public.bump_encounter_pair(v_user_a, v_user_b, v_band);
   203	  UPDATE public.encounter_pairs SET trust_level = COALESCE(trust_level, 'mutual_ble')
   204	    WHERE user_a = v_user_a AND user_b = v_user_b;
   205	
   206	  SELECT id INTO v_enc_id FROM public.encounters WHERE user_a = v_user_a AND user_b = v_user_b AND status = 'active' ORDER BY encounter_time DESC LIMIT 1 FOR UPDATE;
   207	  IF v_enc_id IS NULL THEN
   208	    INSERT INTO public.encounters (user_a,user_b,neighborhood,encounter_time,last_seen_at,range_type,confidence,status,trust_level)
   209	    VALUES (v_user_a,v_user_b,'Near you',v_now,v_now,v_band,0.8,'active','mutual_ble') RETURNING id INTO v_enc_id; v_new := TRUE;
   210	  ELSE
   211	    UPDATE public.encounters e SET last_seen_at = v_now, trust_level = COALESCE(e.trust_level,'mutual_ble'),
   212	      range_type = CASE WHEN e.range_type::TEXT LIKE 'feet_%' AND v_band::TEXT LIKE 'feet_%' AND public.range_band_rank(v_band) < public.range_band_rank(e.range_type) THEN v_band ELSE e.range_type END
   213	    WHERE e.id = v_enc_id;
   214	  END IF;
   215	  encounter_id := v_enc_id; other_user_id := v_claim.user_id; created_new := v_new; RETURN NEXT;
   216	END;
   217	$$;
   430	        FROM public.reports r WHERE r.reporter_id = v_uid
   431	    ), '[]'::jsonb),
   432	
   433	    -- Billing. raw_receipt is excluded: it is the store's payload, contains
   434	    -- no data the user gave us, and can carry provider-side identifiers.
   435	    'subscriptions', COALESCE((
   436	      SELECT jsonb_agg(jsonb_build_object(
   437	               'tier', s.tier, 'status', s.status, 'provider', s.provider,
   438	               'product_id', s.product_id, 'starts_at', s.starts_at,
   439	               'expires_at', s.expires_at, 'canceled_at', s.canceled_at)
   440	             ORDER BY s.created_at DESC)
   441	        FROM public.subscriptions s WHERE s.user_id = v_uid
   442	    ), '[]'::jsonb),
   443	
   444	    'boosts', COALESCE((
   445	      SELECT jsonb_agg(jsonb_build_object(
   446	               'product_id', bo.product_id, 'provider', bo.provider,
   447	               'starts_at', bo.starts_at, 'ends_at', bo.ends_at)
   448	             ORDER BY bo.created_at DESC)
   449	        FROM public.boosts bo WHERE bo.user_id = v_uid
   450	    ), '[]'::jsonb),
   451	
   452	    -- Registered push destinations, by platform and provider only -- the token
   453	    -- itself is a device credential, not user-facing data.
   454	    'push_devices', COALESCE((
   455	      SELECT jsonb_agg(jsonb_build_object(
   456	               'platform', d.platform, 'provider', d.provider, 'created_at', d.created_at))
   457	        FROM public.device_push_tokens d WHERE d.user_id = v_uid
   458	    ), '[]'::jsonb)
   459	  ) INTO v_out;
   460	
   461	  RETURN v_out;
   462	END;
   463	$$;
   464	
   465	COMMENT ON FUNCTION public.export_my_data IS
   466	  'Right-of-access export of the calling user''s own data. Counterparts appear only as opaque user ids; reports filed about the caller are excluded to protect reporters.';
   467	
   468	REVOKE ALL ON FUNCTION public.export_my_data() FROM PUBLIC, anon;
   469	GRANT EXECUTE ON FUNCTION public.export_my_data() TO authenticated;
   470	
   471	-- ---------------------------------------------------------------------------
   472	-- 5. Retention (cleanup_ephemeral_data)
   473	-- ---------------------------------------------------------------------------
   474	-- Body as of 0058_subtle_wake_privacy.sql:334, unchanged. proximity_wake_requests
   475	-- retention already covers both user_id and recipient_user_id rows.
   476	
   477	CREATE OR REPLACE FUNCTION public.cleanup_ephemeral_data()
   478	RETURNS VOID
   479	LANGUAGE plpgsql
   480	SECURITY DEFINER
   481	SET search_path = pg_catalog, public
   482	AS $$
   483	DECLARE
   484	  v_holds BOOLEAN := EXISTS (
   485	    SELECT 1 FROM public.legal_holds
   486	     WHERE released_at IS NULL
   487	       AND (expires_at IS NULL OR expires_at > NOW()));
   488	BEGIN
   489	  IF v_holds THEN
   490	    DELETE FROM public.token_claims tc
   491	     WHERE tc.valid_until < NOW() - INTERVAL '30 minutes'
   492	       AND NOT public.has_legal_hold(tc.user_id);
   493	
   494	    DELETE FROM public.sightings s
   495	     WHERE s.observed_at < NOW() - INTERVAL '24 hours'
   496	       AND NOT public.has_legal_hold(s.observer_user_id)
   497	       AND NOT EXISTS (
   498	         SELECT 1 FROM public.token_claims tc
   499	          WHERE tc.token = s.observed_token
   500	            AND public.has_legal_hold(tc.user_id));
   501	
   502	    DELETE FROM public.location_pings lp
   503	     WHERE lp.created_at < NOW() - INTERVAL '24 hours'
   504	       AND NOT public.has_legal_hold(lp.user_id);
   505	
   506	    -- 0047: token_claim_history is ephemeral too; it was never pruned.
   507	    DELETE FROM public.token_claim_history h
   508	     WHERE h.valid_until < NOW() - INTERVAL '24 hours'
   509	       AND NOT public.has_legal_hold(h.user_id);
   510	
   511	    -- 0056
   512	    DELETE FROM public.rssi_samples rs
   513	     WHERE rs.received_at < NOW() - INTERVAL '30 days'
   514	       AND NOT public.has_legal_hold(rs.user_id);
   515	
   516	    -- 0058
   517	    DELETE FROM public.venue_anchors va
   518	     WHERE va.updated_at < NOW() - INTERVAL '14 days'
   519	       AND NOT public.has_legal_hold(va.user_id);
   520	
   521	    DELETE FROM public.proximity_wake_requests pwr
   522	     WHERE (pwr.status IN ('sent', 'skipped') AND pwr.created_at < NOW() - INTERVAL '30 days')
   523	        OR (pwr.status = 'failed' AND pwr.created_at < NOW() - INTERVAL '7 days');
   524	  ELSE
   525	    DELETE FROM public.token_claims
   526	     WHERE valid_until < NOW() - INTERVAL '30 minutes';
   527	
   528	    DELETE FROM public.sightings
   529	     WHERE observed_at < NOW() - INTERVAL '24 hours';
   530	
   531	    DELETE FROM public.location_pings
   532	     WHERE created_at < NOW() - INTERVAL '24 hours';
   533	
   534	    -- 0047: token_claim_history is ephemeral too; it was never pruned.
   535	    DELETE FROM public.token_claim_history
   536	     WHERE valid_until < NOW() - INTERVAL '24 hours';
   537	
   538	    -- 0056
   539	    DELETE FROM public.rssi_samples
   540	     WHERE received_at < NOW() - INTERVAL '30 days';
   541	
   542	    -- 0058
   543	    DELETE FROM public.venue_anchors
   544	     WHERE updated_at < NOW() - INTERVAL '14 days';
   545	
   546	    DELETE FROM public.proximity_wake_requests
   547	     WHERE (status IN ('sent', 'skipped') AND created_at < NOW() - INTERVAL '30 days')
   548	        OR (status = 'failed' AND created_at < NOW() - INTERVAL '7 days');
   549	  END IF;
   550	
   551	  -- Rate buckets outlive their window by definition; drop idle ones.
   552	  DELETE FROM public.rssi_batch_rate
   553	   WHERE window_start < NOW() - INTERVAL '1 day';
   554	
   555	  -- Recover a worker that died after atomically claiming a batch.
   556	  UPDATE public.notification_outbox
   557	     SET status = CASE WHEN attempts < 5 THEN 'pending' ELSE 'failed' END,
   558	         last_error = 'stale_processing_recovered',
   559	         processing_at = NULL
   560	   WHERE status = 'processing'
   561	     AND processing_at < NOW() - INTERVAL '10 minutes';
   562	
   563	  DELETE FROM public.notification_outbox
   564	   WHERE (status IN ('sent', 'skipped') AND created_at < NOW() - INTERVAL '30 days')
   565	      OR (status = 'failed' AND created_at < NOW() - INTERVAL '7 days');
   566	
   567	  DELETE FROM public.ai_events WHERE created_at < NOW() - INTERVAL '90 days';
   568	  DELETE FROM public.ai_runs   WHERE created_at < NOW() - INTERVAL '90 days';
   569	
   570	  -- Evidence snapshots: 1 year, unless the subject is still held or the
   571	  -- snapshot backs an unexpired (or unfiled) CyberTipline obligation.
   572	  DELETE FROM public.report_evidence e
   573	   WHERE e.captured_at < NOW() - INTERVAL '1 year'
   574	     AND (e.subject_user IS NULL OR NOT public.has_legal_hold(e.subject_user))
   575	     AND NOT EXISTS (
   576	       SELECT 1 FROM public.cybertipline_queue q
   577	        WHERE q.report_id = e.report_id
   578	          AND (q.preserve_until IS NULL OR q.preserve_until > NOW()));
   579	END;
   580	$$;
   581	
   582	COMMENT ON FUNCTION public.cleanup_ephemeral_data IS
   583	  'Sweeps ephemeral tables: location_pings (24 h), sightings (24 h), token_claim_history (24 h), rssi_samples (30 d), venue_anchors (14 d), proximity_wake_requests (30 d sent / 7 d failed), notification_outbox, AI events/runs (90 d), report_evidence (1 y). Honors legal holds.';
   584	
   585	COMMIT;
   100	  BEFORE UPDATE ON public.profiles
   101	  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();
   102	
   103	-- =============================================================================
   104	-- TOKEN CLAIMS (Ephemeral - what THIS user is currently advertising via BLE)
   105	-- =============================================================================
   106	-- Client generates rotating token and calls claim_token() while beacon is ON.
   107	-- Short validity windows (e.g. 10-15 minutes) for privacy.
   108	CREATE TABLE public.token_claims (
   109	  id            BIGSERIAL PRIMARY KEY,
   110	  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
   111	  token         TEXT NOT NULL,                    -- Ephemeral token (see separate spec)
   112	  valid_from    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
   113	  valid_until   TIMESTAMPTZ NOT NULL,
   114	  approx_lat    DOUBLE PRECISION,
   115	  approx_lon    DOUBLE PRECISION,
   116	  range_type    public.range_type,
   117	  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
   118	);
   119	
   120	-- Fast lookup by token + time window (core for correlation)
   121	CREATE INDEX idx_token_claims_lookup 
   122	  ON public.token_claims (token, valid_from, valid_until);
   123	
   124	-- Note: cannot use NOW() in index predicate (must be IMMUTABLE).
   125	CREATE INDEX idx_token_claims_user_active 
   126	  ON public.token_claims (user_id, valid_until);
   127	
   128	-- =============================================================================
   129	-- SIGHTINGS (What OTHER devices were observed - BLE + GPS)
   130	-- =============================================================================
   131	-- Uploaded in batches by the observer while beacon is ON.
   132	-- Contains observed_token (from scanner) + observer's location at time of sighting.
   133	-- Ephemeral: app should prune old records; server can also clean.
   134	CREATE TABLE public.sightings (
   135	  id                  BIGSERIAL PRIMARY KEY,
   136	  observer_user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
   137	  observed_token      TEXT NOT NULL,
   138	  rssi                INTEGER,                     -- For feet-range distance estimation
   139	  observed_at         TIMESTAMPTZ NOT NULL,
   140	  observer_lat        DOUBLE PRECISION NOT NULL,
   141	  observer_lon        DOUBLE PRECISION NOT NULL,
   142	  observer_location   GEOGRAPHY(POINT, 4326) GENERATED ALWAYS AS (
   143	    ST_SetSRID(ST_MakePoint(observer_lon, observer_lat), 4326)::geography
   144	  ) STORED,
   145	  range_type          public.range_type,
   146	  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
   147	);
   148	
   149	-- Critical indexes for correlation queries
   150	CREATE INDEX idx_sightings_token_time 
   151	  ON public.sightings (observed_token, observed_at DESC);
   152	
   153	CREATE INDEX idx_sightings_observer 
   154	  ON public.sightings (observer_user_id, observed_at DESC);
   155	
   156	CREATE INDEX idx_sightings_geo 
   157	  ON public.sightings USING GIST (observer_location);
   158	
   159	-- Cleanup queries filter by created_at at runtime (no NOW() in index predicate).
   160	CREATE INDEX idx_sightings_recent_cleanup 
   161	  ON public.sightings (created_at);
   162	
   163	-- =============================================================================
   164	-- ENCOUNTERS (Server-created real-world crossings)
   165	-- =============================================================================
   166	CREATE TABLE public.encounters (
   167	  id              BIGSERIAL PRIMARY KEY,
   168	  user_a          UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
   169	  user_b          UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
   170	  CHECK (user_a < user_b),                        -- Canonical ordering prevents dups
   171	  neighborhood    TEXT,                           -- e.g. "Downtown LA" (never precise coords)
   172	  encounter_time  TIMESTAMPTZ NOT NULL,
   173	  range_type      public.range_type,
   174	  confidence      NUMERIC(4,2) DEFAULT 0.75,      -- 0.0 - 1.0 based on RSSI + time + geo
   175	  status          public.encounter_status NOT NULL DEFAULT 'active',
     1	-- GPS is a coarse plausibility VETO, never a proximity signal.
     2	--
     3	-- Research (docs/research/gps-fused-location.md):
     4	--   * Android's reported location accuracy is a 68%-CONFIDENCE radius, so
     5	--     roughly 1 fix in 3 has true error LARGER than the circle it claims.
     6	--   * Indoors, median reported accuracy is 29-48 m on current flagships
     7	--     (Galaxy S22 41.7 m, S24 28.8 m, Pixel 10 47.9 m) versus <5 m outdoors.
     8	--
     9	-- Our feet-tier correlation gate was clamped to 50-100 m. Two people standing
    10	-- together inside a bar can each legitimately report a 40 m accuracy circle,
    11	-- so a fixed 100 m gate SILENTLY REJECTS GENUINE ENCOUNTERS — precisely the
    12	-- venue where this app is supposed to work.
    13	--
    14	-- Fix: widen the gate with the uncertainty the phones actually reported.
    15	--   radius = clamp( 2 * (acc_a + acc_b), 100 m, 400 m )
    16	-- The factor 2 converts each 68% circle toward ~95%. A generous veto still
    17	-- blocks cross-city replay/relay, which is the only thing the veto is FOR.
    18	-- Tight geometry is BLE's job, and BLE is the only radio that can do it.
    19	
    20	ALTER TABLE public.token_claims
    21	  ADD COLUMN IF NOT EXISTS accuracy_m DOUBLE PRECISION;
    22	
    23	ALTER TABLE public.sightings
    24	  ADD COLUMN IF NOT EXISTS observer_accuracy_m DOUBLE PRECISION;
    25	
    26	CREATE OR REPLACE FUNCTION public.gps_veto_radius_meters(
    27	  p_acc_a DOUBLE PRECISION,
    28	  p_acc_b DOUBLE PRECISION
    29	)
    30	RETURNS DOUBLE PRECISION
    31	LANGUAGE sql
    32	IMMUTABLE
    33	AS $$
    34	  -- Unknown accuracy on either side => fall back to the widest sane veto
    35	  -- rather than inventing precision we do not have.
    36	  SELECT LEAST(400.0, GREATEST(100.0,
    37	    2.0 * (COALESCE(p_acc_a, 100.0) + COALESCE(p_acc_b, 100.0))
    38	  ));
    39	$$;
    40	
    41	COMMENT ON FUNCTION public.gps_veto_radius_meters IS
    42	  'Accuracy-aware plausibility radius. GPS may only VETO implausible pairs; '
    43	  'it may never assert proximity (consumer GPS ~10 m at best, 29-48 m indoors).';
     1	-- #6 step 1: reciprocal confirmation gate.
     2	--
     3	-- Today record_sighting -> correlate_encounter creates a cloud encounter and
     4	-- bumps durable recurrence from a SINGLE, entirely caller-controlled report
     5	-- (RSSI, time, GPS all forgeable; the HMAC key ships in every app). So a relay
     6	-- + an accomplice can forge "we crossed paths" with anyone, anywhere — and the
     7	-- recurrence feature amplifies it into fake familiarity.
     8	--
     9	-- Fix (behavioral): a cloud encounter + recurrence is created ONLY when BOTH
    10	-- phones independently observed each other within a short window measured by
    11	-- SERVER RECEIPT TIME (received_at) — never p_observed_at / GPS / RSSI, which
    12	-- the caller controls. One-way sightings remain anonymous local cards on the
    13	-- client and short-lived pending evidence on the server; they never reveal
    14	-- identity, notify, rank, or increment recurrence.
    15	--
    16	-- NOT full relay protection: a relay that forwards BOTH tokens still makes both
    17	-- phones report each other. True relay resistance needs secure distance
    18	-- ranging (UWB) — tracked as the 'secure_ranged' trust level. Do not describe
    19	-- mutual_ble as cryptographically relay-proof.
    20	
    21	ALTER TABLE public.sightings
    22	  ADD COLUMN IF NOT EXISTS observed_user_id UUID,
    23	  ADD COLUMN IF NOT EXISTS received_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
    24	
    25	-- Reverse-direction lookup: "did the peer observe ME recently?"
    26	CREATE INDEX IF NOT EXISTS idx_sightings_reverse
    27	  ON public.sightings (observer_user_id, observed_user_id, received_at DESC);
    28	
    29	ALTER TABLE public.encounters
    30	  ADD COLUMN IF NOT EXISTS trust_level TEXT; -- 'mutual_ble' | 'secure_ranged' | NULL (legacy)
    31	ALTER TABLE public.encounter_pairs
    32	  ADD COLUMN IF NOT EXISTS trust_level TEXT;
    33	
    34	-- record_sighting: resolve + store the observed user id and the server receipt
    35	-- time; correlation uses these, not the caller's claimed values.
    36	CREATE OR REPLACE FUNCTION public.record_sighting(
    37	  p_observed_token TEXT, p_lat DOUBLE PRECISION DEFAULT NULL, p_lon DOUBLE PRECISION DEFAULT NULL,
    38	  p_rssi INTEGER DEFAULT NULL, p_observed_at TIMESTAMPTZ DEFAULT NOW(),
    39	  p_range public.range_type DEFAULT NULL, p_accuracy DOUBLE PRECISION DEFAULT NULL
    40	)
    41	RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
    42	AS $$
    43	DECLARE
    44	  v_uid UUID := auth.uid(); v_now TIMESTAMPTZ := clock_timestamp(); v_id BIGINT;
    45	  v_range public.range_type := COALESCE(p_range,'feet_10');
    46	  v_radius DOUBLE PRECISION; v_window INT; v_claim_acc DOUBLE PRECISION; v_calls INT;
    47	  v_observed_uid UUID;
    48	BEGIN
    49	  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;
    50	  IF NOT public.current_user_can_discover() THEN RAISE EXCEPTION 'Account is not discoverable' USING ERRCODE='42501'; END IF;
    51	  IF p_observed_token IS NULL OR lower(p_observed_token) !~ '^[0-9a-f]{32}$' THEN RAISE EXCEPTION 'Invalid beacon token' USING ERRCODE='22023'; END IF;
    52	  IF p_observed_at IS NULL OR p_observed_at < v_now - INTERVAL '10 minutes' OR p_observed_at > v_now + INTERVAL '1 minute' THEN RAISE EXCEPTION 'Invalid sighting time' USING ERRCODE='22023'; END IF;
    53	  IF p_rssi IS NULL OR p_rssi NOT BETWEEN -127 AND 20 THEN RAISE EXCEPTION 'Invalid RSSI' USING ERRCODE='22023'; END IF;
    54	  IF p_lat IS NULL OR p_lon IS NULL THEN RAISE EXCEPTION 'Fresh coordinates are required' USING ERRCODE='22023'; END IF;
    55	  IF p_lat NOT BETWEEN -90 AND 90 OR p_lon NOT BETWEEN -180 AND 180 THEN RAISE EXCEPTION 'Invalid coordinates' USING ERRCODE='22023'; END IF;

exec
/bin/bash -lc "diff -u <(sed -n '89,161p' supabase/migrations/0060_batch_token_preclaim.sql) <(sed -n '23,104p' supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql) || true
diff -u <(sed -n '147,217p' supabase/migrations/0053_late_evidence_tolerance.sql) <(sed -n '106,198p' supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql) || true
diff -u <(sed -n '477,580p' supabase/migrations/0059_proximity_wake_producer.sql) <(sed -n '200,311p' supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql) || true" in /home/hazypiff/in-range
 succeeded in 0ms:
--- /dev/fd/63	2026-08-01 16:48:19.848797017 -0400
+++ /dev/fd/62	2026-08-01 16:48:19.848797017 -0400
@@ -62,12 +62,21 @@
     (token, user_id, valid_from, valid_until, approx_lat, approx_lon, range_type, accuracy_m, created_at)
   VALUES (lower(p_token), v_uid, v_now, p_valid_until, p_lat, p_lon, p_range, p_accuracy, v_now)
   ON CONFLICT (token) DO UPDATE SET
-    valid_until = EXCLUDED.valid_until,
-    -- 0060: fill geo fields on a batch-pre-claimed (NULL-location) row; never
-    -- blank out a fix an earlier single claim already wrote.
-    approx_lat = COALESCE(EXCLUDED.approx_lat, public.token_claim_history.approx_lat),
-    approx_lon = COALESCE(EXCLUDED.approx_lon, public.token_claim_history.approx_lon),
-    range_type = COALESCE(EXCLUDED.range_type, public.token_claim_history.range_type),
-    accuracy_m = COALESCE(EXCLUDED.accuracy_m, public.token_claim_history.accuracy_m);
+    valid_until = GREATEST(public.token_claim_history.valid_until, EXCLUDED.valid_until),
+    approx_lat = EXCLUDED.approx_lat,
+    approx_lon = EXCLUDED.approx_lon,
+    range_type = EXCLUDED.range_type,
+    accuracy_m = EXCLUDED.accuracy_m
+  -- 0063 (audit C-SQL-1): the conflict target is the TOKEN, but the
+  -- security-relevant key is (token, owner). Without this predicate any
+  -- authenticated caller who sniffed a token off the air could rewrite the
+  -- owner's row -- including approx_lat/lon, which correlate_encounter's GPS
+  -- veto compares against -- and could extend valid_until indefinitely.
+  -- A foreign-owned conflict is now a silent no-op.
+  -- NOTE: the previous COALESCE(EXCLUDED.x, existing.x) guard was dead code:
+  -- this function RAISEs on NULL p_lat/p_lon above, so EXCLUDED.* was never
+  -- NULL and the caller's value always won. Restored as a plain assignment so
+  -- the intent is not misread again.
+  WHERE public.token_claim_history.user_id = v_uid;
 END;
 $function$;
--- /dev/fd/63	2026-08-01 16:48:19.855797050 -0400
+++ /dev/fd/62	2026-08-01 16:48:19.855797050 -0400
@@ -13,6 +13,9 @@
   v_reverse_band public.range_type; v_now TIMESTAMPTZ := NOW();
   v_late INTERVAL := public.late_evidence_window();
   v_late_min INT := (EXTRACT(EPOCH FROM public.late_evidence_window()) / 60)::INT;
+  -- 0063 (audit C-SQL-4)
+  v_rev_lat DOUBLE PRECISION; v_rev_lon DOUBLE PRECISION;
+  v_veto_ran BOOLEAN := FALSE;
 BEGIN
   IF v_uid IS NULL OR NOT public.current_user_can_discover() THEN RETURN; END IF;
   SELECT * INTO v_claim FROM public.token_claim_history tc
@@ -33,6 +36,7 @@
   IF p_lat IS NOT NULL AND p_lon IS NOT NULL AND v_claim.approx_lat IS NOT NULL AND v_claim.approx_lon IS NOT NULL THEN
     v_distance := ST_Distance(ST_SetSRID(ST_MakePoint(p_lon, p_lat),4326)::geography, ST_SetSRID(ST_MakePoint(v_claim.approx_lon, v_claim.approx_lat),4326)::geography);
     IF v_distance > LEAST(400.0, GREATEST(5.0, p_radius_meters)) THEN RETURN; END IF;
+    v_veto_ran := TRUE;
   END IF;
 
   IF v_sight_range IS NOT NULL AND v_sight_range::TEXT LIKE 'feet_%' THEN v_band := v_sight_range; ELSE v_band := COALESCE(v_claim.range_type, 'feet_10'); END IF;
@@ -40,12 +44,30 @@
   -- Reciprocity gate (server-receipt window; caller-supplied values ignored).
   -- 0053: widened from a fixed 3 min — the other side's evidence may be a
   -- locked phone's wake-burst upload from earlier in the same co-presence.
-  SELECT rs.range_type INTO v_reverse_band FROM public.sightings rs
+  SELECT rs.range_type, rs.observer_lat, rs.observer_lon
+    INTO v_reverse_band, v_rev_lat, v_rev_lon
+  FROM public.sightings rs
   WHERE rs.observer_user_id = v_claim.user_id AND rs.observed_user_id = v_uid
     AND rs.received_at > NOW() - v_late
   ORDER BY rs.received_at DESC LIMIT 1;
   IF NOT FOUND THEN RETURN; END IF;
 
+  -- 0063 (audit C-SQL-4): the veto above runs ONLY when the claim row carries
+  -- coordinates. claim_token requires them, but claim_token_batch (0060)
+  -- pre-claims the whole batch with NULL location -- the locked-phone path --
+  -- so for those tokens the spatial bound never executed at all. Fall back to
+  -- comparing the two OBSERVERS' own recorded positions, which are NOT NULL on
+  -- every sightings row, and fail CLOSED if neither comparison is possible.
+  IF NOT v_veto_ran THEN
+    IF p_lat IS NULL OR p_lon IS NULL OR v_rev_lat IS NULL OR v_rev_lon IS NULL THEN
+      RETURN;
+    END IF;
+    v_distance := ST_Distance(
+      ST_SetSRID(ST_MakePoint(p_lon, p_lat),4326)::geography,
+      ST_SetSRID(ST_MakePoint(v_rev_lon, v_rev_lat),4326)::geography);
+    IF v_distance > LEAST(400.0, GREATEST(5.0, p_radius_meters)) THEN RETURN; END IF;
+  END IF;
+
   IF v_reverse_band IS NOT NULL AND v_reverse_band::TEXT LIKE 'feet_%' AND v_band::TEXT LIKE 'feet_%'
      AND public.range_band_rank(v_reverse_band) > public.range_band_rank(v_band) THEN
     v_band := v_reverse_band;
--- /dev/fd/63	2026-08-01 16:48:19.856797055 -0400
+++ /dev/fd/62	2026-08-01 16:48:19.856797055 -0400
@@ -73,6 +73,14 @@
   END IF;
 
   -- Rate buckets outlive their window by definition; drop idle ones.
+  -- 0063 (audit C-SQL-3): beacon_token_batch was purged NOWHERE on a schedule.
+  -- Its only DELETEs were self-scoped inside issue_token_batch (runs only when
+  -- that same user next requests a batch, so a lapsed user's rows persisted
+  -- forever) and the account-deletion paths. The table maps token -> user_id,
+  -- and rssi_samples.correlation_id is the same value space, so an unpurged
+  -- copy de-anonymises up to 30 days of proximity data at rest.
+  DELETE FROM public.beacon_token_batch WHERE valid_until < NOW() - INTERVAL '24 hours';
+
   DELETE FROM public.rssi_batch_rate
    WHERE window_start < NOW() - INTERVAL '1 day';
 

exec
/bin/bash -lc "nl -ba supabase/migrations/0053_late_evidence_tolerance.sql | sed -n '55,225p'
nl -ba lib/features/beacon/beacon_service.dart | sed -n '2200,2335p'
nl -ba lib/features/beacon/beacon_service.dart | sed -n '2380,2645p'
nl -ba lib/shared/services/encounters_api.dart | sed -n '95,185p'
rtk rg -n -C 5 \"GRANT .*sightings|POLICY.*sightings|ON public\\.sightings|REVOKE .*sightings|sightings.*(INSERT|UPDATE)|INSERT INTO public\\.sightings|UPDATE public\\.sightings\" supabase/migrations" in /home/hazypiff/in-range
 succeeded in 0ms:
    55	
    56	-- Internal helper: called only inside SECURITY DEFINER functions.
    57	REVOKE EXECUTE ON FUNCTION public.late_evidence_window() FROM PUBLIC, anon, authenticated;
    58	
    59	-- ---------------------------------------------------------------------------
    60	-- record_sighting: gates 1 + 2. Verbatim 0048 body except the two windows.
    61	-- ---------------------------------------------------------------------------
    62	CREATE OR REPLACE FUNCTION public.record_sighting(p_observed_token text, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_rssi integer DEFAULT NULL::integer, p_observed_at timestamp with time zone DEFAULT now(), p_range range_type DEFAULT NULL::range_type, p_accuracy double precision DEFAULT NULL::double precision)
    63	 RETURNS bigint
    64	 LANGUAGE plpgsql
    65	 SECURITY DEFINER
    66	 SET search_path TO 'pg_catalog', 'public'
    67	AS $function$
    68	DECLARE
    69	  v_uid UUID := auth.uid(); v_now TIMESTAMPTZ := clock_timestamp(); v_id BIGINT;
    70	  v_range public.range_type := COALESCE(p_range,'feet_10');
    71	  v_radius DOUBLE PRECISION; v_window INT; v_claim_acc DOUBLE PRECISION; v_calls INT;
    72	  v_observed_uid UUID;
    73	  v_late INTERVAL := public.late_evidence_window();
    74	BEGIN
    75	  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;
    76	  IF NOT public.current_user_can_discover() THEN RAISE EXCEPTION 'Account is not discoverable' USING ERRCODE='42501'; END IF;
    77	  -- Consent gate (0040). No-op unless app_settings.enforce_consent = 1.
    78	  PERFORM public.require_consent(v_uid, 'ble_proximity');
    79	  -- 0048: the observer uploads their OWN GPS here; a caller who withdrew
    80	  -- precise_location must not keep doing so via Beacon.
    81	  IF public.consent_withdrawn(v_uid, 'precise_location') THEN
    82	    RAISE EXCEPTION 'Location sharing was turned off' USING ERRCODE='42501'; END IF;
    83	  IF p_observed_token IS NULL OR lower(p_observed_token) !~ '^[0-9a-f]{32}$' THEN RAISE EXCEPTION 'Invalid beacon token' USING ERRCODE='22023'; END IF;
    84	  -- 0053: was a fixed 10 min — a locked iPhone's natively-buffered sightings
    85	  -- flush with their ORIGINAL capture timestamps when the user wakes it.
    86	  IF p_observed_at IS NULL OR p_observed_at < v_now - v_late OR p_observed_at > v_now + INTERVAL '1 minute' THEN RAISE EXCEPTION 'Invalid sighting time' USING ERRCODE='22023'; END IF;
    87	  IF p_rssi IS NULL OR p_rssi NOT BETWEEN -127 AND 20 THEN RAISE EXCEPTION 'Invalid RSSI' USING ERRCODE='22023'; END IF;
    88	  IF p_lat IS NULL OR p_lon IS NULL THEN RAISE EXCEPTION 'Fresh coordinates are required' USING ERRCODE='22023'; END IF;
    89	  IF p_lat NOT BETWEEN -90 AND 90 OR p_lon NOT BETWEEN -180 AND 180 THEN RAISE EXCEPTION 'Invalid coordinates' USING ERRCODE='22023'; END IF;
    90	  IF p_accuracy IS NOT NULL AND (p_accuracy < 0 OR p_accuracy > 10000) THEN RAISE EXCEPTION 'Invalid accuracy' USING ERRCODE='22023'; END IF;
    91	
    92	  INSERT INTO public.sighting_call_rate AS r (user_id, window_start, calls) VALUES (v_uid, v_now, 1)
    93	  ON CONFLICT (user_id) DO UPDATE
    94	    SET window_start = CASE WHEN r.window_start < v_now - INTERVAL '1 minute' THEN v_now ELSE r.window_start END,
    95	        calls = CASE WHEN r.window_start < v_now - INTERVAL '1 minute' THEN 1 ELSE r.calls + 1 END
    96	  RETURNING calls INTO v_calls;
    97	  IF v_calls > 120 THEN RAISE EXCEPTION 'Sighting rate limit' USING ERRCODE='54000'; END IF;
    98	
    99	  -- Resolve who this token belongs to (history-aware; survives rotation).
   100	  -- 0053: grace widened from 2 min to the late-evidence window — a flushed
   101	  -- sighting may reference a token that expired while the phone slept.
   102	  SELECT h.user_id INTO v_observed_uid FROM public.token_claim_history h
   103	  WHERE h.token = lower(p_observed_token) AND h.user_id <> v_uid
   104	    AND h.valid_until > v_now - v_late
   105	  ORDER BY h.valid_from DESC LIMIT 1;
   106	  IF v_observed_uid IS NULL THEN RAISE EXCEPTION 'Unknown or expired beacon token' USING ERRCODE='22023'; END IF;
   107	  -- 0046: an observed user who withdrew BLE consent must not generate new
   108	  -- evidence, even from a token preserved in history under a legal hold.
   109	  -- 0048: an observed user who withdrew EITHER ble_proximity or precise_location
   110	  -- must not generate new location-correlated evidence.
   111	  IF public.consent_withdrawn(v_observed_uid, 'ble_proximity')
   112	     OR public.consent_withdrawn(v_observed_uid, 'precise_location') THEN
   113	    RAISE EXCEPTION 'Unknown or expired beacon token' USING ERRCODE='22023'; END IF;
   114	
   115	  INSERT INTO public.sightings AS s (
   116	    observer_user_id, observed_token, observed_user_id, received_at,
   117	    rssi, observed_at, observer_lat, observer_lon, range_type, observer_accuracy_m
   118	  ) VALUES (
   119	    v_uid, lower(p_observed_token), v_observed_uid, v_now,
   120	    p_rssi, p_observed_at, p_lat, p_lon, v_range, p_accuracy
   121	  )
   122	  ON CONFLICT (observer_user_id, observed_token) DO UPDATE
   123	    SET observed_at = p_observed_at, received_at = v_now, observed_user_id = v_observed_uid,
   124	        rssi = CASE WHEN p_rssi > s.rssi THEN p_rssi ELSE s.rssi END,
   125	        observer_lat = CASE WHEN p_rssi > s.rssi THEN p_lat ELSE s.observer_lat END,
   126	        observer_lon = CASE WHEN p_rssi > s.rssi THEN p_lon ELSE s.observer_lon END,
   127	        observer_accuracy_m = CASE WHEN p_rssi > s.rssi THEN p_accuracy ELSE s.observer_accuracy_m END,
   128	        range_type = CASE WHEN p_rssi > s.rssi THEN v_range ELSE s.range_type END
   129	  RETURNING id INTO v_id;
   130	
   131	  v_window := LEAST(30, public.range_time_window_minutes(v_range));
   132	  IF v_range::TEXT LIKE 'feet_%' THEN
   133	    SELECT h.accuracy_m INTO v_claim_acc FROM public.token_claim_history h WHERE h.token = lower(p_observed_token) ORDER BY h.valid_from DESC LIMIT 1;
   134	    v_radius := public.gps_veto_radius_meters(p_accuracy, v_claim_acc);
   135	  ELSE v_radius := GREATEST(5.0, public.range_radius_meters(v_range)); END IF;
   136	
   137	  PERFORM public.correlate_encounter(lower(p_observed_token), p_lat, p_lon, v_radius, v_window);
   138	  RETURN v_id;
   139	END;
   140	$function$;
   141	
   142	-- ---------------------------------------------------------------------------
   143	-- correlate_encounter: gate 3 (+ the same claim grace, + a valid_from floor
   144	-- that can never exclude a late-window-valid claim). Verbatim 0030 body
   145	-- except the three window expressions.
   146	-- ---------------------------------------------------------------------------
   147	CREATE OR REPLACE FUNCTION public.correlate_encounter(
   148	  p_observed_token TEXT, p_lat DOUBLE PRECISION, p_lon DOUBLE PRECISION,
   149	  p_radius_meters DOUBLE PRECISION DEFAULT 50, p_time_window_minutes INT DEFAULT 60
   150	)
   151	RETURNS TABLE (encounter_id BIGINT, other_user_id UUID, created_new BOOLEAN)
   152	LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
   153	AS $$
   154	DECLARE
   155	  v_uid UUID := auth.uid(); v_claim public.token_claim_history%ROWTYPE;
   156	  v_user_a UUID; v_user_b UUID; v_enc_id BIGINT;
   157	  v_distance DOUBLE PRECISION; v_rssi INTEGER; v_min_rssi INTEGER;
   158	  v_new BOOLEAN := FALSE; v_sight_range public.range_type; v_band public.range_type;
   159	  v_reverse_band public.range_type; v_now TIMESTAMPTZ := NOW();
   160	  v_late INTERVAL := public.late_evidence_window();
   161	  v_late_min INT := (EXTRACT(EPOCH FROM public.late_evidence_window()) / 60)::INT;
   162	BEGIN
   163	  IF v_uid IS NULL OR NOT public.current_user_can_discover() THEN RETURN; END IF;
   164	  SELECT * INTO v_claim FROM public.token_claim_history tc
   165	  WHERE tc.token = lower(p_observed_token) AND tc.user_id <> v_uid
   166	    -- Floor so a late-window-valid, end-of-life token is never excluded
   167	    -- (token life <=21 min + late window; +2 slack). valid_until is the gate.
   168	    AND tc.valid_from > NOW() - make_interval(mins => GREATEST(23 + v_late_min, LEAST(30, GREATEST(1, p_time_window_minutes))))
   169	    AND tc.valid_until > NOW() - v_late ORDER BY tc.valid_from DESC LIMIT 1;
   170	  IF NOT FOUND OR NOT public.is_discoverable_user(v_claim.user_id) THEN RETURN; END IF;
   171	  IF public.is_blocked_pair(v_uid, v_claim.user_id) THEN RETURN; END IF;
   172	
   173	  SELECT s.rssi, s.range_type INTO v_rssi, v_sight_range FROM public.sightings s
   174	  WHERE s.observer_user_id = v_uid AND s.observed_token = lower(p_observed_token)
   175	  ORDER BY s.observed_at DESC LIMIT 1;
   176	  v_min_rssi := CASE COALESCE(v_claim.range_type,'feet_10') WHEN 'feet_10' THEN -75 WHEN 'feet_20' THEN -85 ELSE -95 END;
   177	  IF v_rssi IS NULL OR v_rssi < v_min_rssi THEN RETURN; END IF;
   178	
   179	  IF p_lat IS NOT NULL AND p_lon IS NOT NULL AND v_claim.approx_lat IS NOT NULL AND v_claim.approx_lon IS NOT NULL THEN
   180	    v_distance := ST_Distance(ST_SetSRID(ST_MakePoint(p_lon, p_lat),4326)::geography, ST_SetSRID(ST_MakePoint(v_claim.approx_lon, v_claim.approx_lat),4326)::geography);
   181	    IF v_distance > LEAST(400.0, GREATEST(5.0, p_radius_meters)) THEN RETURN; END IF;
   182	  END IF;
   183	
   184	  IF v_sight_range IS NOT NULL AND v_sight_range::TEXT LIKE 'feet_%' THEN v_band := v_sight_range; ELSE v_band := COALESCE(v_claim.range_type, 'feet_10'); END IF;
   185	
   186	  -- Reciprocity gate (server-receipt window; caller-supplied values ignored).
   187	  -- 0053: widened from a fixed 3 min — the other side's evidence may be a
   188	  -- locked phone's wake-burst upload from earlier in the same co-presence.
   189	  SELECT rs.range_type INTO v_reverse_band FROM public.sightings rs
   190	  WHERE rs.observer_user_id = v_claim.user_id AND rs.observed_user_id = v_uid
   191	    AND rs.received_at > NOW() - v_late
   192	  ORDER BY rs.received_at DESC LIMIT 1;
   193	  IF NOT FOUND THEN RETURN; END IF;
   194	
   195	  IF v_reverse_band IS NOT NULL AND v_reverse_band::TEXT LIKE 'feet_%' AND v_band::TEXT LIKE 'feet_%'
   196	     AND public.range_band_rank(v_reverse_band) > public.range_band_rank(v_band) THEN
   197	    v_band := v_reverse_band;
   198	  END IF;
   199	
   200	  v_user_a := LEAST(v_uid, v_claim.user_id); v_user_b := GREATEST(v_uid, v_claim.user_id);
   201	  PERFORM pg_advisory_xact_lock(hashtextextended(v_user_a::TEXT || v_user_b::TEXT, 0));
   202	  PERFORM public.bump_encounter_pair(v_user_a, v_user_b, v_band);
   203	  UPDATE public.encounter_pairs SET trust_level = COALESCE(trust_level, 'mutual_ble')
   204	    WHERE user_a = v_user_a AND user_b = v_user_b;
   205	
   206	  SELECT id INTO v_enc_id FROM public.encounters WHERE user_a = v_user_a AND user_b = v_user_b AND status = 'active' ORDER BY encounter_time DESC LIMIT 1 FOR UPDATE;
   207	  IF v_enc_id IS NULL THEN
   208	    INSERT INTO public.encounters (user_a,user_b,neighborhood,encounter_time,last_seen_at,range_type,confidence,status,trust_level)
   209	    VALUES (v_user_a,v_user_b,'Near you',v_now,v_now,v_band,0.8,'active','mutual_ble') RETURNING id INTO v_enc_id; v_new := TRUE;
   210	  ELSE
   211	    UPDATE public.encounters e SET last_seen_at = v_now, trust_level = COALESCE(e.trust_level,'mutual_ble'),
   212	      range_type = CASE WHEN e.range_type::TEXT LIKE 'feet_%' AND v_band::TEXT LIKE 'feet_%' AND public.range_band_rank(v_band) < public.range_band_rank(e.range_type) THEN v_band ELSE e.range_type END
   213	    WHERE e.id = v_enc_id;
   214	  END IF;
   215	  encounter_id := v_enc_id; other_user_id := v_claim.user_id; created_new := v_new; RETURN NEXT;
   216	END;
   217	$$;
  2200	    // Raw per-advert persistence + verbose peer logging is CALIBRATION only.
  2201	    // In production it would retain a place/peer fingerprint and print peer
  2202	    // ids to release logs / bug reports (reviewer #18).
  2203	    if (AppConfig.calibScanMode) {
  2204	      try {
  2205	        onAdvertSample?.call(hexId, rssi, power, at ?? DateTime.now());
  2206	      } catch (e) {
  2207	        debugPrint('onAdvertSample callback error: $e');
  2208	      }
  2209	      // One line per fresh foreign advert — the calibration ground truth. The
  2210	      // per-advert RSSI is already here, so W6 only adds the two things missing:
  2211	      // the receiver tag (logged once per process in _logRadioCapabilities) and
  2212	      // a 5 dBm-binned distribution per window, which is the shape Herald's
  2213	      // self-calibration finding (A9/B9) needs and which is not recoverable
  2214	      // after the walk.
  2215	      _bumpBin(_rssiHist, (rssi / 5).floor() * 5);
  2216	      debugPrint(
  2217	          'Advert corr=${hexId.substring(0, 8)} rssi=$rssi pw=${power == AdvertPower.medium ? "M" : "H"} rx=$_receiverTag');
  2218	    }
  2219	
  2220	    _lastForeignScanAt = DateTime.now();
  2221	    _recordLocalSighting(hexId, rssi, at: at);
  2222	  }
  2223	
  2224	  double? _cachedLat;
  2225	  double? _cachedLon;
  2226	  double? _cachedAccuracy;
  2227	  DateTime? _cachedLocAt;
  2228	  Timer? _locationRefreshTimer;
  2229	
  2230	  final Map<String, DateTime> _lastSightingAt = {};
  2231	  static const _sightingMinInterval = Duration(seconds: 5);
  2232	
  2233	  void _recordLocalSighting(String observedCorrelationIdHex, int rssi,
  2234	      {DateTime? at}) {
  2235	    final now = DateTime.now();
  2236	    final last = _lastSightingAt[observedCorrelationIdHex];
  2237	    if (last != null && now.difference(last) < _sightingMinInterval) {
  2238	      return;
  2239	    }
  2240	    _lastSightingAt[observedCorrelationIdHex] = now;
  2241	    if (_lastSightingAt.length > 1000) {
  2242	      _lastSightingAt.removeWhere(
  2243	        (_, at) => now.difference(at) > const Duration(minutes: 10),
  2244	      );
  2245	      while (_lastSightingAt.length > 1000) {
  2246	        _lastSightingAt.remove(_lastSightingAt.keys.first);
  2247	      }
  2248	    }
  2249	
  2250	    _ensureLocationCache();
  2251	
  2252	    final range = _currentRangeType ?? 'feet_10';
  2253	    // Uploaded sightings carry the ESTIMATED band, not the fixed beacon
  2254	    // range — the server derives encounter bands from it (migration 0022).
  2255	    final estimated = rangeEstimator.classify(observedCorrelationIdHex);
  2256	    final uploadRange = (range.startsWith('feet') && estimated != 'none')
  2257	        ? estimated
  2258	        : range;
  2259	    final record = SightingRecord(
  2260	      observedToken: observedCorrelationIdHex,
  2261	      rssi: rssi,
  2262	      observerLat: _cachedLat,
  2263	      observerLon: _cachedLon,
  2264	      observerAccuracyM: _cachedAccuracy,
  2265	      // A locked iPhone's natively-buffered sighting flushes minutes after
  2266	      // capture; the server (0053) accepts and stores the TRUE capture time,
  2267	      // so pass it through instead of the flush time.
  2268	      observedAt: at ?? now,
  2269	      rangeType: uploadRange,
  2270	    );
  2271	
  2272	    // Keep one COHERENT best-evidence record per corr: RSSI, band, time,
  2273	    // location and accuracy all come from the SAME physical sample. Previously
  2274	    // the strongest RSSI was stitched onto the latest sample's time/coords/band
  2275	    // — an observation that never happened, which could pass the server RSSI
  2276	    // gate on old strength but store an unrelated location/band (reviewer #12).
  2277	    final prev = _pendingByCorr[observedCorrelationIdHex];
  2278	    if (prev == null && _pendingByCorr.length >= _maxPendingSightings) {
  2279	      _pendingByCorr.remove(_pendingByCorr.keys.first);
  2280	    }
  2281	    // Replace only when this sample is strictly stronger; otherwise keep the
  2282	    // existing coherent record untouched.
  2283	    //
  2284	    // ...with one exception: a record with no coordinates can never be sent.
  2285	    // _ensureLocationCache() above is fire-and-forget (a Timer plus up to 6 s
  2286	    // in getCurrentPosition) and turnOnBeacon does not await it, so sightings
  2287	    // observed in the first seconds of a session are built with a null
  2288	    // observerLat/observerLon. _flushSightings skips those records (they fail
  2289	    // record_sighting's required lat/lon) but only REMOVES a record after a
  2290	    // successful send — so without this clause a strong early sighting sticks
  2291	    // in _pendingByCorr forever: never uploadable because it has no
  2292	    // coordinates, never replaced because no later sample beats its RSSI, and
  2293	    // holding one of the _maxPendingSightings slots until FIFO eviction.
  2294	    // The peer is simply never reported, which reads as "it didn't detect me"
  2295	    // at exactly the moment a user is watching. Found by audit 2026-07-25.
  2296	    //
  2297	    // Coherence (reviewer #12) is preserved: we swap in a whole later sample
  2298	    // rather than stitching coordinates onto an older one.
  2299	    final prevUnusable =
  2300	        prev != null && (prev.observerLat == null || prev.observerLon == null);
  2301	    final thisUsable = record.observerLat != null && record.observerLon != null;
  2302	    if (prev == null || rssi > prev.rssi || (prevUnusable && thisUsable)) {
  2303	      _pendingByCorr[observedCorrelationIdHex] = record;
  2304	    }
  2305	
  2306	    final band = estimated;
  2307	    debugPrint(
  2308	        'Sighting observed rssi=$rssi band=$band (tracked=${_pendingByCorr.length})');
  2309	
  2310	    // Local encounter store (instant or delayed reveal).
  2311	    try {
  2312	      onSighting?.call(
  2313	        correlationId: observedCorrelationIdHex,
  2314	        rssi: rssi,
  2315	        rangeType: range,
  2316	        estimatedBand: band,
  2317	      );
  2318	    } catch (e) {
  2319	      debugPrint('onSighting callback error: $e');
  2320	    }
  2321	  }
  2322	
  2323	  /// Calibration ground truth for the GPS layer. Coordinates are logged only
  2324	  /// when INRANGE_CALIB_SCAN is set (our own test phones): comparing the two
  2325	  /// phones' fixes is the ONLY way to measure what the GPS veto is really
  2326	  /// doing, and accuracy alone cannot do it. Production logs accuracy only.
  2327	  void _logGpsFix(Position p, {String? tag}) {
  2328	    final suffix = tag == null ? '' : ' ($tag)';
  2329	    if (AppConfig.calibScanMode) {
  2330	      debugPrint('GpsFix lat=${p.latitude.toStringAsFixed(6)} '
  2331	          'lon=${p.longitude.toStringAsFixed(6)} '
  2332	          'acc=${p.accuracy.toStringAsFixed(1)}m$suffix');
  2333	    } else {
  2334	      debugPrint('GpsFix acc=${p.accuracy.toStringAsFixed(1)}m$suffix');
  2335	    }
  2380	    final maxAge = AppConfig.calibScanMode
  2381	        ? const Duration(seconds: 30)
  2382	        : const Duration(seconds: 120);
  2383	    final stale =
  2384	        _cachedLocAt == null || DateTime.now().difference(_cachedLocAt!) > maxAge;
  2385	    if (!stale) return;
  2386	    if (_locationRefreshTimer != null) return;
  2387	    _locationRefreshTimer = Timer(Duration.zero, () async {
  2388	      try {
  2389	        // Calibration takes a REAL fix every time. getLastKnownPosition can
  2390	        // keep re-serving a stale coarse fix (observed: one phone stuck at
  2391	        // 100 m while the other resolved to 15 m), which would make half the
  2392	        // GPS data worthless. Production still prefers the cached fix — it is
  2393	        // only feeding a coarse plausibility veto and battery matters more.
  2394	        Position? pos = AppConfig.calibScanMode
  2395	            ? null
  2396	            : await Geolocator.getLastKnownPosition();
  2397	        if (pos == null || !_isFreshPosition(pos)) {
  2398	          // Calibration walks request a real fix (sub-5 m outdoors) so we can
  2399	          // measure GPS's actual error against known distances. Production
  2400	          // stays on low accuracy — GPS is only a coarse plausibility veto,
  2401	          // and a high-accuracy fix is not worth the battery for that job.
  2402	          pos = await Geolocator.getCurrentPosition(
  2403	            locationSettings: LocationSettings(
  2404	              accuracy: AppConfig.calibScanMode
  2405	                  ? LocationAccuracy.high
  2406	                  : LocationAccuracy.low,
  2407	              timeLimit: const Duration(seconds: 6),
  2408	            ),
  2409	          );
  2410	        }
  2411	        _cachedLat = pos.latitude;
  2412	        _cachedLon = pos.longitude;
  2413	        _cachedAccuracy = pos.accuracy;
  2414	        _cachedLocAt = DateTime.now();
  2415	        // Android's accuracy figure is a 68%-confidence radius — ~1 fix in 3
  2416	        // is worse than it claims — and indoors it degrades to tens of metres.
  2417	        // Log it: it is the input to the server's correlation radius gate.
  2418	        //
  2419	        // Coordinates are logged ONLY in calibration mode, and only on our own
  2420	        // test phones: without them the two phones' fixes cannot be compared,
  2421	        // so the GPS layer could not be evaluated at all. Never in production.
  2422	        _logGpsFix(pos);
  2423	      } catch (e) {
  2424	        debugPrint('Location cache refresh failed: $e');
  2425	      } finally {
  2426	        _locationRefreshTimer = null;
  2427	      }
  2428	    });
  2429	  }
  2430	
  2431	  String? _currentRangeType;
  2432	
  2433	  /// Fire-and-forget drain of the calibration upload queue.
  2434	  ///
  2435	  /// Swallows everything on purpose. The rows are already durable in SQLite and
  2436	  /// the watermark only advances on server acknowledgement, so a failure here
  2437	  /// costs nothing but a delay — whereas letting it escape would take down the
  2438	  /// flush timer and, on the stop path, the BLE teardown that follows it.
  2439	  Future<void> _flushUploads() async {
  2440	    final flush = onFlushUploads;
  2441	    if (flush == null) return;
  2442	    try {
  2443	      await flush();
  2444	    } catch (e) {
  2445	      debugPrint('RSSI upload flush failed (will retry): $e');
  2446	    }
  2447	  }
  2448	
  2449	  Future<void> _flushSightings() async {
  2450	    if (_pendingByCorr.isEmpty) return;
  2451	    if (!AppConfig.hasRealSupabase) {
  2452	      // Keep local rows; no network thrash against placeholder host.
  2453	      return;
  2454	    }
  2455	
  2456	    final toSend = List<SightingRecord>.from(_pendingByCorr.values);
  2457	
  2458	    for (final s in toSend) {
  2459	      if (s.observerLat == null || s.observerLon == null) continue;
  2460	      try {
  2461	        // Named args match migration signatures (lat/lon required before optionals).
  2462	        await InRangeSupabase.client.rpc('record_sighting', params: {
  2463	          'p_observed_token':
  2464	              s.observedToken, // correlation-id hex (matches claim)
  2465	          'p_lat': s.observerLat,
  2466	          'p_lon': s.observerLon,
  2467	          'p_rssi': s.rssi,
  2468	          'p_observed_at': s.observedAt.toUtc().toIso8601String(),
  2469	          'p_range': _mapUiRangeToDb(s.rangeType),
  2470	          // Sizes the server's GPS plausibility veto from real uncertainty
  2471	          // instead of a fixed guess (migration 0024).
  2472	          'p_accuracy': s.observerAccuracyM,
  2473	        }).timeout(const Duration(seconds: 10));
  2474	        debugPrint('record_sighting OK rssi=${s.rssi}');
  2475	        if (identical(_pendingByCorr[s.observedToken], s)) {
  2476	          _pendingByCorr.remove(s.observedToken);
  2477	        }
  2478	      } catch (e) {
  2479	        debugPrint('Sighting upload failed: $e');
  2480	        // Retain for a later bounded retry; the queue is capped above.
  2481	      }
  2482	    }
  2483	  }
  2484	
  2485	  Future<void> _refreshClaim({required String rangeType}) async {
  2486	    _currentToken = await _tokenSource.nextToken();
  2487	    _currentCorrelationId = _hexTo16Bytes(_currentToken!.token);
  2488	    // Remember every token we advertise so the scanner never self-sights a
  2489	    // stale one (leaked advertiser after off→on). Bounded to stay tiny.
  2490	    _ownCorrHexes.add(_currentCorrelationId!
  2491	        .map((b) => b.toRadixString(16).padLeft(2, '0'))
  2492	        .join());
  2493	    if (_ownCorrHexes.length > 16) {
  2494	      _ownCorrHexes.remove(_ownCorrHexes.first);
  2495	    }
  2496	
  2497	    // Reuse the cached fix only if it is still fresh. Without the age check a
  2498	    // user who travels >400 m without seeing a peer keeps claiming their
  2499	    // ORIGIN, and the server's 400 m veto then rejects the real encounter at
  2500	    // the new location (reviewer #7).
  2501	    final cacheAge = _cachedLocAt == null
  2502	        ? null
  2503	        : DateTime.now().difference(_cachedLocAt!);
  2504	    final cacheFresh = cacheAge != null &&
  2505	        cacheAge <= const Duration(minutes: 2);
  2506	    double? lat = cacheFresh ? _cachedLat : null;
  2507	    double? lon = cacheFresh ? _cachedLon : null;
  2508	    if (lat == null) {
  2509	      try {
  2510	        Position? position = AppConfig.calibScanMode
  2511	            ? null
  2512	            : await Geolocator.getLastKnownPosition();
  2513	        if (position == null || !_isFreshPosition(position)) {
  2514	          position = await Geolocator.getCurrentPosition(
  2515	            locationSettings: LocationSettings(
  2516	              accuracy: AppConfig.calibScanMode
  2517	                  ? LocationAccuracy.high
  2518	                  : LocationAccuracy.low,
  2519	              timeLimit: const Duration(seconds: 5),
  2520	            ),
  2521	          );
  2522	        }
  2523	        lat = position.latitude;
  2524	        lon = position.longitude;
  2525	        _cachedLat = lat;
  2526	        _cachedLon = lon;
  2527	        _cachedAccuracy = position.accuracy;
  2528	        _cachedLocAt = DateTime.now();
  2529	        _logGpsFix(position, tag: 'claim');
  2530	      } catch (e) {
  2531	        debugPrint('Geolocator failed at claim time: $e');
  2532	      }
  2533	    }
  2534	
  2535	    // A new token supersedes any pending retry of the previous claim.
  2536	    final gen = _claimMgr.newSession();
  2537	    _claimRangeType = rangeType;
  2538	    _cachedLat = lat;
  2539	    _cachedLon = lon;
  2540	
  2541	    // Publish the new token's expiry immediately, even before the claim RPC
  2542	    // resolves, so the UI countdown tracks the current token (reviewer #11).
  2543	    onClaimStateChanged?.call(
  2544	        _currentToken!.expiresAt, AppConfig.hasRealSupabase ? _cloudClaimed : null);
  2545	
  2546	    if (!AppConfig.hasRealSupabase) {
  2547	      _cloudClaimed = false;
  2548	      debugPrint('claim_token skipped (no real Supabase — local BLE mode)');
  2549	      return;
  2550	    }
  2551	
  2552	    // Pre-claim the whole issued batch (0060) so tokens the native carrier
  2553	    // serves while Dart is suspended or evicted still resolve server-side.
  2554	    // Self-throttled — fires at session start and day rollover, not per
  2555	    // rotation. Runs before the single claim so its 1-minute throttle never
  2556	    // trips on a fresh single-claim row.
  2557	    unawaited(_preclaimBatch());
  2558	
  2559	    // Retries the SAME live token with bounded backoff; ClaimManager fires
  2560	    // onState (→ onClaimStateChanged) after every attempt.
  2561	    await _claimMgr.attempt(gen);
  2562	  }
  2563	
  2564	  DateTime? _lastBatchPreclaim;
  2565	
  2566	  /// One claim_token_batch RPC per 6 h (migration 0060): makes every slot
  2567	  /// the native iOS carrier can serve resolvable through token_claim_history
  2568	  /// while Dart is suspended. Failures are swallowed — the live per-rotation
  2569	  /// claim still covers the current slot; the pre-claim is the safety net.
  2570	  /// The backoff timestamp is set only on SUCCESS: a failed attempt must not
  2571	  /// suppress the retry due on the next rotation.
  2572	  Future<void> _preclaimBatch() async {
  2573	    final now = DateTime.now();
  2574	    final last = _lastBatchPreclaim;
  2575	    if (last != null && now.difference(last) < const Duration(hours: 6)) {
  2576	      return;
  2577	    }
  2578	    try {
  2579	      await InRangeSupabase.client.rpc('claim_token_batch', params: {
  2580	        'p_range': _mapUiRangeToDb(_claimRangeType ?? 'feet_60'),
  2581	      }).timeout(const Duration(seconds: 10));
  2582	      _lastBatchPreclaim = now;
  2583	      debugPrint('claim_token_batch OK');
  2584	    } catch (e) {
  2585	      debugPrint('claim_token_batch failed: $e');
  2586	    }
  2587	  }
  2588	
  2589	  /// One claim_token RPC for the current token/location. Throws on failure so
  2590	  /// ClaimManager retries; a location refresh is nudged for the next attempt.
  2591	  Future<void> _uploadClaim() async {
  2592	    if (_currentToken == null || _currentCorrelationId == null) {
  2593	      throw StateError('no token to claim');
  2594	    }
  2595	    _ensureLocationCache();
  2596	    final claimToken = _currentCorrelationId!
  2597	        .map((b) => b.toRadixString(16).padLeft(2, '0'))
  2598	        .join();
  2599	    // Always send UTC — a local DateTime without offset is misread as UTC by
  2600	    // Postgres and expires claims hours early (broke feet correlation once).
  2601	    final until = _currentToken!.expiresAt.toUtc().add(const Duration(minutes: 2));
  2602	    // Timeout: a hanging claim (dead network) must fail the attempt so
  2603	    // ClaimManager's bounded retry + the "Local BLE only" fallback engage,
  2604	    // instead of wedging the whole beacon-on flow (S22 2026-07-23).
  2605	    await InRangeSupabase.client.rpc('claim_token', params: {
  2606	      'p_token': claimToken,
  2607	      'p_valid_until': until.toIso8601String(),
  2608	      'p_lat': _cachedLat,
  2609	      'p_lon': _cachedLon,
  2610	      'p_range': _mapUiRangeToDb(_claimRangeType ?? 'feet_60'),
  2611	      'p_accuracy': _cachedAccuracy,
  2612	    }).timeout(const Duration(seconds: 10));
  2613	    debugPrint('claim_token OK until=${until.toIso8601String()}');
  2614	  }
  2615	
  2616	  bool _isFreshPosition(Position position) {
  2617	    final age = DateTime.now().difference(position.timestamp).abs();
  2618	    return age <= const Duration(minutes: 2);
  2619	  }
  2620	
  2621	  Future<void> _releaseClaim() async {
  2622	    _cloudClaimed = false;
  2623	    if (!AppConfig.hasRealSupabase) return;
  2624	    try {
  2625	      await InRangeSupabase.client
  2626	          .rpc('release_token')
  2627	          .timeout(const Duration(seconds: 8));
  2628	    } catch (e) {
  2629	      debugPrint('release_token failed: $e');
  2630	    }
  2631	  }
  2632	
  2633	  String _mapUiRangeToDb(String uiRange) {
  2634	    if (uiRange == 'feet') return 'feet_10';
  2635	    if (uiRange == 'miles') return 'miles_10';
  2636	    return uiRange;
  2637	  }
  2638	}
  2639	
  2640	class SightingRecord {
  2641	  const SightingRecord({
  2642	    required this.observedToken,
  2643	    required this.rssi,
  2644	    required this.observedAt,
  2645	    required this.observerLat,
    95	    } catch (e) {
    96	      debugPrint('swipe_user: $e');
    97	      rethrow;
    98	    }
    99	  }
   100	
   101	  Future<int?> recordLocationPing({
   102	    required double lat,
   103	    required double lon,
   104	    String range = 'miles_10',
   105	    String? neighborhood,
   106	  }) async {
   107	    if (!cloudReady) return null;
   108	    try {
   109	      final id = await InRangeSupabase.client.rpc(
   110	        'record_location_ping',
   111	        params: {
   112	          'p_lat': lat,
   113	          'p_lon': lon,
   114	          'p_range': range,
   115	          'p_neighborhood': neighborhood,
   116	        },
   117	      );
   118	      return id is int ? id : int.tryParse('$id');
   119	    } catch (e) {
   120	      debugPrint('record_location_ping: $e');
   121	      rethrow;
   122	    }
   123	  }
   124	
   125	  Future<void> claimToken({
   126	    required String token,
   127	    required DateTime validUntil,
   128	    double? lat,
   129	    double? lon,
   130	    String range = 'feet_10',
   131	  }) async {
   132	    if (!cloudReady) return;
   133	    try {
   134	      await InRangeSupabase.client.rpc('claim_token', params: {
   135	        'p_token': token,
   136	        'p_valid_until': validUntil.toUtc().toIso8601String(),
   137	        'p_lat': lat,
   138	        'p_lon': lon,
   139	        'p_range': range,
   140	      });
   141	    } catch (e) {
   142	      debugPrint('claim_token: $e');
   143	    }
   144	  }
   145	
   146	  Future<void> recordSighting({
   147	    required String observedToken,
   148	    int? rssi,
   149	    DateTime? observedAt,
   150	    double? lat,
   151	    double? lon,
   152	    String? range,
   153	  }) async {
   154	    if (!cloudReady) return;
   155	    try {
   156	      await InRangeSupabase.client.rpc('record_sighting', params: {
   157	        'p_observed_token': observedToken,
   158	        'p_rssi': rssi,
   159	        'p_observed_at':
   160	            (observedAt ?? DateTime.now()).toUtc().toIso8601String(),
   161	        'p_lat': lat,
   162	        'p_lon': lon,
   163	        'p_range': range,
   164	      });
   165	    } catch (e) {
   166	      debugPrint('record_sighting: $e');
   167	    }
   168	  }
   169	
   170	  Future<List<Map<String, dynamic>>> getMyMatches() async {
   171	    if (!cloudReady) return [];
   172	    try {
   173	      final response = await InRangeSupabase.client.rpc(
   174	        'get_my_matches',
   175	        params: {'p_limit': 50, 'p_offset': 0},
   176	      );
   177	      return List<Map<String, dynamic>>.from(response as List? ?? []);
   178	    } catch (e) {
   179	      debugPrint('get_my_matches: $e');
   180	      rethrow;
   181	    }
   182	  }
   183	
   184	  /// Returns server message id. Throws on failure so UI can roll back optimistic send.
   185	  Future<int> sendMessage({
supabase/migrations/0008_miles_correlation.sql-397-    RAISE EXCEPTION 'Not authenticated';
supabase/migrations/0008_miles_correlation.sql-398-  END IF;
supabase/migrations/0008_miles_correlation.sql-399-
supabase/migrations/0008_miles_correlation.sql-400-  v_range := COALESCE(p_range, 'feet_10');
supabase/migrations/0008_miles_correlation.sql-401-
supabase/migrations/0008_miles_correlation.sql:402:  INSERT INTO public.sightings (
supabase/migrations/0008_miles_correlation.sql-403-    observer_user_id,
supabase/migrations/0008_miles_correlation.sql-404-    observed_token,
supabase/migrations/0008_miles_correlation.sql-405-    rssi,
supabase/migrations/0008_miles_correlation.sql-406-    observed_at,
supabase/migrations/0008_miles_correlation.sql-407-    observer_lat,
supabase/migrations/0003_correlation_fixes.sql-145-BEGIN
supabase/migrations/0003_correlation_fixes.sql-146-  IF v_user_id IS NULL THEN
supabase/migrations/0003_correlation_fixes.sql-147-    RAISE EXCEPTION 'Not authenticated';
supabase/migrations/0003_correlation_fixes.sql-148-  END IF;
supabase/migrations/0003_correlation_fixes.sql-149-
supabase/migrations/0003_correlation_fixes.sql:150:  INSERT INTO public.sightings (
supabase/migrations/0003_correlation_fixes.sql-151-    observer_user_id,
supabase/migrations/0003_correlation_fixes.sql-152-    observed_token,
supabase/migrations/0003_correlation_fixes.sql-153-    rssi,
supabase/migrations/0003_correlation_fixes.sql-154-    observed_at,
supabase/migrations/0003_correlation_fixes.sql-155-    observer_lat,
supabase/migrations/0053_late_evidence_tolerance.sql-110-  -- must not generate new location-correlated evidence.
supabase/migrations/0053_late_evidence_tolerance.sql-111-  IF public.consent_withdrawn(v_observed_uid, 'ble_proximity')
supabase/migrations/0053_late_evidence_tolerance.sql-112-     OR public.consent_withdrawn(v_observed_uid, 'precise_location') THEN
supabase/migrations/0053_late_evidence_tolerance.sql-113-    RAISE EXCEPTION 'Unknown or expired beacon token' USING ERRCODE='22023'; END IF;
supabase/migrations/0053_late_evidence_tolerance.sql-114-
supabase/migrations/0053_late_evidence_tolerance.sql:115:  INSERT INTO public.sightings AS s (
supabase/migrations/0053_late_evidence_tolerance.sql-116-    observer_user_id, observed_token, observed_user_id, received_at,
supabase/migrations/0053_late_evidence_tolerance.sql-117-    rssi, observed_at, observer_lat, observer_lon, range_type, observer_accuracy_m
supabase/migrations/0053_late_evidence_tolerance.sql-118-  ) VALUES (
supabase/migrations/0053_late_evidence_tolerance.sql-119-    v_uid, lower(p_observed_token), v_observed_uid, v_now,
supabase/migrations/0053_late_evidence_tolerance.sql-120-    p_rssi, p_observed_at, p_lat, p_lon, v_range, p_accuracy
supabase/migrations/0019_beta_security_hardening.sql-950-    AND observed_at > v_now - INTERVAL '30 seconds'
supabase/migrations/0019_beta_security_hardening.sql-951-  ORDER BY observed_at DESC
supabase/migrations/0019_beta_security_hardening.sql-952-  LIMIT 1;
supabase/migrations/0019_beta_security_hardening.sql-953-
supabase/migrations/0019_beta_security_hardening.sql-954-  IF v_id IS NULL THEN
supabase/migrations/0019_beta_security_hardening.sql:955:    INSERT INTO public.sightings (
supabase/migrations/0019_beta_security_hardening.sql-956-      observer_user_id, observed_token, rssi, observed_at,
supabase/migrations/0019_beta_security_hardening.sql-957-      observer_lat, observer_lon, range_type
supabase/migrations/0019_beta_security_hardening.sql-958-    ) VALUES (
supabase/migrations/0019_beta_security_hardening.sql-959-      v_uid, lower(p_observed_token), p_rssi, p_observed_at,
supabase/migrations/0019_beta_security_hardening.sql-960-      p_lat, p_lon, v_range
supabase/migrations/0019_beta_security_hardening.sql-961-    ) RETURNING id INTO v_id;
supabase/migrations/0019_beta_security_hardening.sql-962-  ELSE
supabase/migrations/0019_beta_security_hardening.sql:963:    UPDATE public.sightings
supabase/migrations/0019_beta_security_hardening.sql-964-    SET rssi = GREATEST(rssi, p_rssi), observed_at = p_observed_at,
supabase/migrations/0019_beta_security_hardening.sql-965-        observer_lat = COALESCE(p_lat, observer_lat),
supabase/migrations/0019_beta_security_hardening.sql-966-        observer_lon = COALESCE(p_lon, observer_lon),
supabase/migrations/0019_beta_security_hardening.sql-967-        range_type = v_range
supabase/migrations/0019_beta_security_hardening.sql-968-    WHERE id = v_id;
supabase/migrations/0028_token_claim_history.sql-138-    SELECT 1 FROM public.token_claim_history h
supabase/migrations/0028_token_claim_history.sql-139-    WHERE h.token = lower(p_observed_token) AND h.user_id <> v_uid
supabase/migrations/0028_token_claim_history.sql-140-      AND h.valid_until > v_now - INTERVAL '2 minutes'
supabase/migrations/0028_token_claim_history.sql-141-  ) THEN RAISE EXCEPTION 'Unknown or expired beacon token' USING ERRCODE='22023'; END IF;
supabase/migrations/0028_token_claim_history.sql-142-
supabase/migrations/0028_token_claim_history.sql:143:  INSERT INTO public.sightings AS s (observer_user_id, observed_token, rssi, observed_at, observer_lat, observer_lon, range_type, observer_accuracy_m)
supabase/migrations/0028_token_claim_history.sql-144-  VALUES (v_uid, lower(p_observed_token), p_rssi, p_observed_at, p_lat, p_lon, v_range, p_accuracy)
supabase/migrations/0028_token_claim_history.sql-145-  ON CONFLICT (observer_user_id, observed_token) DO UPDATE
supabase/migrations/0028_token_claim_history.sql-146-    SET observed_at = p_observed_at,
supabase/migrations/0028_token_claim_history.sql-147-        rssi = CASE WHEN p_rssi > s.rssi THEN p_rssi ELSE s.rssi END,
supabase/migrations/0028_token_claim_history.sql-148-        observer_lat = CASE WHEN p_rssi > s.rssi THEN p_lat ELSE s.observer_lat END,
supabase/migrations/0011_record_sighting_single_sig.sql-36-    RAISE EXCEPTION 'Not authenticated';
supabase/migrations/0011_record_sighting_single_sig.sql-37-  END IF;
supabase/migrations/0011_record_sighting_single_sig.sql-38-
supabase/migrations/0011_record_sighting_single_sig.sql-39-  v_range := COALESCE(p_range, 'feet_10');
supabase/migrations/0011_record_sighting_single_sig.sql-40-
supabase/migrations/0011_record_sighting_single_sig.sql:41:  INSERT INTO public.sightings (
supabase/migrations/0011_record_sighting_single_sig.sql-42-    observer_user_id, observed_token, rssi, observed_at,
supabase/migrations/0011_record_sighting_single_sig.sql-43-    observer_lat, observer_lon, range_type
supabase/migrations/0011_record_sighting_single_sig.sql-44-  )
supabase/migrations/0011_record_sighting_single_sig.sql-45-  VALUES (
supabase/migrations/0011_record_sighting_single_sig.sql-46-    v_user_id, p_observed_token, p_rssi, p_observed_at,
supabase/migrations/0024_accuracy_aware_correlation.sql-92-    AND observed_at > v_now - INTERVAL '30 seconds'
supabase/migrations/0024_accuracy_aware_correlation.sql-93-  ORDER BY observed_at DESC
supabase/migrations/0024_accuracy_aware_correlation.sql-94-  LIMIT 1;
supabase/migrations/0024_accuracy_aware_correlation.sql-95-
supabase/migrations/0024_accuracy_aware_correlation.sql-96-  IF v_id IS NULL THEN
supabase/migrations/0024_accuracy_aware_correlation.sql:97:    INSERT INTO public.sightings (
supabase/migrations/0024_accuracy_aware_correlation.sql-98-      observer_user_id, observed_token, rssi, observed_at,
supabase/migrations/0024_accuracy_aware_correlation.sql-99-      observer_lat, observer_lon, range_type, observer_accuracy_m
supabase/migrations/0024_accuracy_aware_correlation.sql-100-    ) VALUES (
supabase/migrations/0024_accuracy_aware_correlation.sql-101-      v_uid, lower(p_observed_token), p_rssi, p_observed_at,
supabase/migrations/0024_accuracy_aware_correlation.sql-102-      p_lat, p_lon, v_range, p_accuracy
supabase/migrations/0024_accuracy_aware_correlation.sql-107-    -- stronger do we replace all of them together; otherwise we merely advance
supabase/migrations/0024_accuracy_aware_correlation.sql-108-    -- observed_at (a monotonic last-seen). Previously GREATEST(rssi) was pinned
supabase/migrations/0024_accuracy_aware_correlation.sql-109-    -- to the LATEST sample's location/band — an observation that never
supabase/migrations/0024_accuracy_aware_correlation.sql-110-    -- happened, which could pass the RSSI gate on old strength but store an
supabase/migrations/0024_accuracy_aware_correlation.sql-111-    -- unrelated GPS tuple/band (reviewer #12).
supabase/migrations/0024_accuracy_aware_correlation.sql:112:    UPDATE public.sightings
supabase/migrations/0024_accuracy_aware_correlation.sql-113-    SET observed_at = p_observed_at,
supabase/migrations/0024_accuracy_aware_correlation.sql-114-        rssi        = CASE WHEN p_rssi > rssi THEN p_rssi ELSE rssi END,
supabase/migrations/0024_accuracy_aware_correlation.sql-115-        observer_lat = CASE WHEN p_rssi > rssi THEN p_lat ELSE observer_lat END,
supabase/migrations/0024_accuracy_aware_correlation.sql-116-        observer_lon = CASE WHEN p_rssi > rssi THEN p_lon ELSE observer_lon END,
supabase/migrations/0024_accuracy_aware_correlation.sql-117-        observer_accuracy_m =
supabase/migrations/0026_sighting_idempotency_ratelimit.sql-17-  AND s.observed_token = s2.observed_token
supabase/migrations/0026_sighting_idempotency_ratelimit.sql-18-  AND (s.observed_at < s2.observed_at
supabase/migrations/0026_sighting_idempotency_ratelimit.sql-19-       OR (s.observed_at = s2.observed_at AND s.id < s2.id));
supabase/migrations/0026_sighting_idempotency_ratelimit.sql-20-
supabase/migrations/0026_sighting_idempotency_ratelimit.sql-21-CREATE UNIQUE INDEX IF NOT EXISTS uq_sightings_observer_token
supabase/migrations/0026_sighting_idempotency_ratelimit.sql:22:  ON public.sightings (observer_user_id, observed_token);
supabase/migrations/0026_sighting_idempotency_ratelimit.sql-23-
supabase/migrations/0026_sighting_idempotency_ratelimit.sql-24--- (2) Per-call rate counter -----------------------------------------------------
supabase/migrations/0026_sighting_idempotency_ratelimit.sql-25-CREATE TABLE IF NOT EXISTS public.sighting_call_rate (
supabase/migrations/0026_sighting_idempotency_ratelimit.sql-26-  user_id      UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
supabase/migrations/0026_sighting_idempotency_ratelimit.sql-27-  window_start TIMESTAMPTZ NOT NULL DEFAULT NOW(),
supabase/migrations/0026_sighting_idempotency_ratelimit.sql-105-  END IF;
supabase/migrations/0026_sighting_idempotency_ratelimit.sql-106-
supabase/migrations/0026_sighting_idempotency_ratelimit.sql-107-  -- Atomic upsert: one coherent best-evidence row per (observer, token). No
supabase/migrations/0026_sighting_idempotency_ratelimit.sql-108-  -- read-then-write race. observed_at always advances; RSSI/location/band swap
supabase/migrations/0026_sighting_idempotency_ratelimit.sql-109-  -- together only on a strictly stronger reading (reviewer #12 + #13).
supabase/migrations/0026_sighting_idempotency_ratelimit.sql:110:  INSERT INTO public.sightings AS s (
supabase/migrations/0026_sighting_idempotency_ratelimit.sql-111-    observer_user_id, observed_token, rssi, observed_at,
supabase/migrations/0026_sighting_idempotency_ratelimit.sql-112-    observer_lat, observer_lon, range_type, observer_accuracy_m
supabase/migrations/0026_sighting_idempotency_ratelimit.sql-113-  ) VALUES (
supabase/migrations/0026_sighting_idempotency_ratelimit.sql-114-    v_uid, lower(p_observed_token), p_rssi, p_observed_at,
supabase/migrations/0026_sighting_idempotency_ratelimit.sql-115-    p_lat, p_lon, v_range, p_accuracy
supabase/migrations/0048_gps_scope_and_retention.sql-141-  -- must not generate new location-correlated evidence.
supabase/migrations/0048_gps_scope_and_retention.sql-142-  IF public.consent_withdrawn(v_observed_uid, 'ble_proximity')
supabase/migrations/0048_gps_scope_and_retention.sql-143-     OR public.consent_withdrawn(v_observed_uid, 'precise_location') THEN
supabase/migrations/0048_gps_scope_and_retention.sql-144-    RAISE EXCEPTION 'Unknown or expired beacon token' USING ERRCODE='22023'; END IF;
supabase/migrations/0048_gps_scope_and_retention.sql-145-
supabase/migrations/0048_gps_scope_and_retention.sql:146:  INSERT INTO public.sightings AS s (
supabase/migrations/0048_gps_scope_and_retention.sql-147-    observer_user_id, observed_token, observed_user_id, received_at,
supabase/migrations/0048_gps_scope_and_retention.sql-148-    rssi, observed_at, observer_lat, observer_lon, range_type, observer_accuracy_m
supabase/migrations/0048_gps_scope_and_retention.sql-149-  ) VALUES (
supabase/migrations/0048_gps_scope_and_retention.sql-150-    v_uid, lower(p_observed_token), v_observed_uid, v_now,
supabase/migrations/0048_gps_scope_and_retention.sql-151-    p_rssi, p_observed_at, p_lat, p_lon, v_range, p_accuracy
supabase/migrations/0040_wire_consent_gates.sql-123-  WHERE h.token = lower(p_observed_token) AND h.user_id <> v_uid
supabase/migrations/0040_wire_consent_gates.sql-124-    AND h.valid_until > v_now - INTERVAL '2 minutes'
supabase/migrations/0040_wire_consent_gates.sql-125-  ORDER BY h.valid_from DESC LIMIT 1;
supabase/migrations/0040_wire_consent_gates.sql-126-  IF v_observed_uid IS NULL THEN RAISE EXCEPTION 'Unknown or expired beacon token' USING ERRCODE='22023'; END IF;
supabase/migrations/0040_wire_consent_gates.sql-127-
supabase/migrations/0040_wire_consent_gates.sql:128:  INSERT INTO public.sightings AS s (
supabase/migrations/0040_wire_consent_gates.sql-129-    observer_user_id, observed_token, observed_user_id, received_at,
supabase/migrations/0040_wire_consent_gates.sql-130-    rssi, observed_at, observer_lat, observer_lon, range_type, observer_accuracy_m
supabase/migrations/0040_wire_consent_gates.sql-131-  ) VALUES (
supabase/migrations/0040_wire_consent_gates.sql-132-    v_uid, lower(p_observed_token), v_observed_uid, v_now,
supabase/migrations/0040_wire_consent_gates.sql-133-    p_rssi, p_observed_at, p_lat, p_lon, v_range, p_accuracy
supabase/migrations/0046_withdrawal_enforcement.sql-292-  IF v_observed_uid IS NULL THEN RAISE EXCEPTION 'Unknown or expired beacon token' USING ERRCODE='22023'; END IF;
supabase/migrations/0046_withdrawal_enforcement.sql-293-  -- 0046: an observed user who withdrew BLE consent must not generate new
supabase/migrations/0046_withdrawal_enforcement.sql-294-  -- evidence, even from a token preserved in history under a legal hold.
supabase/migrations/0046_withdrawal_enforcement.sql-295-  IF public.consent_withdrawn(v_observed_uid, 'ble_proximity') THEN RAISE EXCEPTION 'Unknown or expired beacon token' USING ERRCODE='22023'; END IF;
supabase/migrations/0046_withdrawal_enforcement.sql-296-
supabase/migrations/0046_withdrawal_enforcement.sql:297:  INSERT INTO public.sightings AS s (
supabase/migrations/0046_withdrawal_enforcement.sql-298-    observer_user_id, observed_token, observed_user_id, received_at,
supabase/migrations/0046_withdrawal_enforcement.sql-299-    rssi, observed_at, observer_lat, observer_lon, range_type, observer_accuracy_m
supabase/migrations/0046_withdrawal_enforcement.sql-300-  ) VALUES (
supabase/migrations/0046_withdrawal_enforcement.sql-301-    v_uid, lower(p_observed_token), v_observed_uid, v_now,
supabase/migrations/0046_withdrawal_enforcement.sql-302-    p_rssi, p_observed_at, p_lat, p_lon, v_range, p_accuracy
supabase/migrations/0001_init.sql-146-  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
supabase/migrations/0001_init.sql-147-);
supabase/migrations/0001_init.sql-148-
supabase/migrations/0001_init.sql-149--- Critical indexes for correlation queries
supabase/migrations/0001_init.sql-150-CREATE INDEX idx_sightings_token_time 
supabase/migrations/0001_init.sql:151:  ON public.sightings (observed_token, observed_at DESC);
supabase/migrations/0001_init.sql-152-
supabase/migrations/0001_init.sql-153-CREATE INDEX idx_sightings_observer 
supabase/migrations/0001_init.sql:154:  ON public.sightings (observer_user_id, observed_at DESC);
supabase/migrations/0001_init.sql-155-
supabase/migrations/0001_init.sql-156-CREATE INDEX idx_sightings_geo 
supabase/migrations/0001_init.sql:157:  ON public.sightings USING GIST (observer_location);
supabase/migrations/0001_init.sql-158-
supabase/migrations/0001_init.sql-159--- Cleanup queries filter by created_at at runtime (no NOW() in index predicate).
supabase/migrations/0001_init.sql-160-CREATE INDEX idx_sightings_recent_cleanup 
supabase/migrations/0001_init.sql:161:  ON public.sightings (created_at);
supabase/migrations/0001_init.sql-162-
supabase/migrations/0001_init.sql-163--- =============================================================================
supabase/migrations/0001_init.sql-164--- ENCOUNTERS (Server-created real-world crossings)
supabase/migrations/0001_init.sql-165--- =============================================================================
supabase/migrations/0001_init.sql-166-CREATE TABLE public.encounters (
supabase/migrations/0001_init.sql-293-BEGIN
supabase/migrations/0001_init.sql-294-  IF v_user_id IS NULL THEN
supabase/migrations/0001_init.sql-295-    RAISE EXCEPTION 'Not authenticated';
supabase/migrations/0001_init.sql-296-  END IF;
supabase/migrations/0001_init.sql-297-
supabase/migrations/0001_init.sql:298:  INSERT INTO public.sightings (
supabase/migrations/0001_init.sql-299-    observer_user_id,
supabase/migrations/0001_init.sql-300-    observed_token,
supabase/migrations/0001_init.sql-301-    rssi,
supabase/migrations/0001_init.sql-302-    observed_at,
supabase/migrations/0001_init.sql-303-    observer_lat,
supabase/migrations/0001_init.sql-499-  FOR ALL
supabase/migrations/0001_init.sql-500-  USING (user_id = auth.uid())
supabase/migrations/0001_init.sql-501-  WITH CHECK (user_id = auth.uid());
supabase/migrations/0001_init.sql-502-
supabase/migrations/0001_init.sql-503--- Sightings: user can insert their own observations; no broad read (only server RPCs use them)
supabase/migrations/0001_init.sql:504:CREATE POLICY "Users insert own sightings"
supabase/migrations/0001_init.sql:505:  ON public.sightings
supabase/migrations/0001_init.sql-506-  FOR INSERT
supabase/migrations/0001_init.sql-507-  WITH CHECK (observer_user_id = auth.uid());
supabase/migrations/0001_init.sql-508-
supabase/migrations/0001_init.sql-509--- Encounters: only participants can see their encounters
supabase/migrations/0001_init.sql-510-CREATE POLICY "Users see their own encounters"
supabase/migrations/0029_reciprocal_confirmation.sql-22-  ADD COLUMN IF NOT EXISTS observed_user_id UUID,
supabase/migrations/0029_reciprocal_confirmation.sql-23-  ADD COLUMN IF NOT EXISTS received_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
supabase/migrations/0029_reciprocal_confirmation.sql-24-
supabase/migrations/0029_reciprocal_confirmation.sql-25--- Reverse-direction lookup: "did the peer observe ME recently?"
supabase/migrations/0029_reciprocal_confirmation.sql-26-CREATE INDEX IF NOT EXISTS idx_sightings_reverse
supabase/migrations/0029_reciprocal_confirmation.sql:27:  ON public.sightings (observer_user_id, observed_user_id, received_at DESC);
supabase/migrations/0029_reciprocal_confirmation.sql-28-
supabase/migrations/0029_reciprocal_confirmation.sql-29-ALTER TABLE public.encounters
supabase/migrations/0029_reciprocal_confirmation.sql-30-  ADD COLUMN IF NOT EXISTS trust_level TEXT; -- 'mutual_ble' | 'secure_ranged' | NULL (legacy)
supabase/migrations/0029_reciprocal_confirmation.sql-31-ALTER TABLE public.encounter_pairs
supabase/migrations/0029_reciprocal_confirmation.sql-32-  ADD COLUMN IF NOT EXISTS trust_level TEXT;
supabase/migrations/0029_reciprocal_confirmation.sql-67-  WHERE h.token = lower(p_observed_token) AND h.user_id <> v_uid
supabase/migrations/0029_reciprocal_confirmation.sql-68-    AND h.valid_until > v_now - INTERVAL '2 minutes'
supabase/migrations/0029_reciprocal_confirmation.sql-69-  ORDER BY h.valid_from DESC LIMIT 1;
supabase/migrations/0029_reciprocal_confirmation.sql-70-  IF v_observed_uid IS NULL THEN RAISE EXCEPTION 'Unknown or expired beacon token' USING ERRCODE='22023'; END IF;
supabase/migrations/0029_reciprocal_confirmation.sql-71-
supabase/migrations/0029_reciprocal_confirmation.sql:72:  INSERT INTO public.sightings AS s (
supabase/migrations/0029_reciprocal_confirmation.sql-73-    observer_user_id, observed_token, observed_user_id, received_at,
supabase/migrations/0029_reciprocal_confirmation.sql-74-    rssi, observed_at, observer_lat, observer_lon, range_type, observer_accuracy_m
supabase/migrations/0029_reciprocal_confirmation.sql-75-  ) VALUES (
supabase/migrations/0029_reciprocal_confirmation.sql-76-    v_uid, lower(p_observed_token), v_observed_uid, v_now,
supabase/migrations/0029_reciprocal_confirmation.sql-77-    p_rssi, p_observed_at, p_lat, p_lon, v_range, p_accuracy

exec
/bin/bash -lc "nl -ba lib/features/beacon/beacon_service.dart | sed -n '2360,2505p'
nl -ba lib/features/beacon/beacon_service.dart | sed -n '2530,2630p'
nl -ba lib/shared/services/encounters_api.dart | sed -n '115,180p'
rtk rg -n -C 4 \"sightings\" supabase/migrations/0019_beta_security_hardening.sql supabase/migrations/0042_privilege_hardening.sql supabase/migrations/0047_privilege_retention_consent.sql
supabase status -o env" in /home/hazypiff/in-range
 exited 1 in 183ms:
259 | }`:H.stack,BEH=(H,$)=>{let L=H.stack.split(`
260 | `),A=`${$}[cause]: ${L[0]}`;for(let I=1,D=L.length;I<D;I++)A+=`
261 | ${$}${L[I]}`;if(H.cause)A+=` {
262 | ${BEH(H.cause,`${$}  `)}
263 | ${$}}`;return A},XJ=`~effect/Fiber/${Kx}`,LB$={_A:sH,_E:sH},AB$={id:0},Ff=()=>globalThis[PS];class _y{constructor(H,$=!0){this[XJ]=LB$,this.setContext(H),this.id=++AB$.id,this.currentOpCount=0,this.currentLoopCount=0,this.interruptible=$,this._stack=[],this._observers=[],this._exit=void 0,this._children=void 0,this._interruptedCause=void 0,this._yielded=void 0,this.runtimeMetrics?.recordFiberStart(this.context)}[XJ];id;interruptible;currentOpCount;currentLoopCount;_stack;_observers;_exit;_currentExit;_children;_interruptedCause;_yielded;context;currentScheduler;currentTracerContext;currentSpan;currentLogLevel;minimumLogLevel;currentStackFrame;runtimeMetrics;maxOpsBeforeYield;currentPreventYield;_dispatcher=void 0;get currentDispatcher(){return this._dispatcher??=this.currentScheduler.makeDispatcher()}getRef(H){return Ok(this.context,H)}addObserver(H){if(this._exit)return H(this._exit),U0;return this._observers.push(H),()=>{let $=this._observers.indexOf(H);if($>=0)this._observers.splice($,1)}}interruptUnsafe(H
264 |   at ${L}`}return $}function PN(H){switch(H._tag){case"InvalidType":case"OneOf":case"Composite":case"AnyOf":return EN(H.ast.annotations);case"InvalidValue":case"Forbidden":return EN(H.annotations);case"MissingKey":return EN(H.annotations,"messageMissingKey");case"UnexpectedKey":return EN(H.ast.annotations,"messageUnexpectedKey");case"Filter":return EN(H.filter.annotations);case"Encoding":return PN(H.issue)}}function EN(H,$="message"){let L=H?.[$];if(typeof L==="string")return L}function CfH(H){if(G$(H))return"no value provided";return N$(H.value)}function jY(H){switch(H._tag){case"MissingKey":return H;case"Forbidden":return new BV(tI(H.actual,tD),H.annotations);case"Filter":return new hY(tD(H.actual),H.filter,jY(H.issue));case"Pointer":return new jA(H.path,jY(H.issue));case"Encoding":case"InvalidType":case"InvalidValue":case"Composite":return new IA(tI(H.actual,tD));case"AnyOf":case"OneOf":case"UnexpectedKey":return new IA(MH(tD(H.actual)))}}function kY(H){let $;for(let L of H.reasons){if(!kJ(L)||!hd(L.error)

error: Unknown: FileSystem.writeFile (/home/hazypiff/.supabase/telemetry.json.tmp.507ddab1-6c00-46f9-b3aa-65b8430f8b9b)
       _tag: "PlatformError",
 ~effect/platform/PlatformError: "~effect/platform/PlatformError",

      at Q8 (/$bunfs/root/supabase:264:45499)
      at <anonymous> (/$bunfs/root/supabase:271:16131)

259 | }`:H.stack,BEH=(H,$)=>{let L=H.stack.split(`
260 | `),A=`${$}[cause]: ${L[0]}`;for(let I=1,D=L.length;I<D;I++)A+=`
261 | ${$}${L[I]}`;if(H.cause)A+=` {
262 | ${BEH(H.cause,`${$}  `)}
263 | ${$}}`;return A},XJ=`~effect/Fiber/${Kx}`,LB$={_A:sH,_E:sH},AB$={id:0},Ff=()=>globalThis[PS];class _y{constructor(H,$=!0){this[XJ]=LB$,this.setContext(H),this.id=++AB$.id,this.currentOpCount=0,this.currentLoopCount=0,this.interruptible=$,this._stack=[],this._observers=[],this._exit=void 0,this._children=void 0,this._interruptedCause=void 0,this._yielded=void 0,this.runtimeMetrics?.recordFiberStart(this.context)}[XJ];id;interruptible;currentOpCount;currentLoopCount;_stack;_observers;_exit;_currentExit;_children;_interruptedCause;_yielded;context;currentScheduler;currentTracerContext;currentSpan;currentLogLevel;minimumLogLevel;currentStackFrame;runtimeMetrics;maxOpsBeforeYield;currentPreventYield;_dispatcher=void 0;get currentDispatcher(){return this._dispatcher??=this.currentScheduler.makeDispatcher()}getRef(H){return Ok(this.context,H)}addObserver(H){if(this._exit)return H(this._exit),U0;return this._observers.push(H),()=>{let $=this._observers.indexOf(H);if($>=0)this._observers.splice($,1)}}interruptUnsafe(H
264 |   at ${L}`}return $}function PN(H){switch(H._tag){case"InvalidType":case"OneOf":case"Composite":case"AnyOf":return EN(H.ast.annotations);case"InvalidValue":case"Forbidden":return EN(H.annotations);case"MissingKey":return EN(H.annotations,"messageMissingKey");case"UnexpectedKey":return EN(H.ast.annotations,"messageUnexpectedKey");case"Filter":return EN(H.filter.annotations);case"Encoding":return PN(H.issue)}}function EN(H,$="message"){let L=H?.[$];if(typeof L==="string")return L}function CfH(H){if(G$(H))return"no value provided";return N$(H.value)}function jY(H){switch(H._tag){case"MissingKey":return H;case"Forbidden":return new BV(tI(H.actual,tD),H.annotations);case"Filter":return new hY(tD(H.actual),H.filter,jY(H.issue));case"Pointer":return new jA(H.path,jY(H.issue));case"Encoding":case"InvalidType":case"InvalidValue":case"Composite":return new IA(tI(H.actual,tD));case"AnyOf":case"OneOf":case"UnexpectedKey":return new IA(MH(tD(H.actual)))}}function kY(H){let $;for(let L of H.reasons){if(!kJ(L)||!hd(L.error)

error: Unknown: FileSystem.writeFile (/home/hazypiff/.supabase/telemetry.json.tmp.507ddab1-6c00-46f9-b3aa-65b8430f8b9b)
       _tag: "Unknown",
     module: "FileSystem",
     method: "writeFile",
 pathOrDescriptor: "/home/hazypiff/.supabase/telemetry.json.tmp.507ddab1-6c00-46f9-b3aa-65b8430f8b9b",
    syscall: "open",

      at Q8 (/$bunfs/root/supabase:264:45506)
      at <anonymous> (/$bunfs/root/supabase:271:16131)

EROFS: read-only file system, open '/home/hazypiff/.supabase/telemetry.json.tmp.507ddab1-6c00-46f9-b3aa-65b8430f8b9b'
    path: "/home/hazypiff/.supabase/telemetry.json.tmp.507ddab1-6c00-46f9-b3aa-65b8430f8b9b",
 syscall: "open",
   errno: -30,
    code: "EROFS"


EROFS: read-only file system, open '/home/hazypiff/.supabase/telemetry.json.tmp.507ddab1-6c00-46f9-b3aa-65b8430f8b9b'
    path: "/home/hazypiff/.supabase/telemetry.json.tmp.507ddab1-6c00-46f9-b3aa-65b8430f8b9b",
 syscall: "open",
   errno: -30,
    code: "EROFS"


Bun v1.3.13 (Linux x64 baseline)

exec
/bin/bash -lc "graphify query \"What reads or writes token_claims versus token_claim_history by token, and how does release_token revoke a claim?\"
rtk rg -n -C 5 \"CREATE OR REPLACE FUNCTION public\\.release_token|DELETE FROM public\\.token_claims|UPDATE public\\.token_claim_history|FROM public\\.token_claims|JOIN public\\.token_claims|token_claims tc|token_claims c\" supabase/migrations supabase/functions lib
nl -ba supabase/migrations/0031_server_issued_token_batches.sql | sed -n '1,180p'
nl -ba supabase/migrations/0060_batch_token_preclaim.sql | sed -n '1,175p'" in /home/hazypiff/in-range
 succeeded in 213ms:
Traversal: BFS depth=2 | Start: ['token', 'claimToken', 'public.token_claim_history', 'claim_manager.dart', '_ChatThreadScreenState', 'public.token_claims', '2. Advertisement RSSI versus connected RSSI', "C-SQL-1 🔴 `claim_token` overwrites another user's `token_claim_history` row"] | 179 nodes found

NODE beacon_service.dart [src=lib/features/beacon/beacon_service.dart loc=None community=0]
NODE app_session.dart [src=lib/core/session/app_session.dart loc=None community=2]
NODE match_store.dart [src=lib/features/matches/match_store.dart loc=None community=1]
NODE venue_matcher.dart [src=lib/features/beacon/venue_matcher.dart loc=None community=40]
NODE local_encounter_store.dart [src=lib/features/encounters/local_encounter_store.dart loc=None community=10]
NODE swipe_feed.dart [src=lib/features/encounters/swipe_feed.dart loc=None community=212]
NODE consent_screen.dart [src=lib/features/consent/consent_screen.dart loc=None community=51]
NODE locals_service.dart [src=lib/features/locals/locals_service.dart loc=None community=9]
NODE subtle_wake_service.dart [src=lib/features/beacon/subtle_wake_service.dart loc=None community=132]
NODE safety_store.dart [src=lib/core/privacy/safety_store.dart loc=None community=8]
NODE beacon_provider.dart [src=lib/features/beacon/beacon_provider.dart loc=None community=15]
NODE background_beacon_channel.dart [src=lib/features/beacon/background_beacon_channel.dart loc=None community=153]
NODE range_estimator.dart [src=lib/features/beacon/range_estimator.dart loc=None community=5]
NODE package:flutter_riverpod/flutter_riverpod.dart [src=None loc=None community=180]
NODE main.dart [src=lib/main.dart loc=None community=148]
NODE messages_screen.dart [src=lib/features/chat/messages_screen.dart loc=None community=16]
NODE location_keepalive.dart [src=lib/features/beacon/location_keepalive.dart loc=None community=233]
NODE package:in_range/core/config/app_config.dart [src=None loc=None community=256]
NODE swipe_card.dart [src=lib/features/encounters/swipe_card.dart loc=None community=13]
NODE package:flutter/foundation.dart [src=None loc=None community=123]
NODE ephemeral_token_generator.dart [src=lib/features/beacon/ephemeral_token_generator.dart loc=None community=12]
NODE auth_service.dart [src=lib/shared/services/auth_service.dart loc=None community=76]
NODE bool get [src=None loc=None community=176]
NODE chat_sync_service.dart [src=lib/shared/services/chat_sync_service.dart loc=None community=22]
NODE venue_anchor_service.dart [src=lib/features/beacon/venue_anchor_service.dart loc=None community=171]
NODE matchStoreProvider [src=lib/features/matches/match_store.dart loc=None community=236]
NODE package:flutter/material.dart [src=None loc=None community=214]
NODE batch_token_source.dart [src=lib/features/beacon/batch_token_source.dart loc=None community=133]
NODE app_root.dart [src=lib/app_root.dart loc=None community=214]
NODE wifi_scanner.dart [src=lib/features/beacon/wifi_scanner.dart loc=None community=33]
NODE dart:async [src=None loc=None community=245]
NODE DateTime [src=None loc=None community=39]
NODE push_service.dart [src=lib/core/notifications/push_service.dart loc=None community=29]
NODE profile_sync_service.dart [src=lib/shared/services/profile_sync_service.dart loc=None community=38]
NODE backend_status.dart [src=lib/core/backend/backend_status.dart loc=None community=11]
NODE encounters_api.dart [src=lib/shared/services/encounters_api.dart loc=None community=24]
NODE apns_token_service.dart [src=lib/core/notifications/apns_token_service.dart loc=None community=240]
NODE rssi_uploader_test.dart [src=test/rssi_uploader_test.dart loc=None community=170]
NODE iOS Proximity Upgrade — Research and Agent Handoff [src=docs/IOS_PROXIMITY_RESEARCH_2026-07-24.md loc=L1 community=4]
NODE encounters_screen.dart [src=lib/features/encounters/encounters_screen.dart loc=None community=227]
NODE package:in_range/core/network/supabase_client.dart [src=None loc=None community=123]
NODE dart:io [src=None loc=None community=38]
NODE rssi_uploader.dart [src=lib/features/beacon/rssi_uploader.dart loc=None community=15]
NODE location_keepalive_test.dart [src=test/location_keepalive_test.dart loc=None community=245]
NODE consent_service.dart [src=lib/shared/services/consent_service.dart loc=None community=176]
NODE 0001_init.sql [src=supabase/migrations/0001_init.sql loc=None community=68]
NODE claim_manager.dart [src=lib/features/beacon/claim_manager.dart loc=None community=153]
NODE ConsumerState [src=None loc=None community=227]
NODE ConsumerStatefulWidget [src=None loc=None community=227]
NODE wifi_assist.dart [src=lib/features/beacon/wifi_assist.dart loc=None community=241]
NODE _SwipeFeedState [src=lib/features/encounters/swipe_feed.dart loc=None community=227]
NODE package:in_range/features/matches/match_store.dart [src=None loc=None community=214]
NODE build [src=lib/features/settings/settings_screen.dart loc=None community=236]
NODE In Range — full-system hardening & bug-hunt audit, 2026-08-01 [src=docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md loc=L1 community=281]
NODE SettingsScreen [src=lib/features/settings/settings_screen.dart loc=None community=236]
NODE _BeaconScreenState [src=lib/features/beacon/beacon_screen.dart loc=None community=227]
NODE age_gate.dart [src=lib/core/session/age_gate.dart loc=None community=147]
NODE _HomeShellState [src=lib/features/home/home_shell.dart loc=None community=227]
NODE Corrections to older guidance [src=docs/IOS_PROXIMITY_RESEARCH_2026-07-24.md loc=L63 community=4]
NODE package:in_range/core/privacy/safety_store.dart [src=None loc=None community=214]
NODE package:supabase_flutter/supabase_flutter.dart [src=None loc=None community=256]
NODE build [src=lib/features/home/home_shell.dart loc=None community=227]
NODE _LocalsScreenState [src=lib/features/locals/locals_screen.dart loc=None community=236]
NODE ai_feedback_service.dart [src=lib/shared/services/ai_feedback_service.dart loc=None community=176]
NODE static const int [src=None loc=None community=147]
NODE claim_manager_test.dart [src=test/claim_manager_test.dart loc=None community=245]
NODE _AuthScreenState [src=lib/features/auth/auth_screen.dart loc=None community=227]
... (truncated — 112 more nodes cut by ~2000-token budget. Narrow with context_filter=['call'] or use get_node for a specific symbol)
66 matches in 27 files:

supabase/migrations/0001_init.sql-368-tc.user_id,
supabase/migrations/0001_init.sql-369-tc.approx_lat,
supabase/migrations/0001_init.sql-370-tc.approx_lon,
supabase/migrations/0001_init.sql-371-tc.range_type,
supabase/migrations/0001_init.sql-372-tc.valid_from
supabase/migrations/0001_init.sql:373:FROM public.token_claims tc
supabase/migrations/0001_init.sql-374-WHERE tc.token = p_observed_token
supabase/migrations/0001_init.sql-375-AND tc.user_id != v_observer_id
supabase/migrations/0001_init.sql-376-AND tc.valid_from > NOW() - (p_time_window_minutes || ' minutes')::interval
supabase/migrations/0001_init.sql-377-AND tc.valid_until > NOW() - (p_time_window_minutes || ' minutes')::interval
supabase/migrations/0001_init.sql-378-ORDER BY tc.valid_from DESC
supabase/migrations/0002_location_pings_realtime_storage.sql-187-LANGUAGE sql
supabase/migrations/0002_location_pings_realtime_storage.sql-188-SECURITY DEFINER
supabase/migrations/0002_location_pings_realtime_storage.sql-189-SET search_path = public
supabase/migrations/0002_location_pings_realtime_storage.sql-190-AS $$
supabase/migrations/0002_location_pings_realtime_storage.sql-191--- Token claims: hard-expire after 30 min past valid_until
supabase/migrations/0002_location_pings_realtime_storage.sql:192:DELETE FROM public.token_claims
supabase/migrations/0002_location_pings_realtime_storage.sql-193-WHERE valid_until < now() - interval '30 minutes';
supabase/migrations/0002_location_pings_realtime_storage.sql-194-
supabase/migrations/0002_location_pings_realtime_storage.sql-195--- Sightings: purge after 48h or once encounter exists (cascade handles the l...
supabase/migrations/0002_location_pings_realtime_storage.sql-196-DELETE FROM public.sightings
supabase/migrations/0002_location_pings_realtime_storage.sql-197-WHERE observed_at < now() - interval '48 hours';
supabase/migrations/0003_correlation_fixes.sql-51-tc.user_id,
supabase/migrations/0003_correlation_fixes.sql-52-tc.approx_lat,
supabase/migrations/0003_correlation_fixes.sql-53-tc.approx_lon,
supabase/migrations/0003_correlation_fixes.sql-54-tc.range_type,
supabase/migrations/0003_correlation_fixes.sql-55-tc.valid_from
supabase/migrations/0003_correlation_fixes.sql:56:FROM public.token_claims tc
supabase/migrations/0003_correlation_fixes.sql-57-WHERE tc.token = p_observed_token
supabase/migrations/0003_correlation_fixes.sql-58-AND tc.user_id != v_observer_id
supabase/migrations/0003_correlation_fixes.sql-59-AND tc.valid_from > NOW() - (p_time_window_minutes || ' minutes')::interval
supabase/migrations/0003_correlation_fixes.sql-60-AND tc.valid_until > NOW()
supabase/migrations/0003_correlation_fixes.sql-61-ORDER BY tc.valid_from DESC
supabase/migrations/0009_auth_profile_account.sql-173-interests = NULL,
supabase/migrations/0009_auth_profile_account.sql-174-updated_at = NOW()
supabase/migrations/0009_auth_profile_account.sql-175-WHERE id = v_uid;
supabase/migrations/0009_auth_profile_account.sql-176-
supabase/migrations/0009_auth_profile_account.sql-177-DELETE FROM public.location_pings WHERE user_id = v_uid;
supabase/migrations/0009_auth_profile_account.sql:178:DELETE FROM public.token_claims WHERE user_id = v_uid;
supabase/migrations/0009_auth_profile_account.sql-179-DELETE FROM public.device_push_tokens WHERE user_id = v_uid;
supabase/migrations/0009_auth_profile_account.sql-180--- Sightings kept anonymously for correlation integrity optional; delete for ...
supabase/migrations/0009_auth_profile_account.sql-181-DELETE FROM public.sightings WHERE observer_user_id = v_uid;
supabase/migrations/0009_auth_profile_account.sql-182-END;
supabase/migrations/0009_auth_profile_account.sql-183-$$;
supabase/migrations/0009_auth_profile_account.sql-196-IF auth.uid() IS NULL THEN
supabase/migrations/0009_auth_profile_account.sql-197-RAISE EXCEPTION 'Not authenticated';
supabase/migrations/0009_auth_profile_account.sql-198-END IF;
supabase/migrations/0009_auth_profile_account.sql-199-DELETE FROM public.location_pings WHERE user_id = auth.uid();
  +7 more in supabase/migrations/0009_auth_profile_account.sql
supabase/migrations/0012_correlate_grace_dedupe.sql-33-tc.user_id,
supabase/migrations/0012_correlate_grace_dedupe.sql-34-tc.approx_lat,
supabase/migrations/0012_correlate_grace_dedupe.sql-35-tc.approx_lon,
supabase/migrations/0012_correlate_grace_dedupe.sql-36-tc.range_type,
supabase/migrations/0012_correlate_grace_dedupe.sql-37-tc.valid_from
supabase/migrations/0012_correlate_grace_dedupe.sql:38:FROM public.token_claims tc
supabase/migrations/0012_correlate_grace_dedupe.sql-39-WHERE tc.token = p_observed_token
supabase/migrations/0012_correlate_grace_dedupe.sql-40-AND tc.user_id != v_observer_id
supabase/migrations/0012_correlate_grace_dedupe.sql-41-AND tc.valid_from > NOW() - (p_time_window_minutes || ' minutes')::interval
supabase/migrations/0012_correlate_grace_dedupe.sql-42-AND tc.valid_until > NOW() - interval '5 minutes'
supabase/migrations/0012_correlate_grace_dedupe.sql-43-ORDER BY tc.valid_from DESC
supabase/migrations/0018_security_correlate_photos.sql-139-tc.user_id,
supabase/migrations/0018_security_correlate_photos.sql-140-tc.approx_lat,
supabase/migrations/0018_security_correlate_photos.sql-141-tc.approx_lon,
supabase/migrations/0018_security_correlate_photos.sql-142-tc.range_type,
supabase/migrations/0018_security_correlate_photos.sql-143-tc.valid_from
supabase/migrations/0018_security_correlate_photos.sql:144:FROM public.token_claims tc
supabase/migrations/0018_security_correlate_photos.sql-145-JOIN public.profiles pr ON pr.id = tc.user_id
supabase/migrations/0018_security_correlate_photos.sql-146-WHERE tc.token = p_observed_token
supabase/migrations/0018_security_correlate_photos.sql-147-AND tc.user_id != v_observer_id
supabase/migrations/0018_security_correlate_photos.sql-148-AND tc.valid_from > NOW() - (p_time_window_minutes || ' minutes')::interval
supabase/migrations/0018_security_correlate_photos.sql-149-AND tc.valid_until > NOW() - interval '5 minutes'
supabase/migrations/0019_beta_security_hardening.sql-99-
supabase/migrations/0019_beta_security_hardening.sql-100-ALTER TABLE public.token_claims
supabase/migrations/0019_beta_security_hardening.sql-101-ADD COLUMN IF NOT EXISTS last_claimed_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
supabase/migrations/0019_beta_security_hardening.sql-102-
supabase/migrations/0019_beta_security_hardening.sql-103--- One current row per user and one owner per unguessable advertised token.
supabase/migrations/0019_beta_security_hardening.sql:104:DELETE FROM public.token_claims older
supabase/migrations/0019_beta_security_hardening.sql-105-USING public.token_claims newer
supabase/migrations/0019_beta_security_hardening.sql-106-WHERE older.user_id = newer.user_id
supabase/migrations/0019_beta_security_hardening.sql-107-AND (older.valid_from, older.id) < (newer.valid_from, newer.id);
supabase/migrations/0019_beta_security_hardening.sql-108-
supabase/migrations/0019_beta_security_hardening.sql:109:DELETE FROM public.token_claims older
supabase/migrations/0019_beta_security_hardening.sql-110-USING public.token_claims newer
supabase/migrations/0019_beta_security_hardening.sql-111-WHERE older.token = newer.token
supabase/migrations/0019_beta_security_hardening.sql-112-AND older.id < newer.id;
supabase/migrations/0019_beta_security_hardening.sql-113-
  +84 more in supabase/migrations/0019_beta_security_hardening.sql
supabase/migrations/0022_encounter_band_from_sighting.sql-51-IF v_uid IS NULL OR NOT public.current_user_can_discover() THEN
supabase/migrations/0022_encounter_band_from_sighting.sql-52-RETURN;
supabase/migrations/0022_encounter_band_from_sighting.sql-53-END IF;
supabase/migrations/0022_encounter_band_from_sighting.sql-54-
supabase/migrations/0022_encounter_band_from_sighting.sql-55-SELECT * INTO v_claim
supabase/migrations/0022_encounter_band_from_sighting.sql:56:FROM public.token_claims tc
supabase/migrations/0022_encounter_band_from_sighting.sql-57-WHERE tc.token = lower(p_observed_token)
supabase/migrations/0022_encounter_band_from_sighting.sql-58-AND tc.user_id <> v_uid
supabase/migrations/0022_encounter_band_from_sighting.sql-59-AND tc.valid_from > NOW() - make_interval(mins => LEAST(30, GREATEST(1, p_tim...
supabase/migrations/0022_encounter_band_from_sighting.sql-60-AND tc.valid_until > NOW() - INTERVAL '2 minutes'
supabase/migrations/0022_encounter_band_from_sighting.sql-61-LIMIT 1;
supabase/migrations/0024_accuracy_aware_correlation.sql-68-END IF;
supabase/migrations/0024_accuracy_aware_correlation.sql-69-IF p_accuracy IS NOT NULL AND (p_accuracy < 0 OR p_accuracy > 10000) THEN
supabase/migrations/0024_accuracy_aware_correlation.sql-70-RAISE EXCEPTION 'Invalid accuracy' USING ERRCODE = '22023';
supabase/migrations/0024_accuracy_aware_correlation.sql-71-END IF;
supabase/migrations/0024_accuracy_aware_correlation.sql-72-IF NOT EXISTS (
supabase/migrations/0024_accuracy_aware_correlation.sql:73:SELECT 1 FROM public.token_claims tc
supabase/migrations/0024_accuracy_aware_correlation.sql-74-WHERE tc.token = lower(p_observed_token)
supabase/migrations/0024_accuracy_aware_correlation.sql-75-AND tc.user_id <> v_uid
supabase/migrations/0024_accuracy_aware_correlation.sql-76-AND tc.valid_until > v_now - INTERVAL '2 minutes'
supabase/migrations/0024_accuracy_aware_correlation.sql-77-) THEN
supabase/migrations/0024_accuracy_aware_correlation.sql-78-RAISE EXCEPTION 'Unknown or expired beacon token' USING ERRCODE = '22023';
supabase/migrations/0024_accuracy_aware_correlation.sql-124-
supabase/migrations/0024_accuracy_aware_correlation.sql-125-IF v_range::TEXT LIKE 'feet_%' THEN
supabase/migrations/0024_accuracy_aware_correlation.sql-126--- BLE already proved these two are within radio range. GPS is only asked
supabase/migrations/0024_accuracy_aware_correlation.sql-127--- "is this plausible?", sized by what the phones actually reported.
  +29 more in supabase/migrations/0024_accuracy_aware_correlation.sql
supabase/migrations/0025_encounter_recurrence.sql-113-IF v_uid IS NULL OR NOT public.current_user_can_discover() THEN
supabase/migrations/0025_encounter_recurrence.sql-114-RETURN;
supabase/migrations/0025_encounter_recurrence.sql-115-END IF;
supabase/migrations/0025_encounter_recurrence.sql-116-
supabase/migrations/0025_encounter_recurrence.sql-117-SELECT * INTO v_claim
supabase/migrations/0025_encounter_recurrence.sql:118:FROM public.token_claims tc
supabase/migrations/0025_encounter_recurrence.sql-119-WHERE tc.token = lower(p_observed_token)
supabase/migrations/0025_encounter_recurrence.sql-120-AND tc.user_id <> v_uid
supabase/migrations/0025_encounter_recurrence.sql-121-AND tc.valid_from > NOW() - make_interval(mins => LEAST(30, GREATEST(1, p_tim...
supabase/migrations/0025_encounter_recurrence.sql-122-AND tc.valid_until > NOW() - INTERVAL '2 minutes'
supabase/migrations/0025_encounter_recurrence.sql-123-LIMIT 1;
supabase/migrations/0026_sighting_idempotency_ratelimit.sql-94-IF v_calls > 120 THEN
supabase/migrations/0026_sighting_idempotency_ratelimit.sql-95-RAISE EXCEPTION 'Sighting rate limit' USING ERRCODE = '54000';
supabase/migrations/0026_sighting_idempotency_ratelimit.sql-96-END IF;
supabase/migrations/0026_sighting_idempotency_ratelimit.sql-97-
supabase/migrations/0026_sighting_idempotency_ratelimit.sql-98-IF NOT EXISTS (
supabase/migrations/0026_sighting_idempotency_ratelimit.sql:99:SELECT 1 FROM public.token_claims tc
supabase/migrations/0026_sighting_idempotency_ratelimit.sql-100-WHERE tc.token = lower(p_observed_token)
supabase/migrations/0026_sighting_idempotency_ratelimit.sql-101-AND tc.user_id <> v_uid
supabase/migrations/0026_sighting_idempotency_ratelimit.sql-102-AND tc.valid_until > v_now - INTERVAL '2 minutes'
supabase/migrations/0026_sighting_idempotency_ratelimit.sql-103-) THEN
supabase/migrations/0026_sighting_idempotency_ratelimit.sql-104-RAISE EXCEPTION 'Unknown or expired beacon token' USING ERRCODE = '22023';
supabase/migrations/0026_sighting_idempotency_ratelimit.sql-125-RETURNING id INTO v_id;
supabase/migrations/0026_sighting_idempotency_ratelimit.sql-126-
supabase/migrations/0026_sighting_idempotency_ratelimit.sql-127-v_window := LEAST(30, public.range_time_window_minutes(v_range));
supabase/migrations/0026_sighting_idempotency_ratelimit.sql-128-IF v_range::TEXT LIKE 'feet_%' THEN
  +7 more in supabase/migrations/0026_sighting_idempotency_ratelimit.sql
supabase/migrations/0027_durable_recurrence_pairs.sql-120-v_distance DOUBLE PRECISION; v_rssi INTEGER; v_min_rssi INTEGER;
supabase/migrations/0027_durable_recurrence_pairs.sql-121-v_new BOOLEAN := FALSE; v_sight_range public.range_type; v_band public.range_...
supabase/migrations/0027_durable_recurrence_pairs.sql-122-v_now TIMESTAMPTZ := NOW();
supabase/migrations/0027_durable_recurrence_pairs.sql-123-BEGIN
supabase/migrations/0027_durable_recurrence_pairs.sql-124-IF v_uid IS NULL OR NOT public.current_user_can_discover() THEN RETURN; END IF;
supabase/migrations/0027_durable_recurrence_pairs.sql:125:SELECT * INTO v_claim FROM public.token_claims tc
supabase/migrations/0027_durable_recurrence_pairs.sql-126-WHERE tc.token = lower(p_observed_token) AND tc.user_id <> v_uid
supabase/migrations/0027_durable_recurrence_pairs.sql-127-AND tc.valid_from > NOW() - make_interval(mins => LEAST(30, GREATEST(1, p_tim...
supabase/migrations/0027_durable_recurrence_pairs.sql-128-AND tc.valid_until > NOW() - INTERVAL '2 minutes' LIMIT 1;
supabase/migrations/0027_durable_recurrence_pairs.sql-129-IF NOT FOUND OR NOT public.is_discoverable_user(v_claim.user_id) THEN RETURN;...
supabase/migrations/0027_durable_recurrence_pairs.sql-130-IF public.is_blocked_pair(v_uid, v_claim.user_id) THEN RETURN; END IF;
supabase/migrations/0028_token_claim_history.sql-31-
supabase/migrations/0028_token_claim_history.sql-32--- Backfill the current live claims so nothing is lost at deploy time.
supabase/migrations/0028_token_claim_history.sql-33-INSERT INTO public.token_claim_history
supabase/migrations/0028_token_claim_history.sql-34-(token, user_id, valid_from, valid_until, approx_lat, approx_lon, range_type,...
supabase/migrations/0028_token_claim_history.sql-35-SELECT token, user_id, valid_from, valid_until, approx_lat, approx_lon, range...
supabase/migrations/0028_token_claim_history.sql:36:FROM public.token_claims
supabase/migrations/0028_token_claim_history.sql-37-ON CONFLICT (token) DO NOTHING;
supabase/migrations/0028_token_claim_history.sql-38-
supabase/migrations/0028_token_claim_history.sql-39--- claim_token: write to history in addition to the live one-row-per-user claim.
supabase/migrations/0028_token_claim_history.sql-40-CREATE OR REPLACE FUNCTION public.claim_token(
supabase/migrations/0028_token_claim_history.sql-41-p_token TEXT, p_valid_until TIMESTAMPTZ,
supabase/migrations/0028_token_claim_history.sql-62-IF p_lat NOT BETWEEN -90 AND 90 OR p_lon NOT BETWEEN -180 AND 180 THEN
supabase/migrations/0028_token_claim_history.sql-63-RAISE EXCEPTION 'Invalid coordinates' USING ERRCODE='22023'; END IF;
supabase/migrations/0028_token_claim_history.sql-64-IF p_accuracy IS NOT NULL AND (p_accuracy < 0 OR p_accuracy > 10000) THEN
supabase/migrations/0028_token_claim_history.sql-65-RAISE EXCEPTION 'Invalid accuracy' USING ERRCODE='22023'; END IF;
  +7 more in supabase/migrations/0028_token_claim_history.sql
supabase/migrations/0031_server_issued_token_batches.sql-136-IF NOT COALESCE(v_in_batch, FALSE)
supabase/migrations/0031_server_issued_token_batches.sql-137-AND COALESCE((SELECT value_num FROM public.app_settings WHERE key='enforce_ba...
supabase/migrations/0031_server_issued_token_batches.sql-138-RAISE EXCEPTION 'Beacon token was not issued to this account' USING ERRCODE='...
supabase/migrations/0031_server_issued_token_batches.sql-139-END IF;
supabase/migrations/0031_server_issued_token_batches.sql-140-
supabase/migrations/0031_server_issued_token_batches.sql:141:SELECT last_claimed_at INTO v_last FROM public.token_claims WHERE user_id = v...
supabase/migrations/0031_server_issued_token_batches.sql-142-IF v_last IS NOT NULL AND v_last > v_now - INTERVAL '5 seconds' THEN
supabase/migrations/0031_server_issued_token_batches.sql-143-RAISE EXCEPTION 'Beacon claim rate limit' USING ERRCODE='54000'; END IF;
supabase/migrations/0031_server_issued_token_batches.sql-144-
supabase/migrations/0031_server_issued_token_batches.sql-145-INSERT INTO public.token_claims (
supabase/migrations/0031_server_issued_token_batches.sql-146-user_id, token, valid_from, valid_until, approx_lat, approx_lon,
supabase/migrations/0035_account_deletion_completeness.sql-116-updated_at                = NOW()
supabase/migrations/0035_account_deletion_completeness.sql-117-WHERE id = p_uid;
supabase/migrations/0035_account_deletion_completeness.sql-118-
supabase/migrations/0035_account_deletion_completeness.sql-119--- Proximity + beacon telemetry: no reason to retain any of it.
supabase/migrations/0035_account_deletion_completeness.sql-120-DELETE FROM public.location_pings      WHERE user_id          = p_uid;
supabase/migrations/0035_account_deletion_completeness.sql:121:DELETE FROM public.token_claims        WHERE user_id          = p_uid;
supabase/migrations/0035_account_deletion_completeness.sql-122-DELETE FROM public.token_claim_history WHERE user_id          = p_uid;
supabase/migrations/0035_account_deletion_completeness.sql-123-DELETE FROM public.sightings           WHERE observer_user_id = p_uid;
supabase/migrations/0035_account_deletion_completeness.sql-124-DELETE FROM public.beacon_token_batch  WHERE user_id          = p_uid;
supabase/migrations/0035_account_deletion_completeness.sql-125-DELETE FROM public.device_attestations WHERE user_id          = p_uid;
supabase/migrations/0035_account_deletion_completeness.sql-126-
supabase/migrations/0037_legal_hold.sql-164-deleted_at                = COALESCE(deleted_at, NOW()),
supabase/migrations/0037_legal_hold.sql-165-updated_at                = NOW()
supabase/migrations/0037_legal_hold.sql-166-WHERE id = p_uid;
supabase/migrations/0037_legal_hold.sql-167-
supabase/migrations/0037_legal_hold.sql-168-DELETE FROM public.location_pings      WHERE user_id          = p_uid;
supabase/migrations/0037_legal_hold.sql:169:DELETE FROM public.token_claims        WHERE user_id          = p_uid;
supabase/migrations/0037_legal_hold.sql-170-DELETE FROM public.token_claim_history WHERE user_id          = p_uid;
supabase/migrations/0037_legal_hold.sql-171-DELETE FROM public.sightings           WHERE observer_user_id = p_uid;
supabase/migrations/0037_legal_hold.sql-172-DELETE FROM public.beacon_token_batch  WHERE user_id          = p_uid;
supabase/migrations/0037_legal_hold.sql-173-DELETE FROM public.device_attestations WHERE user_id          = p_uid;
supabase/migrations/0037_legal_hold.sql-174-DELETE FROM public.device_push_tokens  WHERE user_id          = p_uid;
supabase/migrations/0040_wire_consent_gates.sql-64-IF NOT COALESCE(v_in_batch, FALSE)
supabase/migrations/0040_wire_consent_gates.sql-65-AND COALESCE((SELECT value_num FROM public.app_settings WHERE key='enforce_ba...
supabase/migrations/0040_wire_consent_gates.sql-66-RAISE EXCEPTION 'Beacon token was not issued to this account' USING ERRCODE='...
supabase/migrations/0040_wire_consent_gates.sql-67-END IF;
  +7 more in supabase/migrations/0040_wire_consent_gates.sql
+10 more files
     1	-- #6 step 2: server-issued opaque token batches.
     2	--
     3	-- Today the client MINTS its own beacon token (random bytes + a user_hash + an
     4	-- HMAC keyed by a secret shipped in the app). The HMAC is therefore cosmetic —
     5	-- anyone with the binary can compute it — and the client fully controls token
     6	-- values and validity windows; claim_token (auth-gated) is the only real
     7	-- token<->identity binding.
     8	--
     9	-- This migration moves token GENERATION to the server. issue_token_batch mints a
    10	-- day's worth of opaque tokens (gen_random_uuid, 122 bits) reserved for the
    11	-- authenticated user. The client fetches the batch once, then advertises each
    12	-- slot's opaque token; it still calls claim_token per rotation so GPS/range stay
    13	-- dynamic, but the token VALUE is now server-owned and unguessable. That is the
    14	-- foundation for attesting issuance (App Attest / Play Integrity, step 3),
    15	-- detecting token fan-out abuse (step 4), and revocation.
    16	--
    17	-- Rollout is non-breaking: claim_token still accepts a self-minted token while
    18	-- the flag `enforce_batch_tokens` is 0 (default). After the batch-aware client
    19	-- ships, flip the flag to 1 (a data change, no migration) to require batch
    20	-- membership. Observer-side offline scanning is unchanged (resolution is still
    21	-- via token_claim_history).
    22	
    23	-- Enforcement flag — OFF by default so this deploy cannot break current clients.
    24	INSERT INTO public.app_settings (key, value_num) VALUES ('enforce_batch_tokens', 0)
    25	ON CONFLICT (key) DO NOTHING;
    26	
    27	CREATE TABLE IF NOT EXISTS public.beacon_token_batch (
    28	  token       TEXT PRIMARY KEY,               -- opaque 32 hex chars (128-bit)
    29	  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    30	  batch_day   DATE NOT NULL,
    31	  slot        INT  NOT NULL,
    32	  valid_from  TIMESTAMPTZ NOT NULL,
    33	  valid_until TIMESTAMPTZ NOT NULL,
    34	  consumed_at TIMESTAMPTZ,                     -- set when first claimed (observability)
    35	  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    36	  UNIQUE (user_id, batch_day, slot)
    37	);
    38	CREATE INDEX IF NOT EXISTS idx_beacon_token_batch_user_day ON public.beacon_token_batch (user_id, batch_day);
    39	CREATE INDEX IF NOT EXISTS idx_beacon_token_batch_expiry ON public.beacon_token_batch (valid_until);
    40	ALTER TABLE public.beacon_token_batch ENABLE ROW LEVEL SECURITY;
    41	-- RPC-only, like sightings/token_claim_history: no direct grant to any client role.
    42	REVOKE ALL ON TABLE public.beacon_token_batch FROM PUBLIC, anon, authenticated;
    43	
    44	CREATE OR REPLACE FUNCTION public.issue_token_batch(
    45	  p_day DATE DEFAULT CURRENT_DATE,
    46	  p_window_minutes INT DEFAULT 15
    47	)
    48	RETURNS TABLE (token TEXT, slot INT, valid_from TIMESTAMPTZ, valid_until TIMESTAMPTZ)
    49	LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
    50	AS $$
    51	#variable_conflict use_column
    52	DECLARE
    53	  v_uid UUID := auth.uid();
    54	  v_window INT := LEAST(60, GREATEST(5, COALESCE(p_window_minutes, 15)));
    55	  v_day DATE := COALESCE(p_day, CURRENT_DATE);
    56	  v_slots INT;
    57	  v_distinct_days INT;
    58	BEGIN
    59	  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;
    60	  IF NOT public.current_user_can_discover() THEN
    61	    RAISE EXCEPTION 'Complete age and photo verification before using Beacon' USING ERRCODE='42501'; END IF;
    62	  -- Only today or tomorrow: bounds pre-mining / fan-out of far-future batches.
    63	  IF v_day < CURRENT_DATE OR v_day > CURRENT_DATE + 1 THEN
    64	    RAISE EXCEPTION 'Batch day out of range' USING ERRCODE='22023'; END IF;
    65	
    66	  -- Housekeeping + abuse guard: drop the caller's stale batches, then cap how
    67	  -- many distinct live days one user may hold (a relay farm requesting many
    68	  -- days of tokens would trip this).
    69	  DELETE FROM public.beacon_token_batch WHERE user_id = v_uid AND batch_day < CURRENT_DATE - 1;
    70	  SELECT count(DISTINCT b.batch_day) INTO v_distinct_days
    71	  FROM public.beacon_token_batch b WHERE b.user_id = v_uid AND b.batch_day >= CURRENT_DATE;
    72	  IF v_distinct_days >= 3 AND NOT EXISTS (
    73	    SELECT 1 FROM public.beacon_token_batch b WHERE b.user_id = v_uid AND b.batch_day = v_day
    74	  ) THEN
    75	    RAISE EXCEPTION 'Too many active token batches' USING ERRCODE='54000'; END IF;
    76	
    77	  v_slots := (1440 / v_window);   -- 96 for a 15-minute window
    78	
    79	  -- Idempotent: ON CONFLICT keeps each slot's originally-issued token, so a
    80	  -- re-fetch returns the SAME batch (no churn in the advertised set).
    81	  -- gen_random_uuid() (pg_catalog, no extension dep) -> 32 lowercase hex chars =
    82	  -- 122 bits of unguessable randomness, matching the ^[0-9a-f]{32}$ token format.
    83	  INSERT INTO public.beacon_token_batch (token, user_id, batch_day, slot, valid_from, valid_until)
    84	  SELECT replace(gen_random_uuid()::text, '-', ''), v_uid, v_day, g,
    85	         (v_day::timestamptz + make_interval(mins => g * v_window)),
    86	         (v_day::timestamptz + make_interval(mins => g * v_window + v_window + 2))
    87	  FROM generate_series(0, v_slots - 1) AS g
    88	  ON CONFLICT (user_id, batch_day, slot) DO NOTHING;
    89	
    90	  RETURN QUERY
    91	  SELECT b.token, b.slot, b.valid_from, b.valid_until
    92	  FROM public.beacon_token_batch b
    93	  WHERE b.user_id = v_uid AND b.batch_day = v_day
    94	  ORDER BY b.slot;
    95	END;
    96	$$;
    97	GRANT EXECUTE ON FUNCTION public.issue_token_batch(DATE, INT) TO authenticated;
    98	
    99	-- claim_token: consume the matching batch token, and (when the flag is on)
   100	-- require the claimed token to belong to the caller's issued batch. Body is
   101	-- otherwise identical to 0028.
   102	CREATE OR REPLACE FUNCTION public.claim_token(
   103	  p_token TEXT, p_valid_until TIMESTAMPTZ,
   104	  p_lat DOUBLE PRECISION DEFAULT NULL, p_lon DOUBLE PRECISION DEFAULT NULL,
   105	  p_range public.range_type DEFAULT 'miles_10', p_accuracy DOUBLE PRECISION DEFAULT NULL
   106	)
   107	RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
   108	AS $$
   109	DECLARE
   110	  v_uid UUID := auth.uid();
   111	  v_now TIMESTAMPTZ := clock_timestamp();
   112	  v_last TIMESTAMPTZ;
   113	  v_in_batch BOOLEAN;
   114	BEGIN
   115	  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;
   116	  IF NOT public.current_user_can_discover() THEN
   117	    RAISE EXCEPTION 'Complete age and photo verification before using Beacon' USING ERRCODE='42501'; END IF;
   118	  IF p_token IS NULL OR p_token !~ '^[0-9a-f]{32}$' THEN
   119	    RAISE EXCEPTION 'Invalid beacon token' USING ERRCODE='22023'; END IF;
   120	  IF p_valid_until IS NULL OR p_valid_until <= v_now + INTERVAL '1 minute'
   121	     OR p_valid_until > v_now + INTERVAL '21 minutes' THEN
   122	    RAISE EXCEPTION 'Token validity must end within 1..21 minutes' USING ERRCODE='22023'; END IF;
   123	  IF p_lat IS NULL OR p_lon IS NULL THEN
   124	    RAISE EXCEPTION 'Fresh coordinates are required' USING ERRCODE='22023'; END IF;
   125	  IF p_lat NOT BETWEEN -90 AND 90 OR p_lon NOT BETWEEN -180 AND 180 THEN
   126	    RAISE EXCEPTION 'Invalid coordinates' USING ERRCODE='22023'; END IF;
   127	  IF p_accuracy IS NOT NULL AND (p_accuracy < 0 OR p_accuracy > 10000) THEN
   128	    RAISE EXCEPTION 'Invalid accuracy' USING ERRCODE='22023'; END IF;
   129	
   130	  -- #6 step 2: the token must be one the server issued to THIS user. Consume it
   131	  -- (observability); enforce membership only when the flag is on so the
   132	  -- batch-aware client can roll out first.
   133	  UPDATE public.beacon_token_batch b SET consumed_at = COALESCE(b.consumed_at, v_now)
   134	  WHERE b.token = lower(p_token) AND b.user_id = v_uid
   135	  RETURNING TRUE INTO v_in_batch;
   136	  IF NOT COALESCE(v_in_batch, FALSE)
   137	     AND COALESCE((SELECT value_num FROM public.app_settings WHERE key='enforce_batch_tokens'), 0) >= 1 THEN
   138	    RAISE EXCEPTION 'Beacon token was not issued to this account' USING ERRCODE='22023';
   139	  END IF;
   140	
   141	  SELECT last_claimed_at INTO v_last FROM public.token_claims WHERE user_id = v_uid;
   142	  IF v_last IS NOT NULL AND v_last > v_now - INTERVAL '5 seconds' THEN
   143	    RAISE EXCEPTION 'Beacon claim rate limit' USING ERRCODE='54000'; END IF;
   144	
   145	  INSERT INTO public.token_claims (
   146	    user_id, token, valid_from, valid_until, approx_lat, approx_lon,
   147	    range_type, accuracy_m, created_at, last_claimed_at)
   148	  VALUES (v_uid, lower(p_token), v_now, p_valid_until, p_lat, p_lon, p_range, p_accuracy, v_now, v_now)
   149	  ON CONFLICT (user_id) DO UPDATE SET
   150	    token = EXCLUDED.token, valid_from = EXCLUDED.valid_from, valid_until = EXCLUDED.valid_until,
   151	    approx_lat = EXCLUDED.approx_lat, approx_lon = EXCLUDED.approx_lon,
   152	    range_type = EXCLUDED.range_type, accuracy_m = EXCLUDED.accuracy_m,
   153	    last_claimed_at = EXCLUDED.last_claimed_at;
   154	
   155	  INSERT INTO public.token_claim_history
   156	    (token, user_id, valid_from, valid_until, approx_lat, approx_lon, range_type, accuracy_m, created_at)
   157	  VALUES (lower(p_token), v_uid, v_now, p_valid_until, p_lat, p_lon, p_range, p_accuracy, v_now)
   158	  ON CONFLICT (token) DO UPDATE SET valid_until = EXCLUDED.valid_until;
   159	END;
   160	$$;
   161	GRANT EXECUTE ON FUNCTION public.claim_token(
   162	  TEXT, TIMESTAMPTZ, DOUBLE PRECISION, DOUBLE PRECISION, public.range_type, DOUBLE PRECISION
   163	) TO authenticated;
     1	-- 0060: close the native-token resolution gap (audit 2026-07-25, critical #2).
     2	--
     3	-- A locked iPhone's native BackgroundBeacon serves GATT reads from its
     4	-- persisted day batch, rotating slots on its own schedule. Only Dart's
     5	-- claim_token wrote token_claim_history — and record_sighting resolves
     6	-- exclusively through that table — so once Dart was suspended or evicted,
     7	-- every later slot the native side served was unresolvable: a peer could
     8	-- hear the beacon and never map it to a person.
     9	--
    10	-- Fix: claim_token_batch pre-claims every still-live slot the server issued
    11	-- to the caller (today + tomorrow, per issue_token_batch), so any token the
    12	-- native carrier can serve is already resolvable. Rows are written WITHOUT
    13	-- coordinates on purpose: a fix stamped at session start would make
    14	-- correlate_encounter's 400 m plausibility veto reject real encounters after
    15	-- the user travels (the reviewer-#7 failure shape), and NULL location is
    16	-- both the safer product choice (a dark, locked phone records no GPS trail)
    17	-- and handled by the veto, which only applies when a claim carries
    18	-- coordinates. When Dart is alive and later single-claims a slot, the
    19	-- claim_token conflict merge below fills the geo fields back in, so the
    20	-- veto returns for the slots that have a fresh fix.
    21	
    22	-- ---------------------------------------------------------------------------
    23	-- 1. claim_token_batch: pre-claim the caller's own issued slots.
    24	-- ---------------------------------------------------------------------------
    25	CREATE OR REPLACE FUNCTION public.claim_token_batch(
    26	  p_range public.range_type DEFAULT 'feet_60'
    27	)
    28	RETURNS INT
    29	LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
    30	AS $function$
    31	DECLARE
    32	  v_uid UUID := auth.uid();
    33	  v_now TIMESTAMPTZ := clock_timestamp();
    34	  v_rows INT;
    35	BEGIN
    36	  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;
    37	  IF NOT public.current_user_can_discover() THEN
    38	    RAISE EXCEPTION 'Complete age and photo verification before using Beacon' USING ERRCODE='42501'; END IF;
    39	  -- Consent gate (0040), same as claim_token. No precise_location check: this
    40	  -- function stores NO coordinates, so there is nothing location-shaped to
    41	  -- withdraw from.
    42	  PERFORM public.require_consent(v_uid, 'ble_proximity');
    43	
    44	  -- Throttle: one batch claim per minute per user. Only batch-originated rows
    45	  -- (NULL location) count, so the per-rotation single claims never trip it.
    46	  IF EXISTS (
    47	    SELECT 1 FROM public.token_claim_history h
    48	    WHERE h.user_id = v_uid AND h.approx_lat IS NULL
    49	      AND h.created_at > v_now - INTERVAL '1 minute'
    50	  ) THEN
    51	    RAISE EXCEPTION 'Beacon claim rate limit' USING ERRCODE='54000';
    52	  END IF;
    53	
    54	  -- Only tokens the server issued to THIS caller (beacon_token_batch
    55	  -- membership) — no user can claim another's tokens, and far-future mining
    56	  -- is already bounded by issue_token_batch's day cap. valid_from/valid_until
    57	  -- are the slot's real window, so resolution and expiry line up with what
    58	  -- the native carrier actually serves. ON CONFLICT DO NOTHING: a slot the
    59	  -- live client already single-claimed keeps its location-bearing row.
    60	  INSERT INTO public.token_claim_history
    61	    (token, user_id, valid_from, valid_until, approx_lat, approx_lon,
    62	     range_type, accuracy_m, created_at)
    63	  SELECT b.token, v_uid, b.valid_from, b.valid_until, NULL, NULL,
    64	         p_range, NULL, v_now
    65	  FROM public.beacon_token_batch b
    66	  WHERE b.user_id = v_uid AND b.valid_until > v_now
    67	  ON CONFLICT (token) DO NOTHING;
    68	  GET DIAGNOSTICS v_rows = ROW_COUNT;
    69	  RETURN v_rows;
    70	END;
    71	$function$;
    72	
    73	COMMENT ON FUNCTION public.claim_token_batch(public.range_type) IS
    74	  'Pre-claims every still-live server-issued batch slot for the caller into token_claim_history (NULL location by design), so tokens served natively by a locked/evicted phone stay resolvable. Returns rows claimed.';
    75	
    76	REVOKE ALL ON FUNCTION public.claim_token_batch(public.range_type)
    77	  FROM PUBLIC, anon;
    78	GRANT EXECUTE ON FUNCTION public.claim_token_batch(public.range_type)
    79	  TO authenticated;
    80	
    81	-- ---------------------------------------------------------------------------
    82	-- 2. claim_token: merge geo fields into a batch-pre-claimed row.
    83	-- ---------------------------------------------------------------------------
    84	-- Body is verbatim 0048 except the token_claim_history conflict clause: a
    85	-- slot first claimed by claim_token_batch carries NULL location; when the
    86	-- live client later single-claims that same slot with a fresh fix, fill the
    87	-- geo fields (never overwriting existing ones) so correlate_encounter's
    88	-- plausibility veto applies to that slot again.
    89	CREATE OR REPLACE FUNCTION public.claim_token(p_token text, p_valid_until timestamp with time zone, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_range range_type DEFAULT 'miles_10'::range_type, p_accuracy double precision DEFAULT NULL::double precision)
    90	 RETURNS void
    91	 LANGUAGE plpgsql
    92	 SECURITY DEFINER
    93	 SET search_path TO 'pg_catalog', 'public'
    94	AS $function$
    95	DECLARE
    96	  v_uid UUID := auth.uid();
    97	  v_now TIMESTAMPTZ := clock_timestamp();
    98	  v_last TIMESTAMPTZ;
    99	  v_in_batch BOOLEAN;
   100	BEGIN
   101	  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;
   102	  IF NOT public.current_user_can_discover() THEN
   103	    RAISE EXCEPTION 'Complete age and photo verification before using Beacon' USING ERRCODE='42501'; END IF;
   104	  -- Consent gate (0040). No-op unless app_settings.enforce_consent = 1.
   105	  PERFORM public.require_consent(v_uid, 'ble_proximity');
   106	  -- 0048: the consent UI scopes GPS to precise_location ("deleted after 24h").
   107	  -- Beacon mandatorily uploads coordinates, so a user who withdrew precise
   108	  -- location must not keep feeding GPS through it, even while ble_proximity
   109	  -- is still granted. Explicit withdrawal denies regardless of enforce_consent.
   110	  IF public.consent_withdrawn(v_uid, 'precise_location') THEN
   111	    RAISE EXCEPTION 'Location sharing was turned off' USING ERRCODE='42501'; END IF;
   112	  IF p_token IS NULL OR p_token !~ '^[0-9a-f]{32}$' THEN
   113	    RAISE EXCEPTION 'Invalid beacon token' USING ERRCODE='22023'; END IF;
   114	  IF p_valid_until IS NULL OR p_valid_until <= v_now + INTERVAL '1 minute'
   115	     OR p_valid_until > v_now + INTERVAL '21 minutes' THEN
   116	    RAISE EXCEPTION 'Token validity must end within 1..21 minutes' USING ERRCODE='22023'; END IF;
   117	  IF p_lat IS NULL OR p_lon IS NULL THEN
   118	    RAISE EXCEPTION 'Fresh coordinates are required' USING ERRCODE='22023'; END IF;
   119	  IF p_lat NOT BETWEEN -90 AND 90 OR p_lon NOT BETWEEN -180 AND 180 THEN
   120	    RAISE EXCEPTION 'Invalid coordinates' USING ERRCODE='22023'; END IF;
   121	  IF p_accuracy IS NOT NULL AND (p_accuracy < 0 OR p_accuracy > 10000) THEN
   122	    RAISE EXCEPTION 'Invalid accuracy' USING ERRCODE='22023'; END IF;
   123	
   124	  -- #6 step 2: the token must be one the server issued to THIS user. Consume it
   125	  -- (observability); enforce membership only when the flag is on so the
   126	  -- batch-aware client can roll out first.
   127	  UPDATE public.beacon_token_batch b SET consumed_at = COALESCE(b.consumed_at, v_now)
   128	  WHERE b.token = lower(p_token) AND b.user_id = v_uid
   129	  RETURNING TRUE INTO v_in_batch;
   130	  IF NOT COALESCE(v_in_batch, FALSE)
   131	     AND COALESCE((SELECT value_num FROM public.app_settings WHERE key='enforce_batch_tokens'), 0) >= 1 THEN
   132	    RAISE EXCEPTION 'Beacon token was not issued to this account' USING ERRCODE='22023';
   133	  END IF;
   134	
   135	  SELECT last_claimed_at INTO v_last FROM public.token_claims WHERE user_id = v_uid;
   136	  IF v_last IS NOT NULL AND v_last > v_now - INTERVAL '5 seconds' THEN
   137	    RAISE EXCEPTION 'Beacon claim rate limit' USING ERRCODE='54000'; END IF;
   138	
   139	  INSERT INTO public.token_claims (
   140	    user_id, token, valid_from, valid_until, approx_lat, approx_lon,
   141	    range_type, accuracy_m, created_at, last_claimed_at)
   142	  VALUES (v_uid, lower(p_token), v_now, p_valid_until, p_lat, p_lon, p_range, p_accuracy, v_now, v_now)
   143	  ON CONFLICT (user_id) DO UPDATE SET
   144	    token = EXCLUDED.token, valid_from = EXCLUDED.valid_from, valid_until = EXCLUDED.valid_until,
   145	    approx_lat = EXCLUDED.approx_lat, approx_lon = EXCLUDED.approx_lon,
   146	    range_type = EXCLUDED.range_type, accuracy_m = EXCLUDED.accuracy_m,
   147	    last_claimed_at = EXCLUDED.last_claimed_at;
   148	
   149	  INSERT INTO public.token_claim_history
   150	    (token, user_id, valid_from, valid_until, approx_lat, approx_lon, range_type, accuracy_m, created_at)
   151	  VALUES (lower(p_token), v_uid, v_now, p_valid_until, p_lat, p_lon, p_range, p_accuracy, v_now)
   152	  ON CONFLICT (token) DO UPDATE SET
   153	    valid_until = EXCLUDED.valid_until,
   154	    -- 0060: fill geo fields on a batch-pre-claimed (NULL-location) row; never
   155	    -- blank out a fix an earlier single claim already wrote.
   156	    approx_lat = COALESCE(EXCLUDED.approx_lat, public.token_claim_history.approx_lat),
   157	    approx_lon = COALESCE(EXCLUDED.approx_lon, public.token_claim_history.approx_lon),
   158	    range_type = COALESCE(EXCLUDED.range_type, public.token_claim_history.range_type),
   159	    accuracy_m = COALESCE(EXCLUDED.accuracy_m, public.token_claim_history.accuracy_m);
   160	END;
   161	$function$;

exec
/bin/bash -lc "rtk rg -n \"release_token\" supabase/migrations
rtk rg -n \"token_claims\" supabase/migrations/00{2[8-9],3[0-9],4[0-9],5[0-9],6[0-3]}*.sql
nl -ba supabase/migrations/0019_beta_security_hardening.sql | sed -n '90,135p;425,485p;1050,1135p;2470,2555p'
nl -ba supabase/migrations/0035_account_deletion_completeness.sql | sed -n '1,180p'" in /home/hazypiff/in-range
 succeeded in 0ms:
supabase/migrations/0019_beta_security_hardening.sql:877:CREATE OR REPLACE FUNCTION public.release_token()
supabase/migrations/0019_beta_security_hardening.sql:2497:        'claim_token', 'release_token', 'record_sighting',
supabase/migrations/0019_beta_security_hardening.sql:2539:        'claim_token', 'release_token', 'record_sighting', 'get_my_encounters',
supabase/migrations/0028_token_claim_history.sql:2:-- new claim_token OVERWRITES it; release_token DELETES it. A peer that observed
supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql:69:  SELECT last_claimed_at INTO v_last FROM public.token_claims WHERE user_id = v_uid;
supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql:73:  INSERT INTO public.token_claims (
supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql:213:    DELETE FROM public.token_claims tc
supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql:221:         SELECT 1 FROM public.token_claims tc
supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql:248:    DELETE FROM public.token_claims
supabase/migrations/0037_legal_hold.sql:169:  DELETE FROM public.token_claims        WHERE user_id          = p_uid;
supabase/migrations/0060_batch_token_preclaim.sql:135:  SELECT last_claimed_at INTO v_last FROM public.token_claims WHERE user_id = v_uid;
supabase/migrations/0060_batch_token_preclaim.sql:139:  INSERT INTO public.token_claims (
supabase/migrations/0047_privilege_retention_consent.sql:117:    DELETE FROM public.token_claims tc
supabase/migrations/0047_privilege_retention_consent.sql:125:         SELECT 1 FROM public.token_claims tc
supabase/migrations/0047_privilege_retention_consent.sql:138:    DELETE FROM public.token_claims
supabase/migrations/0048_gps_scope_and_retention.sql:76:  SELECT last_claimed_at INTO v_last FROM public.token_claims WHERE user_id = v_uid;
supabase/migrations/0048_gps_scope_and_retention.sql:80:  INSERT INTO public.token_claims (
supabase/migrations/0048_gps_scope_and_retention.sql:188:    DELETE FROM public.token_claims tc
supabase/migrations/0048_gps_scope_and_retention.sql:196:         SELECT 1 FROM public.token_claims tc
supabase/migrations/0048_gps_scope_and_retention.sql:209:    DELETE FROM public.token_claims
supabase/migrations/0059_proximity_wake_producer.sql:237:  DELETE FROM public.token_claims            WHERE user_id          = p_uid;
supabase/migrations/0059_proximity_wake_producer.sql:490:    DELETE FROM public.token_claims tc
supabase/migrations/0059_proximity_wake_producer.sql:498:         SELECT 1 FROM public.token_claims tc
supabase/migrations/0059_proximity_wake_producer.sql:525:    DELETE FROM public.token_claims
supabase/migrations/0046_withdrawal_enforcement.sql:5:--   1. BLE: withdrawal deleted token_claims but token_claim_history stayed
supabase/migrations/0046_withdrawal_enforcement.sql:90:           (SELECT token FROM public.token_claims       WHERE user_id = v_uid
supabase/migrations/0046_withdrawal_enforcement.sql:94:    DELETE FROM public.token_claims        WHERE user_id = v_uid;
supabase/migrations/0046_withdrawal_enforcement.sql:186:             (SELECT token FROM public.token_claims       WHERE user_id = v_uid
supabase/migrations/0046_withdrawal_enforcement.sql:190:      DELETE FROM public.token_claims        WHERE user_id = v_uid;
supabase/migrations/0045_withdrawal_effectiveness.sql:125:           (SELECT token FROM public.token_claims WHERE user_id = v_uid);
supabase/migrations/0045_withdrawal_effectiveness.sql:127:    DELETE FROM public.token_claims WHERE user_id = v_uid;
supabase/migrations/0058_subtle_wake_privacy.sql:116:  DELETE FROM public.token_claims            WHERE user_id          = p_uid;
supabase/migrations/0058_subtle_wake_privacy.sql:373:    DELETE FROM public.token_claims tc
supabase/migrations/0058_subtle_wake_privacy.sql:381:         SELECT 1 FROM public.token_claims tc
supabase/migrations/0058_subtle_wake_privacy.sql:408:    DELETE FROM public.token_claims
supabase/migrations/0044_evidence_preservation.sql:17:--       location_pings / sightings / token_claims — material to a
supabase/migrations/0044_evidence_preservation.sql:201:  DELETE FROM public.token_claims        WHERE user_id          = p_uid;
supabase/migrations/0044_evidence_preservation.sql:347:--    their preserved token_claims. Also enforces report_evidence retention.
supabase/migrations/0044_evidence_preservation.sql:362:    DELETE FROM public.token_claims tc
supabase/migrations/0044_evidence_preservation.sql:370:         SELECT 1 FROM public.token_claims tc
supabase/migrations/0044_evidence_preservation.sql:378:    DELETE FROM public.token_claims
supabase/migrations/0056_calibration_rssi_samples.sql:262:  DELETE FROM public.token_claims        WHERE user_id          = p_uid;
supabase/migrations/0056_calibration_rssi_samples.sql:491:    DELETE FROM public.token_claims tc
supabase/migrations/0056_calibration_rssi_samples.sql:499:         SELECT 1 FROM public.token_claims tc
supabase/migrations/0056_calibration_rssi_samples.sql:517:    DELETE FROM public.token_claims
supabase/migrations/0031_server_issued_token_batches.sql:141:  SELECT last_claimed_at INTO v_last FROM public.token_claims WHERE user_id = v_uid;
supabase/migrations/0031_server_issued_token_batches.sql:145:  INSERT INTO public.token_claims (
supabase/migrations/0028_token_claim_history.sql:1:-- #5: token_claims is one row per user (uq_token_claims_user). On rotation the
supabase/migrations/0028_token_claim_history.sql:36:FROM public.token_claims
supabase/migrations/0028_token_claim_history.sql:67:  SELECT last_claimed_at INTO v_last FROM public.token_claims WHERE user_id = v_uid;
supabase/migrations/0028_token_claim_history.sql:71:  INSERT INTO public.token_claims (
supabase/migrations/0040_wire_consent_gates.sql:69:  SELECT last_claimed_at INTO v_last FROM public.token_claims WHERE user_id = v_uid;
supabase/migrations/0040_wire_consent_gates.sql:73:  INSERT INTO public.token_claims (
supabase/migrations/0035_account_deletion_completeness.sql:121:  DELETE FROM public.token_claims        WHERE user_id          = p_uid;
    90	ALTER TABLE public.ai_feedback
    91	  DROP CONSTRAINT IF EXISTS ai_feedback_metadata_size_check;
    92	ALTER TABLE public.ai_feedback
    93	  ADD CONSTRAINT ai_feedback_metadata_size_check
    94	  CHECK (octet_length(metadata::TEXT) <= 16384) NOT VALID;
    95	
    96	ALTER TABLE public.photo_verifications
    97	  ADD COLUMN IF NOT EXISTS storage_object_id UUID,
    98	  ADD COLUMN IF NOT EXISTS storage_object_updated_at TIMESTAMPTZ;
    99	
   100	ALTER TABLE public.token_claims
   101	  ADD COLUMN IF NOT EXISTS last_claimed_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
   102	
   103	-- One current row per user and one owner per unguessable advertised token.
   104	DELETE FROM public.token_claims older
   105	USING public.token_claims newer
   106	WHERE older.user_id = newer.user_id
   107	  AND (older.valid_from, older.id) < (newer.valid_from, newer.id);
   108	
   109	DELETE FROM public.token_claims older
   110	USING public.token_claims newer
   111	WHERE older.token = newer.token
   112	  AND older.id < newer.id;
   113	
   114	CREATE UNIQUE INDEX IF NOT EXISTS uq_token_claims_user
   115	  ON public.token_claims (user_id);
   116	CREATE UNIQUE INDEX IF NOT EXISTS uq_token_claims_token
   117	  ON public.token_claims (token);
   118	
   119	ALTER TABLE public.notification_outbox
   120	  DROP CONSTRAINT IF EXISTS notification_outbox_status_check;
   121	ALTER TABLE public.notification_outbox
   122	  ADD COLUMN IF NOT EXISTS processing_at TIMESTAMPTZ;
   123	ALTER TABLE public.notification_outbox
   124	  ADD CONSTRAINT notification_outbox_status_check
   125	  CHECK (status IN ('pending', 'processing', 'sent', 'failed', 'skipped'));
   126	
   127	CREATE TABLE IF NOT EXISTS public.app_settings (
   128	  key         TEXT PRIMARY KEY,
   129	  value_num   NUMERIC NOT NULL,
   130	  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
   131	);
   132	
   133	ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;
   134	
   135	DROP POLICY IF EXISTS "Service role manages app settings" ON public.app_settings;
   425	    SELECT 1 FROM pg_publication_tables
   426	    WHERE pubname = 'supabase_realtime'
   427	      AND schemaname = 'public' AND tablename = 'encounter_actions'
   428	  ) THEN
   429	    ALTER PUBLICATION supabase_realtime DROP TABLE public.encounter_actions;
   430	  END IF;
   431	END $$;
   432	
   433	-- SECURITY DEFINER RPCs are the only mutation surface for application tables.
   434	REVOKE ALL ON TABLE
   435	  public.profiles,
   436	  public.token_claims,
   437	  public.sightings,
   438	  public.location_pings,
   439	  public.encounters,
   440	  public.encounter_actions,
   441	  public.matches,
   442	  public.messages,
   443	  public.photo_verifications,
   444	  public.blocks,
   445	  public.reports,
   446	  public.subscriptions,
   447	  public.boosts,
   448	  public.ad_impressions,
   449	  public.device_push_tokens,
   450	  public.notification_outbox,
   451	  public.ai_runs,
   452	  public.ai_events,
   453	  public.ai_feedback
   454	FROM PUBLIC, anon, authenticated;
   455	
   456	-- Edge Functions use the service role and still need ordinary SQL privileges;
   457	-- BYPASSRLS does not itself grant SELECT/INSERT/UPDATE/DELETE.
   458	GRANT ALL ON TABLE
   459	  public.profiles,
   460	  public.token_claims,
   461	  public.sightings,
   462	  public.location_pings,
   463	  public.encounters,
   464	  public.encounter_actions,
   465	  public.matches,
   466	  public.messages,
   467	  public.photo_verifications,
   468	  public.blocks,
   469	  public.reports,
   470	  public.subscriptions,
   471	  public.boosts,
   472	  public.ad_impressions,
   473	  public.device_push_tokens,
   474	  public.notification_outbox,
   475	  public.ai_runs,
   476	  public.ai_events,
   477	  public.ai_feedback,
   478	  public.app_settings
   479	TO service_role;
   480	
   481	REVOKE ALL ON TABLE public.v_pending_photo_reviews
   482	  FROM PUBLIC, anon, authenticated;
   483	GRANT SELECT ON TABLE public.v_pending_photo_reviews TO service_role;
   484	
   485	-- Chat history/realtime is the sole direct-table client read.
  1050	    v_distance := ST_Distance(
  1051	      ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography,
  1052	      ST_SetSRID(ST_MakePoint(v_claim.approx_lon, v_claim.approx_lat), 4326)::geography
  1053	    );
  1054	    IF v_distance > LEAST(100.0, GREATEST(5.0, p_radius_meters)) THEN
  1055	      RETURN;
  1056	    END IF;
  1057	  END IF;
  1058	
  1059	  v_user_a := LEAST(v_uid, v_claim.user_id);
  1060	  v_user_b := GREATEST(v_uid, v_claim.user_id);
  1061	  PERFORM pg_advisory_xact_lock(hashtextextended(v_user_a::TEXT || v_user_b::TEXT, 0));
  1062	
  1063	  SELECT id INTO v_enc_id
  1064	  FROM public.encounters
  1065	  WHERE user_a = v_user_a AND user_b = v_user_b AND status = 'active'
  1066	  ORDER BY encounter_time DESC
  1067	  LIMIT 1
  1068	  FOR UPDATE;
  1069	
  1070	  IF v_enc_id IS NULL THEN
  1071	    INSERT INTO public.encounters (
  1072	      user_a, user_b, neighborhood, encounter_time, last_seen_at,
  1073	      range_type, confidence, status
  1074	    ) VALUES (
  1075	      v_user_a, v_user_b, 'Near you', NOW(), NOW(),
  1076	      COALESCE(v_claim.range_type, 'feet_10'),
  1077	      CASE WHEN v_distance IS NULL THEN 0.8 ELSE
  1078	        LEAST(1.0, GREATEST(0.5, 1.0 - (v_distance / GREATEST(p_radius_meters, 1))))
  1079	      END,
  1080	      'active'
  1081	    ) RETURNING id INTO v_enc_id;
  1082	    v_new := TRUE;
  1083	  ELSE
  1084	    UPDATE public.encounters
  1085	    SET last_seen_at = NOW(),
  1086	        confidence = CASE WHEN v_distance IS NULL THEN confidence ELSE
  1087	          LEAST(1.0, GREATEST(0.5, 1.0 - (v_distance / GREATEST(p_radius_meters, 1))))
  1088	        END
  1089	    WHERE id = v_enc_id;
  1090	  END IF;
  1091	
  1092	  encounter_id := v_enc_id;
  1093	  other_user_id := v_claim.user_id;
  1094	  created_new := v_new;
  1095	  RETURN NEXT;
  1096	END;
  1097	$$;
  1098	
  1099	CREATE OR REPLACE FUNCTION public.get_my_encounters(
  1100	  p_limit INT DEFAULT 50,
  1101	  p_offset INT DEFAULT 0,
  1102	  p_min_age_hours NUMERIC DEFAULT 4
  1103	)
  1104	RETURNS TABLE (
  1105	  encounter_id BIGINT,
  1106	  other_user_id UUID,
  1107	  display_name TEXT,
  1108	  photo_urls TEXT[],
  1109	  neighborhood TEXT,
  1110	  encounter_time TIMESTAMPTZ,
  1111	  range_type public.range_type,
  1112	  my_action public.action_type,
  1113	  other_action public.action_type,
  1114	  status public.encounter_status,
  1115	  is_photo_verified BOOLEAN
  1116	)
  1117	LANGUAGE sql
  1118	STABLE
  1119	SECURITY DEFINER
  1120	SET search_path = pg_catalog, public
  1121	AS $$
  1122	  SELECT
  1123	    e.id,
  1124	    CASE WHEN e.user_a = auth.uid() THEN e.user_b ELSE e.user_a END,
  1125	    'Someone nearby'::TEXT,
  1126	    p.photo_urls,
  1127	    e.neighborhood,
  1128	    e.encounter_time,
  1129	    e.range_type,
  1130	    (SELECT ea.action FROM public.encounter_actions ea
  1131	     WHERE ea.user_id = auth.uid() AND ea.encounter_id = e.id),
  1132	    NULL::public.action_type, -- never leak another user's pre-match swipe
  1133	    e.status,
  1134	    TRUE
  1135	  FROM public.encounters e
  2470	  v_revealed_alerts := public.queue_revealed_encounter_alerts();
  2471	  v_expiring_alerts := public.queue_expiring_encounter_alerts();
  2472	  v_correlated := public.batch_correlate_recent_pings(45);
  2473	  RETURN jsonb_build_object(
  2474	    'expired_feet', v_expired_feet,
  2475	    'expired_matches', v_expired_matches,
  2476	    'revealed_alerts', v_revealed_alerts,
  2477	    'expiring_alerts', v_expiring_alerts,
  2478	    'new_miles_encounters', v_correlated,
  2479	    'ran_at', NOW()
  2480	  );
  2481	END;
  2482	$$;
  2483	
  2484	-- -----------------------------------------------------------------------------
  2485	-- 9. Explicit function allowlists (CREATE FUNCTION grants PUBLIC by default)
  2486	-- -----------------------------------------------------------------------------
  2487	
  2488	DO $$
  2489	DECLARE r RECORD;
  2490	BEGIN
  2491	  FOR r IN
  2492	    SELECT p.oid::regprocedure AS sig
  2493	    FROM pg_proc p
  2494	    JOIN pg_namespace n ON n.oid = p.pronamespace
  2495	    WHERE n.nspname = 'public'
  2496	      AND p.proname = ANY (ARRAY[
  2497	        'claim_token', 'release_token', 'record_sighting',
  2498	        'correlate_encounter', 'get_my_encounters',
  2499	        'record_location_ping', 'correlate_miles_encounters', 'get_locals_feed',
  2500	        'batch_correlate_recent_pings', 'range_radius_meters',
  2501	        'range_time_window_minutes', 'preferences_compatible', '_pref_matches',
  2502	        'swipe_encounter', 'swipe_user', 'get_my_matches', 'get_who_liked_you',
  2503	        'send_message', 'mark_messages_read', 'get_match_profile',
  2504	        'block_user', 'unblock_user', 'report_user', 'is_blocked_pair',
  2505	        'upsert_my_profile', 'get_my_profile', 'set_account_paused',
  2506	        'set_incognito', 'request_account_deletion', 'delete_my_location_history',
  2507	        'register_push_token', 'unregister_push_token',
  2508	        'submit_photo_for_verification', 'complete_ai_photo_review',
  2509	        'decide_photo_verification', 'stub_auto_approve_photo',
  2510	        'has_active_boost', 'is_subscriber',
  2511	        'cleanup_ephemeral_data', 'expire_feet_encounters',
  2512	        'expire_idle_matches', 'queue_revealed_encounter_alerts',
  2513	        'queue_expiring_encounter_alerts', 'run_maintenance',
  2514	        'claim_notification_batch', 'log_ai_run', 'complete_ai_run',
  2515	        'log_ai_event', 'submit_ai_feedback', 'backend_health',
  2516	        'encounter_reveal_delay_hours', 'is_discoverable_user',
  2517	        'current_user_can_discover', 'can_access_match',
  2518	        'can_view_profile_photos', 'can_modify_profile_photo',
  2519	        'handle_new_user', 'handle_updated_at', 'notify_on_new_encounter',
  2520	        'sync_subscription_flags'
  2521	      ])
  2522	  LOOP
  2523	    EXECUTE format(
  2524	      'REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated, service_role',
  2525	      r.sig
  2526	    );
  2527	  END LOOP;
  2528	END $$;
  2529	
  2530	DO $$
  2531	DECLARE r RECORD;
  2532	BEGIN
  2533	  FOR r IN
  2534	    SELECT p.oid::regprocedure AS sig
  2535	    FROM pg_proc p
  2536	    JOIN pg_namespace n ON n.oid = p.pronamespace
  2537	    WHERE n.nspname = 'public'
  2538	      AND p.proname = ANY (ARRAY[
  2539	        'claim_token', 'release_token', 'record_sighting', 'get_my_encounters',
  2540	        'record_location_ping', 'get_locals_feed', 'swipe_encounter',
  2541	        'swipe_user', 'get_my_matches', 'get_who_liked_you', 'send_message',
  2542	        'mark_messages_read', 'get_match_profile', 'block_user', 'unblock_user',
  2543	        'report_user', 'upsert_my_profile', 'get_my_profile',
  2544	        'set_account_paused', 'set_incognito', 'request_account_deletion',
  2545	        'delete_my_location_history', 'register_push_token',
  2546	        'unregister_push_token', 'submit_photo_for_verification',
  2547	        'submit_ai_feedback', 'backend_health', 'encounter_reveal_delay_hours',
  2548	        'can_access_match', 'can_view_profile_photos', 'can_modify_profile_photo'
  2549	      ])
  2550	  LOOP
  2551	    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', r.sig);
  2552	  END LOOP;
  2553	END $$;
  2554	
  2555	DO $$
     1	-- 0035_account_deletion_completeness.sql
     2	--
     3	-- Makes "delete my account" actually delete the account.
     4	--
     5	-- WHY (privacy audit 2026-07-19):
     6	--   The previous request_account_deletion() was a partial soft-delete. It
     7	--   scrubbed display_name/bio/photo_urls/interests but LEFT IN PLACE:
     8	--     * sexual_preference  <- regulated as sensitive/special-category data
     9	--     * dob                <- regulated PII, and the age-assurance input
    10	--     * email_hint / phone_hint / neighborhood
    11	--     * the auth.users row, chat message bodies, and storage objects
    12	--   Verified against production before this migration: 4 of 4 soft-deleted
    13	--   profiles still carried sexual_preference and dob.
    14	--
    15	--   There was also no hard-purge path at all, and one could not simply be
    16	--   added: matches.user_a/user_b, messages.sender_id, ad_impressions.user_id
    17	--   and ai_events.user_id are ON DELETE NO ACTION, so DELETE FROM auth.users
    18	--   raises a foreign-key violation for any user who ever matched or chatted.
    19	--   purge_deleted_accounts() below clears those dependents in FK order first.
    20	--
    21	-- MODEL: two phase.
    22	--   1. request_account_deletion() -- synchronous, irreversible PII scrub.
    23	--      Every regulated field is erased at request time, not at purge time,
    24	--      so the grace window never retains sensitive data.
    25	--   2. purge_deleted_accounts(grace) -- removes the residual pseudonymous
    26	--      rows and the auth.users row after the grace period. Wired into
    27	--      run_maintenance(), which already runs every 15 minutes via pg_cron.
    28	--
    29	--   Because phase 1 is irreversible there is deliberately NO account
    30	--   restore. "Deactivate" is a separate concept (is_paused) and remains.
    31	
    32	BEGIN;
    33	
    34	-- dob must be nullable for deletion to erase it. This does NOT relax the
    35	-- app-level requirement: upsert_profile() still raises 'Date of birth
    36	-- required' when a live profile omits it.
    37	ALTER TABLE public.profiles ALTER COLUMN dob DROP NOT NULL;
    38	
    39	-- Retention knob. Purge runs once a profile has been deleted for this long.
    40	INSERT INTO public.app_settings (key, value_num)
    41	VALUES ('deletion_grace_days', 30)
    42	ON CONFLICT (key) DO NOTHING;
    43	
    44	CREATE INDEX IF NOT EXISTS idx_profiles_deleted_at
    45	  ON public.profiles (deleted_at) WHERE deleted_at IS NOT NULL;
    46	
    47	-- Storage objects belonging to deleted accounts. SQL cannot delete these
    48	-- directly (Supabase blocks DELETE on storage.objects), so deletion requests
    49	-- are recorded here and drained by a service-role worker via the Storage API.
    50	-- That worker is drainStorageDeletionQueue() in the `maintenance` Edge
    51	-- Function, on the same 15-minute cadence; until it runs, photos of deleted
    52	-- accounts remain in the buckets, so it is the step that actually completes an
    53	-- erasure request. Rows are kept after deletion, with deleted_at stamped, as
    54	-- the audit trail proving the erasure happened.
    55	CREATE TABLE IF NOT EXISTS public.storage_deletion_queue (
    56	  id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    57	  user_id      UUID NOT NULL,
    58	  bucket_id    TEXT NOT NULL,
    59	  object_name  TEXT NOT NULL,
    60	  requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    61	  deleted_at   TIMESTAMPTZ,
    62	  last_error   TEXT,
    63	  UNIQUE (bucket_id, object_name)
    64	);
    65	
    66	CREATE INDEX IF NOT EXISTS idx_storage_deletion_queue_pending
    67	  ON public.storage_deletion_queue (requested_at) WHERE deleted_at IS NULL;
    68	
    69	ALTER TABLE public.storage_deletion_queue ENABLE ROW LEVEL SECURITY;
    70	-- No policies: service_role bypasses RLS, app users have no access at all.
    71	REVOKE ALL ON TABLE public.storage_deletion_queue FROM PUBLIC, anon, authenticated;
    72	GRANT SELECT, INSERT, UPDATE ON TABLE public.storage_deletion_queue TO service_role;
    73	
    74	COMMENT ON TABLE public.storage_deletion_queue IS
    75	  'Storage objects owned by deleted accounts, pending erasure through the Storage API by a service-role worker. deleted_at stamps completion.';
    76	
    77	-- ---------------------------------------------------------------------------
    78	-- Phase 1 helper: erase every piece of regulated data we hold for one user.
    79	-- Split out from the RPC so the backfill and the purge can reuse it.
    80	-- ---------------------------------------------------------------------------
    81	-- Dropped first so this migration stays re-appliable: 0037 redefines this
    82	-- function as RETURNS BOOLEAN, and Postgres will not change a return type in
    83	-- place. Without the drop, replaying the migration set fails here.
    84	DROP FUNCTION IF EXISTS public.scrub_account_pii(UUID);
    85	
    86	CREATE OR REPLACE FUNCTION public.scrub_account_pii(p_uid UUID)
    87	RETURNS VOID
    88	LANGUAGE plpgsql
    89	SECURITY DEFINER
    90	SET search_path = pg_catalog, public
    91	AS $$
    92	BEGIN
    93	  IF p_uid IS NULL THEN
    94	    RAISE EXCEPTION 'scrub_account_pii requires a user id';
    95	  END IF;
    96	
    97	  UPDATE public.profiles SET
    98	    display_name              = 'Deleted user',
    99	    bio                       = NULL,
   100	    dob                       = NULL,   -- regulated PII
   101	    gender                    = NULL,   -- sensitive
   102	    sexual_preference         = NULL,   -- special-category / sensitive
   103	    interests                 = NULL,
   104	    photo_urls                = NULL,
   105	    neighborhood              = NULL,
   106	    email_hint                = NULL,
   107	    phone_hint                = NULL,
   108	    photo_verification_status = NULL,
   109	    is_photo_verified         = FALSE,
   110	    age_verified              = FALSE,
   111	    is_active                 = FALSE,
   112	    is_paused                 = TRUE,
   113	    is_incognito              = FALSE,
   114	    last_active_at            = NULL,
   115	    deleted_at                = COALESCE(deleted_at, NOW()),
   116	    updated_at                = NOW()
   117	  WHERE id = p_uid;
   118	
   119	  -- Proximity + beacon telemetry: no reason to retain any of it.
   120	  DELETE FROM public.location_pings      WHERE user_id          = p_uid;
   121	  DELETE FROM public.token_claims        WHERE user_id          = p_uid;
   122	  DELETE FROM public.token_claim_history WHERE user_id          = p_uid;
   123	  DELETE FROM public.sightings           WHERE observer_user_id = p_uid;
   124	  DELETE FROM public.beacon_token_batch  WHERE user_id          = p_uid;
   125	  DELETE FROM public.device_attestations WHERE user_id          = p_uid;
   126	
   127	  -- Device / delivery identifiers.
   128	  DELETE FROM public.device_push_tokens  WHERE user_id = p_uid;
   129	  DELETE FROM public.notification_outbox WHERE user_id = p_uid;
   130	
   131	  -- Face/photo verification artifacts.
   132	  DELETE FROM public.photo_verifications WHERE user_id = p_uid;
   133	
   134	  -- Stored files. Supabase forbids DELETE on storage.objects from SQL
   135	  -- ("Direct deletion from storage tables is not allowed. Use the Storage
   136	  -- API instead."), so we enqueue the objects and a service-role worker
   137	  -- drains the queue through the Storage API. Path convention is <uid>/...
   138	  -- for profile + verified photos and <match_id>/<uid>/... for chat media
   139	  -- (see the 0019 storage policies).
   140	  INSERT INTO public.storage_deletion_queue (user_id, bucket_id, object_name)
   141	  SELECT p_uid, o.bucket_id, o.name
   142	    FROM storage.objects o
   143	   WHERE (o.bucket_id IN ('profile_photos', 'verified_photos')
   144	            AND (storage.foldername(o.name))[1] = p_uid::TEXT)
   145	      OR (o.bucket_id = 'chat_media'
   146	            AND (storage.foldername(o.name))[2] = p_uid::TEXT)
   147	  ON CONFLICT (bucket_id, object_name) DO NOTHING;
   148	
   149	  -- Chat bodies are the sender's personal data, but the rows are load-bearing
   150	  -- for the counterpart's thread. Redact content, keep the shell.
   151	  -- CASE keeps messages_payload_check satisfied: 'text' needs non-empty
   152	  -- content, media types do not.
   153	  UPDATE public.messages
   154	     SET content  = CASE WHEN message_type = 'text' THEN '[deleted]' ELSE NULL END,
   155	         metadata = NULL
   156	   WHERE sender_id = p_uid;
   157	
   158	  -- Analytics rows survive de-identified rather than being destroyed.
   159	  UPDATE public.ad_impressions SET user_id = NULL WHERE user_id = p_uid;
   160	  UPDATE public.ai_events      SET user_id = NULL WHERE user_id = p_uid;
   161	END;
   162	$$;
   163	
   164	COMMENT ON FUNCTION public.scrub_account_pii IS
   165	  'Irreversibly erases all regulated personal data for one user. Called by request_account_deletion(); reused by purge and backfill.';
   166	
   167	REVOKE ALL ON FUNCTION public.scrub_account_pii(UUID) FROM PUBLIC, anon, authenticated;
   168	GRANT EXECUTE ON FUNCTION public.scrub_account_pii(UUID) TO service_role;
   169	
   170	-- ---------------------------------------------------------------------------
   171	-- Phase 1 RPC: what the app calls. Self-service, caller can only delete self.
   172	-- ---------------------------------------------------------------------------
   173	CREATE OR REPLACE FUNCTION public.request_account_deletion()
   174	RETURNS VOID
   175	LANGUAGE plpgsql
   176	SECURITY DEFINER
   177	SET search_path = pg_catalog, public
   178	AS $$
   179	DECLARE
   180	  v_uid UUID := auth.uid();

exec
/bin/bash -lc "nl -ba supabase/migrations/0019_beta_security_hardening.sql | sed -n '800,910p'
nl -ba supabase/migrations/0028_token_claim_history.sql | sed -n '1,110p'
nl -ba supabase/migrations/0046_withdrawal_enforcement.sql | sed -n '60,115p;155,205p'" in /home/hazypiff/in-range
 succeeded in 0ms:
   800	    NULLIF(trim(p_label), ''), NULLIF(trim(p_notes), ''),
   801	    COALESCE(p_metadata, '{}'::JSONB)
   802	  ) RETURNING id INTO v_id;
   803	  RETURN v_id;
   804	END;
   805	$$;
   806	
   807	-- -----------------------------------------------------------------------------
   808	-- 4. Ephemeral claims and BLE sightings
   809	-- -----------------------------------------------------------------------------
   810	
   811	CREATE OR REPLACE FUNCTION public.claim_token(
   812	  p_token TEXT,
   813	  p_valid_until TIMESTAMPTZ,
   814	  p_lat DOUBLE PRECISION DEFAULT NULL,
   815	  p_lon DOUBLE PRECISION DEFAULT NULL,
   816	  p_range public.range_type DEFAULT 'miles_10'
   817	)
   818	RETURNS VOID
   819	LANGUAGE plpgsql
   820	SECURITY DEFINER
   821	SET search_path = pg_catalog, public
   822	AS $$
   823	DECLARE
   824	  v_uid UUID := auth.uid();
   825	  v_now TIMESTAMPTZ := clock_timestamp();
   826	  v_last TIMESTAMPTZ;
   827	BEGIN
   828	  IF v_uid IS NULL THEN
   829	    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '28000';
   830	  END IF;
   831	  IF NOT public.current_user_can_discover() THEN
   832	    RAISE EXCEPTION 'Complete age and photo verification before using Beacon'
   833	      USING ERRCODE = '42501';
   834	  END IF;
   835	  IF p_token IS NULL OR p_token !~ '^[0-9a-f]{32}$' THEN
   836	    RAISE EXCEPTION 'Invalid beacon token' USING ERRCODE = '22023';
   837	  END IF;
   838	  IF p_valid_until IS NULL
   839	     OR p_valid_until <= v_now + INTERVAL '1 minute'
   840	     OR p_valid_until > v_now + INTERVAL '21 minutes' THEN
   841	    RAISE EXCEPTION 'Token validity must end within 1..21 minutes'
   842	      USING ERRCODE = '22023';
   843	  END IF;
   844	  IF p_lat IS NULL OR p_lon IS NULL THEN
   845	    RAISE EXCEPTION 'Fresh coordinates are required' USING ERRCODE = '22023';
   846	  END IF;
   847	  IF p_lat NOT BETWEEN -90 AND 90 OR p_lon NOT BETWEEN -180 AND 180 THEN
   848	    RAISE EXCEPTION 'Invalid coordinates' USING ERRCODE = '22023';
   849	  END IF;
   850	
   851	  SELECT last_claimed_at INTO v_last
   852	  FROM public.token_claims
   853	  WHERE user_id = v_uid;
   854	  IF v_last IS NOT NULL AND v_last > v_now - INTERVAL '5 seconds' THEN
   855	    RAISE EXCEPTION 'Beacon claim rate limit' USING ERRCODE = '54000';
   856	  END IF;
   857	
   858	  INSERT INTO public.token_claims (
   859	    user_id, token, valid_from, valid_until, approx_lat, approx_lon,
   860	    range_type, created_at, last_claimed_at
   861	  )
   862	  VALUES (
   863	    v_uid, lower(p_token), v_now, p_valid_until, p_lat, p_lon,
   864	    p_range, v_now, v_now
   865	  )
   866	  ON CONFLICT (user_id) DO UPDATE SET
   867	    token = EXCLUDED.token,
   868	    valid_from = EXCLUDED.valid_from,
   869	    valid_until = EXCLUDED.valid_until,
   870	    approx_lat = EXCLUDED.approx_lat,
   871	    approx_lon = EXCLUDED.approx_lon,
   872	    range_type = EXCLUDED.range_type,
   873	    last_claimed_at = EXCLUDED.last_claimed_at;
   874	END;
   875	$$;
   876	
   877	CREATE OR REPLACE FUNCTION public.release_token()
   878	RETURNS VOID
   879	LANGUAGE sql
   880	SECURITY DEFINER
   881	SET search_path = pg_catalog, public
   882	AS $$
   883	  DELETE FROM public.token_claims WHERE user_id = auth.uid();
   884	$$;
   885	
   886	CREATE OR REPLACE FUNCTION public.record_sighting(
   887	  p_observed_token TEXT,
   888	  p_lat DOUBLE PRECISION DEFAULT NULL,
   889	  p_lon DOUBLE PRECISION DEFAULT NULL,
   890	  p_rssi INTEGER DEFAULT NULL,
   891	  p_observed_at TIMESTAMPTZ DEFAULT NOW(),
   892	  p_range public.range_type DEFAULT NULL
   893	)
   894	RETURNS BIGINT
   895	LANGUAGE plpgsql
   896	SECURITY DEFINER
   897	SET search_path = pg_catalog, public
   898	AS $$
   899	DECLARE
   900	  v_uid UUID := auth.uid();
   901	  v_now TIMESTAMPTZ := clock_timestamp();
   902	  v_id BIGINT;
   903	  v_range public.range_type := COALESCE(p_range, 'feet_10');
   904	  v_radius DOUBLE PRECISION;
   905	  v_window INT;
   906	BEGIN
   907	  IF v_uid IS NULL THEN
   908	    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '28000';
   909	  END IF;
   910	  IF NOT public.current_user_can_discover() THEN
     1	-- #5: token_claims is one row per user (uq_token_claims_user). On rotation the
     2	-- new claim_token OVERWRITES it; release_token DELETES it. A peer that observed
     3	-- the OLD token and buffers the sighting for up to 45 s then uploads it — but
     4	-- the mapping row is gone, so record_sighting / correlate_encounter reject it
     5	-- with "Unknown or expired beacon token." The 2-minute validity grace cannot
     6	-- help because the row no longer exists.
     7	--
     8	-- Fix: keep a short-lived, append-only claim HISTORY. Every claim is also
     9	-- written to token_claim_history; token lookups consult BOTH the live claim and
    10	-- history within valid_until + grace. Ownership stays unique (advertising still
    11	-- uses one live token); release stops advertising without erasing the grace-
    12	-- window mapping. History is pruned by the existing cleanup path.
    13	
    14	CREATE TABLE IF NOT EXISTS public.token_claim_history (
    15	  token       TEXT PRIMARY KEY,
    16	  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    17	  valid_from  TIMESTAMPTZ NOT NULL,
    18	  valid_until TIMESTAMPTZ NOT NULL,
    19	  approx_lat  DOUBLE PRECISION,
    20	  approx_lon  DOUBLE PRECISION,
    21	  range_type  public.range_type,
    22	  accuracy_m  DOUBLE PRECISION,
    23	  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
    24	);
    25	CREATE INDEX IF NOT EXISTS idx_token_claim_history_valid
    26	  ON public.token_claim_history (token, valid_until);
    27	CREATE INDEX IF NOT EXISTS idx_token_claim_history_expiry
    28	  ON public.token_claim_history (valid_until);
    29	ALTER TABLE public.token_claim_history ENABLE ROW LEVEL SECURITY;
    30	-- No policies: only SECURITY DEFINER RPCs read/write it.
    31	
    32	-- Backfill the current live claims so nothing is lost at deploy time.
    33	INSERT INTO public.token_claim_history
    34	  (token, user_id, valid_from, valid_until, approx_lat, approx_lon, range_type, accuracy_m, created_at)
    35	SELECT token, user_id, valid_from, valid_until, approx_lat, approx_lon, range_type, accuracy_m, created_at
    36	FROM public.token_claims
    37	ON CONFLICT (token) DO NOTHING;
    38	
    39	-- claim_token: write to history in addition to the live one-row-per-user claim.
    40	CREATE OR REPLACE FUNCTION public.claim_token(
    41	  p_token TEXT, p_valid_until TIMESTAMPTZ,
    42	  p_lat DOUBLE PRECISION DEFAULT NULL, p_lon DOUBLE PRECISION DEFAULT NULL,
    43	  p_range public.range_type DEFAULT 'miles_10', p_accuracy DOUBLE PRECISION DEFAULT NULL
    44	)
    45	RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
    46	AS $$
    47	DECLARE
    48	  v_uid UUID := auth.uid();
    49	  v_now TIMESTAMPTZ := clock_timestamp();
    50	  v_last TIMESTAMPTZ;
    51	BEGIN
    52	  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;
    53	  IF NOT public.current_user_can_discover() THEN
    54	    RAISE EXCEPTION 'Complete age and photo verification before using Beacon' USING ERRCODE='42501'; END IF;
    55	  IF p_token IS NULL OR p_token !~ '^[0-9a-f]{32}$' THEN
    56	    RAISE EXCEPTION 'Invalid beacon token' USING ERRCODE='22023'; END IF;
    57	  IF p_valid_until IS NULL OR p_valid_until <= v_now + INTERVAL '1 minute'
    58	     OR p_valid_until > v_now + INTERVAL '21 minutes' THEN
    59	    RAISE EXCEPTION 'Token validity must end within 1..21 minutes' USING ERRCODE='22023'; END IF;
    60	  IF p_lat IS NULL OR p_lon IS NULL THEN
    61	    RAISE EXCEPTION 'Fresh coordinates are required' USING ERRCODE='22023'; END IF;
    62	  IF p_lat NOT BETWEEN -90 AND 90 OR p_lon NOT BETWEEN -180 AND 180 THEN
    63	    RAISE EXCEPTION 'Invalid coordinates' USING ERRCODE='22023'; END IF;
    64	  IF p_accuracy IS NOT NULL AND (p_accuracy < 0 OR p_accuracy > 10000) THEN
    65	    RAISE EXCEPTION 'Invalid accuracy' USING ERRCODE='22023'; END IF;
    66	
    67	  SELECT last_claimed_at INTO v_last FROM public.token_claims WHERE user_id = v_uid;
    68	  IF v_last IS NOT NULL AND v_last > v_now - INTERVAL '5 seconds' THEN
    69	    RAISE EXCEPTION 'Beacon claim rate limit' USING ERRCODE='54000'; END IF;
    70	
    71	  INSERT INTO public.token_claims (
    72	    user_id, token, valid_from, valid_until, approx_lat, approx_lon,
    73	    range_type, accuracy_m, created_at, last_claimed_at)
    74	  VALUES (v_uid, lower(p_token), v_now, p_valid_until, p_lat, p_lon, p_range, p_accuracy, v_now, v_now)
    75	  ON CONFLICT (user_id) DO UPDATE SET
    76	    token = EXCLUDED.token, valid_from = EXCLUDED.valid_from, valid_until = EXCLUDED.valid_until,
    77	    approx_lat = EXCLUDED.approx_lat, approx_lon = EXCLUDED.approx_lon,
    78	    range_type = EXCLUDED.range_type, accuracy_m = EXCLUDED.accuracy_m,
    79	    last_claimed_at = EXCLUDED.last_claimed_at;
    80	
    81	  -- Append to history so a peer's buffered sighting of THIS token still
    82	  -- resolves for valid_until + grace even after the next rotation/release.
    83	  INSERT INTO public.token_claim_history
    84	    (token, user_id, valid_from, valid_until, approx_lat, approx_lon, range_type, accuracy_m, created_at)
    85	  VALUES (lower(p_token), v_uid, v_now, p_valid_until, p_lat, p_lon, p_range, p_accuracy, v_now)
    86	  ON CONFLICT (token) DO UPDATE SET valid_until = EXCLUDED.valid_until;
    87	END;
    88	$$;
    89	GRANT EXECUTE ON FUNCTION public.claim_token(
    90	  TEXT, TIMESTAMPTZ, DOUBLE PRECISION, DOUBLE PRECISION, public.range_type, DOUBLE PRECISION
    91	) TO authenticated;
    92	
    93	-- A single lookup used by record_sighting/correlate_encounter: the live claim
    94	-- OR a recent history row (within valid_until + 2 min grace).
    95	CREATE OR REPLACE FUNCTION public.lookup_claim(p_token TEXT)
    96	RETURNS public.token_claim_history
    97	LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
    98	AS $$
    99	  SELECT token, user_id, valid_from, valid_until, approx_lat, approx_lon,
   100	         range_type, accuracy_m, created_at
   101	  FROM public.token_claim_history
   102	  WHERE token = lower(p_token) AND valid_until > NOW() - INTERVAL '2 minutes'
   103	  ORDER BY valid_from DESC LIMIT 1;
   104	$$;
   105	
   106	-- record_sighting + correlate_encounter now resolve the observed token against
   107	-- HISTORY, so a sighting buffered across a rotation/release still correlates.
   108	CREATE OR REPLACE FUNCTION public.record_sighting(
   109	  p_observed_token TEXT, p_lat DOUBLE PRECISION DEFAULT NULL, p_lon DOUBLE PRECISION DEFAULT NULL,
   110	  p_rssi INTEGER DEFAULT NULL, p_observed_at TIMESTAMPTZ DEFAULT NOW(),
    60	SECURITY DEFINER
    61	SET search_path = pg_catalog, public
    62	AS $$
    63	DECLARE
    64	  v_uid  UUID := auth.uid();
    65	  v_hit  BOOLEAN;
    66	  v_held BOOLEAN;
    67	BEGIN
    68	  IF v_uid IS NULL THEN
    69	    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
    70	  END IF;
    71	
    72	  UPDATE public.consent_records
    73	     SET withdrawn_at = NOW()
    74	   WHERE user_id = v_uid AND purpose = p_purpose AND withdrawn_at IS NULL
    75	  RETURNING TRUE INTO v_hit;
    76	
    77	  IF NOT COALESCE(v_hit, FALSE) THEN
    78	    RETURN FALSE;
    79	  END IF;
    80	
    81	  v_held := public.has_legal_hold(v_uid);
    82	
    83	  IF p_purpose IN ('precise_location', 'background_location') AND NOT v_held THEN
    84	    DELETE FROM public.location_pings WHERE user_id = v_uid;
    85	  END IF;
    86	
    87	  IF p_purpose = 'ble_proximity' AND NOT v_held THEN
    88	    DELETE FROM public.sightings s
    89	     WHERE s.observed_token IN
    90	           (SELECT token FROM public.token_claims       WHERE user_id = v_uid
    91	            UNION
    92	            SELECT token FROM public.token_claim_history WHERE user_id = v_uid);
    93	    DELETE FROM public.sightings          WHERE observer_user_id = v_uid;
    94	    DELETE FROM public.token_claims        WHERE user_id = v_uid;
    95	    DELETE FROM public.token_claim_history WHERE user_id = v_uid;
    96	  END IF;
    97	
    98	  IF p_purpose = 'photo_processing' THEN
    99	    UPDATE public.profiles
   100	       SET photo_urls = ARRAY[]::TEXT[],
   101	           is_photo_verified = FALSE,
   102	           photo_verification_status = 'pending'
   103	     WHERE id = v_uid;
   104	    UPDATE public.photo_verifications
   105	       SET state = 'rejected',
   106	           review_notes = COALESCE(review_notes || '; ', '')
   107	                          || 'cancelled: photo_processing consent withdrawn',
   108	           decided_at = NOW()
   109	     WHERE user_id = v_uid
   110	       AND state IN ('pending_upload', 'ai_review', 'ai_passed', 'manual_review');
   111	    IF NOT v_held THEN
   112	      INSERT INTO public.storage_deletion_queue (user_id, bucket_id, object_name)
   113	      SELECT v_uid, o.bucket_id, o.name
   114	        FROM storage.objects o
   115	       WHERE o.bucket_id IN ('profile_photos', 'verified_photos')
   155	  v_uid UUID;
   156	  v_n   INT := 0;
   157	BEGIN
   158	  FOR v_uid IN
   159	    SELECT DISTINCT c.user_id
   160	      FROM public.consent_records c
   161	     WHERE c.withdrawn_at IS NOT NULL
   162	       AND NOT public.has_legal_hold(c.user_id)
   163	       AND NOT EXISTS (
   164	         SELECT 1 FROM public.consent_records a
   165	          WHERE a.user_id = c.user_id AND a.purpose = c.purpose
   166	            AND a.withdrawn_at IS NULL)
   167	  LOOP
   168	    IF public.consent_withdrawn(v_uid, 'photo_processing') THEN
   169	      UPDATE public.profiles
   170	         SET photo_urls = ARRAY[]::TEXT[],
   171	             is_photo_verified = FALSE,
   172	             photo_verification_status = 'pending'
   173	       WHERE id = v_uid
   174	         AND (COALESCE(array_length(photo_urls, 1), 0) > 0 OR is_photo_verified);
   175	      INSERT INTO public.storage_deletion_queue (user_id, bucket_id, object_name)
   176	      SELECT v_uid, o.bucket_id, o.name
   177	        FROM storage.objects o
   178	       WHERE o.bucket_id IN ('profile_photos', 'verified_photos')
   179	         AND (storage.foldername(o.name))[1] = v_uid::TEXT
   180	      ON CONFLICT (bucket_id, object_name) DO NOTHING;
   181	    END IF;
   182	
   183	    IF public.consent_withdrawn(v_uid, 'ble_proximity') THEN
   184	      DELETE FROM public.sightings s
   185	       WHERE s.observed_token IN
   186	             (SELECT token FROM public.token_claims       WHERE user_id = v_uid
   187	              UNION
   188	              SELECT token FROM public.token_claim_history WHERE user_id = v_uid);
   189	      DELETE FROM public.sightings          WHERE observer_user_id = v_uid;
   190	      DELETE FROM public.token_claims        WHERE user_id = v_uid;
   191	      DELETE FROM public.token_claim_history WHERE user_id = v_uid;
   192	    END IF;
   193	
   194	    -- Only precise_location gates the GPS upload; background_location alone
   195	    -- (a user who kept foreground location) must not wipe their pings.
   196	    IF public.consent_withdrawn(v_uid, 'precise_location') THEN
   197	      DELETE FROM public.location_pings WHERE user_id = v_uid;
   198	    END IF;
   199	
   200	    v_n := v_n + 1;
   201	  END LOOP;
   202	  RETURN v_n;
   203	END;
   204	$$;
   205	

codex
The verbatim claim checks out mechanically: beyond the marked blocks, all three bodies match 0060/0053/0059 exactly. One substantive regression has emerged in the marked cleanup change, though: it sits outside the legal-hold branch and will purge held users’ batch rows. I’m validating the remaining exploit and concurrency implications before assigning the verdict.
exec
/bin/bash -lc "nl -ba supabase/migrations/0059_proximity_wake_producer.sql | sed -n '185,265p;470,590p'
nl -ba supabase/migrations/0037_legal_hold.sql | sed -n '1,230p'
rtk rg -n -C 5 \"beacon_token_batch\" supabase/migrations docs | head -n 300
rtk rg -n -C 6 \"cleanup_ephemeral_data\\(|run_maintenance\\(|cron\\.schedule|maintenance\" supabase/migrations/0049_schedule_maintenance_edge_worker.sql supabase/migrations/0059_proximity_wake_producer.sql supabase/migrations/0019_beta_security_hardening.sql supabase/config.toml" in /home/hazypiff/in-range
 succeeded in 0ms:
   185	  IF p_uid IS NULL THEN
   186	    RAISE EXCEPTION 'scrub_account_pii requires a user id';
   187	  END IF;
   188	
   189	  -- Preservation beats erasure. Deferred, not refused: request_account_deletion
   190	  -- still stamps deleted_at, so purge_deleted_accounts() completes this
   191	  -- automatically once the hold lifts.
   192	  IF public.has_legal_hold(p_uid) THEN
   193	    RETURN FALSE;
   194	  END IF;
   195	
   196	  -- Evidence before erasure (H1/H2): snapshot every OPEN report this account
   197	  -- is a party to. The reviewer still reviews; the snapshot just means the
   198	  -- redaction below cannot destroy what they would have reviewed.
   199	  FOR v_rid IN
   200	    SELECT id FROM public.reports
   201	     WHERE (reported_id = p_uid OR reporter_id = p_uid)
   202	       AND status IN ('open', 'reviewing')
   203	  LOOP
   204	    PERFORM public.snapshot_report_evidence(v_rid, 'scrub');
   205	  END LOOP;
   206	
   207	  -- A deleted account holds no live consents (the grant would otherwise stay
   208	  -- "active" through the 30-day grace). Direct UPDATE rather than
   209	  -- withdraw_consent(): that RPC reads auth.uid() and has side effects the
   210	  -- scrub already performs (location_pings goes below).
   211	  UPDATE public.consent_records SET withdrawn_at = NOW()
   212	   WHERE user_id = p_uid AND withdrawn_at IS NULL;
   213	
   214	  UPDATE public.profiles SET
   215	    display_name              = 'Deleted user',
   216	    bio                       = NULL,
   217	    dob                       = NULL,
   218	    gender                    = NULL,
   219	    sexual_preference         = NULL,
   220	    interests                 = NULL,
   221	    photo_urls                = NULL,
   222	    neighborhood              = NULL,
   223	    email_hint                = NULL,
   224	    phone_hint                = NULL,
   225	    photo_verification_status = NULL,
   226	    is_photo_verified         = FALSE,
   227	    age_verified              = FALSE,
   228	    is_active                 = FALSE,
   229	    is_paused                 = TRUE,
   230	    is_incognito              = FALSE,
   231	    last_active_at            = NULL,
   232	    deleted_at                = COALESCE(deleted_at, NOW()),
   233	    updated_at                = NOW()
   234	  WHERE id = p_uid;
   235	
   236	  DELETE FROM public.location_pings          WHERE user_id          = p_uid;
   237	  DELETE FROM public.token_claims            WHERE user_id          = p_uid;
   238	  DELETE FROM public.token_claim_history     WHERE user_id          = p_uid;
   239	  DELETE FROM public.sightings               WHERE observer_user_id = p_uid;
   240	  DELETE FROM public.beacon_token_batch      WHERE user_id          = p_uid;
   241	  DELETE FROM public.device_attestations     WHERE user_id          = p_uid;
   242	  DELETE FROM public.device_push_tokens      WHERE user_id          = p_uid;
   243	  DELETE FROM public.notification_outbox     WHERE user_id          = p_uid;
   244	  DELETE FROM public.photo_verifications     WHERE user_id          = p_uid;
   245	  DELETE FROM public.rssi_samples            WHERE user_id          = p_uid;
   246	  DELETE FROM public.venue_anchors           WHERE user_id          = p_uid;
   247	  DELETE FROM public.proximity_wake_requests WHERE user_id          = p_uid;
   248	  -- 0059: also remove rows where the user was the woken recipient.
   249	  DELETE FROM public.proximity_wake_requests WHERE recipient_user_id = p_uid;
   250	
   251	  INSERT INTO public.storage_deletion_queue (user_id, bucket_id, object_name)
   252	  SELECT p_uid, o.bucket_id, o.name
   253	    FROM storage.objects o
   254	   WHERE (o.bucket_id IN ('profile_photos', 'verified_photos')
   255	            AND (storage.foldername(o.name))[1] = p_uid::TEXT)
   256	      OR (o.bucket_id = 'chat_media'
   257	            AND (storage.foldername(o.name))[2] = p_uid::TEXT)
   258	  ON CONFLICT (bucket_id, object_name) DO NOTHING;
   259	
   260	  UPDATE public.messages
   261	     SET content  = CASE WHEN message_type = 'text' THEN '[deleted]' ELSE NULL END,
   262	         metadata = NULL
   263	   WHERE sender_id = p_uid;
   264	
   265	  UPDATE public.ad_impressions SET user_id = NULL WHERE user_id = p_uid;
   470	
   471	-- ---------------------------------------------------------------------------
   472	-- 5. Retention (cleanup_ephemeral_data)
   473	-- ---------------------------------------------------------------------------
   474	-- Body as of 0058_subtle_wake_privacy.sql:334, unchanged. proximity_wake_requests
   475	-- retention already covers both user_id and recipient_user_id rows.
   476	
   477	CREATE OR REPLACE FUNCTION public.cleanup_ephemeral_data()
   478	RETURNS VOID
   479	LANGUAGE plpgsql
   480	SECURITY DEFINER
   481	SET search_path = pg_catalog, public
   482	AS $$
   483	DECLARE
   484	  v_holds BOOLEAN := EXISTS (
   485	    SELECT 1 FROM public.legal_holds
   486	     WHERE released_at IS NULL
   487	       AND (expires_at IS NULL OR expires_at > NOW()));
   488	BEGIN
   489	  IF v_holds THEN
   490	    DELETE FROM public.token_claims tc
   491	     WHERE tc.valid_until < NOW() - INTERVAL '30 minutes'
   492	       AND NOT public.has_legal_hold(tc.user_id);
   493	
   494	    DELETE FROM public.sightings s
   495	     WHERE s.observed_at < NOW() - INTERVAL '24 hours'
   496	       AND NOT public.has_legal_hold(s.observer_user_id)
   497	       AND NOT EXISTS (
   498	         SELECT 1 FROM public.token_claims tc
   499	          WHERE tc.token = s.observed_token
   500	            AND public.has_legal_hold(tc.user_id));
   501	
   502	    DELETE FROM public.location_pings lp
   503	     WHERE lp.created_at < NOW() - INTERVAL '24 hours'
   504	       AND NOT public.has_legal_hold(lp.user_id);
   505	
   506	    -- 0047: token_claim_history is ephemeral too; it was never pruned.
   507	    DELETE FROM public.token_claim_history h
   508	     WHERE h.valid_until < NOW() - INTERVAL '24 hours'
   509	       AND NOT public.has_legal_hold(h.user_id);
   510	
   511	    -- 0056
   512	    DELETE FROM public.rssi_samples rs
   513	     WHERE rs.received_at < NOW() - INTERVAL '30 days'
   514	       AND NOT public.has_legal_hold(rs.user_id);
   515	
   516	    -- 0058
   517	    DELETE FROM public.venue_anchors va
   518	     WHERE va.updated_at < NOW() - INTERVAL '14 days'
   519	       AND NOT public.has_legal_hold(va.user_id);
   520	
   521	    DELETE FROM public.proximity_wake_requests pwr
   522	     WHERE (pwr.status IN ('sent', 'skipped') AND pwr.created_at < NOW() - INTERVAL '30 days')
   523	        OR (pwr.status = 'failed' AND pwr.created_at < NOW() - INTERVAL '7 days');
   524	  ELSE
   525	    DELETE FROM public.token_claims
   526	     WHERE valid_until < NOW() - INTERVAL '30 minutes';
   527	
   528	    DELETE FROM public.sightings
   529	     WHERE observed_at < NOW() - INTERVAL '24 hours';
   530	
   531	    DELETE FROM public.location_pings
   532	     WHERE created_at < NOW() - INTERVAL '24 hours';
   533	
   534	    -- 0047: token_claim_history is ephemeral too; it was never pruned.
   535	    DELETE FROM public.token_claim_history
   536	     WHERE valid_until < NOW() - INTERVAL '24 hours';
   537	
   538	    -- 0056
   539	    DELETE FROM public.rssi_samples
   540	     WHERE received_at < NOW() - INTERVAL '30 days';
   541	
   542	    -- 0058
   543	    DELETE FROM public.venue_anchors
   544	     WHERE updated_at < NOW() - INTERVAL '14 days';
   545	
   546	    DELETE FROM public.proximity_wake_requests
   547	     WHERE (status IN ('sent', 'skipped') AND created_at < NOW() - INTERVAL '30 days')
   548	        OR (status = 'failed' AND created_at < NOW() - INTERVAL '7 days');
   549	  END IF;
   550	
   551	  -- Rate buckets outlive their window by definition; drop idle ones.
   552	  DELETE FROM public.rssi_batch_rate
   553	   WHERE window_start < NOW() - INTERVAL '1 day';
   554	
   555	  -- Recover a worker that died after atomically claiming a batch.
   556	  UPDATE public.notification_outbox
   557	     SET status = CASE WHEN attempts < 5 THEN 'pending' ELSE 'failed' END,
   558	         last_error = 'stale_processing_recovered',
   559	         processing_at = NULL
   560	   WHERE status = 'processing'
   561	     AND processing_at < NOW() - INTERVAL '10 minutes';
   562	
   563	  DELETE FROM public.notification_outbox
   564	   WHERE (status IN ('sent', 'skipped') AND created_at < NOW() - INTERVAL '30 days')
   565	      OR (status = 'failed' AND created_at < NOW() - INTERVAL '7 days');
   566	
   567	  DELETE FROM public.ai_events WHERE created_at < NOW() - INTERVAL '90 days';
   568	  DELETE FROM public.ai_runs   WHERE created_at < NOW() - INTERVAL '90 days';
   569	
   570	  -- Evidence snapshots: 1 year, unless the subject is still held or the
   571	  -- snapshot backs an unexpired (or unfiled) CyberTipline obligation.
   572	  DELETE FROM public.report_evidence e
   573	   WHERE e.captured_at < NOW() - INTERVAL '1 year'
   574	     AND (e.subject_user IS NULL OR NOT public.has_legal_hold(e.subject_user))
   575	     AND NOT EXISTS (
   576	       SELECT 1 FROM public.cybertipline_queue q
   577	        WHERE q.report_id = e.report_id
   578	          AND (q.preserve_until IS NULL OR q.preserve_until > NOW()));
   579	END;
   580	$$;
   581	
   582	COMMENT ON FUNCTION public.cleanup_ephemeral_data IS
   583	  'Sweeps ephemeral tables: location_pings (24 h), sightings (24 h), token_claim_history (24 h), rssi_samples (30 d), venue_anchors (14 d), proximity_wake_requests (30 d sent / 7 d failed), notification_outbox, AI events/runs (90 d), report_evidence (1 y). Honors legal holds.';
   584	
   585	COMMIT;
     1	-- 0037_legal_hold.sql
     2	--
     3	-- Preservation holds that survive retention purging.
     4	--
     5	-- WHY: 18 U.S.C. §2258A(h)(1) imposes a ONE YEAR preservation obligation the
     6	-- moment a CyberTipline report is filed with NCMEC. 0035 wired
     7	-- purge_deleted_accounts() into run_maintenance(), which pg_cron runs every 15
     8	-- minutes. Without a hold, the sequence
     9	--     incident -> report filed -> subject deletes their account -> 30d grace
    10	--     -> automated purge
    11	-- destroys evidence we are federally obligated to preserve, automatically and
    12	-- with no human in the loop. The retention machinery we built for privacy
    13	-- becomes a spoliation mechanism.
    14	--
    15	-- Note the direction of the conflict: this is preservation BEATING erasure, and
    16	-- every privacy regime we are subject to allows exactly that. GDPR Art. 17(3)(b)
    17	-- excepts processing necessary for compliance with a legal obligation; the US
    18	-- state statutes carry equivalent carve-outs. So a held account's deletion
    19	-- request is DEFERRED, not refused -- deleted_at is still recorded, and the
    20	-- scrub plus purge run automatically once the hold is released.
    21	--
    22	-- Holds are service-role only. A user must never be able to see, place, or
    23	-- lift a hold on themselves: telling the subject of a CyberTipline report that
    24	-- they are under one both tips them off and risks obstruction.
    25	
    26	BEGIN;
    27	
    28	CREATE TABLE IF NOT EXISTS public.legal_holds (
    29	  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    30	  user_id     UUID NOT NULL,
    31	  reason      TEXT NOT NULL CHECK (reason IN (
    32	                'cybertipline_2258a',   -- §2258A(h)(1), 1 year minimum
    33	                'ncii_takedown',        -- TAKE IT DOWN Act request record
    34	                'law_enforcement',      -- preservation letter / subpoena
    35	                'litigation_hold',
    36	                'safety_investigation'
    37	              )),
    38	  detail      TEXT,
    39	  placed_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    40	  placed_by   TEXT NOT NULL,
    41	  expires_at  TIMESTAMPTZ,            -- NULL = indefinite, release manually
    42	  released_at TIMESTAMPTZ,
    43	  released_by TEXT
    44	);
    45	
    46	-- No FK to auth.users on purpose: the hold must outlive the account row, and a
    47	-- CASCADE here would let the very purge this table exists to block delete the
    48	-- record of why it was blocked.
    49	
    50	CREATE INDEX IF NOT EXISTS idx_legal_holds_active
    51	  ON public.legal_holds (user_id) WHERE released_at IS NULL;
    52	
    53	ALTER TABLE public.legal_holds ENABLE ROW LEVEL SECURITY;
    54	-- No policies: service_role bypasses RLS; app users have no access at all.
    55	REVOKE ALL ON TABLE public.legal_holds FROM PUBLIC, anon, authenticated;
    56	GRANT SELECT, INSERT, UPDATE ON TABLE public.legal_holds TO service_role;
    57	
    58	COMMENT ON TABLE public.legal_holds IS
    59	  'Preservation holds that block scrub and purge. §2258A(h)(1) requires 1 year from a CyberTipline filing. Service-role only -- the subject must never learn of a hold.';
    60	
    61	-- ---------------------------------------------------------------------------
    62	CREATE OR REPLACE FUNCTION public.has_legal_hold(p_uid UUID)
    63	RETURNS BOOLEAN
    64	LANGUAGE sql
    65	STABLE
    66	SECURITY DEFINER
    67	SET search_path = pg_catalog, public
    68	AS $$
    69	  SELECT EXISTS (
    70	    SELECT 1 FROM public.legal_holds h
    71	     WHERE h.user_id = p_uid
    72	       AND h.released_at IS NULL
    73	       AND (h.expires_at IS NULL OR h.expires_at > NOW())
    74	  );
    75	$$;
    76	
    77	REVOKE ALL ON FUNCTION public.has_legal_hold(UUID) FROM PUBLIC, anon, authenticated;
    78	GRANT EXECUTE ON FUNCTION public.has_legal_hold(UUID) TO service_role;
    79	
    80	-- Convenience writer so the runbook is one call and the 1-year default for a
    81	-- CyberTipline filing cannot be got wrong by hand.
    82	CREATE OR REPLACE FUNCTION public.place_legal_hold(
    83	  p_uid    UUID,
    84	  p_reason TEXT,
    85	  p_by     TEXT,
    86	  p_detail TEXT DEFAULT NULL,
    87	  p_expires TIMESTAMPTZ DEFAULT NULL
    88	)
    89	RETURNS BIGINT
    90	LANGUAGE plpgsql
    91	SECURITY DEFINER
    92	SET search_path = pg_catalog, public
    93	AS $$
    94	DECLARE
    95	  v_id BIGINT;
    96	  v_expires TIMESTAMPTZ;
    97	BEGIN
    98	  -- §2258A(h)(1) is one year from the report. Default it rather than trusting
    99	  -- whoever is doing incident response at the time to remember.
   100	  v_expires := COALESCE(
   101	    p_expires,
   102	    CASE WHEN p_reason = 'cybertipline_2258a' THEN NOW() + INTERVAL '1 year' END
   103	  );
   104	
   105	  INSERT INTO public.legal_holds (user_id, reason, detail, placed_by, expires_at)
   106	  VALUES (p_uid, p_reason, p_detail, p_by, v_expires)
   107	  RETURNING id INTO v_id;
   108	
   109	  RETURN v_id;
   110	END;
   111	$$;
   112	
   113	REVOKE ALL ON FUNCTION public.place_legal_hold(UUID, TEXT, TEXT, TEXT, TIMESTAMPTZ)
   114	  FROM PUBLIC, anon, authenticated;
   115	GRANT EXECUTE ON FUNCTION public.place_legal_hold(UUID, TEXT, TEXT, TEXT, TIMESTAMPTZ)
   116	  TO service_role;
   117	
   118	-- ---------------------------------------------------------------------------
   119	-- Scrub becomes hold-aware. Returns TRUE if it ran, FALSE if deferred.
   120	--
   121	-- 0035 declared this RETURNS VOID; Postgres will not change a return type in
   122	-- place, so it must be dropped first. Safe: PL/pgSQL call sites are resolved
   123	-- at runtime, not by a tracked dependency, and purge_deleted_accounts() is
   124	-- recreated below in the same transaction.
   125	-- ---------------------------------------------------------------------------
   126	DROP FUNCTION IF EXISTS public.scrub_account_pii(UUID);
   127	
   128	CREATE OR REPLACE FUNCTION public.scrub_account_pii(p_uid UUID)
   129	RETURNS BOOLEAN
   130	LANGUAGE plpgsql
   131	SECURITY DEFINER
   132	SET search_path = pg_catalog, public
   133	AS $$
   134	BEGIN
   135	  IF p_uid IS NULL THEN
   136	    RAISE EXCEPTION 'scrub_account_pii requires a user id';
   137	  END IF;
   138	
   139	  -- Preservation beats erasure. Deferred, not refused: request_account_deletion
   140	  -- still stamps deleted_at, so purge_deleted_accounts() completes this
   141	  -- automatically once the hold lifts.
   142	  IF public.has_legal_hold(p_uid) THEN
   143	    RETURN FALSE;
   144	  END IF;
   145	
   146	  UPDATE public.profiles SET
   147	    display_name              = 'Deleted user',
   148	    bio                       = NULL,
   149	    dob                       = NULL,
   150	    gender                    = NULL,
   151	    sexual_preference         = NULL,
   152	    interests                 = NULL,
   153	    photo_urls                = NULL,
   154	    neighborhood              = NULL,
   155	    email_hint                = NULL,
   156	    phone_hint                = NULL,
   157	    photo_verification_status = NULL,
   158	    is_photo_verified         = FALSE,
   159	    age_verified              = FALSE,
   160	    is_active                 = FALSE,
   161	    is_paused                 = TRUE,
   162	    is_incognito              = FALSE,
   163	    last_active_at            = NULL,
   164	    deleted_at                = COALESCE(deleted_at, NOW()),
   165	    updated_at                = NOW()
   166	  WHERE id = p_uid;
   167	
   168	  DELETE FROM public.location_pings      WHERE user_id          = p_uid;
   169	  DELETE FROM public.token_claims        WHERE user_id          = p_uid;
   170	  DELETE FROM public.token_claim_history WHERE user_id          = p_uid;
   171	  DELETE FROM public.sightings           WHERE observer_user_id = p_uid;
   172	  DELETE FROM public.beacon_token_batch  WHERE user_id          = p_uid;
   173	  DELETE FROM public.device_attestations WHERE user_id          = p_uid;
   174	  DELETE FROM public.device_push_tokens  WHERE user_id          = p_uid;
   175	  DELETE FROM public.notification_outbox WHERE user_id          = p_uid;
   176	  DELETE FROM public.photo_verifications WHERE user_id          = p_uid;
   177	
   178	  INSERT INTO public.storage_deletion_queue (user_id, bucket_id, object_name)
   179	  SELECT p_uid, o.bucket_id, o.name
   180	    FROM storage.objects o
   181	   WHERE (o.bucket_id IN ('profile_photos', 'verified_photos')
   182	            AND (storage.foldername(o.name))[1] = p_uid::TEXT)
   183	      OR (o.bucket_id = 'chat_media'
   184	            AND (storage.foldername(o.name))[2] = p_uid::TEXT)
   185	  ON CONFLICT (bucket_id, object_name) DO NOTHING;
   186	
   187	  UPDATE public.messages
   188	     SET content  = CASE WHEN message_type = 'text' THEN '[deleted]' ELSE NULL END,
   189	         metadata = NULL
   190	   WHERE sender_id = p_uid;
   191	
   192	  UPDATE public.ad_impressions SET user_id = NULL WHERE user_id = p_uid;
   193	  UPDATE public.ai_events      SET user_id = NULL WHERE user_id = p_uid;
   194	
   195	  RETURN TRUE;
   196	END;
   197	$$;
   198	
   199	REVOKE ALL ON FUNCTION public.scrub_account_pii(UUID) FROM PUBLIC, anon, authenticated;
   200	GRANT EXECUTE ON FUNCTION public.scrub_account_pii(UUID) TO service_role;
   201	
   202	-- ---------------------------------------------------------------------------
   203	-- Purge skips held accounts entirely.
   204	-- ---------------------------------------------------------------------------
   205	CREATE OR REPLACE FUNCTION public.purge_deleted_accounts(p_grace INTERVAL DEFAULT NULL)
   206	RETURNS INT
   207	LANGUAGE plpgsql
   208	SECURITY DEFINER
   209	SET search_path = pg_catalog, public
   210	AS $$
   211	DECLARE
   212	  v_grace INTERVAL;
   213	  v_uid   UUID;
   214	  v_count INT := 0;
   215	BEGIN
   216	  v_grace := COALESCE(
   217	    p_grace,
   218	    make_interval(days => COALESCE(
   219	      (SELECT value_num::INT FROM public.app_settings WHERE key = 'deletion_grace_days'), 30))
   220	  );
   221	
   222	  FOR v_uid IN
   223	    SELECT id FROM public.profiles
   224	     WHERE deleted_at IS NOT NULL
   225	       AND deleted_at < NOW() - v_grace
   226	       AND NOT public.has_legal_hold(id)   -- preservation beats retention
   227	  LOOP
   228	    PERFORM public.scrub_account_pii(v_uid);
   229	
   230	    DELETE FROM public.reports  WHERE reporter_id = v_uid OR reported_id = v_uid;
184 matches in 22 files:

docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-86-"guard" is dead code: `0060:117-118` rejects NULL coordinates, so `EXCLUDED.a...
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-87-Tokens are broadcast in plaintext over BLE. Neutralises the GPS veto — `corre...
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-88-(`0053:179-182`) compares against coordinates the attacker just wrote. The ba...
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-89-would stop it sits behind `enforce_batch_tokens`, which is **0**.
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-90-
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:91:### C-SQL-3 🔴 `beacon_token_batch` has no scheduled purge — a permanent token→us...
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-92-`cleanup_ephemeral_data()` (latest `0059:477-580`) purges 9 tables; not this ...
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-93-`rssi_samples` on the shared token yields a de-anonymised proximity graph. **...
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-94-active users' rows rotate out at next batch issue (~1–2 day window); it is **...
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-95-set persists indefinitely. Two-line fix:
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:96:`DELETE FROM public.beacon_token_batch WHERE valid_until < NOW() - INTERVAL '24 ...
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-97-
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-98-### C-SQL-4 🔴 Batch-pre-claimed tokens skip the GPS veto entirely *(found by ...
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-99-`0053:179-182` wraps the veto in `IF ... v_claim.approx_lat IS NOT NULL ...`....
docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-100-(`0060:25`) pre-claims with NULL location — the locked-phone path. For those ...
  +1 more in docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-296-file-protection class.
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-297-
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-298-### What the Linux side is taking — do not duplicate
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-299-
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-300-Production Edge Function redeploy and `verify_jwt` config; the **three** SQL ...
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:301:...ser overwrite (C-SQL-1), `beacon_token_batch` retention (C-SQL-3), and the GPS v...
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-302-batch-pre-claimed tokens (C-SQL-4) — plus the two SQL findings the consensus ...
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-303-`correlate_miles_encounters` encounter fabrication (H-SQL-2) and missing `req...
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-304-newest write paths (H-CONSENT-1); the waitlist endpoint's unauthenticated
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-305-cross-user write and its email-enumeration oracle; `scan_relay_abuse` victim-...
docs/.../2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-306-authorization; the Android Apple-multi-AD advert parser wiring; and the three...
docs/.../transcripts/codex_consensus_r1.md-1228-producers and only the BLE one was hardened by 0029→0053. Also returns raw `u...
docs/.../transcripts/codex_consensus_r1.md-1229-an attacker-chosen point — a presence/identity oracle.
docs/.../transcripts/codex_consensus_r1.md-1230-**Fix:** stop this path writing `encounters` (own table), or stamp `trust_lev...
docs/.../transcripts/codex_consensus_r1.md-1231-everywhere encounters are treated as evidence; stop returning `other_user_id`...
docs/.../transcripts/codex_consensus_r1.md-1232-
docs/.../transcripts/codex_consensus_r1.md:1233:### C-SQL-3 🔴 `beacon_token_batch` has no scheduled purge — a permanent token→us...
docs/.../transcripts/codex_consensus_r1.md-1234-`cleanup_ephemeral_data()` (latest: `0059:477-580`) purges 9 tables; this is ...
docs/.../transcripts/codex_consensus_r1.md-1235-`DELETE` of it is either self-scoped inside `issue_token_batch` or an account...
docs/.../transcripts/codex_consensus_r1.md:1236:`JOIN beacon_token_batch b ON b.token = rssi_samples.correlation_id` yields a fu...
docs/.../transcripts/codex_consensus_r1.md-1237-30-day proximity graph. Users who churn leave their token set on the server p...
docs/.../transcripts/codex_consensus_r1.md:1238:...s):** `DELETE FROM public.beacon_token_batch WHERE valid_until < NOW() - INTERVA...
docs/.../transcripts/codex_consensus_r1.md:1239:The `idx_beacon_token_batch_expiry` index already exists for it.
docs/.../transcripts/codex_consensus_r1.md-1240-
docs/.../transcripts/codex_consensus_r1.md-1241-### C-SQL-4 🔴 Batch-pre-claimed tokens skip the GPS veto entirely *(found by ...
docs/.../transcripts/codex_consensus_r1.md-1242-`0053:179-182` wraps the spatial veto in `IF ... v_claim.approx_lat IS NOT NU...
  +701 more in docs/.../transcripts/codex_consensus_r1.md
docs/.../transcripts/codex_final.md-35-
docs/.../transcripts/codex_final.md-36-Codex argues that `C-W5-1`, `C-W5-2`, `C-W5-3` should be **High, not Critical...
docs/.../transcripts/codex_final.md-37-
docs/.../transcripts/codex_final.md-38-My adjudication, and I want you both to challenge it if you disagree: **I am ...
docs/.../transcripts/codex_final.md-39-
docs/.../transcripts/codex_final.md:40:...ry` overwrite), C-SQL-3 (`beacon_token_batch` never purged), C-SQL-4 (GPS veto s...
docs/.../transcripts/codex_final.md-41-
docs/.../transcripts/codex_final.md-42-Do you both agree with that final tier? If either of you thinks a demoted ite...
docs/.../transcripts/codex_final.md-43-
docs/.../transcripts/codex_final.md-44-## 4. Codex's REPORT-META objection — accepted, confirm the remedy
docs/.../transcripts/codex_final.md-45-
docs/.../transcripts/codex_reconfirm.md-14-
docs/.../transcripts/codex_reconfirm.md-15-Report: /home/hazypiff/in-range/docs/research/2026-08-01-hardening/HARDENING_...
docs/.../transcripts/codex_reconfirm.md-16-
docs/.../transcripts/codex_reconfirm.md-17-Three amendments, all in the VERDICT / FIX ORDER / SYSTEMIC sections:
docs/.../transcripts/codex_reconfirm.md-18-
docs/.../transcripts/codex_reconfirm.md:19:... That is wrong: C-SQL-3 (`beacon_token_batch` never purged) is a server-side ret...
docs/.../transcripts/codex_reconfirm.md-20-
docs/.../transcripts/codex_reconfirm.md-21-**2. The apparent contradiction between C-DIAG-1 being Critical and the W5 de...
docs/.../transcripts/codex_reconfirm.md-22-
docs/.../transcripts/codex_reconfirm.md-23-**3. A stale count.** The SYSTEMIC section claimed the three proposed tests "...
docs/.../transcripts/codex_reconfirm.md-24-
docs/.../transcripts/codex_reconfirm.md-414-72	"guard" is dead code: `0060:117-118` rejects NULL coordinates, so `EXCLUDE...
docs/.../transcripts/codex_reconfirm.md-415-73	Tokens are broadcast in plaintext over BLE. Neutralises the GPS veto — `co...
docs/.../transcripts/codex_reconfirm.md-416-74	(`0053:179-182`) compares against coordinates the attacker just wrote. The...
docs/.../transcripts/codex_reconfirm.md-417-75	would stop it sits behind `enforce_batch_tokens`, which is **0**.
  +155 more in docs/.../transcripts/codex_reconfirm.md
docs/.../transcripts/codex_reconfirm2.md-506---
docs/.../transcripts/codex_reconfirm2.md-507-/home/hazypiff/in-range/docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORD...
docs/.../transcripts/codex_reconfirm2.md-508-/home/hazypiff/in-range/docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORD...
docs/.../transcripts/codex_reconfirm2.md-509-/home/hazypiff/in-range/docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORD...
docs/.../transcripts/codex_reconfirm2.md-510-/home/hazypiff/in-range/docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORD...
docs/.../transcripts/codex_reconfirm2.md:511:...ser overwrite (C-SQL-1), `beacon_token_batch` retention (C-SQL-3), and the GPS v...
docs/.../transcripts/codex_reconfirm2.md-512-/home/hazypiff/in-range/docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORD...
docs/.../transcripts/codex_reconfirm2.md-513-/home/hazypiff/in-range/docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORD...
docs/.../transcripts/codex_reconfirm2.md-514---
docs/.../transcripts/codex_reconfirm2.md-515-/home/hazypiff/in-range/docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORD...
docs/.../transcripts/codex_reconfirm2.md-516-/home/hazypiff/in-range/docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORD...
docs/.../transcripts/codex_reconfirm2.md-624-/home/hazypiff/in-range/docs/research/2026-08-01-hardening/verified_findings_...
docs/.../transcripts/codex_reconfirm2.md-625-/home/hazypiff/in-range/docs/research/2026-08-01-hardening/verified_findings_...
docs/.../transcripts/codex_reconfirm2.md-626-/home/hazypiff/in-range/docs/research/2026-08-01-hardening/verified_findings_...
docs/.../transcripts/codex_reconfirm2.md-627---
  +63 more in docs/.../transcripts/codex_reconfirm2.md
docs/.../transcripts/final_round.md-23-
docs/.../transcripts/final_round.md-24-Codex argues that `C-W5-1`, `C-W5-2`, `C-W5-3` should be **High, not Critical...
docs/.../transcripts/final_round.md-25-
docs/.../transcripts/final_round.md-26-My adjudication, and I want you both to challenge it if you disagree: **I am ...
docs/.../transcripts/final_round.md-27-
docs/.../transcripts/final_round.md:28:...ry` overwrite), C-SQL-3 (`beacon_token_batch` never purged), C-SQL-4 (GPS veto s...
docs/.../transcripts/final_round.md-29-
docs/.../transcripts/final_round.md-30-Do you both agree with that final tier? If either of you thinks a demoted ite...
docs/.../transcripts/final_round.md-31-
docs/.../transcripts/final_round.md-32-## 4. Codex's REPORT-META objection — accepted, confirm the remedy
docs/.../transcripts/final_round.md-33-
docs/.../transcripts/kimi_consensus_r1.md-3-Priority verification targets:
docs/.../transcripts/kimi_consensus_r1.md-4-1. C-PROD-1 reasoning: service_auth.ts requireServiceRole returns 405 on non-...
docs/.../transcripts/kimi_consensus_r1.md-5-2. C-DIAG-1 correction: BackgroundBeacon.swift:956 (sessions only form behind...
docs/.../transcripts/kimi_consensus_r1.md-6-3. H-DIAG-3 correction: AppDelegate.swift:12-17 comments, BackgroundBeacon.sw...
docs/.../transcripts/kimi_consensus_r1.md-7-4. C-SQL-2: correlate_miles_encounters latest definition — is 0048:251-360 re...
docs/.../transcripts/kimi_consensus_r1.md:8:...on in 0060-0062, and that beacon_token_batch isn't purged. Also check idx existe...
docs/.../transcripts/kimi_consensus_r1.md-9-6. C-W5-1: Dart w5_ownership.dart:321 vs 351, Swift W5Ownership.swift:250 vs ...
docs/.../transcripts/kimi_consensus_r1.md-10-7. C-W5-2: BackgroundBeacon.swift:736-751, :714-734.
docs/.../transcripts/kimi_consensus_r1.md-11-8. C-W5-3: W5LinkController.swift:240-254, W5Ownership.swift:516-530.
docs/.../transcripts/kimi_consensus_r1.md-12-9. C-RT-1: beacon_service.dart:417-422, :603, :2449-2483 (main repo).
docs/.../transcripts/kimi_consensus_r1.md-13-10. C-CONSENT-1: grep require_consent in 0056/0059 — quick.
docs/.../transcripts/kimi_consensus_r1.md-30-
docs/.../transcripts/kimi_consensus_r1.md-31-Subagent 1 (explore): verify all W5/iOS findings (C-W5-1, C-W5-2, C-W5-3, C-D...
docs/.../transcripts/kimi_consensus_r1.md-32-
docs/.../transcripts/kimi_consensus_r1.md-33-Subagent 2 (explore): verify Dart/runtime findings (C-RT-1, H-RT-2..H-RT-9) a...
  +7 more in docs/.../transcripts/kimi_consensus_r1.md
docs/.../transcripts/reconfirm.md-2-
docs/.../transcripts/reconfirm.md-3-Report: /home/hazypiff/in-range/docs/research/2026-08-01-hardening/HARDENING_...
docs/.../transcripts/reconfirm.md-4-
docs/.../transcripts/reconfirm.md-5-Three amendments, all in the VERDICT / FIX ORDER / SYSTEMIC sections:
docs/.../transcripts/reconfirm.md-6-
docs/.../transcripts/reconfirm.md:7:... That is wrong: C-SQL-3 (`beacon_token_batch` never purged) is a server-side ret...
docs/.../transcripts/reconfirm.md-8-
docs/.../transcripts/reconfirm.md-9-**2. The apparent contradiction between C-DIAG-1 being Critical and the W5 de...
docs/.../transcripts/reconfirm.md-10-
docs/.../transcripts/reconfirm.md-11-**3. A stale count.** The SYSTEMIC section claimed the three proposed tests "...
docs/.../transcripts/reconfirm.md-12-
docs/.../2026-08-01-hardening/verified_findings_working.md-298-
docs/.../2026-08-01-hardening/verified_findings_working.md-299-**Confidence:** CERTAIN.
docs/.../2026-08-01-hardening/verified_findings_working.md-300-
docs/.../2026-08-01-hardening/verified_findings_working.md-301----
docs/.../2026-08-01-hardening/verified_findings_working.md-302-
docs/.../2026-08-01-hardening/verified_findings_working.md:303:## 🔴 C-SQL-3 — `beacon_token_batch` has NO scheduled purge: a permanent token→us...
docs/.../2026-08-01-hardening/verified_findings_working.md-304-
docs/.../2026-08-01-hardening/verified_findings_working.md-305-**Severity:** Critical (privacy)
docs/.../2026-08-01-hardening/verified_findings_working.md-306-
docs/.../2026-08-01-hardening/verified_findings_working.md-307-**Verified:** `cleanup_ephemeral_data()` — latest definition `0059_proximity_...
docs/.../2026-08-01-hardening/verified_findings_working.md-308-purges 9 tables (`token_claims`, `sightings`, `location_pings`, `token_claim_...
docs/.../2026-08-01-hardening/verified_findings_working.md-309-`venue_anchors`, `proximity_wake_requests`, `rssi_batch_rate`, `notification_...
docs/.../2026-08-01-hardening/verified_findings_working.md:310:**`beacon_token_batch` is not among them.**
docs/.../2026-08-01-hardening/verified_findings_working.md-311-
docs/.../2026-08-01-hardening/verified_findings_working.md:312:Every `DELETE FROM public.beacon_token_batch` in the entire migration set is eit...
  +21 more in docs/.../2026-08-01-hardening/verified_findings_working.md
supabase/migrations/0031_server_issued_token_batches.sql-22-
supabase/migrations/0031_server_issued_token_batches.sql-23--- Enforcement flag — OFF by default so this deploy cannot break current clie...
supabase/migrations/0031_server_issued_token_batches.sql-24-INSERT INTO public.app_settings (key, value_num) VALUES ('enforce_batch_token...
supabase/migrations/0031_server_issued_token_batches.sql-25-ON CONFLICT (key) DO NOTHING;
supabase/migrations/0031_server_issued_token_batches.sql-26-
supabase/migrations/0031_server_issued_token_batches.sql:27:CREATE TABLE IF NOT EXISTS public.beacon_token_batch (
supabase/migrations/0031_server_issued_token_batches.sql-28-token       TEXT PRIMARY KEY,               -- opaque 32 hex chars (128-bit)
supabase/migrations/0031_server_issued_token_batches.sql-29-user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
supabase/migrations/0031_server_issued_token_batches.sql-30-batch_day   DATE NOT NULL,
supabase/migrations/0031_server_issued_token_batches.sql-31-slot        INT  NOT NULL,
supabase/migrations/0031_server_issued_token_batches.sql-32-valid_from  TIMESTAMPTZ NOT NULL,
supabase/migrations/0031_server_issued_token_batches.sql-33-valid_until TIMESTAMPTZ NOT NULL,
supabase/migrations/0031_server_issued_token_batches.sql-34-consumed_at TIMESTAMPTZ,                     -- set when first claimed (obser...
supabase/migrations/0031_server_issued_token_batches.sql-35-created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
supabase/migrations/0031_server_issued_token_batches.sql-36-UNIQUE (user_id, batch_day, slot)
  +56 more in supabase/migrations/0031_server_issued_token_batches.sql
supabase/migrations/0034_device_attestation_scaffold.sql-100-RAISE EXCEPTION 'Batch day out of range' USING ERRCODE='22023'; END IF;
supabase/migrations/0034_device_attestation_scaffold.sql-101-
supabase/migrations/0034_device_attestation_scaffold.sql-102--- Housekeeping + abuse guard: drop the caller's stale batches, then cap how
supabase/migrations/0034_device_attestation_scaffold.sql-103--- many distinct live days one user may hold (a relay farm requesting many
supabase/migrations/0034_device_attestation_scaffold.sql-104--- days of tokens would trip this).
supabase/migrations/0034_device_attestation_scaffold.sql:105:DELETE FROM public.beacon_token_batch WHERE user_id = v_uid AND batch_day < CURR...
supabase/migrations/0034_device_attestation_scaffold.sql-106-SELECT count(DISTINCT b.batch_day) INTO v_distinct_days
supabase/migrations/0034_device_attestation_scaffold.sql:107:FROM public.beacon_token_batch b WHERE b.user_id = v_uid AND b.batch_day >= CURR...
supabase/migrations/0034_device_attestation_scaffold.sql-108-IF v_distinct_days >= 3 AND NOT EXISTS (
supabase/migrations/0034_device_attestation_scaffold.sql:109:SELECT 1 FROM public.beacon_token_batch b WHERE b.user_id = v_uid AND b.batch_da...
supabase/migrations/0034_device_attestation_scaffold.sql-110-) THEN
supabase/migrations/0034_device_attestation_scaffold.sql-111-RAISE EXCEPTION 'Too many active token batches' USING ERRCODE='54000'; END IF;
supabase/migrations/0034_device_attestation_scaffold.sql-112-
supabase/migrations/0034_device_attestation_scaffold.sql-113-v_slots := (1440 / v_window);   -- 96 for a 15-minute window
supabase/migrations/0034_device_attestation_scaffold.sql-114-
  +19 more in supabase/migrations/0034_device_attestation_scaffold.sql
supabase/migrations/0035_account_deletion_completeness.sql-119--- Proximity + beacon telemetry: no reason to retain any of it.
supabase/migrations/0035_account_deletion_completeness.sql-120-DELETE FROM public.location_pings      WHERE user_id          = p_uid;
supabase/migrations/0035_account_deletion_completeness.sql-121-DELETE FROM public.token_claims        WHERE user_id          = p_uid;
supabase/migrations/0035_account_deletion_completeness.sql-122-DELETE FROM public.token_claim_history WHERE user_id          = p_uid;
supabase/migrations/0035_account_deletion_completeness.sql-123-DELETE FROM public.sightings           WHERE observer_user_id = p_uid;
supabase/migrations/0035_account_deletion_completeness.sql:124:DELETE FROM public.beacon_token_batch  WHERE user_id          = p_uid;
supabase/migrations/0035_account_deletion_completeness.sql-125-DELETE FROM public.device_attestations WHERE user_id          = p_uid;
supabase/migrations/0035_account_deletion_completeness.sql-126-
supabase/migrations/0035_account_deletion_completeness.sql-127--- Device / delivery identifiers.
supabase/migrations/0035_account_deletion_completeness.sql-128-DELETE FROM public.device_push_tokens  WHERE user_id = p_uid;
supabase/migrations/0035_account_deletion_completeness.sql-129-DELETE FROM public.notification_outbox WHERE user_id = p_uid;
supabase/migrations/0037_legal_hold.sql-167-
supabase/migrations/0037_legal_hold.sql-168-DELETE FROM public.location_pings      WHERE user_id          = p_uid;
supabase/migrations/0037_legal_hold.sql-169-DELETE FROM public.token_claims        WHERE user_id          = p_uid;
supabase/migrations/0037_legal_hold.sql-170-DELETE FROM public.token_claim_history WHERE user_id          = p_uid;
supabase/migrations/0037_legal_hold.sql-171-DELETE FROM public.sightings           WHERE observer_user_id = p_uid;
supabase/migrations/0037_legal_hold.sql:172:DELETE FROM public.beacon_token_batch  WHERE user_id          = p_uid;
supabase/migrations/0037_legal_hold.sql-173-DELETE FROM public.device_attestations WHERE user_id          = p_uid;
supabase/migrations/0037_legal_hold.sql-174-DELETE FROM public.device_push_tokens  WHERE user_id          = p_uid;
supabase/migrations/0037_legal_hold.sql-175-DELETE FROM public.notification_outbox WHERE user_id          = p_uid;
supabase/migrations/0037_legal_hold.sql-176-DELETE FROM public.photo_verifications WHERE user_id          = p_uid;
supabase/migrations/0037_legal_hold.sql-177-
supabase/migrations/0040_wire_consent_gates.sql-56-RAISE EXCEPTION 'Invalid accuracy' USING ERRCODE='22023'; END IF;
supabase/migrations/0040_wire_consent_gates.sql-57-
supabase/migrations/0040_wire_consent_gates.sql-58--- #6 step 2: the token must be one the server issued to THIS user. Consume it
supabase/migrations/0040_wire_consent_gates.sql-59--- (observability); enforce membership only when the flag is on so the
supabase/migrations/0040_wire_consent_gates.sql-60--- batch-aware client can roll out first.
supabase/migrations/0040_wire_consent_gates.sql:61:UPDATE public.beacon_token_batch b SET consumed_at = COALESCE(b.consumed_at, v_n...
supabase/migrations/0040_wire_consent_gates.sql-62-WHERE b.token = lower(p_token) AND b.user_id = v_uid
supabase/migrations/0040_wire_consent_gates.sql-63-RETURNING TRUE INTO v_in_batch;
supabase/migrations/0040_wire_consent_gates.sql-64-IF NOT COALESCE(v_in_batch, FALSE)
supabase/migrations/0040_wire_consent_gates.sql-65-AND COALESCE((SELECT value_num FROM public.app_settings WHERE key='enforce_ba...
supabase/migrations/0040_wire_consent_gates.sql-66-RAISE EXCEPTION 'Beacon token was not issued to this account' USING ERRCODE='...
supabase/migrations/0044_evidence_preservation.sql-199-
supabase/migrations/0044_evidence_preservation.sql-200-DELETE FROM public.location_pings      WHERE user_id          = p_uid;
supabase/migrations/0044_evidence_preservation.sql-201-DELETE FROM public.token_claims        WHERE user_id          = p_uid;
  +8 more in supabase/migrations/0044_evidence_preservation.sql
+6 more files
supabase/config.toml-64-
supabase/config.toml-65-[functions.ncii-intake]
supabase/config.toml-66-# Public, unauthenticated NCII/TAKE IT DOWN intake — reporters have no JWT.
supabase/config.toml-67-# Abuse control is the per-IP limit inside the function (0050), not the gateway.
supabase/config.toml-68-verify_jwt = false
supabase/config.toml-69-
supabase/config.toml:70:[functions.maintenance]
supabase/config.toml-71-# Self-authenticates via requireServiceRole(); see miles-correlate note.
supabase/config.toml-72-verify_jwt = false
supabase/config.toml-73-
supabase/config.toml-74-[functions.proximity-wake]
supabase/config.toml-75-# Self-authenticates via requireServiceRole(). Previously ABSENT from this file,
supabase/config.toml-76-# so it silently inherited the verify_jwt=true default. NOT yet deployed — 0059
supabase/migrations/0049_schedule_maintenance_edge_worker.sql:1:-- 0049_schedule_maintenance_edge_worker.sql
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-2---
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-3--- Closes the OPS GAP from the privacy audits: prod cron ran only
supabase/migrations/0049_schedule_maintenance_edge_worker.sql:4:-- run_maintenance() (SQL, which just ENQUEUES deleted objects), so queued
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-5--- profile photos were never physically deleted. Postgres cannot delete
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-6--- storage.objects — only the Storage API can, and that lives in the
supabase/migrations/0049_schedule_maintenance_edge_worker.sql:7:-- `maintenance` Edge function. This schedules that Edge worker every 15 min via
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-8--- pg_net, so the storage_deletion_queue actually drains.
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-9---
supabase/migrations/0049_schedule_maintenance_edge_worker.sql:10:-- The existing `in-range-maintenance` SQL cron is intentionally LEFT in place as
supabase/migrations/0049_schedule_maintenance_edge_worker.sql:11:-- a reliable belt: core maintenance (feet expiry, account purge, reveals) keeps
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-12--- running even if pg_net/Edge is unavailable. The Edge worker also calls
supabase/migrations/0049_schedule_maintenance_edge_worker.sql:13:-- run_maintenance() first — that is idempotent/time-gated, so the small overlap
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-14--- is harmless; its unique contribution is the physical Storage-API deletion and
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-15--- the notification-outbox drain.
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-16---
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-17--- SECURITY: the service key is read from Vault (`edge_service_key`) at call time.
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-18--- It is never written into this migration or stored as plaintext in
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-19--- cron.job.command — the command only contains a SELECT against
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-25--- Enable pg_net (guarded: absent on some local/dev images).
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-26-DO $$
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-27-BEGIN
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-28-  IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_net') THEN
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-29-    EXECUTE 'CREATE EXTENSION IF NOT EXISTS pg_net';
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-30-  ELSE
supabase/migrations/0049_schedule_maintenance_edge_worker.sql:31:    RAISE NOTICE 'pg_net unavailable; edge maintenance cron not scheduled (dev)';
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-32-  END IF;
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-33-EXCEPTION
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-34-  WHEN OTHERS THEN
supabase/migrations/0049_schedule_maintenance_edge_worker.sql:35:    RAISE NOTICE 'pg_net enable failed: % — schedule the maintenance Edge cron in the Dashboard', SQLERRM;
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-36-END $$;
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-37-
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-38--- Unschedule prior copy if re-running.
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-39-DO $$
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-40-BEGIN
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-41-  PERFORM cron.unschedule(jobid)
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-48-END $$;
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-49-
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-50--- Schedule the Edge worker every 15 min (only if pg_net is present).
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-51-DO $$
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-52-BEGIN
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-53-  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN
supabase/migrations/0049_schedule_maintenance_edge_worker.sql:54:    PERFORM cron.schedule(
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-55-      'in-range-storage-drain',
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-56-      '*/15 * * * *',
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-57-      $job$
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-58-      SELECT net.http_post(
supabase/migrations/0049_schedule_maintenance_edge_worker.sql:59:        url     := 'https://riigipzlyqeaadyvbuty.supabase.co/functions/v1/maintenance',
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-60-        headers := jsonb_build_object(
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-61-          'Content-Type', 'application/json',
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-62-          'Authorization', 'Bearer ' || (
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-63-            SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'edge_service_key'
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-64-          )
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-65-        ),
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-66-        body    := '{}'::jsonb,
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-67-        timeout_milliseconds := 20000
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-68-      );
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-69-      $job$
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-70-    );
supabase/migrations/0049_schedule_maintenance_edge_worker.sql:71:    RAISE NOTICE 'Scheduled in-range-storage-drain (maintenance Edge worker) every 15 minutes';
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-72-  ELSE
supabase/migrations/0049_schedule_maintenance_edge_worker.sql:73:    RAISE NOTICE 'pg_net not installed; skipping edge maintenance cron (dev)';
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-74-  END IF;
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-75-EXCEPTION
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-76-  WHEN OTHERS THEN
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-77-    RAISE NOTICE 'Could not schedule edge cron: % — use the Dashboard scheduled function instead', SQLERRM;
supabase/migrations/0049_schedule_maintenance_edge_worker.sql-78-END $$;
supabase/migrations/0059_proximity_wake_producer.sql-471--- ---------------------------------------------------------------------------
supabase/migrations/0059_proximity_wake_producer.sql-472--- 5. Retention (cleanup_ephemeral_data)
supabase/migrations/0059_proximity_wake_producer.sql-473--- ---------------------------------------------------------------------------
supabase/migrations/0059_proximity_wake_producer.sql-474--- Body as of 0058_subtle_wake_privacy.sql:334, unchanged. proximity_wake_requests
supabase/migrations/0059_proximity_wake_producer.sql-475--- retention already covers both user_id and recipient_user_id rows.
supabase/migrations/0059_proximity_wake_producer.sql-476-
supabase/migrations/0059_proximity_wake_producer.sql:477:CREATE OR REPLACE FUNCTION public.cleanup_ephemeral_data()
supabase/migrations/0059_proximity_wake_producer.sql-478-RETURNS VOID
supabase/migrations/0059_proximity_wake_producer.sql-479-LANGUAGE plpgsql
supabase/migrations/0059_proximity_wake_producer.sql-480-SECURITY DEFINER
supabase/migrations/0059_proximity_wake_producer.sql-481-SET search_path = pg_catalog, public
supabase/migrations/0059_proximity_wake_producer.sql-482-AS $$
supabase/migrations/0059_proximity_wake_producer.sql-483-DECLARE
supabase/migrations/0019_beta_security_hardening.sql-2388-    AND NOT EXISTS (SELECT 1 FROM public.messages msg WHERE msg.match_id = m.id);
supabase/migrations/0019_beta_security_hardening.sql-2389-  GET DIAGNOSTICS v_count = ROW_COUNT;
supabase/migrations/0019_beta_security_hardening.sql-2390-  RETURN v_count;
supabase/migrations/0019_beta_security_hardening.sql-2391-END;
supabase/migrations/0019_beta_security_hardening.sql-2392-$$;
supabase/migrations/0019_beta_security_hardening.sql-2393-
supabase/migrations/0019_beta_security_hardening.sql:2394:CREATE OR REPLACE FUNCTION public.cleanup_ephemeral_data()
supabase/migrations/0019_beta_security_hardening.sql-2395-RETURNS VOID
supabase/migrations/0019_beta_security_hardening.sql-2396-LANGUAGE sql
supabase/migrations/0019_beta_security_hardening.sql-2397-SECURITY DEFINER
supabase/migrations/0019_beta_security_hardening.sql-2398-SET search_path = pg_catalog, public
supabase/migrations/0019_beta_security_hardening.sql-2399-AS $$
supabase/migrations/0019_beta_security_hardening.sql-2400-  DELETE FROM public.token_claims
supabase/migrations/0019_beta_security_hardening.sql-2448-  SET status = 'processing', attempts = o.attempts + 1, processing_at = NOW()
supabase/migrations/0019_beta_security_hardening.sql-2449-  FROM picked
supabase/migrations/0019_beta_security_hardening.sql-2450-  WHERE o.id = picked.id
supabase/migrations/0019_beta_security_hardening.sql-2451-  RETURNING o.id, o.user_id, o.kind, o.title, o.body, o.payload, o.attempts;
supabase/migrations/0019_beta_security_hardening.sql-2452-$$;
supabase/migrations/0019_beta_security_hardening.sql-2453-
supabase/migrations/0019_beta_security_hardening.sql:2454:CREATE OR REPLACE FUNCTION public.run_maintenance()
supabase/migrations/0019_beta_security_hardening.sql-2455-RETURNS JSONB
supabase/migrations/0019_beta_security_hardening.sql-2456-LANGUAGE plpgsql
supabase/migrations/0019_beta_security_hardening.sql-2457-SECURITY DEFINER
supabase/migrations/0019_beta_security_hardening.sql-2458-SET search_path = pg_catalog, public
supabase/migrations/0019_beta_security_hardening.sql-2459-AS $$
supabase/migrations/0019_beta_security_hardening.sql-2460-DECLARE
supabase/migrations/0019_beta_security_hardening.sql-2461-  v_expired_feet INT;
supabase/migrations/0019_beta_security_hardening.sql-2462-  v_expired_matches INT;
supabase/migrations/0019_beta_security_hardening.sql-2463-  v_revealed_alerts INT;
supabase/migrations/0019_beta_security_hardening.sql-2464-  v_expiring_alerts INT;
supabase/migrations/0019_beta_security_hardening.sql-2465-  v_correlated INT;
supabase/migrations/0019_beta_security_hardening.sql-2466-BEGIN
supabase/migrations/0019_beta_security_hardening.sql:2467:  PERFORM public.cleanup_ephemeral_data();
supabase/migrations/0019_beta_security_hardening.sql-2468-  v_expired_feet := public.expire_feet_encounters();
supabase/migrations/0019_beta_security_hardening.sql-2469-  v_expired_matches := public.expire_idle_matches();
supabase/migrations/0019_beta_security_hardening.sql-2470-  v_revealed_alerts := public.queue_revealed_encounter_alerts();
supabase/migrations/0019_beta_security_hardening.sql-2471-  v_expiring_alerts := public.queue_expiring_encounter_alerts();
supabase/migrations/0019_beta_security_hardening.sql-2472-  v_correlated := public.batch_correlate_recent_pings(45);
supabase/migrations/0019_beta_security_hardening.sql-2473-  RETURN jsonb_build_object(
supabase/migrations/0019_beta_security_hardening.sql-2507-        'register_push_token', 'unregister_push_token',
supabase/migrations/0019_beta_security_hardening.sql-2508-        'submit_photo_for_verification', 'complete_ai_photo_review',
supabase/migrations/0019_beta_security_hardening.sql-2509-        'decide_photo_verification', 'stub_auto_approve_photo',
supabase/migrations/0019_beta_security_hardening.sql-2510-        'has_active_boost', 'is_subscriber',
supabase/migrations/0019_beta_security_hardening.sql-2511-        'cleanup_ephemeral_data', 'expire_feet_encounters',
supabase/migrations/0019_beta_security_hardening.sql-2512-        'expire_idle_matches', 'queue_revealed_encounter_alerts',
supabase/migrations/0019_beta_security_hardening.sql:2513:        'queue_expiring_encounter_alerts', 'run_maintenance',
supabase/migrations/0019_beta_security_hardening.sql-2514-        'claim_notification_batch', 'log_ai_run', 'complete_ai_run',
supabase/migrations/0019_beta_security_hardening.sql-2515-        'log_ai_event', 'submit_ai_feedback', 'backend_health',
supabase/migrations/0019_beta_security_hardening.sql-2516-        'encounter_reveal_delay_hours', 'is_discoverable_user',
supabase/migrations/0019_beta_security_hardening.sql-2517-        'current_user_can_discover', 'can_access_match',
supabase/migrations/0019_beta_security_hardening.sql-2518-        'can_view_profile_photos', 'can_modify_profile_photo',
supabase/migrations/0019_beta_security_hardening.sql-2519-        'handle_new_user', 'handle_updated_at', 'notify_on_new_encounter',
supabase/migrations/0019_beta_security_hardening.sql-2562-    WHERE n.nspname = 'public'
supabase/migrations/0019_beta_security_hardening.sql-2563-      AND p.proname = ANY (ARRAY[
supabase/migrations/0019_beta_security_hardening.sql-2564-        'complete_ai_photo_review', 'decide_photo_verification',
supabase/migrations/0019_beta_security_hardening.sql-2565-        'stub_auto_approve_photo', 'cleanup_ephemeral_data',
supabase/migrations/0019_beta_security_hardening.sql-2566-        'expire_feet_encounters', 'expire_idle_matches',
supabase/migrations/0019_beta_security_hardening.sql-2567-        'queue_revealed_encounter_alerts', 'queue_expiring_encounter_alerts',
supabase/migrations/0019_beta_security_hardening.sql:2568:        'batch_correlate_recent_pings', 'run_maintenance',
supabase/migrations/0019_beta_security_hardening.sql-2569-        'claim_notification_batch', 'is_blocked_pair',
supabase/migrations/0019_beta_security_hardening.sql-2570-        'log_ai_run', 'complete_ai_run', 'log_ai_event'
supabase/migrations/0019_beta_security_hardening.sql-2571-      ])
supabase/migrations/0019_beta_security_hardening.sql-2572-  LOOP
supabase/migrations/0019_beta_security_hardening.sql-2573-    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', r.sig);
supabase/migrations/0019_beta_security_hardening.sql-2574-  END LOOP;

exec
/bin/bash -lc "PGCONNECT_TIMEOUT=2 psql 'postgresql://postgres:postgres@127.0.0.1:54322/postgres' -X -v ON_ERROR_STOP=1 -Atc \"select current_setting('server_version'), to_regclass('public.sightings'), (select attnotnull from pg_attribute where attrelid='public.sightings'::regclass and attname='observer_lat'), (select attnotnull from pg_attribute where attrelid='public.sightings'::regclass and attname='observer_lon');\"" in /home/hazypiff/in-range
 exited 127 in 0ms:
/bin/bash: line 1: psql: command not found

exec
/bin/bash -lc "nl -ba lib/features/beacon/batch_token_source.dart | sed -n '1,300p'
nl -ba lib/features/beacon/ephemeral_token_generator.dart | sed -n '1,180p'
rtk rg -n -C 5 \"issue_token_batch|p_window_minutes|expiresAt\" lib/features/beacon test | head -n 300
rtk rg -n -C 4 \"enforce_batch_tokens\" supabase/migrations docs lib" in /home/hazypiff/in-range
 succeeded in 0ms:
     1	import 'dart:math';
     2	
     3	import 'package:in_range/features/beacon/ephemeral_token_generator.dart';
     4	
     5	/// One slot of a server-issued token batch (#6 step 2).
     6	class BatchSlot {
     7	  const BatchSlot({
     8	    required this.token,
     9	    required this.validFrom,
    10	    required this.validUntil,
    11	  });
    12	
    13	  final String token; // opaque 32 hex chars (128-bit)
    14	  final DateTime validFrom;
    15	  final DateTime validUntil;
    16	}
    17	
    18	/// Fetches a day's opaque token batch. Returns [] when the cloud is unavailable
    19	/// (local BLE mode) or the RPC fails — the caller then falls back to a random
    20	/// token so advertising never stalls.
    21	typedef BatchFetcher = Future<List<BatchSlot>> Function(
    22	    DateTime dayUtc, int windowMinutes);
    23	
    24	/// Server-issued opaque token source (#6 step 2).
    25	///
    26	/// Replaces the client-side [EphemeralTokenGenerator], whose HMAC was keyed by a
    27	/// secret shipped in the app (so it was cosmetic — anyone with the binary could
    28	/// forge it). Here the SERVER mints the opaque tokens (`issue_token_batch`); the
    29	/// client fetches a day's batch once and advertises the slot covering "now". The
    30	/// token value is unguessable and server-owned, which is what makes it
    31	/// unforgeable and enables attested issuance / revocation later.
    32	///
    33	/// Fallback: when no batch is available (local mode or a transient fetch
    34	/// failure) it yields a locally-generated random opaque token so BLE advertising
    35	/// keeps working; those tokens simply won't correlate server-side until a real
    36	/// batch loads. Never throws.
    37	class BatchTokenSource {
    38	  BatchTokenSource({
    39	    required BatchFetcher fetchBatch,
    40	    Duration rotationWindow = const Duration(minutes: 15),
    41	    DateTime Function() now = DateTime.now,
    42	    Random? random,
    43	  })  : _fetch = fetchBatch,
    44	        _window = rotationWindow,
    45	        _now = now,
    46	        _rand = random ?? Random.secure();
    47	
    48	  final BatchFetcher _fetch;
    49	  final Duration _window;
    50	  final DateTime Function() _now;
    51	  final Random _rand;
    52	
    53	  final List<BatchSlot> _slots = <BatchSlot>[];
    54	
    55	  /// Read-only view of the cached batch — the iOS native carrier needs the
    56	  /// whole day's slots so GATT reads can serve the right token per read
    57	  /// without any background timer (IOS_BACKGROUND_BLE_WIRING.md W2).
    58	  List<BatchSlot> get slots => List.unmodifiable(_slots);
    59	
    60	  /// Same rotation policy as before: rotate ~1 min before the current token
    61	  /// expires (or immediately when there is none).
    62	  bool shouldRotate(EphemeralToken? current,
    63	      {Duration grace = const Duration(minutes: 1)}) {
    64	    if (current == null) return true;
    65	    return _now().isAfter(current.expiresAt.subtract(grace));
    66	  }
    67	
    68	  /// The opaque token for the slot covering "now", fetching/refreshing the batch
    69	  /// as needed. Never throws — falls back to a random opaque token.
    70	  Future<EphemeralToken> nextToken() async {
    71	    final now = _now();
    72	    BatchSlot? slot = _covering(now);
    73	    if (slot == null) {
    74	      await _ensureBatch(now);
    75	      slot = _covering(now);
    76	    }
    77	    if (slot != null) {
    78	      return EphemeralToken(
    79	        token: slot.token,
    80	        epochSeconds: slot.validFrom.millisecondsSinceEpoch ~/ 1000,
    81	        issuedAt: now,
    82	        expiresAt: slot.validUntil,
    83	      );
    84	    }
    85	    return _randomToken(now);
    86	  }
    87	
    88	  /// The cached slot whose [validFrom, validUntil) contains [now]. Consecutive
    89	  /// slots overlap by the server-side grace, so prefer the latest-starting one.
    90	  BatchSlot? _covering(DateTime now) {
    91	    BatchSlot? best;
    92	    for (final s in _slots) {
    93	      if (!now.isBefore(s.validFrom) && now.isBefore(s.validUntil)) {
    94	        if (best == null || s.validFrom.isAfter(best.validFrom)) best = s;
    95	      }
    96	    }
    97	    return best;
    98	  }
    99	
   100	  Future<void> _ensureBatch(DateTime now) async {
   101	    final utc = now.toUtc();
   102	    final today = DateTime.utc(utc.year, utc.month, utc.day);
   103	    // An uninterrupted dark session crosses midnight UTC: with only today's
   104	    // slots the native carrier falls back to a stale token at 00:00 and peers
   105	    // stop resolving us (audit 2026-07-25). issue_token_batch permits today
   106	    // AND tomorrow and stays under its 3-active-days abuse cap, so fetch both.
   107	    // Each fetch fails soft independently — a tomorrow-fetch failure must
   108	    // never cost today's batch.
   109	    Future<List<BatchSlot>> fetchTolerant(DateTime day) async {
   110	      try {
   111	        return await _fetch(day, _window.inMinutes);
   112	      } catch (_) {
   113	        return <BatchSlot>[];
   114	      }
   115	    }
   116	
   117	    final results = await Future.wait([
   118	      fetchTolerant(today),
   119	      fetchTolerant(today.add(const Duration(days: 1))),
   120	    ]);
   121	    final combined = <BatchSlot>[...results[0], ...results[1]];
   122	    if (combined.isNotEmpty) {
   123	      _slots
   124	        ..clear()
   125	        ..addAll(combined);
   126	    }
   127	  }
   128	
   129	  EphemeralToken _randomToken(DateTime now) {
   130	    final bytes = List<int>.generate(16, (_) => _rand.nextInt(256));
   131	    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
   132	    final windowSecs = _window.inSeconds;
   133	    final epoch =
   134	        (now.millisecondsSinceEpoch ~/ 1000 ~/ windowSecs) * windowSecs;
   135	    return EphemeralToken(
   136	      token: hex,
   137	      epochSeconds: epoch,
   138	      issuedAt: now,
   139	      expiresAt:
   140	          DateTime.fromMillisecondsSinceEpoch((epoch + windowSecs) * 1000),
   141	    );
   142	  }
   143	}
     1	import 'dart:convert';
     2	import 'dart:math';
     3	import 'dart:typed_data';
     4	
     5	import 'package:crypto/crypto.dart';
     6	
     7	/// EphemeralTokenGenerator
     8	///
     9	/// SUPERSEDED by [BatchTokenSource] (#6 step 2): beacon tokens are now minted by
    10	/// the server (`issue_token_batch`) as opaque values, not derived client-side
    11	/// from a shipped HMAC secret. This class is retained only for reference and its
    12	/// own tests; [EphemeralToken] below is still the shared token value type.
    13	///
    14	/// Implements the v1 token format from docs/ephemeral-token-spec.md:
    15	///
    16	///   `user_hash_8bytes|epoch_4bytes|random_16bytes|hmac_8bytes`
    17	///
    18	/// - user_hash: first 8 bytes of HMAC-SHA256(user_id_secret, version|user_id)
    19	///   (never the raw user UUID).
    20	/// - epoch: Unix seconds rounded down to the rotation window (default 15 min).
    21	/// - random: 16 bytes from Random.secure().
    22	/// - hmac: truncated HMAC-SHA256(global_secret, payload) — anti-forgery.
    23	///
    24	/// The token is base64url-encoded for transport. It rotates every epoch; on
    25	/// rotation the client must call `claim_token` again on the server.
    26	class EphemeralTokenGenerator {
    27	  EphemeralTokenGenerator({
    28	    required String userIdSecret,
    29	    required String userId,
    30	    required String hmacSecret,
    31	    Duration rotationWindow = const Duration(minutes: 15),
    32	    DateTime Function() now = DateTime.now,
    33	  })  : _userIdSecret = userIdSecret,
    34	        _userId = userId,
    35	        _hmacSecret = hmacSecret,
    36	        _rotationWindow = rotationWindow,
    37	        _now = now;
    38	
    39	  final String _userIdSecret;
    40	  final String _userId;
    41	  final String _hmacSecret;
    42	  final Duration _rotationWindow;
    43	  final DateTime Function() _now;
    44	
    45	  static const String _tokenVersion = 'inrange-token-v1';
    46	
    47	  /// Generates a fresh ephemeral token for the current rotation window.
    48	  /// Returns the token string plus the epoch it is valid for and its
    49	  /// computed expiry (end of the rotation window + a small grace period).
    50	  EphemeralToken generate() {
    51	    final now = _now();
    52	    final windowSeconds = _rotationWindow.inSeconds;
    53	    final epochSeconds =
    54	        (now.millisecondsSinceEpoch ~/ 1000 ~/ windowSeconds) * windowSeconds;
    55	    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
    56	      (epochSeconds + windowSeconds) * 1000,
    57	    );
    58	
    59	    final userHash = _userHash();
    60	    final randomBytes = _secureRandomBytes(16);
    61	    final epochBytes = _int32BigEndian(epochSeconds);
    62	
    63	    final payload = BytesBuilder()
    64	      ..add(userHash)
    65	      ..add(epochBytes)
    66	      ..add(randomBytes);
    67	    final payloadBytes = payload.toBytes();
    68	
    69	    final sig = _hmacTruncated(payloadBytes, length: 8);
    70	    final tokenBytes = BytesBuilder()
    71	      ..add(payloadBytes)
    72	      ..add(sig);
    73	    final token = base64Url.encode(tokenBytes.toBytes()).replaceAll('=', '');
    74	
    75	    return EphemeralToken(
    76	      token: token,
    77	      epochSeconds: epochSeconds,
    78	      issuedAt: now,
    79	      expiresAt: expiresAt,
    80	    );
    81	  }
    82	
    83	  /// Returns true if the previously issued token has expired (or is within
    84	  /// the refresh margin) and should be rotated.
    85	  bool shouldRotate(EphemeralToken? current,
    86	      {Duration grace = const Duration(minutes: 1)}) {
    87	    if (current == null) return true;
    88	    return _now().isAfter(current.expiresAt.subtract(grace));
    89	  }
    90	
    91	  List<int> _userHash() {
    92	    final h = Hmac(sha256, utf8.encode(_userIdSecret));
    93	    final digest = h.convert(utf8.encode('$_tokenVersion|$_userId'));
    94	    return digest.bytes.sublist(0, 8);
    95	  }
    96	
    97	  List<int> _hmacTruncated(List<int> payload, {required int length}) {
    98	    final h = Hmac(sha256, utf8.encode(_hmacSecret));
    99	    final digest = h.convert(payload);
   100	    return digest.bytes.sublist(0, length);
   101	  }
   102	
   103	  static List<int> _secureRandomBytes(int length) {
   104	    final r = Random.secure();
   105	    return List<int>.generate(length, (_) => r.nextInt(256));
   106	  }
   107	
   108	  static List<int> _int32BigEndian(int value) {
   109	    final data = ByteData(4)..setUint32(0, value, Endian.big);
   110	    return data.buffer.asUint8List().toList();
   111	  }
   112	}
   113	
   114	/// A generated ephemeral token with its metadata.
   115	class EphemeralToken {
   116	  const EphemeralToken({
   117	    required this.token,
   118	    required this.epochSeconds,
   119	    required this.issuedAt,
   120	    required this.expiresAt,
   121	  });
   122	
   123	  final String token;
   124	  final int epochSeconds;
   125	  final DateTime issuedAt;
   126	  final DateTime expiresAt;
   127	
   128	  bool get isExpired => DateTime.now().isAfter(expiresAt);
   129	}
test/ephemeral_token_generator_test.dart-33-      hmacSecret: hmacSecret,
test/ephemeral_token_generator_test.dart-34-      now: () => now,
test/ephemeral_token_generator_test.dart-35-    );
test/ephemeral_token_generator_test.dart-36-    final token = generator.generate();
test/ephemeral_token_generator_test.dart-37-    expect(generator.shouldRotate(token), isFalse);
test/ephemeral_token_generator_test.dart:38:    now = token.expiresAt.subtract(const Duration(seconds: 30));
test/ephemeral_token_generator_test.dart-39-    expect(generator.shouldRotate(token), isTrue);
test/ephemeral_token_generator_test.dart-40-  });
test/ephemeral_token_generator_test.dart-41-}
lib/features/beacon/beacon_service.dart-79-    venueAnchors.onChanged =
lib/features/beacon/beacon_service.dart-80-        (descriptors) => unawaited(subtleWake.syncAnchors(descriptors));
lib/features/beacon/beacon_service.dart-81-  }
lib/features/beacon/beacon_service.dart-82-
lib/features/beacon/beacon_service.dart-83-  // #6 step 2: opaque beacon tokens now come from the server
lib/features/beacon/beacon_service.dart:84:  // (issue_token_batch), not a client-side HMAC keyed by a secret shipped in the
lib/features/beacon/beacon_service.dart-85-  // app. `userIdSecret` is kept in the signature for API stability but is no
lib/features/beacon/beacon_service.dart-86-  // longer used for token derivation.
lib/features/beacon/beacon_service.dart-87-  late final BatchTokenSource _tokenSource = BatchTokenSource(
lib/features/beacon/beacon_service.dart-88-    fetchBatch: _fetchTokenBatch,
lib/features/beacon/beacon_service.dart-89-    rotationWindow: _rotationWindow,
lib/features/beacon/beacon_service.dart-139-
lib/features/beacon/beacon_service.dart-140-  /// Fired after every claim attempt AND every rotation so the UI reflects the
lib/features/beacon/beacon_service.dart-141-  /// CURRENT token expiry and cloud-claim state — not the first token's stale
lib/features/beacon/beacon_service.dart-142-  /// values (reviewer #11). cloudSynced is null when there is no cloud (local
lib/features/beacon/beacon_service.dart-143-  /// mode); true/false otherwise.
lib/features/beacon/beacon_service.dart:144:  void Function(DateTime? expiresAt, bool? cloudSynced)? onClaimStateChanged;
lib/features/beacon/beacon_service.dart-145-
lib/features/beacon/beacon_service.dart-146-  /// Retryable claim upload (see ClaimManager). Reports cloud-sync state after
lib/features/beacon/beacon_service.dart-147-  /// every attempt so the UI can't show the first token's stale values.
lib/features/beacon/beacon_service.dart-148-  late final ClaimManager _claimMgr = ClaimManager(upload: _uploadClaim)
lib/features/beacon/beacon_service.dart-149-    ..onState = (synced) {
lib/features/beacon/beacon_service.dart-150-      _cloudClaimed = synced;
lib/features/beacon/beacon_service.dart:151:      onClaimStateChanged?.call(_currentToken?.expiresAt, synced);
lib/features/beacon/beacon_service.dart-152-    };
lib/features/beacon/beacon_service.dart-153-
lib/features/beacon/beacon_service.dart-154-  String? _claimRangeType;
lib/features/beacon/beacon_service.dart-155-
lib/features/beacon/beacon_service.dart-156-  bool _isOn = false;
lib/features/beacon/beacon_service.dart-965-    // Timeout is load-bearing: with no/half-dead network this RPC HANGS
lib/features/beacon/beacon_service.dart-966-    // (S22 field incident 2026-07-23 — beacon button appeared dead, the
lib/features/beacon/beacon_service.dart-967-    // whole turnOnBeacon flow stuck here forever). A timeout throws, the
lib/features/beacon/beacon_service.dart-968-    // token source catches and falls back to a local random token, and BLE
lib/features/beacon/beacon_service.dart-969-    // comes up in local mode as designed.
lib/features/beacon/beacon_service.dart:970:    final rows = await InRangeSupabase.client.rpc('issue_token_batch', params: {
lib/features/beacon/beacon_service.dart-971-      'p_day': dayStr,
lib/features/beacon/beacon_service.dart:972:      'p_window_minutes': windowMinutes,
lib/features/beacon/beacon_service.dart-973-    }).timeout(const Duration(seconds: 8));
lib/features/beacon/beacon_service.dart-974-    if (rows is! List) return const <BatchSlot>[];
lib/features/beacon/beacon_service.dart-975-    final out = <BatchSlot>[];
lib/features/beacon/beacon_service.dart-976-    for (final r in rows) {
lib/features/beacon/beacon_service.dart-977-      if (r is Map &&
lib/features/beacon/beacon_service.dart-1011-    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
lib/features/beacon/beacon_service.dart-1012-      final payload = BackgroundBeaconChannel.slotsPayload(
lib/features/beacon/beacon_service.dart-1013-        _tokenSource.slots,
lib/features/beacon/beacon_service.dart-1014-        currentToken: _currentToken!.token,
lib/features/beacon/beacon_service.dart-1015-        currentFrom: _currentToken!.issuedAt,
lib/features/beacon/beacon_service.dart:1016:        currentUntil: _currentToken!.expiresAt,
lib/features/beacon/beacon_service.dart-1017-      );
lib/features/beacon/beacon_service.dart-1018-      final ok = await _bgBeacon.start(payload);
lib/features/beacon/beacon_service.dart-1019-      // W5 test gate: only establish persistent links when the build opts in.
lib/features/beacon/beacon_service.dart-1020-      unawaited(_bgBeacon.setW5Links(AppConfig.w5LinksEnabled));
lib/features/beacon/beacon_service.dart-1021-      // Crack #1: refresh the native wake-ping endpoint + JWT on every
lib/features/beacon/beacon_service.dart-2539-    _cachedLon = lon;
lib/features/beacon/beacon_service.dart-2540-
lib/features/beacon/beacon_service.dart-2541-    // Publish the new token's expiry immediately, even before the claim RPC
lib/features/beacon/beacon_service.dart-2542-    // resolves, so the UI countdown tracks the current token (reviewer #11).
lib/features/beacon/beacon_service.dart-2543-    onClaimStateChanged?.call(
lib/features/beacon/beacon_service.dart:2544:        _currentToken!.expiresAt, AppConfig.hasRealSupabase ? _cloudClaimed : null);
lib/features/beacon/beacon_service.dart-2545-
lib/features/beacon/beacon_service.dart-2546-    if (!AppConfig.hasRealSupabase) {
lib/features/beacon/beacon_service.dart-2547-      _cloudClaimed = false;
lib/features/beacon/beacon_service.dart-2548-      debugPrint('claim_token skipped (no real Supabase — local BLE mode)');
lib/features/beacon/beacon_service.dart-2549-      return;
lib/features/beacon/beacon_service.dart-2596-    final claimToken = _currentCorrelationId!
lib/features/beacon/beacon_service.dart-2597-        .map((b) => b.toRadixString(16).padLeft(2, '0'))
lib/features/beacon/beacon_service.dart-2598-        .join();
lib/features/beacon/beacon_service.dart-2599-    // Always send UTC — a local DateTime without offset is misread as UTC by
lib/features/beacon/beacon_service.dart-2600-    // Postgres and expires claims hours early (broke feet correlation once).
lib/features/beacon/beacon_service.dart:2601:    final until = _currentToken!.expiresAt.toUtc().add(const Duration(minutes: 2));
lib/features/beacon/beacon_service.dart-2602-    // Timeout: a hanging claim (dead network) must fail the attempt so
lib/features/beacon/beacon_service.dart-2603-    // ClaimManager's bounded retry + the "Local BLE only" fallback engage,
lib/features/beacon/beacon_service.dart-2604-    // instead of wedging the whole beacon-on flow (S22 2026-07-23).
lib/features/beacon/beacon_service.dart-2605-    await InRangeSupabase.client.rpc('claim_token', params: {
lib/features/beacon/beacon_service.dart-2606-      'p_token': claimToken,
lib/features/beacon/batch_token_source.dart-23-
lib/features/beacon/batch_token_source.dart-24-/// Server-issued opaque token source (#6 step 2).
lib/features/beacon/batch_token_source.dart-25-///
lib/features/beacon/batch_token_source.dart-26-/// Replaces the client-side [EphemeralTokenGenerator], whose HMAC was keyed by a
lib/features/beacon/batch_token_source.dart-27-/// secret shipped in the app (so it was cosmetic — anyone with the binary could
lib/features/beacon/batch_token_source.dart:28:/// forge it). Here the SERVER mints the opaque tokens (`issue_token_batch`); the
lib/features/beacon/batch_token_source.dart-29-/// client fetches a day's batch once and advertises the slot covering "now". The
lib/features/beacon/batch_token_source.dart-30-/// token value is unguessable and server-owned, which is what makes it
lib/features/beacon/batch_token_source.dart-31-/// unforgeable and enables attested issuance / revocation later.
lib/features/beacon/batch_token_source.dart-32-///
lib/features/beacon/batch_token_source.dart-33-/// Fallback: when no batch is available (local mode or a transient fetch
lib/features/beacon/batch_token_source.dart-60-  /// Same rotation policy as before: rotate ~1 min before the current token
lib/features/beacon/batch_token_source.dart-61-  /// expires (or immediately when there is none).
lib/features/beacon/batch_token_source.dart-62-  bool shouldRotate(EphemeralToken? current,
lib/features/beacon/batch_token_source.dart-63-      {Duration grace = const Duration(minutes: 1)}) {
lib/features/beacon/batch_token_source.dart-64-    if (current == null) return true;
lib/features/beacon/batch_token_source.dart:65:    return _now().isAfter(current.expiresAt.subtract(grace));
lib/features/beacon/batch_token_source.dart-66-  }
lib/features/beacon/batch_token_source.dart-67-
lib/features/beacon/batch_token_source.dart-68-  /// The opaque token for the slot covering "now", fetching/refreshing the batch
lib/features/beacon/batch_token_source.dart-69-  /// as needed. Never throws — falls back to a random opaque token.
lib/features/beacon/batch_token_source.dart-70-  Future<EphemeralToken> nextToken() async {
lib/features/beacon/batch_token_source.dart-77-    if (slot != null) {
lib/features/beacon/batch_token_source.dart-78-      return EphemeralToken(
lib/features/beacon/batch_token_source.dart-79-        token: slot.token,
lib/features/beacon/batch_token_source.dart-80-        epochSeconds: slot.validFrom.millisecondsSinceEpoch ~/ 1000,
lib/features/beacon/batch_token_source.dart-81-        issuedAt: now,
lib/features/beacon/batch_token_source.dart:82:        expiresAt: slot.validUntil,
lib/features/beacon/batch_token_source.dart-83-      );
lib/features/beacon/batch_token_source.dart-84-    }
lib/features/beacon/batch_token_source.dart-85-    return _randomToken(now);
lib/features/beacon/batch_token_source.dart-86-  }
lib/features/beacon/batch_token_source.dart-87-
lib/features/beacon/batch_token_source.dart-100-  Future<void> _ensureBatch(DateTime now) async {
lib/features/beacon/batch_token_source.dart-101-    final utc = now.toUtc();
lib/features/beacon/batch_token_source.dart-102-    final today = DateTime.utc(utc.year, utc.month, utc.day);
lib/features/beacon/batch_token_source.dart-103-    // An uninterrupted dark session crosses midnight UTC: with only today's
lib/features/beacon/batch_token_source.dart-104-    // slots the native carrier falls back to a stale token at 00:00 and peers
lib/features/beacon/batch_token_source.dart:105:    // stop resolving us (audit 2026-07-25). issue_token_batch permits today
lib/features/beacon/batch_token_source.dart-106-    // AND tomorrow and stays under its 3-active-days abuse cap, so fetch both.
lib/features/beacon/batch_token_source.dart-107-    // Each fetch fails soft independently — a tomorrow-fetch failure must
lib/features/beacon/batch_token_source.dart-108-    // never cost today's batch.
lib/features/beacon/batch_token_source.dart-109-    Future<List<BatchSlot>> fetchTolerant(DateTime day) async {
lib/features/beacon/batch_token_source.dart-110-      try {
lib/features/beacon/batch_token_source.dart-134-        (now.millisecondsSinceEpoch ~/ 1000 ~/ windowSecs) * windowSecs;
lib/features/beacon/batch_token_source.dart-135-    return EphemeralToken(
lib/features/beacon/batch_token_source.dart-136-      token: hex,
lib/features/beacon/batch_token_source.dart-137-      epochSeconds: epoch,
lib/features/beacon/batch_token_source.dart-138-      issuedAt: now,
lib/features/beacon/batch_token_source.dart:139:      expiresAt:
lib/features/beacon/batch_token_source.dart-140-          DateTime.fromMillisecondsSinceEpoch((epoch + windowSecs) * 1000),
lib/features/beacon/batch_token_source.dart-141-    );
lib/features/beacon/batch_token_source.dart-142-  }
lib/features/beacon/batch_token_source.dart-143-}
lib/features/beacon/beacon_provider.dart-165-    // keeps advertising.
lib/features/beacon/beacon_provider.dart-166-    unawaited(_service.restoreNativeSession().then((restored) {
lib/features/beacon/beacon_provider.dart-167-      if (restored && mounted) {
lib/features/beacon/beacon_provider.dart-168-        state = BeaconState(
lib/features/beacon/beacon_provider.dart-169-          isOn: true,
lib/features/beacon/beacon_provider.dart:170:          tokenExpiresAt: _service.currentToken?.expiresAt,
lib/features/beacon/beacon_provider.dart-171-          cloudSynced: AppConfig.hasRealSupabase ? _service.cloudClaimed : null,
lib/features/beacon/beacon_provider.dart-172-          discoverable: _service.discoverable,
lib/features/beacon/beacon_provider.dart-173-        );
lib/features/beacon/beacon_provider.dart-174-      }
lib/features/beacon/beacon_provider.dart-175-    }));
lib/features/beacon/beacon_provider.dart-176-    // Every claim attempt / rotation republishes token expiry + cloud state,
lib/features/beacon/beacon_provider.dart-177-    // so the UI can't show the first token's stale values (reviewer #11).
lib/features/beacon/beacon_provider.dart:178:    _service.onClaimStateChanged = (expiresAt, cloudSynced) {
lib/features/beacon/beacon_provider.dart-179-      if (!mounted || !state.isOn) return;
lib/features/beacon/beacon_provider.dart-180-      state = BeaconState(
lib/features/beacon/beacon_provider.dart-181-        isOn: true,
lib/features/beacon/beacon_provider.dart:182:        tokenExpiresAt: expiresAt ?? state.tokenExpiresAt,
lib/features/beacon/beacon_provider.dart-183-        cloudSynced: cloudSynced,
lib/features/beacon/beacon_provider.dart-184-        // Read the service, not our own snapshot: `discoverable` is now composed
lib/features/beacon/beacon_provider.dart-185-        // (advertise up AND receive path alive) and can flip with no user action.
lib/features/beacon/beacon_provider.dart-186-        discoverable: _service.discoverable,
lib/features/beacon/beacon_provider.dart-187-      );
lib/features/beacon/beacon_provider.dart-251-            rethrow;
lib/features/beacon/beacon_provider.dart-252-          }
lib/features/beacon/beacon_provider.dart-253-        }
lib/features/beacon/beacon_provider.dart-254-        state = BeaconState(
lib/features/beacon/beacon_provider.dart-255-          isOn: true,
lib/features/beacon/beacon_provider.dart:256:          tokenExpiresAt: _service.currentToken?.expiresAt,
lib/features/beacon/beacon_provider.dart-257-          cloudSynced: AppConfig.hasRealSupabase ? _service.cloudClaimed : null,
lib/features/beacon/beacon_provider.dart-258-          discoverable: _service.discoverable,
lib/features/beacon/beacon_provider.dart-259-        );
lib/features/beacon/beacon_provider.dart-260-      } catch (e) {
lib/features/beacon/beacon_provider.dart-261-        debugPrint('turnOnBeacon failed: $e');
test/features/beacon/batch_token_source_test.dart-1-import 'package:flutter_test/flutter_test.dart';
test/features/beacon/batch_token_source_test.dart-2-import 'package:in_range/features/beacon/batch_token_source.dart';
test/features/beacon/batch_token_source_test.dart-3-import 'package:in_range/features/beacon/ephemeral_token_generator.dart';
test/features/beacon/batch_token_source_test.dart-4-
test/features/beacon/batch_token_source_test.dart:5:// Mirrors the server (issue_token_batch): 15-min slots tiling a UTC day, each
test/features/beacon/batch_token_source_test.dart-6-// valid for window + 2 min grace.
test/features/beacon/batch_token_source_test.dart-7-List<BatchSlot> _dayBatch(DateTime dayUtc, int windowMinutes) {
test/features/beacon/batch_token_source_test.dart-8-  final slots = <BatchSlot>[];
test/features/beacon/batch_token_source_test.dart-9-  final n = 1440 ~/ windowMinutes;
test/features/beacon/batch_token_source_test.dart-10-  for (var g = 0; g < n; g++) {
test/features/beacon/batch_token_source_test.dart-33-      },
test/features/beacon/batch_token_source_test.dart-34-      now: () => now,
test/features/beacon/batch_token_source_test.dart-35-    );
test/features/beacon/batch_token_source_test.dart-36-    final t = await src.nextToken();
test/features/beacon/batch_token_source_test.dart-37-    expect(t.token, _dayBatch(day, 15)[1].token);
test/features/beacon/batch_token_source_test.dart:38:    expect(t.expiresAt, day.add(const Duration(minutes: 32)));
test/features/beacon/batch_token_source_test.dart-39-    expect(fetches, 2, reason: 'today AND tomorrow are fetched together');
test/features/beacon/batch_token_source_test.dart-40-  });
test/features/beacon/batch_token_source_test.dart-41-
test/features/beacon/batch_token_source_test.dart-42-  test('advancing across slots reuses the cached batch (no refetch)', () async {
test/features/beacon/batch_token_source_test.dart-43-    var now = day.add(const Duration(minutes: 5)); // slot 0
test/features/beacon/batch_token_source_test.dart-97-      now: () => now,
test/features/beacon/batch_token_source_test.dart-98-    );
test/features/beacon/batch_token_source_test.dart-99-    final t = await src.nextToken();
test/features/beacon/batch_token_source_test.dart-100-    expect(_hex32.hasMatch(t.token), isTrue);
test/features/beacon/batch_token_source_test.dart-101-    // window-aligned expiry
test/features/beacon/batch_token_source_test.dart:102:    expect(t.expiresAt.isAfter(now), isTrue);
test/features/beacon/batch_token_source_test.dart:103:    expect(t.expiresAt.difference(t.issuedAt).inMinutes <= 15, isTrue);
test/features/beacon/batch_token_source_test.dart-104-  });
test/features/beacon/batch_token_source_test.dart-105-
test/features/beacon/batch_token_source_test.dart-106-  test('never throws when the fetch fails; yields a random token', () async {
test/features/beacon/batch_token_source_test.dart-107-    final now = day.add(const Duration(minutes: 20));
test/features/beacon/batch_token_source_test.dart-108-    final src = BatchTokenSource(
test/features/beacon/batch_token_source_test.dart-123-    final slot1 = _dayBatch(day, 15)[1]; // expires at 32 min
test/features/beacon/batch_token_source_test.dart-124-    final tok = EphemeralToken(
test/features/beacon/batch_token_source_test.dart-125-      token: slot1.token,
test/features/beacon/batch_token_source_test.dart-126-      epochSeconds: slot1.validFrom.millisecondsSinceEpoch ~/ 1000,
test/features/beacon/batch_token_source_test.dart-127-      issuedAt: slot1.validFrom,
test/features/beacon/batch_token_source_test.dart:128:      expiresAt: slot1.validUntil,
test/features/beacon/batch_token_source_test.dart-129-    );
test/features/beacon/batch_token_source_test.dart-130-    now = day.add(const Duration(minutes: 20));
test/features/beacon/batch_token_source_test.dart-131-    expect(src.shouldRotate(tok), isFalse); // 12 min left
test/features/beacon/batch_token_source_test.dart-132-    now = day.add(const Duration(minutes: 31, seconds: 30)); // <1 min left
test/features/beacon/batch_token_source_test.dart-133-    expect(src.shouldRotate(tok), isTrue);
lib/features/beacon/ephemeral_token_generator.dart-5-import 'package:crypto/crypto.dart';
lib/features/beacon/ephemeral_token_generator.dart-6-
lib/features/beacon/ephemeral_token_generator.dart-7-/// EphemeralTokenGenerator
lib/features/beacon/ephemeral_token_generator.dart-8-///
lib/features/beacon/ephemeral_token_generator.dart-9-/// SUPERSEDED by [BatchTokenSource] (#6 step 2): beacon tokens are now minted by
lib/features/beacon/ephemeral_token_generator.dart:10:/// the server (`issue_token_batch`) as opaque values, not derived client-side
lib/features/beacon/ephemeral_token_generator.dart-11-/// from a shipped HMAC secret. This class is retained only for reference and its
lib/features/beacon/ephemeral_token_generator.dart-12-/// own tests; [EphemeralToken] below is still the shared token value type.
lib/features/beacon/ephemeral_token_generator.dart-13-///
lib/features/beacon/ephemeral_token_generator.dart-14-/// Implements the v1 token format from docs/ephemeral-token-spec.md:
lib/features/beacon/ephemeral_token_generator.dart-15-///
lib/features/beacon/ephemeral_token_generator.dart-50-  EphemeralToken generate() {
lib/features/beacon/ephemeral_token_generator.dart-51-    final now = _now();
lib/features/beacon/ephemeral_token_generator.dart-52-    final windowSeconds = _rotationWindow.inSeconds;
lib/features/beacon/ephemeral_token_generator.dart-53-    final epochSeconds =
lib/features/beacon/ephemeral_token_generator.dart-54-        (now.millisecondsSinceEpoch ~/ 1000 ~/ windowSeconds) * windowSeconds;
lib/features/beacon/ephemeral_token_generator.dart:55:    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
lib/features/beacon/ephemeral_token_generator.dart-56-      (epochSeconds + windowSeconds) * 1000,
lib/features/beacon/ephemeral_token_generator.dart-57-    );
lib/features/beacon/ephemeral_token_generator.dart-58-
lib/features/beacon/ephemeral_token_generator.dart-59-    final userHash = _userHash();
lib/features/beacon/ephemeral_token_generator.dart-60-    final randomBytes = _secureRandomBytes(16);
lib/features/beacon/ephemeral_token_generator.dart-74-
lib/features/beacon/ephemeral_token_generator.dart-75-    return EphemeralToken(
lib/features/beacon/ephemeral_token_generator.dart-76-      token: token,
lib/features/beacon/ephemeral_token_generator.dart-77-      epochSeconds: epochSeconds,
lib/features/beacon/ephemeral_token_generator.dart-78-      issuedAt: now,
lib/features/beacon/ephemeral_token_generator.dart:79:      expiresAt: expiresAt,
lib/features/beacon/ephemeral_token_generator.dart-80-    );
lib/features/beacon/ephemeral_token_generator.dart-81-  }
lib/features/beacon/ephemeral_token_generator.dart-82-
lib/features/beacon/ephemeral_token_generator.dart-83-  /// Returns true if the previously issued token has expired (or is within
lib/features/beacon/ephemeral_token_generator.dart-84-  /// the refresh margin) and should be rotated.
lib/features/beacon/ephemeral_token_generator.dart-85-  bool shouldRotate(EphemeralToken? current,
lib/features/beacon/ephemeral_token_generator.dart-86-      {Duration grace = const Duration(minutes: 1)}) {
lib/features/beacon/ephemeral_token_generator.dart-87-    if (current == null) return true;
lib/features/beacon/ephemeral_token_generator.dart:88:    return _now().isAfter(current.expiresAt.subtract(grace));
lib/features/beacon/ephemeral_token_generator.dart-89-  }
lib/features/beacon/ephemeral_token_generator.dart-90-
lib/features/beacon/ephemeral_token_generator.dart-91-  List<int> _userHash() {
lib/features/beacon/ephemeral_token_generator.dart-92-    final h = Hmac(sha256, utf8.encode(_userIdSecret));
lib/features/beacon/ephemeral_token_generator.dart-93-    final digest = h.convert(utf8.encode('$_tokenVersion|$_userId'));
lib/features/beacon/ephemeral_token_generator.dart-115-class EphemeralToken {
lib/features/beacon/ephemeral_token_generator.dart-116-  const EphemeralToken({
lib/features/beacon/ephemeral_token_generator.dart-117-    required this.token,
lib/features/beacon/ephemeral_token_generator.dart-118-    required this.epochSeconds,
lib/features/beacon/ephemeral_token_generator.dart-119-    required this.issuedAt,
lib/features/beacon/ephemeral_token_generator.dart:120:    required this.expiresAt,
lib/features/beacon/ephemeral_token_generator.dart-121-  });
lib/features/beacon/ephemeral_token_generator.dart-122-
lib/features/beacon/ephemeral_token_generator.dart-123-  final String token;
lib/features/beacon/ephemeral_token_generator.dart-124-  final int epochSeconds;
lib/features/beacon/ephemeral_token_generator.dart-125-  final DateTime issuedAt;
lib/features/beacon/ephemeral_token_generator.dart:126:  final DateTime expiresAt;
lib/features/beacon/ephemeral_token_generator.dart-127-
lib/features/beacon/ephemeral_token_generator.dart:128:  bool get isExpired => DateTime.now().isAfter(expiresAt);
lib/features/beacon/ephemeral_token_generator.dart-129-}
supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql-61-  UPDATE public.beacon_token_batch b SET consumed_at = COALESCE(b.consumed_at, v_now)
supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql-62-  WHERE b.token = lower(p_token) AND b.user_id = v_uid
supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql-63-  RETURNING TRUE INTO v_in_batch;
supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql-64-  IF NOT COALESCE(v_in_batch, FALSE)
supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql:65:     AND COALESCE((SELECT value_num FROM public.app_settings WHERE key='enforce_batch_tokens'), 0) >= 1 THEN
supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql-66-    RAISE EXCEPTION 'Beacon token was not issued to this account' USING ERRCODE='22023';
supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql-67-  END IF;
supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql-68-
supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql-69-  SELECT last_claimed_at INTO v_last FROM public.token_claims WHERE user_id = v_uid;
supabase/migrations/0060_batch_token_preclaim.sql-127-  UPDATE public.beacon_token_batch b SET consumed_at = COALESCE(b.consumed_at, v_now)
supabase/migrations/0060_batch_token_preclaim.sql-128-  WHERE b.token = lower(p_token) AND b.user_id = v_uid
supabase/migrations/0060_batch_token_preclaim.sql-129-  RETURNING TRUE INTO v_in_batch;
supabase/migrations/0060_batch_token_preclaim.sql-130-  IF NOT COALESCE(v_in_batch, FALSE)
supabase/migrations/0060_batch_token_preclaim.sql:131:     AND COALESCE((SELECT value_num FROM public.app_settings WHERE key='enforce_batch_tokens'), 0) >= 1 THEN
supabase/migrations/0060_batch_token_preclaim.sql-132-    RAISE EXCEPTION 'Beacon token was not issued to this account' USING ERRCODE='22023';
supabase/migrations/0060_batch_token_preclaim.sql-133-  END IF;
supabase/migrations/0060_batch_token_preclaim.sql-134-
supabase/migrations/0060_batch_token_preclaim.sql-135-  SELECT last_claimed_at INTO v_last FROM public.token_claims WHERE user_id = v_uid;
supabase/migrations/0040_wire_consent_gates.sql-61-  UPDATE public.beacon_token_batch b SET consumed_at = COALESCE(b.consumed_at, v_now)
supabase/migrations/0040_wire_consent_gates.sql-62-  WHERE b.token = lower(p_token) AND b.user_id = v_uid
supabase/migrations/0040_wire_consent_gates.sql-63-  RETURNING TRUE INTO v_in_batch;
supabase/migrations/0040_wire_consent_gates.sql-64-  IF NOT COALESCE(v_in_batch, FALSE)
supabase/migrations/0040_wire_consent_gates.sql:65:     AND COALESCE((SELECT value_num FROM public.app_settings WHERE key='enforce_batch_tokens'), 0) >= 1 THEN
supabase/migrations/0040_wire_consent_gates.sql-66-    RAISE EXCEPTION 'Beacon token was not issued to this account' USING ERRCODE='22023';
supabase/migrations/0040_wire_consent_gates.sql-67-  END IF;
supabase/migrations/0040_wire_consent_gates.sql-68-
supabase/migrations/0040_wire_consent_gates.sql-69-  SELECT last_claimed_at INTO v_last FROM public.token_claims WHERE user_id = v_uid;
supabase/migrations/0034_device_attestation_scaffold.sql-8--- verifying, calls record_device_attestation() (service role) to record the
supabase/migrations/0034_device_attestation_scaffold.sql-9--- verdict; issue_token_batch then requires a fresh attestation when the
supabase/migrations/0034_device_attestation_scaffold.sql-10--- `require_attestation` flag is on.
supabase/migrations/0034_device_attestation_scaffold.sql-11---
supabase/migrations/0034_device_attestation_scaffold.sql:12:-- Non-breaking rollout, mirroring enforce_batch_tokens (step 2):
supabase/migrations/0034_device_attestation_scaffold.sql-13---   flag defaults 0 -> issue_token_batch behaves exactly as before. After the
supabase/migrations/0034_device_attestation_scaffold.sql-14---   verifier + attesting client ship to devices, flip to 1 (a data change, no
supabase/migrations/0034_device_attestation_scaffold.sql-15---   migration) to require attestation. Rollback: set it back to 0.
supabase/migrations/0034_device_attestation_scaffold.sql-16---
supabase/migrations/0039_consent_records.sql-28---     to show what someone consented to, when, and to which policy version.
supabase/migrations/0039_consent_records.sql-29---   * policy_version is recorded per grant, so a material policy change can
supabase/migrations/0039_consent_records.sql-30---     invalidate prior consent and force a re-ask.
supabase/migrations/0039_consent_records.sql-31---   * Enforcement sits behind app_settings.enforce_consent (default 0), the
supabase/migrations/0039_consent_records.sql:32:--     same non-breaking rollout pattern as enforce_batch_tokens and
supabase/migrations/0039_consent_records.sql-33---     require_attestation. Flipping it before the consent UI ships would lock
supabase/migrations/0039_consent_records.sql-34---     out every existing client.
supabase/migrations/0039_consent_records.sql-35-
supabase/migrations/0039_consent_records.sql-36-BEGIN;
supabase/migrations/0031_server_issued_token_batches.sql-14--- foundation for attesting issuance (App Attest / Play Integrity, step 3),
supabase/migrations/0031_server_issued_token_batches.sql-15--- detecting token fan-out abuse (step 4), and revocation.
supabase/migrations/0031_server_issued_token_batches.sql-16---
supabase/migrations/0031_server_issued_token_batches.sql-17--- Rollout is non-breaking: claim_token still accepts a self-minted token while
supabase/migrations/0031_server_issued_token_batches.sql:18:-- the flag `enforce_batch_tokens` is 0 (default). After the batch-aware client
supabase/migrations/0031_server_issued_token_batches.sql-19--- ships, flip the flag to 1 (a data change, no migration) to require batch
supabase/migrations/0031_server_issued_token_batches.sql-20--- membership. Observer-side offline scanning is unchanged (resolution is still
supabase/migrations/0031_server_issued_token_batches.sql-21--- via token_claim_history).
supabase/migrations/0031_server_issued_token_batches.sql-22-
supabase/migrations/0031_server_issued_token_batches.sql-23--- Enforcement flag — OFF by default so this deploy cannot break current clients.
supabase/migrations/0031_server_issued_token_batches.sql:24:INSERT INTO public.app_settings (key, value_num) VALUES ('enforce_batch_tokens', 0)
supabase/migrations/0031_server_issued_token_batches.sql-25-ON CONFLICT (key) DO NOTHING;
supabase/migrations/0031_server_issued_token_batches.sql-26-
supabase/migrations/0031_server_issued_token_batches.sql-27-CREATE TABLE IF NOT EXISTS public.beacon_token_batch (
supabase/migrations/0031_server_issued_token_batches.sql-28-  token       TEXT PRIMARY KEY,               -- opaque 32 hex chars (128-bit)
supabase/migrations/0031_server_issued_token_batches.sql-133-  UPDATE public.beacon_token_batch b SET consumed_at = COALESCE(b.consumed_at, v_now)
supabase/migrations/0031_server_issued_token_batches.sql-134-  WHERE b.token = lower(p_token) AND b.user_id = v_uid
supabase/migrations/0031_server_issued_token_batches.sql-135-  RETURNING TRUE INTO v_in_batch;
supabase/migrations/0031_server_issued_token_batches.sql-136-  IF NOT COALESCE(v_in_batch, FALSE)
supabase/migrations/0031_server_issued_token_batches.sql:137:     AND COALESCE((SELECT value_num FROM public.app_settings WHERE key='enforce_batch_tokens'), 0) >= 1 THEN
supabase/migrations/0031_server_issued_token_batches.sql-138-    RAISE EXCEPTION 'Beacon token was not issued to this account' USING ERRCODE='22023';
supabase/migrations/0031_server_issued_token_batches.sql-139-  END IF;
supabase/migrations/0031_server_issued_token_batches.sql-140-
supabase/migrations/0031_server_issued_token_batches.sql-141-  SELECT last_claimed_at INTO v_last FROM public.token_claims WHERE user_id = v_uid;
docs/SECURITY_HANDOFF.md-20-| 3 | App Attest / Play Integrity — server scaffold (table + gate + writer, flag OFF) | `migrations/0034` | 🟡 scaffold ✅; verifier+client TODO (Task C) |
docs/SECURITY_HANDOFF.md-21-| 5 | UWB `secure_ranged` confirmation | — | ⛔ TODO (Task D) |
docs/SECURITY_HANDOFF.md-22-
docs/SECURITY_HANDOFF.md-23-**Prod migration ledger:** through `0034`. **Enforcement flags (both OFF):**
docs/SECURITY_HANDOFF.md:24:`app_settings.enforce_batch_tokens = 0`, `app_settings.require_attestation = 0`.
docs/SECURITY_HANDOFF.md-25-
docs/SECURITY_HANDOFF.md-26-**Threat model wording (keep precise):** unilateral/API-only forgery is fixed;
docs/SECURITY_HANDOFF.md-27-`mutual_ble` is **not** relay-proof (a relay forwarding both tokens + spoofing GPS
docs/SECURITY_HANDOFF.md-28-still passes the distance veto — that's what Task C/D and the step-4 telemetry
docs/SECURITY_HANDOFF.md-59-out every old client** — they self-mint tokens `claim_token` will then reject.
docs/SECURITY_HANDOFF.md-60-
docs/SECURITY_HANDOFF.md-61-**Do:**
docs/SECURITY_HANDOFF.md-62-```sql
docs/SECURITY_HANDOFF.md:63:UPDATE public.app_settings SET value_num = 1 WHERE key = 'enforce_batch_tokens';
docs/SECURITY_HANDOFF.md-64-```
docs/SECURITY_HANDOFF.md-65-**Verify:** a self-minted (non-issued) token now fails `claim_token`:
docs/SECURITY_HANDOFF.md-66-```sql
docs/SECURITY_HANDOFF.md-67--- as an authenticated user with a valid session; expect 22023 "not issued to this account"
docs/SECURITY_HANDOFF.md-174-| Client token source | `lib/features/beacon/batch_token_source.dart` |
docs/SECURITY_HANDOFF.md-175-| Beacon service (advertise/scan/claim) | `lib/features/beacon/beacon_service.dart` |
docs/SECURITY_HANDOFF.md-176-| Full review + roadmap narrative | `docs/ADVERSARIAL_REVIEW_2026-07-15.md` |
docs/SECURITY_HANDOFF.md-177-
docs/SECURITY_HANDOFF.md:178:**Key flags (`public.app_settings`):** `enforce_batch_tokens` (Task A),
docs/SECURITY_HANDOFF.md-179-`encounter_reveal_delay_hours` (existing). Add `require_attestation` in Task C.
supabase/migrations/0048_gps_scope_and_retention.sql-68-  UPDATE public.beacon_token_batch b SET consumed_at = COALESCE(b.consumed_at, v_now)
supabase/migrations/0048_gps_scope_and_retention.sql-69-  WHERE b.token = lower(p_token) AND b.user_id = v_uid
supabase/migrations/0048_gps_scope_and_retention.sql-70-  RETURNING TRUE INTO v_in_batch;
supabase/migrations/0048_gps_scope_and_retention.sql-71-  IF NOT COALESCE(v_in_batch, FALSE)
supabase/migrations/0048_gps_scope_and_retention.sql:72:     AND COALESCE((SELECT value_num FROM public.app_settings WHERE key='enforce_batch_tokens'), 0) >= 1 THEN
supabase/migrations/0048_gps_scope_and_retention.sql-73-    RAISE EXCEPTION 'Beacon token was not issued to this account' USING ERRCODE='22023';
supabase/migrations/0048_gps_scope_and_retention.sql-74-  END IF;
supabase/migrations/0048_gps_scope_and_retention.sql-75-
supabase/migrations/0048_gps_scope_and_retention.sql-76-  SELECT last_claimed_at INTO v_last FROM public.token_claims WHERE user_id = v_uid;
docs/PRIVACY_COMPLIANCE_2026-07-19.md-283-
docs/PRIVACY_COMPLIANCE_2026-07-19.md-284-| Flag | Flip after | Gates |
docs/PRIVACY_COMPLIANCE_2026-07-19.md-285-|---|---|---|
docs/PRIVACY_COMPLIANCE_2026-07-19.md-286-| `enforce_consent` | consent UI live on devices **and** policy URLs resolve | `claim_token`, `record_sighting`, `record_location_ping`, `upsert_my_profile` |
docs/PRIVACY_COMPLIANCE_2026-07-19.md:287:| `enforce_batch_tokens` | batch-aware client live (commit `2fb33b8`) | `claim_token` |
docs/PRIVACY_COMPLIANCE_2026-07-19.md-288-| `require_attestation` | Edge Function verifier + client attestation call exist | `issue_token_batch` |
docs/PRIVACY_COMPLIANCE_2026-07-19.md-289-
docs/PRIVACY_COMPLIANCE_2026-07-19.md-290-Verify with:
docs/PRIVACY_COMPLIANCE_2026-07-19.md-291-```sql
docs/ADVERSARIAL_REVIEW_2026-07-15.md-45-> client fetches a day's batch and advertises the slot covering now
docs/ADVERSARIAL_REVIEW_2026-07-15.md-46-> (`BatchTokenSource`, replacing `EphemeralTokenGenerator`); it still claims per
docs/ADVERSARIAL_REVIEW_2026-07-15.md-47-> rotation so GPS/range stay dynamic, but the token VALUE is server-owned and
docs/ADVERSARIAL_REVIEW_2026-07-15.md-48-> unguessable. `claim_token` consumes the caller's batch token and, when
docs/ADVERSARIAL_REVIEW_2026-07-15.md:49:> `app_settings.enforce_batch_tokens >= 1`, rejects any token not issued to that
docs/ADVERSARIAL_REVIEW_2026-07-15.md-50-> account. Rollout is **non-breaking**: the flag defaults 0 so current clients
docs/ADVERSARIAL_REVIEW_2026-07-15.md-51-> keep working; flip it (a data change, no migration) once the batch-aware client
docs/ADVERSARIAL_REVIEW_2026-07-15.md-52-> has rolled out. Observer-side offline scanning is unchanged (resolution stays
docs/ADVERSARIAL_REVIEW_2026-07-15.md-53-> via `token_claim_history`). Validated on local Supabase + harness T9 (96
docs/ADVERSARIAL_REVIEW_2026-07-15.md-54-> distinct opaque tokens, idempotent re-issue, own-token consume, self-minted and
docs/ADVERSARIAL_REVIEW_2026-07-15.md-55-> cross-user tokens rejected under enforcement). Deployed to prod, ledgered 0031,
docs/ADVERSARIAL_REVIEW_2026-07-15.md-56-> flag OFF. **Cutover TODO:** after client rollout, `UPDATE app_settings SET
docs/ADVERSARIAL_REVIEW_2026-07-15.md:57:> value_num=1 WHERE key='enforce_batch_tokens';`.
docs/ADVERSARIAL_REVIEW_2026-07-15.md-58->
docs/ADVERSARIAL_REVIEW_2026-07-15.md-59-> **#6 step 4 — relay-abuse detection + response surface (0032–0033), SHIPPED.**
docs/ADVERSARIAL_REVIEW_2026-07-15.md-60-> `scan_relay_abuse()` (periodic, decoupled from the hot path) raises two signals
docs/ADVERSARIAL_REVIEW_2026-07-15.md-61-> into `beacon_abuse_flags`: `claim_teleport` (an account whose consecutive claims
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-85-`0060:149-159` — `ON CONFLICT (token) DO UPDATE` with **no `WHERE user_id = v_uid`**. The `COALESCE`
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-86-"guard" is dead code: `0060:117-118` rejects NULL coordinates, so `EXCLUDED.approx_lat` always wins.
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-87-Tokens are broadcast in plaintext over BLE. Neutralises the GPS veto — `correlate_encounter`
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-88-(`0053:179-182`) compares against coordinates the attacker just wrote. The batch-membership check that
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:89:would stop it sits behind `enforce_batch_tokens`, which is **0**.
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-90-
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-91-### C-SQL-3 🔴 `beacon_token_batch` has no scheduled purge — a permanent token→user_id map
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-92-`cleanup_ephemeral_data()` (latest `0059:477-580`) purges 9 tables; not this one. Joining it to
docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md-93-`rssi_samples` on the shared token yields a de-anonymised proximity graph. **Nuance accepted from Kimi:**
docs/research/2026-08-01-hardening/verified_findings_working.md-255-themselves, an attacker sets both sides equal and the distance is 0. The spatial half of the anti-forgery
docs/research/2026-08-01-hardening/verified_findings_working.md-256-envelope is removed, so a relay attack no longer needs to know where the victim is.
docs/research/2026-08-01-hardening/verified_findings_working.md-257-
docs/research/2026-08-01-hardening/verified_findings_working.md-258-**Flag gating:** the batch-membership check at `0060:127-133` would close this, but it only raises when
docs/research/2026-08-01-hardening/verified_findings_working.md:259:`enforce_batch_tokens >= 1`, and that flag is **currently 0**. So this is live.
docs/research/2026-08-01-hardening/verified_findings_working.md-260-
docs/research/2026-08-01-hardening/verified_findings_working.md-261-**Fix:** add `WHERE public.token_claim_history.user_id = v_uid` to the `DO UPDATE`, making a foreign-owned
docs/research/2026-08-01-hardening/verified_findings_working.md-262-conflict a silent no-op; and reject cross-owner claims even with the flag off.
docs/research/2026-08-01-hardening/verified_findings_working.md-263-
docs/research/2026-08-01-hardening/transcripts/kimi_audit_prompt.md-17-CRITICAL METHOD NOTE: migrations are cumulative and functions get redefined by later migrations. Before reporting anything about a function, find its LATEST definition and review that one. Verifying this every time is mandatory — it is the most common way this kind of review produces false findings.
docs/research/2026-08-01-hardening/transcripts/kimi_audit_prompt.md-18-
docs/research/2026-08-01-hardening/transcripts/kimi_audit_prompt.md-19-There is a local Postgres container `supabase_db_in-range` on port 54322 which may be running. If it is, you may query it READ-ONLY to check grants, policies, and function bodies. Never touch production.
docs/research/2026-08-01-hardening/transcripts/kimi_audit_prompt.md-20-
docs/research/2026-08-01-hardening/transcripts/kimi_audit_prompt.md:21:OUTPUT: a findings report, most severe first (Critical / High / Medium / Low). For each finding give: the file and line, the concrete exploit steps from the attacker's position, whether it is gated by one of the rollout flags (enforce_consent, enforce_batch_tokens, require_attestation are all currently 0/OFF), the root cause, a specific suggested fix, and your confidence (CERTAIN if you traced it in code, LIKELY, or SPECULATIVE). Try to refute each of your own findings before including it, and drop the ones you refute. A short list of real findings is far more valuable than a long list of speculation. End with a section stating plainly what mutual_ble IS and IS NOT proof of, in language we can paste into a design doc.
docs/research/2026-08-01-hardening/transcripts/consensus_prompt.md-12-Read both documents, then independently verify the findings against the actual code. Your job is specifically to find:
docs/research/2026-08-01-hardening/transcripts/consensus_prompt.md-13-
docs/research/2026-08-01-hardening/transcripts/consensus_prompt.md-14-1. FALSE POSITIVES. Any finding that is wrong, overstated, or already mitigated somewhere the reviewer did not look. The single most common way this codebase produces false findings is a SQL function that a LATER migration redefines — migrations are cumulative, so always locate the latest definition before judging a claim about a function. Check that discipline was actually applied. Also check whether a claimed-missing guard exists at a different layer (a caller, an RLS policy, an edge function, a client-side check).
docs/research/2026-08-01-hardening/transcripts/consensus_prompt.md-15-
docs/research/2026-08-01-hardening/transcripts/consensus_prompt.md:16:2. WRONG SEVERITY. Anything rated Critical that is really High or lower, or the reverse. Pay attention to whether a finding is actually reachable by the stated attacker, and whether a rollout flag gates it. The three flags enforce_consent, enforce_batch_tokens and require_attestation are all currently 0/OFF.
docs/research/2026-08-01-hardening/transcripts/consensus_prompt.md-17-
docs/research/2026-08-01-hardening/transcripts/consensus_prompt.md-18-3. MISSING FINDINGS. Anything materially dangerous the panel did not cover. Be brief here — one line each — this round is primarily about correctness of what is already written.
docs/research/2026-08-01-hardening/transcripts/consensus_prompt.md-19-
docs/research/2026-08-01-hardening/transcripts/consensus_prompt.md-20-4. WRONG OR INCOMPLETE FIXES. Any suggested fix that would not actually close the hole, would break something else, or misses a second call site that needs the same change.
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-94-  I should verify this one point myself since two agents disagree: check 0061's sweep and confirm correlate_encounter's grants in DB. Quick psql check.
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-95-
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-96-  Also Agent 0's F1 says the GPS veto is skipped when claim has NULL coords (batch preclaim path) — and Agent 1 C3 sybil farm says distance veto passes with identical coords. Consistent.
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-97-
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md:98:  Agent 2 M1 (claim_token squat/geo-poisoning) vs Agent 0's refuted "token squatting": Agent 0 refuted full squatting because 0060 pre-claims at fetch time — "a sniffer can only learn a token after it's already claimed". But Agent 2's M1 says: with enforce_batch_tokens OFF, if victim hasn't claimed yet (e.g., victim's client doesn't preclaim — Android path? or token issued but client fetches lazily), attacker can still claim first, full hijack; and even against preclaimed tokens, geo-poisoning works via COALESCE(EXCLUDED.approx_lat, existing). Agent 0's refutation assumed all clients preclaim; Agent 2 notes the attack shape changed but isn't dead. Both can be true: M1 is the more careful statement. The geo-poisoning part arming the 400m veto against the victim is a nice catch and consistent with Agent 0's F1 (NULL-coord claims skip veto — poisoning fills coords, enabling griefing).
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-99-
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-100-  Let me verify two things quickly in the DB (which lags — the scratch DB was created by agent 2; it said it left audit_scratch in place). I can query audit_scratch to check correlate_encounter grants and the claim_token ON CONFLICT clause. Actually simpler: read 0061 file and 0060 lines 145-160 myself. These are pivotal claims for my report. Let me do targeted reads:
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-101-
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-102-  1. Read 0061_close_wake_batch_privilege_hole.sql (6.6K, small) — verify sweep block.
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-138-
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-139-  HIGH:
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-140-  4. Relay-abuse telemetry blind (F2). CERTAIN.
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-141-  5. Decay reset via account recreate; X3 not implementable as described (H3). CERTAIN.
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md:142:  6. claim_token cross-user upsert geo-poisoning / squat while enforce_batch_tokens=0 (M1 agent2). CERTAIN, flag-gated.
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-143-  7. Concurrency: daily cap race / ON CONFLICT aborts (H2).
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-144-
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-145-  MEDIUM:
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-146-  8. Late-evidence window replay budget (F3) — 32–42 min replay life, no cross-direction binding. CERTAIN.
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-181-  4. A single-claims its token within 400 m of V. Reciprocity (0053:189-193) now holds → `encounters` row with `trust_level='mutual_ble'` (0053:208-209) plus a durable recurrence-pair bump (0053:202) — fake "we keep crossing paths" familiarity that reveal/recurrence ranking treats as the strongest evidence class below UWB.
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-182-
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-183-  Even when the veto *does* execute, it compares attacker-supplied observer coords against attacker-supplied-or-absent claim coords, caller-clamped radius (`LEAST(400, GREATEST(5, p_radius_meters))`, 0053:181) — a self-consistent liar passes it.
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-184-
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md:185:  **Flags:** none. Live today with all three flags at 0. `enforce_batch_tokens=1` does not help (preclaim exists regardless); `require_attestation=1` only raises account cost.
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-186-  **Root cause:** the protocol's only spatial check is conditional on data the normal locked-phone path deliberately never writes. The 0053 header's claim that "the GPS veto still bounds space… a replayed token confirms nothing from far away" is false for batch-claimed tokens.
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-187-  **Fix:** (a) when the claim row is NULL-coord, fall back to an **observer-vs-observer** veto (forward and reverse sightings' observer fixes must agree within the accuracy-aware radius — a relay fails this without also controlling the victim's GPS); (b) have `claim_token_batch` stamp coarse location (geohash-3, ~150 km) instead of NULL — enough for a cross-city veto, no meaningful privacy regression; (c) keep `mutual_ble` out of every trust/safety decision until `secure_ranged` (UWB) ships.
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-188-  **Confidence:** CERTAIN.
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-189-
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-215-  `claim_teleport` requires claims with `approx_lat IS NOT NULL` — batch-claimed (NULL-coord) rows never appear; and with 15-min claim rotation, even 270 km of linear spoofed movement between rotations is unflagged. `relay_geo` joins only location-bearing owner claims against observer coords the relay attacker chooses to keep consistent. In C1, **neither endpoint generates a row** — `beacon_abuse_flags` stays empty. Both heuristics are consistency checks over attacker-supplied coordinates; they flag the sloppy relay and structurally cannot see a careful one. Note 0053's header leans on this surface ("already tracked (docs/RELAY_ABUSE_RUNBOOK.md)") — overstated post-0060.
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-216-  **Fix:** add geometry that doesn't need owner claims — flag a token observed from two observer fixes >2 km apart inside one slot window, and run the teleport check over each *observer's* sighting geometry (catches emulator farms moving one account between relay endpoints). Keep the no-auto-restrict policy; just make the signal exist.
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-217-  **Confidence:** CERTAIN.
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-218-
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md:219:  ### H2 — `claim_token` cross-user upsert: token squat / geo-poisoning while `enforce_batch_tokens` = 0
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-220-  **File:** `supabase/migrations/0060_batch_token_preclaim.sql:127-133` (flag-gated membership check), `:149-159` (`ON CONFLICT (token) DO UPDATE` with no ownership guard).
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-221-  **Exploit (authenticated, verified account, sniffed token — verified EXECUTE for `authenticated`):**
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-222-  ```sql
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-223-  SELECT public.claim_token('<32-hex sniffed>', now() + interval '20 minutes',
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-224-                            40.7128, -74.0060, 'feet_60', 10);  -- 1 per 5 s
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-225-  ```
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-226-  - If the victim has not claimed the token (old client, non-preclaim path): attacker **inserts** the row with `user_id = attacker` → `record_sighting` resolves the victim's beacon to the attacker's account → encounter theft/impersonation.
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-227-  - If the victim batch-pre-claimed (NULL geo, the normal case): the update keeps `user_id = victim` but fills `approx_lat/lon` via `COALESCE(EXCLUDED.approx_lat, existing)` and unconditionally overwrites `valid_until`. The attacker plants arbitrary coordinates on the victim's claim, **arming** the 400 m veto against the victim (griefing/DoS of that slot's encounters) or shrinking its resolvable window.
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md:228:  **Flags:** fully closed by `enforce_batch_tokens = 1`; wide open today. Note 0060 *changed the attack shape* (hijack → geo-poisoning for updated clients) rather than removing it.
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-229-  **Fix:** flip the flag on client rollout (planned); independently, make the upsert no-op unless the existing row belongs to the caller: `ON CONFLICT (token) DO UPDATE SET ... WHERE public.token_claim_history.user_id = v_uid`.
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-230-  **Confidence:** CERTAIN.
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-231-
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-232-  ### H3 — Decay reset via delete/recreate works; X3 cannot be implemented as described
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1071-    75	`0060:149-159` — `ON CONFLICT (token) DO UPDATE` with **no `WHERE user_id = v_uid`**. The `COALESCE`
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1072-    76	"guard" is dead code: `0060:117-118` rejects NULL coordinates, so `EXCLUDED.approx_lat` always wins.
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1073-    77	Tokens are broadcast in plaintext over BLE. Neutralises the GPS veto — `correlate_encounter`
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1074-    78	(`0053:179-182`) compares against coordinates the attacker just wrote. The batch-membership check that
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md:1075:    79	would stop it sits behind `enforce_batch_tokens`, which is **0**.
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1076-    80	
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1077-    81	### C-SQL-3 🔴 `beacon_token_batch` has no scheduled purge — a permanent token→user_id map
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1078-    82	`cleanup_ephemeral_data()` (latest `0059:477-580`) purges 9 tables; not this one. Joining it to
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1079-    83	`rssi_samples` on the shared token yields a de-anonymised proximity graph. **Nuance accepted from Kimi:**
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-413-    71	`0060:149-159` — `ON CONFLICT (token) DO UPDATE` with **no `WHERE user_id = v_uid`**. The `COALESCE`
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-414-    72	"guard" is dead code: `0060:117-118` rejects NULL coordinates, so `EXCLUDED.approx_lat` always wins.
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-415-    73	Tokens are broadcast in plaintext over BLE. Neutralises the GPS veto — `correlate_encounter`
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-416-    74	(`0053:179-182`) compares against coordinates the attacker just wrote. The batch-membership check that
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md:417:    75	would stop it sits behind `enforce_batch_tokens`, which is **0**.
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-418-    76	
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-419-    77	### C-SQL-3 🔴 `beacon_token_batch` has no scheduled purge — a permanent token→user_id map
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-420-    78	`cleanup_ephemeral_data()` (latest `0059:477-580`) purges 9 tables; not this one. Joining it to
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-421-    79	`rssi_samples` on the shared token yields a de-anonymised proximity graph. **Nuance accepted from Kimi:**
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-2072-        result(FlutterMethodNotImplemented)
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-2073-      }
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-2074-
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-2075-exec
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md:2076:/bin/bash -lc "rtk rg -n -C 4 'CREATE OR REPLACE FUNCTION public\\.cleanup_ephemeral_data|beacon_token_batch|CREATE OR REPLACE FUNCTION public\\.claim_token\\(|ON CONFLICT \\(token\\)|CREATE OR REPLACE FUNCTION public\\.claim_token_batch|approx_lat IS NOT NULL|enforce_batch_tokens' supabase/migrations | tail -n 320" in /home/hazypiff/in-range
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-2077- succeeded in 0ms:
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-2078-76 matches in 29 files:
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-2079-
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-2080-supabase/migrations/0001_init.sql-235-
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-2225-supabase/migrations/0031_server_issued_token_batches.sql-14--- foundation for attesting issuance (App Attest / Play Integrity, step 3),
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-2226-supabase/migrations/0031_server_issued_token_batches.sql-15--- detecting token fan-out abuse (step 4), and revocation.
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-2227-supabase/migrations/0031_server_issued_token_batches.sql-16---
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-2228-supabase/migrations/0031_server_issued_token_batches.sql-17--- Rollout is non-breaking: claim_token still accepts a self-minted token while
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md:2229:supabase/migrations/0031_server_issued_token_batches.sql:18:-- the flag `enforce_batch_tokens` is 0 (default). After the batch-aware client
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-2230-supabase/migrations/0031_server_issued_token_batches.sql-19--- ships, flip the flag to 1 (a data change, no migration) to require batch
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-2231-supabase/migrations/0031_server_issued_token_batches.sql-20--- membership. Observer-side offline scanning is unchanged (resolution is still
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-2232-supabase/migrations/0031_server_issued_token_batches.sql-21--- via token_claim_history).
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-2233-supabase/migrations/0031_server_issued_token_batches.sql-22-
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-2273-supabase/migrations/0034_device_attestation_scaffold.sql-8--- verifying, calls record_device_attestation() (service role) to record the
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-2274-supabase/migrations/0034_device_attestation_scaffold.sql-9--- verdict; issue_token_batch then requires a fresh attestation when the
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-2275-supabase/migrations/0034_device_attestation_scaffold.sql-10--- `require_attestation` flag is on.
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-2276-supabase/migrations/0034_device_attestation_scaffold.sql-11---
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md:2277:supabase/migrations/0034_device_attestation_scaffold.sql:12:-- Non-breaking rollout, mirroring enforce_batch_tokens (step 2):
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-2278-supabase/migrations/0034_device_attestation_scaffold.sql-13---   flag defaults 0 -> issue_token_batch behaves exactly as before. After the
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-2279-supabase/migrations/0034_device_attestation_scaffold.sql-14---   verifier + attesting client ship to devices, flip to 1 (a data change, no
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-2280-supabase/migrations/0034_device_attestation_scaffold.sql-15---   migration) to require attestation. Rollback: set it back to 0.
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-2281-supabase/migrations/0034_device_attestation_scaffold.sql-16---
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-2525-  UPDATE public.beacon_token_batch b SET consumed_at = COALESCE(b.consumed_at, v_now)
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-2526-  WHERE b.token = lower(p_token) AND b.user_id = v_uid
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-2527-  RETURNING TRUE INTO v_in_batch;
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-2528-  IF NOT COALESCE(v_in_batch, FALSE)
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md:2529:     AND COALESCE((SELECT value_num FROM public.app_settings WHERE key='enforce_batch_tokens'), 0) >= 1 THEN
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-2530-    RAISE EXCEPTION 'Beacon token was not issued to this account' USING ERRCODE='22023';
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-2531-  END IF;
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-2532-
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm.md-2533-  SELECT last_claimed_at INTO v_last FROM public.token_claims WHERE user_id = v_uid;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-24-Read both documents, then independently verify the findings against the actual code. Your job is specifically to find:
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-25-
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-26-1. FALSE POSITIVES. Any finding that is wrong, overstated, or already mitigated somewhere the reviewer did not look. The single most common way this codebase produces false findings is a SQL function that a LATER migration redefines — migrations are cumulative, so always locate the latest definition before judging a claim about a function. Check that discipline was actually applied. Also check whether a claimed-missing guard exists at a different layer (a caller, an RLS policy, an edge function, a client-side check).
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-27-
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:28:2. WRONG SEVERITY. Anything rated Critical that is really High or lower, or the reverse. Pay attention to whether a finding is actually reachable by the stated attacker, and whether a rollout flag gates it. The three flags enforce_consent, enforce_batch_tokens and require_attestation are all currently 0/OFF.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-29-
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30-3. MISSING FINDINGS. Anything materially dangerous the panel did not cover. Be brief here — one line each — this round is primarily about correctness of what is already written.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-31-
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-32-4. WRONG OR INCOMPLETE FIXES. Any suggested fix that would not actually close the hole, would break something else, or misses a second call site that needs the same change.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-1217-`0060:149-159` — `ON CONFLICT (token) DO UPDATE` with **no `WHERE user_id = v_uid`**. The `COALESCE`
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-1218-"guard" is dead code: `0060:117-118` rejects NULL coordinates, so `EXCLUDED.approx_lat` is always non-NULL
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-1219-and always wins. Tokens are broadcast in plaintext over BLE, so any modified client harvests them.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-1220-**Neutralises the GPS veto** — `correlate_encounter` (`0053:179-182`) compares against coordinates the
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:1221:attacker just wrote. Mitigating check is behind `enforce_batch_tokens`, which is **0**.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-1222-**Fix:** add `WHERE public.token_claim_history.user_id = v_uid` to the `DO UPDATE`.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-1223-
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-1224-### C-SQL-2 🔴 `correlate_miles_encounters` fabricates encounters from arbitrary GPS
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-1225-`0048:251-360`, reached via `record_location_ping` (`0019:1227`), granted to `authenticated`
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-1629-themselves, an attacker sets both sides equal and the distance is 0. The spatial half of the anti-forgery
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-1630-envelope is removed, so a relay attack no longer needs to know where the victim is.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-1631-
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-1632-**Flag gating:** the batch-membership check at `0060:127-133` would close this, but it only raises when
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:1633:`enforce_batch_tokens >= 1`, and that flag is **currently 0**. So this is live.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-1634-
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-1635-**Fix:** add `WHERE public.token_claim_history.user_id = v_uid` to the `DO UPDATE`, making a foreign-owned
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-1636-conflict a silent no-op; and reject cross-owner claims even with the flag off.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-1637-
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-2609-   127	  UPDATE public.beacon_token_batch b SET consumed_at = COALESCE(b.consumed_at, v_now)
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-2610-   128	  WHERE b.token = lower(p_token) AND b.user_id = v_uid
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-2611-   129	  RETURNING TRUE INTO v_in_batch;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-2612-   130	  IF NOT COALESCE(v_in_batch, FALSE)
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:2613:   131	     AND COALESCE((SELECT value_num FROM public.app_settings WHERE key='enforce_batch_tokens'), 0) >= 1 THEN
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-2614-   132	    RAISE EXCEPTION 'Beacon token was not issued to this account' USING ERRCODE='22023';
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-2615-   133	  END IF;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-2616-   134	
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-2617-   135	  SELECT last_claimed_at INTO v_last FROM public.token_claims WHERE user_id = v_uid;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9228-  2289	    // record_sighting's required lat/lon) but only REMOVES a record after a
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9229-  2290	    // successful send — so without this clause a strong early sighting sticks
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9230-
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9231-exec
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:9232:/bin/bash -lc 'rtk rg -n "enforce_consent|enforce_batch_tokens|require_attestation" supabase/migrations supabase/seed lib supabase/functions' in /home/hazypiff/in-range
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9233- succeeded in 0ms:
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9234-lib/app_root.dart:99:    // require_consent gates are the backstop once enforce_consent flips on).
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9235-supabase/migrations/0039_consent_records.sql:31:--   * Enforcement sits behind app_settings.enforce_consent (default 0), the
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:9236:supabase/migrations/0039_consent_records.sql:32:--     same non-breaking rollout pattern as enforce_batch_tokens and
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9237-supabase/migrations/0039_consent_records.sql:33:--     require_attestation. Flipping it before the consent UI ships would lock
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9238-supabase/migrations/0039_consent_records.sql:39:VALUES ('enforce_consent', 0)
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9239-supabase/migrations/0039_consent_records.sql:221:  IF COALESCE((SELECT value_num FROM public.app_settings WHERE key = 'enforce_consent'), 0) >= 1
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9240-supabase/migrations/0039_consent_records.sql:232:  'Gate helper. No-op until app_settings.enforce_consent = 1; flip only after the consent UI is live on real devices.';
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9241-supabase/migrations/0048_gps_scope_and_retention.sql:17:-- my_consent_satisfied() so enforce_consent=1 also blocks a never-consented
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9242-supabase/migrations/0048_gps_scope_and_retention.sql:45:  -- Consent gate (0040). No-op unless app_settings.enforce_consent = 1.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9243-supabase/migrations/0048_gps_scope_and_retention.sql:50:  -- is still granted. Explicit withdrawal denies regardless of enforce_consent.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:9244:supabase/migrations/0048_gps_scope_and_retention.sql:72:     AND COALESCE((SELECT value_num FROM public.app_settings WHERE key='enforce_batch_tokens'), 0) >= 1 THEN
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9245-supabase/migrations/0048_gps_scope_and_retention.sql:112:  -- Consent gate (0040). No-op unless app_settings.enforce_consent = 1.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9246-supabase/migrations/0048_gps_scope_and_retention.sql:281:  -- explicit withdrawal always, and (once enforce_consent=1) a never-consented
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9247-supabase/migrations/0048_gps_scope_and_retention.sql:399:  -- explicit withdrawal always; denies never-consented once enforce_consent=1).
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9248-supabase/migrations/0045_withdrawal_effectiveness.sql:7:-- no-oped on an explicit withdrawal while enforce_consent=0 — the rollout flag
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9257-supabase/migrations/0047_privilege_retention_consent.sql:48:-- 5. Storage upload must honor enforce_consent, not just explicit withdrawal.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9258-supabase/migrations/0047_privilege_retention_consent.sql:50:--    and (once enforce_consent=1) denied until positively granted.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9259-supabase/migrations/0047_privilege_retention_consent.sql:61:       COALESCE((SELECT value_num FROM public.app_settings WHERE key = 'enforce_consent'), 0) < 1
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9260-supabase/migrations/0034_device_attestation_scaffold.sql:10:-- `require_attestation` flag is on.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:9261:supabase/migrations/0034_device_attestation_scaffold.sql:12:-- Non-breaking rollout, mirroring enforce_batch_tokens (step 2):
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9262-supabase/migrations/0034_device_attestation_scaffold.sql:23:INSERT INTO public.app_settings (key, value_num) VALUES ('require_attestation', 0)
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9263-supabase/migrations/0034_device_attestation_scaffold.sql:91:  IF COALESCE((SELECT value_num FROM public.app_settings WHERE key='require_attestation'), 0) >= 1
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9264-supabase/migrations/0060_batch_token_preclaim.sql:104:  -- Consent gate (0040). No-op unless app_settings.enforce_consent = 1.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9265-supabase/migrations/0060_batch_token_preclaim.sql:109:  -- is still granted. Explicit withdrawal denies regardless of enforce_consent.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:9266:supabase/migrations/0060_batch_token_preclaim.sql:131:     AND COALESCE((SELECT value_num FROM public.app_settings WHERE key='enforce_batch_tokens'), 0) >= 1 THEN
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:9267:supabase/migrations/0031_server_issued_token_batches.sql:18:-- the flag `enforce_batch_tokens` is 0 (default). After the batch-aware client
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:9268:supabase/migrations/0031_server_issued_token_batches.sql:24:INSERT INTO public.app_settings (key, value_num) VALUES ('enforce_batch_tokens', 0)
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:9269:supabase/migrations/0031_server_issued_token_batches.sql:137:     AND COALESCE((SELECT value_num FROM public.app_settings WHERE key='enforce_batch_tokens'), 0) >= 1 THEN
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9270-supabase/migrations/0046_withdrawal_enforcement.sql:271:  -- Consent gate (0040). No-op unless app_settings.enforce_consent = 1.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9271-supabase/migrations/0040_wire_consent_gates.sql:3:-- Makes app_settings.enforce_consent actually mean something.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9272-supabase/migrations/0040_wire_consent_gates.sql:18:-- Still a no-op until enforce_consent = 1, which must stay 0 until the consent
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9273-supabase/migrations/0040_wire_consent_gates.sql:44:  -- Consent gate (0040). No-op unless app_settings.enforce_consent = 1.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:9274:supabase/migrations/0040_wire_consent_gates.sql:65:     AND COALESCE((SELECT value_num FROM public.app_settings WHERE key='enforce_batch_tokens'), 0) >= 1 THEN
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9275-supabase/migrations/0040_wire_consent_gates.sql:105:  -- Consent gate (0040). No-op unless app_settings.enforce_consent = 1.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9276-supabase/migrations/0040_wire_consent_gates.sql:175:  -- Consent gate (0040). No-op unless app_settings.enforce_consent = 1.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9277-
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9278-exec
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9485-supabase/migrations/0019_beta_security_hardening.sql:142:INSERT INTO public.app_settings (key, value_num)
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9486-supabase/migrations/0045_withdrawal_effectiveness.sql:69:  IF COALESCE((SELECT value_num FROM public.app_settings WHERE key = 'enforce_consent'), 0) >= 1
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9487-supabase/migrations/0045_withdrawal_effectiveness.sql:80:  'Gate helper. Explicit withdrawal denies unconditionally; never-asked users are gated only once app_settings.enforce_consent = 1.';
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9488-supabase/migrations/0060_batch_token_preclaim.sql:104:  -- Consent gate (0040). No-op unless app_settings.enforce_consent = 1.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:9489:supabase/migrations/0060_batch_token_preclaim.sql:131:     AND COALESCE((SELECT value_num FROM public.app_settings WHERE key='enforce_batch_tokens'), 0) >= 1 THEN
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9490-supabase/migrations/0040_wire_consent_gates.sql:3:-- Makes app_settings.enforce_consent actually mean something.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9491-supabase/migrations/0040_wire_consent_gates.sql:44:  -- Consent gate (0040). No-op unless app_settings.enforce_consent = 1.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:9492:supabase/migrations/0040_wire_consent_gates.sql:65:     AND COALESCE((SELECT value_num FROM public.app_settings WHERE key='enforce_batch_tokens'), 0) >= 1 THEN
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9493-supabase/migrations/0040_wire_consent_gates.sql:105:  -- Consent gate (0040). No-op unless app_settings.enforce_consent = 1.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9494-supabase/migrations/0040_wire_consent_gates.sql:175:  -- Consent gate (0040). No-op unless app_settings.enforce_consent = 1.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:9495:supabase/migrations/0031_server_issued_token_batches.sql:24:INSERT INTO public.app_settings (key, value_num) VALUES ('enforce_batch_tokens', 0)
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:9496:supabase/migrations/0031_server_issued_token_batches.sql:137:     AND COALESCE((SELECT value_num FROM public.app_settings WHERE key='enforce_batch_tokens'), 0) >= 1 THEN
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9497-supabase/migrations/0035_account_deletion_completeness.sql:40:INSERT INTO public.app_settings (key, value_num)
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9498-supabase/migrations/0039_consent_records.sql:31:--   * Enforcement sits behind app_settings.enforce_consent (default 0), the
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9499-supabase/migrations/0039_consent_records.sql:38:INSERT INTO public.app_settings (key, value_num)
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9500-supabase/migrations/0039_consent_records.sql:39:VALUES ('enforce_consent', 0)
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9501-supabase/migrations/0039_consent_records.sql:221:  IF COALESCE((SELECT value_num FROM public.app_settings WHERE key = 'enforce_consent'), 0) >= 1
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9502-supabase/migrations/0039_consent_records.sql:232:  'Gate helper. No-op until app_settings.enforce_consent = 1; flip only after the consent UI is live on real devices.';
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9503-supabase/migrations/0048_gps_scope_and_retention.sql:45:  -- Consent gate (0040). No-op unless app_settings.enforce_consent = 1.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:9504:supabase/migrations/0048_gps_scope_and_retention.sql:72:     AND COALESCE((SELECT value_num FROM public.app_settings WHERE key='enforce_batch_tokens'), 0) >= 1 THEN
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9505-supabase/migrations/0048_gps_scope_and_retention.sql:112:  -- Consent gate (0040). No-op unless app_settings.enforce_consent = 1.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9506-supabase/migrations/0034_device_attestation_scaffold.sql:23:INSERT INTO public.app_settings (key, value_num) VALUES ('require_attestation', 0)
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9507-supabase/migrations/0053_late_evidence_tolerance.sql:42:INSERT INTO public.app_settings (key, value_num)
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9508-supabase/migrations/0053_late_evidence_tolerance.sql:77:  -- Consent gate (0040). No-op unless app_settings.enforce_consent = 1.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9820-    14	-- foundation for attesting issuance (App Attest / Play Integrity, step 3),
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9821-    15	-- detecting token fan-out abuse (step 4), and revocation.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9822-    16	--
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9823-    17	-- Rollout is non-breaking: claim_token still accepts a self-minted token while
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:9824:    18	-- the flag `enforce_batch_tokens` is 0 (default). After the batch-aware client
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9825-    19	-- ships, flip the flag to 1 (a data change, no migration) to require batch
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9826-    20	-- membership. Observer-side offline scanning is unchanged (resolution is still
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9827-    21	-- via token_claim_history).
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9828-    22	
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9829-    23	-- Enforcement flag — OFF by default so this deploy cannot break current clients.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:9830:    24	INSERT INTO public.app_settings (key, value_num) VALUES ('enforce_batch_tokens', 0)
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9831-    25	ON CONFLICT (key) DO NOTHING;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9832-    26	
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9833-    27	CREATE TABLE IF NOT EXISTS public.beacon_token_batch (
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9834-    28	  token       TEXT PRIMARY KEY,               -- opaque 32 hex chars (128-bit)
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9939-   133	  UPDATE public.beacon_token_batch b SET consumed_at = COALESCE(b.consumed_at, v_now)
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9940-   134	  WHERE b.token = lower(p_token) AND b.user_id = v_uid
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9941-   135	  RETURNING TRUE INTO v_in_batch;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9942-   136	  IF NOT COALESCE(v_in_batch, FALSE)
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:9943:   137	     AND COALESCE((SELECT value_num FROM public.app_settings WHERE key='enforce_batch_tokens'), 0) >= 1 THEN
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9944-   138	    RAISE EXCEPTION 'Beacon token was not issued to this account' USING ERRCODE='22023';
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9945-   139	  END IF;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9946-   140	
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-9947-   141	  SELECT last_claimed_at INTO v_last FROM public.token_claims WHERE user_id = v_uid;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-16891-themselves, an attacker sets both sides equal and the distance is 0. The spatial half of the anti-forgery
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-16892-envelope is removed, so a relay attack no longer needs to know where the victim is.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-16893-
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-16894-**Flag gating:** the batch-membership check at `0060:127-133` would close this, but it only raises when
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:16895:`enforce_batch_tokens >= 1`, and that flag is **currently 0**. So this is live.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-16896-
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-16897-**Fix:** add `WHERE public.token_claim_history.user_id = v_uid` to the `DO UPDATE`, making a foreign-owned
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-16898-conflict a silent no-op; and reject cross-owner claims even with the flag off.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-16899-
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-17198-docs/ADVERSARIAL_REVIEW_2026-07-15.md-44-> in the app (which was cosmetic — anyone with the binary could compute it). ...
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-17199-docs/ADVERSARIAL_REVIEW_2026-07-15.md-45-> client fetches a day's batch and advertises the slot covering now
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-17200-docs/ADVERSARIAL_REVIEW_2026-07-15.md-46-> (`BatchTokenSource`, replacing `EphemeralTokenGenerator`); it still claims per
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-17201-docs/ADVERSARIAL_REVIEW_2026-07-15.md-47-> rotation so GPS/range stay dynamic, but the token VALUE is server-owned and
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:17202:docs/ADVERSARIAL_REVIEW_2026-07-15.md-49-> `app_settings.enforce_batch_tokens >= 1`, rejects any token not issued to that
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-17203-docs/ADVERSARIAL_REVIEW_2026-07-15.md-50-> account. Rollout is **non-breaking**: the flag defaults 0 so current clients
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-17204-docs/ADVERSARIAL_REVIEW_2026-07-15.md-51-> keep working; flip it (a data change, no migration) once the batch-aware cl...
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-17205-docs/ADVERSARIAL_REVIEW_2026-07-15.md-52-> has rolled out. Observer-side offline scanning is unchanged (resolution stays
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-17206-  +26 more in docs/ADVERSARIAL_REVIEW_2026-07-15.md
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-17298-docs/SECURITY_HANDOFF.md:59:out every old client** — they self-mint tokens `claim_token` will then reject.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-17299-docs/SECURITY_HANDOFF.md-60-
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-17300-docs/SECURITY_HANDOFF.md-61-**Do:**
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-17301-docs/SECURITY_HANDOFF.md-62-```sql
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:17302:docs/SECURITY_HANDOFF.md-63-UPDATE public.app_settings SET value_num = 1 WHERE key = 'enforce_batch_tokens';
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-17303-docs/SECURITY_HANDOFF.md-64-```
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-17304-docs/SECURITY_HANDOFF.md:65:**Verify:** a self-minted (non-issued) token now fails `claim_token`:
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-17305-docs/SECURITY_HANDOFF.md-66-```sql
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-17306-docs/SECURITY_HANDOFF.md-67--- as an authenticated user with a valid session; expect 22023 "not issued to...
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-18175-    56	`0060:149-159` — `ON CONFLICT (token) DO UPDATE` with **no `WHERE user_id = v_uid`**. The `COALESCE`
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-18176-    57	"guard" is dead code: `0060:117-118` rejects NULL coordinates, so `EXCLUDED.approx_lat` is always non-NULL
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-18177-    58	and always wins. Tokens are broadcast in plaintext over BLE, so any modified client harvests them.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-18178-    59	**Neutralises the GPS veto** — `correlate_encounter` (`0053:179-182`) compares against coordinates the
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:18179:    60	attacker just wrote. Mitigating check is behind `enforce_batch_tokens`, which is **0**.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-18180-    61	**Fix:** add `WHERE public.token_claim_history.user_id = v_uid` to the `DO UPDATE`.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-18181-    62	
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-18182-    63	### C-SQL-2 🔴 `correlate_miles_encounters` fabricates encounters from arbitrary GPS
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-18183-    64	`0048:251-360`, reached via `record_location_ping` (`0019:1227`), granted to `authenticated`
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23699-supabase/migrations/0060_batch_token_preclaim.sql:127:  UPDATE public.beacon_token_batch b SET consumed_at = COALESCE(b.consumed_at, v_now)
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23700-supabase/migrations/0060_batch_token_preclaim.sql-128-  WHERE b.token = lower(p_token) AND b.user_id = v_uid
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23701-supabase/migrations/0060_batch_token_preclaim.sql-129-  RETURNING TRUE INTO v_in_batch;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23702-supabase/migrations/0060_batch_token_preclaim.sql-130-  IF NOT COALESCE(v_in_batch, FALSE)
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:23703:supabase/migrations/0060_batch_token_preclaim.sql-131-     AND COALESCE((SELECT value_num FROM public.app_settings WHERE key='enforce_batch_tokens'), 0) >= 1 THEN
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23704-supabase/migrations/0060_batch_token_preclaim.sql-132-    RAISE EXCEPTION 'Beacon token was not issued to this account' USING ERRCODE='22023';
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23705---
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23706-supabase/migrations/0059_proximity_wake_producer.sql-235-
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23707-supabase/migrations/0059_proximity_wake_producer.sql-236-  DELETE FROM public.location_pings          WHERE user_id          = p_uid;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23723-supabase/migrations/0040_wire_consent_gates.sql:61:  UPDATE public.beacon_token_batch b SET consumed_at = COALESCE(b.consumed_at, v_now)
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23724-supabase/migrations/0040_wire_consent_gates.sql-62-  WHERE b.token = lower(p_token) AND b.user_id = v_uid
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23725-supabase/migrations/0040_wire_consent_gates.sql-63-  RETURNING TRUE INTO v_in_batch;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23726-supabase/migrations/0040_wire_consent_gates.sql-64-  IF NOT COALESCE(v_in_batch, FALSE)
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:23727:supabase/migrations/0040_wire_consent_gates.sql-65-     AND COALESCE((SELECT value_num FROM public.app_settings WHERE key='enforce_batch_tokens'), 0) >= 1 THEN
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23728-supabase/migrations/0040_wire_consent_gates.sql-66-    RAISE EXCEPTION 'Beacon token was not issued to this account' USING ERRCODE='22023';
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23729---
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23730-supabase/migrations/0031_server_issued_token_batches.sql-22-
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23731-supabase/migrations/0031_server_issued_token_batches.sql-23--- Enforcement flag — OFF by default so this deploy cannot break current clients.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:23732:supabase/migrations/0031_server_issued_token_batches.sql-24-INSERT INTO public.app_settings (key, value_num) VALUES ('enforce_batch_tokens', 0)
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23733-supabase/migrations/0031_server_issued_token_batches.sql-25-ON CONFLICT (key) DO NOTHING;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23734-supabase/migrations/0031_server_issued_token_batches.sql-26-
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23735-supabase/migrations/0031_server_issued_token_batches.sql:27:CREATE TABLE IF NOT EXISTS public.beacon_token_batch (
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23736-supabase/migrations/0031_server_issued_token_batches.sql-28-  token       TEXT PRIMARY KEY,               -- opaque 32 hex chars (128-bit)
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23797-supabase/migrations/0031_server_issued_token_batches.sql:133:  UPDATE public.beacon_token_batch b SET consumed_at = COALESCE(b.consumed_at, v_now)
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23798-supabase/migrations/0031_server_issued_token_batches.sql-134-  WHERE b.token = lower(p_token) AND b.user_id = v_uid
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23799-supabase/migrations/0031_server_issued_token_batches.sql-135-  RETURNING TRUE INTO v_in_batch;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23800-supabase/migrations/0031_server_issued_token_batches.sql-136-  IF NOT COALESCE(v_in_batch, FALSE)
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:23801:supabase/migrations/0031_server_issued_token_batches.sql-137-     AND COALESCE((SELECT value_num FROM public.app_settings WHERE key='enforce_batch_tokens'), 0) >= 1 THEN
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23802-supabase/migrations/0031_server_issued_token_batches.sql-138-    RAISE EXCEPTION 'Beacon token was not issued to this account' USING ERRCODE='22023';
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23803---
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23804-supabase/migrations/0035_account_deletion_completeness.sql-119-  -- Proximity + beacon telemetry: no reason to retain any of it.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23805-supabase/migrations/0035_account_deletion_completeness.sql-120-  DELETE FROM public.location_pings      WHERE user_id          = p_uid;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23857-supabase/migrations/0048_gps_scope_and_retention.sql:68:  UPDATE public.beacon_token_batch b SET consumed_at = COALESCE(b.consumed_at, v_now)
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23858-supabase/migrations/0048_gps_scope_and_retention.sql-69-  WHERE b.token = lower(p_token) AND b.user_id = v_uid
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23859-supabase/migrations/0048_gps_scope_and_retention.sql-70-  RETURNING TRUE INTO v_in_batch;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23860-supabase/migrations/0048_gps_scope_and_retention.sql-71-  IF NOT COALESCE(v_in_batch, FALSE)
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:23861:supabase/migrations/0048_gps_scope_and_retention.sql-72-     AND COALESCE((SELECT value_num FROM public.app_settings WHERE key='enforce_batch_tokens'), 0) >= 1 THEN
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23862-supabase/migrations/0048_gps_scope_and_retention.sql-73-    RAISE EXCEPTION 'Beacon token was not issued to this account' USING ERRCODE='22023';
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23863---
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23864-supabase/migrations/0034_device_attestation_scaffold.sql-100-    RAISE EXCEPTION 'Batch day out of range' USING ERRCODE='22023'; END IF;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23865-supabase/migrations/0034_device_attestation_scaffold.sql-101-
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23989-   127	  UPDATE public.beacon_token_batch b SET consumed_at = COALESCE(b.consumed_at, v_now)
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23990-   128	  WHERE b.token = lower(p_token) AND b.user_id = v_uid
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23991-   129	  RETURNING TRUE INTO v_in_batch;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23992-   130	  IF NOT COALESCE(v_in_batch, FALSE)
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:23993:   131	     AND COALESCE((SELECT value_num FROM public.app_settings WHERE key='enforce_batch_tokens'), 0) >= 1 THEN
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23994-   132	    RAISE EXCEPTION 'Beacon token was not issued to this account' USING ERRCODE='22023';
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23995-   133	  END IF;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23996-   134	
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-23997-   135	  SELECT last_claimed_at INTO v_last FROM public.token_claims WHERE user_id = v_uid;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-27382-`0060:149-159` — `ON CONFLICT (token) DO UPDATE` with **no `WHERE user_id = v_uid`**. The `COALESCE`
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-27383-"guard" is dead code: `0060:117-118` rejects NULL coordinates, so `EXCLUDED.approx_lat` is always non-NULL
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-27384-and always wins. Tokens are broadcast in plaintext over BLE, so any modified client harvests them.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-27385-**Neutralises the GPS veto** — `correlate_encounter` (`0053:179-182`) compares against coordinates the
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:27386:attacker just wrote. Mitigating check is behind `enforce_batch_tokens`, which is **0**.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-27387-**Fix:** add `WHERE public.token_claim_history.user_id = v_uid` to the `DO UPDATE`.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-27388-
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-27389-### C-SQL-2 🔴 `correlate_miles_encounters` fabricates encounters from arbitrary GPS
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-27390-`0048:251-360`, reached via `record_location_ping` (`0019:1227`), granted to `authenticated`
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-27786-themselves, an attacker sets both sides equal and the distance is 0. The spatial half of the anti-forgery
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-27787-envelope is removed, so a relay attack no longer needs to know where the victim is.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-27788-
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-27789-**Flag gating:** the batch-membership check at `0060:127-133` would close this, but it only raises when
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:27790:`enforce_batch_tokens >= 1`, and that flag is **currently 0**. So this is live.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-27791-
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-27792-**Fix:** add `WHERE public.token_claim_history.user_id = v_uid` to the `DO UPDATE`, making a foreign-owned
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-27793-conflict a silent no-op; and reject cross-owner claims even with the flag off.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-27794-
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28299-   127	  UPDATE public.beacon_token_batch b SET consumed_at = COALESCE(b.consumed_at, v_now)
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28300-   128	  WHERE b.token = lower(p_token) AND b.user_id = v_uid
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28301-   129	  RETURNING TRUE INTO v_in_batch;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28302-   130	  IF NOT COALESCE(v_in_batch, FALSE)
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:28303:   131	     AND COALESCE((SELECT value_num FROM public.app_settings WHERE key='enforce_batch_tokens'), 0) >= 1 THEN
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28304-   132	    RAISE EXCEPTION 'Beacon token was not issued to this account' USING ERRCODE='22023';
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28305-   133	  END IF;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28306-   134	
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28307-   135	  SELECT last_claimed_at INTO v_last FROM public.token_claims WHERE user_id = v_uid;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28692-    20	-- membership. Observer-side offline scanning is unchanged (resolution is still
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28693-    21	-- via token_claim_history).
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28694-    22	
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28695-    23	-- Enforcement flag — OFF by default so this deploy cannot break current clients.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:28696:    24	INSERT INTO public.app_settings (key, value_num) VALUES ('enforce_batch_tokens', 0)
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28697-    25	ON CONFLICT (key) DO NOTHING;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28698-    26	
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28699-    27	CREATE TABLE IF NOT EXISTS public.beacon_token_batch (
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28700-    28	  token       TEXT PRIMARY KEY,               -- opaque 32 hex chars (128-bit)
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-29055-    56	`0060:149-159` — `ON CONFLICT (token) DO UPDATE` with **no `WHERE user_id = v_uid`**. The `COALESCE`
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-29056-    57	"guard" is dead code: `0060:117-118` rejects NULL coordinates, so `EXCLUDED.approx_lat` is always non-NULL
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-29057-    58	and always wins. Tokens are broadcast in plaintext over BLE, so any modified client harvests them.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-29058-    59	**Neutralises the GPS veto** — `correlate_encounter` (`0053:179-182`) compares against coordinates the
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:29059:    60	attacker just wrote. Mitigating check is behind `enforce_batch_tokens`, which is **0**.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-29060-    61	**Fix:** add `WHERE public.token_claim_history.user_id = v_uid` to the `DO UPDATE`.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-29061-    62	
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-29062-    63	### C-SQL-2 🔴 `correlate_miles_encounters` fabricates encounters from arbitrary GPS
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-29063-    64	`0048:251-360`, reached via `record_location_ping` (`0019:1227`), granted to `authenticated`
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30321-    47	      That table is granted to PUBLIC by Supabase (`supabase_admin`) and cannot
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30322-    48	      be revoked as `postgres`, but it is NOT PostgREST-exposed and `anon`/
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30323-
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30324-exec
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:30325:/bin/bash -lc 'rtk rg -n "attestation|require_attestation|enforce_consent|enforce_batch_tokens" docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md docs/research/2026-08-01-hardening/verified_findings_working.md supabase/migrations' in /home/hazypiff/in-range
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30326- succeeded in 0ms:
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30327-71 matches in 18 files:
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30328-
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:30329:docs/.../2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md:60:attacker just wrote. Mitigating check is behind `enforce_batch_tokens`, which...
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:30330:docs/.../2026-08-01-hardening/verified_findings_working.md:230:`enforce_batch_tokens >= 1`, and that flag is **currently 0**. So this is live.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:30331:supabase/migrations/0031_server_issued_token_batches.sql:18:-- the flag `enforce_batch_tokens` is 0 (default). After the batch-aware client
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30332-supabase/migrations/0031_server_issued_token_batches.sql:24:INSERT INTO public.app_settings (key, value_num) VALUES ('enforce_batch_token...
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30333-supabase/migrations/0031_server_issued_token_batches.sql:137:AND COALESCE((SELECT value_num FROM public.app_settings WHERE key='enforce_ba...
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30334-supabase/migrations/0034_device_attestation_scaffold.sql:7:-- attestation verification needs platform SDK/keys). That Edge Function, after
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30335-supabase/migrations/0034_device_attestation_scaffold.sql:8:-- verifying, calls record_device_attestation() (service role) to record the
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30336-supabase/migrations/0034_device_attestation_scaffold.sql:9:-- verdict; issue_token_batch then requires a fresh attestation when the
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30337-supabase/migrations/0034_device_attestation_scaffold.sql:10:-- `require_attestation` flag is on.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:30338:supabase/migrations/0034_device_attestation_scaffold.sql:12:-- Non-breaking rollout, mirroring enforce_batch_tokens (step 2):
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30339-supabase/migrations/0034_device_attestation_scaffold.sql:15:--   migration) to require attestation. Rollback: set it back to 0.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30340-supabase/migrations/0034_device_attestation_scaffold.sql:23:INSERT INTO public.app_settings (key, value_num) VALUES ('require_attestation...
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30341-supabase/migrations/0034_device_attestation_scaffold.sql:26:CREATE TABLE IF NOT EXISTS public.device_attestations (
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30342-supabase/migrations/0034_device_attestation_scaffold.sql:31:expires_at  TIMESTAMPTZ NOT NULL,          -- attestation freshness window
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30349-  +10 more in supabase/migrations/0034_device_attestation_scaffold.sql
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30350-supabase/migrations/0035_account_deletion_completeness.sql:125:DELETE FROM public.device_attestations WHERE user_id          = p_uid;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30351-supabase/migrations/0037_legal_hold.sql:173:DELETE FROM public.device_attestations WHERE user_id          = p_uid;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30352-supabase/migrations/0039_consent_records.sql:31:--   * Enforcement sits behind app_settings.enforce_consent (default 0), the
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:30353:supabase/migrations/0039_consent_records.sql:32:--     same non-breaking rollout pattern as enforce_batch_tokens and
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30354-supabase/migrations/0039_consent_records.sql:33:--     require_attestation. Flipping it before the consent UI ships would lock
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30355-supabase/migrations/0039_consent_records.sql:39:VALUES ('enforce_consent', 0)
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30356-supabase/migrations/0039_consent_records.sql:221:IF COALESCE((SELECT value_num FROM public.app_settings WHERE key = 'enforce_c...
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30357-supabase/migrations/0039_consent_records.sql:232:'Gate helper. No-op until app_settings.enforce_consent = 1; flip only after t...
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30675-   226	themselves, an attacker sets both sides equal and the distance is 0. The spatial half of the anti-forgery
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30676-   227	envelope is removed, so a relay attack no longer needs to know where the victim is.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30677-   228	
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30678-   229	**Flag gating:** the batch-membership check at `0060:127-133` would close this, but it only raises when
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:30679:   230	`enforce_batch_tokens >= 1`, and that flag is **currently 0**. So this is live.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30680-   231	
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30681-   232	**Fix:** add `WHERE public.token_claim_history.user_id = v_uid` to the `DO UPDATE`, making a foreign-owned
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30682-   233	conflict a silent no-op; and reject cross-owner claims even with the flag off.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30683-   234	
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30924-  **Confidence:** Certain on source and inference; I accepted the recorded production responses and did not send any production request.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30925-
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30926-- **C-SQL-1 — severity and incomplete fix.**  
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30927-  **Report:** Critical; adding an owner `WHERE` to the history conflict closes it.  
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:30928:  **True:** The overwrite is real and `enforce_batch_tokens=0` makes it reachable, but a forged BLE encounter still requires reciprocal evidence at [0053:189](/home/hazypiff/in-range/supabase/migrations/0053_late_evidence_tolerance.sql:189). I rate it High, not Critical. More importantly, the proposed fix is incomplete: `token_claims` is mutated first at [0060:139](/home/hazypiff/in-range/supabase/migrations/0060_batch_token_preclaim.sql:139), before the vulnerable history conflict at [0060:149](/home/hazypiff/in-range/supabase/migrations/0060_batch_token_preclaim.sql:149). A conflict `WHERE` can silently skip the history update while leaving the attacker’s live token row poisoned. Foreign history ownership and existing batch ownership must be locked and rejected before either insert.  
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30929-  **Confidence:** Certain.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30930-
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30931-- **C-SQL-2 — obsolete caller citation and overstated attacker class.**  
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30932-  **Report:** Reached through the 0019 definition of `record_location_ping`; exploitable by any authenticated user.  
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-31023-  **Confidence:** Certain on source and inference; I accepted the recorded production responses and did not send any production request.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-31024-
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-31025-- **C-SQL-1 — severity and incomplete fix.**  
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-31026-  **Report:** Critical; adding an owner `WHERE` to the history conflict closes it.  
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:31027:  **True:** The overwrite is real and `enforce_batch_tokens=0` makes it reachable, but a forged BLE encounter still requires reciprocal evidence at [0053:189](/home/hazypiff/in-range/supabase/migrations/0053_late_evidence_tolerance.sql:189). I rate it High, not Critical. More importantly, the proposed fix is incomplete: `token_claims` is mutated first at [0060:139](/home/hazypiff/in-range/supabase/migrations/0060_batch_token_preclaim.sql:139), before the vulnerable history conflict at [0060:149](/home/hazypiff/in-range/supabase/migrations/0060_batch_token_preclaim.sql:149). A conflict `WHERE` can silently skip the history update while leaving the attacker’s live token row poisoned. Foreign history ownership and existing batch ownership must be locked and rejected before either insert.  
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-31028-  **Confidence:** Certain.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-31029-
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-31030-- **C-SQL-2 — obsolete caller citation and overstated attacker class.**  
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-31031-  **Report:** Reached through the 0019 definition of `record_location_ping`; exploitable by any authenticated user.  

exec
/bin/bash -lc "nl -ba docs/research/2026-08-01-hardening/verified_findings_working.md | sed -n '205,245p'
nl -ba docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md | sed -n '30910,30945p'
rtk rg -n -C 8 \"legal hold|GREATEST\\(|observer_accuracy|v_rev_lat|fallback|silent no-op|foreign history\" docs/research/2026-08-01-hardening | head -n 500" in /home/hazypiff/in-range
 succeeded in 0ms:
   205	   moderation step. An anonymous caller can drive that queue.
   206	2. `send-push` drains `notification_outbox` and returns internal row ids and statuses to an anonymous
   207	   caller. It is currently `dry_run` only because FCM credentials are unset — the moment they are
   208	   configured, an anonymous caller can trigger real push delivery to users.
   209	3. Both leak operational internals (row counts, ids, per-row reasons) to unauthenticated callers.
   210	
   211	**Immediate remediation (do this before any other fix in this round):**
   212	`supabase functions deploy send-push photo-review` (and set `verify_jwt=false` for both, plus add a
   213	missing `[functions.proximity-wake]` block, so the `sb_secret_` service key is accepted — see H-CFG-1).
   214	Until redeployed, consider disabling both functions in the dashboard.
   215	
   216	**Confidence:** CERTAIN — probed production directly, three independent request shapes.
   217	
   218	**⚠️ SIDE EFFECT I CAUSED, DISCLOSED:** my first probe was an unauthenticated POST to `send-push`.
   219	The deployed function processed 19 `notification_outbox` rows and marked them
   220	`status='skipped', last_error='no_device_token'` — a terminal state (`send-push/index.ts:315-324`).
   221	Those 19 rows had no registered device token, so they were undeliverable regardless and no user lost a
   222	notification they would otherwise have received. But production state WAS changed by the probe, and it
   223	demonstrates the finding: any anonymous caller can burn the outbox this way.
   224	
   225	---
   226	
   227	## 🔴 C-SQL-1 — `claim_token` lets any authenticated user overwrite ANOTHER user's `token_claim_history` row
   228	
   229	**Severity:** Critical (live today — the mitigating check is behind a flag that is OFF)
   230	**Latest definition:** `supabase/migrations/0060_batch_token_preclaim.sql:149-159` (verified: `claim_token`
   231	is NOT redefined in any later migration).
   232	
   233	**Verified code:**
   234	```sql
   235	INSERT INTO public.token_claim_history (token, user_id, ...)
   236	VALUES (lower(p_token), v_uid, ...)
   237	ON CONFLICT (token) DO UPDATE SET
   238	  valid_until = EXCLUDED.valid_until,
   239	  approx_lat  = COALESCE(EXCLUDED.approx_lat, public.token_claim_history.approx_lat),
   240	  ...
   241	```
   242	There is **no `WHERE token_claim_history.user_id = v_uid`** on the `DO UPDATE`. The conflict target is the
   243	token alone, but the security-relevant key is (token, owner).
   244	
   245	**The `COALESCE` guard is dead code.** Its comment claims it will "never blank out a fix an earlier claim
 30910	/bin/bash -lc "find docs -type f -iname '*gamification*' -print" in /home/hazypiff/in-range
 30911	 succeeded in 0ms:
 30912	docs/GAMIFICATION_SOCIAL_BLUEPRINT_2026-07-31_JOINT.md
 30913	
 30914	codex
 30915	CONSENSUS: AGREED WITH CORRECTIONS — sound, but the items below must be fixed first.
 30916	
 30917	The central conclusion survives, including C-PROD-1. I would retain only C-PROD-1 and C-SQL-2 as current Criticals; the other Criticals are real defects but are High given their reachability, remaining controls, or OFF rollout flags.
 30918	
 30919	## Required corrections
 30920	
 30921	- **C-PROD-1 — impact wording.**  
 30922	  **Report:** The deployed functions lack authentication; `send-push` is harmless while FCM credentials are unset.  
 30923	  **True:** The authentication inference is sound. The shared gate returns 405 before all other work on non-POST requests at [service_auth.ts:6](/home/hazypiff/in-range/supabase/functions/_shared/service_auth.ts:6), and both functions invoke it before database work at [photo-review/index.ts:103](/home/hazypiff/in-range/supabase/functions/photo-review/index.ts:103) and [send-push/index.ts:182](/home/hazypiff/in-range/supabase/functions/send-push/index.ts:182). Therefore the reported unauthenticated GET 200 cannot come from the current gated source. Current `photo-review` also permits `auto_approve` only on localhost at [index.ts:107](/home/hazypiff/in-range/supabase/functions/photo-review/index.ts:107), independently corroborating deploy drift. However, `send-push` is not harmless without FCM: it terminally marks claimed rows `skipped` in the no-token and dry-run branches at [send-push/index.ts:314](/home/hazypiff/in-range/supabase/functions/send-push/index.ts:314) and [send-push/index.ts:339](/home/hazypiff/in-range/supabase/functions/send-push/index.ts:339). Anonymous callers can burn the outbox.  
 30924	  **Confidence:** Certain on source and inference; I accepted the recorded production responses and did not send any production request.
 30925	
 30926	- **C-SQL-1 — severity and incomplete fix.**  
 30927	  **Report:** Critical; adding an owner `WHERE` to the history conflict closes it.  
 30928	  **True:** The overwrite is real and `enforce_batch_tokens=0` makes it reachable, but a forged BLE encounter still requires reciprocal evidence at [0053:189](/home/hazypiff/in-range/supabase/migrations/0053_late_evidence_tolerance.sql:189). I rate it High, not Critical. More importantly, the proposed fix is incomplete: `token_claims` is mutated first at [0060:139](/home/hazypiff/in-range/supabase/migrations/0060_batch_token_preclaim.sql:139), before the vulnerable history conflict at [0060:149](/home/hazypiff/in-range/supabase/migrations/0060_batch_token_preclaim.sql:149). A conflict `WHERE` can silently skip the history update while leaving the attacker’s live token row poisoned. Foreign history ownership and existing batch ownership must be locked and rejected before either insert.  
 30929	  **Confidence:** Certain.
 30930	
 30931	- **C-SQL-2 — obsolete caller citation and overstated attacker class.**  
 30932	  **Report:** Reached through the 0019 definition of `record_location_ping`; exploitable by any authenticated user.  
 30933	  **True:** The latest definition is migration 0040, not 0019. It requires authentication, discoverability, consent, and enabled location history at [0040:156](/home/hazypiff/in-range/supabase/migrations/0040_wire_consent_gates.sql:156). The latest correlator also checks caller consent and peer discoverability, withdrawal, blocks, and preferences at [0048:277](/home/hazypiff/in-range/supabase/migrations/0048_gps_scope_and_retention.sql:277). Those guards do not authenticate the caller-supplied coordinates, so the encounter fabrication and UUID oracle remain Critical, but the attacker must be an eligible/discoverable account with a fresh ping—not merely any authenticated account.  
 30934	  **Confidence:** Certain.
 30935	
 30936	- **C-SQL-3 — severity and legal-hold-breaking fix.**  
 30937	  **Report:** Critical permanent map; add one unconditional delete.  
 30938	  **True:** The retention omission is real, but both `beacon_token_batch` and cross-user RSSI access are unavailable to ordinary clients: the batch table is RPC-only at [0031:40](/home/hazypiff/in-range/supabase/migrations/0031_server_issued_token_batches.sql:40), while RSSI users can read only their own rows at [0056:72](/home/hazypiff/in-range/supabase/migrations/0056_calibration_rssi_samples.sql:72). This is High privacy/retention risk, not a current Critical client exploit. The proposed unconditional delete also violates the cleanup function’s legal-hold invariant. The hold branch at [0059:489](/home/hazypiff/in-range/supabase/migrations/0059_proximity_wake_producer.sql:489) needs `NOT has_legal_hold(user_id)`; only the no-hold branch may delete unconditionally.  
 30939	  **Confidence:** Certain.
 30940	
 30941	- **C-SQL-4 — severity and one invalid fix option.**  
 30942	  **Report:** Critical; either reject location-less claims or compare observer locations.  
 30943	  **True:** The missing GPS veto is real, but reciprocity still remains at [0053:189](/home/hazypiff/in-range/supabase/migrations/0053_late_evidence_tolerance.sql:189), so this is High. Rejecting all location-less claims would disable the locked-phone batch-preclaim path that migration 0060 deliberately introduced. The observer-versus-observer fallback is the viable fix.  
 30944	  **Confidence:** Certain.
 30945	
docs/research/2026-08-01-hardening/verified_findings_working.md-4-severity labels and mechanisms as they stood **before** the three adversarial consensus rounds. The
docs/research/2026-08-01-hardening/verified_findings_working.md-5-signed report (`HARDENING_AUDIT_2026-08-01.md`) is authoritative. The following were changed after these
docs/research/2026-08-01-hardening/verified_findings_working.md-6-sections were written, and the original text is deliberately preserved so the correction is auditable:
docs/research/2026-08-01-hardening/verified_findings_working.md-7-
docs/research/2026-08-01-hardening/verified_findings_working.md-8-| Section below | Superseded by | What changed |
docs/research/2026-08-01-hardening/verified_findings_working.md-9-|---|---|---|
docs/research/2026-08-01-hardening/verified_findings_working.md-10-| `C-SQL-2` | **H-SQL-2** (High) | Its premise was **false**. `0019:2496-2527` revokes `correlate_miles_encounters` from `PUBLIC, anon, authenticated, service_role`; the DB confirms `{postgres=X/postgres}`. The claim "verified: no later migration revokes it" was an **asserted verification that was never performed** — the grep used `00[2-6]*`, excluding 0019. Entry point is `record_location_ping` at `0040:156` (not `0019:1159`), which enforces `current_user_can_discover()` and `require_consent(…,'precise_location')` and returns `bigint`, so the "presence oracle" sub-claim is dead. |
docs/research/2026-08-01-hardening/verified_findings_working.md-11-| `C-DIAG-1` | **H-DIAG-1** (High, merge-blocking) | **Not live.** `ios/Runner/W5LinkController.swift` does not exist on `main` (`git ls-tree main --name-only ios/Runner/` → no W5 files), so no shipped binary writes `w5_rssi_log.jsonl` today. It lands with PR #9. A separate, genuinely-shipped nuance was split out as **H-DIAG-4**: native code reads the persisted `bb.w5links`, not the build flag (`BackgroundBeacon.swift:88, 92, 880, 1034, 1103`), so a stale `true` re-activates native W5 paths before Dart attaches. |
docs/research/2026-08-01-hardening/verified_findings_working.md:12:| `C-W5-1` | **H-W5-1** (High, merge-blocking) | Severity re-rated (branch-only). **Mechanism corrected:** the `realId` fallback *finds* the encounter — it is not "treated as fresh". It is processed by the **uncommitted** path, so the intruder link is added with no winner comparison and no close, and `maybeCommit` no-ops on an already-committed encounter. A full fork occurs only when `myCandidate < peerCandidate`. Executed outcome and fix unchanged. |
docs/research/2026-08-01-hardening/verified_findings_working.md-13-| `C-W5-2`, `C-W5-3` | **H-W5-2**, **H-W5-3** | Severity re-rated — branch-only, merge-blocking. |
docs/research/2026-08-01-hardening/verified_findings_working.md-14-| `H-W5-3` (no lease persistence, in the native reviewer's section) | **H-W5-4** in the report | Renumbered only. |
docs/research/2026-08-01-hardening/verified_findings_working.md-15-| `H-W5-6` (120s grace unreachable, Codex's section below) | **H-W5-5** in the report | Renumbered only; severity raised Medium → High. |
docs/research/2026-08-01-hardening/verified_findings_working.md-16-| `H-W5-4` (dropPeer) / `H-W5-5` (candidate keyed by alias) in the native reviewer's section | **H-W5-6** / **H-W5-7** in the report | Renumbered only. |
docs/research/2026-08-01-hardening/verified_findings_working.md-17-| `C-RT-1` | **H-RT-1** | Local availability failure, not a trust-boundary crossing. Codex's fix supersedes: a timeout does not cancel the underlying flush — `_stopBle()` must run **before** network draining (`beacon_service.dart:603`), with a generation check and bounded batches. |
docs/research/2026-08-01-hardening/verified_findings_working.md-18-| `C-CONSENT-1` | **H-CONSENT-1** | Bounded today: 0056 documents the gap as deliberate pre-rollout, `INRANGE_CALIB_SCAN` defaults false, 0059 is undeployed. |
docs/research/2026-08-01-hardening/verified_findings_working.md-19-| `H-ORCH-1` | **corrected** | The claim "only 6 probes are committed, in `zz_probe_test.dart`" was **wrong**: no such file exists at W5 HEAD or in `git log --all`. It was a temporary artifact created by one of this audit's own subagents and mistaken for committed code. The transcript (`docs/research/2026-07-31/claude_kimi_chat_2026-07-31.md:386`) records `/tmp/kimi-r8/…/w5_ownership_r8_kimi_test.dart`, **26 tests**, "259/259" vs a committed 233 — so **26 probes were cited as sign-off evidence and zero were committed**. The 233 baseline is uncontaminated (measured before the artifact existed). |
docs/research/2026-08-01-hardening/verified_findings_working.md-20-| `H-SQL-5` | **H-SQL-3** in the report | Its proposed fix was a **no-op**: `record_sighting` upserts the forward row with `received_at = v_now` (`0053:119`, `:123`) immediately before calling `correlate_encounter` (`:138`), so comparing reverse receipt time to forward receipt time is the existing predicate. Real fix: compare the two `observed_at` **capture** times and bind observations to the token's validity interval. Two of the original fix items survive: reject `p_observed_at` outside `[valid_from, valid_until]`, and stop refreshing `received_at` on weaker-RSSI upserts. |
docs/research/2026-08-01-hardening/verified_findings_working.md-254-by comparing the caller's coordinates against `v_claim.approx_lat/lon`. Having just written that row
docs/research/2026-08-01-hardening/verified_findings_working.md-255-themselves, an attacker sets both sides equal and the distance is 0. The spatial half of the anti-forgery
docs/research/2026-08-01-hardening/verified_findings_working.md-256-envelope is removed, so a relay attack no longer needs to know where the victim is.
docs/research/2026-08-01-hardening/verified_findings_working.md-257-
docs/research/2026-08-01-hardening/verified_findings_working.md-258-**Flag gating:** the batch-membership check at `0060:127-133` would close this, but it only raises when
docs/research/2026-08-01-hardening/verified_findings_working.md-259-`enforce_batch_tokens >= 1`, and that flag is **currently 0**. So this is live.
docs/research/2026-08-01-hardening/verified_findings_working.md-260-
docs/research/2026-08-01-hardening/verified_findings_working.md-261-**Fix:** add `WHERE public.token_claim_history.user_id = v_uid` to the `DO UPDATE`, making a foreign-owned
docs/research/2026-08-01-hardening/verified_findings_working.md:262:conflict a silent no-op; and reject cross-owner claims even with the flag off.
docs/research/2026-08-01-hardening/verified_findings_working.md-263-
docs/research/2026-08-01-hardening/verified_findings_working.md-264-**Confidence:** CERTAIN (read the latest definition; confirmed no later redefinition).
docs/research/2026-08-01-hardening/verified_findings_working.md-265-
docs/research/2026-08-01-hardening/verified_findings_working.md-266----
docs/research/2026-08-01-hardening/verified_findings_working.md-267-
docs/research/2026-08-01-hardening/verified_findings_working.md-268-## 🔴 C-SQL-2 — `correlate_miles_encounters` fabricates encounters from arbitrary GPS, bypassing the entire 0029 reciprocity gate
docs/research/2026-08-01-hardening/verified_findings_working.md-269-
docs/research/2026-08-01-hardening/verified_findings_working.md-270-**Severity:** Critical (live, not gated by any rollout flag)
docs/research/2026-08-01-hardening/verified_findings_working.md-366-
docs/research/2026-08-01-hardening/verified_findings_working.md-367-## 🔴 C-W5-1 — A committed encounter reached by `realId` bypasses the sticky-keeper branch; the keeper is silently displaced
docs/research/2026-08-01-hardening/verified_findings_working.md-368-
docs/research/2026-08-01-hardening/verified_findings_working.md-369-**Severity:** Critical (reproduces the original #7 duplicate-keeper defect, no attacker required)
docs/research/2026-08-01-hardening/verified_findings_working.md-370-**Branch:** `fix/w5-encounter-lease`
docs/research/2026-08-01-hardening/verified_findings_working.md-371-
docs/research/2026-08-01-hardening/verified_findings_working.md-372-**Verified structurally in BOTH implementations — the committed check precedes the `realId` lookup:**
docs/research/2026-08-01-hardening/verified_findings_working.md-373-
docs/research/2026-08-01-hardening/verified_findings_working.md:374:| | committed branch | `realId` fallback |
docs/research/2026-08-01-hardening/verified_findings_working.md-375-|---|---|---|
docs/research/2026-08-01-hardening/verified_findings_working.md-376-| Dart `lib/features/beacon/w5_ownership.dart` | `:321` `if (e != null && e.committed) {` | `:351` `e ??= _enc[realId];` |
docs/research/2026-08-01-hardening/verified_findings_working.md-377-| Swift `ios/Runner/W5Ownership.swift` | `:250` `if let ec = e, ec.committed {` | `:279` `if e == nil { e = enc[realId] }` |
docs/research/2026-08-01-hardening/verified_findings_working.md-378-
docs/research/2026-08-01-hardening/verified_findings_working.md-379-`e` at the committed check comes only from `_locate(peerAlias, myCandidate)` plus the `peerPrevAlias`
docs/research/2026-08-01-hardening/verified_findings_working.md:380:fallback. When the lease key is the **peer's** candidate (`peerCandidate < myCandidate`) and the incoming
docs/research/2026-08-01-hardening/verified_findings_working.md-381-`peerAlias` is not yet in `_aliasTo`, both lookups miss, the committed branch is skipped, and the
docs/research/2026-08-01-hardening/verified_findings_working.md-382-encounter is then picked up by `_enc[realId]` **as if it were a fresh negotiating encounter**.
docs/research/2026-08-01-hardening/verified_findings_working.md-383-
docs/research/2026-08-01-hardening/verified_findings_working.md-384-**Executed proof (reviewer ran this against the Dart oracle):** committed encounter with keeper `p1`/`L5`;
docs/research/2026-08-01-hardening/verified_findings_working.md-385-a second `onControl` under a rotated (unknown) alias yields effects `[W5SendPropose]` — **no close of the
docs/research/2026-08-01-hardening/verified_findings_working.md-386-intruder, no `owns`** — and `committedKeeper` moves `p1 → p2`, `linkId` `L5 → L0`. The control probe using
docs/research/2026-08-01-hardening/verified_findings_working.md-387-the *known* alias correctly yields `[W5RejectInbound(p2)]` with the keeper unchanged, isolating the cause
docs/research/2026-08-01-hardening/verified_findings_working.md-388-to the `_locate` miss.
docs/research/2026-08-01-hardening/verified_findings_working.md-498-**Severity:** Critical
docs/research/2026-08-01-hardening/verified_findings_working.md-499-**File:** `0053_late_evidence_tolerance.sql:179-182`
docs/research/2026-08-01-hardening/verified_findings_working.md-500-
docs/research/2026-08-01-hardening/verified_findings_working.md-501-**Verified code:**
docs/research/2026-08-01-hardening/verified_findings_working.md-502-```sql
docs/research/2026-08-01-hardening/verified_findings_working.md-503-IF p_lat IS NOT NULL AND p_lon IS NOT NULL
docs/research/2026-08-01-hardening/verified_findings_working.md-504-   AND v_claim.approx_lat IS NOT NULL AND v_claim.approx_lon IS NOT NULL THEN
docs/research/2026-08-01-hardening/verified_findings_working.md-505-  v_distance := ST_Distance(...);
docs/research/2026-08-01-hardening/verified_findings_working.md:506:  IF v_distance > LEAST(400.0, GREATEST(5.0, p_radius_meters)) THEN RETURN; END IF;
docs/research/2026-08-01-hardening/verified_findings_working.md-507-END IF;
docs/research/2026-08-01-hardening/verified_findings_working.md-508-```
docs/research/2026-08-01-hardening/verified_findings_working.md-509-The spatial veto executes **only when the claim row carries coordinates**. `claim_token` requires them
docs/research/2026-08-01-hardening/verified_findings_working.md-510-(`0060:117-118`), but `claim_token_batch` (`0060:25`) pre-claims the whole batch with NULL location —
docs/research/2026-08-01-hardening/verified_findings_working.md-511-that is the locked-phone path 0060 exists to serve. For any token claimed that way, the "space bound"
docs/research/2026-08-01-hardening/verified_findings_working.md-512-that `0053:24-26` calls part of the anti-forgery envelope **does not run at all**.
docs/research/2026-08-01-hardening/verified_findings_working.md-513-
docs/research/2026-08-01-hardening/verified_findings_working.md-514-**Interaction with C-SQL-1:** an attacker does not even need to overwrite the victim's coordinates when
docs/research/2026-08-01-hardening/verified_findings_working.md-515-the claim has none. The two findings are independent routes to the same outcome, so fixing C-SQL-1 alone
docs/research/2026-08-01-hardening/verified_findings_working.md-516-does not close this.
docs/research/2026-08-01-hardening/verified_findings_working.md-517-
docs/research/2026-08-01-hardening/verified_findings_working.md-518-**Fix:** treat a location-less claim as veto-failing rather than veto-skipping, or fall back to an
docs/research/2026-08-01-hardening/verified_findings_working.md-519-observer-vs-observer comparison (compare the two sightings' `observer_lat/lon` to each other, which are
docs/research/2026-08-01-hardening/verified_findings_working.md:520:always present) — Kimi's "observer-vs-observer veto fallback".
docs/research/2026-08-01-hardening/verified_findings_working.md-521-
docs/research/2026-08-01-hardening/verified_findings_working.md-522-**Confidence:** CERTAIN (read the predicate directly).
docs/research/2026-08-01-hardening/verified_findings_working.md-523-
docs/research/2026-08-01-hardening/verified_findings_working.md-524-## H-SQL-5 (NEW, from Kimi) — the two reciprocity directions are never bound to each other
docs/research/2026-08-01-hardening/verified_findings_working.md-525-
docs/research/2026-08-01-hardening/verified_findings_working.md-526-**Verified:** `0053:189-193` selects the reverse sighting on `rs.received_at > NOW() - v_late` only.
docs/research/2026-08-01-hardening/verified_findings_working.md-527-Both directions are compared to `now()`, never to **each other**. Combined with the token's own life
docs/research/2026-08-01-hardening/verified_findings_working.md-528-(≤21 min, `0060:114-116`) the replay budget is remaining-validity + W = **~32 min at the default W=15 and
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-126-passes after.
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-127-
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-128-### Your queue, in the order we recommend
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-129-
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-130-**1. H-W5-1 (High, merge-blocking) — a committed encounter reached by `realId` bypasses the sticky-keeper branch.**
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-131-This is the highest-leverage item in the entire round: it is a two-line hoist in each implementation and
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-132-it reproduces the original #7 duplicate-keeper defect *in production with no attacker involved*.
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-133-
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:134:The committed check runs before the `realId` fallback in both languages:
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-135-- Dart `lib/features/beacon/w5_ownership.dart:321` (`if (e != null && e.committed)`) vs `:351` (`e ??= _enc[realId];`)
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-136-- Swift `ios/Runner/W5Ownership.swift:250` (`if let ec = e, ec.committed`) vs `:279` (`if e == nil { e = enc[realId] }`)
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-137-
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-138-`e` at the committed check comes only from `_locate(peerAlias, myCandidate)` plus the `peerPrevAlias`
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:139:fallback. When the lease key is the peer's candidate (`peerCandidate < myCandidate`) and the incoming
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-140-alias is not yet in `_aliasTo`, `_locate` misses and the committed branch is skipped. **Mechanism note,
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md:141:corrected during consensus (Kimi):** the `_enc[realId]` fallback then *finds* the encounter — it is not
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-142-"treated as fresh". It is processed by the **uncommitted** path, so the intruder link is added with no
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-143-winner comparison and no close, and `maybeCommit` no-ops because the encounter is already committed. A
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-144-full fork only occurs when `myCandidate < peerCandidate`. A reviewer executed this against the Dart
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-145-oracle: effects come back `[W5SendPropose]` — no close of the intruder, no `owns` — and the keeper moves
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-146-`p1 → p2`, `linkId` `L5 → L0`. With the *known* alias the same probe correctly returns
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-147-`[W5RejectInbound(p2)]` and the keeper holds, which isolates the cause to the `_locate` miss.
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-148-
docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md-149-This violates `docs/W5_ENCOUNTER_LEASE_DESIGN.md:295-296` ("A committed keeper is sticky … Committed
docs/research/2026-08-01-hardening/transcripts/reconfirm.md-5-Three amendments, all in the VERDICT / FIX ORDER / SYSTEMIC sections:
docs/research/2026-08-01-hardening/transcripts/reconfirm.md-6-
docs/research/2026-08-01-hardening/transcripts/reconfirm.md-7-**1. The Critical tier was described as homogeneous and it is not.** The old text read "one live in production and remotely exploitable by anyone, four exploitable today by any authenticated user with a modified client." That is wrong: C-SQL-3 (`beacon_token_batch` never purged) is a server-side retention defect that no user exploits — the harm is data at rest — and C-DIAG-1 is a device-local privacy defect in release binaries. Only C-SQL-1 and C-SQL-4 are user-exploitable. The tier is now split three ways: one remotely exploitable (C-PROD-1); two exploitable by an authenticated user with a modified client (C-SQL-1, C-SQL-4); two data-handling defects requiring no attacker (C-SQL-3, C-DIAG-1).
docs/research/2026-08-01-hardening/transcripts/reconfirm.md-8-
docs/research/2026-08-01-hardening/transcripts/reconfirm.md-9-**2. The apparent contradiction between C-DIAG-1 being Critical and the W5 defects being High is now stated explicitly rather than left implicit.** New text: the W5 *feature* is gated by `INRANGE_W5_LINKS`, which is why its correctness defects are merge blockers; C-DIAG-1 is Critical for the opposite reason — `W5LinkController.swift` is *not* behind that compile-time flag, it is behind the persisted `bb.w5links` bool, so the code is compiled into every release binary and a value inherited from a prior diag install re-activates it before Dart can clear it. The severity convention now reads "*Critical* means reachable now — either exploitable today or present in shipped artifacts."
docs/research/2026-08-01-hardening/transcripts/reconfirm.md-10-
docs/research/2026-08-01-hardening/transcripts/reconfirm.md-11-**3. A stale count.** The SYSTEMIC section claimed the three proposed tests "would have caught four Criticals at authoring time." After our downgrades that is false: they catch **two Criticals and one High** — C-SQL-3, C-PROD-1, and H-CONSENT-1 (which we demoted from Critical). Corrected.
docs/research/2026-08-01-hardening/transcripts/reconfirm.md-12-
docs/research/2026-08-01-hardening/transcripts/reconfirm.md:13:Also corrected outside the report, for completeness: the FIX ORDER step 2 no longer says "all live" while including C-DIAG-1; and the Mac work order's stale pre-downgrade labels are fixed (its W5 items now read High/merge-blocking, C-DIAG-1 is marked as the one Critical in that queue, and the C-W5-1 mechanism paragraph now carries Kimi's correction that the `realId` fallback *finds* the encounter and processes it via the uncommitted path rather than treating it as fresh).
docs/research/2026-08-01-hardening/transcripts/reconfirm.md-14-
docs/research/2026-08-01-hardening/transcripts/reconfirm.md-15-No finding was added, removed, or re-rated. This is descriptive accuracy only.
docs/research/2026-08-01-hardening/transcripts/reconfirm.md-16-
docs/research/2026-08-01-hardening/transcripts/reconfirm.md-17-Two caveats are being carried into the PR post verbatim and must remain marked **unverified, not cleared**: (a) the `cron.job` retention schedule, since `0015` wraps `cron.schedule` in an exception-swallowing `DO` block, so a missing row would silently make every retention claim "forever"; and (b) privilege regressions across migrations 0020–0062, since the local container is at 0019.
docs/research/2026-08-01-hardening/transcripts/reconfirm.md-18-
docs/research/2026-08-01-hardening/transcripts/reconfirm.md-19-Reply with one line — `RECONFIRMED` or `NOT RECONFIRMED` — and, if the latter, exactly what is still wrong.
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm3.md-191-30-passes after.
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm3.md-192-31-
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm3.md-193-32:### Your queue, in the order we recommend
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm3.md-194-33-
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm3.md-195-34-**1. H-W5-1 (High, merge-blocking) — a committed encounter reached by `realId` bypasses the sticky-keeper branch.**
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm3.md-196-35-This is the highest-leverage item in the entire round: it is a two-line hoist in each implementation and
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm3.md-197-36-it reproduces the original #7 duplicate-keeper defect *in production with no attacker involved*.
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm3.md-198-37-
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm3.md:199:38-The committed check runs before the `realId` fallback in both languages:
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm3.md-200-39-- Dart `lib/features/beacon/w5_ownership.dart:321` (`if (e != null && e.committed)`) vs `:351` (`e ??= _enc[realId];`)
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm3.md-201-40-- Swift `ios/Runner/W5Ownership.swift:250` (`if let ec = e, ec.committed`) vs `:279` (`if e == nil { e = enc[realId] }`)
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm3.md-202-110-ideally exclude `W5LinkController.swift` from the production target's Sources phase until W5 ships.
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm3.md-203-111-
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm3.md-204-112-**Related and separate — H-DIAG-4 (High), which DOES affect shipped code.** On `main`,
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm3.md-205-113-`INRANGE_W5_LINKS` is only the value Dart later writes to the persisted `bb.w5links`; native code reads
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm3.md-206-114-the **persisted bool**, not the build flag (`BackgroundBeacon.swift:88, 92, 880, 1034, 1103`). A stale
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm3.md-207-115-`true` from a prior diag install re-activates those native paths before Dart attaches. The H-DIAG-3
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm3.md-349-severity labels and mechanisms as they stood **before** the three adversarial consensus rounds. The
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm3.md-350-signed report (`HARDENING_AUDIT_2026-08-01.md`) is authoritative. The following were changed after these
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm3.md-351-sections were written, and the original text is deliberately preserved so the correction is auditable:
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm3.md-352-
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm3.md-353-| Section below | Superseded by | What changed |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm3.md-354-|---|---|---|
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm3.md-355-| `C-SQL-2` | **H-SQL-2** (High) | Its premise was **false**. `0019:2496-2527` revokes `correlate_miles_encounters` from `PUBLIC, anon, authenticated, service_role`; the DB confirms `{postgres=X/postgres}`. The claim "verified: no later migration revokes it" was an **asserted verification that was never performed** — the grep used `00[2-6]*`, excluding 0019. Entry point is `record_location_ping` at `0040:156` (not `0019:1159`), which enforces `current_user_can_discover()` and `require_consent(…,'precise_location')` and returns `bigint`, so the "presence oracle" sub-claim is dead. |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm3.md-356-| `C-DIAG-1` | **H-DIAG-1** (High, merge-blocking) | **Not live.** `ios/Runner/W5LinkController.swift` does not exist on `main` (`git ls-tree main --name-only ios/Runner/` → no W5 files), so no shipped binary writes `w5_rssi_log.jsonl` today. It lands with PR #9. A separate, genuinely-shipped nuance was split out as **H-DIAG-4**: native code reads the persisted `bb.w5links`, not the build flag (`BackgroundBeacon.swift:88, 92, 880, 1034, 1103`), so a stale `true` re-activates native W5 paths before Dart attaches. |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm3.md:357:| `C-W5-1` | **H-W5-1** (High, merge-blocking) | Severity re-rated (branch-only). **Mechanism corrected:** the `realId` fallback *finds* the encounter — it is not "treated as fresh". It is processed by the **uncommitted** path, so the intruder link is added with no winner comparison and no close, and `maybeCommit` no-ops on an already-committed encounter. A full fork occurs only when `myCandidate < peerCandidate`. Executed outcome and fix unchanged. |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm3.md-358-| `C-W5-2`, `C-W5-3` | **H-W5-2**, **H-W5-3** | Severity re-rated — branch-only, merge-blocking. |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm3.md-359-| `H-W5-3` (no lease persistence, in the native reviewer's section) | **H-W5-4** in the report | Renumbered only. |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm3.md-360-| `H-W5-6` (120s grace unreachable, Codex's section below) | **H-W5-5** in the report | Renumbered only; severity raised Medium → High. |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm3.md-361-| `H-W5-4` (dropPeer) / `H-W5-5` (candidate keyed by alias) in the native reviewer's section | **H-W5-6** / **H-W5-7** in the report | Renumbered only. |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm3.md-362-| `C-RT-1` | **H-RT-1** | Local availability failure, not a trust-boundary crossing. Codex's fix supersedes: a timeout does not cancel the underlying flush — `_stopBle()` must run **before** network draining (`beacon_service.dart:603`), with a generation check and bounded batches. |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm3.md-363-| `C-CONSENT-1` | **H-CONSENT-1** | Bounded today: 0056 documents the gap as deliberate pre-rollout, `INRANGE_CALIB_SCAN` defaults false, 0059 is undeployed. |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm3.md-364-| `H-ORCH-1` | **corrected** | The claim "only 6 probes are committed, in `zz_probe_test.dart`" was **wrong**: no such file exists at W5 HEAD or in `git log --all`. It was a temporary artifact created by one of this audit's own subagents and mistaken for committed code. The transcript (`docs/research/2026-07-31/claude_kimi_chat_2026-07-31.md:386`) records `/tmp/kimi-r8/…/w5_ownership_r8_kimi_test.dart`, **26 tests**, "259/259" vs a committed 233 — so **26 probes were cited as sign-off evidence and zero were committed**. The 233 baseline is uncontaminated (measured before the artifact existed). |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm3.md-365-| `H-SQL-5` | **H-SQL-3** in the report | Its proposed fix was a **no-op**: `record_sighting` upserts the forward row with `received_at = v_now` (`0053:119`, `:123`) immediately before calling `correlate_encounter` (`:138`), so comparing reverse receipt time to forward receipt time is the existing predicate. Real fix: compare the two `observed_at` **capture** times and bind observations to the token's validity interval. Two of the original fix items survive: reject `p_observed_at` outside `[valid_from, valid_until]`, and stop refreshing `received_at` on weaker-RSSI upserts. |
docs/research/2026-08-01-hardening/transcripts/kimi_consensus_r1.md-191-
docs/research/2026-08-01-hardening/transcripts/kimi_consensus_r1.md-192-  **3. C-SQL-2 — OVERSTATED; contains a false verification claim and contradicts the report itself.** Three sub-claims fail:
docs/research/2026-08-01-hardening/transcripts/kimi_consensus_r1.md-193-  - "Granted to `authenticated` at `0008:263`, **never revoked**" is false. `0019:2496-2527` revokes ALL on `correlate_miles_encounters` from `PUBLIC, anon, authenticated, service_role`, and the authenticated re-grant list (`0019:2538-2549`) omits it. I read these lines myself. The working file records "verified: no later migration revokes it" — that verification is wrong, and the report's own methodology caveat even notes the DB shows `proacl = {postgres=X/postgres}` — the report refutes itself internally.
docs/research/2026-08-01-hardening/transcripts/kimi_consensus_r1.md-194-  - "Returns raw `other_user_id` — presence oracle" is dead as a client-facing claim: authenticated can't execute the function, and the actual entry point `record_location_ping` returns only a `bigint`.
docs/research/2026-08-01-hardening/transcripts/kimi_consensus_r1.md-195-  - The entry-point ref is stale: latest `record_location_ping` is `0040:156` (calls the correlator at `0040:221`), and it enforces `require_consent(v_uid, 'precise_location')` (`0040:176`) plus the correlator's own caller/peer gates (`0048:277-320`: discoverability, consent-not-withdrawn, blocks, preference compatibility).
docs/research/2026-08-01-hardening/transcripts/kimi_consensus_r1.md-196-
docs/research/2026-08-01-hardening/transcripts/kimi_consensus_r1.md-197-  What survives: the miles path still inserts `encounters` with **NULL trust_level and no reciprocity** (`0048:337-346`), and `get_locals_feed` unlocks on any active row past the reveal delay with no trust_level discrimination (`0048:443-451`). That's a real design gap — but it's the *designed Locals feature* lacking evidence-class separation downstream, not an ungated forgery oracle: fabrication requires the victim to have genuinely pinged recently within ~16 km of the attacker's chosen point, the attacker must be discoverable and consented, and no user ids leak. **Recommend downgrade to High**, rewrite the premise, keep the fix (`trust_level='gps_only'` + exclusion where encounters are treated as evidence). Confidence: CERTAIN on the refuted sub-claims (I read the settling lines); high on the severity call.
docs/research/2026-08-01-hardening/transcripts/kimi_consensus_r1.md-198-
docs/research/2026-08-01-hardening/transcripts/kimi_consensus_r1.md:199:  **4. C-W5-1 — defect real and Critical stands, but the stated mechanism is wrong.** In the named case (lease keyed by the peer's candidate), `realId = min(my, peer) = peerCandidate`, so the `_enc[realId]` fallback (`w5_ownership.dart:351` / `W5Ownership.swift:279`) **finds** the encounter — it is not "treated as fresh." It's processed by the *uncommitted* path: the intruder link is added with no winner comparison and no close (`W5Ownership.swift:301-309`), and `maybeCommit` no-ops on an already-committed encounter. The true defect: **a committed encounter reachable only via realId bypasses the intruder-close logic, and `winner()` can silently change with no `owns`/`close` effects** — which still violates `W5_ENCOUNTER_LEASE_DESIGN.md:294-296` and still produces the duplicate-keeper outcome the reviewer executed. A full encounter fork only occurs when `myCandidate < peerCandidate`. The fix (hoist `realId` above the committed check) remains the right one. Confidence: high.
docs/research/2026-08-01-hardening/transcripts/kimi_consensus_r1.md-200-
docs/research/2026-08-01-hardening/transcripts/kimi_consensus_r1.md-201-  **5. H-DIAG-2 — overstated, and the gap is worse than reported on main.** "Cannot fail" is wrong: `testProductionDomainCannotSeeDiagnosticState` (`ReleaseIsolationTests.swift:24-43`) is a genuine runtime UserDefaults-isolation check, and the constant assertions would catch a Debug-wiring regression. The spirit stands (CI tests Debug-only, `ios-build.yml:52`; empty `<Testables>` in diag.xcscheme). Correction in the other direction: on **main**, the iOS workflow has no RunnerTests job at all — the simulator test job exists only on the W5 branch. Confidence: high.
docs/research/2026-08-01-hardening/transcripts/kimi_consensus_r1.md-202-
docs/research/2026-08-01-hardening/transcripts/kimi_consensus_r1.md-203-  **6. H-W5-5 — "R7 fix #1 is dead code" is overstated.** The fork-on-rotation mechanism is confirmed, but fix #1 still covers rediscovery under an alias whose `aliasTo` entry was evicted (two-generations eviction in `bindAlias`, `W5Ownership.swift:479-488`) while `candidateByAlias` (64-entry, no TTL, `:82`) still maps it. Narrow but reachable — "narrowly alive," not dead. Confidence: high.
docs/research/2026-08-01-hardening/transcripts/kimi_consensus_r1.md-204-
docs/research/2026-08-01-hardening/transcripts/kimi_consensus_r1.md-205-  **7. C-CONSENT-1 — severity disagreement: High, not Critical, on current exposure.** The mechanical claim is exact (zero consent references in 0056/0059), but two facts the report omits bound the exposure: 0056's header documents the missing consent as a deliberate pre-rollout gap and the upload path is gated client-side behind `INRANGE_CALIB_SCAN` (default false — verified `rssi_upload_service.dart:18`); and 0059 is undeployed (the function 404s, per C-PROD-1 itself). The systemic point — withdrawal-effectiveness must be server-side and convention-based gating keeps missing call sites — is correct and the pgTAP fix is the right durable control. But "worse than the earlier audit's defect" overstates today's reachable state for honest clients. Confidence: high.
docs/research/2026-08-01-hardening/transcripts/kimi_consensus_r1.md-206-
docs/research/2026-08-01-hardening/transcripts/kimi_consensus_r1.md-207-  **8. C-SQL-3 — one framing nuance, finding stands.** The 30-day de-anonymisable graph fully bites only for **lapsed** users; active users' rows rotate out at next batch issue (`batch_day < CURRENT_DATE - 1`, `0031:69`/`0034:105`), a ~1–2 day join window. The fix is unchanged and correct.
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-175-  **Files:** `supabase/migrations/0053_late_evidence_tolerance.sql:179-182` (veto guarded by `v_claim.approx_lat IS NOT NULL`); `supabase/migrations/0060_batch_token_preclaim.sql:60-67` (`claim_token_batch` inserts all pre-claimed slots with NULL coords, deliberately — header lines 13-20 acknowledge this disarms the veto).
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-176-
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-177-  **Exploit:** Attacker A plants confederate C near victim V.
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-178-  1. V's locked phone serves batch tokens; its claim rows are all NULL-coord (0060 is the locked-iPhone fix, so this is the *dominant* path for exactly the at-risk population).
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-179-  2. C sniffs V's token, relays to A → A calls `record_sighting(T_v, lat=anything, rssi=-50)`. The 400 m veto at 0053:179 is skipped (claim has no coords). Accepted from anywhere on Earth.
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-180-  3. A's token is relayed to C, re-broadcast beside V; V's **honest** phone buffers it and flushes a genuine sighting with real GPS on wake (the late-flush path 0053 was built to accept).
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-181-  4. A single-claims its token within 400 m of V. Reciprocity (0053:189-193) now holds → `encounters` row with `trust_level='mutual_ble'` (0053:208-209) plus a durable recurrence-pair bump (0053:202) — fake "we keep crossing paths" familiarity that reveal/recurrence ranking treats as the strongest evidence class below UWB.
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-182-
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md:183:  Even when the veto *does* execute, it compares attacker-supplied observer coords against attacker-supplied-or-absent claim coords, caller-clamped radius (`LEAST(400, GREATEST(5, p_radius_meters))`, 0053:181) — a self-consistent liar passes it.
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-184-
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-185-  **Flags:** none. Live today with all three flags at 0. `enforce_batch_tokens=1` does not help (preclaim exists regardless); `require_attestation=1` only raises account cost.
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-186-  **Root cause:** the protocol's only spatial check is conditional on data the normal locked-phone path deliberately never writes. The 0053 header's claim that "the GPS veto still bounds space… a replayed token confirms nothing from far away" is false for batch-claimed tokens.
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-187-  **Fix:** (a) when the claim row is NULL-coord, fall back to an **observer-vs-observer** veto (forward and reverse sightings' observer fixes must agree within the accuracy-aware radius — a relay fails this without also controlling the victim's GPS); (b) have `claim_token_batch` stamp coarse location (geohash-3, ~150 km) instead of NULL — enough for a cross-city veto, no meaningful privacy regression; (c) keep `mutual_ble` out of every trust/safety decision until `secure_ranged` (UWB) ships.
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-188-  **Confidence:** CERTAIN.
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-189-
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-190-  ### C2 — The blueprint's §3.3 ledger sketch is internally broken: two-sided mints violate its own UNIQUE; `day` isn't declared
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-191-  **File:** `docs/GAMIFICATION_SOCIAL_BLUEPRINT_2026-07-31_JOINT.md` §3.3 (L92-97). Schema facts: `0053:200-215` writes both users' state in one tx.
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-291-  Every SECURITY DEFINER function in `public` (93 incl. overloads) has explicit ACLs with **no PUBLIC grant**; anon can execute none (only PostGIS's extension-owned `st_estimatedextent` — not app code). 0061's fix is fully closed and durable (sweep + enumerating regression test). `consent_withdrawn`/`has_consent`/`require_consent`/`has_legal_hold` are service_role-only; where `record_sighting` consults consent internally, errors are collapsed to the same `'Unknown or expired beacon token'` — the earlier leak shape does not recur. RLS is enabled on all 42 app tables; no `USING(true)` reachable by `authenticated`; all INSERT/UPDATE policies carry matching `WITH CHECK (... = auth.uid())`; RPC-only tables hold no anon/authenticated grants. Every app SECURITY DEFINER sets `search_path`. `join_waitlist`'s email→position oracle (0062) is service_role-only (0062:135-136, verified).
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-292-
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-293-  ---
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-294-
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-295-  ## What `mutual_ble` is and is not proof of (paste-ready)
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-296-
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-297-  > `trust_level = 'mutual_ble'` asserts only this: within a sliding server-receipt window (default 15 min, clamped 2–25 min), *both* accounts uploaded at least one sighting report that resolved to the other's currently-claimed beacon token, the observer-reported RSSI cleared a floor, and — **only where the token owner happened to file a location-bearing claim** — the two reported GPS fixes agreed within ≤400 m. It is therefore proof that **two authenticated clients caused mutually consistent rows to exist in the `sightings` table**, nothing more. It is **not** proof that the two devices were ever within BLE range of each other: the BLE frame is an unsigned bearer token that any receiver can copy and re-broadcast, and a two-endpoint relay that forwards both tokens makes both *honest* phones generate exactly the rows the gate checks (0029's header says this explicitly — do not describe `mutual_ble` as relay-proof). It is **not** proof of co-presence in time: the two directions are bound only by independent sliding receipt windows, not to each other — evidence up to ~50 min apart can satisfy it at the max clamp. And it is **not** proof of location: every coordinate, RSSI, and capture timestamp in the evidence is caller-supplied, and for batch-pre-claimed (locked-phone) tokens the spatial veto does not execute at all. Relay resistance requires secure ranging (UWB, the planned `secure_ranged` level); until then, `mutual_ble` must not gate any trust- or safety-sensitive decision.
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-298-
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md:299:  **Bottom line for build order:** fix the ledger uniqueness design (C2/C3) before Phase A writes SQL; treat X4 account-age gating + the per-account daily mint cap as the load-bearing sybil countermeasures (not the pair-key machinery); and ship the observer-vs-observer veto fallback (C1) before `mutual_ble` feeds anything a user can rely on.
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-300-
docs/research/2026-08-01-hardening/transcripts/kimi_audit_out.md-301-To resume this session: kimi -r session_7d89f4bc-8080-4bd9-aaf2-66369260923e
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-533-/home/hazypiff/in-range/docs/research/2026-08-01-hardening/verified_findings_working.md-3-This file is the **working evidence record**, written during discovery. Section headings below carry the
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-534-/home/hazypiff/in-range/docs/research/2026-08-01-hardening/verified_findings_working.md-4-severity labels and mechanisms as they stood **before** the three adversarial consensus rounds. The
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-535---
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-536-/home/hazypiff/in-range/docs/research/2026-08-01-hardening/verified_findings_working.md-7-
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-537-/home/hazypiff/in-range/docs/research/2026-08-01-hardening/verified_findings_working.md-8-| Section below | Superseded by | What changed |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-538-/home/hazypiff/in-range/docs/research/2026-08-01-hardening/verified_findings_working.md-9-|---|---|---|
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-539-/home/hazypiff/in-range/docs/research/2026-08-01-hardening/verified_findings_working.md:10:| `C-SQL-2` | **H-SQL-2** (High) | Its premise was **false**. `0019:2496-2527` revokes `correlate_miles_encounters` from `PUBLIC, anon, authenticated, service_role`; the DB confirms `{postgres=X/postgres}`. The claim "verified: no later migration revokes it" was an **asserted verification that was never performed** — the grep used `00[2-6]*`, excluding 0019. Entry point is `record_location_ping` at `0040:156` (not `0019:1159`), which enforces `current_user_can_discover()` and `require_consent(…,'precise_location')` and returns `bigint`, so the "presence oracle" sub-claim is dead. |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-540-/home/hazypiff/in-range/docs/research/2026-08-01-hardening/verified_findings_working.md:11:| `C-DIAG-1` | **H-DIAG-1** (High, merge-blocking) | **Not live.** `ios/Runner/W5LinkController.swift` does not exist on `main` (`git ls-tree main --name-only ios/Runner/` → no W5 files), so no shipped binary writes `w5_rssi_log.jsonl` today. It lands with PR #9. A separate, genuinely-shipped nuance was split out as **H-DIAG-4**: native code reads the persisted `bb.w5links`, not the build flag (`BackgroundBeacon.swift:88, 92, 880, 1034, 1103`), so a stale `true` re-activates native W5 paths before Dart attaches. |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md:541:/home/hazypiff/in-range/docs/research/2026-08-01-hardening/verified_findings_working.md:12:| `C-W5-1` | **H-W5-1** (High, merge-blocking) | Severity re-rated (branch-only). **Mechanism corrected:** the `realId` fallback *finds* the encounter — it is not "treated as fresh". It is processed by the **uncommitted** path, so the intruder link is added with no winner comparison and no close, and `maybeCommit` no-ops on an already-committed encounter. A full fork occurs only when `myCandidate < peerCandidate`. Executed outcome and fix unchanged. |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-542-/home/hazypiff/in-range/docs/research/2026-08-01-hardening/verified_findings_working.md-13-| `C-W5-2`, `C-W5-3` | **H-W5-2**, **H-W5-3** | Severity re-rated — branch-only, merge-blocking. |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-543-/home/hazypiff/in-range/docs/research/2026-08-01-hardening/verified_findings_working.md:14:| `C-RT-1` | **H-RT-1** | Local availability failure, not a trust-boundary crossing. Codex's fix supersedes: a timeout does not cancel the underlying flush — `_stopBle()` must run **before** network draining (`beacon_service.dart:603`), with a generation check and bounded batches. |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-544-/home/hazypiff/in-range/docs/research/2026-08-01-hardening/verified_findings_working.md-15-| `C-CONSENT-1` | **H-CONSENT-1** | Bounded today: 0056 documents the gap as deliberate pre-rollout, `INRANGE_CALIB_SCAN` defaults false, 0059 is undeployed. |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-545-/home/hazypiff/in-range/docs/research/2026-08-01-hardening/verified_findings_working.md:16:| `H-ORCH-1` | **corrected** | The claim "only 6 probes are committed, in `zz_probe_test.dart`" was **wrong**: no such file exists at W5 HEAD or in `git log --all`. It was a temporary artifact created by one of this audit's own subagents and mistaken for committed code. The transcript (`docs/research/2026-07-31/claude_kimi_chat_2026-07-31.md:386`) records `/tmp/kimi-r8/…/w5_ownership_r8_kimi_test.dart`, **26 tests**, "259/259" vs a committed 233 — so **26 probes were cited as sign-off evidence and zero were committed**. The 233 baseline is uncontaminated (measured before the artifact existed). |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-546-/home/hazypiff/in-range/docs/research/2026-08-01-hardening/verified_findings_working.md:17:| `H-SQL-5` | **H-SQL-3** in the report | Its proposed fix was a **no-op**: `record_sighting` upserts the forward row with `received_at = v_now` (`0053:119`, `:123`) immediately before calling `correlate_encounter` (`:138`), so comparing reverse receipt time to forward receipt time is the existing predicate. Real fix: compare the two `observed_at` **capture** times and bind observations to the token's validity interval. Two of the original fix items survive: reject `p_observed_at` outside `[valid_from, valid_until]`, and stop refreshing `received_at` on weaker-RSSI upserts. |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-547-/home/hazypiff/in-range/docs/research/2026-08-01-hardening/verified_findings_working.md:18:| `H-PRIV-1` | **M-PRIV-1** (Medium) | "No path ever clears it" is **struck**: `drainBufferedWakes` (`subtle_wake_service.dart:306-346`) checks only the platform, not any flag, and the ack fires for every entry. What persists un-aged is only what accumulated while no engine existed. Coordinates are place-level SLC/`CLVisit`, not raw GPS. |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-548-/home/hazypiff/in-range/docs/research/2026-08-01-hardening/verified_findings_working.md:19:| `H-SQL-4` | **M-SQL-1** (Medium) | The runbook forbids punitive action on `relay_geo` (`RELAY_ABUSE_RUNBOOK.md:22`) and the attacker needs the victim's rotating token. |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-549-/home/hazypiff/in-range/docs/research/2026-08-01-hardening/verified_findings_working.md-20-
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-883-     4	severity labels and mechanisms as they stood **before** the three adversarial consensus rounds. The
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-884-     5	signed report (`HARDENING_AUDIT_2026-08-01.md`) is authoritative. The following were changed after these
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-885-     6	sections were written, and the original text is deliberately preserved so the correction is auditable:
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-886-     7	
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-887-     8	| Section below | Superseded by | What changed |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-888-     9	|---|---|---|
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-889-    10	| `C-SQL-2` | **H-SQL-2** (High) | Its premise was **false**. `0019:2496-2527` revokes `correlate_miles_encounters` from `PUBLIC, anon, authenticated, service_role`; the DB confirms `{postgres=X/postgres}`. The claim "verified: no later migration revokes it" was an **asserted verification that was never performed** — the grep used `00[2-6]*`, excluding 0019. Entry point is `record_location_ping` at `0040:156` (not `0019:1159`), which enforces `current_user_can_discover()` and `require_consent(…,'precise_location')` and returns `bigint`, so the "presence oracle" sub-claim is dead. |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-890-    11	| `C-DIAG-1` | **H-DIAG-1** (High, merge-blocking) | **Not live.** `ios/Runner/W5LinkController.swift` does not exist on `main` (`git ls-tree main --name-only ios/Runner/` → no W5 files), so no shipped binary writes `w5_rssi_log.jsonl` today. It lands with PR #9. A separate, genuinely-shipped nuance was split out as **H-DIAG-4**: native code reads the persisted `bb.w5links`, not the build flag (`BackgroundBeacon.swift:88, 92, 880, 1034, 1103`), so a stale `true` re-activates native W5 paths before Dart attaches. |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md:891:    12	| `C-W5-1` | **H-W5-1** (High, merge-blocking) | Severity re-rated (branch-only). **Mechanism corrected:** the `realId` fallback *finds* the encounter — it is not "treated as fresh". It is processed by the **uncommitted** path, so the intruder link is added with no winner comparison and no close, and `maybeCommit` no-ops on an already-committed encounter. A full fork occurs only when `myCandidate < peerCandidate`. Executed outcome and fix unchanged. |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-892-    13	| `C-W5-2`, `C-W5-3` | **H-W5-2**, **H-W5-3** | Severity re-rated — branch-only, merge-blocking. |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-893-    14	| `C-RT-1` | **H-RT-1** | Local availability failure, not a trust-boundary crossing. Codex's fix supersedes: a timeout does not cancel the underlying flush — `_stopBle()` must run **before** network draining (`beacon_service.dart:603`), with a generation check and bounded batches. |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-894-    15	| `C-CONSENT-1` | **H-CONSENT-1** | Bounded today: 0056 documents the gap as deliberate pre-rollout, `INRANGE_CALIB_SCAN` defaults false, 0059 is undeployed. |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-895-    16	| `H-ORCH-1` | **corrected** | The claim "only 6 probes are committed, in `zz_probe_test.dart`" was **wrong**: no such file exists at W5 HEAD or in `git log --all`. It was a temporary artifact created by one of this audit's own subagents and mistaken for committed code. The transcript (`docs/research/2026-07-31/claude_kimi_chat_2026-07-31.md:386`) records `/tmp/kimi-r8/…/w5_ownership_r8_kimi_test.dart`, **26 tests**, "259/259" vs a committed 233 — so **26 probes were cited as sign-off evidence and zero were committed**. The 233 baseline is uncontaminated (measured before the artifact existed). |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-896-    17	| `H-SQL-5` | **H-SQL-3** in the report | Its proposed fix was a **no-op**: `record_sighting` upserts the forward row with `received_at = v_now` (`0053:119`, `:123`) immediately before calling `correlate_encounter` (`:138`), so comparing reverse receipt time to forward receipt time is the existing predicate. Real fix: compare the two `observed_at` **capture** times and bind observations to the token's validity interval. Two of the original fix items survive: reject `p_observed_at` outside `[valid_from, valid_until]`, and stop refreshing `received_at` on weaker-RSSI upserts. |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-897-    18	| `H-PRIV-1` | **M-PRIV-1** (Medium) | "No path ever clears it" is **struck**: `drainBufferedWakes` (`subtle_wake_service.dart:306-346`) checks only the platform, not any flag, and the ack fires for every entry. What persists un-aged is only what accumulated while no engine existed. Coordinates are place-level SLC/`CLVisit`, not raw GPS. |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-898-    19	| `H-SQL-4` | **M-SQL-1** (Medium) | The runbook forbids punitive action on `relay_geo` (`RELAY_ABUSE_RUNBOOK.md:22`) and the attacker needs the victim's rotating token. |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-899-    20	
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1231-    30	passes after.
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1232-    31	
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1233-    32	### Your queue, in the order we recommend
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1234-    33	
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1235-    34	**1. H-W5-1 (High, merge-blocking) — a committed encounter reached by `realId` bypasses the sticky-keeper branch.**
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1236-    35	This is the highest-leverage item in the entire round: it is a two-line hoist in each implementation and
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1237-    36	it reproduces the original #7 duplicate-keeper defect *in production with no attacker involved*.
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1238-    37	
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md:1239:    38	The committed check runs before the `realId` fallback in both languages:
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1240-    39	- Dart `lib/features/beacon/w5_ownership.dart:321` (`if (e != null && e.committed)`) vs `:351` (`e ??= _enc[realId];`)
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1241-    40	- Swift `ios/Runner/W5Ownership.swift:250` (`if let ec = e, ec.committed`) vs `:279` (`if e == nil { e = enc[realId] }`)
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1242-    41	
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1243-    42	`e` at the committed check comes only from `_locate(peerAlias, myCandidate)` plus the `peerPrevAlias`
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md:1244:    43	fallback. When the lease key is the peer's candidate (`peerCandidate < myCandidate`) and the incoming
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1245-    44	alias is not yet in `_aliasTo`, `_locate` misses and the committed branch is skipped. **Mechanism note,
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md:1246:    45	corrected during consensus (Kimi):** the `_enc[realId]` fallback then *finds* the encounter — it is not
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1247-    46	"treated as fresh". It is processed by the **uncommitted** path, so the intruder link is added with no
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1248-    47	winner comparison and no close, and `maybeCommit` no-ops because the encounter is already committed. A
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1249-    48	full fork only occurs when `myCandidate < peerCandidate`. A reviewer executed this against the Dart
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1250-    49	oracle: effects come back `[W5SendPropose]` — no close of the intruder, no `owns` — and the keeper moves
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1251-    50	`p1 → p2`, `linkId` `L5 → L0`. With the *known* alias the same probe correctly returns
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1252-    51	`[W5RejectInbound(p2)]` and the keeper holds, which isolates the cause to the `_locate` miss.
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1253-    52	
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1254-    53	This violates `docs/W5_ENCOUNTER_LEASE_DESIGN.md:295-296` ("A committed keeper is sticky … Committed
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1459-   257	the mapping to their final identifiers is in the amendment table at the top of
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1460-   258	`verified_findings_working.md`.
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1461-   259	
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1462-   260	**Final state: four Criticals, all server-side and live. Both auditors re-confirmed.**
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1463-
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1464-exec
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1465-/bin/bash -lc "nl -ba /home/hazypiff/in-range/docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md | sed -n '45,145p'" in /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1466- succeeded in 0ms:
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md:1467:    45	corrected during consensus (Kimi):** the `_enc[realId]` fallback then *finds* the encounter — it is not
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1468-    46	"treated as fresh". It is processed by the **uncommitted** path, so the intruder link is added with no
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1469-    47	winner comparison and no close, and `maybeCommit` no-ops because the encounter is already committed. A
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1470-    48	full fork only occurs when `myCandidate < peerCandidate`. A reviewer executed this against the Dart
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1471-    49	oracle: effects come back `[W5SendPropose]` — no close of the intruder, no `owns` — and the keeper moves
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1472-    50	`p1 → p2`, `linkId` `L5 → L0`. With the *known* alias the same probe correctly returns
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1473-    51	`[W5RejectInbound(p2)]` and the keeper holds, which isolates the cause to the `_locate` miss.
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1474-    52	
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1475-    53	This violates `docs/W5_ENCOUNTER_LEASE_DESIGN.md:295-296` ("A committed keeper is sticky … Committed
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1909-  1026	        unawaited(_bgBeacon.setWakePing(
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1910-  1027	          url: AppConfig.wakePingUrl,
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1911-  1028	          auth: InRangeSupabase.client.auth.currentSession?.accessToken,
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1912-  1029	        ));
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1913-  1030	      }
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1914-  1031	      _applyAdvertisingVerdict(ok, 'native start');
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1915-  1032	      debugPrint(ok
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1916-  1033	          ? 'iOS native advertising armed (marker + GATT token carrier)'
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md:1917:  1034	          : 'iOS native advertising not ready → scan-only fallback');
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1918-  1035	      return;
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1919-    30	        'INRANGE_SCAN_LEGACY_ONLY' =>
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1920-    31	          const String.fromEnvironment('INRANGE_SCAN_LEGACY_ONLY'),
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1921-    32	        'INRANGE_SCAN_RESTART_MINUTES' =>
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1922-    33	          const String.fromEnvironment('INRANGE_SCAN_RESTART_MINUTES'),
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1923-    34	        'INRANGE_SUBTLE_WAKE' =>
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1924-    35	          const String.fromEnvironment('INRANGE_SUBTLE_WAKE'),
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1925-    36	        'INRANGE_LOCATION_RESIDENCY' =>
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1996-191:- **H-RT-1** *(was C-RT-1, downgraded per Codex — a local availability failure, not a security-boundary
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1997-257:4. **H-W5-1** (two-line hoist + the vector that pins it), then **H-W5-5** *before* the Phase-5 matrix.
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1998-/home/hazypiff/in-range/docs/research/2026-08-01-hardening/MAC_AGENT_WORK_ORDER.md
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-1999-163:branch yields 233/233 today, only 6 probes are committed (`test/features/beacon/zz_probe_test.dart`), and
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2000-165:(`git log --all` finds no trace). 233 + 26 = 259 reconciles it exactly. So roughly twenty adversarial
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2001-210:what this round exists to establish, given all suites were green while five Criticals and the entire
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2002-/home/hazypiff/in-range/docs/research/2026-08-01-hardening/verified_findings_working.md
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2003-11:| `C-DIAG-1` | **H-DIAG-1** (High, merge-blocking) | **Not live.** `ios/Runner/W5LinkController.swift` does not exist on `main` (`git ls-tree main --name-only ios/Runner/` → no W5 files), so no shipped binary writes `w5_rssi_log.jsonl` today. It lands with PR #9. A separate, genuinely-shipped nuance was split out as **H-DIAG-4**: native code reads the persisted `bb.w5links`, not the build flag (`BackgroundBeacon.swift:88, 92, 880, 1034, 1103`), so a stale `true` re-activates native W5 paths before Dart attaches. |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md:2004:12:| `C-W5-1` | **H-W5-1** (High, merge-blocking) | Severity re-rated (branch-only). **Mechanism corrected:** the `realId` fallback *finds* the encounter — it is not "treated as fresh". It is processed by the **uncommitted** path, so the intruder link is added with no winner comparison and no close, and `maybeCommit` no-ops on an already-committed encounter. A full fork occurs only when `myCandidate < peerCandidate`. Executed outcome and fix unchanged. |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2005-13:| `C-W5-2`, `C-W5-3` | **H-W5-2**, **H-W5-3** | Severity re-rated — branch-only, merge-blocking. |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2006-14:| `C-RT-1` | **H-RT-1** | Local availability failure, not a trust-boundary crossing. Codex's fix supersedes: a timeout does not cancel the underlying flush — `_stopBle()` must run **before** network draining (`beacon_service.dart:603`), with a generation check and bounded batches. |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2007-16:| `H-ORCH-1` | **corrected** | The claim "only 6 probes are committed, in `zz_probe_test.dart`" was **wrong**: no such file exists at W5 HEAD or in `git log --all`. It was a temporary artifact created by one of this audit's own subagents and mistaken for committed code. The transcript (`docs/research/2026-07-31/claude_kimi_chat_2026-07-31.md:386`) records `/tmp/kimi-r8/…/w5_ownership_r8_kimi_test.dart`, **26 tests**, "259/259" vs a committed 233 — so **26 probes were cited as sign-off evidence and zero were committed**. The 233 baseline is uncontaminated (measured before the artifact existed). |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2008-34:## H-ORCH-1 — Round-8 sign-off evidence is partially unreproducible; ~20 adversarial probes lost
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2009-53:| Only **6** probes are committed | `test/features/beacon/zz_probe_test.dart` = 6 `test(` cases |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2010-61:that pin it are, for the most part, gone: ~20 of the 26 probes cited in the PASS are not in the
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2011-77:## C-DIAG-1 — Diagnostic W5 link layer + plaintext RSSI log ship in production binaries, gated only by a persisted bool
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2012-364:## 🔴 C-W5-1 — A committed encounter reached by `realId` bypasses the sticky-keeper branch; the keeper is silently displaced
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2082-   363	
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2083-   364	## 🔴 C-W5-1 — A committed encounter reached by `realId` bypasses the sticky-keeper branch; the keeper is silently displaced
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2084-   365	
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2085-   366	**Severity:** Critical (reproduces the original #7 duplicate-keeper defect, no attacker required)
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2086-   367	**Branch:** `fix/w5-encounter-lease`
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2087-   368	
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2088-   369	**Verified structurally in BOTH implementations — the committed check precedes the `realId` lookup:**
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2089-   370	
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md:2090:   371	| | committed branch | `realId` fallback |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2091-   372	|---|---|---|
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2092-   373	| Dart `lib/features/beacon/w5_ownership.dart` | `:321` `if (e != null && e.committed) {` | `:351` `e ??= _enc[realId];` |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2093-   374	| Swift `ios/Runner/W5Ownership.swift` | `:250` `if let ec = e, ec.committed {` | `:279` `if e == nil { e = enc[realId] }` |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2094-   375	
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2095-   376	`e` at the committed check comes only from `_locate(peerAlias, myCandidate)` plus the `peerPrevAlias`
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md:2096:   377	fallback. When the lease key is the **peer's** candidate (`peerCandidate < myCandidate`) and the incoming
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2097-   378	`peerAlias` is not yet in `_aliasTo`, both lookups miss, the committed branch is skipped, and the
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2098-   379	encounter is then picked up by `_enc[realId]` **as if it were a fresh negotiating encounter**.
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2099-   380	
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2100-   381	**Executed proof (reviewer ran this against the Dart oracle):** committed encounter with keeper `p1`/`L5`;
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2101-   382	a second `onControl` under a rotated (unknown) alias yields effects `[W5SendPropose]` — **no close of the
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2102-   383	intruder, no `owns`** — and `committedKeeper` moves `p1 → p2`, `linkId` `L5 → L0`. The control probe using
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2103-   384	the *known* alias correctly yields `[W5RejectInbound(p2)]` with the keeper unchanged, isolating the cause
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2104-   385	to the `_locate` miss.
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2214-   495	**Severity:** Critical
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2215-   496	**File:** `0053_late_evidence_tolerance.sql:179-182`
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2216-   497	
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2217-   498	**Verified code:**
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2218-   499	```sql
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2219-   500	IF p_lat IS NOT NULL AND p_lon IS NOT NULL
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2220-   501	   AND v_claim.approx_lat IS NOT NULL AND v_claim.approx_lon IS NOT NULL THEN
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2221-   502	  v_distance := ST_Distance(...);
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md:2222:   503	  IF v_distance > LEAST(400.0, GREATEST(5.0, p_radius_meters)) THEN RETURN; END IF;
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2223-   504	END IF;
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2224-   505	```
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2225-   506	The spatial veto executes **only when the claim row carries coordinates**. `claim_token` requires them
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2226-   507	(`0060:117-118`), but `claim_token_batch` (`0060:25`) pre-claims the whole batch with NULL location —
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2227-   508	that is the locked-phone path 0060 exists to serve. For any token claimed that way, the "space bound"
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2228-   509	that `0053:24-26` calls part of the anti-forgery envelope **does not run at all**.
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2229-   510	
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2230-   511	**Interaction with C-SQL-1:** an attacker does not even need to overwrite the victim's coordinates when
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2231-   512	the claim has none. The two findings are independent routes to the same outcome, so fixing C-SQL-1 alone
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2232-   513	does not close this.
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2233-   514	
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2234-   515	**Fix:** treat a location-less claim as veto-failing rather than veto-skipping, or fall back to an
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2235-   516	observer-vs-observer comparison (compare the two sightings' `observer_lat/lon` to each other, which are
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md:2236:   517	always present) — Kimi's "observer-vs-observer veto fallback".
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2237-   518	
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2238-   519	**Confidence:** CERTAIN (read the predicate directly).
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2239-   520	
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2240-   521	## H-SQL-5 (NEW, from Kimi) — the two reciprocity directions are never bound to each other
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2241-   522	
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2242-   523	**Verified:** `0053:189-193` selects the reverse sighting on `rs.received_at > NOW() - v_late` only.
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2243-   524	Both directions are compared to `now()`, never to **each other**. Combined with the token's own life
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2244-   525	(≤21 min, `0060:114-116`) the replay budget is remaining-validity + W = **~32 min at the default W=15 and
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2382-   663	
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2383-   664	**Note:** this independently matches the Claude native reviewer's own "VERIFIED SOUND" list on threading
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2384-   665	and codec bounds. Two models agreeing on what is *correct* is worth as much here as agreement on defects.
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2385-
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2386-exec
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2387-/bin/bash -lc 'rg -n -C 2 "H-W5-[34567]" /home/hazypiff/in-range/docs/research/2026-08-01-hardening/verified_findings_working.md' in /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2388- succeeded in 0ms:
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2389-11-| `C-DIAG-1` | **H-DIAG-1** (High, merge-blocking) | **Not live.** `ios/Runner/W5LinkController.swift` does not exist on `main` (`git ls-tree main --name-only ios/Runner/` → no W5 files), so no shipped binary writes `w5_rssi_log.jsonl` today. It lands with PR #9. A separate, genuinely-shipped nuance was split out as **H-DIAG-4**: native code reads the persisted `bb.w5links`, not the build flag (`BackgroundBeacon.swift:88, 92, 880, 1034, 1103`), so a stale `true` re-activates native W5 paths before Dart attaches. |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md:2390:12-| `C-W5-1` | **H-W5-1** (High, merge-blocking) | Severity re-rated (branch-only). **Mechanism corrected:** the `realId` fallback *finds* the encounter — it is not "treated as fresh". It is processed by the **uncommitted** path, so the intruder link is added with no winner comparison and no close, and `maybeCommit` no-ops on an already-committed encounter. A full fork occurs only when `myCandidate < peerCandidate`. Executed outcome and fix unchanged. |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2391-13:| `C-W5-2`, `C-W5-3` | **H-W5-2**, **H-W5-3** | Severity re-rated — branch-only, merge-blocking. |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2392-14-| `C-RT-1` | **H-RT-1** | Local availability failure, not a trust-boundary crossing. Codex's fix supersedes: a timeout does not cancel the underlying flush — `_stopBle()` must run **before** network draining (`beacon_service.dart:603`), with a generation check and bounded batches. |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2393-15-| `C-CONSENT-1` | **H-CONSENT-1** | Bounded today: 0056 documents the gap as deliberate pre-rollout, `INRANGE_CALIB_SCAN` defaults false, 0059 is undeployed. |
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2394---
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2395-579-# ROUND 2 — Codex (`gpt-5.6-sol`) independent pass (verified additions)
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2396-580-
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2397-581:## H-W5-6 (NEW, from Codex; severity RAISED by coordinator Medium → High) — the 120s reconnect grace is normally unreachable, blocked by 5- and 15-minute discovery caches
docs/research/2026-08-01-hardening/transcripts/codex_reconfirm2.md-2398-582-
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-240-  ACK path, cap, and bijection (the doc protocol is executable).
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-241-
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-242-## Constants & encoding (normative)
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-243-
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-244-- `MAX_CONTENDERS = 5` (reconciled with the ≤185-byte one-frame budget:
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-245-  `4 header + 16 encounterId + 4 viewGen + 1 count + 32·N` ≤ 185 ⟹ N ≤ 5). Both
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-246-  a **local** contender count (known links + pending dials) and an **inbound**
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-247-  `PROPOSE` count are bounded; over-count fails closed (role-correct
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md:248:  close/reject, or token-read fallback if a peer's MTU cannot hold a bounded
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-249-  frame). Byte-size and count are separate checks.
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-250-- All ids (`encounterId`, `candidateId`, `linkId`) are **16 bytes**; `viewGen` is
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-251-  a **uint32, big-endian**, and **saturates** at `2^32−1` (never wraps into an
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-252-  older value) — on saturation the encounter is torn down and re-established.
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-253-- `viewHash` / `setHash` = **SHA-256** over the domain-separated encoding
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-254-  `"W5-VIEW-v1" || encounterId || u32(viewGen) || Σ(central(16) || linkId(16))`
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-255-  with contenders in ascending `(central, linkId)` byte order; the low 16 bytes
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-256-  are carried on the wire. (The Dart reference uses the canonical string as the
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-271-- Frame header `len` is a **u16 big-endian** body length; a frame must be
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-272-  exactly `4 + len` bytes (trailing bytes = violation).
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-273-- Type codes (v1): `HELLO=0x01, HELLO_ACK=0x02, PROPOSE=0x03, PROPOSE_ACK=0x04,
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-274-  REJECT=0x05, ALIAS_ROLL=0x06, BYE=0x07`.
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-275-- `setHash` truncation = the **leading** 16 bytes of the SHA-256 digest.
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-276-- `HELLO.prevAlias` = all-zero 16 bytes when absent.
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-277-- A `PROPOSE` at the cap (5 contenders) is exactly 185 bytes — the one-frame
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-278-  budget is tight by construction (vector-asserted).
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md:279:- Decode contract: unknown `ver` → legacy fallback result (never a close);
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-280-  unknown type / bad len / over-cap / non-canonically-ordered contenders /
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-281-  oversize on a supported `ver` → violation (drop + close). Encoders refuse
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-282-  out-of-contract input at the source (over-cap, non-ascending, non-16-byte
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-283-  ids, out-of-u32 generations).
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-284-
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-285-## v5 corrections (PR #9 round 4)
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-286-
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-287-- **Physical-link identity ≠ encounter identity.** A fresh 128-bit **`linkId`**
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-292-  duplicate connections agreeing on different physical links; a stale proposal
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-293-  committing a replacement link.
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-294-- **Proposals bind to `encounterId` + `viewGen`**; a delayed proposal/ack from an
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-295-  older view cannot commit a newer link. Peer agreement clears on any local view
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-296-  change.
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-297-- **Wire protocol specified** (below): `HELLO`/`HELLO_ACK` carry `linkId`;
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-298-  `PROPOSE`/`PROPOSE_ACK`/`REJECT` carry contender lists + view binding + caps;
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-299-  notify size honours `CBCentral.maximumUpdateValueLength`; unknown-version →
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md:300:  fallback, unknown-type-of-known-version → close.
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-301-- **Tests use observer-local handles** — compare the committed wire `linkId`
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-302-  across endpoints, then assert each maps it to the correct local handle; added
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-303-  same-direction-duplicate and asymmetric-reconnect/stale-proposal regressions;
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-304-  the harness also asserts **no `owns` before commit**.
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-305-
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-306-## v4 corrections (PR #9 round 3)
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-307-
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-308-- **Safety is agreement, not elapsed time.** Commit happens only when this
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-428-- `ALIAS_ROLL` (over the keeper, before/at rotation) — `newAlias(16)`. Atomic:
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-429-  current→previous, set new current.
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-430-- `BYE` — graceful teardown (optional; loss handled by grace timer).
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-431-
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-432-`viewGen` is a per-endpoint monotonic counter bumped whenever the contender set
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-433-changes; peer agreement is cleared on any local view change, so a delayed
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-434-`PROPOSE`/`ACK` from an older `viewGen` cannot commit a replacement link.
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-435-
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md:436:Backward compatibility: a peer without `CA6E` → token-read fallback (no lease,
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-437-unchanged, never broken).
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-438-
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-439-## Ownership state model (native authority)
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-440-
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-441-Per encounter (`leaseId`):
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-442-
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-443-```
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-444-state ∈ { negotiating, confirmed, grace }
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-616-     2	import Foundation
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-617-     3	
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-618-     4	// CA6E binary wire codec — must stay byte-identical to
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-619-     5	// lib/features/beacon/w5_codec.dart; both are pinned by the shared vectors
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-620-     6	// (test/features/beacon/w5_codec_vectors.json, consumed by W5CodecTests).
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-621-     7	// See docs/W5_ENCOUNTER_LEASE_DESIGN.md §Wire format.
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-622-     8	//
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-623-     9	// Frame = ver(1) | type(1) | len(2, u16 BE) | body(len), parsed strictly:
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md:624:    10	// unknown ver → .legacyVersion (token-read fallback, NOT a close); unknown
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-625-    11	// type / bad len / over-cap / non-canonical contenders on a supported ver →
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-626-    12	// .violation (drop + close the link). All ids exactly 16 bytes; viewGen u32 BE.
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-627-    13	
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-628-    14	let kW5CodecVersion: UInt8 = 1
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-629-    15	let kW5CodecMaxContenders = 5
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-630-    16	let kW5IdLen = 16
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-631-    17	let kW5MaxFrame = 185 // one-write/notify budget (design §Constants)
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-632-    18	
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-666-    52	  case proposeAck(encounterId: Data, viewGen: UInt32, setHash: Data)
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-667-    53	  case reject(encounterId: Data, viewGen: UInt32, linkId: Data)
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-668-    54	  case aliasRoll(newAlias: Data)
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-669-    55	  case bye
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-670-    56	}
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-671-    57	
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-672-    58	enum W5DecodeResult: Equatable {
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-673-    59	  case ok(W5WireMsg)
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md:674:    60	  /// Unknown ver: peer is lease-incapable → token-read fallback, never close.
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-675-    61	  case legacyVersion(UInt8)
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-676-    62	  /// Malformed/unknown-type/over-cap on a supported ver: drop + close the link.
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-677-    63	  case violation(String)
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-678-    64	}
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-679-    65	
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-680-    66	enum W5CodecError: Error {
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-681-    67	  case contract(String)
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-682-    68	}
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-2470-   350	    guard let list = args as? [[String: Any]] else { return }
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-2471-   351	    let sane = list.filter {
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-2472-   352	      ($0["t"] as? String)?.count == 32 && $0["f"] is NSNumber && $0["u"] is NSNumber
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-2473-   353	    }
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-2474-   354	    if !sane.isEmpty { defaults.set(sane, forKey: Self.keySlots) }
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-2475-   355	  }
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-2476-   356	
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-2477-   357	  /// The token for the slot covering NOW. Returns nil when nothing covers —
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md:2478:   358	  /// the old fallback served the newest EXPIRED token ("stale beats
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-2479-   359	  /// nothing"), but every claim on an expired token is unresolvable
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-2480-   360	  /// server-side, so peers burned a connect + read for a token the server
docs/research/2026-08-01-hardening/transcripts/codex_audit_out.md-2481-   361	  /// would reject. With today+tomorrow batches (0060 client side) an

exec
/bin/bash -lc "rtk rg -n -C 6 \"GREATEST\\(public\\.token_claim_history\\.valid_until|resolvable life|can only ever grow|shorten an existing|valid_until = GREATEST\" docs supabase/migrations
rtk rg -n -C 8 \"observer_accuracy_m|GPS.*accuracy|two OBSERVERS|observer-versus-observer\" docs/research/2026-08-01-hardening | head -n 400" in /home/hazypiff/in-range
 succeeded in 0ms:
supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql-81-    last_claimed_at = EXCLUDED.last_claimed_at;
supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql-82-
supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql-83-  INSERT INTO public.token_claim_history
supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql-84-    (token, user_id, valid_from, valid_until, approx_lat, approx_lon, range_type, accuracy_m, created_at)
supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql-85-  VALUES (lower(p_token), v_uid, v_now, p_valid_until, p_lat, p_lon, p_range, p_accuracy, v_now)
supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql-86-  ON CONFLICT (token) DO UPDATE SET
supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql:87:    valid_until = GREATEST(public.token_claim_history.valid_until, EXCLUDED.valid_until),
supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql-88-    approx_lat = EXCLUDED.approx_lat,
supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql-89-    approx_lon = EXCLUDED.approx_lon,
supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql-90-    range_type = EXCLUDED.range_type,
supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql-91-    accuracy_m = EXCLUDED.accuracy_m
supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql-92-  -- 0063 (audit C-SQL-1): the conflict target is the TOKEN, but the
supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql-93-  -- security-relevant key is (token, owner). Without this predicate any
docs/research/2026-08-01-hardening/transcripts/kimi_consensus_r2.md-23-  - The scan watchdog: check what reads `_lastForeignScanAt`. Let me grep to confirm the watchdog claim ("hides a dead scanner").
docs/research/2026-08-01-hardening/transcripts/kimi_consensus_r2.md-24-
docs/research/2026-08-01-hardening/transcripts/kimi_consensus_r2.md-25-  But wait — severity assessment: the finding H-RT-3 says "replayed into the live 90s window with fresh timestamps → false 'Close By' for a peer who was near 20 minutes ago, and it hides a dead scanner from the watchdog." The mechanism as stated ("fresh timestamps") was wrong for the upload path but right in effect for the estimator — the estimator stamps now() which is equivalent to fresh timestamps at the classifier. So the coordinator is right that my refutation was wrong: I refuted the drain, but the finding's effect is real at the estimator boundary. My delegate even noted this ("replayed samples do enter rangeEstimator.addObservation... at drain time, so the estimator window and local feed treat them as live") but called it "deliberate (late-evidence design per :311-316)". Is it deliberate? Lines :311-316 are about the native buffer design. The late-evidence design (0053) is about the *server* accepting true capture times. The estimator is an on-device 90-second sliding window classifier — there is no design rationale for stamping drained samples as now; the estimator simply lacks a timestamp parameter. The comment at :2265-2267 shows the authors cared about true capture time for upload. So the estimator stamping looks like an unconsidered gap, not deliberate design. But is there a counterargument? When the app is killed/locked and iOS buffers sightings natively, on drain (app wake), should a 20-min-old sample make the peer show as "Close By" now? No — that's a false live proximity signal. And `_lastForeignScanAt` — check the watchdog.
docs/research/2026-08-01-hardening/transcripts/kimi_consensus_r2.md-26-
docs/research/2026-08-01-hardening/transcripts/kimi_consensus_r2.md-27-  Let me grep _lastForeignScanAt usage.
docs/research/2026-08-01-hardening/transcripts/kimi_consensus_r2.md-28-
docs/research/2026-08-01-hardening/transcripts/kimi_consensus_r2.md-29-  Also for H-PRIV-1, need to read SubtleWakeCoordinator.swift:335-350 (removeObject in ack path), :400-450 (lat/lon entries), and check Dart side drainBufferedWakes/isSupported/AppConfig.subtleWake default. Let me read those and grep the Dart side.Now check the emitWake buffer-append path and cap enforcement (around :300-330 presumably), and the Dart side: drainBufferedWakes + isSupported + AppConfig.subtleWake default. Let me read SubtleWakeCoordinator.swift around 290-330 (emitWake) and grep the Dart side.Now I have what I need for both disputes. Let me check the remaining piece for H-PRIV-1: does `drainBufferedWakes` return early unless `isSupported`, and does `isSupported` require `AppConfig.subtleWake`? The grep shows `_readSubtleWakeFlag()` returns AppConfig.subtleWake (default false — app_config.dart:146-150, empty → 'false'). Need to see where isSupported gates the drain. Let me check subtle_wake_service.dart around isSupported and the start of drainBufferedWakes — line 306-330. The drain at :307 checks platform iOS only; does it check _running/isSupported? The drain is called from start() (:159) and onWakeBuffered (:244). If subtleWake flag is false, does start() return early before reaching :159? And does onWakeBuffered get delivered if native side buffers? The native side only buffers if the coordinator is running — but the coordinator's start is driven by Dart... Actually the native SubtleWakeCoordinator.bootFromPersistence() runs pre-Dart from AppDelegate (:22) — persisted wantsToRun state can restart SLC monitoring natively even if the Dart flag is now false! That's the H-DIAG-3-adjacent path: native wakes appendBuffer events natively (emitWake → appendBuffer when no channel or suspended). Then buffer accumulates. When does it ever get cleared? Only via Dart drain+ack (ackBuffer at :335-346, removeObject only when buffer empties). Dart's drain requires... let me verify the isSupported gate inside SubtleWakeService — check lines ~100-160 and where drainBufferedWakes checks isSupported. The coordinator claims "Dart's drainBufferedWakes returns early unless isSupported, which requires AppConfig.subtleWake (default false)". Let me verify.
docs/research/2026-08-01-hardening/transcripts/kimi_consensus_r2.md-30-
docs/research/2026-08-01-hardening/transcripts/kimi_consensus_r2.md:31:  Also for precision: are these SLC/CLVisit coordinates "place-level"? SLC (significant location change) fixes are typically cell-tower triangulation — accuracy often hundreds of meters to km; CLVisit coordinates are place-level. The entries carry acc field. The coordinator concedes "raw GPS" → "place-level coordinates". Fair. But note didUpdateLocations uses the SLC manager's fix with whatever accuracy; not "raw precise GPS" since no continuous session (:400 comment "SLC fixes only — this manager never runs a continuous session").
docs/research/2026-08-01-hardening/transcripts/kimi_consensus_r2.md-32-
docs/research/2026-08-01-hardening/transcripts/kimi_consensus_r2.md-33-  So H-PRIV-1 adjudication: my refutation cited the wrong buffer (BackgroundLocationCoordinator). The finding's actual subject, SubtleWakeCoordinator, does have: bufferKey "io.inrange.subtlewake.buffer" (:21), cap 50 (:22), lat/lon entries (:407-408 slc, :442-443 visit), removal only in ackBuffer (:335-346), and notifyBufferReady only tells Dart when channel exists + app active. If the Dart flag is off, start() never runs → does drain ever happen? onWakeBuffered is only invoked by native when channel != nil and app active; channel is set when Dart registers the handler (SubtleWakeService constructor/init?). If the Dart service registers a method handler regardless of flag, then onWakeBuffered → drainBufferedWakes; if drain returns early due to isSupported false, buffer never acked, never cleared → persists indefinitely (cap 50, count-only eviction). So the finding stands with modification: cap 50 not "up to 50"... actually report said "up to 50" — correct! Report said "persists up to 50 raw GPS fixes in UserDefaults with a count cap and no age limit, and no path ever clears it — survives updates, included in backups." Cap 50 ✓, count cap ✓, no age limit ✓. "No path ever clears it" — needs the isSupported check. Let me verify the early return.
docs/research/2026-08-01-hardening/transcripts/kimi_consensus_r2.md-34-
docs/research/2026-08-01-hardening/transcripts/kimi_consensus_r2.md-35-  Also note: even with the flag ON, UserDefaults is included in backups and survives updates; entries do carry place-level coords. And when flag OFF but native pre-Dart boot re-arms SLC (persisted wantsToRun), buffer grows and is never drained. Need to verify isSupported gate.
docs/research/2026-08-01-hardening/transcripts/kimi_consensus_r2.md-36-
docs/research/2026-08-01-hardening/transcripts/kimi_consensus_r2.md-37-  Let me read subtle_wake_service.dart around isSupported and drainBufferedWakes start.One more check: does `drainBufferedWakes` itself check isSupported? Lines 306-330 showed: `:307 if (_platform != TargetPlatform.iOS) return;` then drain-in-flight logic, then invokes channel. Does it check isSupported anywhere? The grep for isSupported showed only :98, :146, :215. So drainBufferedWakes does NOT check isSupported directly — it checks platform only. But wait, does handleWake get called per drained wake, and does the ack happen regardless? Need to see the rest of drainBufferedWakes (lines 306-345) to determine whether the ack lands when isSupported is false. If drain pulls the buffer and acks even with flag off (handleWake returns early but ack still sent), then the buffer IS cleared whenever Dart runs the service on iOS regardless of flag. But drain is only called from start() (:159 — gated by isSupported at :146) and onWakeBuffered (:244 — is the channel handler registered only when running?). If the method handler is registered in the constructor or in start() after the isSupported check, then with flag off: handler never registered → native notifyBufferReady's invokeMethod gets nothing → no drain → buffer persists. Also, does native even buffer when flag off? Native pre-Dart boot (AppDelegate:22 bootFromPersistence) re-arms SLC from persisted wantsToRun — yes, natively, regardless of the Dart flag. emitWake appends to buffer when channel is nil or app suspended. So with flag off but a prior session having run with wantsToRun persisted... hmm, but if flag was always off, native start() was never called by Dart, so wantsToRun never persisted true. The stale-state scenario: bench build had flag on → wantsToRun persisted → later build/flag off → native re-arms SLC pre-Dart (H-DIAG-3 territory) → buffers wakes → Dart flag off → start() returns at :146 → drain never called from there; onWakeBuffered handler — registered where? Let me check where the method call handler is set (_channel.setMethodCallHandler) — likely in start() or an init. If in start() after :146, then with flag off there's no handler and no drain ever → buffer persists forever (capped at 50, FIFO).
docs/research/2026-08-01-hardening/transcripts/kimi_consensus_r2.md-38-
docs/research/2026-08-01-hardening/transcripts/kimi_consensus_r2.md-39-  Let me read drainBufferedWakes fully (306-350) and find setMethodCallHandler.Key facts now established for H-PRIV-1:
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-2800-   380	)
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-2801-   381	LANGUAGE plpgsql
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-2802-   382	STABLE
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-2803-   383	SECURITY DEFINER
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-2804-   384	SET search_path = pg_catalog, public
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-2805-   385	AS $$
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-2806-
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-2807- succeeded in 0ms:
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:2808:   130	    rssi, observed_at, observer_lat, observer_lon, range_type, observer_accuracy_m
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-2809-   131	  ) VALUES (
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-2810-   132	    v_uid, lower(p_observed_token), v_observed_uid, v_now,
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-2811-   133	    p_rssi, p_observed_at, p_lat, p_lon, v_range, p_accuracy
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-2812-   134	  )
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-2813-   135	  ON CONFLICT (observer_user_id, observed_token) DO UPDATE
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-2814-   136	    SET observed_at = p_observed_at, received_at = v_now, observed_user_id = v_observed_uid,
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-2815-   137	        rssi = CASE WHEN p_rssi > s.rssi THEN p_rssi ELSE s.rssi END,
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-2816-   138	        observer_lat = CASE WHEN p_rssi > s.rssi THEN p_lat ELSE s.observer_lat END,
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-2817-   139	        observer_lon = CASE WHEN p_rssi > s.rssi THEN p_lon ELSE s.observer_lon END,
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:2818:   140	        observer_accuracy_m = CASE WHEN p_rssi > s.rssi THEN p_accuracy ELSE s.observer_accuracy_m END,
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-2819-   141	        range_type = CASE WHEN p_rssi > s.rssi THEN v_range ELSE s.range_type END
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-2820-   142	  RETURNING id INTO v_id;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-2821-   143	
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-2822-   144	  v_window := LEAST(30, public.range_time_window_minutes(v_range));
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-2823-   145	  IF v_range::TEXT LIKE 'feet_%' THEN
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-2824-   146	    SELECT h.accuracy_m INTO v_claim_acc FROM public.token_claim_history h WHERE h.token = lower(p_observed_token) ORDER BY h.valid_from DESC LIMIT 1;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-2825-   147	    v_radius := public.gps_veto_radius_meters(p_accuracy, v_claim_acc);
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-2826-   148	  ELSE v_radius := GREATEST(5.0, public.range_radius_meters(v_range)); END IF;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-12877-   109	  -- 0048: an observed user who withdrew EITHER ble_proximity or precise_location
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-12878-   110	  -- must not generate new location-correlated evidence.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-12879-   111	  IF public.consent_withdrawn(v_observed_uid, 'ble_proximity')
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-12880-   112	     OR public.consent_withdrawn(v_observed_uid, 'precise_location') THEN
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-12881-   113	    RAISE EXCEPTION 'Unknown or expired beacon token' USING ERRCODE='22023'; END IF;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-12882-   114	
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-12883-   115	  INSERT INTO public.sightings AS s (
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-12884-   116	    observer_user_id, observed_token, observed_user_id, received_at,
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:12885:   117	    rssi, observed_at, observer_lat, observer_lon, range_type, observer_accuracy_m
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-12886-   118	  ) VALUES (
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-12887-   119	    v_uid, lower(p_observed_token), v_observed_uid, v_now,
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-12888-   120	    p_rssi, p_observed_at, p_lat, p_lon, v_range, p_accuracy
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-12889-   121	  )
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-12890-   122	  ON CONFLICT (observer_user_id, observed_token) DO UPDATE
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-12891-   123	    SET observed_at = p_observed_at, received_at = v_now, observed_user_id = v_observed_uid,
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-12892-   124	        rssi = CASE WHEN p_rssi > s.rssi THEN p_rssi ELSE s.rssi END,
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-12893-   125	        observer_lat = CASE WHEN p_rssi > s.rssi THEN p_lat ELSE s.observer_lat END,
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-12894-   126	        observer_lon = CASE WHEN p_rssi > s.rssi THEN p_lon ELSE s.observer_lon END,
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:12895:   127	        observer_accuracy_m = CASE WHEN p_rssi > s.rssi THEN p_accuracy ELSE s.observer_accuracy_m END,
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-12896-   128	        range_type = CASE WHEN p_rssi > s.rssi THEN v_range ELSE s.range_type END
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-12897-   129	  RETURNING id INTO v_id;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-12898-   130	
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-12899-   131	  v_window := LEAST(30, public.range_time_window_minutes(v_range));
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-12900-   132	  IF v_range::TEXT LIKE 'feet_%' THEN
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-12901-   133	    SELECT h.accuracy_m INTO v_claim_acc FROM public.token_claim_history h WHERE h.token = lower(p_observed_token) ORDER BY h.valid_from DESC LIMIT 1;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-12902-   134	    v_radius := public.gps_veto_radius_meters(p_accuracy, v_claim_acc);
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-12903-   135	  ELSE v_radius := GREATEST(5.0, public.range_radius_meters(v_range)); END IF;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-14321-  2650	
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-14322-  2651	  final String observedToken;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-14323-  2652	  final int rssi;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-14324-  2653	  final DateTime observedAt;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-14325-  2654	  final double? observerLat;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-14326-  2655	  final double? observerLon;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-14327-  2656	  final String rangeType;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-14328-  2657	
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:14329:  2658	  /// Reported GPS accuracy (metres) — sizes the server's plausibility veto.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-14330-  2659	  final double? observerAccuracyM;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-14331-  2660	}
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-14332-
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-14333-exec
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-14334-/bin/bash -lc "nl -ba lib/features/encounters/encounters_provider.dart | sed -n '1,260p'; rtk rg -n \"myEncountersProvider|_clearUserRuntime|invalidate\\(\" lib" in /home/hazypiff/in-range
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-14335- succeeded in 0ms:
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-14336-     1	import 'package:flutter_riverpod/flutter_riverpod.dart';
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-14337-     2	import 'package:in_range/core/config/app_config.dart';
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-24164-   109	  -- 0048: an observed user who withdrew EITHER ble_proximity or precise_location
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-24165-   110	  -- must not generate new location-correlated evidence.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-24166-   111	  IF public.consent_withdrawn(v_observed_uid, 'ble_proximity')
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-24167-   112	     OR public.consent_withdrawn(v_observed_uid, 'precise_location') THEN
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-24168-   113	    RAISE EXCEPTION 'Unknown or expired beacon token' USING ERRCODE='22023'; END IF;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-24169-   114	
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-24170-   115	  INSERT INTO public.sightings AS s (
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-24171-   116	    observer_user_id, observed_token, observed_user_id, received_at,
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:24172:   117	    rssi, observed_at, observer_lat, observer_lon, range_type, observer_accuracy_m
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-24173-   118	  ) VALUES (
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-24174-   119	    v_uid, lower(p_observed_token), v_observed_uid, v_now,
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-24175-   120	    p_rssi, p_observed_at, p_lat, p_lon, v_range, p_accuracy
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-24176-   121	  )
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-24177-   122	  ON CONFLICT (observer_user_id, observed_token) DO UPDATE
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-24178-   123	    SET observed_at = p_observed_at, received_at = v_now, observed_user_id = v_observed_uid,
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-24179-   124	        rssi = CASE WHEN p_rssi > s.rssi THEN p_rssi ELSE s.rssi END,
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-24180-   125	        observer_lat = CASE WHEN p_rssi > s.rssi THEN p_lat ELSE s.observer_lat END,
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-24181-   126	        observer_lon = CASE WHEN p_rssi > s.rssi THEN p_lon ELSE s.observer_lon END,
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:24182:   127	        observer_accuracy_m = CASE WHEN p_rssi > s.rssi THEN p_accuracy ELSE s.observer_accuracy_m END,
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-24183-   128	        range_type = CASE WHEN p_rssi > s.rssi THEN v_range ELSE s.range_type END
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-24184-   129	  RETURNING id INTO v_id;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-24185-   130	
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-24186-   131	  v_window := LEAST(30, public.range_time_window_minutes(v_range));
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-24187-   132	  IF v_range::TEXT LIKE 'feet_%' THEN
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-24188-   133	    SELECT h.accuracy_m INTO v_claim_acc FROM public.token_claim_history h WHERE h.token = lower(p_observed_token) ORDER BY h.valid_from DESC LIMIT 1;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-24189-   134	    v_radius := public.gps_veto_radius_meters(p_accuracy, v_claim_acc);
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-24190-   135	  ELSE v_radius := GREATEST(5.0, public.range_radius_meters(v_range)); END IF;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-25840-supabase/migrations/0046_withdrawal_enforcement.sql-291-  ORDER BY h.valid_from DESC LIMIT 1;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-25841-supabase/migrations/0046_withdrawal_enforcement.sql-292-  IF v_observed_uid IS NULL THEN RAISE EXCEPTION 'Unknown or expired beacon token' USING ERRCODE='22023'; END IF;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-25842-supabase/migrations/0046_withdrawal_enforcement.sql-293-  -- 0046: an observed user who withdrew BLE consent must not generate new
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-25843-supabase/migrations/0046_withdrawal_enforcement.sql-294-  -- evidence, even from a token preserved in history under a legal hold.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-25844-supabase/migrations/0046_withdrawal_enforcement.sql:295:  IF public.consent_withdrawn(v_observed_uid, 'ble_proximity') THEN RAISE EXCEPTION 'Unknown or expired beacon token' USING ERRCODE='22023'; END IF;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-25845-supabase/migrations/0046_withdrawal_enforcement.sql-296-
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-25846-supabase/migrations/0046_withdrawal_enforcement.sql-297-  INSERT INTO public.sightings AS s (
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-25847-supabase/migrations/0046_withdrawal_enforcement.sql-298-    observer_user_id, observed_token, observed_user_id, received_at,
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:25848:supabase/migrations/0046_withdrawal_enforcement.sql-299-    rssi, observed_at, observer_lat, observer_lon, range_type, observer_accuracy_m
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-25849---
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-25850-supabase/migrations/0046_withdrawal_enforcement.sql-589-        v_own.geo,
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-25851-supabase/migrations/0046_withdrawal_enforcement.sql-590-        LEAST(v_radius, public.range_radius_meters(lp.range_type))
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-25852-supabase/migrations/0046_withdrawal_enforcement.sql-591-      )
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-25853-supabase/migrations/0046_withdrawal_enforcement.sql-592-      AND public.is_discoverable_user(lp.user_id)
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-25854-supabase/migrations/0046_withdrawal_enforcement.sql:593:      AND NOT public.consent_withdrawn(lp.user_id, 'precise_location')
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-25855-supabase/migrations/0046_withdrawal_enforcement.sql-594-      AND NOT public.is_blocked_pair(v_uid, lp.user_id)
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-25856-supabase/migrations/0046_withdrawal_enforcement.sql-595-      AND public.preferences_compatible(v_uid, lp.user_id)
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28373-   109	  -- 0048: an observed user who withdrew EITHER ble_proximity or precise_location
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28374-   110	  -- must not generate new location-correlated evidence.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28375-   111	  IF public.consent_withdrawn(v_observed_uid, 'ble_proximity')
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28376-   112	     OR public.consent_withdrawn(v_observed_uid, 'precise_location') THEN
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28377-   113	    RAISE EXCEPTION 'Unknown or expired beacon token' USING ERRCODE='22023'; END IF;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28378-   114	
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28379-   115	  INSERT INTO public.sightings AS s (
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28380-   116	    observer_user_id, observed_token, observed_user_id, received_at,
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:28381:   117	    rssi, observed_at, observer_lat, observer_lon, range_type, observer_accuracy_m
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28382-   118	  ) VALUES (
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28383-   119	    v_uid, lower(p_observed_token), v_observed_uid, v_now,
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28384-   120	    p_rssi, p_observed_at, p_lat, p_lon, v_range, p_accuracy
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28385-   121	  )
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28386-   122	  ON CONFLICT (observer_user_id, observed_token) DO UPDATE
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28387-   123	    SET observed_at = p_observed_at, received_at = v_now, observed_user_id = v_observed_uid,
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28388-   124	        rssi = CASE WHEN p_rssi > s.rssi THEN p_rssi ELSE s.rssi END,
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28389-   125	        observer_lat = CASE WHEN p_rssi > s.rssi THEN p_lat ELSE s.observer_lat END,
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28390-   126	        observer_lon = CASE WHEN p_rssi > s.rssi THEN p_lon ELSE s.observer_lon END,
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:28391:   127	        observer_accuracy_m = CASE WHEN p_rssi > s.rssi THEN p_accuracy ELSE s.observer_accuracy_m END,
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28392-   128	        range_type = CASE WHEN p_rssi > s.rssi THEN v_range ELSE s.range_type END
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28393-   129	  RETURNING id INTO v_id;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28394-   130	
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28395-   131	  v_window := LEAST(30, public.range_time_window_minutes(v_range));
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28396-   132	  IF v_range::TEXT LIKE 'feet_%' THEN
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28397-   133	    SELECT h.accuracy_m INTO v_claim_acc FROM public.token_claim_history h WHERE h.token = lower(p_observed_token) ORDER BY h.valid_from DESC LIMIT 1;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28398-   134	    v_radius := public.gps_veto_radius_meters(p_accuracy, v_claim_acc);
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-28399-   135	  ELSE v_radius := GREATEST(5.0, public.range_radius_meters(v_range)); END IF;
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30935-
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30936-- **C-SQL-3 — severity and legal-hold-breaking fix.**  
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30937-  **Report:** Critical permanent map; add one unconditional delete.  
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30938-  **True:** The retention omission is real, but both `beacon_token_batch` and cross-user RSSI access are unavailable to ordinary clients: the batch table is RPC-only at [0031:40](/home/hazypiff/in-range/supabase/migrations/0031_server_issued_token_batches.sql:40), while RSSI users can read only their own rows at [0056:72](/home/hazypiff/in-range/supabase/migrations/0056_calibration_rssi_samples.sql:72). This is High privacy/retention risk, not a current Critical client exploit. The proposed unconditional delete also violates the cleanup function’s legal-hold invariant. The hold branch at [0059:489](/home/hazypiff/in-range/supabase/migrations/0059_proximity_wake_producer.sql:489) needs `NOT has_legal_hold(user_id)`; only the no-hold branch may delete unconditionally.  
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30939-  **Confidence:** Certain.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30940-
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30941-- **C-SQL-4 — severity and one invalid fix option.**  
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30942-  **Report:** Critical; either reject location-less claims or compare observer locations.  
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:30943:  **True:** The missing GPS veto is real, but reciprocity still remains at [0053:189](/home/hazypiff/in-range/supabase/migrations/0053_late_evidence_tolerance.sql:189), so this is High. Rejecting all location-less claims would disable the locked-phone batch-preclaim path that migration 0060 deliberately introduced. The observer-versus-observer fallback is the viable fix.  
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30944-  **Confidence:** Certain.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30945-
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30946-- **C-CONSENT-1 — severity and wrong consent purposes.**  
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30947-  **Report:** Critical; use `ble_proximity` for RSSI and `precise_location` for wake/venue writes.  
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30948-  **True:** The missing checks are real, but calibration and subtle wake are OFF by default at [app_config.dart:138](/home/hazypiff/in-range/lib/core/config/app_config.dart:138) and [app_config.dart:178](/home/hazypiff/in-range/lib/core/config/app_config.dart:178), and proximity-wake is undeployed. This is a High rollout/compliance blocker rather than a current Critical exploit. The RSSI specification explicitly says general-user raw RSSI is a new consent category at [CLOUD_RSSI_UPLOAD_SPEC.md:26](/home/hazypiff/in-range/docs/CLOUD_RSSI_UPLOAD_SPEC.md:26); `ble_proximity` is insufficient. Closed-app venue/wake processing maps to `background_location`, described at [consent_screen.dart:95](/home/hazypiff/in-range/lib/features/consent/consent_screen.dart:95), rather than simply `precise_location`. Converting venue writes to an RPC also requires revoking the existing direct DML grant and permissive RLS policy at [0057:60](/home/hazypiff/in-range/supabase/migrations/0057_subtle_wake_support.sql:60) and [0058:34](/home/hazypiff/in-range/supabase/migrations/0058_subtle_wake_privacy.sql:34), or clients retain a bypass.  
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30949-  The latest `require_consent` is migration 0045, not 0039; it already honors explicit withdrawal even while `enforce_consent=0` at [0045:57](/home/hazypiff/in-range/supabase/migrations/0045_withdrawal_effectiveness.sql:57).  
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30950-  **Confidence:** Certain.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-30951-
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-31034-
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-31035-- **C-SQL-3 — severity and legal-hold-breaking fix.**  
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-31036-  **Report:** Critical permanent map; add one unconditional delete.  
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-31037-  **True:** The retention omission is real, but both `beacon_token_batch` and cross-user RSSI access are unavailable to ordinary clients: the batch table is RPC-only at [0031:40](/home/hazypiff/in-range/supabase/migrations/0031_server_issued_token_batches.sql:40), while RSSI users can read only their own rows at [0056:72](/home/hazypiff/in-range/supabase/migrations/0056_calibration_rssi_samples.sql:72). This is High privacy/retention risk, not a current Critical client exploit. The proposed unconditional delete also violates the cleanup function’s legal-hold invariant. The hold branch at [0059:489](/home/hazypiff/in-range/supabase/migrations/0059_proximity_wake_producer.sql:489) needs `NOT has_legal_hold(user_id)`; only the no-hold branch may delete unconditionally.  
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-31038-  **Confidence:** Certain.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-31039-
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-31040-- **C-SQL-4 — severity and one invalid fix option.**  
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-31041-  **Report:** Critical; either reject location-less claims or compare observer locations.  
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md:31042:  **True:** The missing GPS veto is real, but reciprocity still remains at [0053:189](/home/hazypiff/in-range/supabase/migrations/0053_late_evidence_tolerance.sql:189), so this is High. Rejecting all location-less claims would disable the locked-phone batch-preclaim path that migration 0060 deliberately introduced. The observer-versus-observer fallback is the viable fix.  
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-31043-  **Confidence:** Certain.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-31044-
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-31045-- **C-CONSENT-1 — severity and wrong consent purposes.**  
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-31046-  **Report:** Critical; use `ble_proximity` for RSSI and `precise_location` for wake/venue writes.  
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-31047-  **True:** The missing checks are real, but calibration and subtle wake are OFF by default at [app_config.dart:138](/home/hazypiff/in-range/lib/core/config/app_config.dart:138) and [app_config.dart:178](/home/hazypiff/in-range/lib/core/config/app_config.dart:178), and proximity-wake is undeployed. This is a High rollout/compliance blocker rather than a current Critical exploit. The RSSI specification explicitly says general-user raw RSSI is a new consent category at [CLOUD_RSSI_UPLOAD_SPEC.md:26](/home/hazypiff/in-range/docs/CLOUD_RSSI_UPLOAD_SPEC.md:26); `ble_proximity` is insufficient. Closed-app venue/wake processing maps to `background_location`, described at [consent_screen.dart:95](/home/hazypiff/in-range/lib/features/consent/consent_screen.dart:95), rather than simply `precise_location`. Converting venue writes to an RPC also requires revoking the existing direct DML grant and permissive RLS policy at [0057:60](/home/hazypiff/in-range/supabase/migrations/0057_subtle_wake_support.sql:60) and [0058:34](/home/hazypiff/in-range/supabase/migrations/0058_subtle_wake_privacy.sql:34), or clients retain a bypass.  
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-31048-  The latest `require_consent` is migration 0045, not 0039; it already honors explicit withdrawal even while `enforce_consent=0` at [0045:57](/home/hazypiff/in-range/supabase/migrations/0045_withdrawal_effectiveness.sql:57).  
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-31049-  **Confidence:** Certain.
docs/research/2026-08-01-hardening/transcripts/codex_consensus_r1.md-31050-

exec
/bin/bash -lc "rtk rg -n -C 3 \"(GRANT|REVOKE).*correlate_encounter|correlate_encounter.*(GRANT|REVOKE)\" supabase/migrations
rtk rg -n \"ALTER TABLE public\\.sightings.*(DROP NOT NULL|SET NOT NULL)|ALTER COLUMN observer_(lat|lon)\" supabase/migrations
nl -ba supabase/migrations/0019_beta_security_hardening.sql | sed -n '2484,2560p'
nl -ba supabase/migrations/0053_late_evidence_tolerance.sql | sed -n '80,142p'" in /home/hazypiff/in-range
 succeeded in 0ms:
  2484	-- -----------------------------------------------------------------------------
  2485	-- 9. Explicit function allowlists (CREATE FUNCTION grants PUBLIC by default)
  2486	-- -----------------------------------------------------------------------------
  2487	
  2488	DO $$
  2489	DECLARE r RECORD;
  2490	BEGIN
  2491	  FOR r IN
  2492	    SELECT p.oid::regprocedure AS sig
  2493	    FROM pg_proc p
  2494	    JOIN pg_namespace n ON n.oid = p.pronamespace
  2495	    WHERE n.nspname = 'public'
  2496	      AND p.proname = ANY (ARRAY[
  2497	        'claim_token', 'release_token', 'record_sighting',
  2498	        'correlate_encounter', 'get_my_encounters',
  2499	        'record_location_ping', 'correlate_miles_encounters', 'get_locals_feed',
  2500	        'batch_correlate_recent_pings', 'range_radius_meters',
  2501	        'range_time_window_minutes', 'preferences_compatible', '_pref_matches',
  2502	        'swipe_encounter', 'swipe_user', 'get_my_matches', 'get_who_liked_you',
  2503	        'send_message', 'mark_messages_read', 'get_match_profile',
  2504	        'block_user', 'unblock_user', 'report_user', 'is_blocked_pair',
  2505	        'upsert_my_profile', 'get_my_profile', 'set_account_paused',
  2506	        'set_incognito', 'request_account_deletion', 'delete_my_location_history',
  2507	        'register_push_token', 'unregister_push_token',
  2508	        'submit_photo_for_verification', 'complete_ai_photo_review',
  2509	        'decide_photo_verification', 'stub_auto_approve_photo',
  2510	        'has_active_boost', 'is_subscriber',
  2511	        'cleanup_ephemeral_data', 'expire_feet_encounters',
  2512	        'expire_idle_matches', 'queue_revealed_encounter_alerts',
  2513	        'queue_expiring_encounter_alerts', 'run_maintenance',
  2514	        'claim_notification_batch', 'log_ai_run', 'complete_ai_run',
  2515	        'log_ai_event', 'submit_ai_feedback', 'backend_health',
  2516	        'encounter_reveal_delay_hours', 'is_discoverable_user',
  2517	        'current_user_can_discover', 'can_access_match',
  2518	        'can_view_profile_photos', 'can_modify_profile_photo',
  2519	        'handle_new_user', 'handle_updated_at', 'notify_on_new_encounter',
  2520	        'sync_subscription_flags'
  2521	      ])
  2522	  LOOP
  2523	    EXECUTE format(
  2524	      'REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated, service_role',
  2525	      r.sig
  2526	    );
  2527	  END LOOP;
  2528	END $$;
  2529	
  2530	DO $$
  2531	DECLARE r RECORD;
  2532	BEGIN
  2533	  FOR r IN
  2534	    SELECT p.oid::regprocedure AS sig
  2535	    FROM pg_proc p
  2536	    JOIN pg_namespace n ON n.oid = p.pronamespace
  2537	    WHERE n.nspname = 'public'
  2538	      AND p.proname = ANY (ARRAY[
  2539	        'claim_token', 'release_token', 'record_sighting', 'get_my_encounters',
  2540	        'record_location_ping', 'get_locals_feed', 'swipe_encounter',
  2541	        'swipe_user', 'get_my_matches', 'get_who_liked_you', 'send_message',
  2542	        'mark_messages_read', 'get_match_profile', 'block_user', 'unblock_user',
  2543	        'report_user', 'upsert_my_profile', 'get_my_profile',
  2544	        'set_account_paused', 'set_incognito', 'request_account_deletion',
  2545	        'delete_my_location_history', 'register_push_token',
  2546	        'unregister_push_token', 'submit_photo_for_verification',
  2547	        'submit_ai_feedback', 'backend_health', 'encounter_reveal_delay_hours',
  2548	        'can_access_match', 'can_view_profile_photos', 'can_modify_profile_photo'
  2549	      ])
  2550	  LOOP
  2551	    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', r.sig);
  2552	  END LOOP;
  2553	END $$;
  2554	
  2555	DO $$
  2556	DECLARE r RECORD;
  2557	BEGIN
  2558	  FOR r IN
  2559	    SELECT p.oid::regprocedure AS sig
  2560	    FROM pg_proc p
    80	  -- precise_location must not keep doing so via Beacon.
    81	  IF public.consent_withdrawn(v_uid, 'precise_location') THEN
    82	    RAISE EXCEPTION 'Location sharing was turned off' USING ERRCODE='42501'; END IF;
    83	  IF p_observed_token IS NULL OR lower(p_observed_token) !~ '^[0-9a-f]{32}$' THEN RAISE EXCEPTION 'Invalid beacon token' USING ERRCODE='22023'; END IF;
    84	  -- 0053: was a fixed 10 min — a locked iPhone's natively-buffered sightings
    85	  -- flush with their ORIGINAL capture timestamps when the user wakes it.
    86	  IF p_observed_at IS NULL OR p_observed_at < v_now - v_late OR p_observed_at > v_now + INTERVAL '1 minute' THEN RAISE EXCEPTION 'Invalid sighting time' USING ERRCODE='22023'; END IF;
    87	  IF p_rssi IS NULL OR p_rssi NOT BETWEEN -127 AND 20 THEN RAISE EXCEPTION 'Invalid RSSI' USING ERRCODE='22023'; END IF;
    88	  IF p_lat IS NULL OR p_lon IS NULL THEN RAISE EXCEPTION 'Fresh coordinates are required' USING ERRCODE='22023'; END IF;
    89	  IF p_lat NOT BETWEEN -90 AND 90 OR p_lon NOT BETWEEN -180 AND 180 THEN RAISE EXCEPTION 'Invalid coordinates' USING ERRCODE='22023'; END IF;
    90	  IF p_accuracy IS NOT NULL AND (p_accuracy < 0 OR p_accuracy > 10000) THEN RAISE EXCEPTION 'Invalid accuracy' USING ERRCODE='22023'; END IF;
    91	
    92	  INSERT INTO public.sighting_call_rate AS r (user_id, window_start, calls) VALUES (v_uid, v_now, 1)
    93	  ON CONFLICT (user_id) DO UPDATE
    94	    SET window_start = CASE WHEN r.window_start < v_now - INTERVAL '1 minute' THEN v_now ELSE r.window_start END,
    95	        calls = CASE WHEN r.window_start < v_now - INTERVAL '1 minute' THEN 1 ELSE r.calls + 1 END
    96	  RETURNING calls INTO v_calls;
    97	  IF v_calls > 120 THEN RAISE EXCEPTION 'Sighting rate limit' USING ERRCODE='54000'; END IF;
    98	
    99	  -- Resolve who this token belongs to (history-aware; survives rotation).
   100	  -- 0053: grace widened from 2 min to the late-evidence window — a flushed
   101	  -- sighting may reference a token that expired while the phone slept.
   102	  SELECT h.user_id INTO v_observed_uid FROM public.token_claim_history h
   103	  WHERE h.token = lower(p_observed_token) AND h.user_id <> v_uid
   104	    AND h.valid_until > v_now - v_late
   105	  ORDER BY h.valid_from DESC LIMIT 1;
   106	  IF v_observed_uid IS NULL THEN RAISE EXCEPTION 'Unknown or expired beacon token' USING ERRCODE='22023'; END IF;
   107	  -- 0046: an observed user who withdrew BLE consent must not generate new
   108	  -- evidence, even from a token preserved in history under a legal hold.
   109	  -- 0048: an observed user who withdrew EITHER ble_proximity or precise_location
   110	  -- must not generate new location-correlated evidence.
   111	  IF public.consent_withdrawn(v_observed_uid, 'ble_proximity')
   112	     OR public.consent_withdrawn(v_observed_uid, 'precise_location') THEN
   113	    RAISE EXCEPTION 'Unknown or expired beacon token' USING ERRCODE='22023'; END IF;
   114	
   115	  INSERT INTO public.sightings AS s (
   116	    observer_user_id, observed_token, observed_user_id, received_at,
   117	    rssi, observed_at, observer_lat, observer_lon, range_type, observer_accuracy_m
   118	  ) VALUES (
   119	    v_uid, lower(p_observed_token), v_observed_uid, v_now,
   120	    p_rssi, p_observed_at, p_lat, p_lon, v_range, p_accuracy
   121	  )
   122	  ON CONFLICT (observer_user_id, observed_token) DO UPDATE
   123	    SET observed_at = p_observed_at, received_at = v_now, observed_user_id = v_observed_uid,
   124	        rssi = CASE WHEN p_rssi > s.rssi THEN p_rssi ELSE s.rssi END,
   125	        observer_lat = CASE WHEN p_rssi > s.rssi THEN p_lat ELSE s.observer_lat END,
   126	        observer_lon = CASE WHEN p_rssi > s.rssi THEN p_lon ELSE s.observer_lon END,
   127	        observer_accuracy_m = CASE WHEN p_rssi > s.rssi THEN p_accuracy ELSE s.observer_accuracy_m END,
   128	        range_type = CASE WHEN p_rssi > s.rssi THEN v_range ELSE s.range_type END
   129	  RETURNING id INTO v_id;
   130	
   131	  v_window := LEAST(30, public.range_time_window_minutes(v_range));
   132	  IF v_range::TEXT LIKE 'feet_%' THEN
   133	    SELECT h.accuracy_m INTO v_claim_acc FROM public.token_claim_history h WHERE h.token = lower(p_observed_token) ORDER BY h.valid_from DESC LIMIT 1;
   134	    v_radius := public.gps_veto_radius_meters(p_accuracy, v_claim_acc);
   135	  ELSE v_radius := GREATEST(5.0, public.range_radius_meters(v_range)); END IF;
   136	
   137	  PERFORM public.correlate_encounter(lower(p_observed_token), p_lat, p_lon, v_radius, v_window);
   138	  RETURN v_id;
   139	END;
   140	$function$;
   141	
   142	-- ---------------------------------------------------------------------------

exec
/bin/bash -lc "rtk rg -n -C 8 \"drain.*sighting|buffered.*sighting|native.*sighting|_recordLocalSighting\\(\" lib/features/beacon/beacon_service.dart ios/Runner | head -n 500
nl -ba lib/features/beacon/beacon_service.dart | sed -n '280,390p;900,1060p;2120,2228p'" in /home/hazypiff/in-range
 succeeded in 0ms:
lib/features/beacon/beacon_service.dart-54-        _correlationSalt = hmacSecret,
lib/features/beacon/beacon_service.dart-55-        _rotationWindow = rotationWindow,
lib/features/beacon/beacon_service.dart-56-        venueAnchors = VenueAnchorService(
lib/features/beacon/beacon_service.dart-57-          persistenceKey: () => 'inrange.venue_anchors.v1',
lib/features/beacon/beacon_service.dart-58-          readPersisted: (key) async => sharedPreferences?.getString(key),
lib/features/beacon/beacon_service.dart-59-          writePersisted: (key, value) async =>
lib/features/beacon/beacon_service.dart-60-              await sharedPreferences?.setString(key, value),
lib/features/beacon/beacon_service.dart-61-        ) {
lib/features/beacon/beacon_service.dart:62:    // Feed native/Dart location fixes into the sighting cache. The fix is used
lib/features/beacon/beacon_service.dart-63-    // for server radius gates and refreshes the cache without a fresh
lib/features/beacon/beacon_service.dart-64-    // Geolocator call per sighting. GPS is still not a proximity classifier.
lib/features/beacon/beacon_service.dart-65-    locationKeepalive.onFix = _onLocationFix;
lib/features/beacon/beacon_service.dart-66-
lib/features/beacon/beacon_service.dart-67-    // Subtle-wake path (docs/SUBTLE_TRACKING_ARCHITECTURE.md): each wake turns
lib/features/beacon/beacon_service.dart-68-    // into a cache refresh + a bounded BLE burst; anchor edits propagate to
lib/features/beacon/beacon_service.dart-69-    // the native coordinator as region descriptors. The BSSID salt MUST be
lib/features/beacon/beacon_service.dart-70-    // the correlation salt so hints match the venue matcher's fingerprints.
lib/features/beacon/beacon_service.dart-302-      debugPrint('Native session restore failed: $e');
lib/features/beacon/beacon_service.dart-303-      return false;
lib/features/beacon/beacon_service.dart-304-    }
lib/features/beacon/beacon_service.dart-305-  }
lib/features/beacon/beacon_service.dart-306-
lib/features/beacon/beacon_service.dart-307-  bool _nativeDrainInFlight = false;
lib/features/beacon/beacon_service.dart-308-  bool _nativeDrainPending = false;
lib/features/beacon/beacon_service.dart-309-
lib/features/beacon/beacon_service.dart:310:  /// Pull-and-ack drain of the native background buffer: sightings are
lib/features/beacon/beacon_service.dart-311-  /// ingested with their original capture timestamps (migration 0053's
lib/features/beacon/beacon_service.dart-312-  /// late-evidence window covers them server-side) and only then acked, so
lib/features/beacon/beacon_service.dart-313-  /// a crash mid-drain re-delivers instead of losing them. Serialized: two
lib/features/beacon/beacon_service.dart:314:  /// concurrent drains would ack overlapping counts and delete sightings
lib/features/beacon/beacon_service.dart-315-  /// neither ingested (audit 2026-07-25 round 3); a drain requested while
lib/features/beacon/beacon_service.dart-316-  /// one runs is folded into a follow-up pass.
lib/features/beacon/beacon_service.dart-317-  Future<void> _drainNativeBuffer() async {
lib/features/beacon/beacon_service.dart-318-    if (!_isOn) return;
lib/features/beacon/beacon_service.dart-319-    // iOS-only: the buffer lives in BackgroundBeacon.swift. There is no Android
lib/features/beacon/beacon_service.dart-320-    // implementation of io.inrange/background_beacon, so on Android every call
lib/features/beacon/beacon_service.dart-321-    // threw MissingPluginException, got caught, and printed
lib/features/beacon/beacon_service.dart-322-    // "BackgroundBeacon drain failed: ..." on EVERY beacon start (observed on an
lib/features/beacon/beacon_service.dart-627-    } catch (e) {
lib/features/beacon/beacon_service.dart-628-      debugPrint('onBeaconStopped callback error: $e');
lib/features/beacon/beacon_service.dart-629-    }
lib/features/beacon/beacon_service.dart-630-  }
lib/features/beacon/beacon_service.dart-631-
lib/features/beacon/beacon_service.dart-632-  Future<void> _rotateToken(String rangeType) async {
lib/features/beacon/beacon_service.dart-633-    final gen = _sessionGeneration;
lib/features/beacon/beacon_service.dart-634-    try {
lib/features/beacon/beacon_service.dart:635:      // Drain buffered sightings FIRST: the server keeps one claim per user,
lib/features/beacon/beacon_service.dart-636-      // so rows still referencing the outgoing token would fail after the
lib/features/beacon/beacon_service.dart-637-      // new claim replaces it (audit 2026-07-13 #3).
lib/features/beacon/beacon_service.dart-638-      await _flushSightings();
lib/features/beacon/beacon_service.dart-639-      if (!_isOn || gen != _sessionGeneration) return;
lib/features/beacon/beacon_service.dart-640-      await _refreshClaim(rangeType: rangeType);
lib/features/beacon/beacon_service.dart-641-      // A rotation that straddled turnOffBeacon must not resurrect the
lib/features/beacon/beacon_service.dart-642-      // claim or the advertiser.
lib/features/beacon/beacon_service.dart-643-      if (!_isOn || gen != _sessionGeneration) {
lib/features/beacon/beacon_service.dart-1398-    }
lib/features/beacon/beacon_service.dart-1399-  }
lib/features/beacon/beacon_service.dart-1400-
lib/features/beacon/beacon_service.dart-1401-  /// Authoritative re-read of the native BLE state. Public so the resume path,
lib/features/beacon/beacon_service.dart-1402-  /// and any future caller, can force reconciliation.
lib/features/beacon/beacon_service.dart-1403-  ///
lib/features/beacon/beacon_service.dart-1404-  /// Needed because `onBleState` is a push and a push issued while the app is
lib/features/beacon/beacon_service.dart-1405-  /// backgrounded is accepted then silently dropped by a suspended engine —
lib/features/beacon/beacon_service.dart:1406:  /// exactly the hazard the native sighting BUFFER exists to work around
lib/features/beacon/beacon_service.dart-1407-  /// (drainBufferedSightings + ack, audit 2026-07-25 round 3). State has no
lib/features/beacon/beacon_service.dart-1408-  /// buffer, so it has to be pulled.
lib/features/beacon/beacon_service.dart-1409-  ///
lib/features/beacon/beacon_service.dart-1410-  /// A null answer is UNKNOWN and is never treated as healthy: nothing
lib/features/beacon/beacon_service.dart-1411-  /// pessimistic is cleared on null.
lib/features/beacon/beacon_service.dart-1412-  Future<NativeBleState?> refreshNativeBleState() async {
lib/features/beacon/beacon_service.dart-1413-    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return null;
lib/features/beacon/beacon_service.dart-1414-    final state = await _bgBeacon.readBleState();
lib/features/beacon/beacon_service.dart-2172-  /// session (if any) is torn down immediately. No-op off-iOS / no session.
lib/features/beacon/beacon_service.dart-2173-  void dropPeer(String tokenHex) {
lib/features/beacon/beacon_service.dart-2174-    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
lib/features/beacon/beacon_service.dart-2175-      unawaited(_bgBeacon.dropPeer(tokenHex));
lib/features/beacon/beacon_service.dart-2176-    }
lib/features/beacon/beacon_service.dart-2177-  }
lib/features/beacon/beacon_service.dart-2178-
lib/features/beacon/beacon_service.dart-2179-  /// Single ingest point for a foreign token sample — scan results and the
lib/features/beacon/beacon_service.dart:2180:  /// iOS native carrier's sightings (W4) both land here, so the self-sight
lib/features/beacon/beacon_service.dart-2181-  /// guard, estimator, calibration log and sighting bookkeeping stay one
lib/features/beacon/beacon_service.dart-2182-  /// code path.
lib/features/beacon/beacon_service.dart-2183-  void _ingestForeignSample(String hexId, int rssi, AdvertPower power,
lib/features/beacon/beacon_service.dart-2184-      {DateTime? at}) {
lib/features/beacon/beacon_service.dart-2185-    // Filter ALL of our own tokens, not just the current one — a leaked
lib/features/beacon/beacon_service.dart-2186-    // advertiser from a prior beacon session kept broadcasting the OLD
lib/features/beacon/beacon_service.dart-2187-    // token after off→on, and we self-sighted it at a rock-constant RSSI
lib/features/beacon/beacon_service.dart-2188-    // for an entire field test (2026-07-13 walk).
lib/features/beacon/beacon_service.dart-2213-      // self-calibration finding (A9/B9) needs and which is not recoverable
lib/features/beacon/beacon_service.dart-2214-      // after the walk.
lib/features/beacon/beacon_service.dart-2215-      _bumpBin(_rssiHist, (rssi / 5).floor() * 5);
lib/features/beacon/beacon_service.dart-2216-      debugPrint(
lib/features/beacon/beacon_service.dart-2217-          'Advert corr=${hexId.substring(0, 8)} rssi=$rssi pw=${power == AdvertPower.medium ? "M" : "H"} rx=$_receiverTag');
lib/features/beacon/beacon_service.dart-2218-    }
lib/features/beacon/beacon_service.dart-2219-
lib/features/beacon/beacon_service.dart-2220-    _lastForeignScanAt = DateTime.now();
lib/features/beacon/beacon_service.dart:2221:    _recordLocalSighting(hexId, rssi, at: at);
lib/features/beacon/beacon_service.dart-2222-  }
lib/features/beacon/beacon_service.dart-2223-
lib/features/beacon/beacon_service.dart-2224-  double? _cachedLat;
lib/features/beacon/beacon_service.dart-2225-  double? _cachedLon;
lib/features/beacon/beacon_service.dart-2226-  double? _cachedAccuracy;
lib/features/beacon/beacon_service.dart-2227-  DateTime? _cachedLocAt;
lib/features/beacon/beacon_service.dart-2228-  Timer? _locationRefreshTimer;
lib/features/beacon/beacon_service.dart-2229-
lib/features/beacon/beacon_service.dart-2230-  final Map<String, DateTime> _lastSightingAt = {};
lib/features/beacon/beacon_service.dart-2231-  static const _sightingMinInterval = Duration(seconds: 5);
lib/features/beacon/beacon_service.dart-2232-
lib/features/beacon/beacon_service.dart:2233:  void _recordLocalSighting(String observedCorrelationIdHex, int rssi,
lib/features/beacon/beacon_service.dart-2234-      {DateTime? at}) {
lib/features/beacon/beacon_service.dart-2235-    final now = DateTime.now();
lib/features/beacon/beacon_service.dart-2236-    final last = _lastSightingAt[observedCorrelationIdHex];
lib/features/beacon/beacon_service.dart-2237-    if (last != null && now.difference(last) < _sightingMinInterval) {
lib/features/beacon/beacon_service.dart-2238-      return;
lib/features/beacon/beacon_service.dart-2239-    }
lib/features/beacon/beacon_service.dart-2240-    _lastSightingAt[observedCorrelationIdHex] = now;
lib/features/beacon/beacon_service.dart-2241-    if (_lastSightingAt.length > 1000) {
lib/features/beacon/beacon_service.dart-2257-        ? estimated
lib/features/beacon/beacon_service.dart-2258-        : range;
lib/features/beacon/beacon_service.dart-2259-    final record = SightingRecord(
lib/features/beacon/beacon_service.dart-2260-      observedToken: observedCorrelationIdHex,
lib/features/beacon/beacon_service.dart-2261-      rssi: rssi,
lib/features/beacon/beacon_service.dart-2262-      observerLat: _cachedLat,
lib/features/beacon/beacon_service.dart-2263-      observerLon: _cachedLon,
lib/features/beacon/beacon_service.dart-2264-      observerAccuracyM: _cachedAccuracy,
lib/features/beacon/beacon_service.dart:2265:      // A locked iPhone's natively-buffered sighting flushes minutes after
lib/features/beacon/beacon_service.dart-2266-      // capture; the server (0053) accepts and stores the TRUE capture time,
lib/features/beacon/beacon_service.dart-2267-      // so pass it through instead of the flush time.
lib/features/beacon/beacon_service.dart-2268-      observedAt: at ?? now,
lib/features/beacon/beacon_service.dart-2269-      rangeType: uploadRange,
lib/features/beacon/beacon_service.dart-2270-    );
lib/features/beacon/beacon_service.dart-2271-
lib/features/beacon/beacon_service.dart-2272-    // Keep one COHERENT best-evidence record per corr: RSSI, band, time,
lib/features/beacon/beacon_service.dart-2273-    // location and accuracy all come from the SAME physical sample. Previously
ios/Runner/BackgroundBeacon.swift-515-  private func notifyBufferReady() {
ios/Runner/BackgroundBeacon.swift-516-    guard let ch = channel,
ios/Runner/BackgroundBeacon.swift-517-          UIApplication.shared.applicationState == .active,
ios/Runner/BackgroundBeacon.swift-518-          let buf = defaults.array(forKey: Self.keyBuffer) as? [[String: Any]],
ios/Runner/BackgroundBeacon.swift-519-          !buf.isEmpty else { return }
ios/Runner/BackgroundBeacon.swift-520-    ch.invokeMethod("onBufferedSightingsReady", arguments: nil)
ios/Runner/BackgroundBeacon.swift-521-  }
ios/Runner/BackgroundBeacon.swift-522-
ios/Runner/BackgroundBeacon.swift:523:  /// Drops the first [count] buffered sightings — called only after Dart
ios/Runner/BackgroundBeacon.swift-524-  /// confirms ingestion of that many drained entries.
ios/Runner/BackgroundBeacon.swift-525-  private func ackBuffer(_ count: Int) {
ios/Runner/BackgroundBeacon.swift-526-    guard count > 0,
ios/Runner/BackgroundBeacon.swift-527-          var buf = defaults.array(forKey: Self.keyBuffer) as? [[String: Any]],
ios/Runner/BackgroundBeacon.swift-528-          !buf.isEmpty else { return }
ios/Runner/BackgroundBeacon.swift-529-    buf.removeFirst(min(count, buf.count))
ios/Runner/BackgroundBeacon.swift-530-    if buf.isEmpty {
ios/Runner/BackgroundBeacon.swift-531-      defaults.removeObject(forKey: Self.keyBuffer)
   280	  /// secrets, or a PAUSED account — "hidden from new encounters" must not
   281	  /// advertise) the native side is stopped so nothing advertises behind the
   282	  /// user's back. Returns true when a session was restored. No-op off iOS
   283	  /// and when the beacon is already on.
   284	  Future<bool> restoreNativeSession() async {
   285	    if (_isOn) return false;
   286	    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return false;
   287	    if (!await _bgBeacon.isNativeEnabled()) return false;
   288	    if (_userId.trim().isEmpty ||
   289	        !AppConfig.hasCryptoSecrets ||
   290	        isAccountPaused?.call() == true) {
   291	      debugPrint('Native beacon active but session not restorable — stopping');
   292	      await _bgBeacon.stop();
   293	      return false;
   294	    }
   295	    debugPrint('Restoring beacon session from native state');
   296	    try {
   297	      // Range is a fixed product constant (SelectedRangeController), so no
   298	      // persisted choice is needed to resume.
   299	      await turnOnBeacon(rangeType: 'feet_60');
   300	      return true;
   301	    } catch (e) {
   302	      debugPrint('Native session restore failed: $e');
   303	      return false;
   304	    }
   305	  }
   306	
   307	  bool _nativeDrainInFlight = false;
   308	  bool _nativeDrainPending = false;
   309	
   310	  /// Pull-and-ack drain of the native background buffer: sightings are
   311	  /// ingested with their original capture timestamps (migration 0053's
   312	  /// late-evidence window covers them server-side) and only then acked, so
   313	  /// a crash mid-drain re-delivers instead of losing them. Serialized: two
   314	  /// concurrent drains would ack overlapping counts and delete sightings
   315	  /// neither ingested (audit 2026-07-25 round 3); a drain requested while
   316	  /// one runs is folded into a follow-up pass.
   317	  Future<void> _drainNativeBuffer() async {
   318	    if (!_isOn) return;
   319	    // iOS-only: the buffer lives in BackgroundBeacon.swift. There is no Android
   320	    // implementation of io.inrange/background_beacon, so on Android every call
   321	    // threw MissingPluginException, got caught, and printed
   322	    // "BackgroundBeacon drain failed: ..." on EVERY beacon start (observed on an
   323	    // S9, 2026-07-26 bench). Harmless, but it put an alarming line in the walk
   324	    // logs we are about to read closely — and a real drain failure would have
   325	    // been indistinguishable from the routine one.
   326	    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
   327	    if (_nativeDrainInFlight) {
   328	      _nativeDrainPending = true;
   329	      return;
   330	    }
   331	    _nativeDrainInFlight = true;
   332	    try {
   333	      do {
   334	        _nativeDrainPending = false;
   335	        final items = await _bgBeacon.drainBufferedSightings();
   336	        if (items.isEmpty || !_isOn) return;
   337	        for (final s in items) {
   338	          final token = s['token'], rssi = s['rssi'], ts = s['ts'];
   339	          if (token is String && token.length == 32 && rssi is int) {
   340	            final at = ts is int
   341	                ? DateTime.fromMillisecondsSinceEpoch(ts)
   342	                : DateTime.now();
   343	            _ingestForeignSample(token, rssi, AdvertPower.high, at: at);
   344	          }
   345	        }
   346	        await _bgBeacon.ackBufferedSightings(items.length);
   347	      } while (_nativeDrainPending && _isOn);
   348	    } finally {
   349	      _nativeDrainInFlight = false;
   350	    }
   351	  }
   352	
   353	  Future<void> turnOnBeacon({required String rangeType}) async {
   354	    if (_isOn) return;
   355	    if (!AppConfig.hasCryptoSecrets) {
   356	      debugPrint(
   357	        'Beacon refused: INRANGE_HMAC_SECRET / INRANGE_USER_ID_SECRET missing. '
   358	        'Set these in .env — no hardcoded fallback is shipped.',
   359	      );
   360	      throw StateError('Missing crypto secrets; cannot start beacon.');
   361	    }
   362	    if (_userId.trim().isEmpty) {
   363	      throw StateError('Sign in before starting the beacon.');
   364	    }
   365	    _currentRangeType = rangeType;
   366	    final gen = ++_sessionGeneration;
   367	    _scanningWanted = true;
   368	    _advertisingWanted = true;
   369	
   370	    try {
   371	      await _refreshClaim(rangeType: rangeType);
   372	      // A turnOffBeacon (account pause / provider disposal) can land during any
   373	      // of these awaits, bump the generation, and stop BLE. If so, abort before
   374	      // we publish _isOn or install timers — otherwise startup resurrects a
   375	      // stopped service (reviewer #3).
   376	      if (gen != _sessionGeneration) throw StateError('beacon turned off');
   377	      await _startAdvertising();
   378	      if (gen != _sessionGeneration) throw StateError('beacon turned off');
   379	      await _startScanning();
   380	      if (gen != _sessionGeneration) throw StateError('beacon turned off');
   381	      _isOn = true;
   382	      // Last, and only once the session is really up. OFF by default and a
   383	      // no-op unless INRANGE_LOCATION_RESIDENCY is set: it keeps the process
   384	      // from suspending so app-owned timers keep firing, which is NOT the same
   385	      // as foreground BLE and is still unmeasured. See LocationKeepalive.
   386	      // Never blocks the beacon — a denied grant costs latency, not function.
   387	      unawaited(locationKeepalive.start());
   388	      // Tier 2-4 wakes (SLC, region, silent push). Same contract as the
   389	      // keepalive: gated, iOS-only, and never blocks the beacon.
   390	      unawaited(subtleWake.start());
   900	    }
   901	    await _restartScanning('subtle-wake burst');
   902	  }
   903	
   904	  Future<void> _stopBle() async {
   905	    // Serialized behind any in-flight start; queued starts no-op via
   906	    // _scanningWanted (already false by the time _stopBle is called on stop).
   907	    try {
   908	      await _serialScanOp(() async {
   909	        await _scanSub?.cancel();
   910	        _scanSub = null;
   911	        _scanRunning = false;
   912	        await FlutterBluePlus.stopScan();
   913	      });
   914	    } catch (e) {
   915	      debugPrint('BLE scan stop failed: $e');
   916	    }
   917	    try {
   918	      // Serialized: runs after any in-flight advertising start, and queued
   919	      // starts behind it no-op via _advertisingWanted.
   920	      await _serialAdvOp(() => FlutterBlePeripheral().stop());
   921	    } catch (e) {
   922	      debugPrint('BLE advertising stop failed: $e');
   923	    }
   924	    // iOS: the native carrier owns advertising + the filtered background
   925	    // scan — stopping it also clears the persisted enabled flag so a BT
   926	    // relaunch doesn't resurrect a beacon the user turned off.
   927	    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
   928	      await _bgBeacon.stop();
   929	    }
   930	  }
   931	
   932	  // --- BLE Implementation ---
   933	
   934	  static const String _inRangeServiceUuid =
   935	      '0000cafe-0000-1000-8000-00805f9b34fb';
   936	  // (The 16-bit "cafe" short form of the marker now lives in the native
   937	  // BackgroundBeacon module, which owns all iOS advertising.)
   938	  static const int _inRangeManufacturerId = 0xFFFF;
   939	  // W3: Apple's BLE company id — a backgrounded iPhone's overflow advert is
   940	  // manufacturerData under this id with first payload byte 0x01.
   941	  static const int _appleCompanyId = 0x004C;
   942	  // The GATT characteristic the iOS native module serves the token from.
   943	  static const String _inRangeTokenCharUuid =
   944	      '0000ca7e-0000-1000-8000-00805f9b34fb';
   945	
   946	  /// The advertised/claimed correlation id is now the raw 16 bytes of the
   947	  /// server-issued opaque token (32 hex chars) — no HMAC. Peers hex these bytes
   948	  /// back to the same token and report it; the server resolves it via the claim
   949	  /// history the advertiser wrote. (#6 step 2)
   950	  Uint8List _hexTo16Bytes(String hex) {
   951	    final out = Uint8List(16);
   952	    for (var i = 0; i < 16; i++) {
   953	      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
   954	    }
   955	    return out;
   956	  }
   957	
   958	  /// Fetches this user's server-issued opaque token batch for [dayUtc]. Returns
   959	  /// [] in local mode or on failure, so the token source falls back to a random
   960	  /// token and advertising never stalls.
   961	  Future<List<BatchSlot>> _fetchTokenBatch(
   962	      DateTime dayUtc, int windowMinutes) async {
   963	    if (!AppConfig.hasRealSupabase) return const <BatchSlot>[];
   964	    final dayStr = dayUtc.toIso8601String().split('T').first;
   965	    // Timeout is load-bearing: with no/half-dead network this RPC HANGS
   966	    // (S22 field incident 2026-07-23 — beacon button appeared dead, the
   967	    // whole turnOnBeacon flow stuck here forever). A timeout throws, the
   968	    // token source catches and falls back to a local random token, and BLE
   969	    // comes up in local mode as designed.
   970	    final rows = await InRangeSupabase.client.rpc('issue_token_batch', params: {
   971	      'p_day': dayStr,
   972	      'p_window_minutes': windowMinutes,
   973	    }).timeout(const Duration(seconds: 8));
   974	    if (rows is! List) return const <BatchSlot>[];
   975	    final out = <BatchSlot>[];
   976	    for (final r in rows) {
   977	      if (r is Map &&
   978	          r['token'] is String &&
   979	          r['valid_from'] != null &&
   980	          r['valid_until'] != null) {
   981	        out.add(BatchSlot(
   982	          token: r['token'] as String,
   983	          validFrom: DateTime.parse('${r['valid_from']}').toUtc(),
   984	          validUntil: DateTime.parse('${r['valid_until']}').toUtc(),
   985	        ));
   986	      }
   987	    }
   988	    return out;
   989	  }
   990	
   991	  Future<void> _startAdvertising() => _serialAdvOp(_startAdvertisingLocked);
   992	
   993	  Future<void> _startAdvertisingLocked() async {
   994	    // Beacon turned off while this op sat in the queue — do not resurrect.
   995	    if (!_advertisingWanted) return;
   996	    if (_currentToken == null || _currentCorrelationId == null) {
   997	      throw StateError('No beacon token is available');
   998	    }
   999	
  1000	    // iOS: the native BackgroundBeacon module owns advertising in BOTH
  1001	    // lifecycles now (W2/W4, docs/IOS_BACKGROUND_BLE_WIRING.md) — one
  1002	    // advertiser, no contention. Foreground it advertises the marker + the
  1003	    // rotating token as a second service UUID (today's path-b fast path,
  1004	    // kept); locked/backgrounded the advert degrades to the overflow area
  1005	    // and peers connect + read the token from the CA7E characteristic
  1006	    // instead, served per-read from the batch slots we pass here. Rotation
  1007	    // re-enters this method, so the module always holds the fresh batch.
  1008	    // Falls back to scan-only (fail-closed _advertisingUp) if the native
  1009	    // start reports no radio; the definitive verdict for BOTH roles arrives
  1010	    // via onBleState, which native pushes from `start`.
  1011	    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
  1012	      final payload = BackgroundBeaconChannel.slotsPayload(
  1013	        _tokenSource.slots,
  1014	        currentToken: _currentToken!.token,
  1015	        currentFrom: _currentToken!.issuedAt,
  1016	        currentUntil: _currentToken!.expiresAt,
  1017	      );
  1018	      final ok = await _bgBeacon.start(payload);
  1019	      // W5 test gate: only establish persistent links when the build opts in.
  1020	      unawaited(_bgBeacon.setW5Links(AppConfig.w5LinksEnabled));
  1021	      // Crack #1: refresh the native wake-ping endpoint + JWT on every
  1022	      // (re)start — rotation re-enters here every ~15 min, keeping the
  1023	      // stored token fresh. Endpoint is null until the server half (issue
  1024	      // #4) ships, which keeps the native side silent.
  1025	      if (AppConfig.hasRealSupabase) {
  1026	        unawaited(_bgBeacon.setWakePing(
  1027	          url: AppConfig.wakePingUrl,
  1028	          auth: InRangeSupabase.client.auth.currentSession?.accessToken,
  1029	        ));
  1030	      }
  1031	      _applyAdvertisingVerdict(ok, 'native start');
  1032	      debugPrint(ok
  1033	          ? 'iOS native advertising armed (marker + GATT token carrier)'
  1034	          : 'iOS native advertising not ready → scan-only fallback');
  1035	      return;
  1036	    }
  1037	    _applyAdvertisingVerdict(true, 'android advertise start');
  1038	
  1039	    final peripheral = FlutterBlePeripheral();
  1040	    // Legacy payload: mfg id + 16-byte corr + 1 flag byte (fits 31-byte AD).
  1041	    // Flag bit0 = medium-power slot. Field test 2026-07-13: Samsung's stack
  1042	    // does NOT update the TX Power Level AD when settings change, so the
  1043	    // slot marker must live in our own payload. Remaining flag bits are
  1044	    // reserved (future mesh relay bit). 16-byte adverts = legacy = high.
  1045	    final payload = Uint8List(17)
  1046	      ..setRange(0, 16, _currentCorrelationId!)
  1047	      ..[16] = _advPower == AdvertPower.medium ? 0x01 : 0x00;
  1048	    // W1 (IOS_BACKGROUND_BLE_WIRING.md): also advertise the fixed CAFE
  1049	    // discovery marker — a backgrounded iPhone can only scan with an exact
  1050	    // service-UUID filter, and mfgData alone can never match one. Android
  1051	    // encodes base-UUID-aliased UUIDs as 16-bit on air, so this costs 4
  1052	    // bytes: flags 3 + mfg AD 21 + svc AD 4 = 28 ≤ 31. Verify on-device
  1053	    // that BOTH fields still arrive (some stacks mis-handle mixed ADs).
  1054	    final advertiseData = AdvertiseData(
  1055	      manufacturerId: _inRangeManufacturerId,
  1056	      manufacturerData: payload,
  1057	      serviceUuids: const [_inRangeServiceUuid],
  1058	      includeDeviceName: false,
  1059	    );
  1060	
  2120	        onStranger: () {
  2121	          stranger = true;
  2122	          debugPrint('W3 GATT $deviceId: no In Range service (stranger)');
  2123	        },
  2124	        onFailure: (code) => failureCode = code,
  2125	      );
  2126	      // W2/W3: outcome histogram + distinct-MAC fates. This is READ-ONLY — the
  2127	      // backoff floors above are untouched, because outcome-aware backoff (1.7)
  2128	      // is frozen until this data says which outcomes actually dominate.
  2129	      //
  2130	      // The split is now real. Until 2026-07-26 every non-`no_service` failure
  2131	      // fell into one `failed` bucket, because the wrapper swallowed the native
  2132	      // code — so W2 could not tell "the room is full of unreachable strangers"
  2133	      // (connect_failed) from "our 10 s timeout is too tight" (timeout) from
  2134	      // "the radio is off" (bt_off), which are three different fixes. The codes
  2135	      // come straight from GattTokenReader.kt; `failed` now means only the one
  2136	      // case that carries no code at all — a null return with no exception.
  2137	      if (AppConfig.calibScanMode) {
  2138	        _bumpCounter(
  2139	          _gattOutcomeCounts,
  2140	          bytes == null
  2141	              ? (stranger ? 'no_service' : (failureCode ?? 'failed'))
  2142	              : (bytes.length == 16 ? 'success' : 'bad_length'),
  2143	        );
  2144	        if (stranger) _w3NoServiceMacs.add(deviceId);
  2145	        if (bytes != null && bytes.length == 16) _w3TokenMacs.add(deviceId);
  2146	      }
  2147	      if (bytes != null) {
  2148	        debugPrint('W3 GATT $deviceId: read ${bytes.length} bytes');
  2149	        if (bytes.length == 16 && _isOn) {
  2150	          final hex =
  2151	              bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  2152	          _gattTokenByDevice[deviceId] = hex;
  2153	          _gattTokenAt[deviceId] = DateTime.now();
  2154	          if (_gattTokenByDevice.length > 64) {
  2155	            final cutoff =
  2156	                DateTime.now().subtract(const Duration(minutes: 15));
  2157	            _gattTokenAt.removeWhere((id, at) {
  2158	              final stale = at.isBefore(cutoff);
  2159	              if (stale) _gattTokenByDevice.remove(id);
  2160	              return stale;
  2161	            });
  2162	          }
  2163	          _ingestForeignSample(hex, rssi, AdvertPower.high);
  2164	        }
  2165	      }
  2166	    } finally {
  2167	      _gattInflight.remove(deviceId);
  2168	    }
  2169	  }
  2170	
  2171	  /// W5 owner rule (2026-07-24): a pass/reject resolves the pair — its live
  2172	  /// session (if any) is torn down immediately. No-op off-iOS / no session.
  2173	  void dropPeer(String tokenHex) {
  2174	    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
  2175	      unawaited(_bgBeacon.dropPeer(tokenHex));
  2176	    }
  2177	  }
  2178	
  2179	  /// Single ingest point for a foreign token sample — scan results and the
  2180	  /// iOS native carrier's sightings (W4) both land here, so the self-sight
  2181	  /// guard, estimator, calibration log and sighting bookkeeping stay one
  2182	  /// code path.
  2183	  void _ingestForeignSample(String hexId, int rssi, AdvertPower power,
  2184	      {DateTime? at}) {
  2185	    // Filter ALL of our own tokens, not just the current one — a leaked
  2186	    // advertiser from a prior beacon session kept broadcasting the OLD
  2187	    // token after off→on, and we self-sighted it at a rock-constant RSSI
  2188	    // for an entire field test (2026-07-13 walk).
  2189	    if (_ownCorrHexes.contains(hexId)) return;
  2190	
  2191	    rangeEstimator.addObservation(
  2192	      hexId,
  2193	      ProximityObservation(
  2194	        source: ProximitySource.advertRssi,
  2195	        rssi: rssi,
  2196	        localState: defaultTargetPlatform == TargetPlatform.iOS ? 'locked' : 'scan',
  2197	      ),
  2198	      power: power,
  2199	    );
  2200	    // Raw per-advert persistence + verbose peer logging is CALIBRATION only.
  2201	    // In production it would retain a place/peer fingerprint and print peer
  2202	    // ids to release logs / bug reports (reviewer #18).
  2203	    if (AppConfig.calibScanMode) {
  2204	      try {
  2205	        onAdvertSample?.call(hexId, rssi, power, at ?? DateTime.now());
  2206	      } catch (e) {
  2207	        debugPrint('onAdvertSample callback error: $e');
  2208	      }
  2209	      // One line per fresh foreign advert — the calibration ground truth. The
  2210	      // per-advert RSSI is already here, so W6 only adds the two things missing:
  2211	      // the receiver tag (logged once per process in _logRadioCapabilities) and
  2212	      // a 5 dBm-binned distribution per window, which is the shape Herald's
  2213	      // self-calibration finding (A9/B9) needs and which is not recoverable
  2214	      // after the walk.
  2215	      _bumpBin(_rssiHist, (rssi / 5).floor() * 5);
  2216	      debugPrint(
  2217	          'Advert corr=${hexId.substring(0, 8)} rssi=$rssi pw=${power == AdvertPower.medium ? "M" : "H"} rx=$_receiverTag');
  2218	    }
  2219	
  2220	    _lastForeignScanAt = DateTime.now();
  2221	    _recordLocalSighting(hexId, rssi, at: at);
  2222	  }
  2223	
  2224	  double? _cachedLat;
  2225	  double? _cachedLon;
  2226	  double? _cachedAccuracy;
  2227	  DateTime? _cachedLocAt;
  2228	  Timer? _locationRefreshTimer;

exec
/bin/bash -lc "nl -ba lib/features/beacon/beacon_service.dart | sed -n '390,455p;2485,2545p'
rtk rg -n -C 3 \"_drainNativeBuffer\\(\" lib/features/beacon/beacon_service.dart" in /home/hazypiff/in-range
 succeeded in 0ms:
   390	      unawaited(subtleWake.start());
   391	      unawaited(subtleWake.syncAnchors(venueAnchors.regionDescriptors()));
   392	      // Pick up anything the native carrier buffered while this isolate was
   393	      // dead (eviction restore) or suspended.
   394	      unawaited(_drainNativeBuffer());
   395	    } catch (e) {
   396	      if (gen == _sessionGeneration) {
   397	        _advertisingWanted = false;
   398	        _scanningWanted = false;
   399	        await locationKeepalive.stop();
   400	        await subtleWake.stop();
   401	        await _stopBle();
   402	        _currentToken = null;
   403	        _currentCorrelationId = null;
   404	        _currentRangeType = null;
   405	      }
   406	      rethrow;
   407	    }
   408	
   409	    _rotationTimer?.cancel();
   410	    _rotationTimer = Timer.periodic(const Duration(seconds: 90), (_) {
   411	      if (!_isOn) return;
   412	      if (_tokenSource.shouldRotate(_currentToken)) {
   413	        unawaited(_rotateToken(rangeType));
   414	      }
   415	    });
   416	
   417	    _sightingFlushTimer?.cancel();
   418	    _sightingFlushTimer = Timer.periodic(const Duration(seconds: 45), (_) {
   419	      if (!_isOn) return;
   420	      _flushSightings();
   421	      _flushUploads();
   422	    });
   423	    _scanRestartTimer?.cancel();
   424	    // MUST be < 10 min on Android 14+ (finding D7 of
   425	    // docs/BLE_PRIOR_ART_REVIEW_2026-07-26.md).
   426	    //
   427	    // Path correction, 2026-07-26: the previous comment cited
   428	    // `research/ble-radio-optimization.md` and a reviewer, finding nothing at
   429	    // that path, concluded the 30-minute figure was unsourced and argued from
   430	    // there. The file is `docs/research/ble-radio-optimization.md` and the
   431	    // figure is sourced at :19-21 to a quoted academic paper ("the Android
   432	    // operating system automatically switches from the SCAN_MODE_LOW_LATENCY to
   433	    // the SCAN_MODE_OPPORTUNISTIC setting after 30 min of continuous
   434	    // scanning"). It was never wrong — it describes Android ≤13. Cite the full
   435	    // path; a one-character path error cost a reviewer an entire argument.
   436	    //
   437	    // AOSP demotes a long-running scan on a timeout that changed under us:
   438	    // 30 min on Android 10–13, but **10 min on 14+**. The mechanism changed
   439	    // too. On ≤13 an unfiltered client went OPPORTUNISTIC with its filters
   440	    // removed; on 14+ a *filtered* client — which ours must be, since ≥8.1
   441	    // suppresses unfiltered screen-off scans — is forced to
   442	    // SCAN_MODE_FORCE_DOWNGRADED = LOW_POWER (ScanManager.java:1550-1578,
   443	    // :123), and `mStats.setScanTimeout()` makes isForceDowngradedScanClient()
   444	    // **sticky for the life of that scanner** (AppScanStats.java:801-810).
   445	    // Sticky drags the screen-off path down with it: SCREEN_OFF_BALANCED 25%
   446	    // → SCREEN_OFF 5% (ScanManager.java:698-731, duty cycles at :85-97).
   447	    //
   448	    // So at 25 min, on a 14+ handset, 15 of every 25 minutes ran at ⅕–⅒ the
   449	    // duty cycle we were already paying for — invisible from Dart, because FBP
   450	    // reports the demotion in no way at all (isScanning stays true, no event).
   451	    // 8 min keeps it at `balanced` continuously with 2 min of slack for a
   452	    // Doze-deferred timer, and stays far under the 30-min behaviour on the S9s.
   453	    // The cost is one scan-quota charge per 8 min against a budget of 5 per
   454	    // 30 s (D6) — a non-issue. Not backed off on failure: see
   455	    // _requestScanRestart.
  2485	  Future<void> _refreshClaim({required String rangeType}) async {
  2486	    _currentToken = await _tokenSource.nextToken();
  2487	    _currentCorrelationId = _hexTo16Bytes(_currentToken!.token);
  2488	    // Remember every token we advertise so the scanner never self-sights a
  2489	    // stale one (leaked advertiser after off→on). Bounded to stay tiny.
  2490	    _ownCorrHexes.add(_currentCorrelationId!
  2491	        .map((b) => b.toRadixString(16).padLeft(2, '0'))
  2492	        .join());
  2493	    if (_ownCorrHexes.length > 16) {
  2494	      _ownCorrHexes.remove(_ownCorrHexes.first);
  2495	    }
  2496	
  2497	    // Reuse the cached fix only if it is still fresh. Without the age check a
  2498	    // user who travels >400 m without seeing a peer keeps claiming their
  2499	    // ORIGIN, and the server's 400 m veto then rejects the real encounter at
  2500	    // the new location (reviewer #7).
  2501	    final cacheAge = _cachedLocAt == null
  2502	        ? null
  2503	        : DateTime.now().difference(_cachedLocAt!);
  2504	    final cacheFresh = cacheAge != null &&
  2505	        cacheAge <= const Duration(minutes: 2);
  2506	    double? lat = cacheFresh ? _cachedLat : null;
  2507	    double? lon = cacheFresh ? _cachedLon : null;
  2508	    if (lat == null) {
  2509	      try {
  2510	        Position? position = AppConfig.calibScanMode
  2511	            ? null
  2512	            : await Geolocator.getLastKnownPosition();
  2513	        if (position == null || !_isFreshPosition(position)) {
  2514	          position = await Geolocator.getCurrentPosition(
  2515	            locationSettings: LocationSettings(
  2516	              accuracy: AppConfig.calibScanMode
  2517	                  ? LocationAccuracy.high
  2518	                  : LocationAccuracy.low,
  2519	              timeLimit: const Duration(seconds: 5),
  2520	            ),
  2521	          );
  2522	        }
  2523	        lat = position.latitude;
  2524	        lon = position.longitude;
  2525	        _cachedLat = lat;
  2526	        _cachedLon = lon;
  2527	        _cachedAccuracy = position.accuracy;
  2528	        _cachedLocAt = DateTime.now();
  2529	        _logGpsFix(position, tag: 'claim');
  2530	      } catch (e) {
  2531	        debugPrint('Geolocator failed at claim time: $e');
  2532	      }
  2533	    }
  2534	
  2535	    // A new token supersedes any pending retry of the previous claim.
  2536	    final gen = _claimMgr.newSession();
  2537	    _claimRangeType = rangeType;
  2538	    _cachedLat = lat;
  2539	    _cachedLon = lon;
  2540	
  2541	    // Publish the new token's expiry immediately, even before the claim RPC
  2542	    // resolves, so the UI countdown tracks the current token (reviewer #11).
  2543	    onClaimStateChanged?.call(
  2544	        _currentToken!.expiresAt, AppConfig.hasRealSupabase ? _cloudClaimed : null);
  2545	
106-    })
107-    ..onBleState = _onNativeBleState
108-    ..onBufferedSightingsReady = (() {
109:      unawaited(_drainNativeBuffer());
110-    });
111-  final Duration _rotationWindow;
112-  final String _userId;
314-  /// concurrent drains would ack overlapping counts and delete sightings
315-  /// neither ingested (audit 2026-07-25 round 3); a drain requested while
316-  /// one runs is folded into a follow-up pass.
317:  Future<void> _drainNativeBuffer() async {
318-    if (!_isOn) return;
319-    // iOS-only: the buffer lives in BackgroundBeacon.swift. There is no Android
320-    // implementation of io.inrange/background_beacon, so on Android every call
391-      unawaited(subtleWake.syncAnchors(venueAnchors.regionDescriptors()));
392-      // Pick up anything the native carrier buffered while this isolate was
393-      // dead (eviction restore) or suspended.
394:      unawaited(_drainNativeBuffer());
395-    } catch (e) {
396-      if (gen == _sessionGeneration) {
397-        _advertisingWanted = false;
1452-      // data we came to collect, and the drain is idempotent (pull-and-ack: the
1453-      // native side only discards what we acknowledge), so a redundant call costs
1454-      // one empty channel round trip.
1455:      unawaited(_drainNativeBuffer());
1456-    });
1457-    _resumeObserver = obs;
1458-    binding.addObserver(obs);

exec
/bin/bash -lc "nl -ba ios/Runner/BackgroundBeacon.swift | sed -n '455,535p'
nl -ba lib/features/beacon/beacon_service.dart | sed -n '307,350p;2249,2305p;2449,2483p'
nl -ba supabase/migrations/0023_gps_accuracy_aware_gate.sql | sed -n '26,43p'" in /home/hazypiff/in-range
 succeeded in 0ms:
   455	  /// the ordering explicit at `BluetoothDiscoveryService.swift:165`,
   456	  /// *"// Only connect if we didn't got a EphId in the Advertisement"*.
   457	  /// OpenTrace still had to connect because its tempID is a base64 JSON blob
   458	  /// too big for an advert; in-range's 16 bytes are not.
   459	  ///
   460	  /// Layout mirrors `beacon_service.dart:703-705` exactly:
   461	  /// `[company id, little-endian][16-byte correlation id][flag byte]`, flag
   462	  /// bit0 = medium-power slot. The flag byte is OPTIONAL (16-byte adverts
   463	  /// predate it, and `beacon_service.dart:968` still accepts both lengths) and
   464	  /// is never part of the token — folding it in would corrupt every id. Any
   465	  /// other length is rejected outright rather than read at a guessed offset.
   466	  private static func androidAdvertToken(
   467	    _ advertisementData: [String: Any]
   468	  ) -> (hex: String, mediumPower: Bool)? {
   469	    guard let raw = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
   470	          raw.count >= 18
   471	    else { return nil }
   472	    let bytes = [UInt8](raw)
   473	    // CoreBluetooth returns the whole AD field, company id included, and the
   474	    // company id is little-endian on air.
   475	    let company = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
   476	    guard company == inRangeCompanyID else { return nil }
   477	    let body = bytes.count - 2
   478	    guard body == 16 || body == 17 else { return nil }
   479	    let hex = bytes[2..<18].map { String(format: "%02x", $0) }.joined()
   480	    let mediumPower = body == 17 && (bytes[18] & 0x01) != 0
   481	    return (hex, mediumPower)
   482	  }
   483	
   484	  // MARK: - Sighting delivery
   485	
   486	  /// `mediumPower` carries B1's Android flag bit0 (`beacon_service.dart:705`).
   487	  /// It matters: "heard on medium" IS the physical feet_30 gate, so an Android
   488	  /// sighting mislabelled as high-power would silently widen that tier. iOS
   489	  /// peers have no power flag — high is the only slot they advertise in — so
   490	  /// the default preserves every pre-existing call site exactly.
   491	  private func emitSighting(tokenHex: String, rssi: Int, mediumPower: Bool = false) {
   492	    let ts = Int(Date().timeIntervalSince1970 * 1000)
   493	    let sighting: [String: Any] = [
   494	      "token": tokenHex, "rssi": rssi, "ts": ts,
   495	      "pwr": mediumPower ? "medium" : "high",
   496	    ]
   497	    // NEVER hand a background sighting to the Flutter engine: a suspended
   498	    // engine's channel accepts the call and silently drops it (dark-bench
   499	    // 2026-07-23 — native discoveries happened, Dart never saw them).
   500	    // Background → persist natively; Dart pulls and acks when it is ready.
   501	    if UIApplication.shared.applicationState == .active, let ch = channel {
   502	      ch.invokeMethod("onSighting", arguments: sighting)
   503	    } else {
   504	      var buf = (defaults.array(forKey: Self.keyBuffer) as? [[String: Any]]) ?? []
   505	      buf.append(sighting)
   506	      if buf.count > Self.bufferCap { buf.removeFirst(buf.count - Self.bufferCap) }
   507	      defaults.set(buf, forKey: Self.keyBuffer)
   508	    }
   509	  }
   510	
   511	  /// Tells Dart the buffer is non-empty so it can pull (drain) and ack.
   512	  /// Never delivers the sightings itself — a pushed batch whose delivery is
   513	  /// not confirmed can be lost on a cold launch, which is exactly the bug
   514	  /// pull-and-ack exists to close.
   515	  private func notifyBufferReady() {
   516	    guard let ch = channel,
   517	          UIApplication.shared.applicationState == .active,
   518	          let buf = defaults.array(forKey: Self.keyBuffer) as? [[String: Any]],
   519	          !buf.isEmpty else { return }
   520	    ch.invokeMethod("onBufferedSightingsReady", arguments: nil)
   521	  }
   522	
   523	  /// Drops the first [count] buffered sightings — called only after Dart
   524	  /// confirms ingestion of that many drained entries.
   525	  private func ackBuffer(_ count: Int) {
   526	    guard count > 0,
   527	          var buf = defaults.array(forKey: Self.keyBuffer) as? [[String: Any]],
   528	          !buf.isEmpty else { return }
   529	    buf.removeFirst(min(count, buf.count))
   530	    if buf.isEmpty {
   531	      defaults.removeObject(forKey: Self.keyBuffer)
   532	    } else {
   533	      defaults.set(buf, forKey: Self.keyBuffer)
   534	    }
   535	  }
   307	  bool _nativeDrainInFlight = false;
   308	  bool _nativeDrainPending = false;
   309	
   310	  /// Pull-and-ack drain of the native background buffer: sightings are
   311	  /// ingested with their original capture timestamps (migration 0053's
   312	  /// late-evidence window covers them server-side) and only then acked, so
   313	  /// a crash mid-drain re-delivers instead of losing them. Serialized: two
   314	  /// concurrent drains would ack overlapping counts and delete sightings
   315	  /// neither ingested (audit 2026-07-25 round 3); a drain requested while
   316	  /// one runs is folded into a follow-up pass.
   317	  Future<void> _drainNativeBuffer() async {
   318	    if (!_isOn) return;
   319	    // iOS-only: the buffer lives in BackgroundBeacon.swift. There is no Android
   320	    // implementation of io.inrange/background_beacon, so on Android every call
   321	    // threw MissingPluginException, got caught, and printed
   322	    // "BackgroundBeacon drain failed: ..." on EVERY beacon start (observed on an
   323	    // S9, 2026-07-26 bench). Harmless, but it put an alarming line in the walk
   324	    // logs we are about to read closely — and a real drain failure would have
   325	    // been indistinguishable from the routine one.
   326	    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
   327	    if (_nativeDrainInFlight) {
   328	      _nativeDrainPending = true;
   329	      return;
   330	    }
   331	    _nativeDrainInFlight = true;
   332	    try {
   333	      do {
   334	        _nativeDrainPending = false;
   335	        final items = await _bgBeacon.drainBufferedSightings();
   336	        if (items.isEmpty || !_isOn) return;
   337	        for (final s in items) {
   338	          final token = s['token'], rssi = s['rssi'], ts = s['ts'];
   339	          if (token is String && token.length == 32 && rssi is int) {
   340	            final at = ts is int
   341	                ? DateTime.fromMillisecondsSinceEpoch(ts)
   342	                : DateTime.now();
   343	            _ingestForeignSample(token, rssi, AdvertPower.high, at: at);
   344	          }
   345	        }
   346	        await _bgBeacon.ackBufferedSightings(items.length);
   347	      } while (_nativeDrainPending && _isOn);
   348	    } finally {
   349	      _nativeDrainInFlight = false;
   350	    }
  2249	
  2250	    _ensureLocationCache();
  2251	
  2252	    final range = _currentRangeType ?? 'feet_10';
  2253	    // Uploaded sightings carry the ESTIMATED band, not the fixed beacon
  2254	    // range — the server derives encounter bands from it (migration 0022).
  2255	    final estimated = rangeEstimator.classify(observedCorrelationIdHex);
  2256	    final uploadRange = (range.startsWith('feet') && estimated != 'none')
  2257	        ? estimated
  2258	        : range;
  2259	    final record = SightingRecord(
  2260	      observedToken: observedCorrelationIdHex,
  2261	      rssi: rssi,
  2262	      observerLat: _cachedLat,
  2263	      observerLon: _cachedLon,
  2264	      observerAccuracyM: _cachedAccuracy,
  2265	      // A locked iPhone's natively-buffered sighting flushes minutes after
  2266	      // capture; the server (0053) accepts and stores the TRUE capture time,
  2267	      // so pass it through instead of the flush time.
  2268	      observedAt: at ?? now,
  2269	      rangeType: uploadRange,
  2270	    );
  2271	
  2272	    // Keep one COHERENT best-evidence record per corr: RSSI, band, time,
  2273	    // location and accuracy all come from the SAME physical sample. Previously
  2274	    // the strongest RSSI was stitched onto the latest sample's time/coords/band
  2275	    // — an observation that never happened, which could pass the server RSSI
  2276	    // gate on old strength but store an unrelated location/band (reviewer #12).
  2277	    final prev = _pendingByCorr[observedCorrelationIdHex];
  2278	    if (prev == null && _pendingByCorr.length >= _maxPendingSightings) {
  2279	      _pendingByCorr.remove(_pendingByCorr.keys.first);
  2280	    }
  2281	    // Replace only when this sample is strictly stronger; otherwise keep the
  2282	    // existing coherent record untouched.
  2283	    //
  2284	    // ...with one exception: a record with no coordinates can never be sent.
  2285	    // _ensureLocationCache() above is fire-and-forget (a Timer plus up to 6 s
  2286	    // in getCurrentPosition) and turnOnBeacon does not await it, so sightings
  2287	    // observed in the first seconds of a session are built with a null
  2288	    // observerLat/observerLon. _flushSightings skips those records (they fail
  2289	    // record_sighting's required lat/lon) but only REMOVES a record after a
  2290	    // successful send — so without this clause a strong early sighting sticks
  2291	    // in _pendingByCorr forever: never uploadable because it has no
  2292	    // coordinates, never replaced because no later sample beats its RSSI, and
  2293	    // holding one of the _maxPendingSightings slots until FIFO eviction.
  2294	    // The peer is simply never reported, which reads as "it didn't detect me"
  2295	    // at exactly the moment a user is watching. Found by audit 2026-07-25.
  2296	    //
  2297	    // Coherence (reviewer #12) is preserved: we swap in a whole later sample
  2298	    // rather than stitching coordinates onto an older one.
  2299	    final prevUnusable =
  2300	        prev != null && (prev.observerLat == null || prev.observerLon == null);
  2301	    final thisUsable = record.observerLat != null && record.observerLon != null;
  2302	    if (prev == null || rssi > prev.rssi || (prevUnusable && thisUsable)) {
  2303	      _pendingByCorr[observedCorrelationIdHex] = record;
  2304	    }
  2305	
  2449	  Future<void> _flushSightings() async {
  2450	    if (_pendingByCorr.isEmpty) return;
  2451	    if (!AppConfig.hasRealSupabase) {
  2452	      // Keep local rows; no network thrash against placeholder host.
  2453	      return;
  2454	    }
  2455	
  2456	    final toSend = List<SightingRecord>.from(_pendingByCorr.values);
  2457	
  2458	    for (final s in toSend) {
  2459	      if (s.observerLat == null || s.observerLon == null) continue;
  2460	      try {
  2461	        // Named args match migration signatures (lat/lon required before optionals).
  2462	        await InRangeSupabase.client.rpc('record_sighting', params: {
  2463	          'p_observed_token':
  2464	              s.observedToken, // correlation-id hex (matches claim)
  2465	          'p_lat': s.observerLat,
  2466	          'p_lon': s.observerLon,
  2467	          'p_rssi': s.rssi,
  2468	          'p_observed_at': s.observedAt.toUtc().toIso8601String(),
  2469	          'p_range': _mapUiRangeToDb(s.rangeType),
  2470	          // Sizes the server's GPS plausibility veto from real uncertainty
  2471	          // instead of a fixed guess (migration 0024).
  2472	          'p_accuracy': s.observerAccuracyM,
  2473	        }).timeout(const Duration(seconds: 10));
  2474	        debugPrint('record_sighting OK rssi=${s.rssi}');
  2475	        if (identical(_pendingByCorr[s.observedToken], s)) {
  2476	          _pendingByCorr.remove(s.observedToken);
  2477	        }
  2478	      } catch (e) {
  2479	        debugPrint('Sighting upload failed: $e');
  2480	        // Retain for a later bounded retry; the queue is capped above.
  2481	      }
  2482	    }
  2483	  }
    26	CREATE OR REPLACE FUNCTION public.gps_veto_radius_meters(
    27	  p_acc_a DOUBLE PRECISION,
    28	  p_acc_b DOUBLE PRECISION
    29	)
    30	RETURNS DOUBLE PRECISION
    31	LANGUAGE sql
    32	IMMUTABLE
    33	AS $$
    34	  -- Unknown accuracy on either side => fall back to the widest sane veto
    35	  -- rather than inventing precision we do not have.
    36	  SELECT LEAST(400.0, GREATEST(100.0,
    37	    2.0 * (COALESCE(p_acc_a, 100.0) + COALESCE(p_acc_b, 100.0))
    38	  ));
    39	$$;
    40	
    41	COMMENT ON FUNCTION public.gps_veto_radius_meters IS
    42	  'Accuracy-aware plausibility radius. GPS may only VETO implausible pairs; '
    43	  'it may never assert proximity (consumer GPS ~10 m at best, 29-48 m indoors).';

Completed source-level review, mechanical predecessor diffs, schema/write-path tracing, and live-deployment analysis. The current migration has blocking ownership and legal-hold defects despite applying cleanly.
  ✓ Inspect migration, audit findings, and exact predecessor function definitions
  ✓ Trace schema constraints and all real coordinate/token write paths
  ✓ Analyze conflict, lifetime, privilege, locking, and transactional behavior
  ✓ Report adversarial verdict with file:line findings
codex
VERDICT: SAFE WITH CHANGES

Do not deploy the current file. Two fixes are incomplete, and the cleanup change violates legal holds.

1. Blocking — C-SQL-1 still permits poisoned ownership state

At [0063:61](/home/hazypiff/in-range/supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql:61), a token belonging to another batch produces `v_in_batch = false`, but is accepted while `enforce_batch_tokens = 0`. An attacker can therefore claim a batch-issued token whose history row has not yet been preclaimed.

Worse, [0063:73](/home/hazypiff/in-range/supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql:73) mutates the attacker’s `token_claims` row before the history conflict at [0063:83](/home/hazypiff/in-range/supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql:83). When the `WHERE` at [0063:102](/home/hazypiff/in-range/supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql:102) rejects that update, the function still returns success and leaves the attacker’s live row pointing at the victim’s token. That can squat the unique token and make a later legitimate claim fail.

Required change:

- Reject a token already owned by another `beacon_token_batch` row regardless of the rollout flag.
- Lock/check batch and history ownership before either insert.
- Retain the conflict predicate as defense-in-depth, but add `RETURNING`; if the upsert affects zero rows, raise a generic `22023`.
- Audit existing mismatches between `token_claims`, `token_claim_history`, and `beacon_token_batch`.

Yes, it should raise. The ownership oracle is negligible: tokens are 122-bit values normally learned from BLE, active foreign tokens already expose a unique-constraint failure, and `record_sighting` already distinguishes resolvable tokens. Use a generic “Invalid beacon token” rather than revealing an owner.

2. Blocking — C-SQL-3 deletes evidence under legal hold

The unconditional delete at [0063:281](/home/hazypiff/in-range/supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql:281) sits outside the hold-aware branches. It will purge held users’ batch mappings on the next maintenance run.

That contradicts the function’s hold invariant at [0063:212](/home/hazypiff/in-range/supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql:212) and the account scrub logic, which explicitly defers all deletion for held users at [0059:189](/home/hazypiff/in-range/supabase/migrations/0059_proximity_wake_producer.sql:189).

Use:

- `... AND NOT public.has_legal_hold(b.user_id)` in the hold branch.
- The unconditional delete only in the no-hold branch.

3. C-SQL-4 — NULL does not break the locked-phone path, but location timing can

Stored reverse coordinates cannot be NULL:

- Both columns are `NOT NULL` at [0001:140](/home/hazypiff/in-range/supabase/migrations/0001_init.sql:140).
- `record_sighting` rejects missing coordinates at [0053:88](/home/hazypiff/in-range/supabase/migrations/0053_late_evidence_tolerance.sql:88).
- The production client skips unsendable sightings at [beacon_service.dart:2458](/home/hazypiff/in-range/lib/features/beacon/beacon_service.dart:2458).
- Direct client DML on `sightings` was revoked at [0019:433](/home/hazypiff/in-range/supabase/migrations/0019_beta_security_hardening.sql:433).

A phone with no fix produces no reverse row, so it already failed the existing reciprocity gate. The new NULL fail-closed check does not create that failure.

There is, however, a real locked-phone false-negative edge: the native buffer stores only token, RSSI, and timestamp at [BackgroundBeacon.swift:491](/home/hazypiff/in-range/ios/Runner/BackgroundBeacon.swift:491). Dart later attaches its current cached location at [beacon_service.dart:2259](/home/hazypiff/in-range/lib/features/beacon/beacon_service.dart:2259). If the phone moved before waking, the fallback compares wake-time coordinates to encounter-time coordinates and may reject a genuine late encounter.

Also, [0063:152](/home/hazypiff/in-range/supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql:152) does not fetch `observer_accuracy_m`. The supplied radius was calculated using the NULL claim accuracy, not the reverse sighting’s actual accuracy. That can make the veto either too narrow or too wide. Fetch and use both sightings’ accuracy values, and add a moved-before-wake regression test.

4. `GREATEST` is not a new owner exploit, but it is not a real lifetime bound

At [0063:87](/home/hazypiff/in-range/supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql:87), `GREATEST` does not create the ability to renew indefinitely: the same owner could already call repeatedly with later expiries under plain assignment.

Encounter creation is additionally bounded by the unchanged `valid_from` test at [0063:130](/home/hazypiff/in-range/supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql:130)—about 38 minutes with the default late window, at most 48. However, `record_sighting` checks only `valid_until` at [0053:102](/home/hazypiff/in-range/supabase/migrations/0053_late_evidence_tolerance.sql:102), so an owner can keep resolution and retention alive by renewing.

`GREATEST` also prevents correcting an accidentally excessive expiry. The stronger design is to derive/cap validity from the authoritative batch row; for legacy tokens, apply a fixed bound from the original `valid_from`. I would not rely on monotonicity as a security property.

5. The “dead COALESCE” claim is only half true

At [0063:88](/home/hazypiff/in-range/supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql:88):

- `approx_lat` and `approx_lon` are necessarily non-NULL, so their `COALESCE`s were dead.
- `p_accuracy` is explicitly nullable.
- `p_range` can be explicitly passed as NULL despite having a default.

Therefore the explanation at [0063:98](/home/hazypiff/in-range/supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql:98) is false for `range_type` and `accuracy_m`. Plain assignment may still be preferable for accuracy coherence, but it is a deliberate semantic change and needs a test—not a dead-code cleanup.

6. Diff and deployment mechanics

The mechanical diffs confirm no body drift outside the marked sections:

- `claim_token` otherwise matches 0060.
- `correlate_encounter` otherwise matches 0053.
- `cleanup_ephemeral_data` otherwise matches 0059.

The single transaction is correct: all three definitions become visible atomically, signatures are unchanged, and `CREATE OR REPLACE` preserves existing ACLs. The migration itself does not run cleanup.

Operationally, the first scheduled cleanup will delete the entire accumulated expired-batch backlog in one transaction. The expiry index exists, but preflight the row count and batch the purge if it is large. Also inspect ownership mismatches and remember that this migration does not repair previously poisoned coordinates/history.

Because local migration 0063 is already recorded as applied, after editing it you must reset/replay or explicitly reapply the corrected definitions before considering the rehearsal valid.
tokens used
213,340
VERDICT: SAFE WITH CHANGES

Do not deploy the current file. Two fixes are incomplete, and the cleanup change violates legal holds.

1. Blocking — C-SQL-1 still permits poisoned ownership state

At [0063:61](/home/hazypiff/in-range/supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql:61), a token belonging to another batch produces `v_in_batch = false`, but is accepted while `enforce_batch_tokens = 0`. An attacker can therefore claim a batch-issued token whose history row has not yet been preclaimed.

Worse, [0063:73](/home/hazypiff/in-range/supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql:73) mutates the attacker’s `token_claims` row before the history conflict at [0063:83](/home/hazypiff/in-range/supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql:83). When the `WHERE` at [0063:102](/home/hazypiff/in-range/supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql:102) rejects that update, the function still returns success and leaves the attacker’s live row pointing at the victim’s token. That can squat the unique token and make a later legitimate claim fail.

Required change:

- Reject a token already owned by another `beacon_token_batch` row regardless of the rollout flag.
- Lock/check batch and history ownership before either insert.
- Retain the conflict predicate as defense-in-depth, but add `RETURNING`; if the upsert affects zero rows, raise a generic `22023`.
- Audit existing mismatches between `token_claims`, `token_claim_history`, and `beacon_token_batch`.

Yes, it should raise. The ownership oracle is negligible: tokens are 122-bit values normally learned from BLE, active foreign tokens already expose a unique-constraint failure, and `record_sighting` already distinguishes resolvable tokens. Use a generic “Invalid beacon token” rather than revealing an owner.

2. Blocking — C-SQL-3 deletes evidence under legal hold

The unconditional delete at [0063:281](/home/hazypiff/in-range/supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql:281) sits outside the hold-aware branches. It will purge held users’ batch mappings on the next maintenance run.

That contradicts the function’s hold invariant at [0063:212](/home/hazypiff/in-range/supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql:212) and the account scrub logic, which explicitly defers all deletion for held users at [0059:189](/home/hazypiff/in-range/supabase/migrations/0059_proximity_wake_producer.sql:189).

Use:

- `... AND NOT public.has_legal_hold(b.user_id)` in the hold branch.
- The unconditional delete only in the no-hold branch.

3. C-SQL-4 — NULL does not break the locked-phone path, but location timing can

Stored reverse coordinates cannot be NULL:

- Both columns are `NOT NULL` at [0001:140](/home/hazypiff/in-range/supabase/migrations/0001_init.sql:140).
- `record_sighting` rejects missing coordinates at [0053:88](/home/hazypiff/in-range/supabase/migrations/0053_late_evidence_tolerance.sql:88).
- The production client skips unsendable sightings at [beacon_service.dart:2458](/home/hazypiff/in-range/lib/features/beacon/beacon_service.dart:2458).
- Direct client DML on `sightings` was revoked at [0019:433](/home/hazypiff/in-range/supabase/migrations/0019_beta_security_hardening.sql:433).

A phone with no fix produces no reverse row, so it already failed the existing reciprocity gate. The new NULL fail-closed check does not create that failure.

There is, however, a real locked-phone false-negative edge: the native buffer stores only token, RSSI, and timestamp at [BackgroundBeacon.swift:491](/home/hazypiff/in-range/ios/Runner/BackgroundBeacon.swift:491). Dart later attaches its current cached location at [beacon_service.dart:2259](/home/hazypiff/in-range/lib/features/beacon/beacon_service.dart:2259). If the phone moved before waking, the fallback compares wake-time coordinates to encounter-time coordinates and may reject a genuine late encounter.

Also, [0063:152](/home/hazypiff/in-range/supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql:152) does not fetch `observer_accuracy_m`. The supplied radius was calculated using the NULL claim accuracy, not the reverse sighting’s actual accuracy. That can make the veto either too narrow or too wide. Fetch and use both sightings’ accuracy values, and add a moved-before-wake regression test.

4. `GREATEST` is not a new owner exploit, but it is not a real lifetime bound

At [0063:87](/home/hazypiff/in-range/supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql:87), `GREATEST` does not create the ability to renew indefinitely: the same owner could already call repeatedly with later expiries under plain assignment.

Encounter creation is additionally bounded by the unchanged `valid_from` test at [0063:130](/home/hazypiff/in-range/supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql:130)—about 38 minutes with the default late window, at most 48. However, `record_sighting` checks only `valid_until` at [0053:102](/home/hazypiff/in-range/supabase/migrations/0053_late_evidence_tolerance.sql:102), so an owner can keep resolution and retention alive by renewing.

`GREATEST` also prevents correcting an accidentally excessive expiry. The stronger design is to derive/cap validity from the authoritative batch row; for legacy tokens, apply a fixed bound from the original `valid_from`. I would not rely on monotonicity as a security property.

5. The “dead COALESCE” claim is only half true

At [0063:88](/home/hazypiff/in-range/supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql:88):

- `approx_lat` and `approx_lon` are necessarily non-NULL, so their `COALESCE`s were dead.
- `p_accuracy` is explicitly nullable.
- `p_range` can be explicitly passed as NULL despite having a default.

Therefore the explanation at [0063:98](/home/hazypiff/in-range/supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql:98) is false for `range_type` and `accuracy_m`. Plain assignment may still be preferable for accuracy coherence, but it is a deliberate semantic change and needs a test—not a dead-code cleanup.

6. Diff and deployment mechanics

The mechanical diffs confirm no body drift outside the marked sections:

- `claim_token` otherwise matches 0060.
- `correlate_encounter` otherwise matches 0053.
- `cleanup_ephemeral_data` otherwise matches 0059.

The single transaction is correct: all three definitions become visible atomically, signatures are unchanged, and `CREATE OR REPLACE` preserves existing ACLs. The migration itself does not run cleanup.

Operationally, the first scheduled cleanup will delete the entire accumulated expired-batch backlog in one transaction. The expiry index exists, but preflight the row count and batch the purge if it is large. Also inspect ownership mismatches and remember that this migration does not repair previously poisoned coordinates/history.

Because local migration 0063 is already recorded as applied, after editing it you must reset/replay or explicitly reapply the corrected definitions before considering the rehearsal valid.
