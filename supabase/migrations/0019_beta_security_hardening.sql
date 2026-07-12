-- =============================================================================
-- Migration 0019: beta security, privacy, and state-machine hardening
-- =============================================================================
-- Fixes verified during the 2026-07-11 ultimate audit:
--   * RPCs were executable by PUBLIC unless explicitly revoked.
--   * direct table writes bypassed profile/photo/message/swipe validation.
--   * client-controlled reveal delay and realtime exposed fresh encounters.
--   * swipe_user could manufacture an encounter with any UUID.
--   * Locals accepted arbitrary query coordinates and leaked exact timing/range.
--   * encounter_time was refreshed continuously, so the 4h reveal never elapsed.
--   * blocks did not revoke direct message/storage/realtime access.
--   * token claims had no format/window/uniqueness enforcement.
--   * match expiry and push queue claiming were client/worker race prone.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Schema invariants and server-owned configuration
-- -----------------------------------------------------------------------------

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS age_verified BOOLEAN NOT NULL DEFAULT FALSE;

-- Existing users who already passed mandatory photo review and have an adult DOB
-- are the only safe automatic backfill. Everyone else re-verifies on profile save.
UPDATE public.profiles
SET age_verified = TRUE
WHERE is_photo_verified = TRUE
  AND dob <= CURRENT_DATE - INTERVAL '18 years';

ALTER TABLE public.encounters
  ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ;

UPDATE public.encounters
SET last_seen_at = encounter_time
WHERE last_seen_at IS NULL;

ALTER TABLE public.encounters
  ALTER COLUMN last_seen_at SET DEFAULT NOW(),
  ALTER COLUMN last_seen_at SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_encounters_reveal
  ON public.encounters (status, encounter_time DESC);
CREATE INDEX IF NOT EXISTS idx_encounters_last_seen
  ON public.encounters (status, last_seen_at DESC);

ALTER TABLE public.matches
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'active',
  ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS ended_at TIMESTAMPTZ;

UPDATE public.matches
SET expires_at = matched_at + INTERVAL '24 hours'
WHERE status = 'active'
  AND expires_at IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.messages msg WHERE msg.match_id = public.matches.id
  );

ALTER TABLE public.matches
  DROP CONSTRAINT IF EXISTS matches_status_check;
ALTER TABLE public.matches
  ADD CONSTRAINT matches_status_check
  CHECK (status IN ('active', 'expired', 'blocked'));

CREATE INDEX IF NOT EXISTS idx_matches_status_expiry
  ON public.matches (status, expires_at)
  WHERE status = 'active';

ALTER TABLE public.messages
  DROP CONSTRAINT IF EXISTS messages_content_length_check;
ALTER TABLE public.messages
  ADD CONSTRAINT messages_content_length_check
  CHECK (content IS NULL OR char_length(content) <= 4000) NOT VALID;

ALTER TABLE public.messages
  DROP CONSTRAINT IF EXISTS messages_metadata_size_check;
ALTER TABLE public.messages
  ADD CONSTRAINT messages_metadata_size_check
  CHECK (metadata IS NULL OR octet_length(metadata::text) <= 16384) NOT VALID;

ALTER TABLE public.messages
  DROP CONSTRAINT IF EXISTS messages_payload_check;
ALTER TABLE public.messages
  ADD CONSTRAINT messages_payload_check
  CHECK (
    (message_type = 'text' AND content IS NOT NULL AND length(trim(content)) > 0)
    OR message_type IN ('photo', 'voice', 'video')
  ) NOT VALID;

ALTER TABLE public.ai_feedback
  DROP CONSTRAINT IF EXISTS ai_feedback_metadata_size_check;
ALTER TABLE public.ai_feedback
  ADD CONSTRAINT ai_feedback_metadata_size_check
  CHECK (octet_length(metadata::TEXT) <= 16384) NOT VALID;

ALTER TABLE public.photo_verifications
  ADD COLUMN IF NOT EXISTS storage_object_id UUID,
  ADD COLUMN IF NOT EXISTS storage_object_updated_at TIMESTAMPTZ;

ALTER TABLE public.token_claims
  ADD COLUMN IF NOT EXISTS last_claimed_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- One current row per user and one owner per unguessable advertised token.
DELETE FROM public.token_claims older
USING public.token_claims newer
WHERE older.user_id = newer.user_id
  AND (older.valid_from, older.id) < (newer.valid_from, newer.id);

DELETE FROM public.token_claims older
USING public.token_claims newer
WHERE older.token = newer.token
  AND older.id < newer.id;

CREATE UNIQUE INDEX IF NOT EXISTS uq_token_claims_user
  ON public.token_claims (user_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_token_claims_token
  ON public.token_claims (token);

ALTER TABLE public.notification_outbox
  DROP CONSTRAINT IF EXISTS notification_outbox_status_check;
ALTER TABLE public.notification_outbox
  ADD COLUMN IF NOT EXISTS processing_at TIMESTAMPTZ;
ALTER TABLE public.notification_outbox
  ADD CONSTRAINT notification_outbox_status_check
  CHECK (status IN ('pending', 'processing', 'sent', 'failed', 'skipped'));

CREATE TABLE IF NOT EXISTS public.app_settings (
  key         TEXT PRIMARY KEY,
  value_num   NUMERIC NOT NULL,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Service role manages app settings" ON public.app_settings;
CREATE POLICY "Service role manages app settings"
  ON public.app_settings FOR ALL
  TO service_role
  USING (TRUE)
  WITH CHECK (TRUE);

INSERT INTO public.app_settings (key, value_num)
VALUES ('encounter_reveal_delay_hours', 4)
ON CONFLICT (key) DO NOTHING;

REVOKE ALL ON TABLE public.app_settings FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.app_settings TO service_role;

CREATE OR REPLACE FUNCTION public.encounter_reveal_delay_hours()
RETURNS NUMERIC
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT LEAST(168::NUMERIC, GREATEST(0::NUMERIC, COALESCE(
    (SELECT value_num FROM public.app_settings
     WHERE key = 'encounter_reveal_delay_hours'),
    4::NUMERIC
  )));
$$;

CREATE OR REPLACE FUNCTION public.is_discoverable_user(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = p_user_id
      AND p.is_active = TRUE
      AND COALESCE(p.is_paused, FALSE) = FALSE
      AND p.deleted_at IS NULL
      AND COALESCE(p.is_incognito, FALSE) = FALSE
      AND COALESCE(p.age_verified, FALSE) = TRUE
      AND p.dob <= CURRENT_DATE - INTERVAL '18 years'
      AND COALESCE(p.is_photo_verified, FALSE) = TRUE
      AND COALESCE(array_length(p.photo_urls, 1), 0) > 0
  );
$$;

CREATE OR REPLACE FUNCTION public.current_user_can_discover()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT auth.uid() IS NOT NULL
    AND COALESCE(auth.jwt()->>'is_anonymous', 'false') <> 'true'
    AND public.is_discoverable_user(auth.uid());
$$;

CREATE OR REPLACE FUNCTION public.can_access_match(p_match_id BIGINT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.matches m
    WHERE m.id = p_match_id
      AND m.status = 'active'
      AND (m.user_a = auth.uid() OR m.user_b = auth.uid())
      AND NOT EXISTS (
        SELECT 1 FROM public.blocks b
        WHERE (b.blocker_id = m.user_a AND b.blocked_id = m.user_b)
           OR (b.blocker_id = m.user_b AND b.blocked_id = m.user_a)
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.can_view_profile_photos(p_owner UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT auth.uid() IS NOT NULL AND (
    p_owner = auth.uid()
    OR (
      public.is_discoverable_user(p_owner)
      AND NOT EXISTS (
        SELECT 1 FROM public.blocks b
        WHERE (b.blocker_id = auth.uid() AND b.blocked_id = p_owner)
           OR (b.blocker_id = p_owner AND b.blocked_id = auth.uid())
      )
      AND (
        EXISTS (
          SELECT 1 FROM public.matches m
          WHERE m.status = 'active'
            AND ((m.user_a = auth.uid() AND m.user_b = p_owner)
              OR (m.user_b = auth.uid() AND m.user_a = p_owner))
        )
        OR EXISTS (
          SELECT 1 FROM public.encounters e
          WHERE e.status = 'active'
            AND e.encounter_time <= NOW() - make_interval(
              secs => (public.encounter_reveal_delay_hours() * 3600)::DOUBLE PRECISION
            )
            AND ((e.user_a = auth.uid() AND e.user_b = p_owner)
              OR (e.user_b = auth.uid() AND e.user_a = p_owner))
        )
      )
    )
  );
$$;

CREATE OR REPLACE FUNCTION public.can_modify_profile_photo(p_path TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT auth.uid() IS NOT NULL
    AND split_part(p_path, '/', 1) = auth.uid()::TEXT
    AND NOT EXISTS (
      SELECT 1 FROM public.photo_verifications pv
      WHERE pv.user_id = auth.uid()
        AND pv.photo_path = p_path
        AND pv.state IN ('ai_review', 'manual_review', 'approved')
    );
$$;

-- -----------------------------------------------------------------------------
-- 2. RLS and Storage: relationship scoped, block aware, RPC-only writes
-- -----------------------------------------------------------------------------

DROP POLICY IF EXISTS "System can insert encounters" ON public.encounters;
DROP POLICY IF EXISTS "Users see their own encounters" ON public.encounters;
CREATE POLICY "Users see own revealed encounters"
  ON public.encounters FOR SELECT
  TO authenticated
  USING (
    (user_a = auth.uid() OR user_b = auth.uid())
    AND encounter_time <= NOW() - make_interval(
      secs => (public.encounter_reveal_delay_hours() * 3600)::DOUBLE PRECISION
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.blocks b
      WHERE (b.blocker_id = user_a AND b.blocked_id = user_b)
         OR (b.blocker_id = user_b AND b.blocked_id = user_a)
    )
  );

DROP POLICY IF EXISTS "Users manage own actions" ON public.encounter_actions;
CREATE POLICY "Users read own actions"
  ON public.encounter_actions FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users see their matches" ON public.matches;
CREATE POLICY "Users see active unblocked matches"
  ON public.matches FOR SELECT
  TO authenticated
  USING (public.can_access_match(id));

DROP POLICY IF EXISTS "Users see messages in their matches" ON public.messages;
CREATE POLICY "Users see messages in active unblocked matches"
  ON public.messages FOR SELECT
  TO authenticated
  USING (public.can_access_match(match_id));

DROP POLICY IF EXISTS "Users can send messages in their matches" ON public.messages;
DROP POLICY IF EXISTS "Users update messages in their matches" ON public.messages;

DROP POLICY IF EXISTS "Users can manage their own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can read limited public profiles" ON public.profiles;
CREATE POLICY "Users read own profile"
  ON public.profiles FOR SELECT
  TO authenticated
  USING (id = auth.uid());

-- Profile photos: unique uploads, immutable while under review/approved.
DROP POLICY IF EXISTS "Users upload own profile photos" ON storage.objects;
CREATE POLICY "Users upload own profile photos"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'profile_photos'
    AND (storage.foldername(name))[1] = auth.uid()::TEXT
  );

DROP POLICY IF EXISTS "Users update own profile photos" ON storage.objects;

DROP POLICY IF EXISTS "Users delete own profile photos" ON storage.objects;
CREATE POLICY "Users delete unreviewed own profile photos"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'profile_photos'
    AND public.can_modify_profile_photo(name)
  );

DROP POLICY IF EXISTS "Users read own profile photos" ON storage.objects;
CREATE POLICY "Users read own profile photos"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'profile_photos'
    AND (storage.foldername(name))[1] = auth.uid()::TEXT
  );

DROP POLICY IF EXISTS "Encounter or match peers read profile photos" ON storage.objects;
CREATE POLICY "Encounter or match peers read profile photos"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'profile_photos'
    AND public.can_view_profile_photos(
      NULLIF((storage.foldername(name))[1], '')::UUID
    )
  );

DROP POLICY IF EXISTS "Users read own verified photos" ON storage.objects;
CREATE POLICY "Users read own verified photos"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'verified_photos'
    AND (storage.foldername(name))[1] = auth.uid()::TEXT
  );

DROP POLICY IF EXISTS "Encounter or match peers read verified photos" ON storage.objects;
CREATE POLICY "Encounter or match peers read verified photos"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'verified_photos'
    AND public.can_view_profile_photos(
      NULLIF((storage.foldername(name))[1], '')::UUID
    )
  );

DROP POLICY IF EXISTS "Match participants upload chat media" ON storage.objects;
CREATE POLICY "Match participants upload chat media"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'chat_media'
    AND (storage.foldername(name))[1] ~ '^[0-9]+$'
    AND (storage.foldername(name))[2] = auth.uid()::TEXT
    AND public.can_access_match(((storage.foldername(name))[1])::BIGINT)
  );

DROP POLICY IF EXISTS "Match participants read chat media" ON storage.objects;
CREATE POLICY "Match participants read chat media"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'chat_media'
    AND (storage.foldername(name))[1] ~ '^[0-9]+$'
    AND public.can_access_match(((storage.foldername(name))[1])::BIGINT)
  );

DROP POLICY IF EXISTS "Match participants delete own chat media" ON storage.objects;
CREATE POLICY "Match participants delete own chat media"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'chat_media'
    AND (storage.foldername(name))[1] ~ '^[0-9]+$'
    AND (storage.foldername(name))[2] = auth.uid()::TEXT
    AND public.can_access_match(((storage.foldername(name))[1])::BIGINT)
  );

-- Fresh encounters/actions must never stream around the server reveal delay.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public' AND tablename = 'encounters'
  ) THEN
    ALTER PUBLICATION supabase_realtime DROP TABLE public.encounters;
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public' AND tablename = 'encounter_actions'
  ) THEN
    ALTER PUBLICATION supabase_realtime DROP TABLE public.encounter_actions;
  END IF;
END $$;

-- SECURITY DEFINER RPCs are the only mutation surface for application tables.
REVOKE ALL ON TABLE
  public.profiles,
  public.token_claims,
  public.sightings,
  public.location_pings,
  public.encounters,
  public.encounter_actions,
  public.matches,
  public.messages,
  public.photo_verifications,
  public.blocks,
  public.reports,
  public.subscriptions,
  public.boosts,
  public.ad_impressions,
  public.device_push_tokens,
  public.notification_outbox,
  public.ai_runs,
  public.ai_events,
  public.ai_feedback
FROM PUBLIC, anon, authenticated;

-- Edge Functions use the service role and still need ordinary SQL privileges;
-- BYPASSRLS does not itself grant SELECT/INSERT/UPDATE/DELETE.
GRANT ALL ON TABLE
  public.profiles,
  public.token_claims,
  public.sightings,
  public.location_pings,
  public.encounters,
  public.encounter_actions,
  public.matches,
  public.messages,
  public.photo_verifications,
  public.blocks,
  public.reports,
  public.subscriptions,
  public.boosts,
  public.ad_impressions,
  public.device_push_tokens,
  public.notification_outbox,
  public.ai_runs,
  public.ai_events,
  public.ai_feedback,
  public.app_settings
TO service_role;

REVOKE ALL ON TABLE public.v_pending_photo_reviews
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.v_pending_photo_reviews TO service_role;

-- Chat history/realtime is the sole direct-table client read.
GRANT SELECT ON TABLE public.messages TO authenticated;

REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC, anon, authenticated;
GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO service_role;

-- -----------------------------------------------------------------------------
-- 3. Auth/profile RPCs: exact age gate and server-owned account flags
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_dob DATE := (CURRENT_DATE - INTERVAL '25 years')::DATE;
  v_raw_dob TEXT := NULLIF(trim(NEW.raw_user_meta_data->>'dob'), '');
BEGIN
  -- Auth metadata is untrusted. A malformed date must not abort all signups.
  IF v_raw_dob IS NOT NULL THEN
    BEGIN
      v_dob := v_raw_dob::DATE;
      IF v_dob > CURRENT_DATE OR v_dob < DATE '1900-01-01' THEN
        v_dob := (CURRENT_DATE - INTERVAL '25 years')::DATE;
      END IF;
    EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN
      v_dob := (CURRENT_DATE - INTERVAL '25 years')::DATE;
    END;
  END IF;

  INSERT INTO public.profiles (
    id, display_name, dob, age_verified, email_hint, phone_hint,
    created_at, updated_at
  )
  VALUES (
    NEW.id,
    left(COALESCE(
      NULLIF(trim(NEW.raw_user_meta_data->>'display_name'), ''),
      NULLIF(trim(NEW.raw_user_meta_data->>'full_name'), ''),
      NULLIF(split_part(COALESCE(NEW.email, ''), '@', 1), ''),
      'New user'
    ), 80),
    v_dob,
    FALSE,
    NEW.email,
    NEW.phone,
    NOW(),
    NOW()
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_my_profile(
  p_display_name TEXT,
  p_bio TEXT DEFAULT NULL,
  p_dob DATE DEFAULT NULL,
  p_gender TEXT DEFAULT NULL,
  p_sexual_preference TEXT DEFAULT NULL,
  p_interests TEXT[] DEFAULT NULL,
  p_photo_urls TEXT[] DEFAULT NULL,
  p_beacon_default_range public.range_type DEFAULT 'miles_10'
)
RETURNS public.profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_row public.profiles;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '28000';
  END IF;
  IF p_display_name IS NULL OR length(trim(p_display_name)) NOT BETWEEN 1 AND 80 THEN
    RAISE EXCEPTION 'Display name must be 1..80 characters' USING ERRCODE = '22023';
  END IF;
  IF p_display_name ~ '[[:cntrl:]]' THEN
    RAISE EXCEPTION 'Display name contains invalid characters' USING ERRCODE = '22023';
  END IF;
  IF p_dob IS NULL THEN
    RAISE EXCEPTION 'Date of birth required' USING ERRCODE = '22023';
  END IF;
  IF p_dob < DATE '1900-01-01' OR p_dob > CURRENT_DATE - INTERVAL '18 years' THEN
    RAISE EXCEPTION 'Must be 18 or older' USING ERRCODE = '22023';
  END IF;
  IF p_bio IS NOT NULL AND char_length(p_bio) > 500 THEN
    RAISE EXCEPTION 'Bio max 500 characters' USING ERRCODE = '22023';
  END IF;
  IF p_interests IS NOT NULL AND COALESCE(array_length(p_interests, 1), 0) > 20 THEN
    RAISE EXCEPTION 'Max 20 interests' USING ERRCODE = '22023';
  END IF;
  IF p_interests IS NOT NULL AND EXISTS (
    SELECT 1 FROM unnest(p_interests) i
    WHERE length(trim(i)) NOT BETWEEN 1 AND 50
  ) THEN
    RAISE EXCEPTION 'Interest must be 1..50 characters' USING ERRCODE = '22023';
  END IF;
  IF p_photo_urls IS NOT NULL AND COALESCE(array_length(p_photo_urls, 1), 0) > 6 THEN
    RAISE EXCEPTION 'Max 6 photos' USING ERRCODE = '22023';
  END IF;
  IF p_photo_urls IS NOT NULL AND EXISTS (
    SELECT 1 FROM unnest(p_photo_urls) photo_path
    WHERE split_part(photo_path, '/', 1) <> v_uid::TEXT
       OR photo_path LIKE 'http://%'
       OR photo_path LIKE 'https://%'
       OR photo_path LIKE '/%'
       OR photo_path LIKE '%\\%'
  ) THEN
    RAISE EXCEPTION 'Photo paths must be in your storage folder' USING ERRCODE = '22023';
  END IF;
  IF p_photo_urls IS NOT NULL AND EXISTS (
    SELECT 1 FROM unnest(p_photo_urls) photo_path
    WHERE NOT EXISTS (
      SELECT 1 FROM storage.objects o
      WHERE o.bucket_id = 'profile_photos' AND o.name = photo_path
    )
  ) THEN
    RAISE EXCEPTION 'Profile photo object not found' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.profiles (
    id, display_name, bio, dob, age_verified, gender, sexual_preference,
    interests, photo_urls, beacon_default_range, updated_at
  )
  VALUES (
    v_uid, trim(p_display_name), NULLIF(trim(p_bio), ''), p_dob, TRUE,
    p_gender, p_sexual_preference, p_interests, p_photo_urls,
    p_beacon_default_range, NOW()
  )
  ON CONFLICT (id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    bio = EXCLUDED.bio,
    dob = EXCLUDED.dob,
    age_verified = TRUE,
    gender = EXCLUDED.gender,
    sexual_preference = EXCLUDED.sexual_preference,
    interests = EXCLUDED.interests,
    photo_urls = COALESCE(EXCLUDED.photo_urls, public.profiles.photo_urls),
    beacon_default_range = EXCLUDED.beacon_default_range,
    updated_at = NOW()
  RETURNING * INTO v_row;

  -- Verification follows the currently referenced immutable object path, not a
  -- client-provided boolean.
  UPDATE public.profiles p
  SET is_photo_verified = EXISTS (
        SELECT 1 FROM public.photo_verifications pv
        WHERE pv.user_id = v_uid
          AND pv.state = 'approved'
          AND pv.photo_path = ANY(COALESCE(p.photo_urls, ARRAY[]::TEXT[]))
      ),
      photo_verification_status = CASE
        WHEN EXISTS (
          SELECT 1 FROM public.photo_verifications pv
          WHERE pv.user_id = v_uid
            AND pv.state = 'approved'
            AND pv.photo_path = ANY(COALESCE(p.photo_urls, ARRAY[]::TEXT[]))
        ) THEN 'verified'
        ELSE 'pending'
      END
  WHERE p.id = v_uid
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_profile()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT CASE WHEN p.id IS NULL THEN NULL ELSE jsonb_build_object(
    'id', p.id,
    'display_name', p.display_name,
    'bio', p.bio,
    'dob', p.dob,
    'age_verified', p.age_verified,
    'gender', p.gender,
    'sexual_preference', p.sexual_preference,
    'interests', p.interests,
    'photo_urls', p.photo_urls,
    'is_photo_verified', p.is_photo_verified,
    'photo_verification_status', p.photo_verification_status,
    'is_paused', p.is_paused,
    'is_incognito', p.is_incognito,
    'is_subscriber', p.is_subscriber,
    'subscription_tier', p.subscription_tier,
    'beacon_default_range', p.beacon_default_range
  ) END
  FROM (SELECT auth.uid() AS uid) me
  LEFT JOIN public.profiles p ON p.id = me.uid;
$$;

CREATE OR REPLACE FUNCTION public.set_account_paused(p_paused BOOLEAN)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '28000';
  END IF;
  UPDATE public.profiles
  SET is_paused = COALESCE(p_paused, TRUE), updated_at = NOW()
  WHERE id = auth.uid();
  IF COALESCE(p_paused, TRUE) THEN
    DELETE FROM public.token_claims WHERE user_id = auth.uid();
    DELETE FROM public.location_pings WHERE user_id = auth.uid();
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_incognito(p_enabled BOOLEAN)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '28000';
  END IF;
  IF COALESCE(p_enabled, FALSE) AND NOT public.is_subscriber(auth.uid()) THEN
    RAISE EXCEPTION 'Subscription required for Incognito Mode'
      USING ERRCODE = '42501';
  END IF;
  UPDATE public.profiles
  SET is_incognito = COALESCE(p_enabled, FALSE), updated_at = NOW()
  WHERE id = auth.uid();
  IF COALESCE(p_enabled, FALSE) THEN
    DELETE FROM public.token_claims WHERE user_id = auth.uid();
    DELETE FROM public.location_pings WHERE user_id = auth.uid();
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.backend_health()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog
AS $$ SELECT auth.uid() IS NOT NULL $$;

CREATE OR REPLACE FUNCTION public.submit_ai_feedback(
  p_event_id BIGINT DEFAULT NULL,
  p_feedback_type TEXT DEFAULT 'quality',
  p_rating SMALLINT DEFAULT NULL,
  p_label TEXT DEFAULT NULL,
  p_notes TEXT DEFAULT NULL,
  p_metadata JSONB DEFAULT '{}'::JSONB
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_event_user UUID;
  v_event_run UUID;
  v_id BIGINT;
  v_type TEXT := COALESCE(NULLIF(trim(p_feedback_type), ''), 'quality');
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '28000';
  END IF;
  IF v_type NOT IN (
    'thumbs_up', 'thumbs_down', 'correction', 'appeal',
    'bug', 'safety', 'quality', 'other'
  ) THEN
    RAISE EXCEPTION 'Invalid feedback type' USING ERRCODE = '22023';
  END IF;
  IF p_rating IS NOT NULL AND p_rating NOT BETWEEN 1 AND 5 THEN
    RAISE EXCEPTION 'Rating must be 1..5' USING ERRCODE = '22023';
  END IF;
  IF char_length(COALESCE(p_label, '')) > 80
     OR char_length(COALESCE(p_notes, '')) > 2000 THEN
    RAISE EXCEPTION 'Feedback text is too long' USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(COALESCE(p_metadata, '{}'::JSONB)) <> 'object'
     OR octet_length(COALESCE(p_metadata, '{}'::JSONB)::TEXT) > 16384 THEN
    RAISE EXCEPTION 'Invalid feedback metadata' USING ERRCODE = '22023';
  END IF;
  IF (
    SELECT count(*) FROM public.ai_feedback f
    WHERE f.user_id = v_uid AND f.created_at > NOW() - INTERVAL '1 hour'
  ) >= 20 THEN
    RAISE EXCEPTION 'Feedback rate limit' USING ERRCODE = '54000';
  END IF;

  IF p_event_id IS NOT NULL THEN
    SELECT user_id, run_id INTO v_event_user, v_event_run
    FROM public.ai_events WHERE id = p_event_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'AI event not found' USING ERRCODE = 'P0002';
    END IF;
    IF v_event_user IS DISTINCT FROM v_uid THEN
      RAISE EXCEPTION 'Not authorized for this AI event' USING ERRCODE = '42501';
    END IF;
  END IF;

  INSERT INTO public.ai_feedback (
    event_id, run_id, user_id, feedback_type, rating, label, notes, metadata
  ) VALUES (
    p_event_id, v_event_run, v_uid, v_type, p_rating,
    NULLIF(trim(p_label), ''), NULLIF(trim(p_notes), ''),
    COALESCE(p_metadata, '{}'::JSONB)
  ) RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- -----------------------------------------------------------------------------
-- 4. Ephemeral claims and BLE sightings
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.claim_token(
  p_token TEXT,
  p_valid_until TIMESTAMPTZ,
  p_lat DOUBLE PRECISION DEFAULT NULL,
  p_lon DOUBLE PRECISION DEFAULT NULL,
  p_range public.range_type DEFAULT 'miles_10'
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_now TIMESTAMPTZ := clock_timestamp();
  v_last TIMESTAMPTZ;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '28000';
  END IF;
  IF NOT public.current_user_can_discover() THEN
    RAISE EXCEPTION 'Complete age and photo verification before using Beacon'
      USING ERRCODE = '42501';
  END IF;
  IF p_token IS NULL OR p_token !~ '^[0-9a-f]{32}$' THEN
    RAISE EXCEPTION 'Invalid beacon token' USING ERRCODE = '22023';
  END IF;
  IF p_valid_until IS NULL
     OR p_valid_until <= v_now + INTERVAL '1 minute'
     OR p_valid_until > v_now + INTERVAL '21 minutes' THEN
    RAISE EXCEPTION 'Token validity must end within 1..21 minutes'
      USING ERRCODE = '22023';
  END IF;
  IF p_lat IS NULL OR p_lon IS NULL THEN
    RAISE EXCEPTION 'Fresh coordinates are required' USING ERRCODE = '22023';
  END IF;
  IF p_lat NOT BETWEEN -90 AND 90 OR p_lon NOT BETWEEN -180 AND 180 THEN
    RAISE EXCEPTION 'Invalid coordinates' USING ERRCODE = '22023';
  END IF;

  SELECT last_claimed_at INTO v_last
  FROM public.token_claims
  WHERE user_id = v_uid;
  IF v_last IS NOT NULL AND v_last > v_now - INTERVAL '5 seconds' THEN
    RAISE EXCEPTION 'Beacon claim rate limit' USING ERRCODE = '54000';
  END IF;

  INSERT INTO public.token_claims (
    user_id, token, valid_from, valid_until, approx_lat, approx_lon,
    range_type, created_at, last_claimed_at
  )
  VALUES (
    v_uid, lower(p_token), v_now, p_valid_until, p_lat, p_lon,
    p_range, v_now, v_now
  )
  ON CONFLICT (user_id) DO UPDATE SET
    token = EXCLUDED.token,
    valid_from = EXCLUDED.valid_from,
    valid_until = EXCLUDED.valid_until,
    approx_lat = EXCLUDED.approx_lat,
    approx_lon = EXCLUDED.approx_lon,
    range_type = EXCLUDED.range_type,
    last_claimed_at = EXCLUDED.last_claimed_at;
END;
$$;

CREATE OR REPLACE FUNCTION public.release_token()
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  DELETE FROM public.token_claims WHERE user_id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.record_sighting(
  p_observed_token TEXT,
  p_lat DOUBLE PRECISION DEFAULT NULL,
  p_lon DOUBLE PRECISION DEFAULT NULL,
  p_rssi INTEGER DEFAULT NULL,
  p_observed_at TIMESTAMPTZ DEFAULT NOW(),
  p_range public.range_type DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_now TIMESTAMPTZ := clock_timestamp();
  v_id BIGINT;
  v_range public.range_type := COALESCE(p_range, 'feet_10');
  v_radius DOUBLE PRECISION;
  v_window INT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '28000';
  END IF;
  IF NOT public.current_user_can_discover() THEN
    RAISE EXCEPTION 'Account is not discoverable' USING ERRCODE = '42501';
  END IF;
  IF p_observed_token IS NULL OR lower(p_observed_token) !~ '^[0-9a-f]{32}$' THEN
    RAISE EXCEPTION 'Invalid beacon token' USING ERRCODE = '22023';
  END IF;
  IF p_observed_at IS NULL
     OR p_observed_at < v_now - INTERVAL '10 minutes'
     OR p_observed_at > v_now + INTERVAL '1 minute' THEN
    RAISE EXCEPTION 'Invalid sighting time' USING ERRCODE = '22023';
  END IF;
  IF p_rssi IS NULL OR p_rssi NOT BETWEEN -127 AND 20 THEN
    RAISE EXCEPTION 'Invalid RSSI' USING ERRCODE = '22023';
  END IF;
  IF p_lat IS NULL OR p_lon IS NULL THEN
    RAISE EXCEPTION 'Fresh coordinates are required' USING ERRCODE = '22023';
  END IF;
  IF p_lat NOT BETWEEN -90 AND 90 OR p_lon NOT BETWEEN -180 AND 180 THEN
    RAISE EXCEPTION 'Invalid coordinates' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.token_claims tc
    WHERE tc.token = lower(p_observed_token)
      AND tc.user_id <> v_uid
      AND tc.valid_until > v_now - INTERVAL '2 minutes'
  ) THEN
    RAISE EXCEPTION 'Unknown or expired beacon token' USING ERRCODE = '22023';
  END IF;
  IF (
    SELECT count(*) FROM public.sightings s
    WHERE s.observer_user_id = v_uid
      AND s.created_at > v_now - INTERVAL '1 minute'
  ) >= 120 THEN
    RAISE EXCEPTION 'Sighting rate limit' USING ERRCODE = '54000';
  END IF;

  SELECT id INTO v_id
  FROM public.sightings
  WHERE observer_user_id = v_uid
    AND observed_token = lower(p_observed_token)
    AND observed_at > v_now - INTERVAL '30 seconds'
  ORDER BY observed_at DESC
  LIMIT 1;

  IF v_id IS NULL THEN
    INSERT INTO public.sightings (
      observer_user_id, observed_token, rssi, observed_at,
      observer_lat, observer_lon, range_type
    ) VALUES (
      v_uid, lower(p_observed_token), p_rssi, p_observed_at,
      p_lat, p_lon, v_range
    ) RETURNING id INTO v_id;
  ELSE
    UPDATE public.sightings
    SET rssi = GREATEST(rssi, p_rssi), observed_at = p_observed_at,
        observer_lat = COALESCE(p_lat, observer_lat),
        observer_lon = COALESCE(p_lon, observer_lon),
        range_type = v_range
    WHERE id = v_id;
  END IF;

  -- A BLE observation is physically short-range even if the UI is in Miles
  -- mode. Never let a caller turn it into a 200-mile token correlation.
  v_radius := LEAST(100.0, GREATEST(5.0, public.range_radius_meters(v_range)));
  IF v_range::TEXT LIKE 'feet_%' THEN
    v_radius := GREATEST(v_radius, 50.0); -- tolerate low-accuracy phone GPS
  END IF;
  v_window := LEAST(30, public.range_time_window_minutes(v_range));

  PERFORM public.correlate_encounter(
    lower(p_observed_token), p_lat, p_lon, v_radius, v_window
  );
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.correlate_encounter(
  p_observed_token TEXT,
  p_lat DOUBLE PRECISION,
  p_lon DOUBLE PRECISION,
  p_radius_meters DOUBLE PRECISION DEFAULT 50,
  p_time_window_minutes INT DEFAULT 60
)
RETURNS TABLE (
  encounter_id BIGINT,
  other_user_id UUID,
  created_new BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_claim public.token_claims%ROWTYPE;
  v_user_a UUID;
  v_user_b UUID;
  v_enc_id BIGINT;
  v_distance DOUBLE PRECISION;
  v_rssi INTEGER;
  v_min_rssi INTEGER;
  v_new BOOLEAN := FALSE;
BEGIN
  IF v_uid IS NULL OR NOT public.current_user_can_discover() THEN
    RETURN;
  END IF;

  SELECT * INTO v_claim
  FROM public.token_claims tc
  WHERE tc.token = lower(p_observed_token)
    AND tc.user_id <> v_uid
    AND tc.valid_from > NOW() - make_interval(mins => LEAST(30, GREATEST(1, p_time_window_minutes)))
    AND tc.valid_until > NOW() - INTERVAL '2 minutes'
  LIMIT 1;

  IF NOT FOUND OR NOT public.is_discoverable_user(v_claim.user_id) THEN
    RETURN;
  END IF;
  IF public.is_blocked_pair(v_uid, v_claim.user_id) THEN
    RETURN;
  END IF;

  SELECT s.rssi INTO v_rssi
  FROM public.sightings s
  WHERE s.observer_user_id = v_uid
    AND s.observed_token = lower(p_observed_token)
  ORDER BY s.observed_at DESC
  LIMIT 1;

  v_min_rssi := CASE COALESCE(v_claim.range_type, 'feet_10')
    WHEN 'feet_10' THEN -75
    WHEN 'feet_20' THEN -85
    ELSE -95
  END;
  IF v_rssi IS NULL OR v_rssi < v_min_rssi THEN
    RETURN;
  END IF;

  IF p_lat IS NOT NULL AND p_lon IS NOT NULL
     AND v_claim.approx_lat IS NOT NULL AND v_claim.approx_lon IS NOT NULL THEN
    v_distance := ST_Distance(
      ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography,
      ST_SetSRID(ST_MakePoint(v_claim.approx_lon, v_claim.approx_lat), 4326)::geography
    );
    IF v_distance > LEAST(100.0, GREATEST(5.0, p_radius_meters)) THEN
      RETURN;
    END IF;
  END IF;

  v_user_a := LEAST(v_uid, v_claim.user_id);
  v_user_b := GREATEST(v_uid, v_claim.user_id);
  PERFORM pg_advisory_xact_lock(hashtextextended(v_user_a::TEXT || v_user_b::TEXT, 0));

  SELECT id INTO v_enc_id
  FROM public.encounters
  WHERE user_a = v_user_a AND user_b = v_user_b AND status = 'active'
  ORDER BY encounter_time DESC
  LIMIT 1
  FOR UPDATE;

  IF v_enc_id IS NULL THEN
    INSERT INTO public.encounters (
      user_a, user_b, neighborhood, encounter_time, last_seen_at,
      range_type, confidence, status
    ) VALUES (
      v_user_a, v_user_b, 'Near you', NOW(), NOW(),
      COALESCE(v_claim.range_type, 'feet_10'),
      CASE WHEN v_distance IS NULL THEN 0.8 ELSE
        LEAST(1.0, GREATEST(0.5, 1.0 - (v_distance / GREATEST(p_radius_meters, 1))))
      END,
      'active'
    ) RETURNING id INTO v_enc_id;
    v_new := TRUE;
  ELSE
    UPDATE public.encounters
    SET last_seen_at = NOW(),
        confidence = CASE WHEN v_distance IS NULL THEN confidence ELSE
          LEAST(1.0, GREATEST(0.5, 1.0 - (v_distance / GREATEST(p_radius_meters, 1))))
        END
    WHERE id = v_enc_id;
  END IF;

  encounter_id := v_enc_id;
  other_user_id := v_claim.user_id;
  created_new := v_new;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_encounters(
  p_limit INT DEFAULT 50,
  p_offset INT DEFAULT 0,
  p_min_age_hours NUMERIC DEFAULT 4
)
RETURNS TABLE (
  encounter_id BIGINT,
  other_user_id UUID,
  display_name TEXT,
  photo_urls TEXT[],
  neighborhood TEXT,
  encounter_time TIMESTAMPTZ,
  range_type public.range_type,
  my_action public.action_type,
  other_action public.action_type,
  status public.encounter_status,
  is_photo_verified BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT
    e.id,
    CASE WHEN e.user_a = auth.uid() THEN e.user_b ELSE e.user_a END,
    'Someone nearby'::TEXT,
    p.photo_urls,
    e.neighborhood,
    e.encounter_time,
    e.range_type,
    (SELECT ea.action FROM public.encounter_actions ea
     WHERE ea.user_id = auth.uid() AND ea.encounter_id = e.id),
    NULL::public.action_type, -- never leak another user's pre-match swipe
    e.status,
    TRUE
  FROM public.encounters e
  JOIN public.profiles p
    ON p.id = CASE WHEN e.user_a = auth.uid() THEN e.user_b ELSE e.user_a END
  WHERE public.current_user_can_discover()
    AND (e.user_a = auth.uid() OR e.user_b = auth.uid())
    AND e.status = 'active'
    AND e.encounter_time <= NOW() - make_interval(
      secs => (public.encounter_reveal_delay_hours() * 3600)::DOUBLE PRECISION
    )
    AND public.is_discoverable_user(p.id)
    AND NOT public.is_blocked_pair(auth.uid(), p.id)
    AND NOT EXISTS (
      SELECT 1 FROM public.encounter_actions mine
      WHERE mine.encounter_id = e.id AND mine.user_id = auth.uid()
    )
  ORDER BY e.encounter_time DESC
  LIMIT LEAST(100, GREATEST(1, COALESCE(p_limit, 50)))
  OFFSET GREATEST(0, COALESCE(p_offset, 0));
$$;

-- -----------------------------------------------------------------------------
-- 5. Miles/Locals: fresh-own-ping origin, coarse output, consistent safety gates
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.record_location_ping(
  p_lat DOUBLE PRECISION,
  p_lon DOUBLE PRECISION,
  p_range public.range_type DEFAULT 'miles_10',
  p_neighborhood TEXT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_id BIGINT;
  v_hood TEXT;
  v_last RECORD;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '28000';
  END IF;
  IF NOT public.current_user_can_discover() THEN
    RAISE EXCEPTION 'Complete age and photo verification before using Locals'
      USING ERRCODE = '42501';
  END IF;
  IF p_lat IS NULL OR p_lon IS NULL
     OR p_lat NOT BETWEEN -90 AND 90 OR p_lon NOT BETWEEN -180 AND 180 THEN
    RAISE EXCEPTION 'Invalid coordinates' USING ERRCODE = '22023';
  END IF;
  IF p_range::TEXT NOT LIKE 'miles_%' THEN
    RAISE EXCEPTION 'Locals requires a miles range' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = v_uid AND NOT p.location_history_enabled
  ) THEN
    RAISE EXCEPTION 'Location history is disabled' USING ERRCODE = '42501';
  END IF;

  v_hood := left(COALESCE(NULLIF(trim(p_neighborhood), ''), 'Nearby'), 80);
  -- Never accept the old client fallback "Area 12.34, -56.78" as a label.
  IF v_hood ~* '^-?area[[:space:]]+-?[0-9]+\.[0-9]+.*[,-][[:space:]]*-?[0-9]+\.[0-9]+' THEN
    v_hood := 'Nearby';
  END IF;

  SELECT lp.id, lp.created_at INTO v_last
  FROM public.location_pings lp
  WHERE lp.user_id = v_uid
  ORDER BY lp.created_at DESC
  LIMIT 1;

  -- Stream + timer callbacks can overlap. Treat a sub-30-second duplicate as
  -- the same ping instead of growing the table or racing correlation.
  IF v_last.id IS NOT NULL AND v_last.created_at > NOW() - INTERVAL '30 seconds' THEN
    RETURN v_last.id;
  END IF;

  INSERT INTO public.location_pings (user_id, geo, range_type, neighborhood)
  VALUES (
    v_uid,
    ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography,
    p_range,
    v_hood
  ) RETURNING id INTO v_id;

  UPDATE public.profiles
  SET last_active_at = NOW(), neighborhood = v_hood
  WHERE id = v_uid;

  PERFORM public.correlate_miles_encounters(p_lat, p_lon, p_range, v_hood);
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.correlate_miles_encounters(
  p_lat DOUBLE PRECISION,
  p_lon DOUBLE PRECISION,
  p_range public.range_type DEFAULT 'miles_10',
  p_neighborhood TEXT DEFAULT NULL
)
RETURNS TABLE (
  encounter_id BIGINT,
  other_user_id UUID,
  created_new BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_own RECORD;
  v_peer RECORD;
  v_user_a UUID;
  v_user_b UUID;
  v_enc_id BIGINT;
  v_radius DOUBLE PRECISION;
  v_distance DOUBLE PRECISION;
  v_new BOOLEAN;
BEGIN
  IF v_uid IS NULL OR NOT public.current_user_can_discover() THEN
    RETURN;
  END IF;

  SELECT lp.id, lp.geo, lp.range_type, lp.neighborhood, lp.created_at
  INTO v_own
  FROM public.location_pings lp
  WHERE lp.user_id = v_uid
    AND lp.created_at > NOW() - INTERVAL '5 minutes'
  ORDER BY lp.created_at DESC
  LIMIT 1;
  IF NOT FOUND OR v_own.range_type::TEXT NOT LIKE 'miles_%' THEN
    RETURN;
  END IF;

  v_radius := public.range_radius_meters(v_own.range_type);
  FOR v_peer IN
    SELECT DISTINCT ON (lp.user_id)
      lp.user_id,
      lp.geo,
      lp.range_type,
      lp.neighborhood,
      lp.created_at,
      ST_Distance(lp.geo, v_own.geo) AS distance_m
    FROM public.location_pings lp
    WHERE lp.user_id <> v_uid
      AND lp.created_at > NOW() - make_interval(
        mins => LEAST(1440, public.range_time_window_minutes(v_own.range_type))
      )
      AND ST_DWithin(
        lp.geo,
        v_own.geo,
        LEAST(v_radius, public.range_radius_meters(lp.range_type))
      )
      AND public.is_discoverable_user(lp.user_id)
      AND NOT public.is_blocked_pair(v_uid, lp.user_id)
      AND public.preferences_compatible(v_uid, lp.user_id)
    ORDER BY lp.user_id, lp.created_at DESC
    LIMIT 100
  LOOP
    v_distance := v_peer.distance_m;
    v_user_a := LEAST(v_uid, v_peer.user_id);
    v_user_b := GREATEST(v_uid, v_peer.user_id);
    PERFORM pg_advisory_xact_lock(hashtextextended(v_user_a::TEXT || v_user_b::TEXT, 0));

    SELECT id INTO v_enc_id
    FROM public.encounters
    WHERE user_a = v_user_a AND user_b = v_user_b AND status = 'active'
    ORDER BY encounter_time DESC
    LIMIT 1
    FOR UPDATE;

    IF v_enc_id IS NULL THEN
      INSERT INTO public.encounters (
        user_a, user_b, neighborhood, encounter_time, last_seen_at,
        range_type, confidence, status
      ) VALUES (
        v_user_a, v_user_b,
        COALESCE(v_own.neighborhood, v_peer.neighborhood, 'Nearby'),
        NOW(), NOW(), v_own.range_type,
        LEAST(1.0, GREATEST(0.4, 1.0 - (v_distance / GREATEST(v_radius, 1)))),
        'active'
      ) RETURNING id INTO v_enc_id;
      v_new := TRUE;
    ELSE
      UPDATE public.encounters
      SET last_seen_at = NOW(),
          neighborhood = COALESCE(v_own.neighborhood, v_peer.neighborhood, neighborhood),
          confidence = LEAST(1.0, GREATEST(0.4, 1.0 - (v_distance / GREATEST(v_radius, 1))))
      WHERE id = v_enc_id;
      v_new := FALSE;
    END IF;

    encounter_id := v_enc_id;
    other_user_id := v_peer.user_id;
    created_new := v_new;
    RETURN NEXT;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_locals_feed(
  p_lat DOUBLE PRECISION,
  p_lon DOUBLE PRECISION,
  p_range public.range_type DEFAULT 'miles_10',
  p_limit INT DEFAULT 50
)
RETURNS TABLE (
  user_id UUID,
  distance_m DOUBLE PRECISION,
  neighborhood TEXT,
  photo_urls TEXT[],
  is_photo_verified BOOLEAN,
  is_boosted BOOLEAN,
  last_ping_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_own RECORD;
  v_radius DOUBLE PRECISION;
  v_window INT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '28000';
  END IF;
  IF NOT public.current_user_can_discover() THEN
    RAISE EXCEPTION 'Account is not discoverable' USING ERRCODE = '42501';
  END IF;

  -- p_lat/p_lon remain in the stable API signature, but are deliberately not
  -- trusted. The origin is the caller's latest server-recorded ping.
  SELECT lp.geo, lp.range_type, lp.created_at INTO v_own
  FROM public.location_pings lp
  WHERE lp.user_id = v_uid
    AND lp.created_at > NOW() - INTERVAL '5 minutes'
  ORDER BY lp.created_at DESC
  LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Record a fresh location ping first' USING ERRCODE = '55000';
  END IF;

  v_radius := public.range_radius_meters(v_own.range_type);
  v_window := LEAST(1440, public.range_time_window_minutes(v_own.range_type));

  RETURN QUERY
  SELECT DISTINCT ON (lp.user_id)
    lp.user_id,
    -- 250m bands and 15-minute timestamps reduce trilateration/online-status
    -- precision while preserving a useful Locals UI.
    (CEIL(ST_Distance(lp.geo, v_own.geo) / 250.0) * 250.0)::DOUBLE PRECISION,
    lp.neighborhood,
    pr.photo_urls,
    TRUE,
    public.has_active_boost(lp.user_id),
    date_bin(INTERVAL '15 minutes', lp.created_at, TIMESTAMPTZ '2001-01-01 00:00:00+00')
  FROM public.location_pings lp
  JOIN public.profiles pr ON pr.id = lp.user_id
  WHERE lp.user_id <> v_uid
    AND lp.created_at > NOW() - make_interval(mins => v_window)
    AND ST_DWithin(
      lp.geo,
      v_own.geo,
      LEAST(v_radius, public.range_radius_meters(lp.range_type))
    )
    AND public.is_discoverable_user(lp.user_id)
    AND NOT public.is_blocked_pair(v_uid, lp.user_id)
    AND public.preferences_compatible(v_uid, lp.user_id)
    AND EXISTS (
      SELECT 1 FROM public.encounters revealed
      WHERE revealed.status = 'active'
        AND revealed.encounter_time <= NOW() - make_interval(
          secs => (public.encounter_reveal_delay_hours() * 3600)::DOUBLE PRECISION
        )
        AND ((revealed.user_a = v_uid AND revealed.user_b = lp.user_id)
          OR (revealed.user_b = v_uid AND revealed.user_a = lp.user_id))
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.encounters e
      JOIN public.encounter_actions ea ON ea.encounter_id = e.id
      WHERE ea.user_id = v_uid
        AND ((e.user_a = v_uid AND e.user_b = lp.user_id)
          OR (e.user_b = v_uid AND e.user_a = lp.user_id))
    )
  ORDER BY lp.user_id, public.has_active_boost(lp.user_id) DESC, lp.created_at DESC
  LIMIT LEAST(100, GREATEST(1, COALESCE(p_limit, 50)));
END;
$$;

CREATE OR REPLACE FUNCTION public.batch_correlate_recent_pings(
  p_lookback_minutes INT DEFAULT 30
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_lookback INT := LEAST(120, GREATEST(1, COALESCE(p_lookback_minutes, 30)));
  v_source RECORD;
  v_peer RECORD;
  v_enc_id BIGINT;
  v_count INT := 0;
  v_radius DOUBLE PRECISION;
BEGIN
  FOR v_source IN
    SELECT DISTINCT ON (lp.user_id)
      lp.user_id, lp.geo, lp.range_type, lp.neighborhood, lp.created_at
    FROM public.location_pings lp
    WHERE lp.created_at > NOW() - make_interval(mins => v_lookback)
      AND lp.range_type::TEXT LIKE 'miles_%'
      AND public.is_discoverable_user(lp.user_id)
    ORDER BY lp.user_id, lp.created_at DESC
  LOOP
    v_radius := public.range_radius_meters(v_source.range_type);
    FOR v_peer IN
      SELECT DISTINCT ON (lp.user_id)
        lp.user_id, lp.geo, lp.range_type, lp.neighborhood,
        ST_Distance(lp.geo, v_source.geo) AS distance_m
      FROM public.location_pings lp
      WHERE lp.user_id > v_source.user_id -- each pair exactly once
        AND lp.created_at > NOW() - make_interval(mins => v_lookback)
        AND public.is_discoverable_user(lp.user_id)
        AND ST_DWithin(
          lp.geo, v_source.geo,
          LEAST(v_radius, public.range_radius_meters(lp.range_type))
        )
        AND NOT public.is_blocked_pair(v_source.user_id, lp.user_id)
        AND public.preferences_compatible(v_source.user_id, lp.user_id)
      ORDER BY lp.user_id, lp.created_at DESC
    LOOP
      PERFORM pg_advisory_xact_lock(
        hashtextextended(v_source.user_id::TEXT || v_peer.user_id::TEXT, 0)
      );
      SELECT id INTO v_enc_id
      FROM public.encounters
      WHERE user_a = v_source.user_id AND user_b = v_peer.user_id
        AND status = 'active'
      ORDER BY encounter_time DESC
      LIMIT 1
      FOR UPDATE;

      IF v_enc_id IS NULL THEN
        INSERT INTO public.encounters (
          user_a, user_b, neighborhood, encounter_time, last_seen_at,
          range_type, confidence, status
        ) VALUES (
          v_source.user_id, v_peer.user_id,
          COALESCE(v_source.neighborhood, v_peer.neighborhood, 'Nearby'),
          NOW(), NOW(), v_source.range_type,
          LEAST(1.0, GREATEST(0.4, 1.0 - (v_peer.distance_m / GREATEST(v_radius, 1)))),
          'active'
        ) RETURNING id INTO v_enc_id;
        v_count := v_count + 1;
      ELSE
        UPDATE public.encounters
        SET last_seen_at = NOW(),
            confidence = LEAST(1.0, GREATEST(0.4, 1.0 - (v_peer.distance_m / GREATEST(v_radius, 1))))
        WHERE id = v_enc_id;
      END IF;
    END LOOP;
  END LOOP;
  RETURN v_count;
END;
$$;

-- -----------------------------------------------------------------------------
-- 6. Swipe, match, chat, and block state machines
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.swipe_encounter(
  p_encounter_id BIGINT,
  p_action public.action_type
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_enc public.encounters%ROWTYPE;
  v_other UUID;
  v_other_action public.action_type;
  v_match_id BIGINT;
  v_created_match BOOLEAN := FALSE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '28000';
  END IF;
  IF NOT public.current_user_can_discover() THEN
    RAISE EXCEPTION 'Account is not discoverable' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_enc
  FROM public.encounters
  WHERE id = p_encounter_id
  FOR UPDATE;
  IF NOT FOUND OR (v_enc.user_a <> v_uid AND v_enc.user_b <> v_uid) THEN
    RAISE EXCEPTION 'Encounter not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_enc.status <> 'active' THEN
    RAISE EXCEPTION 'Encounter is not swipeable' USING ERRCODE = '55000';
  END IF;
  IF v_enc.encounter_time > NOW() - make_interval(
    secs => (public.encounter_reveal_delay_hours() * 3600)::DOUBLE PRECISION
  ) THEN
    RAISE EXCEPTION 'Encounter is not revealed yet' USING ERRCODE = '42501';
  END IF;
  IF v_enc.range_type::TEXT LIKE 'feet_%'
     AND v_enc.last_seen_at < NOW() - INTERVAL '24 hours' THEN
    UPDATE public.encounters SET status = 'expired' WHERE id = v_enc.id;
    RAISE EXCEPTION 'Encounter expired' USING ERRCODE = '55000';
  END IF;

  v_other := CASE WHEN v_enc.user_a = v_uid THEN v_enc.user_b ELSE v_enc.user_a END;
  IF NOT public.is_discoverable_user(v_other)
     OR public.is_blocked_pair(v_uid, v_other) THEN
    RAISE EXCEPTION 'Encounter unavailable' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.encounter_actions (user_id, encounter_id, action)
  VALUES (v_uid, p_encounter_id, p_action)
  ON CONFLICT (user_id, encounter_id) DO UPDATE
    SET action = EXCLUDED.action, acted_at = NOW();

  IF p_action = 'pass' THEN
    RETURN jsonb_build_object('matched', FALSE, 'match_id', NULL, 'action', 'pass');
  END IF;

  SELECT action INTO v_other_action
  FROM public.encounter_actions
  WHERE encounter_id = p_encounter_id AND user_id = v_other;

  IF v_other_action = 'like' THEN
    INSERT INTO public.matches (
      encounter_id, user_a, user_b, matched_at, status, expires_at
    ) VALUES (
      p_encounter_id, LEAST(v_uid, v_other), GREATEST(v_uid, v_other),
      NOW(), 'active', NOW() + INTERVAL '24 hours'
    )
    ON CONFLICT (encounter_id) DO NOTHING
    RETURNING id INTO v_match_id;

    IF v_match_id IS NOT NULL THEN
      v_created_match := TRUE;
    ELSE
      SELECT id INTO v_match_id
      FROM public.matches
      WHERE encounter_id = p_encounter_id AND status = 'active';
    END IF;

    IF v_match_id IS NULL THEN
      RAISE EXCEPTION 'Match is unavailable' USING ERRCODE = '55000';
    END IF;

    UPDATE public.encounters SET status = 'matched' WHERE id = p_encounter_id;

    IF v_created_match THEN
      INSERT INTO public.notification_outbox (user_id, kind, title, body, payload)
      VALUES
        (
          v_uid, 'new_match', 'It''s a match',
          'You both liked each other. Say hi!',
          jsonb_build_object('match_id', v_match_id, 'other_user_id', v_other)
        ),
        (
          v_other, 'new_match', 'It''s a match',
          'You both liked each other. Say hi!',
          jsonb_build_object('match_id', v_match_id, 'other_user_id', v_uid)
        );
    END IF;

    RETURN jsonb_build_object(
      'matched', TRUE, 'match_id', v_match_id,
      'action', 'like', 'other_user_id', v_other
    );
  END IF;

  RETURN jsonb_build_object('matched', FALSE, 'match_id', NULL, 'action', 'like');
END;
$$;

CREATE OR REPLACE FUNCTION public.swipe_user(
  p_other_user_id UUID,
  p_action public.action_type,
  p_range public.range_type DEFAULT 'miles_10',
  p_neighborhood TEXT DEFAULT 'Nearby'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_enc_id BIGINT;
  v_result JSONB;
BEGIN
  IF v_uid IS NULL OR p_other_user_id IS NULL OR p_other_user_id = v_uid THEN
    RAISE EXCEPTION 'Invalid user' USING ERRCODE = '22023';
  END IF;
  IF NOT public.current_user_can_discover()
     OR NOT public.is_discoverable_user(p_other_user_id)
     OR public.is_blocked_pair(v_uid, p_other_user_id) THEN
    RAISE EXCEPTION 'User unavailable' USING ERRCODE = '42501';
  END IF;

  -- Never manufacture proximity from a user UUID. record_location_ping /
  -- record_sighting must already have created a real, revealed encounter.
  SELECT e.id INTO v_enc_id
  FROM public.encounters e
  WHERE e.user_a = LEAST(v_uid, p_other_user_id)
    AND e.user_b = GREATEST(v_uid, p_other_user_id)
    AND e.status = 'active'
    AND e.encounter_time <= NOW() - make_interval(
      secs => (public.encounter_reveal_delay_hours() * 3600)::DOUBLE PRECISION
    )
  ORDER BY e.encounter_time DESC
  LIMIT 1;

  IF v_enc_id IS NULL THEN
    RAISE EXCEPTION 'No eligible encounter with this user' USING ERRCODE = '42501';
  END IF;

  SELECT public.swipe_encounter(v_enc_id, p_action) INTO v_result;
  RETURN v_result || jsonb_build_object('encounter_id', v_enc_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_matches(
  p_limit INT DEFAULT 50,
  p_offset INT DEFAULT 0
)
RETURNS TABLE (
  match_id BIGINT,
  other_user_id UUID,
  display_name TEXT,
  photo_urls TEXT[],
  bio TEXT,
  age INT,
  gender TEXT,
  interests TEXT[],
  neighborhood TEXT,
  matched_at TIMESTAMPTZ,
  last_message TEXT,
  last_message_at TIMESTAMPTZ,
  unread_count BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT
    m.id,
    CASE WHEN m.user_a = auth.uid() THEN m.user_b ELSE m.user_a END,
    COALESCE(p.display_name, 'Match'),
    p.photo_urls,
    p.bio,
    EXTRACT(YEAR FROM age(p.dob))::INT,
    p.gender,
    p.interests,
    p.neighborhood,
    m.matched_at,
    (SELECT msg.content FROM public.messages msg
     WHERE msg.match_id = m.id ORDER BY msg.created_at DESC LIMIT 1),
    (SELECT msg.created_at FROM public.messages msg
     WHERE msg.match_id = m.id ORDER BY msg.created_at DESC LIMIT 1),
    (SELECT count(*) FROM public.messages msg
     WHERE msg.match_id = m.id AND msg.sender_id <> auth.uid() AND msg.read_at IS NULL)
  FROM public.matches m
  JOIN public.profiles p
    ON p.id = CASE WHEN m.user_a = auth.uid() THEN m.user_b ELSE m.user_a END
  WHERE auth.uid() IS NOT NULL
    AND m.status = 'active'
    AND (m.user_a = auth.uid() OR m.user_b = auth.uid())
    AND p.deleted_at IS NULL AND p.is_active
    AND NOT public.is_blocked_pair(auth.uid(), p.id)
  ORDER BY COALESCE(
    (SELECT msg.created_at FROM public.messages msg
     WHERE msg.match_id = m.id ORDER BY msg.created_at DESC LIMIT 1),
    m.matched_at
  ) DESC
  LIMIT LEAST(100, GREATEST(1, COALESCE(p_limit, 50)))
  OFFSET GREATEST(0, COALESCE(p_offset, 0));
$$;

CREATE OR REPLACE FUNCTION public.get_who_liked_you(p_limit INT DEFAULT 50)
RETURNS TABLE (
  encounter_id BIGINT,
  other_user_id UUID,
  neighborhood TEXT,
  encounter_time TIMESTAMPTZ,
  range_type public.range_type
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_subscriber(auth.uid()) THEN
    RAISE EXCEPTION 'Subscription required' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
  SELECT e.id,
    CASE WHEN e.user_a = auth.uid() THEN e.user_b ELSE e.user_a END,
    e.neighborhood, e.encounter_time, e.range_type
  FROM public.encounters e
  JOIN public.encounter_actions theirs
    ON theirs.encounter_id = e.id
   AND theirs.user_id <> auth.uid() AND theirs.action = 'like'
  WHERE (e.user_a = auth.uid() OR e.user_b = auth.uid())
    AND e.status = 'active'
    AND e.encounter_time <= NOW() - make_interval(
      secs => (public.encounter_reveal_delay_hours() * 3600)::DOUBLE PRECISION
    )
    AND public.is_discoverable_user(
      CASE WHEN e.user_a = auth.uid() THEN e.user_b ELSE e.user_a END
    )
    AND NOT public.is_blocked_pair(
      auth.uid(), CASE WHEN e.user_a = auth.uid() THEN e.user_b ELSE e.user_a END
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.encounter_actions mine
      WHERE mine.encounter_id = e.id AND mine.user_id = auth.uid()
    )
  ORDER BY theirs.acted_at DESC
  LIMIT LEAST(100, GREATEST(1, COALESCE(p_limit, 50)));
END;
$$;

CREATE OR REPLACE FUNCTION public.send_message(
  p_match_id BIGINT,
  p_content TEXT,
  p_message_type public.message_type DEFAULT 'text',
  p_metadata JSONB DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_match public.matches%ROWTYPE;
  v_other UUID;
  v_id BIGINT;
  v_path TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '28000';
  END IF;

  SELECT * INTO v_match FROM public.matches WHERE id = p_match_id FOR UPDATE;
  IF NOT FOUND OR (v_match.user_a <> v_uid AND v_match.user_b <> v_uid) THEN
    RAISE EXCEPTION 'Match not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_match.status <> 'active' THEN
    RAISE EXCEPTION 'Match is not active' USING ERRCODE = '55000';
  END IF;
  IF v_match.expires_at IS NOT NULL AND v_match.expires_at <= NOW()
     AND NOT EXISTS (SELECT 1 FROM public.messages WHERE match_id = p_match_id) THEN
    UPDATE public.matches SET status = 'expired', ended_at = NOW() WHERE id = p_match_id;
    RAISE EXCEPTION 'Match expired' USING ERRCODE = '55000';
  END IF;

  v_other := CASE WHEN v_match.user_a = v_uid THEN v_match.user_b ELSE v_match.user_a END;
  IF public.is_blocked_pair(v_uid, v_other) THEN
    RAISE EXCEPTION 'Match unavailable' USING ERRCODE = '42501';
  END IF;
  IF p_content IS NOT NULL AND char_length(p_content) > 4000 THEN
    RAISE EXCEPTION 'Message max 4000 characters' USING ERRCODE = '22023';
  END IF;
  IF p_metadata IS NOT NULL AND octet_length(p_metadata::TEXT) > 16384 THEN
    RAISE EXCEPTION 'Message metadata too large' USING ERRCODE = '22023';
  END IF;
  IF p_message_type = 'text'
     AND (p_content IS NULL OR length(trim(p_content)) = 0) THEN
    RAISE EXCEPTION 'Message content required' USING ERRCODE = '22023';
  END IF;

  IF p_message_type <> 'text' THEN
    v_path := NULLIF(p_metadata->>'storage_path', '');
    IF v_path IS NULL
       OR split_part(v_path, '/', 1) <> p_match_id::TEXT
       OR split_part(v_path, '/', 2) <> v_uid::TEXT
       OR NOT EXISTS (
         SELECT 1 FROM storage.objects o
         WHERE o.bucket_id = 'chat_media' AND o.name = v_path
       ) THEN
      RAISE EXCEPTION 'Valid chat media upload required' USING ERRCODE = '22023';
    END IF;
  END IF;

  INSERT INTO public.messages (match_id, sender_id, content, message_type, metadata)
  VALUES (
    p_match_id, v_uid,
    CASE WHEN p_message_type = 'text' THEN trim(p_content) ELSE NULLIF(trim(p_content), '') END,
    p_message_type, p_metadata
  ) RETURNING id INTO v_id;

  UPDATE public.matches SET expires_at = NULL WHERE id = p_match_id;

  INSERT INTO public.notification_outbox (user_id, kind, title, body, payload)
  VALUES (
    v_other, 'new_message', 'New message',
    'Open In Range to view it.',
    jsonb_build_object('match_id', p_match_id, 'message_id', v_id, 'sender_id', v_uid)
  );

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_messages_read(p_match_id BIGINT)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE v_count INT;
BEGIN
  IF NOT public.can_access_match(p_match_id) THEN
    RAISE EXCEPTION 'Match not found' USING ERRCODE = 'P0002';
  END IF;
  UPDATE public.messages
  SET read_at = NOW()
  WHERE match_id = p_match_id
    AND sender_id <> auth.uid() AND read_at IS NULL;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.block_user(p_blocked_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL OR p_blocked_id IS NULL OR p_blocked_id = v_uid THEN
    RAISE EXCEPTION 'Invalid user' USING ERRCODE = '22023';
  END IF;
  INSERT INTO public.blocks (blocker_id, blocked_id)
  VALUES (v_uid, p_blocked_id)
  ON CONFLICT DO NOTHING;

  UPDATE public.encounters
  SET status = 'expired'
  WHERE status = 'active'
    AND user_a = LEAST(v_uid, p_blocked_id)
    AND user_b = GREATEST(v_uid, p_blocked_id);

  UPDATE public.matches
  SET status = 'blocked', ended_at = NOW()
  WHERE status = 'active'
    AND user_a = LEAST(v_uid, p_blocked_id)
    AND user_b = GREATEST(v_uid, p_blocked_id);

  UPDATE public.notification_outbox
  SET status = 'skipped', last_error = 'blocked_pair'
  WHERE status IN ('pending', 'processing')
    AND (
      (user_id = v_uid AND payload->>'other_user_id' = p_blocked_id::TEXT)
      OR (user_id = p_blocked_id AND payload->>'other_user_id' = v_uid::TEXT)
      OR (user_id = v_uid AND payload->>'sender_id' = p_blocked_id::TEXT)
      OR (user_id = p_blocked_id AND payload->>'sender_id' = v_uid::TEXT)
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.unblock_user(p_blocked_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '28000';
  END IF;
  DELETE FROM public.blocks
  WHERE blocker_id = auth.uid() AND blocked_id = p_blocked_id;
  -- Blocking ends a match; unblocking never silently restores it.
END;
$$;

CREATE OR REPLACE FUNCTION public.report_user(
  p_reported_id UUID,
  p_reason public.report_reason,
  p_details TEXT DEFAULT NULL,
  p_match_id BIGINT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_id BIGINT;
BEGIN
  IF v_uid IS NULL OR p_reported_id IS NULL OR p_reported_id = v_uid THEN
    RAISE EXCEPTION 'Invalid reported user' USING ERRCODE = '22023';
  END IF;
  IF p_details IS NOT NULL AND char_length(p_details) > 2000 THEN
    RAISE EXCEPTION 'Report details max 2000 characters' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.encounters e
    WHERE (e.user_a = LEAST(v_uid, p_reported_id)
       AND e.user_b = GREATEST(v_uid, p_reported_id))
    UNION ALL
    SELECT 1 FROM public.matches m
    WHERE (m.user_a = LEAST(v_uid, p_reported_id)
       AND m.user_b = GREATEST(v_uid, p_reported_id))
  ) THEN
    RAISE EXCEPTION 'No relationship with reported user' USING ERRCODE = '42501';
  END IF;
  IF p_match_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.matches m
    WHERE m.id = p_match_id
      AND m.user_a = LEAST(v_uid, p_reported_id)
      AND m.user_b = GREATEST(v_uid, p_reported_id)
  ) THEN
    RAISE EXCEPTION 'Invalid report match' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.reports (reporter_id, reported_id, reason, details, match_id)
  VALUES (v_uid, p_reported_id, p_reason, NULLIF(trim(p_details), ''), p_match_id)
  RETURNING id INTO v_id;
  PERFORM public.block_user(p_reported_id);
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_match_profile(p_other_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_row public.profiles%ROWTYPE;
BEGIN
  IF v_uid IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.matches m
    WHERE m.status = 'active'
      AND ((m.user_a = v_uid AND m.user_b = p_other_user_id)
        OR (m.user_b = v_uid AND m.user_a = p_other_user_id))
  ) OR public.is_blocked_pair(v_uid, p_other_user_id) THEN
    RAISE EXCEPTION 'Match not found' USING ERRCODE = 'P0002';
  END IF;
  SELECT * INTO v_row FROM public.profiles WHERE id = p_other_user_id;
  IF NOT FOUND OR NOT v_row.is_active OR v_row.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Profile not found' USING ERRCODE = 'P0002';
  END IF;
  RETURN jsonb_build_object(
    'id', v_row.id, 'display_name', v_row.display_name, 'bio', v_row.bio,
    'age', EXTRACT(YEAR FROM age(v_row.dob))::INT, 'gender', v_row.gender,
    'interests', v_row.interests, 'photo_urls', v_row.photo_urls,
    'is_photo_verified', v_row.is_photo_verified, 'neighborhood', v_row.neighborhood
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- 7. Photo verification: bind decisions to an immutable Storage object version
-- -----------------------------------------------------------------------------

UPDATE public.photo_verifications pv
SET storage_object_id = o.id,
    storage_object_updated_at = o.updated_at
FROM storage.objects o
WHERE pv.storage_object_id IS NULL
  AND o.bucket_id = 'profile_photos'
  AND o.name = pv.photo_path;

CREATE OR REPLACE FUNCTION public.submit_photo_for_verification(
  p_photo_path TEXT,
  p_slot_index SMALLINT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_id UUID;
  v_object RECORD;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '28000';
  END IF;
  IF p_slot_index IS NULL OR p_slot_index NOT BETWEEN 0 AND 5 THEN
    RAISE EXCEPTION 'slot_index must be 0..5' USING ERRCODE = '22023';
  END IF;
  IF p_photo_path IS NULL
     OR split_part(p_photo_path, '/', 1) <> v_uid::TEXT
     OR p_photo_path LIKE 'http%'
     OR length(p_photo_path) > 500 THEN
    RAISE EXCEPTION 'Invalid photo path' USING ERRCODE = '22023';
  END IF;
  IF (
    SELECT count(*) FROM public.photo_verifications pv
    WHERE pv.user_id = v_uid AND pv.created_at > NOW() - INTERVAL '1 hour'
  ) >= 12 THEN
    RAISE EXCEPTION 'Photo review rate limit' USING ERRCODE = '54000';
  END IF;

  SELECT o.id, o.updated_at INTO v_object
  FROM storage.objects o
  WHERE o.bucket_id = 'profile_photos' AND o.name = p_photo_path;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Uploaded photo not found' USING ERRCODE = 'P0002';
  END IF;

  -- A new submission supersedes unfinished reviews for the same slot, without
  -- mutating any previously approved immutable photo.
  UPDATE public.photo_verifications
  SET state = 'rejected',
      review_notes = 'Superseded by a newer upload',
      decided_at = NOW(), updated_at = NOW()
  WHERE user_id = v_uid AND slot_index = p_slot_index
    AND state IN ('pending_upload', 'ai_review', 'ai_passed', 'ai_failed', 'manual_review');

  INSERT INTO public.photo_verifications (
    user_id, photo_path, slot_index, state,
    storage_object_id, storage_object_updated_at
  ) VALUES (
    v_uid, p_photo_path, p_slot_index, 'ai_review',
    v_object.id, v_object.updated_at
  ) RETURNING id INTO v_id;

  UPDATE public.profiles p
  SET photo_urls = (
        SELECT array_agg(x.path ORDER BY x.ord)
        FROM (
          SELECT ord,
            CASE WHEN ord - 1 = p_slot_index
              THEN p_photo_path
              ELSE p.photo_urls[ord]
            END AS path
          FROM generate_series(
            1,
            GREATEST(COALESCE(array_length(p.photo_urls, 1), 0), p_slot_index + 1)
          ) ord
        ) x
        WHERE x.path IS NOT NULL AND x.path <> ''
      ),
      is_photo_verified = EXISTS (
        SELECT 1 FROM public.photo_verifications approved
        WHERE approved.user_id = v_uid AND approved.state = 'approved'
          AND approved.photo_path <> p_photo_path
          AND approved.photo_path = ANY(COALESCE(p.photo_urls, ARRAY[]::TEXT[]))
      ),
      photo_verification_status = 'pending',
      updated_at = NOW()
  WHERE p.id = v_uid;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_ai_photo_review(
  p_verification_id UUID,
  p_score NUMERIC,
  p_passed BOOLEAN,
  p_notes TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE v_review public.photo_verifications%ROWTYPE;
BEGIN
  IF p_score IS NULL OR p_score < 0 OR p_score > 1 THEN
    RAISE EXCEPTION 'AI score must be 0..1' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO v_review
  FROM public.photo_verifications
  WHERE id = p_verification_id AND state = 'ai_review'
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Verification not in AI review' USING ERRCODE = '55000';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM storage.objects o
    WHERE o.bucket_id = 'profile_photos'
      AND o.name = v_review.photo_path
      AND o.id = v_review.storage_object_id
      AND o.updated_at IS NOT DISTINCT FROM v_review.storage_object_updated_at
  ) THEN
    RAISE EXCEPTION 'Photo changed after submission' USING ERRCODE = '55000';
  END IF;

  UPDATE public.photo_verifications
  SET ai_score = p_score,
      ai_notes = left(p_notes, 1000),
      state = CASE WHEN p_passed
        THEN 'manual_review'::public.photo_verification_state
        ELSE 'ai_failed'::public.photo_verification_state
      END,
      updated_at = NOW()
  WHERE id = p_verification_id;

  IF NOT p_passed THEN
    INSERT INTO public.notification_outbox (user_id, kind, title, body, payload)
    VALUES (
      v_review.user_id, 'photo_rejected', 'Photo needs a retake',
      'The automated check could not validate this photo. Please upload a clear selfie.',
      jsonb_build_object('verification_id', p_verification_id)
    );
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.decide_photo_verification(
  p_verification_id UUID,
  p_approve BOOLEAN,
  p_notes TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_review public.photo_verifications%ROWTYPE;
  v_verified BOOLEAN;
BEGIN
  SELECT * INTO v_review
  FROM public.photo_verifications
  WHERE id = p_verification_id
    AND state IN ('manual_review', 'ai_passed')
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Verification not reviewable' USING ERRCODE = '55000';
  END IF;

  IF p_approve AND NOT EXISTS (
    SELECT 1 FROM storage.objects o
    WHERE o.bucket_id = 'profile_photos'
      AND o.name = v_review.photo_path
      AND o.id = v_review.storage_object_id
      AND o.updated_at IS NOT DISTINCT FROM v_review.storage_object_updated_at
  ) THEN
    RAISE EXCEPTION 'Photo changed after submission' USING ERRCODE = '55000';
  END IF;

  UPDATE public.photo_verifications
  SET state = CASE WHEN p_approve
        THEN 'approved'::public.photo_verification_state
        ELSE 'rejected'::public.photo_verification_state
      END,
      review_notes = left(p_notes, 1000),
      decided_at = NOW(), updated_at = NOW()
  WHERE id = p_verification_id;

  SELECT EXISTS (
    SELECT 1 FROM public.photo_verifications pv
    JOIN public.profiles p ON p.id = pv.user_id
    WHERE pv.user_id = v_review.user_id AND pv.state = 'approved'
      AND pv.photo_path = ANY(COALESCE(p.photo_urls, ARRAY[]::TEXT[]))
  ) INTO v_verified;

  UPDATE public.profiles
  SET is_photo_verified = v_verified,
      photo_verification_status = CASE
        WHEN v_verified THEN 'verified'
        WHEN p_approve THEN 'pending'
        ELSE 'rejected'
      END,
      updated_at = NOW()
  WHERE id = v_review.user_id;

  INSERT INTO public.notification_outbox (user_id, kind, title, body, payload)
  VALUES (
    v_review.user_id,
    CASE WHEN p_approve
      THEN 'photo_verified'::public.notification_kind
      ELSE 'photo_rejected'::public.notification_kind
    END,
    CASE WHEN p_approve THEN 'You''re verified' ELSE 'Photo not approved' END,
    CASE WHEN p_approve THEN 'Your photo passed review.'
      ELSE COALESCE(NULLIF(left(p_notes, 500), ''), 'Please upload a different clear photo.')
    END,
    jsonb_build_object('verification_id', p_verification_id)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.stub_auto_approve_photo(p_verification_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE v_state public.photo_verification_state;
BEGIN
  SELECT state INTO v_state FROM public.photo_verifications
  WHERE id = p_verification_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Verification not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_state = 'ai_review' THEN
    PERFORM public.complete_ai_photo_review(
      p_verification_id, 0.95, TRUE, 'explicit lab-only stub pass'
    );
  END IF;
  PERFORM public.decide_photo_verification(
    p_verification_id, TRUE, 'explicit lab-only stub auto-approve'
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- 8. Delayed notifications, expiry, cleanup, and atomic push queue claiming
-- -----------------------------------------------------------------------------

DROP TRIGGER IF EXISTS encounters_notify_insert ON public.encounters;

CREATE OR REPLACE FUNCTION public.queue_revealed_encounter_alerts()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE v_count INT;
BEGIN
  INSERT INTO public.notification_outbox (user_id, kind, title, body, payload)
  SELECT
    participant.user_id,
    'new_encounter',
    'New encounter',
    'A past run-in is ready to view.',
    jsonb_build_object(
      'encounter_id', e.id,
      'other_user_id', participant.other_user_id,
      'range_type', e.range_type
    )
  FROM public.encounters e
  CROSS JOIN LATERAL (
    VALUES (e.user_a, e.user_b), (e.user_b, e.user_a)
  ) AS participant(user_id, other_user_id)
  WHERE e.status = 'active'
    AND e.encounter_time <= NOW() - make_interval(
      secs => (public.encounter_reveal_delay_hours() * 3600)::DOUBLE PRECISION
    )
    AND public.is_discoverable_user(participant.user_id)
    AND public.is_discoverable_user(participant.other_user_id)
    AND NOT public.is_blocked_pair(participant.user_id, participant.other_user_id)
    AND NOT EXISTS (
      SELECT 1 FROM public.notification_outbox o
      WHERE o.user_id = participant.user_id
        AND o.kind = 'new_encounter'
        AND o.payload->>'encounter_id' = e.id::TEXT
    );
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.queue_expiring_encounter_alerts()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE v_count INT;
BEGIN
  INSERT INTO public.notification_outbox (user_id, kind, title, body, payload)
  SELECT
    participant.user_id,
    'expiring_encounter',
    'Encounter expiring soon',
    'A feet run-in expires in under 2 hours. Swipe before it disappears.',
    jsonb_build_object(
      'encounter_id', e.id,
      'other_user_id', participant.other_user_id
    )
  FROM public.encounters e
  CROSS JOIN LATERAL (
    VALUES (e.user_a, e.user_b), (e.user_b, e.user_a)
  ) AS participant(user_id, other_user_id)
  WHERE e.status = 'active'
    AND e.range_type::TEXT LIKE 'feet_%'
    AND e.last_seen_at < NOW() - INTERVAL '22 hours'
    AND e.last_seen_at >= NOW() - INTERVAL '24 hours'
    AND e.encounter_time <= NOW() - make_interval(
      secs => (public.encounter_reveal_delay_hours() * 3600)::DOUBLE PRECISION
    )
    AND public.is_discoverable_user(participant.user_id)
    AND public.is_discoverable_user(participant.other_user_id)
    AND NOT public.is_blocked_pair(participant.user_id, participant.other_user_id)
    AND NOT EXISTS (
      SELECT 1 FROM public.notification_outbox o
      WHERE o.user_id = participant.user_id
        AND o.kind = 'expiring_encounter'
        AND o.payload->>'encounter_id' = e.id::TEXT
    );
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.expire_feet_encounters()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE v_count INT;
BEGIN
  UPDATE public.encounters
  SET status = 'expired'
  WHERE status = 'active'
    AND range_type::TEXT LIKE 'feet_%'
    AND last_seen_at < NOW() - INTERVAL '24 hours';
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.expire_idle_matches()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE v_count INT;
BEGIN
  UPDATE public.matches m
  SET status = 'expired', ended_at = NOW()
  WHERE m.status = 'active'
    AND m.expires_at IS NOT NULL
    AND m.expires_at <= NOW()
    AND NOT EXISTS (SELECT 1 FROM public.messages msg WHERE msg.match_id = m.id);
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.cleanup_ephemeral_data()
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  DELETE FROM public.token_claims
  WHERE valid_until < NOW() - INTERVAL '30 minutes';

  DELETE FROM public.sightings
  WHERE observed_at < NOW() - INTERVAL '48 hours';

  DELETE FROM public.location_pings
  WHERE created_at < NOW() - INTERVAL '24 hours';

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
  DELETE FROM public.ai_runs WHERE created_at < NOW() - INTERVAL '90 days';
$$;

CREATE OR REPLACE FUNCTION public.claim_notification_batch(p_limit INT DEFAULT 50)
RETURNS TABLE (
  id BIGINT,
  user_id UUID,
  kind public.notification_kind,
  title TEXT,
  body TEXT,
  payload JSONB,
  attempts INT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  WITH picked AS (
    SELECT o.id
    FROM public.notification_outbox o
    WHERE o.status = 'pending' AND o.attempts < 5
    ORDER BY o.created_at ASC
    FOR UPDATE SKIP LOCKED
    LIMIT LEAST(200, GREATEST(1, COALESCE(p_limit, 50)))
  )
  UPDATE public.notification_outbox o
  SET status = 'processing', attempts = o.attempts + 1, processing_at = NOW()
  FROM picked
  WHERE o.id = picked.id
  RETURNING o.id, o.user_id, o.kind, o.title, o.body, o.payload, o.attempts;
$$;

CREATE OR REPLACE FUNCTION public.run_maintenance()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_expired_feet INT;
  v_expired_matches INT;
  v_revealed_alerts INT;
  v_expiring_alerts INT;
  v_correlated INT;
BEGIN
  PERFORM public.cleanup_ephemeral_data();
  v_expired_feet := public.expire_feet_encounters();
  v_expired_matches := public.expire_idle_matches();
  v_revealed_alerts := public.queue_revealed_encounter_alerts();
  v_expiring_alerts := public.queue_expiring_encounter_alerts();
  v_correlated := public.batch_correlate_recent_pings(45);
  RETURN jsonb_build_object(
    'expired_feet', v_expired_feet,
    'expired_matches', v_expired_matches,
    'revealed_alerts', v_revealed_alerts,
    'expiring_alerts', v_expiring_alerts,
    'new_miles_encounters', v_correlated,
    'ran_at', NOW()
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- 9. Explicit function allowlists (CREATE FUNCTION grants PUBLIC by default)
-- -----------------------------------------------------------------------------

DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = ANY (ARRAY[
        'claim_token', 'release_token', 'record_sighting',
        'correlate_encounter', 'get_my_encounters',
        'record_location_ping', 'correlate_miles_encounters', 'get_locals_feed',
        'batch_correlate_recent_pings', 'range_radius_meters',
        'range_time_window_minutes', 'preferences_compatible', '_pref_matches',
        'swipe_encounter', 'swipe_user', 'get_my_matches', 'get_who_liked_you',
        'send_message', 'mark_messages_read', 'get_match_profile',
        'block_user', 'unblock_user', 'report_user', 'is_blocked_pair',
        'upsert_my_profile', 'get_my_profile', 'set_account_paused',
        'set_incognito', 'request_account_deletion', 'delete_my_location_history',
        'register_push_token', 'unregister_push_token',
        'submit_photo_for_verification', 'complete_ai_photo_review',
        'decide_photo_verification', 'stub_auto_approve_photo',
        'has_active_boost', 'is_subscriber',
        'cleanup_ephemeral_data', 'expire_feet_encounters',
        'expire_idle_matches', 'queue_revealed_encounter_alerts',
        'queue_expiring_encounter_alerts', 'run_maintenance',
        'claim_notification_batch', 'log_ai_run', 'complete_ai_run',
        'log_ai_event', 'submit_ai_feedback', 'backend_health',
        'encounter_reveal_delay_hours', 'is_discoverable_user',
        'current_user_can_discover', 'can_access_match',
        'can_view_profile_photos', 'can_modify_profile_photo',
        'handle_new_user', 'handle_updated_at', 'notify_on_new_encounter',
        'sync_subscription_flags'
      ])
  LOOP
    EXECUTE format(
      'REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated, service_role',
      r.sig
    );
  END LOOP;
END $$;

DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = ANY (ARRAY[
        'claim_token', 'release_token', 'record_sighting', 'get_my_encounters',
        'record_location_ping', 'get_locals_feed', 'swipe_encounter',
        'swipe_user', 'get_my_matches', 'get_who_liked_you', 'send_message',
        'mark_messages_read', 'get_match_profile', 'block_user', 'unblock_user',
        'report_user', 'upsert_my_profile', 'get_my_profile',
        'set_account_paused', 'set_incognito', 'request_account_deletion',
        'delete_my_location_history', 'register_push_token',
        'unregister_push_token', 'submit_photo_for_verification',
        'submit_ai_feedback', 'backend_health', 'encounter_reveal_delay_hours',
        'can_access_match', 'can_view_profile_photos', 'can_modify_profile_photo'
      ])
  LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', r.sig);
  END LOOP;
END $$;

DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = ANY (ARRAY[
        'complete_ai_photo_review', 'decide_photo_verification',
        'stub_auto_approve_photo', 'cleanup_ephemeral_data',
        'expire_feet_encounters', 'expire_idle_matches',
        'queue_revealed_encounter_alerts', 'queue_expiring_encounter_alerts',
        'batch_correlate_recent_pings', 'run_maintenance',
        'claim_notification_batch', 'is_blocked_pair',
        'log_ai_run', 'complete_ai_run', 'log_ai_event'
      ])
  LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', r.sig);
  END LOOP;
END $$;

-- Lock down future migrations too. Each new client RPC must opt in explicitly.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE ALL ON TABLES FROM PUBLIC, anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE ALL ON SEQUENCES FROM PUBLIC, anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON TABLES TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO service_role;
REVOKE CREATE ON SCHEMA public FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- Fail the migration if a privacy-sensitive application table somehow lacks
-- RLS. This makes future clean resets an executable audit check.
DO $$
DECLARE v_table TEXT;
BEGIN
  SELECT c.relname INTO v_table
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
  IF v_table IS NOT NULL THEN
    RAISE EXCEPTION 'RLS is not enabled on public.%', v_table;
  END IF;
END $$;

COMMENT ON FUNCTION public.encounter_reveal_delay_hours() IS
  'Server-owned minimum encounter reveal delay. Default 4h; set app_settings to 0 only in an isolated lab project.';
COMMENT ON FUNCTION public.swipe_user(UUID, public.action_type, public.range_type, TEXT) IS
  'Swipe a peer only when server correlation already created a revealed encounter; never creates proximity from a UUID.';
COMMENT ON FUNCTION public.get_locals_feed(DOUBLE PRECISION, DOUBLE PRECISION, public.range_type, INT) IS
  'Locals feed anchored to caller latest server ping. Returns 250m distance bands and 15-minute timestamps.';
COMMENT ON SCHEMA public IS
  'In Range — migrations 0001–0019; beta hardening includes explicit RPC grants, server reveal gates, and block-aware storage/chat.';
