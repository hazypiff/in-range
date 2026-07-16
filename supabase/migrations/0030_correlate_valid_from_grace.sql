-- Rotation-boundary fix (found reviewing #5/#6): correlate_encounter silently
-- dropped legitimate reciprocal encounters observed near a token's end of life.
--
-- record_sighting accepts a token while valid_until > now - 2min (grace). But
-- correlate_encounter required valid_from > now - LEAST(30, window) — 15 min for
-- feet. A live-within-grace token can have valid_from up to ~23 min ago (life
-- <=21 min + 2 min grace), so the last portion of every token's life failed the
-- valid_from floor: record_sighting stored the sighting, correlate never
-- confirmed. Reproduced: end-of-life reciprocal pair -> sighting stored,
-- 0 encounters.
--
-- The real recency gate is valid_until > now - 2min (a token is created with
-- valid_until <= now+21min, so a grace-valid claim was made at most ~23 min
-- ago). Floor the valid_from window at 25 min so it never excludes a
-- grace-valid claim. Not a security change: valid_until + the reciprocity
-- server-receipt window remain the gates; this only stops wrongly dropping
-- honest late-life encounters.

CREATE OR REPLACE FUNCTION public.correlate_encounter(
  p_observed_token TEXT, p_lat DOUBLE PRECISION, p_lon DOUBLE PRECISION,
  p_radius_meters DOUBLE PRECISION DEFAULT 50, p_time_window_minutes INT DEFAULT 60
)
RETURNS TABLE (encounter_id BIGINT, other_user_id UUID, created_new BOOLEAN)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid UUID := auth.uid(); v_claim public.token_claim_history%ROWTYPE;
  v_user_a UUID; v_user_b UUID; v_enc_id BIGINT;
  v_distance DOUBLE PRECISION; v_rssi INTEGER; v_min_rssi INTEGER;
  v_new BOOLEAN := FALSE; v_sight_range public.range_type; v_band public.range_type;
  v_reverse_band public.range_type; v_now TIMESTAMPTZ := NOW();
BEGIN
  IF v_uid IS NULL OR NOT public.current_user_can_discover() THEN RETURN; END IF;
  SELECT * INTO v_claim FROM public.token_claim_history tc
  WHERE tc.token = lower(p_observed_token) AND tc.user_id <> v_uid
    -- Floor at 25 min so a grace-valid, end-of-life token is never excluded
    -- (token life <=21 min + 2 min grace). valid_until below is the real gate.
    AND tc.valid_from > NOW() - make_interval(mins => GREATEST(25, LEAST(30, GREATEST(1, p_time_window_minutes))))
    AND tc.valid_until > NOW() - INTERVAL '2 minutes' ORDER BY tc.valid_from DESC LIMIT 1;
  IF NOT FOUND OR NOT public.is_discoverable_user(v_claim.user_id) THEN RETURN; END IF;
  IF public.is_blocked_pair(v_uid, v_claim.user_id) THEN RETURN; END IF;

  SELECT s.rssi, s.range_type INTO v_rssi, v_sight_range FROM public.sightings s
  WHERE s.observer_user_id = v_uid AND s.observed_token = lower(p_observed_token)
  ORDER BY s.observed_at DESC LIMIT 1;
  v_min_rssi := CASE COALESCE(v_claim.range_type,'feet_10') WHEN 'feet_10' THEN -75 WHEN 'feet_20' THEN -85 ELSE -95 END;
  IF v_rssi IS NULL OR v_rssi < v_min_rssi THEN RETURN; END IF;

  IF p_lat IS NOT NULL AND p_lon IS NOT NULL AND v_claim.approx_lat IS NOT NULL AND v_claim.approx_lon IS NOT NULL THEN
    v_distance := ST_Distance(ST_SetSRID(ST_MakePoint(p_lon, p_lat),4326)::geography, ST_SetSRID(ST_MakePoint(v_claim.approx_lon, v_claim.approx_lat),4326)::geography);
    IF v_distance > LEAST(400.0, GREATEST(5.0, p_radius_meters)) THEN RETURN; END IF;
  END IF;

  IF v_sight_range IS NOT NULL AND v_sight_range::TEXT LIKE 'feet_%' THEN v_band := v_sight_range; ELSE v_band := COALESCE(v_claim.range_type, 'feet_10'); END IF;

  -- Reciprocity gate (server-receipt window; caller-supplied values ignored).
  SELECT rs.range_type INTO v_reverse_band FROM public.sightings rs
  WHERE rs.observer_user_id = v_claim.user_id AND rs.observed_user_id = v_uid
    AND rs.received_at > NOW() - INTERVAL '3 minutes'
  ORDER BY rs.received_at DESC LIMIT 1;
  IF NOT FOUND THEN RETURN; END IF;

  IF v_reverse_band IS NOT NULL AND v_reverse_band::TEXT LIKE 'feet_%' AND v_band::TEXT LIKE 'feet_%'
     AND public.range_band_rank(v_reverse_band) > public.range_band_rank(v_band) THEN
    v_band := v_reverse_band;
  END IF;

  v_user_a := LEAST(v_uid, v_claim.user_id); v_user_b := GREATEST(v_uid, v_claim.user_id);
  PERFORM pg_advisory_xact_lock(hashtextextended(v_user_a::TEXT || v_user_b::TEXT, 0));
  PERFORM public.bump_encounter_pair(v_user_a, v_user_b, v_band);
  UPDATE public.encounter_pairs SET trust_level = COALESCE(trust_level, 'mutual_ble')
    WHERE user_a = v_user_a AND user_b = v_user_b;

  SELECT id INTO v_enc_id FROM public.encounters WHERE user_a = v_user_a AND user_b = v_user_b AND status = 'active' ORDER BY encounter_time DESC LIMIT 1 FOR UPDATE;
  IF v_enc_id IS NULL THEN
    INSERT INTO public.encounters (user_a,user_b,neighborhood,encounter_time,last_seen_at,range_type,confidence,status,trust_level)
    VALUES (v_user_a,v_user_b,'Near you',v_now,v_now,v_band,0.8,'active','mutual_ble') RETURNING id INTO v_enc_id; v_new := TRUE;
  ELSE
    UPDATE public.encounters e SET last_seen_at = v_now, trust_level = COALESCE(e.trust_level,'mutual_ble'),
      range_type = CASE WHEN e.range_type::TEXT LIKE 'feet_%' AND v_band::TEXT LIKE 'feet_%' AND public.range_band_rank(v_band) < public.range_band_rank(e.range_type) THEN v_band ELSE e.range_type END
    WHERE e.id = v_enc_id;
  END IF;
  encounter_id := v_enc_id; other_user_id := v_claim.user_id; created_new := v_new; RETURN NEXT;
END;
$$;
