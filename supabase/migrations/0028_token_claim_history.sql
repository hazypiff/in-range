-- #5: token_claims is one row per user (uq_token_claims_user). On rotation the
-- new claim_token OVERWRITES it; release_token DELETES it. A peer that observed
-- the OLD token and buffers the sighting for up to 45 s then uploads it — but
-- the mapping row is gone, so record_sighting / correlate_encounter reject it
-- with "Unknown or expired beacon token." The 2-minute validity grace cannot
-- help because the row no longer exists.
--
-- Fix: keep a short-lived, append-only claim HISTORY. Every claim is also
-- written to token_claim_history; token lookups consult BOTH the live claim and
-- history within valid_until + grace. Ownership stays unique (advertising still
-- uses one live token); release stops advertising without erasing the grace-
-- window mapping. History is pruned by the existing cleanup path.

CREATE TABLE IF NOT EXISTS public.token_claim_history (
  token       TEXT PRIMARY KEY,
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  valid_from  TIMESTAMPTZ NOT NULL,
  valid_until TIMESTAMPTZ NOT NULL,
  approx_lat  DOUBLE PRECISION,
  approx_lon  DOUBLE PRECISION,
  range_type  public.range_type,
  accuracy_m  DOUBLE PRECISION,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_token_claim_history_valid
  ON public.token_claim_history (token, valid_until);
CREATE INDEX IF NOT EXISTS idx_token_claim_history_expiry
  ON public.token_claim_history (valid_until);
ALTER TABLE public.token_claim_history ENABLE ROW LEVEL SECURITY;
-- No policies: only SECURITY DEFINER RPCs read/write it.

-- Backfill the current live claims so nothing is lost at deploy time.
INSERT INTO public.token_claim_history
  (token, user_id, valid_from, valid_until, approx_lat, approx_lon, range_type, accuracy_m, created_at)
SELECT token, user_id, valid_from, valid_until, approx_lat, approx_lon, range_type, accuracy_m, created_at
FROM public.token_claims
ON CONFLICT (token) DO NOTHING;

-- claim_token: write to history in addition to the live one-row-per-user claim.
CREATE OR REPLACE FUNCTION public.claim_token(
  p_token TEXT, p_valid_until TIMESTAMPTZ,
  p_lat DOUBLE PRECISION DEFAULT NULL, p_lon DOUBLE PRECISION DEFAULT NULL,
  p_range public.range_type DEFAULT 'miles_10', p_accuracy DOUBLE PRECISION DEFAULT NULL
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_now TIMESTAMPTZ := clock_timestamp();
  v_last TIMESTAMPTZ;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;
  IF NOT public.current_user_can_discover() THEN
    RAISE EXCEPTION 'Complete age and photo verification before using Beacon' USING ERRCODE='42501'; END IF;
  IF p_token IS NULL OR p_token !~ '^[0-9a-f]{32}$' THEN
    RAISE EXCEPTION 'Invalid beacon token' USING ERRCODE='22023'; END IF;
  IF p_valid_until IS NULL OR p_valid_until <= v_now + INTERVAL '1 minute'
     OR p_valid_until > v_now + INTERVAL '21 minutes' THEN
    RAISE EXCEPTION 'Token validity must end within 1..21 minutes' USING ERRCODE='22023'; END IF;
  IF p_lat IS NULL OR p_lon IS NULL THEN
    RAISE EXCEPTION 'Fresh coordinates are required' USING ERRCODE='22023'; END IF;
  IF p_lat NOT BETWEEN -90 AND 90 OR p_lon NOT BETWEEN -180 AND 180 THEN
    RAISE EXCEPTION 'Invalid coordinates' USING ERRCODE='22023'; END IF;
  IF p_accuracy IS NOT NULL AND (p_accuracy < 0 OR p_accuracy > 10000) THEN
    RAISE EXCEPTION 'Invalid accuracy' USING ERRCODE='22023'; END IF;

  SELECT last_claimed_at INTO v_last FROM public.token_claims WHERE user_id = v_uid;
  IF v_last IS NOT NULL AND v_last > v_now - INTERVAL '5 seconds' THEN
    RAISE EXCEPTION 'Beacon claim rate limit' USING ERRCODE='54000'; END IF;

  INSERT INTO public.token_claims (
    user_id, token, valid_from, valid_until, approx_lat, approx_lon,
    range_type, accuracy_m, created_at, last_claimed_at)
  VALUES (v_uid, lower(p_token), v_now, p_valid_until, p_lat, p_lon, p_range, p_accuracy, v_now, v_now)
  ON CONFLICT (user_id) DO UPDATE SET
    token = EXCLUDED.token, valid_from = EXCLUDED.valid_from, valid_until = EXCLUDED.valid_until,
    approx_lat = EXCLUDED.approx_lat, approx_lon = EXCLUDED.approx_lon,
    range_type = EXCLUDED.range_type, accuracy_m = EXCLUDED.accuracy_m,
    last_claimed_at = EXCLUDED.last_claimed_at;

  -- Append to history so a peer's buffered sighting of THIS token still
  -- resolves for valid_until + grace even after the next rotation/release.
  INSERT INTO public.token_claim_history
    (token, user_id, valid_from, valid_until, approx_lat, approx_lon, range_type, accuracy_m, created_at)
  VALUES (lower(p_token), v_uid, v_now, p_valid_until, p_lat, p_lon, p_range, p_accuracy, v_now)
  ON CONFLICT (token) DO UPDATE SET valid_until = EXCLUDED.valid_until;
END;
$$;
GRANT EXECUTE ON FUNCTION public.claim_token(
  TEXT, TIMESTAMPTZ, DOUBLE PRECISION, DOUBLE PRECISION, public.range_type, DOUBLE PRECISION
) TO authenticated;

-- A single lookup used by record_sighting/correlate_encounter: the live claim
-- OR a recent history row (within valid_until + 2 min grace).
CREATE OR REPLACE FUNCTION public.lookup_claim(p_token TEXT)
RETURNS public.token_claim_history
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
  SELECT token, user_id, valid_from, valid_until, approx_lat, approx_lon,
         range_type, accuracy_m, created_at
  FROM public.token_claim_history
  WHERE token = lower(p_token) AND valid_until > NOW() - INTERVAL '2 minutes'
  ORDER BY valid_from DESC LIMIT 1;
$$;

-- record_sighting + correlate_encounter now resolve the observed token against
-- HISTORY, so a sighting buffered across a rotation/release still correlates.
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

  -- History-aware token check (survives rotation/release within grace) (#5).
  IF NOT EXISTS (
    SELECT 1 FROM public.token_claim_history h
    WHERE h.token = lower(p_observed_token) AND h.user_id <> v_uid
      AND h.valid_until > v_now - INTERVAL '2 minutes'
  ) THEN RAISE EXCEPTION 'Unknown or expired beacon token' USING ERRCODE='22023'; END IF;

  INSERT INTO public.sightings AS s (observer_user_id, observed_token, rssi, observed_at, observer_lat, observer_lon, range_type, observer_accuracy_m)
  VALUES (v_uid, lower(p_observed_token), p_rssi, p_observed_at, p_lat, p_lon, v_range, p_accuracy)
  ON CONFLICT (observer_user_id, observed_token) DO UPDATE
    SET observed_at = p_observed_at,
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

-- correlate_encounter: resolve the claim from HISTORY (same body as 0027).
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
  v_now TIMESTAMPTZ := NOW();
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
  v_user_a := LEAST(v_uid, v_claim.user_id); v_user_b := GREATEST(v_uid, v_claim.user_id);
  PERFORM pg_advisory_xact_lock(hashtextextended(v_user_a::TEXT || v_user_b::TEXT, 0));
  PERFORM public.bump_encounter_pair(v_user_a, v_user_b, v_band);

  SELECT id INTO v_enc_id FROM public.encounters WHERE user_a = v_user_a AND user_b = v_user_b AND status = 'active' ORDER BY encounter_time DESC LIMIT 1 FOR UPDATE;
  IF v_enc_id IS NULL THEN
    INSERT INTO public.encounters (user_a,user_b,neighborhood,encounter_time,last_seen_at,range_type,confidence,status)
    VALUES (v_user_a,v_user_b,'Near you',v_now,v_now,v_band,0.8,'active') RETURNING id INTO v_enc_id; v_new := TRUE;
  ELSE
    UPDATE public.encounters e SET last_seen_at = v_now,
      range_type = CASE WHEN e.range_type::TEXT LIKE 'feet_%' AND v_band::TEXT LIKE 'feet_%' AND public.range_band_rank(v_band) < public.range_band_rank(e.range_type) THEN v_band ELSE e.range_type END
    WHERE e.id = v_enc_id;
  END IF;
  encounter_id := v_enc_id; other_user_id := v_claim.user_id; created_new := v_new; RETURN NEXT;
END;
$$;
