-- #6 step 1: reciprocal confirmation gate.
--
-- Today record_sighting -> correlate_encounter creates a cloud encounter and
-- bumps durable recurrence from a SINGLE, entirely caller-controlled report
-- (RSSI, time, GPS all forgeable; the HMAC key ships in every app). So a relay
-- + an accomplice can forge "we crossed paths" with anyone, anywhere — and the
-- recurrence feature amplifies it into fake familiarity.
--
-- Fix (behavioral): a cloud encounter + recurrence is created ONLY when BOTH
-- phones independently observed each other within a short window measured by
-- SERVER RECEIPT TIME (received_at) — never p_observed_at / GPS / RSSI, which
-- the caller controls. One-way sightings remain anonymous local cards on the
-- client and short-lived pending evidence on the server; they never reveal
-- identity, notify, rank, or increment recurrence.
--
-- NOT full relay protection: a relay that forwards BOTH tokens still makes both
-- phones report each other. True relay resistance needs secure distance
-- ranging (UWB) — tracked as the 'secure_ranged' trust level. Do not describe
-- mutual_ble as cryptographically relay-proof.

ALTER TABLE public.sightings
  ADD COLUMN IF NOT EXISTS observed_user_id UUID,
  ADD COLUMN IF NOT EXISTS received_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- Reverse-direction lookup: "did the peer observe ME recently?"
CREATE INDEX IF NOT EXISTS idx_sightings_reverse
  ON public.sightings (observer_user_id, observed_user_id, received_at DESC);

ALTER TABLE public.encounters
  ADD COLUMN IF NOT EXISTS trust_level TEXT; -- 'mutual_ble' | 'secure_ranged' | NULL (legacy)
ALTER TABLE public.encounter_pairs
  ADD COLUMN IF NOT EXISTS trust_level TEXT;

-- record_sighting: resolve + store the observed user id and the server receipt
-- time; correlation uses these, not the caller's claimed values.
CREATE OR REPLACE FUNCTION public.record_sighting(
  p_observed_token TEXT, p_lat DOUBLE PRECISION DEFAULT NULL, p_lon DOUBLE PRECISION DEFAULT NULL,
  p_rssi INTEGER DEFAULT NULL, p_observed_at TIMESTAMPTZ DEFAULT NOW(),
  p_range public.range_type DEFAULT NULL, p_accuracy DOUBLE PRECISION DEFAULT NULL
)
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid UUID := auth.uid(); v_now TIMESTAMPTZ := clock_timestamp(); v_id BIGINT;
  v_range public.range_type := COALESCE(p_range,'feet_10');
  v_radius DOUBLE PRECISION; v_window INT; v_claim_acc DOUBLE PRECISION; v_calls INT;
  v_observed_uid UUID;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;
  IF NOT public.current_user_can_discover() THEN RAISE EXCEPTION 'Account is not discoverable' USING ERRCODE='42501'; END IF;
  IF p_observed_token IS NULL OR lower(p_observed_token) !~ '^[0-9a-f]{32}$' THEN RAISE EXCEPTION 'Invalid beacon token' USING ERRCODE='22023'; END IF;
  IF p_observed_at IS NULL OR p_observed_at < v_now - INTERVAL '10 minutes' OR p_observed_at > v_now + INTERVAL '1 minute' THEN RAISE EXCEPTION 'Invalid sighting time' USING ERRCODE='22023'; END IF;
  IF p_rssi IS NULL OR p_rssi NOT BETWEEN -127 AND 20 THEN RAISE EXCEPTION 'Invalid RSSI' USING ERRCODE='22023'; END IF;
  IF p_lat IS NULL OR p_lon IS NULL THEN RAISE EXCEPTION 'Fresh coordinates are required' USING ERRCODE='22023'; END IF;
  IF p_lat NOT BETWEEN -90 AND 90 OR p_lon NOT BETWEEN -180 AND 180 THEN RAISE EXCEPTION 'Invalid coordinates' USING ERRCODE='22023'; END IF;
  IF p_accuracy IS NOT NULL AND (p_accuracy < 0 OR p_accuracy > 10000) THEN RAISE EXCEPTION 'Invalid accuracy' USING ERRCODE='22023'; END IF;

  INSERT INTO public.sighting_call_rate AS r (user_id, window_start, calls) VALUES (v_uid, v_now, 1)
  ON CONFLICT (user_id) DO UPDATE
    SET window_start = CASE WHEN r.window_start < v_now - INTERVAL '1 minute' THEN v_now ELSE r.window_start END,
        calls = CASE WHEN r.window_start < v_now - INTERVAL '1 minute' THEN 1 ELSE r.calls + 1 END
  RETURNING calls INTO v_calls;
  IF v_calls > 120 THEN RAISE EXCEPTION 'Sighting rate limit' USING ERRCODE='54000'; END IF;

  -- Resolve who this token belongs to (history-aware; survives rotation).
  SELECT h.user_id INTO v_observed_uid FROM public.token_claim_history h
  WHERE h.token = lower(p_observed_token) AND h.user_id <> v_uid
    AND h.valid_until > v_now - INTERVAL '2 minutes'
  ORDER BY h.valid_from DESC LIMIT 1;
  IF v_observed_uid IS NULL THEN RAISE EXCEPTION 'Unknown or expired beacon token' USING ERRCODE='22023'; END IF;

  INSERT INTO public.sightings AS s (
    observer_user_id, observed_token, observed_user_id, received_at,
    rssi, observed_at, observer_lat, observer_lon, range_type, observer_accuracy_m
  ) VALUES (
    v_uid, lower(p_observed_token), v_observed_uid, v_now,
    p_rssi, p_observed_at, p_lat, p_lon, v_range, p_accuracy
  )
  ON CONFLICT (observer_user_id, observed_token) DO UPDATE
    SET observed_at = p_observed_at, received_at = v_now, observed_user_id = v_observed_uid,
        rssi = CASE WHEN p_rssi > s.rssi THEN p_rssi ELSE s.rssi END,
        observer_lat = CASE WHEN p_rssi > s.rssi THEN p_lat ELSE s.observer_lat END,
        observer_lon = CASE WHEN p_rssi > s.rssi THEN p_lon ELSE s.observer_lon END,
        observer_accuracy_m = CASE WHEN p_rssi > s.rssi THEN p_accuracy ELSE s.observer_accuracy_m END,
        range_type = CASE WHEN p_rssi > s.rssi THEN v_range ELSE s.range_type END
  RETURNING id INTO v_id;

  v_window := LEAST(30, public.range_time_window_minutes(v_range));
  IF v_range::TEXT LIKE 'feet_%' THEN
    SELECT h.accuracy_m INTO v_claim_acc FROM public.token_claim_history h WHERE h.token = lower(p_observed_token) ORDER BY h.valid_from DESC LIMIT 1;
    v_radius := public.gps_veto_radius_meters(p_accuracy, v_claim_acc);
  ELSE v_radius := GREATEST(5.0, public.range_radius_meters(v_range)); END IF;

  PERFORM public.correlate_encounter(lower(p_observed_token), p_lat, p_lon, v_radius, v_window);
  RETURN v_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.record_sighting(TEXT, DOUBLE PRECISION, DOUBLE PRECISION, INTEGER, TIMESTAMPTZ, public.range_type, DOUBLE PRECISION) TO authenticated;

-- correlate_encounter: RECIPROCITY GATE. Only proceed to encounter + recurrence
-- when the peer independently observed me within the server-receipt window.
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
    AND tc.valid_from > NOW() - make_interval(mins => LEAST(30, GREATEST(1, p_time_window_minutes)))
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

  -- ===== RECIPROCITY GATE (reviewer #6 step 1) =====
  -- The peer must have independently observed ME within the SERVER-RECEIPT
  -- window (not caller-controlled p_observed_at). One-way => no cloud encounter,
  -- no recurrence; the client's anonymous local card is unaffected.
  SELECT rs.range_type INTO v_reverse_band FROM public.sightings rs
  WHERE rs.observer_user_id = v_claim.user_id AND rs.observed_user_id = v_uid
    AND rs.received_at > NOW() - INTERVAL '3 minutes'
  ORDER BY rs.received_at DESC LIMIT 1;
  IF NOT FOUND THEN RETURN; END IF;

  -- Displayed band = the WIDER (more conservative) of the two directions, so a
  -- malicious side cannot claim feet_10 when the honest phone saw only a weak
  -- signal.
  IF v_reverse_band IS NOT NULL AND v_reverse_band::TEXT LIKE 'feet_%' AND v_band::TEXT LIKE 'feet_%'
     AND public.range_band_rank(v_reverse_band) > public.range_band_rank(v_band) THEN
    v_band := v_reverse_band;
  END IF;
  -- =================================================

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
