-- #6 step 3 (Task C) — server scaffold for App Attest / Play Integrity.
--
-- This is the SERVER half only, and it is inert until turned on. The actual
-- cryptographic verification (Apple App Attest CBOR + root CA chain; Google Play
-- Integrity decrypt/verify) must happen in a Supabase Edge Function that makes
-- outbound calls — it CANNOT be done in a SQL RPC (pg_net is not installed, and
-- attestation verification needs platform SDK/keys). That Edge Function, after
-- verifying, calls record_device_attestation() (service role) to record the
-- verdict; issue_token_batch then requires a fresh attestation when the
-- `require_attestation` flag is on.
--
-- Non-breaking rollout, mirroring enforce_batch_tokens (step 2):
--   flag defaults 0 -> issue_token_batch behaves exactly as before. After the
--   verifier + attesting client ship to devices, flip to 1 (a data change, no
--   migration) to require attestation. Rollback: set it back to 0.
--
-- What remains for whoever picks up Task C: (a) the Edge Function verifier,
-- (b) the client obtaining an App Attest assertion / Play Integrity token at
-- batch-fetch time and routing it to that verifier. Table + gate + writer +
-- flag + test are done here.

-- Enforcement flag — OFF by default.
INSERT INTO public.app_settings (key, value_num) VALUES ('require_attestation', 0)
ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.device_attestations (
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  platform    TEXT NOT NULL CHECK (platform IN ('ios','android')),
  verdict     TEXT NOT NULL,                 -- e.g. 'pass' / integrity summary
  verified_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at  TIMESTAMPTZ NOT NULL,          -- attestation freshness window
  detail      JSONB,                         -- verifier metadata (key id, flags)
  PRIMARY KEY (user_id, platform)
);
CREATE INDEX IF NOT EXISTS idx_device_attestations_fresh
  ON public.device_attestations (user_id, expires_at DESC);
ALTER TABLE public.device_attestations ENABLE ROW LEVEL SECURITY;
-- RPC/service only; no client role reads or writes it.
REVOKE ALL ON TABLE public.device_attestations FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.device_attestations TO service_role;

-- Called by the Edge Function AFTER it has cryptographically verified the
-- attestation. p_user is the id the function authenticated; service role only.
CREATE OR REPLACE FUNCTION public.record_device_attestation(
  p_user UUID,
  p_platform TEXT,
  p_verdict TEXT,
  p_ttl INTERVAL DEFAULT INTERVAL '24 hours',
  p_detail JSONB DEFAULT NULL
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
BEGIN
  IF p_user IS NULL OR p_platform NOT IN ('ios','android')
     OR NULLIF(trim(COALESCE(p_verdict,'')), '') IS NULL THEN
    RAISE EXCEPTION 'Invalid attestation' USING ERRCODE='22023';
  END IF;
  INSERT INTO public.device_attestations (user_id, platform, verdict, verified_at, expires_at, detail)
  VALUES (p_user, p_platform, p_verdict, NOW(),
          NOW() + GREATEST(INTERVAL '1 minute', LEAST(INTERVAL '30 days', COALESCE(p_ttl, INTERVAL '24 hours'))),
          p_detail)
  ON CONFLICT (user_id, platform) DO UPDATE SET
    verdict = EXCLUDED.verdict, verified_at = EXCLUDED.verified_at,
    expires_at = EXCLUDED.expires_at, detail = EXCLUDED.detail;
END $$;
REVOKE ALL ON FUNCTION public.record_device_attestation(UUID, TEXT, TEXT, INTERVAL, JSONB)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_device_attestation(UUID, TEXT, TEXT, INTERVAL, JSONB) TO service_role;

-- issue_token_batch: same as 0031, plus a flag-gated attestation requirement.
CREATE OR REPLACE FUNCTION public.issue_token_batch(
  p_day DATE DEFAULT CURRENT_DATE,
  p_window_minutes INT DEFAULT 15
)
RETURNS TABLE (token TEXT, slot INT, valid_from TIMESTAMPTZ, valid_until TIMESTAMPTZ)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
#variable_conflict use_column
DECLARE
  v_uid UUID := auth.uid();
  v_window INT := LEAST(60, GREATEST(5, COALESCE(p_window_minutes, 15)));
  v_day DATE := COALESCE(p_day, CURRENT_DATE);
  v_slots INT;
  v_distinct_days INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;
  IF NOT public.current_user_can_discover() THEN
    RAISE EXCEPTION 'Complete age and photo verification before using Beacon' USING ERRCODE='42501'; END IF;
  -- #6 step 3: require a fresh, verified device attestation when enabled. OFF by
  -- default so this is non-breaking until the verifier + attesting client ship.
  IF COALESCE((SELECT value_num FROM public.app_settings WHERE key='require_attestation'), 0) >= 1
     AND NOT EXISTS (
       SELECT 1 FROM public.device_attestations da
       WHERE da.user_id = v_uid AND da.expires_at > NOW()
     ) THEN
    RAISE EXCEPTION 'Device attestation required' USING ERRCODE='42501';
  END IF;
  -- Only today or tomorrow: bounds pre-mining / fan-out of far-future batches.
  IF v_day < CURRENT_DATE OR v_day > CURRENT_DATE + 1 THEN
    RAISE EXCEPTION 'Batch day out of range' USING ERRCODE='22023'; END IF;

  -- Housekeeping + abuse guard: drop the caller's stale batches, then cap how
  -- many distinct live days one user may hold (a relay farm requesting many
  -- days of tokens would trip this).
  DELETE FROM public.beacon_token_batch WHERE user_id = v_uid AND batch_day < CURRENT_DATE - 1;
  SELECT count(DISTINCT b.batch_day) INTO v_distinct_days
  FROM public.beacon_token_batch b WHERE b.user_id = v_uid AND b.batch_day >= CURRENT_DATE;
  IF v_distinct_days >= 3 AND NOT EXISTS (
    SELECT 1 FROM public.beacon_token_batch b WHERE b.user_id = v_uid AND b.batch_day = v_day
  ) THEN
    RAISE EXCEPTION 'Too many active token batches' USING ERRCODE='54000'; END IF;

  v_slots := (1440 / v_window);   -- 96 for a 15-minute window

  -- Idempotent: ON CONFLICT keeps each slot's originally-issued token, so a
  -- re-fetch returns the SAME batch (no churn in the advertised set).
  -- gen_random_uuid() (pg_catalog, no extension dep) -> 32 lowercase hex chars =
  -- 122 bits of unguessable randomness, matching the ^[0-9a-f]{32}$ token format.
  INSERT INTO public.beacon_token_batch (token, user_id, batch_day, slot, valid_from, valid_until)
  SELECT replace(gen_random_uuid()::text, '-', ''), v_uid, v_day, g,
         (v_day::timestamptz + make_interval(mins => g * v_window)),
         (v_day::timestamptz + make_interval(mins => g * v_window + v_window + 2))
  FROM generate_series(0, v_slots - 1) AS g
  ON CONFLICT (user_id, batch_day, slot) DO NOTHING;

  RETURN QUERY
  SELECT b.token, b.slot, b.valid_from, b.valid_until
  FROM public.beacon_token_batch b
  WHERE b.user_id = v_uid AND b.batch_day = v_day
  ORDER BY b.slot;
END;
$$;
GRANT EXECUTE ON FUNCTION public.issue_token_batch(DATE, INT) TO authenticated;
