-- 0060: close the native-token resolution gap (audit 2026-07-25, critical #2).
--
-- A locked iPhone's native BackgroundBeacon serves GATT reads from its
-- persisted day batch, rotating slots on its own schedule. Only Dart's
-- claim_token wrote token_claim_history — and record_sighting resolves
-- exclusively through that table — so once Dart was suspended or evicted,
-- every later slot the native side served was unresolvable: a peer could
-- hear the beacon and never map it to a person.
--
-- Fix: claim_token_batch pre-claims every still-live slot the server issued
-- to the caller (today + tomorrow, per issue_token_batch), so any token the
-- native carrier can serve is already resolvable. Rows are written WITHOUT
-- coordinates on purpose: a fix stamped at session start would make
-- correlate_encounter's 400 m plausibility veto reject real encounters after
-- the user travels (the reviewer-#7 failure shape), and NULL location is
-- both the safer product choice (a dark, locked phone records no GPS trail)
-- and handled by the veto, which only applies when a claim carries
-- coordinates. When Dart is alive and later single-claims a slot, the
-- claim_token conflict merge below fills the geo fields back in, so the
-- veto returns for the slots that have a fresh fix.

-- ---------------------------------------------------------------------------
-- 1. claim_token_batch: pre-claim the caller's own issued slots.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.claim_token_batch(
  p_range public.range_type DEFAULT 'feet_60'
)
RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_now TIMESTAMPTZ := clock_timestamp();
  v_rows INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;
  IF NOT public.current_user_can_discover() THEN
    RAISE EXCEPTION 'Complete age and photo verification before using Beacon' USING ERRCODE='42501'; END IF;
  -- Consent gate (0040), same as claim_token. No precise_location check: this
  -- function stores NO coordinates, so there is nothing location-shaped to
  -- withdraw from.
  PERFORM public.require_consent(v_uid, 'ble_proximity');

  -- Throttle: one batch claim per minute per user. Only batch-originated rows
  -- (NULL location) count, so the per-rotation single claims never trip it.
  IF EXISTS (
    SELECT 1 FROM public.token_claim_history h
    WHERE h.user_id = v_uid AND h.approx_lat IS NULL
      AND h.created_at > v_now - INTERVAL '1 minute'
  ) THEN
    RAISE EXCEPTION 'Beacon claim rate limit' USING ERRCODE='54000';
  END IF;

  -- Only tokens the server issued to THIS caller (beacon_token_batch
  -- membership) — no user can claim another's tokens, and far-future mining
  -- is already bounded by issue_token_batch's day cap. valid_from/valid_until
  -- are the slot's real window, so resolution and expiry line up with what
  -- the native carrier actually serves. ON CONFLICT DO NOTHING: a slot the
  -- live client already single-claimed keeps its location-bearing row.
  INSERT INTO public.token_claim_history
    (token, user_id, valid_from, valid_until, approx_lat, approx_lon,
     range_type, accuracy_m, created_at)
  SELECT b.token, v_uid, b.valid_from, b.valid_until, NULL, NULL,
         p_range, NULL, v_now
  FROM public.beacon_token_batch b
  WHERE b.user_id = v_uid AND b.valid_until > v_now
  ON CONFLICT (token) DO NOTHING;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows;
END;
$function$;

COMMENT ON FUNCTION public.claim_token_batch(public.range_type) IS
  'Pre-claims every still-live server-issued batch slot for the caller into token_claim_history (NULL location by design), so tokens served natively by a locked/evicted phone stay resolvable. Returns rows claimed.';

REVOKE ALL ON FUNCTION public.claim_token_batch(public.range_type)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_token_batch(public.range_type)
  TO authenticated;

-- ---------------------------------------------------------------------------
-- 2. claim_token: merge geo fields into a batch-pre-claimed row.
-- ---------------------------------------------------------------------------
-- Body is verbatim 0048 except the token_claim_history conflict clause: a
-- slot first claimed by claim_token_batch carries NULL location; when the
-- live client later single-claims that same slot with a fresh fix, fill the
-- geo fields (never overwriting existing ones) so correlate_encounter's
-- plausibility veto applies to that slot again.
CREATE OR REPLACE FUNCTION public.claim_token(p_token text, p_valid_until timestamp with time zone, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_range range_type DEFAULT 'miles_10'::range_type, p_accuracy double precision DEFAULT NULL::double precision)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_now TIMESTAMPTZ := clock_timestamp();
  v_last TIMESTAMPTZ;
  v_in_batch BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;
  IF NOT public.current_user_can_discover() THEN
    RAISE EXCEPTION 'Complete age and photo verification before using Beacon' USING ERRCODE='42501'; END IF;
  -- Consent gate (0040). No-op unless app_settings.enforce_consent = 1.
  PERFORM public.require_consent(v_uid, 'ble_proximity');
  -- 0048: the consent UI scopes GPS to precise_location ("deleted after 24h").
  -- Beacon mandatorily uploads coordinates, so a user who withdrew precise
  -- location must not keep feeding GPS through it, even while ble_proximity
  -- is still granted. Explicit withdrawal denies regardless of enforce_consent.
  IF public.consent_withdrawn(v_uid, 'precise_location') THEN
    RAISE EXCEPTION 'Location sharing was turned off' USING ERRCODE='42501'; END IF;
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
  ON CONFLICT (token) DO UPDATE SET
    valid_until = EXCLUDED.valid_until,
    -- 0060: fill geo fields on a batch-pre-claimed (NULL-location) row; never
    -- blank out a fix an earlier single claim already wrote.
    approx_lat = COALESCE(EXCLUDED.approx_lat, public.token_claim_history.approx_lat),
    approx_lon = COALESCE(EXCLUDED.approx_lon, public.token_claim_history.approx_lon),
    range_type = COALESCE(EXCLUDED.range_type, public.token_claim_history.range_type),
    accuracy_m = COALESCE(EXCLUDED.accuracy_m, public.token_claim_history.accuracy_m);
END;
$function$;
