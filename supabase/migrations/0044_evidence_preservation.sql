-- 0044_evidence_preservation.sql
--
-- Close the three remaining evidence-destruction paths found by the
-- 2026-07-22 re-audit. The 0037/0041 legal-hold system protected the held
-- account's own scrub/purge, but held or soon-to-be-held evidence could still
-- be destroyed three other ways:
--
--   H1  The subject self-deletes BEFORE a reviewer escalates: scrub runs
--       synchronously at request time, redacting their messages (the
--       enticement content) and queueing their media for deletion. The hold
--       placed later at escalation preserves only wreckage.
--   H2  A THIRD PARTY's routine purge destroys held evidence: purging the
--       reporter deletes their reports (whose details are evidence) and their
--       matches — which CASCADE-deletes the HELD subject's side of the shared
--       conversation (messages.match_id ON DELETE CASCADE).
--   M3  cleanup_ephemeral_data() was entirely hold-blind: a held subject's
--       location_pings / sightings / token_claims — material to a
--       proximity-app investigation — were purged at 24-48h regardless.
--
-- Approach: report-scoped evidence snapshots, not broader holds. Auto-holding
-- every reported account would let anyone freeze a stranger's deletion by
-- filing a report; instead, deletion proceeds and exactly the evidence at
-- risk (the report + the conversation between the pair) is snapshotted into a
-- service-role-only table first. Data minimization and preservation both hold.
--
-- Also here (audit LOW/M2/L1/L2):
--   * withdraw_consent no longer deletes location_pings under an active hold
--     (withdrawal is still recorded; deletion completes when the hold lifts
--     via the now hold-aware cleanup).
--   * scrub_account_pii withdraws all active consents (a "deleted" account
--     must not keep live consent grants through the 30-day grace).
--   * purge clears the purged user's media_hashes rows and de-identifies
--     their ncii_reports authorship (both are bare UUIDs with no FK).
--   * v_report_triage's §2258A prompt now includes 'other' — the realistic
--     enticement channel the runbook already tells reviewers to read first.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Evidence snapshots. Service-role only; survives deletion of the report
--    row (report_id SET NULL) and of either account (bare UUIDs, no FK).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.report_evidence (
  id            BIGSERIAL PRIMARY KEY,
  report_id     BIGINT REFERENCES public.reports(id) ON DELETE SET NULL,
  subject_user  UUID,          -- the reported account
  reporter_user UUID,
  captured_by   TEXT NOT NULL, -- 'scrub' (deletion raced review) | 'escalation'
  captured_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  payload       JSONB NOT NULL
);

-- One snapshot per (report, trigger); replays/reruns are no-ops.
CREATE UNIQUE INDEX IF NOT EXISTS idx_report_evidence_once
  ON public.report_evidence (report_id, captured_by)
  WHERE report_id IS NOT NULL;

ALTER TABLE public.report_evidence ENABLE ROW LEVEL SECURITY;
-- No policies: like cybertipline_queue, the subject must never see this.
REVOKE ALL ON TABLE public.report_evidence FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, DELETE ON TABLE public.report_evidence TO service_role;
REVOKE ALL ON SEQUENCE public.report_evidence_id_seq FROM PUBLIC, anon, authenticated;

COMMENT ON TABLE public.report_evidence IS
  'Report-scoped evidence snapshots taken before any erasure path can destroy them. Service-role only. Retention: 1 year via cleanup_ephemeral_data unless held or tied to an unexpired CyberTipline obligation.';

-- ---------------------------------------------------------------------------
-- 2. The snapshot itself: the report row + every message between the pair,
--    with media storage paths and content hashes. (The media bytes live in
--    storage and follow their own lifecycle; the sha256 proves what was
--    there and ties into the media_hashes fan-out.)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.snapshot_report_evidence(
  p_report_id BIGINT,
  p_trigger   TEXT
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  r      RECORD;
  v_msgs JSONB;
  v_id   BIGINT;
BEGIN
  SELECT * INTO r FROM public.reports WHERE id = p_report_id;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'message_id',   m.id,
           'match_id',     m.match_id,
           'sender_id',    m.sender_id,
           'message_type', m.message_type,
           'content',      m.content,
           'metadata',     m.metadata,
           'created_at',   m.created_at,
           'sha256',       mh.sha256
         ) ORDER BY m.created_at), '[]'::jsonb)
    INTO v_msgs
    FROM public.messages m
    JOIN public.matches mt ON mt.id = m.match_id
    LEFT JOIN public.media_hashes mh
      ON mh.bucket_id = 'chat_media'
     AND mh.object_name = m.metadata->>'storage_path'
   WHERE (mt.user_a = r.reporter_id AND mt.user_b = r.reported_id)
      OR (mt.user_a = r.reported_id AND mt.user_b = r.reporter_id);

  INSERT INTO public.report_evidence
    (report_id, subject_user, reporter_user, captured_by, payload)
  VALUES
    (p_report_id, r.reported_id, r.reporter_id, p_trigger,
     jsonb_build_object(
       'report', jsonb_build_object(
         'id', r.id, 'reason', r.reason, 'details', r.details,
         'match_id', r.match_id, 'status', r.status,
         'created_at', r.created_at),
       'messages', v_msgs))
  ON CONFLICT (report_id, captured_by) WHERE report_id IS NOT NULL
  DO NOTHING
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.snapshot_report_evidence(BIGINT, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.snapshot_report_evidence(BIGINT, TEXT)
  TO service_role;

-- ---------------------------------------------------------------------------
-- 3. H1: scrub snapshots open reports involving the account BEFORE redacting.
--    A subject's self-deletion can no longer outrun review, and a reporter's
--    self-deletion no longer destroys what they reported.
--    Also L1: deletion withdraws every active consent.
-- ---------------------------------------------------------------------------
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

REVOKE ALL ON FUNCTION public.scrub_account_pii(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.scrub_account_pii(UUID) TO service_role;

-- ---------------------------------------------------------------------------
-- 4. H2: purge defers any account that shares a match with a HELD user —
--    deleting those matches would CASCADE away the held user's side of the
--    conversation. Deferred, not refused: it completes when the hold lifts.
--    Also L1: clear the purged user's media_hashes and ncii authorship.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.purge_deleted_accounts(p_grace INTERVAL DEFAULT NULL)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_grace INTERVAL;
  v_uid   UUID;
  v_count INT := 0;
BEGIN
  v_grace := COALESCE(
    p_grace,
    make_interval(days => COALESCE(
      (SELECT value_num::INT FROM public.app_settings WHERE key = 'deletion_grace_days'), 30))
  );

  FOR v_uid IN
    SELECT p.id FROM public.profiles p
     WHERE p.deleted_at IS NOT NULL
       AND p.deleted_at < NOW() - v_grace
       AND NOT public.has_legal_hold(p.id)   -- preservation beats retention
       AND NOT EXISTS (                       -- H2: counterpart is held
         SELECT 1 FROM public.matches m
          WHERE (m.user_a = p.id OR m.user_b = p.id)
            AND public.has_legal_hold(
                  CASE WHEN m.user_a = p.id THEN m.user_b ELSE m.user_a END))
  LOOP
    PERFORM public.scrub_account_pii(v_uid);

    DELETE FROM public.media_hashes WHERE user_id = v_uid;
    UPDATE public.ncii_reports SET reporter_user_id = NULL
     WHERE reporter_user_id = v_uid;

    DELETE FROM public.reports  WHERE reporter_id = v_uid OR reported_id = v_uid;
    DELETE FROM public.messages WHERE sender_id = v_uid;
    DELETE FROM public.matches  WHERE user_a = v_uid OR user_b = v_uid;
    DELETE FROM auth.users WHERE id = v_uid;

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.purge_deleted_accounts(INTERVAL) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_deleted_accounts(INTERVAL) TO service_role;

-- ---------------------------------------------------------------------------
-- 5. Escalation snapshots too (belt and suspenders with the hold): from this
--    moment the evidence exists independently of every row lifecycle.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.escalate_report(
  p_report_id BIGINT,
  p_category  TEXT,
  p_by        TEXT,
  p_detail    TEXT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_subject UUID;
  v_hold    BIGINT;
  v_queue   BIGINT;
BEGIN
  SELECT reported_id INTO v_subject FROM public.reports WHERE id = p_report_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No such report: %', p_report_id USING ERRCODE = '22023';
  END IF;

  -- 1. Preserve FIRST, before anything else can race a deletion. §2258A(h)(1)
  --    is 1 year from filing; we hold from confirmation, which is stricter.
  --    place_legal_hold defaults a cybertipline_2258a hold to 1 year.
  v_hold := public.place_legal_hold(
    v_subject, 'cybertipline_2258a', p_by,
    format('report #%s (%s)', p_report_id, p_category));

  -- 1b. Snapshot the report + conversation now: no later purge of either
  --     party can destroy what the filing will rely on.
  PERFORM public.snapshot_report_evidence(p_report_id, 'escalation');

  -- 2. Record the filing obligation so it cannot be silently dropped.
  INSERT INTO public.cybertipline_queue
    (report_id, subject_id, legal_hold_id, category, detail, opened_by)
  VALUES (p_report_id, v_subject, v_hold, p_category, p_detail, p_by)
  RETURNING id INTO v_queue;

  -- 3. Move the report out of the open queue.
  UPDATE public.reports
     SET status = 'actioned', resolved_at = NOW()
   WHERE id = p_report_id;

  RETURN v_queue;
END;
$$;

REVOKE ALL ON FUNCTION public.escalate_report(BIGINT,TEXT,TEXT,TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.escalate_report(BIGINT,TEXT,TEXT,TEXT) TO service_role;

-- ---------------------------------------------------------------------------
-- 6. M3: hold-aware ephemeral cleanup. The common case (no active holds) is
--    byte-for-byte the old fast path; the hold-aware predicates only run when
--    at least one active hold exists. Sightings OF a held user are found via
--    their preserved token_claims. Also enforces report_evidence retention.
-- ---------------------------------------------------------------------------
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
  ELSE
    DELETE FROM public.token_claims
     WHERE valid_until < NOW() - INTERVAL '30 minutes';

    DELETE FROM public.sightings
     WHERE observed_at < NOW() - INTERVAL '48 hours';

    DELETE FROM public.location_pings
     WHERE created_at < NOW() - INTERVAL '24 hours';
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

-- ---------------------------------------------------------------------------
-- 7. M2: consent withdrawal under an active hold records the withdrawal but
--    defers the location wipe — the subject of a preservation hold must not
--    be able to destroy their own location evidence with a toggle. The
--    hold-aware cleanup (above) completes the deletion once the hold lifts.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.withdraw_consent(p_purpose TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_hit BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  UPDATE public.consent_records
     SET withdrawn_at = NOW()
   WHERE user_id = v_uid AND purpose = p_purpose AND withdrawn_at IS NULL
  RETURNING TRUE INTO v_hit;

  -- Withdrawing location consent must actually stop the processing, not just
  -- record a preference. Delete what we hold for that purpose now — unless a
  -- legal hold requires it preserved (deferred to the hold-aware cleanup).
  IF COALESCE(v_hit, FALSE)
     AND p_purpose IN ('precise_location', 'background_location')
     AND NOT public.has_legal_hold(v_uid) THEN
    DELETE FROM public.location_pings WHERE user_id = v_uid;
  END IF;

  RETURN COALESCE(v_hit, FALSE);
END;
$$;

GRANT EXECUTE ON FUNCTION public.withdraw_consent(TEXT) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.withdraw_consent(TEXT) FROM PUBLIC, anon;

-- ---------------------------------------------------------------------------
-- 8. L2: the §2258A triage prompt now includes 'other' — the runbook's own
--    stated primary scenario (§2422(b) enticement in chat) usually arrives as
--    'other' or 'harassment', not 'underage'.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_report_triage
WITH (security_invoker = true, security_barrier = true) AS
SELECT
  r.id,
  r.created_at,
  r.reason,
  r.reported_id,
  r.match_id,
  r.details,
  -- A prompt, not a gate: these reasons MAY implicate §2258A and should be
  -- read first. The reviewer still classifies.
  (r.reason IN ('underage', 'harassment', 'inappropriate_photos', 'other')) AS review_for_2258a,
  EXISTS (SELECT 1 FROM public.cybertipline_queue q WHERE q.report_id = r.id) AS already_escalated
FROM public.reports r
WHERE r.status IN ('open', 'reviewing')
ORDER BY
  (r.reason = 'underage') DESC,   -- the explicit minor-safety signal first
  r.created_at ASC;

REVOKE ALL ON public.v_report_triage FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.v_report_triage TO service_role;

COMMIT;
