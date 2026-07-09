-- =============================================================================
-- Migration 0008: Miles-based GPS correlation + location ping RPC
-- =============================================================================
-- Outline: miles 1–200 indefinite lifespan; continuous logging while beacon ON.
-- Pure GPS path when BLE is off/sparse: location_pings + correlate_miles.
-- =============================================================================

-- ----------------------------------------------------------------------------
-- 1. Range helpers (full enum coverage — fixes incomplete CASE in 0003)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.range_radius_meters(p_range public.range_type)
RETURNS DOUBLE PRECISION
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE p_range
    WHEN 'feet_10'   THEN 5.0
    WHEN 'feet_20'   THEN 8.0
    WHEN 'feet_30'   THEN 12.0
    WHEN 'miles_1'   THEN 1609.0
    WHEN 'miles_5'   THEN 8047.0
    WHEN 'miles_10'  THEN 16093.0
    WHEN 'miles_25'  THEN 40234.0
    WHEN 'miles_50'  THEN 80467.0
    WHEN 'miles_100' THEN 160934.0
    WHEN 'miles_200' THEN 321869.0
    ELSE 1609.0
  END;
$$;

CREATE OR REPLACE FUNCTION public.range_time_window_minutes(p_range public.range_type)
RETURNS INT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE p_range
    WHEN 'feet_10'   THEN 15
    WHEN 'feet_20'   THEN 20
    WHEN 'feet_30'   THEN 30
    WHEN 'miles_1'   THEN 90
    WHEN 'miles_5'   THEN 120
    WHEN 'miles_10'  THEN 180
    WHEN 'miles_25'  THEN 240
    WHEN 'miles_50'  THEN 360
    WHEN 'miles_100' THEN 720
    WHEN 'miles_200' THEN 1440
    ELSE 90
  END;
$$;

GRANT EXECUTE ON FUNCTION public.range_radius_meters TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.range_time_window_minutes TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2. record_location_ping — client-friendly RPC (lat/lon → geography)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_location_ping(
  p_lat DOUBLE PRECISION,
  p_lon DOUBLE PRECISION,
  p_range public.range_type DEFAULT 'miles_10',
  p_neighborhood TEXT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_id BIGINT;
  v_hood TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_lat IS NULL OR p_lon IS NULL THEN
    RAISE EXCEPTION 'lat/lon required';
  END IF;
  IF p_lat < -90 OR p_lat > 90 OR p_lon < -180 OR p_lon > 180 THEN
    RAISE EXCEPTION 'Invalid coordinates';
  END IF;

  -- Skip if user paused or deleted
  IF EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = v_uid AND (is_paused OR deleted_at IS NOT NULL OR NOT is_active)
  ) THEN
    RAISE EXCEPTION 'Account not discoverable';
  END IF;

  v_hood := COALESCE(
    NULLIF(trim(p_neighborhood), ''),
    'Area ' || round(p_lat::numeric, 2)::text || ', ' || round(p_lon::numeric, 2)::text
  );

  INSERT INTO public.location_pings (user_id, geo, range_type, neighborhood)
  VALUES (
    v_uid,
    ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography,
    p_range,
    v_hood
  )
  RETURNING id INTO v_id;

  UPDATE public.profiles
  SET last_active_at = NOW(), neighborhood = v_hood
  WHERE id = v_uid;

  -- Fire miles correlation for this ping
  PERFORM public.correlate_miles_encounters(
    p_lat,
    p_lon,
    p_range,
    v_hood
  );

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.record_location_ping TO authenticated;

-- ----------------------------------------------------------------------------
-- 3. correlate_miles_encounters — match users within range who also pinged
-- ----------------------------------------------------------------------------
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
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_radius DOUBLE PRECISION;
  v_window INT;
  v_point GEOGRAPHY;
  r RECORD;
  v_user_a UUID;
  v_user_b UUID;
  v_enc_id BIGINT;
  v_new BOOLEAN;
  v_distance DOUBLE PRECISION;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Only for miles ranges (feet uses BLE path)
  IF p_range::text NOT LIKE 'miles_%' THEN
    RETURN;
  END IF;

  v_radius := public.range_radius_meters(p_range);
  v_window := public.range_time_window_minutes(p_range);
  v_point := ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography;

  FOR r IN
    SELECT DISTINCT ON (lp.user_id)
      lp.user_id,
      lp.neighborhood,
      lp.range_type,
      ST_Distance(lp.geo, v_point) AS distance_m,
      lp.created_at
    FROM public.location_pings lp
    JOIN public.profiles pr ON pr.id = lp.user_id
    WHERE lp.user_id <> v_uid
      AND lp.created_at > NOW() - (v_window || ' minutes')::interval
      AND ST_DWithin(lp.geo, v_point, v_radius)
      AND COALESCE(pr.is_paused, FALSE) = FALSE
      AND pr.deleted_at IS NULL
      AND pr.is_active = TRUE
      AND COALESCE(pr.is_incognito, FALSE) = FALSE  -- incognito hidden from Locals
      AND NOT public.is_blocked_pair(v_uid, lp.user_id)
      -- Sexual preference / gender filter when both set
      AND (
        pr.sexual_preference IS NULL
        OR (SELECT sexual_preference FROM public.profiles WHERE id = v_uid) IS NULL
        OR public.preferences_compatible(v_uid, lp.user_id)
      )
    ORDER BY lp.user_id, lp.created_at DESC
    LIMIT 100
  LOOP
    v_distance := r.distance_m;
    IF v_uid < r.user_id THEN
      v_user_a := v_uid;
      v_user_b := r.user_id;
    ELSE
      v_user_a := r.user_id;
      v_user_b := v_uid;
    END IF;

    -- Dedup: one active miles encounter per pair (refresh time if exists)
    SELECT id INTO v_enc_id
    FROM public.encounters
    WHERE user_a = v_user_a AND user_b = v_user_b
      AND status = 'active'
      AND range_type::text LIKE 'miles_%'
    ORDER BY encounter_time DESC
    LIMIT 1;

    IF v_enc_id IS NOT NULL THEN
      UPDATE public.encounters
      SET
        encounter_time = NOW(),
        neighborhood = COALESCE(p_neighborhood, r.neighborhood, neighborhood),
        confidence = LEAST(1.0, GREATEST(0.4, 1.0 - (v_distance / v_radius)))
      WHERE id = v_enc_id;
      v_new := FALSE;
    ELSE
      INSERT INTO public.encounters (
        user_a, user_b, neighborhood, encounter_time, range_type, confidence, status
      )
      VALUES (
        v_user_a,
        v_user_b,
        COALESCE(p_neighborhood, r.neighborhood, 'Nearby area'),
        NOW(),
        p_range,
        LEAST(1.0, GREATEST(0.4, 1.0 - (v_distance / v_radius))),
        'active'
      )
      RETURNING id INTO v_enc_id;
      v_new := TRUE;

      -- Notify both of new encounter (respect reveal delay client-side)
      INSERT INTO public.notification_outbox (user_id, kind, title, body, payload)
      VALUES
        (
          v_uid,
          'new_encounter',
          'New person in range',
          'Someone was near ' || COALESCE(p_neighborhood, r.neighborhood, 'you'),
          jsonb_build_object('encounter_id', v_enc_id, 'other_user_id', r.user_id)
        ),
        (
          r.user_id,
          'new_encounter',
          'New person in range',
          'Someone was near ' || COALESCE(r.neighborhood, p_neighborhood, 'you'),
          jsonb_build_object('encounter_id', v_enc_id, 'other_user_id', v_uid)
        );
    END IF;

    encounter_id := v_enc_id;
    other_user_id := r.user_id;
    created_new := v_new;
    RETURN NEXT;
  END LOOP;

  RETURN;
END;
$$;

GRANT EXECUTE ON FUNCTION public.correlate_miles_encounters TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 4. Preference compatibility (gender × sexual_preference)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.preferences_compatible(a UUID, b UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  pa public.profiles%ROWTYPE;
  pb public.profiles%ROWTYPE;
BEGIN
  SELECT * INTO pa FROM public.profiles WHERE id = a;
  SELECT * INTO pb FROM public.profiles WHERE id = b;
  IF NOT FOUND OR pa.id IS NULL OR pb.id IS NULL THEN
    RETURN TRUE; -- incomplete profiles: allow (client filters later)
  END IF;

  -- sexual_preference: men | women | both
  -- gender: male | female | non-binary | prefer-not-to-say | other
  RETURN
    public._pref_matches(pa.sexual_preference, pb.gender)
    AND public._pref_matches(pb.sexual_preference, pa.gender);
END;
$$;

CREATE OR REPLACE FUNCTION public._pref_matches(pref TEXT, other_gender TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN pref IS NULL OR other_gender IS NULL THEN TRUE
    WHEN pref = 'both' THEN TRUE
    WHEN pref = 'men' THEN other_gender IN ('male')
    WHEN pref = 'women' THEN other_gender IN ('female')
    ELSE TRUE
  END;
$$;

GRANT EXECUTE ON FUNCTION public.preferences_compatible TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 5. get_locals_feed — people currently in miles range (pre-swipe discovery)
-- ----------------------------------------------------------------------------
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
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_radius DOUBLE PRECISION;
  v_window INT;
  v_point GEOGRAPHY;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  v_radius := public.range_radius_meters(p_range);
  v_window := public.range_time_window_minutes(p_range);
  v_point := ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography;

  RETURN QUERY
  SELECT DISTINCT ON (lp.user_id)
    lp.user_id,
    ST_Distance(lp.geo, v_point) AS distance_m,
    lp.neighborhood,
    pr.photo_urls,
    COALESCE(pr.is_photo_verified, FALSE),
    public.has_active_boost(lp.user_id),
    lp.created_at
  FROM public.location_pings lp
  JOIN public.profiles pr ON pr.id = lp.user_id
  WHERE lp.user_id <> v_uid
    AND lp.created_at > NOW() - (v_window || ' minutes')::interval
    AND ST_DWithin(lp.geo, v_point, v_radius)
    AND COALESCE(pr.is_paused, FALSE) = FALSE
    AND pr.deleted_at IS NULL
    AND pr.is_active
    AND COALESCE(pr.is_incognito, FALSE) = FALSE
    AND COALESCE(array_length(pr.photo_urls, 1), 0) > 0
    AND NOT public.is_blocked_pair(v_uid, lp.user_id)
    AND public.preferences_compatible(v_uid, lp.user_id)
  ORDER BY lp.user_id, public.has_active_boost(lp.user_id) DESC, lp.created_at DESC
  LIMIT p_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_locals_feed TO authenticated;

-- ----------------------------------------------------------------------------
-- 6. Fix record_sighting to use full range map
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_sighting(
  p_observed_token TEXT,
  p_rssi INTEGER DEFAULT NULL,
  p_observed_at TIMESTAMPTZ DEFAULT NOW(),
  p_lat DOUBLE PRECISION DEFAULT NULL,
  p_lon DOUBLE PRECISION DEFAULT NULL,
  p_range public.range_type DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_sighting_id BIGINT;
  v_radius DOUBLE PRECISION;
  v_window INT;
  v_range public.range_type;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  v_range := COALESCE(p_range, 'feet_10');

  INSERT INTO public.sightings (
    observer_user_id,
    observed_token,
    rssi,
    observed_at,
    observer_lat,
    observer_lon,
    range_type
  )
  VALUES (
    v_user_id,
    p_observed_token,
    p_rssi,
    p_observed_at,
    COALESCE(p_lat, 0),
    COALESCE(p_lon, 0),
    v_range
  )
  RETURNING id INTO v_sighting_id;

  IF p_lat IS NOT NULL AND p_lon IS NOT NULL THEN
    v_radius := public.range_radius_meters(v_range);
    -- BLE feet: expand slightly for GPS noise
    IF v_range::text LIKE 'feet_%' THEN
      v_radius := GREATEST(v_radius, 50.0);
    END IF;
    v_window := public.range_time_window_minutes(v_range);

    PERFORM public.correlate_encounter(
      p_observed_token,
      p_lat,
      p_lon,
      v_radius,
      v_window
    );
  END IF;

  RETURN v_sighting_id;
END;
$$;

-- ----------------------------------------------------------------------------
-- 7. Batch correlate job for service_role (Edge cron)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.batch_correlate_recent_pings(
  p_lookback_minutes INT DEFAULT 30
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r RECORD;
  v_count INT := 0;
BEGIN
  -- For each recent ping, find nearby other users and upsert encounters
  FOR r IN
    SELECT DISTINCT ON (lp.user_id)
      lp.user_id,
      ST_Y(lp.geo::geometry) AS lat,
      ST_X(lp.geo::geometry) AS lon,
      lp.range_type,
      lp.neighborhood
    FROM public.location_pings lp
    WHERE lp.created_at > NOW() - (p_lookback_minutes || ' minutes')::interval
      AND lp.range_type::text LIKE 'miles_%'
    ORDER BY lp.user_id, lp.created_at DESC
  LOOP
    -- Temporarily set role context is not possible; use direct pair insert logic
    INSERT INTO public.encounters (
      user_a, user_b, neighborhood, encounter_time, range_type, confidence, status
    )
    SELECT
      LEAST(r.user_id, o.user_id),
      GREATEST(r.user_id, o.user_id),
      COALESCE(r.neighborhood, o.neighborhood, 'Nearby area'),
      NOW(),
      r.range_type,
      0.7,
      'active'
    FROM (
      SELECT DISTINCT ON (lp2.user_id)
        lp2.user_id,
        lp2.neighborhood,
        lp2.geo
      FROM public.location_pings lp2
      WHERE lp2.user_id <> r.user_id
        AND lp2.created_at > NOW() - (p_lookback_minutes || ' minutes')::interval
        AND ST_DWithin(
          lp2.geo,
          ST_SetSRID(ST_MakePoint(r.lon, r.lat), 4326)::geography,
          public.range_radius_meters(r.range_type)
        )
      ORDER BY lp2.user_id, lp2.created_at DESC
    ) o
    WHERE NOT public.is_blocked_pair(r.user_id, o.user_id)
      AND NOT EXISTS (
        SELECT 1 FROM public.encounters e
        WHERE e.user_a = LEAST(r.user_id, o.user_id)
          AND e.user_b = GREATEST(r.user_id, o.user_id)
          AND e.status = 'active'
          AND e.range_type::text LIKE 'miles_%'
      )
    ON CONFLICT DO NOTHING;

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.batch_correlate_recent_pings TO service_role;

COMMENT ON FUNCTION public.record_location_ping IS
  'Client GPS ping while miles beacon ON; inserts geography + runs miles correlation.';
COMMENT ON FUNCTION public.correlate_miles_encounters IS
  'Creates/refreshes miles encounters for users within selected range radius.';
COMMENT ON FUNCTION public.get_locals_feed IS
  'Locals tab: nearby active profiles (photo only pre-match rules apply client-side).';
COMMENT ON FUNCTION public.batch_correlate_recent_pings IS
  'Service-role cron: re-correlate all recent pings without user JWT.';
