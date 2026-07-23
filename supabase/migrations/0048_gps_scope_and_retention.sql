-- 0048_gps_scope_and_retention.sql
--
-- Closes three findings from the 0047 adversarial re-audit:
--   1. GPS retention broke the app's own "deleted after 24 hours" promise:
--      sightings (observer_lat/lon, NOT NULL) and token_claim_history
--      (approx_lat/lon) were swept at 48h. Both are spent within the ~30-min
--      correlation window, so their retention drops to 24h; the existing
--      NOT has_legal_hold predicates still preserve held users' evidence.
--   2. Withdrawing precise_location did NOT stop GPS collection through Beacon:
--      claim_token/record_sighting gated only ble_proximity. Both now deny a
--      precise_location-withdrawn caller, and record_sighting also refuses to
--      generate evidence about an observed user who withdrew precise_location.
--   3. The miles-correlate Edge patch calls is_discoverable_user() as
--      service_role, which lacked EXECUTE -> it would fail closed on deploy.
--
-- Plus: get_locals_feed / correlate_miles_encounters caller gates now use
-- my_consent_satisfied() so enforce_consent=1 also blocks a never-consented
-- caller holding a stale pre-rollout ping.
--
-- All function bodies are the verbatim current definitions (0040/0046/0047)
-- with only the injections above; no unrelated logic changed.

BEGIN;

-- ============================ FINDING 3 =============================
-- Internal service-role Edge function (miles-correlate) must be able to call it.
GRANT EXECUTE ON FUNCTION public.is_discoverable_user(UUID) TO service_role;

-- ============================ FINDING 2 =============================
CREATE OR REPLACE FUNCTION public.claim_token(p_token text, p_valid_until timestamp with time zone, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_range range_type DEFAULT 'miles_10'::range_type, p_accuracy double precision DEFAULT NULL::double precision)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_now TIMESTAMPTZ := clock_timestamp();
  v_last TIMESTAMPTZ;
  v_in_batch BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;
  IF NOT public.current_user_can_discover() THEN
    RAISE EXCEPTION 'Complete age and photo verification before using Beacon' USING ERRCODE='42501'; END IF;
  -- Consent gate (0040). No-op unless app_settings.enforce_consent = 1.
  PERFORM public.require_consent(v_uid, 'ble_proximity');
  -- 0048: the consent UI scopes GPS to precise_location ("deleted after 24h").
  -- Beacon mandatorily uploads coordinates, so a user who withdrew precise
  -- location must not keep feeding GPS through it, even while ble_proximity
  -- is still granted. Explicit withdrawal denies regardless of enforce_consent.
  IF public.consent_withdrawn(v_uid, 'precise_location') THEN
    RAISE EXCEPTION 'Location sharing was turned off' USING ERRCODE='42501'; END IF;
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

  -- #6 step 2: the token must be one the server issued to THIS user. Consume it
  -- (observability); enforce membership only when the flag is on so the
  -- batch-aware client can roll out first.
  UPDATE public.beacon_token_batch b SET consumed_at = COALESCE(b.consumed_at, v_now)
  WHERE b.token = lower(p_token) AND b.user_id = v_uid
  RETURNING TRUE INTO v_in_batch;
  IF NOT COALESCE(v_in_batch, FALSE)
     AND COALESCE((SELECT value_num FROM public.app_settings WHERE key='enforce_batch_tokens'), 0) >= 1 THEN
    RAISE EXCEPTION 'Beacon token was not issued to this account' USING ERRCODE='22023';
  END IF;

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

  INSERT INTO public.token_claim_history
    (token, user_id, valid_from, valid_until, approx_lat, approx_lon, range_type, accuracy_m, created_at)
  VALUES (lower(p_token), v_uid, v_now, p_valid_until, p_lat, p_lon, p_range, p_accuracy, v_now)
  ON CONFLICT (token) DO UPDATE SET valid_until = EXCLUDED.valid_until;
END;
$function$;


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


-- ============================ FINDING 1 =============================
CREATE OR REPLACE FUNCTION public.cleanup_ephemeral_data()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_holds BOOLEAN := EXISTS (
    SELECT 1 FROM public.legal_holds
     WHERE released_at IS NULL
       AND (expires_at IS NULL OR expires_at > NOW()));
BEGIN
  IF v_holds THEN
    DELETE FROM public.token_claims tc
     WHERE tc.valid_until < NOW() - INTERVAL '30 minutes'
       AND NOT public.has_legal_hold(tc.user_id);

    DELETE FROM public.sightings s
     WHERE s.observed_at < NOW() - INTERVAL '24 hours'
       AND NOT public.has_legal_hold(s.observer_user_id)
       AND NOT EXISTS (
         SELECT 1 FROM public.token_claims tc
          WHERE tc.token = s.observed_token
            AND public.has_legal_hold(tc.user_id));

    DELETE FROM public.location_pings lp
     WHERE lp.created_at < NOW() - INTERVAL '24 hours'
       AND NOT public.has_legal_hold(lp.user_id);

    -- 0047: token_claim_history is ephemeral too; it was never pruned.
    DELETE FROM public.token_claim_history h
     WHERE h.valid_until < NOW() - INTERVAL '24 hours'
       AND NOT public.has_legal_hold(h.user_id);
  ELSE
    DELETE FROM public.token_claims
     WHERE valid_until < NOW() - INTERVAL '30 minutes';

    DELETE FROM public.sightings
     WHERE observed_at < NOW() - INTERVAL '24 hours';

    DELETE FROM public.location_pings
     WHERE created_at < NOW() - INTERVAL '24 hours';

    DELETE FROM public.token_claim_history
     WHERE valid_until < NOW() - INTERVAL '24 hours';
  END IF;

  -- Recover a worker that died after atomically claiming a batch.
  UPDATE public.notification_outbox
     SET status = CASE WHEN attempts < 5 THEN 'pending' ELSE 'failed' END,
         last_error = 'stale_processing_recovered',
         processing_at = NULL
   WHERE status = 'processing'
     AND processing_at < NOW() - INTERVAL '10 minutes';

  DELETE FROM public.notification_outbox
   WHERE (status IN ('sent', 'skipped') AND created_at < NOW() - INTERVAL '30 days')
      OR (status = 'failed' AND created_at < NOW() - INTERVAL '7 days');

  DELETE FROM public.ai_events WHERE created_at < NOW() - INTERVAL '90 days';
  DELETE FROM public.ai_runs   WHERE created_at < NOW() - INTERVAL '90 days';

  -- Evidence snapshots: 1 year, unless the subject is still held or the
  -- snapshot backs an unexpired (or unfiled) CyberTipline obligation.
  DELETE FROM public.report_evidence e
   WHERE e.captured_at < NOW() - INTERVAL '1 year'
     AND (e.subject_user IS NULL OR NOT public.has_legal_hold(e.subject_user))
     AND NOT EXISTS (
       SELECT 1 FROM public.cybertipline_queue q
        WHERE q.report_id = e.report_id
          AND (q.preserve_until IS NULL OR q.preserve_until > NOW()));
END;
$$;


-- ================= FINDING 4 (caller consent gates) =================
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
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_own RECORD;
  v_peer RECORD;
  v_user_a UUID;
  v_user_b UUID;
  v_enc_id BIGINT;
  v_radius DOUBLE PRECISION;
  v_distance DOUBLE PRECISION;
  v_new BOOLEAN;
BEGIN
  IF v_uid IS NULL OR NOT public.current_user_can_discover() THEN
    RETURN;
  END IF;
  -- 0048: caller must positively satisfy precise_location consent. This denies
  -- explicit withdrawal always, and (once enforce_consent=1) a never-consented
  -- caller who still holds a fresh pre-rollout ping.
  IF NOT public.my_consent_satisfied('precise_location') THEN
    RETURN;
  END IF;

  SELECT lp.id, lp.geo, lp.range_type, lp.neighborhood, lp.created_at
  INTO v_own
  FROM public.location_pings lp
  WHERE lp.user_id = v_uid
    AND lp.created_at > NOW() - INTERVAL '5 minutes'
  ORDER BY lp.created_at DESC
  LIMIT 1;
  IF NOT FOUND OR v_own.range_type::TEXT NOT LIKE 'miles_%' THEN
    RETURN;
  END IF;

  v_radius := public.range_radius_meters(v_own.range_type);
  FOR v_peer IN
    SELECT DISTINCT ON (lp.user_id)
      lp.user_id,
      lp.geo,
      lp.range_type,
      lp.neighborhood,
      lp.created_at,
      ST_Distance(lp.geo, v_own.geo) AS distance_m
    FROM public.location_pings lp
    WHERE lp.user_id <> v_uid
      AND lp.created_at > NOW() - make_interval(
        mins => LEAST(1440, public.range_time_window_minutes(v_own.range_type))
      )
      AND ST_DWithin(
        lp.geo,
        v_own.geo,
        LEAST(v_radius, public.range_radius_meters(lp.range_type))
      )
      AND public.is_discoverable_user(lp.user_id)
      AND NOT public.consent_withdrawn(lp.user_id, 'precise_location')
      AND NOT public.is_blocked_pair(v_uid, lp.user_id)
      AND public.preferences_compatible(v_uid, lp.user_id)
    ORDER BY lp.user_id, lp.created_at DESC
    LIMIT 100
  LOOP
    v_distance := v_peer.distance_m;
    v_user_a := LEAST(v_uid, v_peer.user_id);
    v_user_b := GREATEST(v_uid, v_peer.user_id);
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
        v_user_a, v_user_b,
        COALESCE(v_own.neighborhood, v_peer.neighborhood, 'Nearby'),
        NOW(), NOW(), v_own.range_type,
        LEAST(1.0, GREATEST(0.4, 1.0 - (v_distance / GREATEST(v_radius, 1)))),
        'active'
      ) RETURNING id INTO v_enc_id;
      v_new := TRUE;
    ELSE
      UPDATE public.encounters
      SET last_seen_at = NOW(),
          neighborhood = COALESCE(v_own.neighborhood, v_peer.neighborhood, neighborhood),
          confidence = LEAST(1.0, GREATEST(0.4, 1.0 - (v_distance / GREATEST(v_radius, 1))))
      WHERE id = v_enc_id;
      v_new := FALSE;
    END IF;

    encounter_id := v_enc_id;
    other_user_id := v_peer.user_id;
    created_new := v_new;
    RETURN NEXT;
  END LOOP;
END;
$$;


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
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_own RECORD;
  v_radius DOUBLE PRECISION;
  v_window INT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '28000';
  END IF;
  IF NOT public.current_user_can_discover() THEN
    RAISE EXCEPTION 'Account is not discoverable' USING ERRCODE = '42501';
  END IF;
  -- 0048: caller must positively satisfy precise_location consent (denies
  -- explicit withdrawal always; denies never-consented once enforce_consent=1).
  IF NOT public.my_consent_satisfied('precise_location') THEN
    RAISE EXCEPTION 'Account is not discoverable' USING ERRCODE = '42501';
  END IF;

  -- p_lat/p_lon remain in the stable API signature, but are deliberately not
  -- trusted. The origin is the caller's latest server-recorded ping.
  SELECT lp.geo, lp.range_type, lp.created_at INTO v_own
  FROM public.location_pings lp
  WHERE lp.user_id = v_uid
    AND lp.created_at > NOW() - INTERVAL '5 minutes'
  ORDER BY lp.created_at DESC
  LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Record a fresh location ping first' USING ERRCODE = '55000';
  END IF;

  v_radius := public.range_radius_meters(v_own.range_type);
  v_window := LEAST(1440, public.range_time_window_minutes(v_own.range_type));

  RETURN QUERY
  SELECT DISTINCT ON (lp.user_id)
    lp.user_id,
    -- 250m bands and 15-minute timestamps reduce trilateration/online-status
    -- precision while preserving a useful Locals UI.
    (CEIL(ST_Distance(lp.geo, v_own.geo) / 250.0) * 250.0)::DOUBLE PRECISION,
    lp.neighborhood,
    pr.photo_urls,
    TRUE,
    public.has_active_boost(lp.user_id),
    date_bin(INTERVAL '15 minutes', lp.created_at, TIMESTAMPTZ '2001-01-01 00:00:00+00')
  FROM public.location_pings lp
  JOIN public.profiles pr ON pr.id = lp.user_id
  WHERE lp.user_id <> v_uid
    AND lp.created_at > NOW() - make_interval(mins => v_window)
    AND ST_DWithin(
      lp.geo,
      v_own.geo,
      LEAST(v_radius, public.range_radius_meters(lp.range_type))
    )
    AND public.is_discoverable_user(lp.user_id)
    AND NOT public.consent_withdrawn(lp.user_id, 'precise_location')
    AND NOT public.is_blocked_pair(v_uid, lp.user_id)
    AND public.preferences_compatible(v_uid, lp.user_id)
    AND EXISTS (
      SELECT 1 FROM public.encounters revealed
      WHERE revealed.status = 'active'
        AND revealed.encounter_time <= NOW() - make_interval(
          secs => (public.encounter_reveal_delay_hours() * 3600)::DOUBLE PRECISION
        )
        AND ((revealed.user_a = v_uid AND revealed.user_b = lp.user_id)
          OR (revealed.user_b = v_uid AND revealed.user_a = lp.user_id))
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.encounters e
      JOIN public.encounter_actions ea ON ea.encounter_id = e.id
      WHERE ea.user_id = v_uid
        AND ((e.user_a = v_uid AND e.user_b = lp.user_id)
          OR (e.user_b = v_uid AND e.user_a = lp.user_id))
    )
  ORDER BY lp.user_id, public.has_active_boost(lp.user_id) DESC, lp.created_at DESC
  LIMIT LEAST(100, GREATEST(1, COALESCE(p_limit, 50)));
END;
$$;


COMMIT;
