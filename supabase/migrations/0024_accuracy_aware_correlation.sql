-- Apply the accuracy-aware GPS veto end to end (see 0023 for the rationale).
--
-- Two changes:
--   1. record_sighting() accepts the observer's reported GPS accuracy and
--      sizes the correlation radius from the ACTUAL uncertainty of both
--      phones instead of a fixed 50-100 m guess.
--   2. correlate_encounter()'s hard LEAST(100.0, ...) clamp is raised to
--      400 m. That clamp was the bug: two people standing together indoors
--      can each report a 40 m accuracy circle, and 2*(40+40) = 160 m > 100 m,
--      so the old cap threw the encounter away no matter what we passed in.
--
-- The veto stays coarse ON PURPOSE. It exists to stop cross-city relay/replay,
-- not to measure distance. Distance is BLE's job.

-- Adding p_accuracy with a default creates a NEW overload rather than
-- replacing the old function — both would then match a call that omits
-- p_accuracy, and PostgREST returns PGRST203 (ambiguous). Drop the exact
-- prior signature first (migration 0011 documented this same outage mode).
DROP FUNCTION IF EXISTS public.record_sighting(
  TEXT, DOUBLE PRECISION, DOUBLE PRECISION, INTEGER, TIMESTAMPTZ, public.range_type
);

CREATE OR REPLACE FUNCTION public.record_sighting(
  p_observed_token TEXT,
  p_lat DOUBLE PRECISION DEFAULT NULL,
  p_lon DOUBLE PRECISION DEFAULT NULL,
  p_rssi INTEGER DEFAULT NULL,
  p_observed_at TIMESTAMPTZ DEFAULT NOW(),
  p_range public.range_type DEFAULT NULL,
  p_accuracy DOUBLE PRECISION DEFAULT NULL
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
  v_claim_acc DOUBLE PRECISION;
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
  IF p_accuracy IS NOT NULL AND (p_accuracy < 0 OR p_accuracy > 10000) THEN
    RAISE EXCEPTION 'Invalid accuracy' USING ERRCODE = '22023';
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
      observer_lat, observer_lon, range_type, observer_accuracy_m
    ) VALUES (
      v_uid, lower(p_observed_token), p_rssi, p_observed_at,
      p_lat, p_lon, v_range, p_accuracy
    ) RETURNING id INTO v_id;
  ELSE
    -- Keep a COHERENT strongest observation: RSSI, band, location and accuracy
    -- must come from the SAME sample. Only when this sample is strictly
    -- stronger do we replace all of them together; otherwise we merely advance
    -- observed_at (a monotonic last-seen). Previously GREATEST(rssi) was pinned
    -- to the LATEST sample's location/band — an observation that never
    -- happened, which could pass the RSSI gate on old strength but store an
    -- unrelated GPS tuple/band (reviewer #12).
    UPDATE public.sightings
    SET observed_at = p_observed_at,
        rssi        = CASE WHEN p_rssi > rssi THEN p_rssi ELSE rssi END,
        observer_lat = CASE WHEN p_rssi > rssi THEN p_lat ELSE observer_lat END,
        observer_lon = CASE WHEN p_rssi > rssi THEN p_lon ELSE observer_lon END,
        observer_accuracy_m =
          CASE WHEN p_rssi > rssi THEN p_accuracy ELSE observer_accuracy_m END,
        range_type  = CASE WHEN p_rssi > rssi THEN v_range ELSE range_type END
    WHERE id = v_id;
  END IF;

  v_window := LEAST(30, public.range_time_window_minutes(v_range));

  IF v_range::TEXT LIKE 'feet_%' THEN
    -- BLE already proved these two are within radio range. GPS is only asked
    -- "is this plausible?", sized by what the phones actually reported.
    SELECT tc.accuracy_m INTO v_claim_acc
    FROM public.token_claims tc
    WHERE tc.token = lower(p_observed_token)
    LIMIT 1;

    v_radius := public.gps_veto_radius_meters(p_accuracy, v_claim_acc);
  ELSE
    -- Miles tiers keep their designed geometry.
    v_radius := GREATEST(5.0, public.range_radius_meters(v_range));
  END IF;

  PERFORM public.correlate_encounter(
    lower(p_observed_token), p_lat, p_lon, v_radius, v_window
  );
  RETURN v_id;
END;
$$;

-- correlate_encounter: same as 0022 (encounter band derived from the sighting,
-- narrowing only) but with the distance clamp raised from 100 m to 400 m so an
-- accuracy-aware radius can actually take effect.
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
  v_sight_range public.range_type;
  v_band public.range_type;
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

  SELECT s.rssi, s.range_type INTO v_rssi, v_sight_range
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
    -- 400 m ceiling (was 100 m): indoors each phone can honestly report a
    -- 40 m accuracy circle, and the old cap silently discarded those pairs.
    IF v_distance > LEAST(400.0, GREATEST(5.0, p_radius_meters)) THEN
      RETURN;
    END IF;
  END IF;

  IF v_sight_range IS NOT NULL AND v_sight_range::TEXT LIKE 'feet_%' THEN
    v_band := v_sight_range;
  ELSE
    v_band := COALESCE(v_claim.range_type, 'feet_10');
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
      v_band,
      CASE WHEN v_distance IS NULL THEN 0.8 ELSE
        LEAST(1.0, GREATEST(0.5, 1.0 - (v_distance / GREATEST(p_radius_meters, 1))))
      END,
      'active'
    ) RETURNING id INTO v_enc_id;
    v_new := TRUE;
  ELSE
    UPDATE public.encounters e
    SET last_seen_at = NOW(),
        range_type = CASE
          WHEN e.range_type::TEXT LIKE 'feet_%'
               AND v_band::TEXT LIKE 'feet_%'
               AND public.range_band_rank(v_band) < public.range_band_rank(e.range_type)
            THEN v_band
          ELSE e.range_type
        END,
        confidence = CASE WHEN v_distance IS NULL THEN confidence ELSE
          LEAST(1.0, GREATEST(0.5, 1.0 - (v_distance / GREATEST(p_radius_meters, 1))))
        END
    WHERE e.id = v_enc_id;
  END IF;

  encounter_id := v_enc_id;
  other_user_id := v_claim.user_id;
  created_new := v_new;
  RETURN NEXT;
END;
$$;

GRANT EXECUTE ON FUNCTION public.record_sighting(
  TEXT, DOUBLE PRECISION, DOUBLE PRECISION, INTEGER, TIMESTAMPTZ,
  public.range_type, DOUBLE PRECISION
) TO authenticated;

-- claim_token also carries the claimer's GPS accuracy, so the veto radius is
-- computed from BOTH phones' real uncertainty rather than one side's.
-- Drop the prior 5-arg signature first (same ambiguous-overload reason as above).
DROP FUNCTION IF EXISTS public.claim_token(
  TEXT, TIMESTAMPTZ, DOUBLE PRECISION, DOUBLE PRECISION, public.range_type
);

CREATE OR REPLACE FUNCTION public.claim_token(
  p_token TEXT,
  p_valid_until TIMESTAMPTZ,
  p_lat DOUBLE PRECISION DEFAULT NULL,
  p_lon DOUBLE PRECISION DEFAULT NULL,
  p_range public.range_type DEFAULT 'miles_10',
  p_accuracy DOUBLE PRECISION DEFAULT NULL
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
  IF p_accuracy IS NOT NULL AND (p_accuracy < 0 OR p_accuracy > 10000) THEN
    RAISE EXCEPTION 'Invalid accuracy' USING ERRCODE = '22023';
  END IF;

  SELECT last_claimed_at INTO v_last
  FROM public.token_claims
  WHERE user_id = v_uid;
  IF v_last IS NOT NULL AND v_last > v_now - INTERVAL '5 seconds' THEN
    RAISE EXCEPTION 'Beacon claim rate limit' USING ERRCODE = '54000';
  END IF;

  INSERT INTO public.token_claims (
    user_id, token, valid_from, valid_until, approx_lat, approx_lon,
    range_type, accuracy_m, created_at, last_claimed_at
  )
  VALUES (
    v_uid, lower(p_token), v_now, p_valid_until, p_lat, p_lon,
    p_range, p_accuracy, v_now, v_now
  )
  ON CONFLICT (user_id) DO UPDATE SET
    token = EXCLUDED.token,
    valid_from = EXCLUDED.valid_from,
    valid_until = EXCLUDED.valid_until,
    approx_lat = EXCLUDED.approx_lat,
    approx_lon = EXCLUDED.approx_lon,
    range_type = EXCLUDED.range_type,
    accuracy_m = EXCLUDED.accuracy_m,
    last_claimed_at = EXCLUDED.last_claimed_at;
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_token(
  TEXT, TIMESTAMPTZ, DOUBLE PRECISION, DOUBLE PRECISION,
  public.range_type, DOUBLE PRECISION
) TO authenticated;
