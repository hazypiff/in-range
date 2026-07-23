-- 0053: late-evidence tolerance — reciprocity must survive asymmetric uploads.
--
-- WHY (locked-iPhone reality, bench-measured 2026-07-23, see
-- docs/IOS_BACKGROUND_BLE_WIRING.md): an Android peer uploads rich, timely
-- sightings of a locked iPhone (overflow scan + GATT reads), but the locked
-- iPhone buffers its own sightings natively and only flushes them when the
-- user wakes the phone — minutes later. Three server gates then killed the
-- flush, so the pair could NEVER confirm:
--   1. record_sighting: p_observed_at older than 10 min  -> 'Invalid sighting time'
--   2. record_sighting + correlate_encounter: observed token more than 2 min
--      past valid_until -> 'Unknown or expired beacon token'
--   3. correlate_encounter reciprocity: reverse sighting received_at within
--      3 min -> the other side's last upload is often older by the flush time
--
-- CHANGE: one knob, app_settings.late_evidence_window_minutes (default 15,
-- server-clamped to [2, 25]), replaces all three constants. 2 preserves the
-- old grace as the floor; 25 keeps every window inside a token lifetime
-- (claim_token enforces valid_until <= now + 21 min), so evidence can never
-- outlive the token that anchors it by more than the clamp.
--
-- WHAT DOES NOT CHANGE (the anti-forgery envelope):
--   - Reciprocity still keys on SERVER received_at; caller-supplied
--     timestamps still cannot widen anything (harness T2).
--   - The GPS veto still bounds space: correlate refuses when the caller's
--     coords are farther than the (<=400 m) radius from the claim's coords —
--     a replayed token confirms nothing from far away.
--   - Both directions must still be real uploads by both accounts; nothing
--     here lets one device fabricate the other's evidence.
--   Widening is therefore purely temporal: "both saw each other within ~15
--   min at the same place" instead of "within 3 min". The sniffed-token
--   replay window grows from 2 to <=25 min; that surface is already tracked
--   (docs/RELAY_ABUSE_RUNBOOK.md, attestation scaffold 0034) and stays
--   GPS-bounded.
--
-- Harness: T2/T6 fixtures updated (stale means beyond-the-window now),
-- new T48 proves the full locked-iPhone late-flush confirms.

-- ---------------------------------------------------------------------------
-- The knob + its reader. STABLE: one read per statement is fine; the clamp
-- lives here so a bad/absent setting can never widen past a token lifetime.
-- ---------------------------------------------------------------------------
INSERT INTO public.app_settings (key, value_num)
VALUES ('late_evidence_window_minutes', 15)
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.late_evidence_window()
RETURNS INTERVAL
LANGUAGE sql STABLE
SET search_path = pg_catalog, public
AS $$
  SELECT make_interval(mins => GREATEST(2, LEAST(25, COALESCE(
    (SELECT value_num FROM public.app_settings
      WHERE key = 'late_evidence_window_minutes'), 15)))::INT);
$$;

-- Internal helper: called only inside SECURITY DEFINER functions.
REVOKE EXECUTE ON FUNCTION public.late_evidence_window() FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- record_sighting: gates 1 + 2. Verbatim 0048 body except the two windows.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_sighting(p_observed_token text, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_rssi integer DEFAULT NULL::integer, p_observed_at timestamp with time zone DEFAULT now(), p_range range_type DEFAULT NULL::range_type, p_accuracy double precision DEFAULT NULL::double precision)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid(); v_now TIMESTAMPTZ := clock_timestamp(); v_id BIGINT;
  v_range public.range_type := COALESCE(p_range,'feet_10');
  v_radius DOUBLE PRECISION; v_window INT; v_claim_acc DOUBLE PRECISION; v_calls INT;
  v_observed_uid UUID;
  v_late INTERVAL := public.late_evidence_window();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;
  IF NOT public.current_user_can_discover() THEN RAISE EXCEPTION 'Account is not discoverable' USING ERRCODE='42501'; END IF;
  -- Consent gate (0040). No-op unless app_settings.enforce_consent = 1.
  PERFORM public.require_consent(v_uid, 'ble_proximity');
  -- 0048: the observer uploads their OWN GPS here; a caller who withdrew
  -- precise_location must not keep doing so via Beacon.
  IF public.consent_withdrawn(v_uid, 'precise_location') THEN
    RAISE EXCEPTION 'Location sharing was turned off' USING ERRCODE='42501'; END IF;
  IF p_observed_token IS NULL OR lower(p_observed_token) !~ '^[0-9a-f]{32}$' THEN RAISE EXCEPTION 'Invalid beacon token' USING ERRCODE='22023'; END IF;
  -- 0053: was a fixed 10 min — a locked iPhone's natively-buffered sightings
  -- flush with their ORIGINAL capture timestamps when the user wakes it.
  IF p_observed_at IS NULL OR p_observed_at < v_now - v_late OR p_observed_at > v_now + INTERVAL '1 minute' THEN RAISE EXCEPTION 'Invalid sighting time' USING ERRCODE='22023'; END IF;
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
  -- 0053: grace widened from 2 min to the late-evidence window — a flushed
  -- sighting may reference a token that expired while the phone slept.
  SELECT h.user_id INTO v_observed_uid FROM public.token_claim_history h
  WHERE h.token = lower(p_observed_token) AND h.user_id <> v_uid
    AND h.valid_until > v_now - v_late
  ORDER BY h.valid_from DESC LIMIT 1;
  IF v_observed_uid IS NULL THEN RAISE EXCEPTION 'Unknown or expired beacon token' USING ERRCODE='22023'; END IF;
  -- 0046: an observed user who withdrew BLE consent must not generate new
  -- evidence, even from a token preserved in history under a legal hold.
  -- 0048: an observed user who withdrew EITHER ble_proximity or precise_location
  -- must not generate new location-correlated evidence.
  IF public.consent_withdrawn(v_observed_uid, 'ble_proximity')
     OR public.consent_withdrawn(v_observed_uid, 'precise_location') THEN
    RAISE EXCEPTION 'Unknown or expired beacon token' USING ERRCODE='22023'; END IF;

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
$function$;

-- ---------------------------------------------------------------------------
-- correlate_encounter: gate 3 (+ the same claim grace, + a valid_from floor
-- that can never exclude a late-window-valid claim). Verbatim 0030 body
-- except the three window expressions.
-- ---------------------------------------------------------------------------
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
  v_late INTERVAL := public.late_evidence_window();
  v_late_min INT := (EXTRACT(EPOCH FROM public.late_evidence_window()) / 60)::INT;
BEGIN
  IF v_uid IS NULL OR NOT public.current_user_can_discover() THEN RETURN; END IF;
  SELECT * INTO v_claim FROM public.token_claim_history tc
  WHERE tc.token = lower(p_observed_token) AND tc.user_id <> v_uid
    -- Floor so a late-window-valid, end-of-life token is never excluded
    -- (token life <=21 min + late window; +2 slack). valid_until is the gate.
    AND tc.valid_from > NOW() - make_interval(mins => GREATEST(23 + v_late_min, LEAST(30, GREATEST(1, p_time_window_minutes))))
    AND tc.valid_until > NOW() - v_late ORDER BY tc.valid_from DESC LIMIT 1;
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
  -- 0053: widened from a fixed 3 min — the other side's evidence may be a
  -- locked phone's wake-burst upload from earlier in the same co-presence.
  SELECT rs.range_type INTO v_reverse_band FROM public.sightings rs
  WHERE rs.observer_user_id = v_claim.user_id AND rs.observed_user_id = v_uid
    AND rs.received_at > NOW() - v_late
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
