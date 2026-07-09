-- Feet correlation: 5-minute claim expiry grace + dedupe active encounters per pair
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
      AND tc.valid_until > NOW() - interval '5 minutes'
    ORDER BY tc.valid_from DESC
    LIMIT 5
  LOOP
    IF v_claim.approx_lat IS NOT NULL AND v_claim.approx_lon IS NOT NULL THEN
      v_distance := ST_Distance(
        ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography,
        ST_SetSRID(ST_MakePoint(v_claim.approx_lon, v_claim.approx_lat), 4326)::geography
      );

      IF v_distance <= p_radius_meters THEN
        IF v_observer_id < v_claim.user_id THEN
          v_user_a := v_observer_id; v_user_b := v_claim.user_id;
        ELSE
          v_user_a := v_claim.user_id; v_user_b := v_observer_id;
        END IF;

        SELECT id INTO v_enc_id FROM public.encounters
        WHERE user_a = v_user_a AND user_b = v_user_b AND status = 'active'
        ORDER BY encounter_time DESC LIMIT 1;

        IF v_enc_id IS NULL THEN
          INSERT INTO public.encounters (
            user_a, user_b, neighborhood, encounter_time, range_type, confidence, status
          ) VALUES (
            v_user_a, v_user_b, 'Near you', NOW(),
            COALESCE(v_claim.range_type, 'feet_10'),
            LEAST(1.0, GREATEST(0.5, 1.0 - (v_distance / GREATEST(p_radius_meters, 1)))),
            'active'
          ) RETURNING id INTO v_enc_id;
          v_new := TRUE;
        ELSE
          UPDATE public.encounters SET encounter_time = NOW(),
            confidence = LEAST(1.0, GREATEST(0.5, 1.0 - (v_distance / GREATEST(p_radius_meters, 1))))
          WHERE id = v_enc_id;
          v_new := FALSE;
        END IF;

        encounter_id := v_enc_id;
        other_user_id := v_claim.user_id;
        created_new := v_new;
        RETURN NEXT;
        v_new := FALSE;
      END IF;
    ELSE
      IF v_observer_id < v_claim.user_id THEN
        v_user_a := v_observer_id; v_user_b := v_claim.user_id;
      ELSE
        v_user_a := v_claim.user_id; v_user_b := v_observer_id;
      END IF;
      SELECT id INTO v_enc_id FROM public.encounters
      WHERE user_a = v_user_a AND user_b = v_user_b AND status = 'active'
      ORDER BY encounter_time DESC LIMIT 1;
      IF v_enc_id IS NULL THEN
        INSERT INTO public.encounters (
          user_a, user_b, neighborhood, encounter_time, range_type, confidence, status
        ) VALUES (
          v_user_a, v_user_b, 'Near you', NOW(),
          COALESCE(v_claim.range_type, 'feet_10'), 0.8, 'active'
        ) RETURNING id INTO v_enc_id;
        v_new := TRUE;
      END IF;
      encounter_id := v_enc_id;
      other_user_id := v_claim.user_id;
      created_new := v_new;
      RETURN NEXT;
    END IF;
  END LOOP;
  RETURN;
END;
$$;
