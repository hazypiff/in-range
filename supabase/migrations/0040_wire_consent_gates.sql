-- 0040_wire_consent_gates.sql
--
-- Makes app_settings.enforce_consent actually mean something.
--
-- 0039 added consent records and require_consent(), but NOTHING CALLED IT.
-- Flipping the flag would have been a silent no-op -- the worst kind of
-- compliance control, because it reads as enforced on a dashboard while
-- collecting exactly as much data as before.
--
-- This inserts one require_consent() call into each collection path, directly
-- after the existing authentication and discoverability gates:
--
--   claim_token          -> ble_proximity      (broadcasting a beacon token)
--   record_sighting      -> ble_proximity      (observing someone else's)
--   record_location_ping -> precise_location   (GPS upload)
--   upsert_my_profile    -> sensitive_profile  (gender / sexual orientation)
--
-- Still a no-op until enforce_consent = 1, which must stay 0 until the consent
-- UI is live on real devices -- flipping it early locks out every existing
-- client. T18 asserts both halves: silent when off, enforcing when on.
--
-- The function bodies below are the CURRENT production definitions with one
-- line added each. They were generated from pg_get_functiondef() rather than
-- retyped, so nothing else in these hot-path functions drifted.

BEGIN;


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
$function$;


CREATE OR REPLACE FUNCTION public.record_location_ping(p_lat double precision, p_lon double precision, p_range range_type DEFAULT 'miles_10'::range_type, p_neighborhood text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_id BIGINT;
  v_hood TEXT;
  v_last RECORD;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '28000';
  END IF;
  IF NOT public.current_user_can_discover() THEN
    RAISE EXCEPTION 'Complete age and photo verification before using Locals'
      USING ERRCODE = '42501';
  END IF;
  -- Consent gate (0040). No-op unless app_settings.enforce_consent = 1.
  PERFORM public.require_consent(v_uid, 'precise_location');
  IF p_lat IS NULL OR p_lon IS NULL
     OR p_lat NOT BETWEEN -90 AND 90 OR p_lon NOT BETWEEN -180 AND 180 THEN
    RAISE EXCEPTION 'Invalid coordinates' USING ERRCODE = '22023';
  END IF;
  IF p_range::TEXT NOT LIKE 'miles_%' THEN
    RAISE EXCEPTION 'Locals requires a miles range' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = v_uid AND NOT p.location_history_enabled
  ) THEN
    RAISE EXCEPTION 'Location history is disabled' USING ERRCODE = '42501';
  END IF;

  v_hood := left(COALESCE(NULLIF(trim(p_neighborhood), ''), 'Nearby'), 80);
  -- Never accept the old client fallback "Area 12.34, -56.78" as a label.
  IF v_hood ~* '^-?area[[:space:]]+-?[0-9]+\.[0-9]+.*[,-][[:space:]]*-?[0-9]+\.[0-9]+' THEN
    v_hood := 'Nearby';
  END IF;

  SELECT lp.id, lp.created_at INTO v_last
  FROM public.location_pings lp
  WHERE lp.user_id = v_uid
  ORDER BY lp.created_at DESC
  LIMIT 1;

  -- Stream + timer callbacks can overlap. Treat a sub-30-second duplicate as
  -- the same ping instead of growing the table or racing correlation.
  IF v_last.id IS NOT NULL AND v_last.created_at > NOW() - INTERVAL '30 seconds' THEN
    RETURN v_last.id;
  END IF;

  INSERT INTO public.location_pings (user_id, geo, range_type, neighborhood)
  VALUES (
    v_uid,
    ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography,
    p_range,
    v_hood
  ) RETURNING id INTO v_id;

  UPDATE public.profiles
  SET last_active_at = NOW(), neighborhood = v_hood
  WHERE id = v_uid;

  PERFORM public.correlate_miles_encounters(p_lat, p_lon, p_range, v_hood);
  RETURN v_id;
END;
$function$;


CREATE OR REPLACE FUNCTION public.upsert_my_profile(p_display_name text, p_bio text DEFAULT NULL::text, p_dob date DEFAULT NULL::date, p_gender text DEFAULT NULL::text, p_sexual_preference text DEFAULT NULL::text, p_interests text[] DEFAULT NULL::text[], p_photo_urls text[] DEFAULT NULL::text[], p_beacon_default_range range_type DEFAULT 'miles_10'::range_type)
 RETURNS profiles
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_row public.profiles;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '28000';
  END IF;
  -- Consent gate (0040): only when sensitive fields are actually being
  -- written. Clearing them must never require consent to clear.
  IF p_gender IS NOT NULL OR p_sexual_preference IS NOT NULL THEN
    PERFORM public.require_consent(v_uid, 'sensitive_profile');
  END IF;
  IF p_display_name IS NULL OR length(trim(p_display_name)) NOT BETWEEN 1 AND 80 THEN
    RAISE EXCEPTION 'Display name must be 1..80 characters' USING ERRCODE = '22023';
  END IF;
  IF p_display_name ~ '[[:cntrl:]]' THEN
    RAISE EXCEPTION 'Display name contains invalid characters' USING ERRCODE = '22023';
  END IF;
  IF p_dob IS NULL THEN
    RAISE EXCEPTION 'Date of birth required' USING ERRCODE = '22023';
  END IF;
  IF p_dob < DATE '1900-01-01' OR p_dob > CURRENT_DATE - INTERVAL '18 years' THEN
    RAISE EXCEPTION 'Must be 18 or older' USING ERRCODE = '22023';
  END IF;
  IF p_bio IS NOT NULL AND char_length(p_bio) > 500 THEN
    RAISE EXCEPTION 'Bio max 500 characters' USING ERRCODE = '22023';
  END IF;
  IF p_interests IS NOT NULL AND COALESCE(array_length(p_interests, 1), 0) > 20 THEN
    RAISE EXCEPTION 'Max 20 interests' USING ERRCODE = '22023';
  END IF;
  IF p_interests IS NOT NULL AND EXISTS (
    SELECT 1 FROM unnest(p_interests) i
    WHERE length(trim(i)) NOT BETWEEN 1 AND 50
  ) THEN
    RAISE EXCEPTION 'Interest must be 1..50 characters' USING ERRCODE = '22023';
  END IF;
  IF p_photo_urls IS NOT NULL AND COALESCE(array_length(p_photo_urls, 1), 0) > 6 THEN
    RAISE EXCEPTION 'Max 6 photos' USING ERRCODE = '22023';
  END IF;
  IF p_photo_urls IS NOT NULL AND EXISTS (
    SELECT 1 FROM unnest(p_photo_urls) photo_path
    WHERE split_part(photo_path, '/', 1) <> v_uid::TEXT
       OR photo_path LIKE 'http://%'
       OR photo_path LIKE 'https://%'
       OR photo_path LIKE '/%'
       OR photo_path LIKE '%\\%'
  ) THEN
    RAISE EXCEPTION 'Photo paths must be in your storage folder' USING ERRCODE = '22023';
  END IF;
  IF p_photo_urls IS NOT NULL AND EXISTS (
    SELECT 1 FROM unnest(p_photo_urls) photo_path
    WHERE NOT EXISTS (
      SELECT 1 FROM storage.objects o
      WHERE o.bucket_id = 'profile_photos' AND o.name = photo_path
    )
  ) THEN
    RAISE EXCEPTION 'Profile photo object not found' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.profiles (
    id, display_name, bio, dob, age_verified, gender, sexual_preference,
    interests, photo_urls, beacon_default_range, updated_at
  )
  VALUES (
    v_uid, trim(p_display_name), NULLIF(trim(p_bio), ''), p_dob, TRUE,
    p_gender, p_sexual_preference, p_interests, p_photo_urls,
    p_beacon_default_range, NOW()
  )
  ON CONFLICT (id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    bio = EXCLUDED.bio,
    dob = EXCLUDED.dob,
    age_verified = TRUE,
    gender = EXCLUDED.gender,
    sexual_preference = EXCLUDED.sexual_preference,
    interests = EXCLUDED.interests,
    photo_urls = COALESCE(EXCLUDED.photo_urls, public.profiles.photo_urls),
    beacon_default_range = EXCLUDED.beacon_default_range,
    updated_at = NOW()
  RETURNING * INTO v_row;

  -- Verification follows the currently referenced immutable object path, not a
  -- client-provided boolean.
  UPDATE public.profiles p
  SET is_photo_verified = EXISTS (
        SELECT 1 FROM public.photo_verifications pv
        WHERE pv.user_id = v_uid
          AND pv.state = 'approved'
          AND pv.photo_path = ANY(COALESCE(p.photo_urls, ARRAY[]::TEXT[]))
      ),
      photo_verification_status = CASE
        WHEN EXISTS (
          SELECT 1 FROM public.photo_verifications pv
          WHERE pv.user_id = v_uid
            AND pv.state = 'approved'
            AND pv.photo_path = ANY(COALESCE(p.photo_urls, ARRAY[]::TEXT[]))
        ) THEN 'verified'
        ELSE 'pending'
      END
  WHERE p.id = v_uid
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$function$;


COMMIT;
