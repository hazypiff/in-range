-- 0035_account_deletion_completeness.sql
--
-- Makes "delete my account" actually delete the account.
--
-- WHY (privacy audit 2026-07-19):
--   The previous request_account_deletion() was a partial soft-delete. It
--   scrubbed display_name/bio/photo_urls/interests but LEFT IN PLACE:
--     * sexual_preference  <- regulated as sensitive/special-category data
--     * dob                <- regulated PII, and the age-assurance input
--     * email_hint / phone_hint / neighborhood
--     * the auth.users row, chat message bodies, and storage objects
--   Verified against production before this migration: 4 of 4 soft-deleted
--   profiles still carried sexual_preference and dob.
--
--   There was also no hard-purge path at all, and one could not simply be
--   added: matches.user_a/user_b, messages.sender_id, ad_impressions.user_id
--   and ai_events.user_id are ON DELETE NO ACTION, so DELETE FROM auth.users
--   raises a foreign-key violation for any user who ever matched or chatted.
--   purge_deleted_accounts() below clears those dependents in FK order first.
--
-- MODEL: two phase.
--   1. request_account_deletion() -- synchronous, irreversible PII scrub.
--      Every regulated field is erased at request time, not at purge time,
--      so the grace window never retains sensitive data.
--   2. purge_deleted_accounts(grace) -- removes the residual pseudonymous
--      rows and the auth.users row after the grace period. Wired into
--      run_maintenance(), which already runs every 15 minutes via pg_cron.
--
--   Because phase 1 is irreversible there is deliberately NO account
--   restore. "Deactivate" is a separate concept (is_paused) and remains.

BEGIN;

-- dob must be nullable for deletion to erase it. This does NOT relax the
-- app-level requirement: upsert_profile() still raises 'Date of birth
-- required' when a live profile omits it.
ALTER TABLE public.profiles ALTER COLUMN dob DROP NOT NULL;

-- Retention knob. Purge runs once a profile has been deleted for this long.
INSERT INTO public.app_settings (key, value_num)
VALUES ('deletion_grace_days', 30)
ON CONFLICT (key) DO NOTHING;

CREATE INDEX IF NOT EXISTS idx_profiles_deleted_at
  ON public.profiles (deleted_at) WHERE deleted_at IS NOT NULL;

-- Storage objects belonging to deleted accounts. SQL cannot delete these
-- directly (Supabase blocks DELETE on storage.objects), so deletion requests
-- are recorded here and drained by a service-role worker via the Storage API.
-- That worker is drainStorageDeletionQueue() in the `maintenance` Edge
-- Function, on the same 15-minute cadence; until it runs, photos of deleted
-- accounts remain in the buckets, so it is the step that actually completes an
-- erasure request. Rows are kept after deletion, with deleted_at stamped, as
-- the audit trail proving the erasure happened.
CREATE TABLE IF NOT EXISTS public.storage_deletion_queue (
  id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id      UUID NOT NULL,
  bucket_id    TEXT NOT NULL,
  object_name  TEXT NOT NULL,
  requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at   TIMESTAMPTZ,
  last_error   TEXT,
  UNIQUE (bucket_id, object_name)
);

CREATE INDEX IF NOT EXISTS idx_storage_deletion_queue_pending
  ON public.storage_deletion_queue (requested_at) WHERE deleted_at IS NULL;

ALTER TABLE public.storage_deletion_queue ENABLE ROW LEVEL SECURITY;
-- No policies: service_role bypasses RLS, app users have no access at all.
REVOKE ALL ON TABLE public.storage_deletion_queue FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.storage_deletion_queue TO service_role;

COMMENT ON TABLE public.storage_deletion_queue IS
  'Storage objects owned by deleted accounts, pending erasure through the Storage API by a service-role worker. deleted_at stamps completion.';

-- ---------------------------------------------------------------------------
-- Phase 1 helper: erase every piece of regulated data we hold for one user.
-- Split out from the RPC so the backfill and the purge can reuse it.
-- ---------------------------------------------------------------------------
-- Dropped first so this migration stays re-appliable: 0037 redefines this
-- function as RETURNS BOOLEAN, and Postgres will not change a return type in
-- place. Without the drop, replaying the migration set fails here.
DROP FUNCTION IF EXISTS public.scrub_account_pii(UUID);

CREATE OR REPLACE FUNCTION public.scrub_account_pii(p_uid UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF p_uid IS NULL THEN
    RAISE EXCEPTION 'scrub_account_pii requires a user id';
  END IF;

  UPDATE public.profiles SET
    display_name              = 'Deleted user',
    bio                       = NULL,
    dob                       = NULL,   -- regulated PII
    gender                    = NULL,   -- sensitive
    sexual_preference         = NULL,   -- special-category / sensitive
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

  -- Proximity + beacon telemetry: no reason to retain any of it.
  DELETE FROM public.location_pings      WHERE user_id          = p_uid;
  DELETE FROM public.token_claims        WHERE user_id          = p_uid;
  DELETE FROM public.token_claim_history WHERE user_id          = p_uid;
  DELETE FROM public.sightings           WHERE observer_user_id = p_uid;
  DELETE FROM public.beacon_token_batch  WHERE user_id          = p_uid;
  DELETE FROM public.device_attestations WHERE user_id          = p_uid;

  -- Device / delivery identifiers.
  DELETE FROM public.device_push_tokens  WHERE user_id = p_uid;
  DELETE FROM public.notification_outbox WHERE user_id = p_uid;

  -- Face/photo verification artifacts.
  DELETE FROM public.photo_verifications WHERE user_id = p_uid;

  -- Stored files. Supabase forbids DELETE on storage.objects from SQL
  -- ("Direct deletion from storage tables is not allowed. Use the Storage
  -- API instead."), so we enqueue the objects and a service-role worker
  -- drains the queue through the Storage API. Path convention is <uid>/...
  -- for profile + verified photos and <match_id>/<uid>/... for chat media
  -- (see the 0019 storage policies).
  INSERT INTO public.storage_deletion_queue (user_id, bucket_id, object_name)
  SELECT p_uid, o.bucket_id, o.name
    FROM storage.objects o
   WHERE (o.bucket_id IN ('profile_photos', 'verified_photos')
            AND (storage.foldername(o.name))[1] = p_uid::TEXT)
      OR (o.bucket_id = 'chat_media'
            AND (storage.foldername(o.name))[2] = p_uid::TEXT)
  ON CONFLICT (bucket_id, object_name) DO NOTHING;

  -- Chat bodies are the sender's personal data, but the rows are load-bearing
  -- for the counterpart's thread. Redact content, keep the shell.
  -- CASE keeps messages_payload_check satisfied: 'text' needs non-empty
  -- content, media types do not.
  UPDATE public.messages
     SET content  = CASE WHEN message_type = 'text' THEN '[deleted]' ELSE NULL END,
         metadata = NULL
   WHERE sender_id = p_uid;

  -- Analytics rows survive de-identified rather than being destroyed.
  UPDATE public.ad_impressions SET user_id = NULL WHERE user_id = p_uid;
  UPDATE public.ai_events      SET user_id = NULL WHERE user_id = p_uid;
END;
$$;

COMMENT ON FUNCTION public.scrub_account_pii IS
  'Irreversibly erases all regulated personal data for one user. Called by request_account_deletion(); reused by purge and backfill.';

REVOKE ALL ON FUNCTION public.scrub_account_pii(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.scrub_account_pii(UUID) TO service_role;

-- ---------------------------------------------------------------------------
-- Phase 1 RPC: what the app calls. Self-service, caller can only delete self.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.request_account_deletion()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;
  PERFORM public.scrub_account_pii(v_uid);
END;
$$;

COMMENT ON FUNCTION public.request_account_deletion IS
  'User-initiated account deletion. Erases all regulated PII synchronously and irreversibly; residual pseudonymous rows and the auth.users row are removed later by purge_deleted_accounts().';

GRANT EXECUTE ON FUNCTION public.request_account_deletion() TO authenticated;

-- ---------------------------------------------------------------------------
-- Phase 2: hard purge after the grace window.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.purge_deleted_accounts(p_grace INTERVAL DEFAULT NULL)
RETURNS INT
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
    SELECT id FROM public.profiles
     WHERE deleted_at IS NOT NULL
       AND deleted_at < NOW() - v_grace
  LOOP
    -- Re-scrub defensively: covers rows soft-deleted by an older client and
    -- anything written during the grace window.
    PERFORM public.scrub_account_pii(v_uid);

    -- Clear ON DELETE NO ACTION dependents in FK order, or the auth.users
    -- delete below fails. messages cascade from matches.
    DELETE FROM public.reports WHERE reporter_id = v_uid OR reported_id = v_uid;
    DELETE FROM public.messages WHERE sender_id = v_uid;
    DELETE FROM public.matches  WHERE user_a = v_uid OR user_b = v_uid;

    -- Everything else is ON DELETE CASCADE from auth.users.
    DELETE FROM auth.users WHERE id = v_uid;

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION public.purge_deleted_accounts IS
  'Hard-deletes accounts whose grace window has elapsed. Clears NO ACTION dependents (reports, messages, matches) before removing auth.users.';

REVOKE ALL ON FUNCTION public.purge_deleted_accounts(INTERVAL) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_deleted_accounts(INTERVAL) TO service_role;

-- ---------------------------------------------------------------------------
-- Wire purge into the existing 15-minute maintenance job.
-- ---------------------------------------------------------------------------
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
BEGIN
  PERFORM public.cleanup_ephemeral_data();
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
    'ran_at', NOW()
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- Backfill: remediate accounts deleted under the old partial scrub.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_uid UUID;
  v_n   INT := 0;
BEGIN
  FOR v_uid IN SELECT id FROM public.profiles WHERE deleted_at IS NOT NULL
  LOOP
    -- Replay safety: on a re-apply after 0037 exists, this migration briefly
    -- reinstalls the hold-BLIND scrub above, so an unguarded backfill here
    -- would erase the PII of a legally-held account (§2258A spoliation) before
    -- 0037 re-applies the hold-aware version. Skip held accounts. On the first
    -- forward apply legal_holds does not exist yet, so to_regclass short-
    -- circuits and every deleted profile is scrubbed as intended (no hold can
    -- exist before 0037).
    IF to_regclass('public.legal_holds') IS NOT NULL
       AND EXISTS (
         SELECT 1 FROM public.legal_holds h
          WHERE h.user_id = v_uid
            AND h.released_at IS NULL
            AND (h.expires_at IS NULL OR h.expires_at > NOW())
       ) THEN
      CONTINUE;
    END IF;
    PERFORM public.scrub_account_pii(v_uid);
    v_n := v_n + 1;
  END LOOP;
  RAISE NOTICE 'Backfill: re-scrubbed % previously soft-deleted profile(s)', v_n;
END;
$$;

COMMIT;
