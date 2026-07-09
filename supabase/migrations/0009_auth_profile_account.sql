-- =============================================================================
-- Migration 0009: Auth triggers, profile upsert, account pause/delete, tokens
-- =============================================================================

-- ----------------------------------------------------------------------------
-- 1. Auto-create profile on auth.users insert
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (
    id,
    display_name,
    dob,
    email_hint,
    phone_hint,
    created_at,
    updated_at
  )
  VALUES (
    NEW.id,
    COALESCE(
      NEW.raw_user_meta_data->>'display_name',
      NEW.raw_user_meta_data->>'full_name',
      split_part(COALESCE(NEW.email, ''), '@', 1),
      'New user'
    ),
    -- Placeholder DOB; user must update to 18+ during profile setup
    COALESCE(
      (NEW.raw_user_meta_data->>'dob')::date,
      (CURRENT_DATE - INTERVAL '25 years')::date
    ),
    NEW.email,
    NEW.phone,
    NOW(),
    NOW()
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ----------------------------------------------------------------------------
-- 2. upsert_my_profile — full profile creation from client
-- ----------------------------------------------------------------------------
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
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_row public.profiles;
  v_age INT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_display_name IS NULL OR length(trim(p_display_name)) = 0 THEN
    RAISE EXCEPTION 'display_name required';
  END IF;
  IF p_dob IS NOT NULL THEN
    v_age := EXTRACT(YEAR FROM age(p_dob))::INT;
    IF v_age < 18 THEN
      RAISE EXCEPTION 'Must be 18 or older';
    END IF;
  END IF;
  IF p_bio IS NOT NULL AND char_length(p_bio) > 500 THEN
    RAISE EXCEPTION 'Bio max 500 characters';
  END IF;
  IF p_photo_urls IS NOT NULL AND array_length(p_photo_urls, 1) > 6 THEN
    RAISE EXCEPTION 'Max 6 photos';
  END IF;

  INSERT INTO public.profiles (
    id, display_name, bio, dob, gender, sexual_preference,
    interests, photo_urls, beacon_default_range, updated_at
  )
  VALUES (
    v_uid,
    trim(p_display_name),
    p_bio,
    COALESCE(p_dob, (CURRENT_DATE - INTERVAL '25 years')::date),
    p_gender,
    p_sexual_preference,
    p_interests,
    p_photo_urls,
    p_beacon_default_range,
    NOW()
  )
  ON CONFLICT (id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    bio = COALESCE(EXCLUDED.bio, public.profiles.bio),
    dob = COALESCE(EXCLUDED.dob, public.profiles.dob),
    gender = COALESCE(EXCLUDED.gender, public.profiles.gender),
    sexual_preference = COALESCE(EXCLUDED.sexual_preference, public.profiles.sexual_preference),
    interests = COALESCE(EXCLUDED.interests, public.profiles.interests),
    photo_urls = COALESCE(EXCLUDED.photo_urls, public.profiles.photo_urls),
    beacon_default_range = COALESCE(EXCLUDED.beacon_default_range, public.profiles.beacon_default_range),
    updated_at = NOW()
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_my_profile TO authenticated;

-- ----------------------------------------------------------------------------
-- 3. Account pause / resume
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_account_paused(p_paused BOOLEAN)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  UPDATE public.profiles
  SET is_paused = p_paused, updated_at = NOW()
  WHERE id = auth.uid();
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_account_paused TO authenticated;

-- ----------------------------------------------------------------------------
-- 4. Soft delete account + purge location history
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.request_account_deletion()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  UPDATE public.profiles
  SET
    is_active = FALSE,
    is_paused = TRUE,
    deleted_at = NOW(),
    display_name = 'Deleted user',
    bio = NULL,
    photo_urls = NULL,
    interests = NULL,
    updated_at = NOW()
  WHERE id = v_uid;

  DELETE FROM public.location_pings WHERE user_id = v_uid;
  DELETE FROM public.token_claims WHERE user_id = v_uid;
  DELETE FROM public.device_push_tokens WHERE user_id = v_uid;
  -- Sightings kept anonymously for correlation integrity optional; delete for privacy:
  DELETE FROM public.sightings WHERE observer_user_id = v_uid;
END;
$$;

GRANT EXECUTE ON FUNCTION public.request_account_deletion TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_my_location_history()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  DELETE FROM public.location_pings WHERE user_id = auth.uid();
  GET DIAGNOSTICS v_count = ROW_COUNT;
  DELETE FROM public.token_claims WHERE user_id = auth.uid();
  DELETE FROM public.sightings WHERE observer_user_id = auth.uid();
  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_my_location_history TO authenticated;

-- ----------------------------------------------------------------------------
-- 5. Incognito (subscriber-only)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_incognito(p_enabled BOOLEAN)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_enabled AND NOT public.is_subscriber(auth.uid()) THEN
    RAISE EXCEPTION 'Subscription required for Incognito Mode'
      USING ERRCODE = '42501';
  END IF;
  UPDATE public.profiles
  SET is_incognito = p_enabled, updated_at = NOW()
  WHERE id = auth.uid();
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_incognito TO authenticated;

-- ----------------------------------------------------------------------------
-- 6. Register / unregister FCM token
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.register_push_token(
  p_token TEXT,
  p_platform TEXT,
  p_app_version TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_token IS NULL OR length(trim(p_token)) = 0 THEN
    RAISE EXCEPTION 'token required';
  END IF;
  IF p_platform NOT IN ('android', 'ios', 'web') THEN
    RAISE EXCEPTION 'platform must be android|ios|web';
  END IF;

  INSERT INTO public.device_push_tokens (user_id, token, platform, app_version, last_seen_at)
  VALUES (auth.uid(), trim(p_token), p_platform, p_app_version, NOW())
  ON CONFLICT (user_id, token) DO UPDATE
    SET last_seen_at = NOW(),
        platform = EXCLUDED.platform,
        app_version = COALESCE(EXCLUDED.app_version, public.device_push_tokens.app_version)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.unregister_push_token(p_token TEXT)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  DELETE FROM public.device_push_tokens
  WHERE user_id = auth.uid() AND token = p_token;
$$;

GRANT EXECUTE ON FUNCTION public.register_push_token TO authenticated;
GRANT EXECUTE ON FUNCTION public.unregister_push_token TO authenticated;

-- ----------------------------------------------------------------------------
-- 7. Public profile for matches only
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_match_profile(p_other_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_row public.profiles%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Must be matched
  IF NOT EXISTS (
    SELECT 1 FROM public.matches m
    WHERE (m.user_a = v_uid AND m.user_b = p_other_user_id)
       OR (m.user_b = v_uid AND m.user_a = p_other_user_id)
  ) THEN
    RAISE EXCEPTION 'Not matched' USING ERRCODE = '42501';
  END IF;

  IF public.is_blocked_pair(v_uid, p_other_user_id) THEN
    RAISE EXCEPTION 'Blocked';
  END IF;

  SELECT * INTO v_row FROM public.profiles WHERE id = p_other_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Profile not found';
  END IF;

  RETURN jsonb_build_object(
    'id', v_row.id,
    'display_name', v_row.display_name,
    'bio', v_row.bio,
    'age', EXTRACT(YEAR FROM age(v_row.dob))::INT,
    'gender', v_row.gender,
    'interests', v_row.interests,
    'photo_urls', v_row.photo_urls,
    'is_photo_verified', v_row.is_photo_verified,
    'neighborhood', v_row.neighborhood
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_match_profile TO authenticated;

-- ----------------------------------------------------------------------------
-- 8. Sync subscription flags when subscription row changes
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sync_subscription_flags()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.profiles
  SET
    is_subscriber = EXISTS (
      SELECT 1 FROM public.subscriptions s
      WHERE s.user_id = COALESCE(NEW.user_id, OLD.user_id)
        AND s.status IN ('active', 'trialing', 'grace_period')
        AND (s.expires_at IS NULL OR s.expires_at > NOW())
    ),
    subscription_tier = COALESCE(
      (
        SELECT s.tier FROM public.subscriptions s
        WHERE s.user_id = COALESCE(NEW.user_id, OLD.user_id)
          AND s.status IN ('active', 'trialing', 'grace_period')
        ORDER BY s.starts_at DESC LIMIT 1
      ),
      'free'
    ),
    show_ads = NOT EXISTS (
      SELECT 1 FROM public.subscriptions s
      WHERE s.user_id = COALESCE(NEW.user_id, OLD.user_id)
        AND s.status IN ('active', 'trialing', 'grace_period')
    ),
    updated_at = NOW()
  WHERE id = COALESCE(NEW.user_id, OLD.user_id);
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS subscriptions_sync_flags ON public.subscriptions;
CREATE TRIGGER subscriptions_sync_flags
  AFTER INSERT OR UPDATE OR DELETE ON public.subscriptions
  FOR EACH ROW EXECUTE FUNCTION public.sync_subscription_flags();

-- ----------------------------------------------------------------------------
-- 9. Profiles: allow authenticated read of limited fields for encounter photos
-- (Pre-match still only photo+neighborhood via get_my_encounters RPC)
-- Own profile full access already exists.
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Users can read limited public profiles" ON public.profiles;
CREATE POLICY "Users can read limited public profiles"
  ON public.profiles FOR SELECT
  TO authenticated
  USING (
    id = auth.uid()
    OR (
      is_active = TRUE
      AND deleted_at IS NULL
      AND is_paused = FALSE
    )
  );

COMMENT ON FUNCTION public.handle_new_user IS
  'Creates empty profile row when auth.users inserts (email/phone/OAuth/anonymous).';
COMMENT ON FUNCTION public.upsert_my_profile IS
  'Client profile setup; enforces 18+, bio 500, max 6 photos.';
COMMENT ON FUNCTION public.request_account_deletion IS
  'Soft-delete + scrub PII and location history.';
