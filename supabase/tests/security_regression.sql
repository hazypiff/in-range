\set ON_ERROR_STOP on

BEGIN;

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------
-- Added 2026-07-25. This file was never wired into run_security_tests.sh
-- (which runs only reciprocity_security_test.sql), so it had never been
-- executed and assumed fixture users that nothing created. Everything below
-- runs inside the BEGIN/ROLLBACK, so these rows never persist.
-- Only (id, email): every other auth.users column is nullable or defaulted on
-- real Supabase, and this also applies against the reduced auth.users stub
-- used by scripts/rehearse_migrations.sh.
INSERT INTO auth.users (id, email)
VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'sec_a@test.local'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'sec_b@test.local'),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'sec_d@test.local')
ON CONFLICT (id) DO NOTHING;

-- The acting user (sub = aaaa... in the JWT claims set below) must clear the
-- age + photo gates, otherwise claim_token raises the verification error
-- before it ever reaches the coordinate check, and the negative assertion
-- further down ("coordinate-free token claim unexpectedly succeeded", which
-- traps SQLSTATE 22023) never exercises what it claims to.
--
-- Deliberately NOT applied to bbbb.../dddd...: the photo-verification block
-- and the swipe block below depend on those two starting unverified.
UPDATE public.profiles
SET display_name = 'SecA',
    dob = '1990-01-01',
    is_active = TRUE,
    age_verified = TRUE,
    is_photo_verified = TRUE,
    photo_urls = ARRAY['sec_a.jpg']
WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

-- 0045: current_user_can_discover() also requires an APPROVED verification row
-- matching the current photo, not just the is_photo_verified flag. Same shape
-- the reciprocity runner seeds (run_security_tests.sh).
INSERT INTO public.photo_verifications (user_id, photo_path, slot_index, state, decided_at)
VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'sec_a.jpg', 0, 'approved', now())
ON CONFLICT DO NOTHING;

DO $$
DECLARE
  v_missing_rls TEXT;
  v_anon_secdef TEXT;
  v_realtime TEXT[];
  v_claimed INT;
  v_attempts INT;
  v_object_id UUID;
  v_object_updated TIMESTAMPTZ;
  v_verification UUID;
  v_photo_state public.photo_verification_state;
BEGIN
  SELECT c.relname INTO v_missing_rls
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relkind = 'r'
    AND c.relname = ANY (ARRAY[
      'profiles', 'token_claims', 'sightings', 'location_pings', 'encounters',
      'encounter_actions', 'matches', 'messages', 'photo_verifications',
      'blocks', 'reports', 'subscriptions', 'boosts', 'ad_impressions',
      'device_push_tokens', 'notification_outbox', 'ai_runs', 'ai_events',
      'ai_feedback', 'app_settings', 'venue_anchors', 'proximity_wake_requests'
    ])
    AND NOT c.relrowsecurity
  LIMIT 1;
  ASSERT v_missing_rls IS NULL, 'privacy-sensitive table lacks RLS';

  ASSERT NOT has_table_privilege('anon', 'public.profiles', 'SELECT'),
    'anon can read profiles';
  ASSERT NOT has_table_privilege('authenticated', 'public.profiles', 'UPDATE'),
    'authenticated can bypass profile RPC validation';
  ASSERT has_table_privilege('authenticated', 'public.messages', 'SELECT'),
    'authenticated cannot hydrate RLS-filtered messages';
  ASSERT NOT has_table_privilege('authenticated', 'public.messages', 'UPDATE'),
    'authenticated can directly mutate messages';
  ASSERT has_table_privilege('service_role', 'public.notification_outbox', 'SELECT')
    AND has_table_privilege('service_role', 'public.notification_outbox', 'UPDATE'),
    'Edge Function service role lacks outbox access';
  ASSERT NOT has_table_privilege('anon', 'public.venue_anchors', 'SELECT'),
    'anon can read venue anchors';
  ASSERT has_table_privilege('authenticated', 'public.venue_anchors', 'SELECT')
    AND has_table_privilege('authenticated', 'public.venue_anchors', 'INSERT'),
    'authenticated cannot manage own venue anchors';
  ASSERT has_table_privilege('service_role', 'public.venue_anchors', 'SELECT'),
    'service role cannot read venue anchors for co-location matching';
  ASSERT NOT has_table_privilege('anon', 'public.proximity_wake_requests', 'SELECT'),
    'anon can read proximity wake requests';
  ASSERT NOT has_table_privilege('authenticated', 'public.proximity_wake_requests', 'SELECT'),
    'authenticated can read proximity wake requests';
  ASSERT has_table_privilege('service_role', 'public.proximity_wake_requests', 'SELECT')
    AND has_table_privilege('service_role', 'public.proximity_wake_requests', 'UPDATE'),
    'Edge Function service role lacks proximity wake outbox access';
  ASSERT NOT has_table_privilege('anon', 'public.device_push_tokens', 'SELECT'),
    'anon can read push tokens';
  -- Clients must reach this table ONLY through register_push_token /
  -- unregister_push_token (SECURITY DEFINER). push_service.dart:74,98 does
  -- exactly that and never selects the table; the Edge functions read it as
  -- service_role. Until 2026-07-25 this asserted that authenticated held
  -- direct SELECT+INSERT — an expectation that was never true and is weaker
  -- than the shipped design. It went unnoticed because the assertion at the
  -- old claim_token line aborted this block before reaching anything below it.
  ASSERT NOT has_table_privilege('authenticated', 'public.device_push_tokens', 'SELECT')
    AND NOT has_table_privilege('authenticated', 'public.device_push_tokens', 'INSERT'),
    'authenticated has direct table access to push tokens; must go via RPC';
  ASSERT has_function_privilege('authenticated', 'public.register_push_token(text,text,text,text)', 'EXECUTE'),
    'authenticated cannot register a push token via RPC';
  ASSERT NOT has_function_privilege('anon', 'public.enqueue_proximity_wake(text,text)', 'EXECUTE'),
    'anon can enqueue proximity wake';
  ASSERT has_function_privilege('authenticated', 'public.enqueue_proximity_wake(text,text)', 'EXECUTE'),
    'authenticated cannot enqueue proximity wake';
  ASSERT NOT has_function_privilege('anon', 'public.register_push_token(text,text,text,text)', 'EXECUTE'),
    'anon can register push token';
  ASSERT has_function_privilege('authenticated', 'public.register_push_token(text,text,text,text)', 'EXECUTE'),
    'authenticated cannot register push token';

  ASSERT NOT has_function_privilege('anon', 'public.run_maintenance()', 'EXECUTE'),
    'anon can execute maintenance';
  ASSERT NOT has_function_privilege('authenticated', 'public.run_maintenance()', 'EXECUTE'),
    'client can execute maintenance';
  ASSERT has_function_privilege('service_role', 'public.run_maintenance()', 'EXECUTE'),
    'service role cannot execute maintenance';
  -- 6-arg signature. The 5-arg form this asserted on until 2026-07-25 was
  -- DROPPED at 0024:287 ("Drop the prior 5-arg signature first"), so
  -- has_function_privilege raised undefined_function and aborted this whole
  -- DO block — every assertion below it had been unreachable for 37
  -- migrations. p_accuracy was added by the same migration that dropped it.
  ASSERT NOT has_function_privilege('anon', 'public.claim_token(text,timestamptz,double precision,double precision,range_type,double precision)', 'EXECUTE'),
    'anon can claim a beacon token';
  ASSERT NOT has_function_privilege('anon', 'public.handle_new_user()', 'EXECUTE')
    AND NOT has_function_privilege('authenticated', 'public.handle_new_user()', 'EXECUTE'),
    'trigger function retained default execute privileges';

  -- Enumerating check: NO SECURITY DEFINER function in public may be reachable
  -- by anon. This exists because naming functions one at a time does not scale
  -- and did not work: claim_proximity_wake_batch (0057:120) shipped with no
  -- GRANT and no REVOKE, so its proacl was NULL, which means Postgres's
  -- built-in default of EXECUTE TO PUBLIC — which anon inherits. It was
  -- confirmed by execution to return other users' user_id and coarse location
  -- to an unauthenticated caller, straight through the table's own
  -- service_role-only RLS, and no assertion here would have caught it.
  --
  -- The 0019:2578 ALTER DEFAULT PRIVILEGES that was supposed to prevent this
  -- class does not work: a fresh SECURITY DEFINER function created as postgres
  -- in this schema still comes out anon-executable with proacl NULL. Adding
  -- anon/authenticated to that statement was tested and did not change it.
  -- So this assertion, not the default-privilege net, is the actual control.
  -- Every function in this schema is protected only by its explicit REVOKE.
  --
  -- Extension-owned functions (PostGIS st_estimatedextent etc.) are excluded:
  -- we do not own their privilege model.
  SELECT string_agg(p.oid::regprocedure::TEXT, ', ' ORDER BY p.oid::regprocedure::TEXT)
    INTO v_anon_secdef
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.prosecdef
    AND has_function_privilege('anon', p.oid, 'EXECUTE')
    AND NOT EXISTS (
      SELECT 1 FROM pg_depend d
      JOIN pg_extension e ON e.oid = d.refobjid
      WHERE d.objid = p.oid AND d.deptype = 'e'
    );
  ASSERT v_anon_secdef IS NULL,
    'SECURITY DEFINER function(s) executable by anon: ' || COALESCE(v_anon_secdef, '');

  SELECT array_agg(tablename::TEXT ORDER BY tablename) INTO v_realtime
  FROM pg_publication_tables
  WHERE pubname = 'supabase_realtime' AND schemaname = 'public';
  ASSERT v_realtime = ARRAY['matches', 'messages'],
    'unexpected table is exposed over realtime';

  ASSERT NOT EXISTS (
    SELECT 1 FROM storage.buckets
    WHERE id IN ('profile_photos', 'chat_media', 'verified_photos') AND public
  ), 'sensitive storage bucket is public';

  ASSERT public.encounter_reveal_delay_hours() >= 4,
    'server reveal delay is below four hours';

  DELETE FROM public.notification_outbox;
  INSERT INTO public.notification_outbox (user_id, kind, title, body, payload)
  VALUES (
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'new_match',
    'test', 'test', '{}'::jsonb
  );
  SELECT count(*) INTO v_claimed FROM public.claim_notification_batch(10);
  ASSERT v_claimed = 1, 'worker did not claim pending notification';
  SELECT count(*) INTO v_claimed FROM public.claim_notification_batch(10);
  ASSERT v_claimed = 0, 'notification was claimed by two workers';
  SELECT attempts INTO v_attempts FROM public.notification_outbox LIMIT 1;
  ASSERT v_attempts = 1, 'claim did not increment attempts exactly once';

  INSERT INTO storage.objects (bucket_id, name, owner)
  VALUES (
    'profile_photos',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/audit.jpg',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
  )
  RETURNING id, updated_at INTO v_object_id, v_object_updated;
  INSERT INTO public.photo_verifications (
    user_id, photo_path, slot_index, state,
    storage_object_id, storage_object_updated_at
  ) VALUES (
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/audit.jpg',
    5, 'ai_review', v_object_id, v_object_updated
  ) RETURNING id INTO v_verification;
  PERFORM public.complete_ai_photo_review(v_verification, 0.8, TRUE, 'audit');
  SELECT state INTO v_photo_state
  FROM public.photo_verifications WHERE id = v_verification;
  ASSERT v_photo_state = 'manual_review', 'AI review state transition failed';
  PERFORM public.decide_photo_verification(v_verification, FALSE, 'audit');
  SELECT state INTO v_photo_state
  FROM public.photo_verifications WHERE id = v_verification;
  ASSERT v_photo_state = 'rejected', 'manual review state transition failed';

  -- Make Dan discoverable only inside this rolled-back test transaction so the
  -- swipe assertion reaches the "existing encounter required" branch.
  UPDATE public.profiles
  SET is_photo_verified = TRUE, photo_urls = ARRAY['seed/dan_1.jpg']
  WHERE id = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
  INSERT INTO public.encounters (
    user_a, user_b, neighborhood, encounter_time, last_seen_at,
    range_type, confidence, status
  ) VALUES (
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'dddddddd-dddd-dddd-dddd-dddddddddddd',
    'Nearby', NOW(), NOW(), 'miles_10', 0.9, 'active'
  );
END $$;

SELECT set_config(
  'request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated","is_anonymous":false}',
  true
);
SET LOCAL ROLE authenticated;

DO $$
BEGIN
  BEGIN
    EXECUTE $sql$
      UPDATE public.profiles
      SET is_photo_verified = TRUE
      WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    $sql$;
    RAISE EXCEPTION 'direct profile update unexpectedly succeeded';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    PERFORM public.swipe_user(
      'dddddddd-dddd-dddd-dddd-dddddddddddd',
      'like', 'miles_10', 'Nearby'
    );
    RAISE EXCEPTION 'arbitrary UUID swipe unexpectedly succeeded';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    NULL;
  END;

  BEGIN
    PERFORM public.claim_token(
      '0123456789abcdef0123456789abcdef',
      NOW() + INTERVAL '10 minutes', NULL, NULL, 'feet_10'
    );
    RAISE EXCEPTION 'coordinate-free token claim unexpectedly succeeded';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  BEGIN
    PERFORM public.submit_ai_feedback(
      NULL::BIGINT, 'quality'::TEXT, 5::SMALLINT,
      NULL::TEXT, NULL::TEXT, '[]'::JSONB
    );
    RAISE EXCEPTION 'non-object feedback metadata unexpectedly succeeded';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  ASSERT NOT EXISTS (
    SELECT 1 FROM public.get_my_encounters(100, 0, 0)
    WHERE other_action IS NOT NULL
  ), 'pre-match reciprocal swipe leaked';
  ASSERT NOT EXISTS (
    SELECT 1 FROM public.get_my_encounters(100, 0, 0)
    WHERE other_user_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd'
  ), 'caller-controlled reveal delay exposed a fresh encounter';
END $$;

RESET ROLE;
ROLLBACK;
