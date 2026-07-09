-- =============================================================================
-- Migration 0003: Fix correlate_encounter time-window bug + range-aware radius
-- =============================================================================
-- BUGS FIXED:
-- 1. correlate_encounter: `valid_until > NOW() - window` allowed expired claims
--    to match. Should be `valid_until > NOW()` (claim must still be active).
-- 2. record_sighting: hardcoded 50m + 90min regardless of range_type. Miles
--    modes (miles_1, miles_10) need a larger radius (1km / 5km) or they never
--    correlate. Now derives radius + window from the observed token's
--    range_type.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Fix 1: correlate_encounter — active claims only (valid_until > NOW())
-- -----------------------------------------------------------------------------
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
SET search_path = public
AS $$
DECLARE
  v_observer_id UUID := auth.uid();
  v_claim RECORD;
  v_distance NUMERIC;
  v_enc_id BIGINT;
  v_user_a UUID;
  v_user_b UUID;
  v_new BOOLEAN := FALSE;
BEGIN
  IF v_observer_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Find recent claims for this token from OTHER users.
  -- Bug fix: claim must still be ACTIVE (valid_until > NOW()), not just
  -- "expired within the last window". The previous logic matched claims that
  -- had been expired for up to p_time_window_minutes.
  FOR v_claim IN
    SELECT
      tc.user_id,
      tc.approx_lat,
      tc.approx_lon,
      tc.range_type,
      tc.valid_from
    FROM public.token_claims tc
    WHERE tc.token = p_observed_token
      AND tc.user_id != v_observer_id
      AND tc.valid_from > NOW() - (p_time_window_minutes || ' minutes')::interval
      AND tc.valid_until > NOW()
    ORDER BY tc.valid_from DESC
    LIMIT 5
  LOOP
    -- Compute distance using PostGIS (longitude first in ST_MakePoint)
    IF v_claim.approx_lat IS NOT NULL AND v_claim.approx_lon IS NOT NULL THEN
      v_distance := ST_Distance(
        ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography,
        ST_SetSRID(ST_MakePoint(v_claim.approx_lon, v_claim.approx_lat), 4326)::geography
      );

      IF v_distance <= p_radius_meters THEN
        -- Canonical user order
        IF v_observer_id < v_claim.user_id THEN
          v_user_a := v_observer_id;
          v_user_b := v_claim.user_id;
        ELSE
          v_user_a := v_claim.user_id;
          v_user_b := v_observer_id;
        END IF;

        -- Insert encounter (idempotent)
        INSERT INTO public.encounters (
          user_a,
          user_b,
          neighborhood,
          encounter_time,
          range_type,
          confidence
        )
        VALUES (
          v_user_a,
          v_user_b,
          'Neighborhood',
          NOW(),
          COALESCE(v_claim.range_type, 'miles_10'),
          LEAST(1.0, GREATEST(0.5, 1.0 - (v_distance / 100.0)))
        )
        ON CONFLICT (user_a, user_b, encounter_time) DO NOTHING
        RETURNING id INTO v_enc_id;

        IF v_enc_id IS NOT NULL THEN
          v_new := TRUE;
        ELSE
          SELECT id INTO v_enc_id
          FROM public.encounters
          WHERE user_a = v_user_a AND user_b = v_user_b
          ORDER BY encounter_time DESC
          LIMIT 1;
        END IF;

        encounter_id := v_enc_id;
        other_user_id := v_claim.user_id;
        created_new := v_new;
        RETURN NEXT;
        v_new := FALSE;
      END IF;
    END IF;
  END LOOP;

  RETURN;
END;
$$;

-- -----------------------------------------------------------------------------
-- Fix 2: record_sighting — derive radius + window from range_type
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_sighting(
  p_observed_token TEXT,
  p_lat DOUBLE PRECISION,
  p_lon DOUBLE PRECISION,
  p_rssi INTEGER DEFAULT NULL,
  p_observed_at TIMESTAMPTZ DEFAULT NOW(),
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
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

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
    p_lat,
    p_lon,
    p_range
  )
  RETURNING id INTO v_sighting_id;

  -- Derive correlation radius + time window from the range_type.
  -- Feet modes: tight radius (50m) so encounters reflect real proximity.
  -- Miles modes: wider radius so they actually correlate.
  v_radius := CASE COALESCE(p_range, 'feet_10')
    WHEN 'feet_10'  THEN 50.0
    WHEN 'feet_100' THEN 100.0
    WHEN 'feet_500' THEN 500.0
    WHEN 'miles_1'  THEN 1609.0
    WHEN 'miles_10' THEN 8046.0
    ELSE 50.0
  END;

  v_window := CASE COALESCE(p_range, 'feet_10')
    WHEN 'feet_10'  THEN 15
    WHEN 'feet_100' THEN 30
    WHEN 'feet_500' THEN 60
    WHEN 'miles_1'  THEN 90
    WHEN 'miles_10' THEN 180
    ELSE 60
  END;

  PERFORM public.correlate_encounter(
    p_observed_token,
    p_lat,
    p_lon,
    v_radius,
    v_window
  );

  RETURN v_sighting_id;
END;
$$;

-- =============================================================================
-- END OF MIGRATION
-- =============================================================================
