-- =============================================================================
-- Seed test data for In Range (run AFTER migrations, as service_role / SQL editor)
-- =============================================================================
-- Creates 4 fake auth users + profiles + location pings + encounters + match.
-- Password for all: TestPass123!
--
-- Usage (Dashboard SQL Editor with service role, or psql as postgres):
--   \i supabase/seed/seed_test_data.sql
--
-- NOTE: auth.users inserts require service role / postgres. If this fails in
-- Dashboard free tier, create users via Auth UI then re-run the public.* block
-- with real UUIDs substituted below.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
DECLARE
  u1 UUID := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  u2 UUID := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  u3 UUID := 'cccccccc-cccc-cccc-cccc-cccccccccccc';
  u4 UUID := 'dddddddd-dddd-dddd-dddd-dddddddddddd';
  enc1 BIGINT;
  enc2 BIGINT;
  match1 BIGINT;
BEGIN
  -- Wipe prior seed (idempotent re-run)
  DELETE FROM public.messages WHERE match_id IN (
    SELECT id FROM public.matches WHERE user_a IN (u1,u2,u3,u4) OR user_b IN (u1,u2,u3,u4)
  );
  DELETE FROM public.matches WHERE user_a IN (u1,u2,u3,u4) OR user_b IN (u1,u2,u3,u4);
  DELETE FROM public.encounter_actions WHERE user_id IN (u1,u2,u3,u4);
  DELETE FROM public.encounters WHERE user_a IN (u1,u2,u3,u4) OR user_b IN (u1,u2,u3,u4);
  DELETE FROM public.location_pings WHERE user_id IN (u1,u2,u3,u4);
  DELETE FROM public.device_push_tokens WHERE user_id IN (u1,u2,u3,u4);
  DELETE FROM public.photo_verifications WHERE user_id IN (u1,u2,u3,u4);
  DELETE FROM public.profiles WHERE id IN (u1,u2,u3,u4);
  DELETE FROM auth.users WHERE id IN (u1,u2,u3,u4);

  -- auth.users (minimal columns; schema may vary slightly by Supabase version)
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, confirmation_token, recovery_token,
    email_change_token_new, email_change
  ) VALUES
    (
      u1, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
      'alice@inrange.test', crypt('TestPass123!', gen_salt('bf')),
      NOW(), '{"provider":"email","providers":["email"]}',
      '{"display_name":"Alice"}', NOW(), NOW(), '', '', '', ''
    ),
    (
      u2, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
      'bob@inrange.test', crypt('TestPass123!', gen_salt('bf')),
      NOW(), '{"provider":"email","providers":["email"]}',
      '{"display_name":"Bob"}', NOW(), NOW(), '', '', '', ''
    ),
    (
      u3, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
      'cara@inrange.test', crypt('TestPass123!', gen_salt('bf')),
      NOW(), '{"provider":"email","providers":["email"]}',
      '{"display_name":"Cara"}', NOW(), NOW(), '', '', '', ''
    ),
    (
      u4, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
      'dan@inrange.test', crypt('TestPass123!', gen_salt('bf')),
      NOW(), '{"provider":"email","providers":["email"]}',
      '{"display_name":"Dan"}', NOW(), NOW(), '', '', '', ''
    )
  ON CONFLICT (id) DO NOTHING;

  -- Profiles (trigger may have created stubs — upsert)
  INSERT INTO public.profiles (
    id, display_name, bio, dob, gender, sexual_preference, interests,
    photo_urls, is_photo_verified, photo_verification_status, neighborhood, is_active
  ) VALUES
    (
      u1, 'Alice', 'Coffee & hikes. Met you near downtown.',
      '1995-04-12', 'female', 'men',
      ARRAY['Coffee','Hiking','Music'],
      ARRAY['seed/alice_1.jpg'], TRUE, 'verified', 'Downtown', TRUE
    ),
    (
      u2, 'Bob', 'Tech + tacos.',
      '1992-08-03', 'male', 'women',
      ARRAY['Tech','Food','Gaming'],
      ARRAY['seed/bob_1.jpg'], TRUE, 'verified', 'Downtown', TRUE
    ),
    (
      u3, 'Cara', 'Art walks and dogs.',
      '1998-01-22', 'female', 'both',
      ARRAY['Art','Dogs','Travel'],
      ARRAY['seed/cara_1.jpg'], TRUE, 'verified', 'Eastside', TRUE
    ),
    (
      u4, 'Dan', 'Gym mornings.',
      '1990-11-09', 'male', 'women',
      ARRAY['Fitness','Movies'],
      ARRAY['seed/dan_1.jpg'], FALSE, 'pending', 'Westside', TRUE
    )
  ON CONFLICT (id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    bio = EXCLUDED.bio,
    dob = EXCLUDED.dob,
    gender = EXCLUDED.gender,
    sexual_preference = EXCLUDED.sexual_preference,
    interests = EXCLUDED.interests,
    photo_urls = EXCLUDED.photo_urls,
    is_photo_verified = EXCLUDED.is_photo_verified,
    photo_verification_status = EXCLUDED.photo_verification_status,
    neighborhood = EXCLUDED.neighborhood;

  -- Location pings near DTLA-ish coords (for miles correlation)
  INSERT INTO public.location_pings (user_id, geo, range_type, neighborhood, created_at)
  VALUES
    (u1, ST_SetSRID(ST_MakePoint(-118.2437, 34.0522), 4326)::geography, 'miles_10', 'Downtown', NOW() - INTERVAL '5 minutes'),
    (u2, ST_SetSRID(ST_MakePoint(-118.2440, 34.0525), 4326)::geography, 'miles_10', 'Downtown', NOW() - INTERVAL '4 minutes'),
    (u3, ST_SetSRID(ST_MakePoint(-118.2400, 34.0500), 4326)::geography, 'miles_5', 'Eastside', NOW() - INTERVAL '8 minutes'),
    (u4, ST_SetSRID(ST_MakePoint(-118.2800, 34.0600), 4326)::geography, 'miles_25', 'Westside', NOW() - INTERVAL '12 minutes');

  -- Encounters (Alice↔Bob feet, Alice↔Cara miles) — old enough for 0h reveal
  INSERT INTO public.encounters (
    user_a, user_b, neighborhood, encounter_time, range_type, confidence, status
  ) VALUES
    (u1, u2, 'Downtown coffee shop', NOW() - INTERVAL '5 hours', 'feet_20', 0.92, 'active'),
    (u1, u3, 'Eastside', NOW() - INTERVAL '6 hours', 'miles_5', 0.80, 'active'),
    (u2, u3, 'Downtown', NOW() - INTERVAL '3 hours', 'miles_10', 0.75, 'active')
  RETURNING id INTO enc1;

  -- Mutual like → match Alice & Bob on first encounter
  SELECT id INTO enc1 FROM public.encounters
  WHERE user_a = u1 AND user_b = u2 ORDER BY id DESC LIMIT 1;

  INSERT INTO public.encounter_actions (user_id, encounter_id, action)
  VALUES (u1, enc1, 'like'), (u2, enc1, 'like')
  ON CONFLICT DO NOTHING;

  UPDATE public.encounters SET status = 'matched' WHERE id = enc1;

  INSERT INTO public.matches (encounter_id, user_a, user_b, matched_at)
  VALUES (enc1, u1, u2, NOW() - INTERVAL '2 hours')
  RETURNING id INTO match1;

  INSERT INTO public.messages (match_id, sender_id, content, message_type)
  VALUES
    (match1, u1, 'Hey! I saw you were at Downtown coffee shop. Were you there for the open mic?', 'text'),
    (match1, u2, 'Yes! Small world. Want to grab coffee again?', 'text');

  -- Push token placeholders (FCM mock)
  INSERT INTO public.device_push_tokens (user_id, token, platform)
  VALUES
    (u1, 'mock-fcm-token-alice', 'android'),
    (u2, 'mock-fcm-token-bob', 'android')
  ON CONFLICT DO NOTHING;

  -- Pending photo verification for Dan
  INSERT INTO public.photo_verifications (user_id, photo_path, slot_index, state)
  VALUES (u4, u4::text || '/0-seed.jpg', 0, 'ai_review');

  RAISE NOTICE 'Seed complete: alice/bob/cara/dan @inrange.test password TestPass123!';
  RAISE NOTICE 'Encounters + 1 match (Alice/Bob) with sample chat.';
END $$;
