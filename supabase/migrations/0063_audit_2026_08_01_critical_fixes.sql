-- 0063_audit_2026_08_01_critical_fixes.sql
--
-- Fixes three of the four Criticals from the 2026-08-01 tri-model hardening
-- audit (docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md,
-- commit d1b8c38). The fourth (C-PROD-1) was a deploy-drift defect and was
-- closed by redeploying send-push + photo-review; no schema change.
--
--   C-SQL-1  claim_token could overwrite ANOTHER user's token_claim_history row
--   C-SQL-3  beacon_token_batch had no scheduled purge
--   C-SQL-4  batch-pre-claimed (NULL-location) tokens skipped the GPS veto
--
-- Function bodies below were extracted VERBATIM from their latest definitions
-- (claim_token 0060, correlate_encounter 0053, cleanup_ephemeral_data 0059) and
-- modified only at the marked sites, to avoid transcription drift.
--
-- REVIEW STATUS: reviewed by Kimi K3 and Codex (gpt-5.6-sol). Both found real
-- defects in the first draft; all are fixed here and re-rehearsed:
--   * the "dead COALESCE" claim was only half true -- p_accuracy and p_range are
--     genuinely nullable, so dropping their COALESCEs would have silently nulled
--     values an earlier claim set. Restored. (Codex)
--   * the fallback veto reused p_radius_meters, which record_sighting computed
--     from the CLAIM's (NULL-ish) accuracy -- the very thing that got us there.
--     Now recomputed from both OBSERVERS' accuracies. (Kimi and Codex, indep.)
--   * the batch purge was hold-blind, contradicting this function's own legal
--     hold invariant. Now hold-aware. (Codex and Kimi)
--   * a first draft added GREATEST() to valid_until; reverted to the original
--     plain assignment, since it is not a security property and it would block
--     correcting an accidentally excessive expiry. (Codex)
--   * self-caught during review: correlate_encounter has no p_accuracy
--     parameter, so the first radius call would not have resolved.
--
-- ⛔ DEPLOYMENT BLOCKER -- DO NOT PUSH THIS ALONE.
-- Production is at 0001-0055 + 0062; 0056-0061 are NOT applied (verified via
-- `supabase migration list --linked` and a live schema dump). This migration
-- redefines cleanup_ephemeral_data using 0059's body, which references
-- rssi_samples, venue_anchors and proximity_wake_requests -- none of which
-- exist in production. Pushing 0063 by itself would break run_maintenance, the
-- job that performs every retention purge. Ship 0056 -> 0063 as one ordered
-- batch. (Caught by Kimi.)
--
-- KNOWN LIMITATIONS, NOT SOLVED HERE -- these need tests, not more SQL:
--   1. Moved-before-wake false negative (Codex). The native buffer stores only
--      token/rssi/ts; Dart attaches its CURRENT cached location at flush time.
--      If a locked phone moved between the encounter and its wake, the fallback
--      compares wake-time coordinates against encounter-time coordinates and can
--      reject a genuine late encounter. Needs a regression test before the
--      0056-0063 batch ships.
--   2. Squat-first residual (Kimi). The ownership guard protects the UPDATE path
--      only; the INSERT path still allows claiming a token first while
--      enforce_batch_tokens = 0, and this guard then makes that squat permanent.
--      Belongs to the flag flip.
--   3. First scheduled cleanup after this lands will delete the entire
--      accumulated expired-batch backlog in one transaction. Preflight the row
--      count and batch it if large. (Codex)
--   4. This migration does not repair already-poisoned coordinate/history rows.

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
  ON CONFLICT (token) DO UPDATE SET
    valid_until = EXCLUDED.valid_until,
    approx_lat = EXCLUDED.approx_lat,
    approx_lon = EXCLUDED.approx_lon,
    -- REVIEW FIX (Codex): the COALESCEs were dead ONLY for approx_lat/approx_lon,
    -- which cannot be NULL (0060:117-118 raises). p_accuracy is nullable and
    -- p_range can be passed NULL explicitly despite its default, so dropping
    -- their COALESCEs would have been a silent semantic change that could null
    -- out a value an earlier claim had set. Restored.
    range_type = COALESCE(EXCLUDED.range_type, public.token_claim_history.range_type),
    accuracy_m = COALESCE(EXCLUDED.accuracy_m, public.token_claim_history.accuracy_m)
  -- 0063 (audit C-SQL-1): the conflict target is the TOKEN, but the
  -- security-relevant key is (token, owner). Without this predicate any
  -- authenticated caller who sniffed a token off the air could rewrite the
  -- owner's row -- including approx_lat/lon, which correlate_encounter's GPS
  -- veto compares against -- and could extend valid_until indefinitely.
  -- A foreign-owned conflict is now a silent no-op.
  -- NOTE on the geo COALESCEs: they were dead ONLY for approx_lat/approx_lon
  -- (this function RAISEs on NULL p_lat/p_lon), so those are plain assignments
  -- now. range_type/accuracy_m keep theirs -- both are genuinely nullable.
  -- RESIDUAL, NOT CLOSED BY THIS MIGRATION: the guard protects the UPDATE path
  -- only. The INSERT path (token never claimed before) still lets a caller
  -- create a history row under their own user_id for a token issued to someone
  -- else while enforce_batch_tokens = 0, and this WHERE then makes that squat
  -- permanent -- the legitimate owner's later claim is also a no-op. That
  -- residual belongs to the enforce_batch_tokens flip. (Kimi, migration review.)
  -- Deliberately a silent no-op rather than a RAISE: a distinct error would be
  -- a "this token is live and owned by someone else" oracle, and reusing the
  -- generic error would abort the whole transaction and break honest old
  -- clients reclaiming after a squat during the flag-off window.
  WHERE public.token_claim_history.user_id = v_uid;
END;
$function$;

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
  -- 0063 (audit C-SQL-4)
  v_rev_lat DOUBLE PRECISION; v_rev_lon DOUBLE PRECISION;
  v_rev_acc DOUBLE PRECISION; v_fwd_acc DOUBLE PRECISION;
  v_fallback_radius DOUBLE PRECISION;
  v_veto_ran BOOLEAN := FALSE;
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

  SELECT s.rssi, s.range_type, s.observer_accuracy_m
    INTO v_rssi, v_sight_range, v_fwd_acc
  FROM public.sightings s
  WHERE s.observer_user_id = v_uid AND s.observed_token = lower(p_observed_token)
  ORDER BY s.observed_at DESC LIMIT 1;
  v_min_rssi := CASE COALESCE(v_claim.range_type,'feet_10') WHEN 'feet_10' THEN -75 WHEN 'feet_20' THEN -85 ELSE -95 END;
  IF v_rssi IS NULL OR v_rssi < v_min_rssi THEN RETURN; END IF;

  IF p_lat IS NOT NULL AND p_lon IS NOT NULL AND v_claim.approx_lat IS NOT NULL AND v_claim.approx_lon IS NOT NULL THEN
    v_distance := ST_Distance(ST_SetSRID(ST_MakePoint(p_lon, p_lat),4326)::geography, ST_SetSRID(ST_MakePoint(v_claim.approx_lon, v_claim.approx_lat),4326)::geography);
    IF v_distance > LEAST(400.0, GREATEST(5.0, p_radius_meters)) THEN RETURN; END IF;
    v_veto_ran := TRUE;
  END IF;

  IF v_sight_range IS NOT NULL AND v_sight_range::TEXT LIKE 'feet_%' THEN v_band := v_sight_range; ELSE v_band := COALESCE(v_claim.range_type, 'feet_10'); END IF;

  -- Reciprocity gate (server-receipt window; caller-supplied values ignored).
  -- 0053: widened from a fixed 3 min — the other side's evidence may be a
  -- locked phone's wake-burst upload from earlier in the same co-presence.
  SELECT rs.range_type, rs.observer_lat, rs.observer_lon, rs.observer_accuracy_m
    INTO v_reverse_band, v_rev_lat, v_rev_lon, v_rev_acc
  FROM public.sightings rs
  WHERE rs.observer_user_id = v_claim.user_id AND rs.observed_user_id = v_uid
    AND rs.received_at > NOW() - v_late
  ORDER BY rs.received_at DESC LIMIT 1;
  IF NOT FOUND THEN RETURN; END IF;

  -- 0063 (audit C-SQL-4): the veto above runs ONLY when the claim row carries
  -- coordinates. claim_token requires them, but claim_token_batch (0060)
  -- pre-claims the whole batch with NULL location -- the locked-phone path --
  -- so for those tokens the spatial bound never executed at all. Fall back to
  -- comparing the two OBSERVERS' own recorded positions, which are NOT NULL on
  -- every sightings row, and fail CLOSED if neither comparison is possible.
  IF NOT v_veto_ran THEN
    IF p_lat IS NULL OR p_lon IS NULL OR v_rev_lat IS NULL OR v_rev_lon IS NULL THEN
      RETURN;
    END IF;
    -- REVIEW FIX (Kimi + Codex, independently): p_radius_meters was computed by
    -- record_sighting from the CLAIM's accuracy, which is exactly the NULL-ish
    -- value that got us here. Recompute from the two OBSERVERS' own accuracies,
    -- so an SLC/wake-burst reverse fix that is legitimately hundreds of metres
    -- coarse is not vetoed as a forgery. Still 400 m capped.
    -- NOTE: correlate_encounter has no p_accuracy parameter; the caller's own
    -- accuracy comes from their sighting row, fetched above.
    v_fallback_radius := public.gps_veto_radius_meters(v_fwd_acc, v_rev_acc);
    v_distance := ST_Distance(
      ST_SetSRID(ST_MakePoint(p_lon, p_lat),4326)::geography,
      ST_SetSRID(ST_MakePoint(v_rev_lon, v_rev_lat),4326)::geography);
    IF v_distance > v_fallback_radius THEN RETURN; END IF;
  END IF;

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

    -- 0056
    DELETE FROM public.rssi_samples rs
     WHERE rs.received_at < NOW() - INTERVAL '30 days'
       AND NOT public.has_legal_hold(rs.user_id);

    -- 0058
    DELETE FROM public.venue_anchors va
     WHERE va.updated_at < NOW() - INTERVAL '14 days'
       AND NOT public.has_legal_hold(va.user_id);

    DELETE FROM public.proximity_wake_requests pwr
     WHERE (pwr.status IN ('sent', 'skipped') AND pwr.created_at < NOW() - INTERVAL '30 days')
        OR (pwr.status = 'failed' AND pwr.created_at < NOW() - INTERVAL '7 days');
  ELSE
    DELETE FROM public.token_claims
     WHERE valid_until < NOW() - INTERVAL '30 minutes';

    DELETE FROM public.sightings
     WHERE observed_at < NOW() - INTERVAL '24 hours';

    DELETE FROM public.location_pings
     WHERE created_at < NOW() - INTERVAL '24 hours';

    -- 0047: token_claim_history is ephemeral too; it was never pruned.
    DELETE FROM public.token_claim_history
     WHERE valid_until < NOW() - INTERVAL '24 hours';

    -- 0056
    DELETE FROM public.rssi_samples
     WHERE received_at < NOW() - INTERVAL '30 days';

    -- 0058
    DELETE FROM public.venue_anchors
     WHERE updated_at < NOW() - INTERVAL '14 days';

    DELETE FROM public.proximity_wake_requests
     WHERE (status IN ('sent', 'skipped') AND created_at < NOW() - INTERVAL '30 days')
        OR (status = 'failed' AND created_at < NOW() - INTERVAL '7 days');
  END IF;

  -- Rate buckets outlive their window by definition; drop idle ones.
  -- 0063 (audit C-SQL-3): beacon_token_batch was purged NOWHERE on a schedule.
  -- Its only DELETEs were self-scoped inside issue_token_batch (runs only when
  -- that same user next requests a batch, so a lapsed user's rows persisted
  -- forever) and the account-deletion paths. The table maps token -> user_id,
  -- and rssi_samples.correlation_id is the same value space, so an unpurged
  -- copy de-anonymises up to 30 days of proximity data at rest.
  -- REVIEW FIX (Codex + Kimi): hold-aware. An unconditional purge here would
  -- contradict this function's own legal-hold invariant and destroy a held
  -- user's token mappings while their token_claim_history is preserved.
  DELETE FROM public.beacon_token_batch b
  WHERE b.valid_until < NOW() - INTERVAL '24 hours'
    AND NOT public.has_legal_hold(b.user_id);

  DELETE FROM public.rssi_batch_rate
   WHERE window_start < NOW() - INTERVAL '1 day';

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

COMMIT;
