-- 0059_proximity_wake_producer.sql
--
-- Fixes for the proximity-wake pipeline:
--
--   1. Adds a producer. proximity_wake_requests was privacy-plumbed but had no
--      writer. The client now calls public.enqueue_proximity_wake after
--      uploading a venue hint, which inserts a pending row with requester
--      throttling.
--   2. Fixes peer rate limiting. The original recentlyWoken checked
--      user_id = peer, but rows were only created with the requester's
--      user_id. We now record recipient_user_id on each sent row so the
--      per-peer check actually works.
--
-- SENSITIVITY: no new raw location data. peer_hint remains the coarse geohash
-- and hashed BSSID uploaded by the client. recipient_user_id is used only for
-- rate limiting and is deleted on account scrub.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. recipient_user_id on proximity_wake_requests
-- ---------------------------------------------------------------------------

ALTER TABLE public.proximity_wake_requests
  ADD COLUMN IF NOT EXISTS recipient_user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_proximity_wake_recipient_sent
  ON public.proximity_wake_requests (recipient_user_id, sent_at DESC)
  WHERE status = 'sent' AND recipient_user_id IS NOT NULL;

COMMENT ON COLUMN public.proximity_wake_requests.recipient_user_id IS
  'The peer who was woken. Used for per-peer rate limiting; null on pending rows.';

-- ---------------------------------------------------------------------------
-- 1b. Push-token provider discriminator
-- ---------------------------------------------------------------------------
-- device_push_tokens currently holds FCM tokens for send-push. APNs tokens for
-- proximity-wake must not be fed into the FCM HTTP v1 API. A provider column
-- keeps the two namespaces separate without a second table.

ALTER TABLE public.device_push_tokens
  ADD COLUMN IF NOT EXISTS provider TEXT NOT NULL DEFAULT 'fcm'
    CHECK (provider IN ('fcm', 'apns'));

CREATE INDEX IF NOT EXISTS idx_push_tokens_provider
  ON public.device_push_tokens (provider, platform);

COMMENT ON COLUMN public.device_push_tokens.provider IS
  'Push provider namespace. fcm = Firebase Cloud Messaging (send-push); apns = Apple Push Notification service (proximity-wake).';

-- Existing iOS rows are FCM until proven otherwise (the app has not shipped
-- APNs token registration yet).
UPDATE public.device_push_tokens SET provider = 'fcm' WHERE provider IS NULL;

-- register_push_token now accepts a provider so APNs tokens do not land in
-- the FCM namespace. SECURITY DEFINER; same validation as 0009 plus provider.
-- DROP the 0009 3-arg version first: without this the CREATE makes a 4-arg
-- overload, the old 3-arg function stays live, and PostgREST's existing
-- 3-arg .rpc('register_push_token', ...) becomes ambiguous at call time.
DROP FUNCTION IF EXISTS public.register_push_token(TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.register_push_token(
  p_token TEXT,
  p_platform TEXT,
  p_app_version TEXT DEFAULT NULL,
  p_provider TEXT DEFAULT 'fcm'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_token IS NULL OR length(trim(p_token)) = 0 THEN
    RAISE EXCEPTION 'token required';
  END IF;
  IF p_platform NOT IN ('android', 'ios', 'web') THEN
    RAISE EXCEPTION 'platform must be android|ios|web';
  END IF;
  IF p_provider NOT IN ('fcm', 'apns') THEN
    RAISE EXCEPTION 'provider must be fcm|apns';
  END IF;

  INSERT INTO public.device_push_tokens (user_id, token, platform, app_version, provider, last_seen_at)
  VALUES (auth.uid(), trim(p_token), p_platform, p_app_version, p_provider, NOW())
  ON CONFLICT (user_id, token) DO UPDATE
    SET last_seen_at = NOW(),
        platform = EXCLUDED.platform,
        app_version = COALESCE(EXCLUDED.app_version, public.device_push_tokens.app_version),
        provider = EXCLUDED.provider
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

COMMENT ON FUNCTION public.register_push_token(TEXT, TEXT, TEXT, TEXT) IS
  'Registers a device push token for the calling user. provider=fcm for send-push, provider=apns for proximity-wake.';

REVOKE ALL ON FUNCTION public.register_push_token(TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_push_token(TEXT, TEXT, TEXT, TEXT) TO authenticated;

-- ---------------------------------------------------------------------------
-- 2. Producer RPC: enqueue_proximity_wake
-- ---------------------------------------------------------------------------
-- Called by the client after a successful venue-hint upload. SECURITY DEFINER
-- so the batch insert and rate-limit check cannot be bypassed by direct table
-- access. One pending row per user per 5 minutes — the Edge Function still
-- does its own 15-minute send-side rate limit.

CREATE OR REPLACE FUNCTION public.enqueue_proximity_wake(
  p_geohash TEXT,
  p_hashed_bssid TEXT
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_id BIGINT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  IF (p_geohash IS NULL OR p_geohash = '') AND (p_hashed_bssid IS NULL OR p_hashed_bssid = '') THEN
    RAISE EXCEPTION 'enqueue_proximity_wake requires a geohash or a hashed BSSID';
  END IF;

  -- Requester throttle: skip if a pending row already exists for this user in
  -- the last 5 minutes. The Edge Function's 15-minute sent-side limit is the
  -- real guard; this just keeps the outbox from flooding on a burst of hints.
  IF EXISTS (
    SELECT 1 FROM public.proximity_wake_requests
     WHERE user_id = v_uid
       AND status = 'pending'
       AND created_at > NOW() - INTERVAL '5 minutes'
  ) THEN
    RETURN NULL;
  END IF;

  INSERT INTO public.proximity_wake_requests (user_id, peer_hint)
  VALUES (
    v_uid,
    jsonb_strip_nulls(jsonb_build_object(
      'geohash', NULLIF(p_geohash, ''),
      'hashed_bssid', NULLIF(p_hashed_bssid, '')
    ))
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

COMMENT ON FUNCTION public.enqueue_proximity_wake IS
  'Enqueues a proximity wake request after a venue-hint upload. Throttled to one pending row per user per 5 minutes. Called by the client; service_role and Edge Function drain the outbox.';

REVOKE ALL ON FUNCTION public.enqueue_proximity_wake(TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.enqueue_proximity_wake(TEXT, TEXT) TO authenticated;

-- ---------------------------------------------------------------------------
-- 3. Deletion (scrub_account_pii)
-- ---------------------------------------------------------------------------
-- recipient_user_id references auth.users, so a deleting user must also have
-- rows where they were the recipient removed.
-- Body as of 0058_subtle_wake_privacy.sql:55, plus recipient_user_id handling.

CREATE OR REPLACE FUNCTION public.scrub_account_pii(p_uid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_rid BIGINT;
BEGIN
  IF p_uid IS NULL THEN
    RAISE EXCEPTION 'scrub_account_pii requires a user id';
  END IF;

  -- Preservation beats erasure. Deferred, not refused: request_account_deletion
  -- still stamps deleted_at, so purge_deleted_accounts() completes this
  -- automatically once the hold lifts.
  IF public.has_legal_hold(p_uid) THEN
    RETURN FALSE;
  END IF;

  -- Evidence before erasure (H1/H2): snapshot every OPEN report this account
  -- is a party to. The reviewer still reviews; the snapshot just means the
  -- redaction below cannot destroy what they would have reviewed.
  FOR v_rid IN
    SELECT id FROM public.reports
     WHERE (reported_id = p_uid OR reporter_id = p_uid)
       AND status IN ('open', 'reviewing')
  LOOP
    PERFORM public.snapshot_report_evidence(v_rid, 'scrub');
  END LOOP;

  -- A deleted account holds no live consents (the grant would otherwise stay
  -- "active" through the 30-day grace). Direct UPDATE rather than
  -- withdraw_consent(): that RPC reads auth.uid() and has side effects the
  -- scrub already performs (location_pings goes below).
  UPDATE public.consent_records SET withdrawn_at = NOW()
   WHERE user_id = p_uid AND withdrawn_at IS NULL;

  UPDATE public.profiles SET
    display_name              = 'Deleted user',
    bio                       = NULL,
    dob                       = NULL,
    gender                    = NULL,
    sexual_preference         = NULL,
    interests                 = NULL,
    photo_urls                = NULL,
    neighborhood              = NULL,
    email_hint                = NULL,
    phone_hint                = NULL,
    photo_verification_status = NULL,
    is_photo_verified         = FALSE,
    age_verified              = FALSE,
    is_active                 = FALSE,
    is_paused                 = TRUE,
    is_incognito              = FALSE,
    last_active_at            = NULL,
    deleted_at                = COALESCE(deleted_at, NOW()),
    updated_at                = NOW()
  WHERE id = p_uid;

  DELETE FROM public.location_pings          WHERE user_id          = p_uid;
  DELETE FROM public.token_claims            WHERE user_id          = p_uid;
  DELETE FROM public.token_claim_history     WHERE user_id          = p_uid;
  DELETE FROM public.sightings               WHERE observer_user_id = p_uid;
  DELETE FROM public.beacon_token_batch      WHERE user_id          = p_uid;
  DELETE FROM public.device_attestations     WHERE user_id          = p_uid;
  DELETE FROM public.device_push_tokens      WHERE user_id          = p_uid;
  DELETE FROM public.notification_outbox     WHERE user_id          = p_uid;
  DELETE FROM public.photo_verifications     WHERE user_id          = p_uid;
  DELETE FROM public.rssi_samples            WHERE user_id          = p_uid;
  DELETE FROM public.venue_anchors           WHERE user_id          = p_uid;
  DELETE FROM public.proximity_wake_requests WHERE user_id          = p_uid;
  -- 0059: also remove rows where the user was the woken recipient.
  DELETE FROM public.proximity_wake_requests WHERE recipient_user_id = p_uid;

  INSERT INTO public.storage_deletion_queue (user_id, bucket_id, object_name)
  SELECT p_uid, o.bucket_id, o.name
    FROM storage.objects o
   WHERE (o.bucket_id IN ('profile_photos', 'verified_photos')
            AND (storage.foldername(o.name))[1] = p_uid::TEXT)
      OR (o.bucket_id = 'chat_media'
            AND (storage.foldername(o.name))[2] = p_uid::TEXT)
  ON CONFLICT (bucket_id, object_name) DO NOTHING;

  UPDATE public.messages
     SET content  = CASE WHEN message_type = 'text' THEN '[deleted]' ELSE NULL END,
         metadata = NULL
   WHERE sender_id = p_uid;

  UPDATE public.ad_impressions SET user_id = NULL WHERE user_id = p_uid;
  UPDATE public.ai_events      SET user_id = NULL WHERE user_id = p_uid;

  RETURN TRUE;
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Right of access (export_my_data)
-- ---------------------------------------------------------------------------
-- Body as of 0058_subtle_wake_privacy.sql:147, plus recipient_user_id in the
-- proximity_wake_requests export.

CREATE OR REPLACE FUNCTION public.export_my_data()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_out JSONB;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  SELECT jsonb_build_object(
    'export_format', 'in_range.export.v1',
    'generated_at', NOW(),
    'user_id', v_uid,

    -- Everything we hold on the profile itself.
    'profile', (
      SELECT to_jsonb(p) - 'id'
        FROM public.profiles p WHERE p.id = v_uid
    ),

    'account', (
      SELECT jsonb_build_object(
               'email', u.email,
               'created_at', u.created_at,
               'last_sign_in_at', u.last_sign_in_at)
        FROM auth.users u WHERE u.id = v_uid
    ),

    -- Proximity records. Counterpart stays an opaque id by design.
    'encounters', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'encounter_id', e.id,
               'counterpart_user_id', CASE WHEN e.user_a = v_uid THEN e.user_b ELSE e.user_a END,
               'encounter_time', e.encounter_time,
               'neighborhood', e.neighborhood,
               'range_type', e.range_type,
               'confidence', e.confidence,
               'trust_level', e.trust_level,
               'status', e.status,
               'session_count', e.session_count,
               'distinct_day_count', e.distinct_day_count,
               'first_seen_at', e.first_seen_at,
               'last_seen_at', e.last_seen_at)
             ORDER BY e.encounter_time DESC)
        FROM public.encounters e
       WHERE e.user_a = v_uid OR e.user_b = v_uid
    ), '[]'::jsonb),

    'encounter_actions', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'encounter_id', a.encounter_id, 'action', a.action, 'acted_at', a.acted_at)
             ORDER BY a.acted_at DESC)
        FROM public.encounter_actions a WHERE a.user_id = v_uid
    ), '[]'::jsonb),

    'matches', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'match_id', m.id,
               'counterpart_user_id', CASE WHEN m.user_a = v_uid THEN m.user_b ELSE m.user_a END,
               'matched_at', m.matched_at, 'status', m.status,
               'expires_at', m.expires_at, 'ended_at', m.ended_at)
             ORDER BY m.matched_at DESC)
        FROM public.matches m WHERE m.user_a = v_uid OR m.user_b = v_uid
    ), '[]'::jsonb),

    -- Conversations the caller participated in. Bodies included (already
    -- visible to them in-app); sender marked as self/counterpart.
    'messages', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'match_id', msg.match_id,
               'sent_by_me', (msg.sender_id = v_uid),
               'content', msg.content,
               'message_type', msg.message_type,
               'created_at', msg.created_at,
               'read_at', msg.read_at)
             ORDER BY msg.created_at)
        FROM public.messages msg
        JOIN public.matches mt ON mt.id = msg.match_id
       WHERE mt.user_a = v_uid OR mt.user_b = v_uid
    ), '[]'::jsonb),

    -- Precise location. Purged after 24h, so this is normally near-empty --
    -- which is itself a useful thing for a requester to be able to see.
    'location_pings', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'latitude', ST_Y(lp.geo::geometry),
               'longitude', ST_X(lp.geo::geometry),
               'range_type', lp.range_type,
               'neighborhood', lp.neighborhood,
               'created_at', lp.created_at)
             ORDER BY lp.created_at DESC)
        FROM public.location_pings lp WHERE lp.user_id = v_uid
    ), '[]'::jsonb),

    -- 0056: raw proximity measurements shipped from the caller's own devices.
    -- The counterpart is a rotating correlation id, never a user id, so this
    -- stays consistent with the scope rule at the top of 0036.
    'rssi_samples', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'device_id', rs.device_id,
               'platform', rs.platform,
               'at_ms', rs.at_ms,
               'correlation_id', rs.correlation_id,
               'rssi', rs.rssi,
               'power', rs.power,
               'received_at', rs.received_at)
             ORDER BY rs.at_ms)
        FROM public.rssi_samples rs WHERE rs.user_id = v_uid
    ), '[]'::jsonb),

    -- 0058: coarse venue hints. Geohash is city-level; BSSID is hashed.
    'venue_anchors', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'geohash', va.geohash,
               'radius_m', va.radius_m,
               'hashed_bssid', va.hashed_bssid,
               'updated_at', va.updated_at)
             ORDER BY va.updated_at DESC)
        FROM public.venue_anchors va WHERE va.user_id = v_uid
    ), '[]'::jsonb),

    -- 0058/0059: silent-push wake requests. No user data beyond the hint.
    'proximity_wake_requests', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'peer_hint', pwr.peer_hint,
               'status', pwr.status,
               'created_at', pwr.created_at,
               'sent_at', pwr.sent_at)
             ORDER BY pwr.created_at DESC)
        FROM public.proximity_wake_requests pwr WHERE pwr.user_id = v_uid
    ), '[]'::jsonb),

    'blocks', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'blocked_user_id', b.blocked_id, 'created_at', b.created_at)
             ORDER BY b.created_at DESC)
        FROM public.blocks b WHERE b.blocker_id = v_uid
    ), '[]'::jsonb),

    -- Reports the caller FILED. Reports filed ABOUT them are deliberately
    -- excluded: disclosing those would expose the reporter and defeat the
    -- safety mechanism.
    'reports_filed', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'reason', r.reason, 'details', r.details,
               'status', r.status, 'created_at', r.created_at)
             ORDER BY r.created_at DESC)
        FROM public.reports r WHERE r.reporter_id = v_uid
    ), '[]'::jsonb),

    -- Billing. raw_receipt is excluded: it is the store's payload, contains
    -- no data the user gave us, and can carry provider-side identifiers.
    'subscriptions', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'tier', s.tier, 'status', s.status, 'provider', s.provider,
               'product_id', s.product_id, 'starts_at', s.starts_at,
               'expires_at', s.expires_at, 'canceled_at', s.canceled_at)
             ORDER BY s.created_at DESC)
        FROM public.subscriptions s WHERE s.user_id = v_uid
    ), '[]'::jsonb),

    'boosts', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'product_id', bo.product_id, 'provider', bo.provider,
               'starts_at', bo.starts_at, 'ends_at', bo.ends_at)
             ORDER BY bo.created_at DESC)
        FROM public.boosts bo WHERE bo.user_id = v_uid
    ), '[]'::jsonb),

    -- Registered push destinations, by platform and provider only -- the token
    -- itself is a device credential, not user-facing data.
    'push_devices', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'platform', d.platform, 'provider', d.provider, 'created_at', d.created_at))
        FROM public.device_push_tokens d WHERE d.user_id = v_uid
    ), '[]'::jsonb)
  ) INTO v_out;

  RETURN v_out;
END;
$$;

COMMENT ON FUNCTION public.export_my_data IS
  'Right-of-access export of the calling user''s own data. Counterparts appear only as opaque user ids; reports filed about the caller are excluded to protect reporters.';

REVOKE ALL ON FUNCTION public.export_my_data() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.export_my_data() TO authenticated;

-- ---------------------------------------------------------------------------
-- 5. Retention (cleanup_ephemeral_data)
-- ---------------------------------------------------------------------------
-- Body as of 0058_subtle_wake_privacy.sql:334, unchanged. proximity_wake_requests
-- retention already covers both user_id and recipient_user_id rows.

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

COMMENT ON FUNCTION public.cleanup_ephemeral_data IS
  'Sweeps ephemeral tables: location_pings (24 h), sightings (24 h), token_claim_history (24 h), rssi_samples (30 d), venue_anchors (14 d), proximity_wake_requests (30 d sent / 7 d failed), notification_outbox, AI events/runs (90 d), report_evidence (1 y). Honors legal holds.';

COMMIT;
