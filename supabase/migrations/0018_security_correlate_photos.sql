-- =============================================================================
-- Migration 0017: Production readiness — photo bucket privacy + correlate safety
-- =============================================================================
-- F1/F2 audit 2026-07-09:
--   * profile_photos was public — anyone with a UUID path could fetch photos
--   * correlate_encounter created encounters for blocked/paused/inactive peers
-- =============================================================================

-- ----------------------------------------------------------------------------
-- 1. Private profile_photos + authenticated encounter/match-scoped read
-- ----------------------------------------------------------------------------
UPDATE storage.buckets
SET public = false
WHERE id = 'profile_photos';

DROP POLICY IF EXISTS "Public read profile photos" ON storage.objects;

-- Owners always read own folder
DROP POLICY IF EXISTS "Users read own profile photos" ON storage.objects;
CREATE POLICY "Users read own profile photos"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'profile_photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Peers may read only when there is an active/matched encounter or a match
DROP POLICY IF EXISTS "Encounter or match peers read profile photos" ON storage.objects;
CREATE POLICY "Encounter or match peers read profile photos"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'profile_photos'
    AND (
      EXISTS (
        SELECT 1 FROM public.encounters e
        WHERE e.status IN ('active', 'matched')
          AND (
            (e.user_a = auth.uid() AND e.user_b::text = (storage.foldername(name))[1])
            OR (e.user_b = auth.uid() AND e.user_a::text = (storage.foldername(name))[1])
          )
      )
      OR EXISTS (
        SELECT 1 FROM public.matches m
        WHERE (
          (m.user_a = auth.uid() AND m.user_b::text = (storage.foldername(name))[1])
          OR (m.user_b = auth.uid() AND m.user_a::text = (storage.foldername(name))[1])
        )
      )
    )
  );

-- verified_photos: keep public-read only if still used for approved badges;
-- tighten to authenticated for consistency
UPDATE storage.buckets
SET public = false
WHERE id = 'verified_photos';

DROP POLICY IF EXISTS "Public read verified photos" ON storage.objects;
CREATE POLICY "Authenticated read verified photos"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (bucket_id = 'verified_photos');

-- ----------------------------------------------------------------------------
-- 2. correlate_encounter — block / pause / active / deleted / photo-verified
-- ----------------------------------------------------------------------------
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

  -- Observer must be active (not paused)
  IF EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = v_observer_id
      AND (is_paused OR deleted_at IS NOT NULL OR NOT is_active)
  ) THEN
    RETURN;
  END IF;

  FOR v_claim IN
    SELECT
      tc.user_id,
      tc.approx_lat,
      tc.approx_lon,
      tc.range_type,
      tc.valid_from
    FROM public.token_claims tc
    JOIN public.profiles pr ON pr.id = tc.user_id
    WHERE tc.token = p_observed_token
      AND tc.user_id != v_observer_id
      AND tc.valid_from > NOW() - (p_time_window_minutes || ' minutes')::interval
      AND tc.valid_until > NOW() - interval '5 minutes'
      AND pr.is_active = TRUE
      AND COALESCE(pr.is_paused, FALSE) = FALSE
      AND pr.deleted_at IS NULL
      AND COALESCE(pr.is_incognito, FALSE) = FALSE
      AND NOT public.is_blocked_pair(v_observer_id, tc.user_id)
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
      -- BLE-only token match without geo
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

COMMENT ON FUNCTION public.correlate_encounter IS
  'BLE/token correlation. Skips blocked, paused, deleted, inactive, and incognito peers.';

-- ----------------------------------------------------------------------------
-- 3. batch_correlate: also require observer profile active
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
  FOR r IN
    SELECT DISTINCT ON (lp.user_id)
      lp.user_id,
      ST_Y(lp.geo::geometry) AS lat,
      ST_X(lp.geo::geometry) AS lon,
      lp.range_type,
      lp.neighborhood
    FROM public.location_pings lp
    JOIN public.profiles pr ON pr.id = lp.user_id
    WHERE lp.created_at > NOW() - (p_lookback_minutes || ' minutes')::interval
      AND lp.range_type::text LIKE 'miles_%'
      AND pr.is_active
      AND NOT pr.is_paused
      AND pr.deleted_at IS NULL
      AND NOT pr.is_incognito
    ORDER BY lp.user_id, lp.created_at DESC
  LOOP
    INSERT INTO public.encounters (
      user_a, user_b, neighborhood, encounter_time, range_type, confidence, status
    )
    SELECT
      LEAST(r.user_id, o.user_id),
      GREATEST(r.user_id, o.user_id),
      COALESCE(r.neighborhood, o.neighborhood, 'Nearby'),
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
        AND EXISTS (
          SELECT 1 FROM public.profiles pr
          WHERE pr.id = lp2.user_id
            AND pr.is_active
            AND NOT pr.is_paused
            AND pr.deleted_at IS NULL
            AND NOT pr.is_incognito
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
