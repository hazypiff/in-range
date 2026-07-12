\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
  v_missing_rls TEXT;
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
      'ai_feedback', 'app_settings'
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

  ASSERT NOT has_function_privilege('anon', 'public.run_maintenance()', 'EXECUTE'),
    'anon can execute maintenance';
  ASSERT NOT has_function_privilege('authenticated', 'public.run_maintenance()', 'EXECUTE'),
    'client can execute maintenance';
  ASSERT has_function_privilege('service_role', 'public.run_maintenance()', 'EXECUTE'),
    'service role cannot execute maintenance';
  ASSERT NOT has_function_privilege('anon', 'public.claim_token(text,timestamptz,double precision,double precision,range_type)', 'EXECUTE'),
    'anon can claim a beacon token';
  ASSERT NOT has_function_privilege('anon', 'public.handle_new_user()', 'EXECUTE')
    AND NOT has_function_privilege('authenticated', 'public.handle_new_user()', 'EXECUTE'),
    'trigger function retained default execute privileges';

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
