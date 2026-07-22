-- 0045_withdrawal_effectiveness.sql
--
-- Withdrawal must be EFFECTIVE, not just recorded. The 2026-07-22 device audit
-- showed 0039/0044's withdraw_consent only did real cleanup for location:
-- withdrawing photo consent left the photo, verification, and discoverability
-- live; withdrawing BLE consent left tokens and sightings; and require_consent
-- no-oped on an explicit withdrawal while enforce_consent=0 — the rollout flag
-- neutralized a recorded "no", which is exactly backwards (GDPR Art. 7(3),
-- NJDPA 15-day revocation; we take effect immediately).
--
-- Owner product decisions implemented here:
--   * photo_processing withdrawal: drop discoverability + verification, cancel
--     pending checks, delete user-facing photo assets. Re-entry = new upload
--     and a new verification pass.
--   * ble_proximity withdrawal: revoke active tokens, purge unprocessed
--     sightings (both BY the user and OF the user's tokens), reject further
--     BLE writes. Historical encounters follow normal retention.
--   * sensitive_profile withdrawal: out of discovery/matching until re-granted.
--   * An explicit withdrawal denies access EVEN WHILE enforce_consent=0.
--   * An approved photo_verifications row matching the CURRENT photo is the
--     source of truth for discoverability — never the denormalized boolean.
--
-- Legal-hold doctrine unchanged (0037/0044): destructive steps are DEFERRED,
-- not refused, while a hold is active; visibility changes apply immediately.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Explicit-withdrawal state, distinct from never-asked. "No active grant
--    but at least one record" can only mean every grant was withdrawn.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.consent_withdrawn(p_uid UUID, p_purpose TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT NOT public.has_consent(p_uid, p_purpose)
     AND EXISTS (
       SELECT 1 FROM public.consent_records
        WHERE user_id = p_uid AND purpose = p_purpose
     );
$$;

REVOKE ALL ON FUNCTION public.consent_withdrawn(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.consent_withdrawn(UUID, TEXT) TO authenticated, service_role;

COMMENT ON FUNCTION public.consent_withdrawn IS
  'TRUE only when the user has explicitly withdrawn a purpose and not re-granted it. Never-asked users return FALSE — the enforce_consent rollout flag governs them, not this.';

-- ---------------------------------------------------------------------------
-- 2. require_consent v2: a recorded withdrawal is honored unconditionally.
--    enforce_consent remains a ROLLOUT flag for clients that were never asked;
--    it must not neutralize an explicit "no".
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.require_consent(p_uid UUID, p_purpose TEXT)
RETURNS VOID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF public.consent_withdrawn(p_uid, p_purpose) THEN
    RAISE EXCEPTION 'Consent required for % (withdrawn)', p_purpose
      USING ERRCODE = '42501';
  END IF;
  IF COALESCE((SELECT value_num FROM public.app_settings WHERE key = 'enforce_consent'), 0) >= 1
     AND NOT public.has_consent(p_uid, p_purpose) THEN
    RAISE EXCEPTION 'Consent required for %', p_purpose USING ERRCODE = '42501';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.require_consent(UUID, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.require_consent(UUID, TEXT) TO service_role;

COMMENT ON FUNCTION public.require_consent IS
  'Gate helper. Explicit withdrawal denies unconditionally; never-asked users are gated only once app_settings.enforce_consent = 1.';

-- ---------------------------------------------------------------------------
-- 3. withdraw_consent v3: per-purpose effectiveness.
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

  -- Withdrawing consent must stop the processing, not just record a
  -- preference. Destructive steps are deferred (not refused) under an active
  -- legal hold — the subject of a preservation hold must not destroy evidence
  -- with a toggle (T25); the hold-aware sweeps complete deletion on release.

  IF p_purpose IN ('precise_location', 'background_location') AND NOT v_held THEN
    DELETE FROM public.location_pings WHERE user_id = v_uid;
  END IF;

  IF p_purpose = 'ble_proximity' AND NOT v_held THEN
    -- Sightings OF this user's advertised tokens first — the join needs the
    -- claims that the last statement deletes.
    DELETE FROM public.sightings s
     WHERE s.observed_token IN
           (SELECT token FROM public.token_claims WHERE user_id = v_uid);
    DELETE FROM public.sightings WHERE observer_user_id = v_uid;
    DELETE FROM public.token_claims WHERE user_id = v_uid;
  END IF;

  IF p_purpose = 'photo_processing' THEN
    -- Visibility and verification go immediately, hold or no hold: the object
    -- paths survive in photo_verifications and, under a hold, the objects
    -- themselves stay in storage, so nothing evidentiary is lost here.
    UPDATE public.profiles
       SET photo_urls = ARRAY[]::TEXT[],
           is_photo_verified = FALSE,
           photo_verification_status = 'pending'
     WHERE id = v_uid;
    -- Cancel checks in flight; keep terminal rows as the audit trail.
    UPDATE public.photo_verifications
       SET state = 'rejected',
           review_notes = COALESCE(review_notes || '; ', '')
                          || 'cancelled: photo_processing consent withdrawn',
           decided_at = NOW()
     WHERE user_id = v_uid
       AND state IN ('pending_upload', 'ai_review', 'ai_passed', 'manual_review');
    -- Physical erasure of the user-facing assets (profile buckets only; chat
    -- media belongs to conversations, not this purpose). Deferred under hold.
    IF NOT v_held THEN
      INSERT INTO public.storage_deletion_queue (user_id, bucket_id, object_name)
      SELECT v_uid, o.bucket_id, o.name
        FROM storage.objects o
       WHERE o.bucket_id IN ('profile_photos', 'verified_photos')
         AND (storage.foldername(o.name))[1] = v_uid::TEXT
      ON CONFLICT (bucket_id, object_name) DO NOTHING;
    END IF;
  END IF;

  -- sensitive_profile needs no deletion here: is_discoverable_user() denies
  -- discovery/matching the moment the withdrawal is recorded (below).

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.withdraw_consent(TEXT) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.withdraw_consent(TEXT) FROM PUBLIC, anon;

-- ---------------------------------------------------------------------------
-- 4. is_discoverable_user v2: an approved verification row for a photo the
--    profile CURRENTLY references is the source of truth; the denormalized
--    is_photo_verified boolean is no longer consulted (prod had 7 discoverable
--    profiles whose boolean said verified with no approved row behind it).
--    Explicitly withdrawn sensitive_profile / photo_processing consent also
--    removes the account from discovery until re-granted.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_discoverable_user(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = p_user_id
      AND p.is_active = TRUE
      AND COALESCE(p.is_paused, FALSE) = FALSE
      AND p.deleted_at IS NULL
      AND COALESCE(p.is_incognito, FALSE) = FALSE
      AND COALESCE(p.age_verified, FALSE) = TRUE
      AND p.dob <= CURRENT_DATE - INTERVAL '18 years'
      AND COALESCE(array_length(p.photo_urls, 1), 0) > 0
      AND EXISTS (
        SELECT 1 FROM public.photo_verifications pv
        WHERE pv.user_id = p.id
          AND pv.state = 'approved'
          AND pv.photo_path = ANY(p.photo_urls)
      )
  )
  AND NOT public.consent_withdrawn(p_user_id, 'sensitive_profile')
  AND NOT public.consent_withdrawn(p_user_id, 'photo_processing');
$$;

COMMIT;
