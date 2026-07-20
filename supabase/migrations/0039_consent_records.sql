-- 0039_consent_records.sql
--
-- Unbundled, purpose-scoped, revocable consent with an audit trail.
--
-- WHY: we had no consent records at all. Required by, at minimum:
--   * NJDPA (home state) -- sensitive data may not be processed without
--     consent, and "consent" expressly EXCLUDES "acceptance of a general or
--     broad terms of use or similar document that contains descriptions of
--     personal data processing along with other, unrelated information," and
--     anything "obtained through the use of dark patterns." A ToS checkbox is
--     not consent. Revocation must be honored within 15 DAYS -- tighter than
--     the 45-day norm elsewhere.
--   * Connecticut -- since 2026-07-01 the thresholds are ELIMINATED for any
--     controller processing sensitive data. One CT user puts us in full scope.
--   * FTC orders (X-Mode / InMarket) -- precise-location consent must be
--     obtained SEPARATELY FROM the privacy policy and ToS, must be
--     unavoidable, and is PURPOSE-SCOPED: consent for proximity matching does
--     not stretch to analytics or advertising.
--   * GDPR Art. 9 on any EU exposure -- explicit consent is the only realistic
--     basis for sexual orientation, and Art. 7(3) requires withdrawal to be as
--     easy as granting.
--
-- DESIGN
--   * One row PER PURPOSE. Bundling is the specific thing the statutes reject,
--     so the schema makes bundling impossible rather than merely discouraged.
--   * Append-only. Withdrawal stamps withdrawn_at on the existing row; nothing
--     is ever deleted. The audit trail IS the compliance artifact -- being able
--     to show what someone consented to, when, and to which policy version.
--   * policy_version is recorded per grant, so a material policy change can
--     invalidate prior consent and force a re-ask.
--   * Enforcement sits behind app_settings.enforce_consent (default 0), the
--     same non-breaking rollout pattern as enforce_batch_tokens and
--     require_attestation. Flipping it before the consent UI ships would lock
--     out every existing client.

BEGIN;

INSERT INTO public.app_settings (key, value_num)
VALUES ('enforce_consent', 0)
ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.consent_records (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id        UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Purposes are deliberately narrow. Adding a use means adding a purpose and
  -- asking again -- that is what "purpose-scoped" means in the FTC orders.
  purpose        TEXT NOT NULL CHECK (purpose IN (
                   'sensitive_profile',    -- gender + sexual orientation (Art. 9 / state sensitive)
                   'precise_location',     -- GPS upload for proximity matching
                   'background_location',  -- collection while app closed
                   'ble_proximity',        -- BLE scan/advertise + encounter records
                   'photo_processing'      -- profile photo storage + verification
                 )),

  granted_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  withdrawn_at   TIMESTAMPTZ,
  policy_version TEXT NOT NULL,

  -- Evidence of HOW consent was taken, for the audit trail. Not free-form:
  -- 'implied' is deliberately absent as a legal value.
  method         TEXT NOT NULL DEFAULT 'explicit_toggle'
                   CHECK (method IN ('explicit_toggle', 'explicit_dialog')),
  ui_surface     TEXT,   -- e.g. 'onboarding.consent_step'
  CHECK (withdrawn_at IS NULL OR withdrawn_at >= granted_at)
);

-- At most one ACTIVE grant per purpose; history is preserved alongside.
CREATE UNIQUE INDEX IF NOT EXISTS idx_consent_active
  ON public.consent_records (user_id, purpose) WHERE withdrawn_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_consent_user ON public.consent_records (user_id);

ALTER TABLE public.consent_records ENABLE ROW LEVEL SECURITY;

-- Users may READ their own record -- Art. 7 and every state access right make
-- "what did I agree to?" answerable. Writes go through the RPCs so the audit
-- trail cannot be forged or rewritten by the client.
DROP POLICY IF EXISTS "Users read own consent records" ON public.consent_records;
CREATE POLICY "Users read own consent records"
  ON public.consent_records FOR SELECT TO authenticated
  USING (user_id = auth.uid());

REVOKE ALL ON TABLE public.consent_records FROM PUBLIC, anon;
GRANT SELECT ON TABLE public.consent_records TO authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.consent_records TO service_role;

COMMENT ON TABLE public.consent_records IS
  'Unbundled, purpose-scoped consent. Append-only: withdrawal stamps withdrawn_at, nothing is deleted. The history is the compliance artifact.';

-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.grant_consent(
  p_purpose        TEXT,
  p_policy_version TEXT,
  p_ui_surface     TEXT DEFAULT NULL,
  p_method         TEXT DEFAULT 'explicit_toggle'
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_id  BIGINT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_policy_version IS NULL OR length(trim(p_policy_version)) = 0 THEN
    RAISE EXCEPTION 'Consent must record the policy version it was given against'
      USING ERRCODE = '22023';
  END IF;

  -- Already active for this purpose: idempotent, and do NOT restamp
  -- granted_at. The original moment of consent is the fact we must be able to
  -- evidence later.
  SELECT id INTO v_id FROM public.consent_records
   WHERE user_id = v_uid AND purpose = p_purpose AND withdrawn_at IS NULL;
  IF FOUND THEN
    RETURN v_id;
  END IF;

  INSERT INTO public.consent_records
    (user_id, purpose, policy_version, method, ui_surface)
  VALUES (v_uid, p_purpose, p_policy_version, p_method, p_ui_surface)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.grant_consent(TEXT,TEXT,TEXT,TEXT) TO authenticated;

-- ---------------------------------------------------------------------------
-- Withdrawal must be as easy as granting (Art. 7(3)); NJDPA requires effect
-- within 15 days -- we take effect immediately, which is strictly better.
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
  -- record a preference. Delete what we hold for that purpose now.
  IF COALESCE(v_hit, FALSE) AND p_purpose IN ('precise_location', 'background_location') THEN
    DELETE FROM public.location_pings WHERE user_id = v_uid;
  END IF;

  RETURN COALESCE(v_hit, FALSE);
END;
$$;

GRANT EXECUTE ON FUNCTION public.withdraw_consent(TEXT) TO authenticated;

-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.has_consent(p_uid UUID, p_purpose TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.consent_records
     WHERE user_id = p_uid AND purpose = p_purpose AND withdrawn_at IS NULL
  );
$$;

REVOKE ALL ON FUNCTION public.has_consent(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_consent(UUID, TEXT) TO authenticated, service_role;

-- What the client renders the consent screen from, and what an access request
-- is answered with.
CREATE OR REPLACE FUNCTION public.my_consents()
RETURNS TABLE (
  purpose        TEXT,
  granted        BOOLEAN,
  granted_at     TIMESTAMPTZ,
  withdrawn_at   TIMESTAMPTZ,
  policy_version TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT c.purpose, (c.withdrawn_at IS NULL), c.granted_at, c.withdrawn_at, c.policy_version
    FROM public.consent_records c
   WHERE c.user_id = auth.uid()
   ORDER BY c.purpose, c.granted_at DESC;
$$;

GRANT EXECUTE ON FUNCTION public.my_consents() TO authenticated;

-- ---------------------------------------------------------------------------
-- Enforcement, behind a flag. OFF by default: flipping it before the consent
-- UI ships would lock out every existing client.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.require_consent(p_uid UUID, p_purpose TEXT)
RETURNS VOID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF COALESCE((SELECT value_num FROM public.app_settings WHERE key = 'enforce_consent'), 0) >= 1
     AND NOT public.has_consent(p_uid, p_purpose) THEN
    RAISE EXCEPTION 'Consent required for %', p_purpose USING ERRCODE = '42501';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.require_consent(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.require_consent(UUID, TEXT) TO authenticated, service_role;

COMMENT ON FUNCTION public.require_consent IS
  'Gate helper. No-op until app_settings.enforce_consent = 1; flip only after the consent UI is live on real devices.';

-- Deletion must clear consent too -- a withdrawn/erased account has no live
-- grants. CASCADE on user_id handles purge; the scrub path needs it explicit.
COMMIT;
