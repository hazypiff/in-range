-- #13: record_sighting had a SELECT-then-INSERT dedupe (two concurrent calls
-- could both see no row and insert duplicates), and its "120/minute" rate limit
-- counted sighting ROWS by created_at — but a caller hammering one token inside
-- the 30 s dedupe window only UPDATEs the same row, so the count stayed at 1
-- while every call still ran PostGIS + correlation.
--
-- Fix: (1) one canonical row per (observer, observed_token) enforced by a unique
-- index, and an atomic INSERT ... ON CONFLICT upsert (no read-then-write race);
-- (2) a real per-user, per-minute CALL counter, incremented atomically before
-- the work, independent of row dedupe.

-- (1) Idempotency ---------------------------------------------------------------
-- Collapse any pre-existing duplicates (none in practice) keeping the latest.
DELETE FROM public.sightings s
USING public.sightings s2
WHERE s.observer_user_id = s2.observer_user_id
  AND s.observed_token = s2.observed_token
  AND (s.observed_at < s2.observed_at
       OR (s.observed_at = s2.observed_at AND s.id < s2.id));

CREATE UNIQUE INDEX IF NOT EXISTS uq_sightings_observer_token
  ON public.sightings (observer_user_id, observed_token);

-- (2) Per-call rate counter -----------------------------------------------------
CREATE TABLE IF NOT EXISTS public.sighting_call_rate (
  user_id      UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  window_start TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  calls        INT NOT NULL DEFAULT 0
);
ALTER TABLE public.sighting_call_rate ENABLE ROW LEVEL SECURITY;
-- No policies: only the SECURITY DEFINER RPC touches it.

CREATE OR REPLACE FUNCTION public.record_sighting(
  p_observed_token TEXT,
  p_lat DOUBLE PRECISION DEFAULT NULL,
  p_lon DOUBLE PRECISION DEFAULT NULL,
  p_rssi INTEGER DEFAULT NULL,
  p_observed_at TIMESTAMPTZ DEFAULT NOW(),
  p_range public.range_type DEFAULT NULL,
  p_accuracy DOUBLE PRECISION DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_now TIMESTAMPTZ := clock_timestamp();
  v_id BIGINT;
  v_range public.range_type := COALESCE(p_range, 'feet_10');
  v_radius DOUBLE PRECISION;
  v_window INT;
  v_claim_acc DOUBLE PRECISION;
  v_calls INT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '28000';
  END IF;
  IF NOT public.current_user_can_discover() THEN
    RAISE EXCEPTION 'Account is not discoverable' USING ERRCODE = '42501';
  END IF;
  IF p_observed_token IS NULL OR lower(p_observed_token) !~ '^[0-9a-f]{32}$' THEN
    RAISE EXCEPTION 'Invalid beacon token' USING ERRCODE = '22023';
  END IF;
  IF p_observed_at IS NULL
     OR p_observed_at < v_now - INTERVAL '10 minutes'
     OR p_observed_at > v_now + INTERVAL '1 minute' THEN
    RAISE EXCEPTION 'Invalid sighting time' USING ERRCODE = '22023';
  END IF;
  IF p_rssi IS NULL OR p_rssi NOT BETWEEN -127 AND 20 THEN
    RAISE EXCEPTION 'Invalid RSSI' USING ERRCODE = '22023';
  END IF;
  IF p_lat IS NULL OR p_lon IS NULL THEN
    RAISE EXCEPTION 'Fresh coordinates are required' USING ERRCODE = '22023';
  END IF;
  IF p_lat NOT BETWEEN -90 AND 90 OR p_lon NOT BETWEEN -180 AND 180 THEN
    RAISE EXCEPTION 'Invalid coordinates' USING ERRCODE = '22023';
  END IF;
  IF p_accuracy IS NOT NULL AND (p_accuracy < 0 OR p_accuracy > 10000) THEN
    RAISE EXCEPTION 'Invalid accuracy' USING ERRCODE = '22023';
  END IF;

  -- Real per-CALL rate limit: atomic upsert of a 1-minute bucket, counted
  -- before any work, so coalesced same-token updates cannot bypass it.
  INSERT INTO public.sighting_call_rate AS r (user_id, window_start, calls)
  VALUES (v_uid, v_now, 1)
  ON CONFLICT (user_id) DO UPDATE
    SET window_start = CASE WHEN r.window_start < v_now - INTERVAL '1 minute'
                           THEN v_now ELSE r.window_start END,
        calls = CASE WHEN r.window_start < v_now - INTERVAL '1 minute'
                     THEN 1 ELSE r.calls + 1 END
  RETURNING calls INTO v_calls;
  IF v_calls > 120 THEN
    RAISE EXCEPTION 'Sighting rate limit' USING ERRCODE = '54000';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.token_claims tc
    WHERE tc.token = lower(p_observed_token)
      AND tc.user_id <> v_uid
      AND tc.valid_until > v_now - INTERVAL '2 minutes'
  ) THEN
    RAISE EXCEPTION 'Unknown or expired beacon token' USING ERRCODE = '22023';
  END IF;

  -- Atomic upsert: one coherent best-evidence row per (observer, token). No
  -- read-then-write race. observed_at always advances; RSSI/location/band swap
  -- together only on a strictly stronger reading (reviewer #12 + #13).
  INSERT INTO public.sightings AS s (
    observer_user_id, observed_token, rssi, observed_at,
    observer_lat, observer_lon, range_type, observer_accuracy_m
  ) VALUES (
    v_uid, lower(p_observed_token), p_rssi, p_observed_at,
    p_lat, p_lon, v_range, p_accuracy
  )
  ON CONFLICT (observer_user_id, observed_token) DO UPDATE
    SET observed_at = p_observed_at,
        rssi = CASE WHEN p_rssi > s.rssi THEN p_rssi ELSE s.rssi END,
        observer_lat = CASE WHEN p_rssi > s.rssi THEN p_lat ELSE s.observer_lat END,
        observer_lon = CASE WHEN p_rssi > s.rssi THEN p_lon ELSE s.observer_lon END,
        observer_accuracy_m =
          CASE WHEN p_rssi > s.rssi THEN p_accuracy ELSE s.observer_accuracy_m END,
        range_type = CASE WHEN p_rssi > s.rssi THEN v_range ELSE s.range_type END
  RETURNING id INTO v_id;

  v_window := LEAST(30, public.range_time_window_minutes(v_range));
  IF v_range::TEXT LIKE 'feet_%' THEN
    SELECT tc.accuracy_m INTO v_claim_acc
    FROM public.token_claims tc WHERE tc.token = lower(p_observed_token) LIMIT 1;
    v_radius := public.gps_veto_radius_meters(p_accuracy, v_claim_acc);
  ELSE
    v_radius := GREATEST(5.0, public.range_radius_meters(v_range));
  END IF;

  PERFORM public.correlate_encounter(
    lower(p_observed_token), p_lat, p_lon, v_radius, v_window
  );
  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.record_sighting(
  TEXT, DOUBLE PRECISION, DOUBLE PRECISION, INTEGER, TIMESTAMPTZ,
  public.range_type, DOUBLE PRECISION
) TO authenticated;
