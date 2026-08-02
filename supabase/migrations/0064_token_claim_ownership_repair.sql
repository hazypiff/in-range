-- 0064_token_claim_ownership_repair.sql
--
-- Closes the squat-first residual left explicitly open by 0063. During the
-- flag-off rollout window, claim_token accepted legacy client-minted tokens.
-- That compatibility path also let user A put user B's server-issued batch
-- token into token_claims before B single-claimed it. The unique token index
-- then rejected B with 23505, while 0063's history ownership predicate made
-- the poisoned history row permanent.
--
-- The server-issued batch row is now authoritative whenever it exists,
-- independently of enforce_batch_tokens:
--   * a foreign caller receives the existing generic ownership error before
--     any claim table is mutated;
--   * the proven batch owner may remove only a foreign squat for that token;
--   * the same owner repairs a poisoned token_claim_history row atomically.
-- A foreign squat covered by an active legal hold is the one exception: both
-- rows are preserved and the claim fails with the same generic error before
-- consumed_at or either claim table changes. This follows the project's
-- existing "preservation beats erasure" invariant. Once the hold is released,
-- the next owner claim performs the normal atomic repair. If counsel later
-- requires repair during a hold, add a separately retained evidence snapshot;
-- never preserve only the poisoned history row in the live resolution path.
-- Legacy tokens that have no batch row remain accepted while the rollout flag
-- is off, preserving the intended compatibility window.
--
-- REVIEW STATUS: Kimi K3 and Claude Opus independently agreed on the ownership
-- invariant and owner-only repair shape. The exact working-tree bytes still
-- require their post-implementation review; do not infer approval from this
-- comment or from review of the earlier 0063 draft. Review sessions and
-- disagreements are recorded in LINUX_ROUND_2_PANEL_LEDGER.md.
--
-- DEPLOYMENT BLOCKER: do not deploy this migration by itself. Production was
-- verified at 0001-0055 + 0062 during the 2026-08-01 audit. Ship the complete
-- ordered 0056 -> 0064 set only after migration rehearsal, exact-patch review,
-- and the production cron preflight documented in the hardening report.

BEGIN;

CREATE OR REPLACE FUNCTION public.claim_token(
  p_token TEXT,
  p_valid_until TIMESTAMPTZ,
  p_lat DOUBLE PRECISION DEFAULT NULL,
  p_lon DOUBLE PRECISION DEFAULT NULL,
  p_range public.range_type DEFAULT 'miles_10',
  p_accuracy DOUBLE PRECISION DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_now TIMESTAMPTZ := clock_timestamp();
  v_last TIMESTAMPTZ;
  v_batch_owner UUID;
  v_in_batch BOOLEAN := FALSE;
  v_held_foreign BOOLEAN := FALSE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000';
  END IF;
  IF NOT public.current_user_can_discover() THEN
    RAISE EXCEPTION 'Complete age and photo verification before using Beacon'
      USING ERRCODE='42501';
  END IF;
  PERFORM public.require_consent(v_uid, 'ble_proximity');
  IF public.consent_withdrawn(v_uid, 'precise_location') THEN
    RAISE EXCEPTION 'Location sharing was turned off' USING ERRCODE='42501';
  END IF;
  IF p_token IS NULL OR p_token !~ '^[0-9a-f]{32}$' THEN
    RAISE EXCEPTION 'Invalid beacon token' USING ERRCODE='22023';
  END IF;
  IF p_valid_until IS NULL
     OR p_valid_until <= v_now + INTERVAL '1 minute'
     OR p_valid_until > v_now + INTERVAL '21 minutes' THEN
    RAISE EXCEPTION 'Token validity must end within 1..21 minutes'
      USING ERRCODE='22023';
  END IF;
  IF p_lat IS NULL OR p_lon IS NULL THEN
    RAISE EXCEPTION 'Fresh coordinates are required' USING ERRCODE='22023';
  END IF;
  IF p_lat NOT BETWEEN -90 AND 90 OR p_lon NOT BETWEEN -180 AND 180 THEN
    RAISE EXCEPTION 'Invalid coordinates' USING ERRCODE='22023';
  END IF;
  IF p_accuracy IS NOT NULL AND (p_accuracy < 0 OR p_accuracy > 10000) THEN
    RAISE EXCEPTION 'Invalid accuracy' USING ERRCODE='22023';
  END IF;

  -- 0064: a batch row is the authoritative ownership record even while the
  -- compatibility flag is off. Keep the row locked through repair so scheduled
  -- cleanup cannot remove the authority between this check and the writes.
  SELECT b.user_id
    INTO v_batch_owner
    FROM public.beacon_token_batch b
   WHERE b.token = lower(p_token)
   FOR KEY SHARE;

  IF v_batch_owner IS NOT NULL AND v_batch_owner <> v_uid THEN
    -- Reuse the established generic error; never disclose the owner's identity.
    -- Failing before any write also prevents consumed_at and rate-limit churn.
    RAISE EXCEPTION 'Beacon token was not issued to this account'
      USING ERRCODE='22023';
  END IF;

  v_in_batch := COALESCE(v_batch_owner = v_uid, FALSE);
  IF v_in_batch THEN
    -- Legal holds preserve both sides of the conflict. A history-only guard
    -- would leave the attacker-owned resolution row live while token_claims
    -- moved to the victim: precisely the half-repaired state this migration
    -- exists to prevent.
    SELECT EXISTS (
      SELECT 1
        FROM public.token_claims c
       WHERE c.token = lower(p_token)
         AND c.user_id <> v_uid
         AND public.has_legal_hold(c.user_id)
      UNION ALL
      SELECT 1
        FROM public.token_claim_history h
       WHERE h.token = lower(p_token)
         AND h.user_id <> v_uid
         AND public.has_legal_hold(h.user_id)
    ) INTO v_held_foreign;

    IF v_held_foreign THEN
      RAISE EXCEPTION 'Beacon token was not issued to this account'
        USING ERRCODE='22023';
    END IF;
  END IF;

  IF v_in_batch THEN
    UPDATE public.beacon_token_batch b
       SET consumed_at = COALESCE(b.consumed_at, v_now)
     WHERE b.token = lower(p_token) AND b.user_id = v_uid;
  END IF;

  IF NOT v_in_batch
     AND COALESCE((SELECT value_num FROM public.app_settings
                    WHERE key='enforce_batch_tokens'), 0) >= 1 THEN
    RAISE EXCEPTION 'Beacon token was not issued to this account'
      USING ERRCODE='22023';
  END IF;

  SELECT last_claimed_at
    INTO v_last
    FROM public.token_claims
   WHERE user_id = v_uid;
  IF v_last IS NOT NULL AND v_last > v_now - INTERVAL '5 seconds' THEN
    RAISE EXCEPTION 'Beacon claim rate limit' USING ERRCODE='54000';
  END IF;

  -- Only beacon_token_batch proves ownership strongly enough to evict a squat.
  -- These deletes and the following upserts are one transaction: any later
  -- failure rolls the repair back rather than leaving half-repaired state.
  IF v_in_batch THEN
    DELETE FROM public.token_claims
     WHERE token = lower(p_token)
       AND user_id <> v_uid
       AND NOT public.has_legal_hold(user_id);
    DELETE FROM public.token_claim_history
     WHERE token = lower(p_token)
       AND user_id <> v_uid
       AND NOT public.has_legal_hold(user_id);

    -- Close the check/delete race: a hold placed after the first check makes
    -- either guarded DELETE skip its row, and this RAISE rolls every write in
    -- the function back (including consumed_at and a one-sided delete).
    IF EXISTS (
      SELECT 1 FROM public.token_claims
       WHERE token = lower(p_token) AND user_id <> v_uid
      UNION ALL
      SELECT 1 FROM public.token_claim_history
       WHERE token = lower(p_token) AND user_id <> v_uid
    ) THEN
      RAISE EXCEPTION 'Beacon token was not issued to this account'
        USING ERRCODE='22023';
    END IF;
  END IF;

  INSERT INTO public.token_claims (
    user_id, token, valid_from, valid_until, approx_lat, approx_lon,
    range_type, accuracy_m, created_at, last_claimed_at
  )
  VALUES (
    v_uid, lower(p_token), v_now, p_valid_until, p_lat, p_lon,
    p_range, p_accuracy, v_now, v_now
  )
  ON CONFLICT (user_id) DO UPDATE SET
    token = EXCLUDED.token,
    valid_from = EXCLUDED.valid_from,
    valid_until = EXCLUDED.valid_until,
    approx_lat = EXCLUDED.approx_lat,
    approx_lon = EXCLUDED.approx_lon,
    range_type = EXCLUDED.range_type,
    accuracy_m = EXCLUDED.accuracy_m,
    last_claimed_at = EXCLUDED.last_claimed_at;

  INSERT INTO public.token_claim_history (
    token, user_id, valid_from, valid_until, approx_lat, approx_lon,
    range_type, accuracy_m, created_at
  )
  VALUES (
    lower(p_token), v_uid, v_now, p_valid_until, p_lat, p_lon,
    p_range, p_accuracy, v_now
  )
  ON CONFLICT (token) DO UPDATE SET
    valid_until = EXCLUDED.valid_until,
    approx_lat = EXCLUDED.approx_lat,
    approx_lon = EXCLUDED.approx_lon,
    range_type = COALESCE(
      EXCLUDED.range_type, public.token_claim_history.range_type
    ),
    accuracy_m = COALESCE(
      EXCLUDED.accuracy_m, public.token_claim_history.accuracy_m
    )
  WHERE public.token_claim_history.user_id = v_uid;
END;
$function$;

COMMENT ON FUNCTION public.claim_token(
  TEXT, TIMESTAMPTZ, DOUBLE PRECISION, DOUBLE PRECISION,
  public.range_type, DOUBLE PRECISION
) IS 'Claims a beacon token; server-issued batch ownership is authoritative and proven owners atomically repair pre-0064 foreign squats.';

REVOKE ALL ON FUNCTION public.claim_token(
  TEXT, TIMESTAMPTZ, DOUBLE PRECISION, DOUBLE PRECISION,
  public.range_type, DOUBLE PRECISION
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_token(
  TEXT, TIMESTAMPTZ, DOUBLE PRECISION, DOUBLE PRECISION,
  public.range_type, DOUBLE PRECISION
) TO authenticated;

COMMIT;
