-- Client claims are fixed at feet_60 (the beacon's radio envelope) while the
-- RangeEstimator classifies each sighting into feet_10/30/60. Encounters
-- previously copied the CLAIM's range — so every server encounter became
-- feet_60 regardless of how close the pair actually got. Derive the
-- encounter band from the observer's sighting instead, narrowing on later
-- closer sightings but never widening (mirrors the client's best_band).

CREATE OR REPLACE FUNCTION public.range_band_rank(p_range public.range_type)
RETURNS INT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE p_range
    WHEN 'feet_10' THEN 0
    WHEN 'feet_20' THEN 1  -- legacy rows rank with feet_30
    WHEN 'feet_30' THEN 1
    WHEN 'feet_60' THEN 2
    ELSE 3                 -- miles tiers: never mixed with feet ranking
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
    IF v_distance > LEAST(100.0, GREATEST(5.0, p_radius_meters)) THEN
      RETURN;
    END IF;
  END IF;

  -- Encounter band: the observer's estimated band when it's a feet band,
  -- otherwise fall back to the claim (miles flows keep old behavior).
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
        -- Narrow only: a later closer pass upgrades the band; a far pass
        -- never downgrades it (same rule as the client's best_band).
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
