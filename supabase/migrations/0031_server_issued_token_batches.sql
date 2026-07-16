-- #6 step 2: server-issued opaque token batches.
--
-- Today the client MINTS its own beacon token (random bytes + a user_hash + an
-- HMAC keyed by a secret shipped in the app). The HMAC is therefore cosmetic —
-- anyone with the binary can compute it — and the client fully controls token
-- values and validity windows; claim_token (auth-gated) is the only real
-- token<->identity binding.
--
-- This migration moves token GENERATION to the server. issue_token_batch mints a
-- day's worth of opaque tokens (gen_random_uuid, 122 bits) reserved for the
-- authenticated user. The client fetches the batch once, then advertises each
-- slot's opaque token; it still calls claim_token per rotation so GPS/range stay
-- dynamic, but the token VALUE is now server-owned and unguessable. That is the
-- foundation for attesting issuance (App Attest / Play Integrity, step 3),
-- detecting token fan-out abuse (step 4), and revocation.
--
-- Rollout is non-breaking: claim_token still accepts a self-minted token while
-- the flag `enforce_batch_tokens` is 0 (default). After the batch-aware client
-- ships, flip the flag to 1 (a data change, no migration) to require batch
-- membership. Observer-side offline scanning is unchanged (resolution is still
-- via token_claim_history).

-- Enforcement flag — OFF by default so this deploy cannot break current clients.
INSERT INTO public.app_settings (key, value_num) VALUES ('enforce_batch_tokens', 0)
ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.beacon_token_batch (
  token       TEXT PRIMARY KEY,               -- opaque 32 hex chars (128-bit)
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  batch_day   DATE NOT NULL,
  slot        INT  NOT NULL,
  valid_from  TIMESTAMPTZ NOT NULL,
  valid_until TIMESTAMPTZ NOT NULL,
  consumed_at TIMESTAMPTZ,                     -- set when first claimed (observability)
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, batch_day, slot)
);
CREATE INDEX IF NOT EXISTS idx_beacon_token_batch_user_day ON public.beacon_token_batch (user_id, batch_day);
CREATE INDEX IF NOT EXISTS idx_beacon_token_batch_expiry ON public.beacon_token_batch (valid_until);
ALTER TABLE public.beacon_token_batch ENABLE ROW LEVEL SECURITY;
-- RPC-only, like sightings/token_claim_history: no direct grant to any client role.
REVOKE ALL ON TABLE public.beacon_token_batch FROM PUBLIC, anon, authenticated;

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

-- claim_token: consume the matching batch token, and (when the flag is on)
-- require the claimed token to belong to the caller's issued batch. Body is
-- otherwise identical to 0028.
CREATE OR REPLACE FUNCTION public.claim_token(
  p_token TEXT, p_valid_until TIMESTAMPTZ,
  p_lat DOUBLE PRECISION DEFAULT NULL, p_lon DOUBLE PRECISION DEFAULT NULL,
  p_range public.range_type DEFAULT 'miles_10', p_accuracy DOUBLE PRECISION DEFAULT NULL
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_now TIMESTAMPTZ := clock_timestamp();
  v_last TIMESTAMPTZ;
  v_in_batch BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;
  IF NOT public.current_user_can_discover() THEN
    RAISE EXCEPTION 'Complete age and photo verification before using Beacon' USING ERRCODE='42501'; END IF;
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
  ON CONFLICT (token) DO UPDATE SET valid_until = EXCLUDED.valid_until;
END;
$$;
GRANT EXECUTE ON FUNCTION public.claim_token(
  TEXT, TIMESTAMPTZ, DOUBLE PRECISION, DOUBLE PRECISION, public.range_type, DOUBLE PRECISION
) TO authenticated;
