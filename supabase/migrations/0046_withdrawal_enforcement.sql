-- 0046_withdrawal_enforcement.sql
--
-- The 2026-07-22 adversarial replay found that 0045 recorded and cleaned up a
-- withdrawal but left FOUR ways to keep processing after it:
--   1. BLE: withdrawal deleted token_claims but token_claim_history stayed
--      resolvable, so an observer could still record sightings OF a withdrawn
--      user (and, under a hold, form a fresh encounter).
--   2. Photos: the Storage INSERT policy and the photo-submission / profile-
--      path RPCs had no consent gate, so a stale client could resume uploading
--      and verifying while photo consent was withdrawn.
--   3. Hold-deferred photo erasure never resumed: nothing re-enqueued the
--      objects after a hold was released.
--   Plus: preserved-under-hold location evidence was still matchable by live
--   correlation, consent_withdrawn() was an authenticated cross-user oracle,
--   and retiring background_location left two active grants with no way to
--   withdraw them.
--
-- This migration makes withdrawal enforceable at every write path, adds a
-- reconciler for deferred cleanup after hold release, closes the oracle, and
-- retires background_location. enforcement flags stay 0; an explicit
-- withdrawal is honored regardless of them (0045 doctrine).

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Close the cross-user oracle 0045 reopened. consent_withdrawn(uid,purpose)
--    takes an arbitrary uid, so authenticated must not call it directly (same
--    class 0042 closed for has_consent/require_consent). SECURITY DEFINER
--    callers (is_discoverable_user, require_consent, the correlation funcs)
--    run as the owner and are unaffected. A self-scoped wrapper covers the one
--    place an RLS policy needs the check as the calling user.
-- ---------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.consent_withdrawn(UUID, TEXT) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.consent_withdrawn(UUID, TEXT) TO service_role;

CREATE OR REPLACE FUNCTION public.my_consent_withdrawn(p_purpose TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT public.consent_withdrawn(auth.uid(), p_purpose);
$$;

REVOKE ALL ON FUNCTION public.my_consent_withdrawn(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_consent_withdrawn(TEXT) TO authenticated, service_role;

COMMENT ON FUNCTION public.my_consent_withdrawn IS
  'Self-scoped withdrawal check (auth.uid() only) for RLS policies. No arbitrary-uid oracle.';

-- ---------------------------------------------------------------------------
-- 2. withdraw_consent v4: BLE withdrawal also clears token_claim_history, so
--    no preserved token remains resolvable (deferred under a hold, as before).
--    Everything else is identical to 0045.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.withdraw_consent(p_purpose TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid  UUID := auth.uid();
  v_hit  BOOLEAN;
  v_held BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  UPDATE public.consent_records
     SET withdrawn_at = NOW()
   WHERE user_id = v_uid AND purpose = p_purpose AND withdrawn_at IS NULL
  RETURNING TRUE INTO v_hit;

  IF NOT COALESCE(v_hit, FALSE) THEN
    RETURN FALSE;
  END IF;

  v_held := public.has_legal_hold(v_uid);

  IF p_purpose IN ('precise_location', 'background_location') AND NOT v_held THEN
    DELETE FROM public.location_pings WHERE user_id = v_uid;
  END IF;

  IF p_purpose = 'ble_proximity' AND NOT v_held THEN
    DELETE FROM public.sightings s
     WHERE s.observed_token IN
           (SELECT token FROM public.token_claims       WHERE user_id = v_uid
            UNION
            SELECT token FROM public.token_claim_history WHERE user_id = v_uid);
    DELETE FROM public.sightings          WHERE observer_user_id = v_uid;
    DELETE FROM public.token_claims        WHERE user_id = v_uid;
    DELETE FROM public.token_claim_history WHERE user_id = v_uid;
  END IF;

  IF p_purpose = 'photo_processing' THEN
    UPDATE public.profiles
       SET photo_urls = ARRAY[]::TEXT[],
           is_photo_verified = FALSE,
           photo_verification_status = 'pending'
     WHERE id = v_uid;
    UPDATE public.photo_verifications
       SET state = 'rejected',
           review_notes = COALESCE(review_notes || '; ', '')
                          || 'cancelled: photo_processing consent withdrawn',
           decided_at = NOW()
     WHERE user_id = v_uid
       AND state IN ('pending_upload', 'ai_review', 'ai_passed', 'manual_review');
    IF NOT v_held THEN
      INSERT INTO public.storage_deletion_queue (user_id, bucket_id, object_name)
      SELECT v_uid, o.bucket_id, o.name
        FROM storage.objects o
       WHERE o.bucket_id IN ('profile_photos', 'verified_photos')
         AND (storage.foldername(o.name))[1] = v_uid::TEXT
      ON CONFLICT (bucket_id, object_name) DO NOTHING;
    END IF;
  END IF;

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.withdraw_consent(TEXT) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.withdraw_consent(TEXT) FROM PUBLIC, anon;

-- ---------------------------------------------------------------------------
-- 3. Storage INSERT gate: no profile-photo upload while photo consent is
--    withdrawn (ownership check alone was insufficient).
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Users upload own profile photos" ON storage.objects;
CREATE POLICY "Users upload own profile photos"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'profile_photos'
    AND (storage.foldername(name))[1] = auth.uid()::TEXT
    AND NOT public.my_consent_withdrawn('photo_processing')
  );

-- ---------------------------------------------------------------------------
-- 4. reconcile_withdrawn_consent(): finishes deferred cleanup for users whose
--    hold has since been released, and mops up any lingering evidence for
--    withdrawn-and-unheld users. Idempotent; service-role only; wired into
--    run_maintenance below.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reconcile_withdrawn_consent()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid UUID;
  v_n   INT := 0;
BEGIN
  FOR v_uid IN
    SELECT DISTINCT c.user_id
      FROM public.consent_records c
     WHERE c.withdrawn_at IS NOT NULL
       AND NOT public.has_legal_hold(c.user_id)
       AND NOT EXISTS (
         SELECT 1 FROM public.consent_records a
          WHERE a.user_id = c.user_id AND a.purpose = c.purpose
            AND a.withdrawn_at IS NULL)
  LOOP
    IF public.consent_withdrawn(v_uid, 'photo_processing') THEN
      UPDATE public.profiles
         SET photo_urls = ARRAY[]::TEXT[],
             is_photo_verified = FALSE,
             photo_verification_status = 'pending'
       WHERE id = v_uid
         AND (COALESCE(array_length(photo_urls, 1), 0) > 0 OR is_photo_verified);
      INSERT INTO public.storage_deletion_queue (user_id, bucket_id, object_name)
      SELECT v_uid, o.bucket_id, o.name
        FROM storage.objects o
       WHERE o.bucket_id IN ('profile_photos', 'verified_photos')
         AND (storage.foldername(o.name))[1] = v_uid::TEXT
      ON CONFLICT (bucket_id, object_name) DO NOTHING;
    END IF;

    IF public.consent_withdrawn(v_uid, 'ble_proximity') THEN
      DELETE FROM public.sightings s
       WHERE s.observed_token IN
             (SELECT token FROM public.token_claims       WHERE user_id = v_uid
              UNION
              SELECT token FROM public.token_claim_history WHERE user_id = v_uid);
      DELETE FROM public.sightings          WHERE observer_user_id = v_uid;
      DELETE FROM public.token_claims        WHERE user_id = v_uid;
      DELETE FROM public.token_claim_history WHERE user_id = v_uid;
    END IF;

    -- Only precise_location gates the GPS upload; background_location alone
    -- (a user who kept foreground location) must not wipe their pings.
    IF public.consent_withdrawn(v_uid, 'precise_location') THEN
      DELETE FROM public.location_pings WHERE user_id = v_uid;
    END IF;

    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$$;

REVOKE ALL ON FUNCTION public.reconcile_withdrawn_consent() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reconcile_withdrawn_consent() TO service_role;

-- run_maintenance v-next: reconcile deferred withdrawals each cycle.
CREATE OR REPLACE FUNCTION public.run_maintenance()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_expired_feet INT;
  v_expired_matches INT;
  v_revealed_alerts INT;
  v_expiring_alerts INT;
  v_correlated INT;
  v_purged INT;
  v_reconciled INT;
BEGIN
  PERFORM public.cleanup_ephemeral_data();
  v_reconciled      := public.reconcile_withdrawn_consent();
  v_expired_feet    := public.expire_feet_encounters();
  v_expired_matches := public.expire_idle_matches();
  v_revealed_alerts := public.queue_revealed_encounter_alerts();
  v_expiring_alerts := public.queue_expiring_encounter_alerts();
  v_correlated      := public.batch_correlate_recent_pings(45);
  v_purged          := public.purge_deleted_accounts();
  RETURN jsonb_build_object(
    'expired_feet', v_expired_feet,
    'expired_matches', v_expired_matches,
    'revealed_alerts', v_revealed_alerts,
    'expiring_alerts', v_expiring_alerts,
    'new_miles_encounters', v_correlated,
    'purged_accounts', v_purged,
    'reconciled_withdrawals', v_reconciled,
    'ran_at', NOW()
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Retire background_location: the toggle was removed from the consent UI
--    (no shipped feature collects it), which also removed the withdrawal
--    route for anyone still holding an active grant. Withdraw them now so no
--    grant is left dangling. Not a ping wipe: these users keep precise_location.
-- ---------------------------------------------------------------------------
UPDATE public.consent_records
   SET withdrawn_at = NOW()
 WHERE purpose = 'background_location' AND withdrawn_at IS NULL;

-- ==== record_sighting v-next: gate the OBSERVED user's BLE withdrawal ====
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
  -- 0046: an observed user who withdrew BLE consent must not generate new
  -- evidence, even from a token preserved in history under a legal hold.
  IF public.consent_withdrawn(v_observed_uid, 'ble_proximity') THEN RAISE EXCEPTION 'Unknown or expired beacon token' USING ERRCODE='22023'; END IF;

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

-- ==== upsert_my_profile v-next: gate photo-path writes ====
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
  -- 0046: writing photo paths IS photo processing; clearing them is not.
  IF p_photo_urls IS NOT NULL AND array_length(p_photo_urls, 1) > 0 THEN
    PERFORM public.require_consent(v_uid, 'photo_processing');
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

-- ==== submit_photo_for_verification v-next: gate photo consent ====
CREATE OR REPLACE FUNCTION public.submit_photo_for_verification(
  p_photo_path TEXT,
  p_slot_index SMALLINT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_id UUID;
  v_object RECORD;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '28000';
  END IF;
  -- 0046: no photo storage/verification while photo consent is withdrawn.
  PERFORM public.require_consent(v_uid, 'photo_processing');
  IF p_slot_index IS NULL OR p_slot_index NOT BETWEEN 0 AND 5 THEN
    RAISE EXCEPTION 'slot_index must be 0..5' USING ERRCODE = '22023';
  END IF;
  IF p_photo_path IS NULL
     OR split_part(p_photo_path, '/', 1) <> v_uid::TEXT
     OR p_photo_path LIKE 'http%'
     OR length(p_photo_path) > 500 THEN
    RAISE EXCEPTION 'Invalid photo path' USING ERRCODE = '22023';
  END IF;
  IF (
    SELECT count(*) FROM public.photo_verifications pv
    WHERE pv.user_id = v_uid AND pv.created_at > NOW() - INTERVAL '1 hour'
  ) >= 12 THEN
    RAISE EXCEPTION 'Photo review rate limit' USING ERRCODE = '54000';
  END IF;

  SELECT o.id, o.updated_at INTO v_object
  FROM storage.objects o
  WHERE o.bucket_id = 'profile_photos' AND o.name = p_photo_path;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Uploaded photo not found' USING ERRCODE = 'P0002';
  END IF;

  -- A new submission supersedes unfinished reviews for the same slot, without
  -- mutating any previously approved immutable photo.
  UPDATE public.photo_verifications
  SET state = 'rejected',
      review_notes = 'Superseded by a newer upload',
      decided_at = NOW(), updated_at = NOW()
  WHERE user_id = v_uid AND slot_index = p_slot_index
    AND state IN ('pending_upload', 'ai_review', 'ai_passed', 'ai_failed', 'manual_review');

  INSERT INTO public.photo_verifications (
    user_id, photo_path, slot_index, state,
    storage_object_id, storage_object_updated_at
  ) VALUES (
    v_uid, p_photo_path, p_slot_index, 'ai_review',
    v_object.id, v_object.updated_at
  ) RETURNING id INTO v_id;

  UPDATE public.profiles p
  SET photo_urls = (
        SELECT array_agg(x.path ORDER BY x.ord)
        FROM (
          SELECT ord,
            CASE WHEN ord - 1 = p_slot_index
              THEN p_photo_path
              ELSE p.photo_urls[ord]
            END AS path
          FROM generate_series(
            1,
            GREATEST(COALESCE(array_length(p.photo_urls, 1), 0), p_slot_index + 1)
          ) ord
        ) x
        WHERE x.path IS NOT NULL AND x.path <> ''
      ),
      is_photo_verified = EXISTS (
        SELECT 1 FROM public.photo_verifications approved
        WHERE approved.user_id = v_uid AND approved.state = 'approved'
          AND approved.photo_path <> p_photo_path
          AND approved.photo_path = ANY(COALESCE(p.photo_urls, ARRAY[]::TEXT[]))
      ),
      photo_verification_status = 'pending',
      updated_at = NOW()
  WHERE p.id = v_uid;

  RETURN v_id;
END;
$$;

-- ==== correlate_miles_encounters v-next: exclude withdrawn-location peers ====
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

-- ==== get_locals_feed v-next: exclude withdrawn-location peers ====
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

-- ==== batch_correlate_recent_pings v-next: exclude withdrawn-location ====
CREATE OR REPLACE FUNCTION public.batch_correlate_recent_pings(
  p_lookback_minutes INT DEFAULT 30
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_lookback INT := LEAST(120, GREATEST(1, COALESCE(p_lookback_minutes, 30)));
  v_source RECORD;
  v_peer RECORD;
  v_enc_id BIGINT;
  v_count INT := 0;
  v_radius DOUBLE PRECISION;
BEGIN
  FOR v_source IN
    SELECT DISTINCT ON (lp.user_id)
      lp.user_id, lp.geo, lp.range_type, lp.neighborhood, lp.created_at
    FROM public.location_pings lp
    WHERE lp.created_at > NOW() - make_interval(mins => v_lookback)
      AND lp.range_type::TEXT LIKE 'miles_%'
      AND public.is_discoverable_user(lp.user_id)
      AND NOT public.consent_withdrawn(lp.user_id, 'precise_location')
    ORDER BY lp.user_id, lp.created_at DESC
  LOOP
    v_radius := public.range_radius_meters(v_source.range_type);
    FOR v_peer IN
      SELECT DISTINCT ON (lp.user_id)
        lp.user_id, lp.geo, lp.range_type, lp.neighborhood,
        ST_Distance(lp.geo, v_source.geo) AS distance_m
      FROM public.location_pings lp
      WHERE lp.user_id > v_source.user_id -- each pair exactly once
        AND lp.created_at > NOW() - make_interval(mins => v_lookback)
        AND public.is_discoverable_user(lp.user_id)
      AND NOT public.consent_withdrawn(lp.user_id, 'precise_location')
        AND ST_DWithin(
          lp.geo, v_source.geo,
          LEAST(v_radius, public.range_radius_meters(lp.range_type))
        )
        AND NOT public.is_blocked_pair(v_source.user_id, lp.user_id)
        AND public.preferences_compatible(v_source.user_id, lp.user_id)
      ORDER BY lp.user_id, lp.created_at DESC
    LOOP
      PERFORM pg_advisory_xact_lock(
        hashtextextended(v_source.user_id::TEXT || v_peer.user_id::TEXT, 0)
      );
      SELECT id INTO v_enc_id
      FROM public.encounters
      WHERE user_a = v_source.user_id AND user_b = v_peer.user_id
        AND status = 'active'
      ORDER BY encounter_time DESC
      LIMIT 1
      FOR UPDATE;

      IF v_enc_id IS NULL THEN
        INSERT INTO public.encounters (
          user_a, user_b, neighborhood, encounter_time, last_seen_at,
          range_type, confidence, status
        ) VALUES (
          v_source.user_id, v_peer.user_id,
          COALESCE(v_source.neighborhood, v_peer.neighborhood, 'Nearby'),
          NOW(), NOW(), v_source.range_type,
          LEAST(1.0, GREATEST(0.4, 1.0 - (v_peer.distance_m / GREATEST(v_radius, 1)))),
          'active'
        ) RETURNING id INTO v_enc_id;
        v_count := v_count + 1;
      ELSE
        UPDATE public.encounters
        SET last_seen_at = NOW(),
            confidence = LEAST(1.0, GREATEST(0.4, 1.0 - (v_peer.distance_m / GREATEST(v_radius, 1))))
        WHERE id = v_enc_id;
      END IF;
    END LOOP;
  END LOOP;
  RETURN v_count;
END;
$$;

COMMIT;
