-- 0056_calibration_rssi_samples.sql
--
-- Ship on-device rssi_log rows to the server so a calibration walk can be
-- extracted without the phone in hand.
--
-- WHY: an iPhone's calibration data is currently trapped behind a USB pull on
-- the one Mac that is paired with it. That does not scale past two testers and
-- it does not work at all for real users, whose phones we can never touch. See
-- docs/CLOUD_RSSI_UPLOAD_SPEC.md.
--
-- SENSITIVITY: rssi_samples is a RAW CO-LOCATION LOG. Each row says "this user
-- was within BLE range of this correlation id at this instant". Two users'
-- streams joined server-side reconstruct who was near whom and when — exactly
-- what the encounter pipeline deliberately withholds behind the reveal delay
-- and the consent gates (0039/0040). Uploads are therefore gated CLIENT-SIDE on
-- INRANGE_CALIB_SCAN (a lab flag, default false). Enabling this for general
-- users is a new data category, not a config change: it needs a consent record,
-- a retention decision, and a privacy-policy line first.
--
-- The device DB stays the source of truth. This is a shipper on top of it, so a
-- network failure mid-walk costs nothing a USB pull cannot recover.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. rssi_samples
-- ---------------------------------------------------------------------------
-- Mirrors lib/core/db/local_db.dart:32 (rssi_log), plus the three columns the
-- local table does not need: who, which device, and which local row.

CREATE TABLE IF NOT EXISTS public.rssi_samples (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id        UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  device_id      TEXT NOT NULL,
  platform       TEXT NOT NULL CHECK (platform IN ('ios','android')),
  -- The local rssi_log.id (INTEGER PRIMARY KEY AUTOINCREMENT). Carried so the
  -- natural key below is exact, and so the extractor can detect a GAP in the
  -- sequence — the difference between "the peer went quiet" and "the upload
  -- dropped rows", which RSSI values alone cannot distinguish.
  device_seq     BIGINT NOT NULL,
  -- DEVICE clock, milliseconds. Never server time: extract_walk.py windows on
  -- this and the walk_id digest hashes it, so rewriting it here would break
  -- walk identity. Same client-timestamp pass-through rationale as 0053.
  at_ms          BIGINT NOT NULL,
  correlation_id TEXT NOT NULL,
  rssi           INTEGER NOT NULL CHECK (rssi BETWEEN -127 AND 20),
  power          TEXT NOT NULL CHECK (power IN ('H','M')),
  received_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Idempotency. Re-uploading a batch must not mint duplicate samples: a walk
-- that ingests twice satisfies the >=3-walk trainer gate with copies of one
-- walk, which is the exact failure the walk_id digest exists to prevent.
--
-- Keyed on device_seq rather than on the sample content. Content is not unique
-- — two adverts can share (at_ms, correlation_id, rssi, power) — so a content
-- key would silently drop real measurements and skew high_n/med_n.
--
-- CLIENT REQUIREMENT: device_seq restarts at 1 if the local DB is recreated, so
-- LocalDb.wipeAll() MUST rotate device_id. Without that, post-wipe rows collide
-- with pre-wipe rows and are dropped by this index.
CREATE UNIQUE INDEX IF NOT EXISTS uq_rssi_samples_device_seq
  ON public.rssi_samples (user_id, device_id, device_seq);

-- Extraction: one walk window on one device.
CREATE INDEX IF NOT EXISTS idx_rssi_samples_device_time
  ON public.rssi_samples (user_id, device_id, at_ms);

CREATE INDEX IF NOT EXISTS idx_rssi_samples_cleanup
  ON public.rssi_samples (received_at);

ALTER TABLE public.rssi_samples ENABLE ROW LEVEL SECURITY;

-- No INSERT policy: writes go through record_rssi_batch (SECURITY DEFINER) so
-- the batch cap and rate limit cannot be bypassed by a direct table insert.
-- SELECT on own rows only — needed by export_my_data below, and the thing that
-- keeps this table from being a proximity oracle for anyone else.
DROP POLICY IF EXISTS "Users read own rssi samples" ON public.rssi_samples;
CREATE POLICY "Users read own rssi samples"
  ON public.rssi_samples FOR SELECT TO authenticated
  USING (user_id = auth.uid());

REVOKE ALL ON TABLE public.rssi_samples FROM PUBLIC, anon;
GRANT SELECT ON TABLE public.rssi_samples TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.rssi_samples TO service_role;

COMMENT ON TABLE public.rssi_samples IS
  'Raw per-advert RSSI shipped from devices for proximity calibration. Co-location data: rows joined across two users reconstruct who was near whom. Written only while INRANGE_CALIB_SCAN is on; enabling for general users requires a consent record (0039).';
COMMENT ON COLUMN public.rssi_samples.device_seq IS
  'Local rssi_log.id. Natural key for idempotent re-upload and for gap detection. LocalDb.wipeAll() must rotate device_id, since this counter restarts at 1.';
COMMENT ON COLUMN public.rssi_samples.at_ms IS
  'Device clock at sample time, not upload time. extract_walk.py windows on this and the walk_id digest hashes it.';

-- ---------------------------------------------------------------------------
-- 2. record_rssi_batch
-- ---------------------------------------------------------------------------
-- Per-call rate bucket, same shape as sighting_call_rate (0026): counted before
-- the work, so a caller cannot burn server time by resending duplicates that
-- ON CONFLICT will discard.

CREATE TABLE IF NOT EXISTS public.rssi_batch_rate (
  user_id      UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  window_start TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  calls        INT NOT NULL DEFAULT 0
);
ALTER TABLE public.rssi_batch_rate ENABLE ROW LEVEL SECURITY;
-- No policies: only the SECURITY DEFINER RPC touches it.

CREATE OR REPLACE FUNCTION public.record_rssi_batch(
  p_device_id TEXT,
  p_platform  TEXT,
  p_samples   JSONB
) RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid   UUID := auth.uid();
  v_now   TIMESTAMPTZ := NOW();
  v_calls INT;
  v_n     INT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_device_id IS NULL OR length(p_device_id) NOT BETWEEN 8 AND 64 THEN
    RAISE EXCEPTION 'Invalid device id' USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(p_samples) <> 'array' THEN
    RAISE EXCEPTION 'p_samples must be a JSON array' USING ERRCODE = '22023';
  END IF;
  -- Cap matches the client's page size. A larger batch is a bug or an abuse,
  -- not a legitimate flush.
  IF jsonb_array_length(p_samples) > 500 THEN
    RAISE EXCEPTION 'Batch too large' USING ERRCODE = '22023';
  END IF;
  -- Rate FIRST, before the empty-batch short-circuit below: metering only the
  -- calls that carry rows would leave an empty-array flood entirely unmetered,
  -- which is the same hole 0026 closed on record_sighting. (Calls that RAISE
  -- above cannot be metered at all — the exception rolls the counter back with
  -- everything else. Same inherent property as sighting_call_rate.)
  INSERT INTO public.rssi_batch_rate AS r (user_id, window_start, calls)
  VALUES (v_uid, v_now, 1)
  ON CONFLICT (user_id) DO UPDATE
    SET window_start = CASE WHEN r.window_start < v_now - INTERVAL '1 minute'
                           THEN v_now ELSE r.window_start END,
        calls = CASE WHEN r.window_start < v_now - INTERVAL '1 minute'
                     THEN 1 ELSE r.calls + 1 END
  RETURNING calls INTO v_calls;
  -- 20 calls/min x 500 rows = 10k rows/min, ~20x the steady-state flush rate
  -- of a 45 s timer, so a backlog drain never trips it.
  IF v_calls > 20 THEN
    RAISE EXCEPTION 'RSSI batch rate limit' USING ERRCODE = '54000';
  END IF;

  IF jsonb_array_length(p_samples) = 0 THEN
    RETURN 0;
  END IF;

  INSERT INTO public.rssi_samples
      (user_id, device_id, platform, device_seq, at_ms,
       correlation_id, rssi, power)
  SELECT v_uid, p_device_id, p_platform,
         (s->>'device_seq')::BIGINT,
         (s->>'at_ms')::BIGINT,
         s->>'correlation_id',
         (s->>'rssi')::INT,
         s->>'power'
    FROM jsonb_array_elements(p_samples) s
  -- Column-list inference, not ON CONSTRAINT: uq_rssi_samples_device_seq is a
  -- unique INDEX, and ON CONSTRAINT only resolves table constraints.
  ON CONFLICT (user_id, device_id, device_seq) DO NOTHING;

  GET DIAGNOSTICS v_n = ROW_COUNT;
  -- Rows INSERTED, not rows offered: a full-duplicate replay returns 0, which
  -- is how the client distinguishes "already shipped" from "shipped now".
  RETURN v_n;
END;
$$;

COMMENT ON FUNCTION public.record_rssi_batch(TEXT, TEXT, JSONB) IS
  'Idempotent bulk insert of calibration RSSI samples for the calling user. Returns the number of rows actually inserted; a replayed batch returns 0.';

REVOKE ALL ON FUNCTION public.record_rssi_batch(TEXT, TEXT, JSONB)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_rssi_batch(TEXT, TEXT, JSONB)
  TO authenticated;

-- ---------------------------------------------------------------------------
-- 3. Wire the new table into the three guarantees that already shipped.
-- ---------------------------------------------------------------------------
-- Each is a full re-declaration of the current definition plus one clause;
-- Postgres has no way to add a statement to an existing function body. Same
-- approach 0037 and 0044 took to scrub_account_pii.

-- 3a. Deletion. The FK cascade covers auth.users removal, but the app-level
--     scrub runs long before that (0035: 30-day grace) and must not leave a
--     deleted account's co-location log sitting on the server.
--     Body as of 0044_evidence_preservation.sql:140, plus rssi_samples.
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

  DELETE FROM public.location_pings      WHERE user_id          = p_uid;
  DELETE FROM public.token_claims        WHERE user_id          = p_uid;
  DELETE FROM public.token_claim_history WHERE user_id          = p_uid;
  DELETE FROM public.sightings           WHERE observer_user_id = p_uid;
  DELETE FROM public.beacon_token_batch  WHERE user_id          = p_uid;
  DELETE FROM public.device_attestations WHERE user_id          = p_uid;
  DELETE FROM public.device_push_tokens  WHERE user_id          = p_uid;
  DELETE FROM public.notification_outbox WHERE user_id          = p_uid;
  DELETE FROM public.photo_verifications WHERE user_id          = p_uid;
  DELETE FROM public.rssi_samples        WHERE user_id          = p_uid;  -- 0056

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

-- 3b. Right of access. Omitting this table would make the export incomplete for
--     exactly the users who have the most sensitive rows on the server.
--     Body as of 0036_data_export.sql:22, plus rssi_samples.
--     Volume note: bounded by the 30-day sweep in 3c and by the fact that
--     uploads only happen under INRANGE_CALIB_SCAN. Discloses nothing the
--     caller cannot already SELECT under the RLS policy above.
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

    -- Registered push destinations, by platform only -- the token itself is a
    -- device credential, not user-facing data.
    'push_devices', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'platform', d.platform, 'created_at', d.created_at))
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

-- 3c. Retention. 30 days on received_at.
--     Longer than the 7-day local prune (local_db.dart:74) on purpose — the
--     whole point of shipping is that a walk stays extractable after the phone
--     has pruned it — and far shorter than the sightings/location_pings 24 h
--     rule is short, because these rows are lab data with a known lifetime
--     rather than live product data. Rotate this number if calibration uploads
--     are ever enabled for general users.
--     Body as of 0048_gps_scope_and_retention.sql:175, plus rssi_samples.
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
  ELSE
    DELETE FROM public.token_claims
     WHERE valid_until < NOW() - INTERVAL '30 minutes';

    DELETE FROM public.sightings
     WHERE observed_at < NOW() - INTERVAL '24 hours';

    DELETE FROM public.location_pings
     WHERE created_at < NOW() - INTERVAL '24 hours';

    DELETE FROM public.token_claim_history
     WHERE valid_until < NOW() - INTERVAL '24 hours';

    -- 0056
    DELETE FROM public.rssi_samples
     WHERE received_at < NOW() - INTERVAL '30 days';
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

COMMIT;
