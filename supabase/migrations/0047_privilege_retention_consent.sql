-- 0047_privilege_retention_consent.sql
--
-- The 2026-07-22 privilege/retention/consent audit found six holes 0046 did
-- not close. All are fixed here (SQL half); the Edge-worker half ships with
-- this commit and must be deployed + scheduled (see SAFETY_RUNBOOK / commit).
--
--   1. CRITICAL  lookup_claim() was executable by anon (PUBLIC default grant),
--                deanonymizing any live BLE token -> owner uuid + approx GPS.
--   2. HIGH      bump_encounter_pair() was anon-executable -> forged pair rows.
--   3. HIGH      token_claim_history was never pruned (claimed "ephemeral").
--   4. HIGH      caller-side location withdrawal was ungated in the two
--                interactive read/correlate paths (only peers were filtered).
--   5. HIGH      the Storage upload gate honored an explicit withdrawal but not
--                enforce_consent=1 with no consent row (never-asked upload).
--   6. HIGH      (Edge) the queue drain didn't recheck holds -> a photo held
--                after being queued was still deletable; and prod scheduled
--                only the SQL RPC, never the Edge worker that physically
--                deletes. The SQL half: a hold-aware dequeue RPC.
--
-- Root cause of 1/2: functions granted to `authenticated` but never REVOKEd
-- from PUBLIC, which the `anon` role inherits. This migration revokes PUBLIC
-- (and anon) from every internal/authenticated SECURITY DEFINER RPC that was
-- exposed, keeping submit_ncii_report (the intentional public form) anon.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1 + 2. Privilege lockdown. Internal-only helpers go to service_role; the
--        rest keep their explicit `authenticated` grant but lose PUBLIC/anon.
-- ---------------------------------------------------------------------------

-- Internal-only (called only inside other SECURITY DEFINER RPCs as the owner):
REVOKE ALL ON FUNCTION public.lookup_claim(TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.lookup_claim(TEXT) TO service_role;

REVOKE ALL ON FUNCTION public.bump_encounter_pair(UUID, UUID, public.range_type) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.bump_encounter_pair(UUID, UUID, public.range_type) TO service_role;

-- Authenticated-only surface: strip the inherited anon/PUBLIC access, keep the
-- explicit authenticated grant each migration already made.
REVOKE EXECUTE ON FUNCTION public.claim_token(TEXT, TIMESTAMPTZ, DOUBLE PRECISION, DOUBLE PRECISION, public.range_type, DOUBLE PRECISION) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.record_sighting(TEXT, DOUBLE PRECISION, DOUBLE PRECISION, INTEGER, TIMESTAMPTZ, public.range_type, DOUBLE PRECISION) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_my_encounters(INT, INT, NUMERIC) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.issue_token_batch(DATE, INT) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.encounter_recurrence(BIGINT, INT) FROM PUBLIC, anon;

-- ---------------------------------------------------------------------------
-- 5. Storage upload must honor enforce_consent, not just explicit withdrawal.
--    my_consent_satisfied() mirrors require_consent(): denied while withdrawn,
--    and (once enforce_consent=1) denied until positively granted.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.my_consent_satisfied(p_purpose TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT NOT public.consent_withdrawn(auth.uid(), p_purpose)
     AND (
       COALESCE((SELECT value_num FROM public.app_settings WHERE key = 'enforce_consent'), 0) < 1
       OR public.has_consent(auth.uid(), p_purpose)
     );
$$;

REVOKE ALL ON FUNCTION public.my_consent_satisfied(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_consent_satisfied(TEXT) TO authenticated, service_role;

DROP POLICY IF EXISTS "Users upload own profile photos" ON storage.objects;
CREATE POLICY "Users upload own profile photos"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'profile_photos'
    AND (storage.foldername(name))[1] = auth.uid()::TEXT
    AND public.my_consent_satisfied('photo_processing')
  );

-- ---------------------------------------------------------------------------
-- 6 (SQL half). Hold-aware dequeue for the Storage worker: it must never hand
--    back an object whose owner is now under a legal hold, even if the object
--    was queued before the hold. The Edge worker calls this instead of reading
--    the table directly.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.pending_storage_deletions(p_limit INT DEFAULT 200)
RETURNS TABLE (id BIGINT, bucket_id TEXT, object_name TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT q.id, q.bucket_id, q.object_name
    FROM public.storage_deletion_queue q
   WHERE q.deleted_at IS NULL
     AND NOT public.has_legal_hold(q.user_id)
   ORDER BY q.requested_at ASC
   LIMIT GREATEST(1, LEAST(1000, COALESCE(p_limit, 200)));
$$;

REVOKE ALL ON FUNCTION public.pending_storage_deletions(INT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pending_storage_deletions(INT) TO service_role;

-- ==== cleanup_ephemeral_data v-next: prune token_claim_history ====
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
     WHERE s.observed_at < NOW() - INTERVAL '48 hours'
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
     WHERE h.valid_until < NOW() - INTERVAL '48 hours'
       AND NOT public.has_legal_hold(h.user_id);
  ELSE
    DELETE FROM public.token_claims
     WHERE valid_until < NOW() - INTERVAL '30 minutes';

    DELETE FROM public.sightings
     WHERE observed_at < NOW() - INTERVAL '48 hours';

    DELETE FROM public.location_pings
     WHERE created_at < NOW() - INTERVAL '24 hours';

    DELETE FROM public.token_claim_history
     WHERE valid_until < NOW() - INTERVAL '48 hours';
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

-- ==== correlate_miles_encounters v-next: caller precise_location gate ====
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
  -- 0047: a caller who withdrew precise_location must not have their own
  -- preserved (held) ping drive correlation.
  IF public.consent_withdrawn(v_uid, 'precise_location') THEN
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

-- ==== get_locals_feed v-next: caller precise_location gate ====
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
  -- 0047: a caller who withdrew precise_location cannot read the feed off
  -- their own preserved (held) ping either.
  IF public.consent_withdrawn(v_uid, 'precise_location') THEN
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
