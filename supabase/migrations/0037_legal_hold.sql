-- 0037_legal_hold.sql
--
-- Preservation holds that survive retention purging.
--
-- WHY: 18 U.S.C. §2258A(h)(1) imposes a ONE YEAR preservation obligation the
-- moment a CyberTipline report is filed with NCMEC. 0035 wired
-- purge_deleted_accounts() into run_maintenance(), which pg_cron runs every 15
-- minutes. Without a hold, the sequence
--     incident -> report filed -> subject deletes their account -> 30d grace
--     -> automated purge
-- destroys evidence we are federally obligated to preserve, automatically and
-- with no human in the loop. The retention machinery we built for privacy
-- becomes a spoliation mechanism.
--
-- Note the direction of the conflict: this is preservation BEATING erasure, and
-- every privacy regime we are subject to allows exactly that. GDPR Art. 17(3)(b)
-- excepts processing necessary for compliance with a legal obligation; the US
-- state statutes carry equivalent carve-outs. So a held account's deletion
-- request is DEFERRED, not refused -- deleted_at is still recorded, and the
-- scrub plus purge run automatically once the hold is released.
--
-- Holds are service-role only. A user must never be able to see, place, or
-- lift a hold on themselves: telling the subject of a CyberTipline report that
-- they are under one both tips them off and risks obstruction.

BEGIN;

CREATE TABLE IF NOT EXISTS public.legal_holds (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id     UUID NOT NULL,
  reason      TEXT NOT NULL CHECK (reason IN (
                'cybertipline_2258a',   -- §2258A(h)(1), 1 year minimum
                'ncii_takedown',        -- TAKE IT DOWN Act request record
                'law_enforcement',      -- preservation letter / subpoena
                'litigation_hold',
                'safety_investigation'
              )),
  detail      TEXT,
  placed_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  placed_by   TEXT NOT NULL,
  expires_at  TIMESTAMPTZ,            -- NULL = indefinite, release manually
  released_at TIMESTAMPTZ,
  released_by TEXT
);

-- No FK to auth.users on purpose: the hold must outlive the account row, and a
-- CASCADE here would let the very purge this table exists to block delete the
-- record of why it was blocked.

CREATE INDEX IF NOT EXISTS idx_legal_holds_active
  ON public.legal_holds (user_id) WHERE released_at IS NULL;

ALTER TABLE public.legal_holds ENABLE ROW LEVEL SECURITY;
-- No policies: service_role bypasses RLS; app users have no access at all.
REVOKE ALL ON TABLE public.legal_holds FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.legal_holds TO service_role;

COMMENT ON TABLE public.legal_holds IS
  'Preservation holds that block scrub and purge. §2258A(h)(1) requires 1 year from a CyberTipline filing. Service-role only -- the subject must never learn of a hold.';

-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.has_legal_hold(p_uid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.legal_holds h
     WHERE h.user_id = p_uid
       AND h.released_at IS NULL
       AND (h.expires_at IS NULL OR h.expires_at > NOW())
  );
$$;

REVOKE ALL ON FUNCTION public.has_legal_hold(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.has_legal_hold(UUID) TO service_role;

-- Convenience writer so the runbook is one call and the 1-year default for a
-- CyberTipline filing cannot be got wrong by hand.
CREATE OR REPLACE FUNCTION public.place_legal_hold(
  p_uid    UUID,
  p_reason TEXT,
  p_by     TEXT,
  p_detail TEXT DEFAULT NULL,
  p_expires TIMESTAMPTZ DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_id BIGINT;
  v_expires TIMESTAMPTZ;
BEGIN
  -- §2258A(h)(1) is one year from the report. Default it rather than trusting
  -- whoever is doing incident response at the time to remember.
  v_expires := COALESCE(
    p_expires,
    CASE WHEN p_reason = 'cybertipline_2258a' THEN NOW() + INTERVAL '1 year' END
  );

  INSERT INTO public.legal_holds (user_id, reason, detail, placed_by, expires_at)
  VALUES (p_uid, p_reason, p_detail, p_by, v_expires)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.place_legal_hold(UUID, TEXT, TEXT, TEXT, TIMESTAMPTZ)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.place_legal_hold(UUID, TEXT, TEXT, TEXT, TIMESTAMPTZ)
  TO service_role;

-- ---------------------------------------------------------------------------
-- Scrub becomes hold-aware. Returns TRUE if it ran, FALSE if deferred.
--
-- 0035 declared this RETURNS VOID; Postgres will not change a return type in
-- place, so it must be dropped first. Safe: PL/pgSQL call sites are resolved
-- at runtime, not by a tracked dependency, and purge_deleted_accounts() is
-- recreated below in the same transaction.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.scrub_account_pii(UUID);

CREATE OR REPLACE FUNCTION public.scrub_account_pii(p_uid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
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
-- Purge skips held accounts entirely.
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
       AND NOT public.has_legal_hold(id)   -- preservation beats retention
  LOOP
    PERFORM public.scrub_account_pii(v_uid);

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
-- Deletion RPC: unchanged contract for the client, but now honest about
-- deferral. Still returns VOID so no client change is required.
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

  -- Record the request either way. If a hold is active the scrub no-ops and
  -- this stamp is what makes the purge fire automatically on release.
  UPDATE public.profiles
     SET deleted_at = COALESCE(deleted_at, NOW()),
         is_active  = FALSE,
         is_paused  = TRUE,
         updated_at = NOW()
   WHERE id = v_uid;

  PERFORM public.scrub_account_pii(v_uid);
END;
$$;

GRANT EXECUTE ON FUNCTION public.request_account_deletion() TO authenticated;

COMMIT;
