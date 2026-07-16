-- #6 step 4: relay-abuse detection (telemetry).
--
-- mutual_ble (step 1) is explicitly NOT relay-proof: a relay that forwards BOTH
-- tokens makes both phones report, and if the relay spoofs consistent GPS the
-- per-encounter distance veto passes. This migration adds server-side detection
-- for the two signals a relay/spoof leaves behind, decoupled from the hot path
-- (a periodic scan, the way real anti-abuse works — no latency on claim/sight):
--
--   1. claim_teleport — an account whose consecutive claims imply impossible
--      travel (its GPS is being spoofed or injected by a relay).
--   2. relay_geo — a claimed token OBSERVED from a location implausibly far from
--      where its owner claimed it (beyond any GPS-accuracy explanation): the
--      token must have been relayed to a distant advertiser.
--
-- This is TELEMETRY, not auto-punishment: in a forwarding relay BOTH parties are
-- victims, so flags feed review/rate-limiting, and the existing distance veto
-- still blocks the specific bogus encounter. Suppression/response is a separate,
-- deliberate ops decision (a later step).

CREATE TABLE IF NOT EXISTS public.beacon_abuse_flags (
  id         BIGSERIAL PRIMARY KEY,
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reason     TEXT NOT NULL,
  detail     JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_beacon_abuse_flags_user ON public.beacon_abuse_flags (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_beacon_abuse_flags_reason ON public.beacon_abuse_flags (reason, created_at DESC);
ALTER TABLE public.beacon_abuse_flags ENABLE ROW LEVEL SECURITY;
-- Ops/service only; no client role reads or writes it.
REVOKE ALL ON TABLE public.beacon_abuse_flags FROM PUBLIC, anon, authenticated;

-- Internal: record a flag, de-duped per (user, reason) over a short window so a
-- burst of the same signal does not spam the table. Not granted to any client
-- role — only the SECURITY DEFINER scanner (as its owner) calls it.
CREATE OR REPLACE FUNCTION public.note_abuse_flag(p_user UUID, p_reason TEXT, p_detail JSONB)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
BEGIN
  IF p_user IS NULL THEN RETURN FALSE; END IF;
  IF EXISTS (
    SELECT 1 FROM public.beacon_abuse_flags
    WHERE user_id = p_user AND reason = p_reason AND created_at > NOW() - INTERVAL '5 minutes'
  ) THEN RETURN FALSE; END IF;
  INSERT INTO public.beacon_abuse_flags (user_id, reason, detail) VALUES (p_user, p_reason, p_detail);
  RETURN TRUE;
END $$;
REVOKE ALL ON FUNCTION public.note_abuse_flag(UUID, TEXT, JSONB) FROM PUBLIC, anon, authenticated;

-- Maximum plausible physical speed between two beacon fixes (m/s). ~300 m/s is
-- faster than a commercial airliner; anything above it over a real distance is a
-- spoof/relay, not honest movement.
-- Anything travelled beyond this AND faster than the speed cap is impossible.
CREATE OR REPLACE FUNCTION public.scan_relay_abuse(p_since INTERVAL DEFAULT INTERVAL '1 hour')
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
DECLARE
  v_count INT := 0; r RECORD;
  c_max_mps CONSTANT DOUBLE PRECISION := 300.0;   -- speed cap
  c_min_meters CONSTANT DOUBLE PRECISION := 2000.0; -- ignore GPS jitter
BEGIN
  -- 1) claim_teleport: consecutive claims by one user that imply impossible speed.
  FOR r IN
    WITH c AS (
      SELECT user_id, valid_from, approx_lat, approx_lon,
             LAG(valid_from)  OVER w AS prev_from,
             LAG(approx_lat)  OVER w AS prev_lat,
             LAG(approx_lon)  OVER w AS prev_lon
      FROM public.token_claim_history
      WHERE valid_from > NOW() - p_since AND approx_lat IS NOT NULL AND approx_lon IS NOT NULL
      WINDOW w AS (PARTITION BY user_id ORDER BY valid_from)
    )
    SELECT user_id,
           ST_Distance(ST_SetSRID(ST_MakePoint(prev_lon, prev_lat),4326)::geography,
                       ST_SetSRID(ST_MakePoint(approx_lon, approx_lat),4326)::geography) AS meters,
           EXTRACT(EPOCH FROM (valid_from - prev_from)) AS secs
    FROM c
    WHERE prev_from IS NOT NULL AND prev_lat IS NOT NULL AND prev_lon IS NOT NULL
  LOOP
    IF r.secs > 1 AND r.meters > c_min_meters AND (r.meters / r.secs) > c_max_mps THEN
      IF public.note_abuse_flag(r.user_id, 'claim_teleport',
           jsonb_build_object('meters', round(r.meters), 'seconds', round(r.secs), 'mps', round(r.meters / r.secs)))
      THEN v_count := v_count + 1; END IF;
    END IF;
  END LOOP;

  -- 2) relay_geo: a token observed implausibly far from where its owner claimed
  --    it. Honest observers are within the GPS veto radius (<=400 m) of the
  --    advertiser; an observer kilometres away means the token was relayed.
  FOR r IN
    SELECT h.user_id, h.token,
           max(ST_Distance(
             ST_SetSRID(ST_MakePoint(h.approx_lon, h.approx_lat),4326)::geography,
             ST_SetSRID(ST_MakePoint(s.observer_lon, s.observer_lat),4326)::geography)) AS max_m,
           count(DISTINCT s.observer_user_id) AS observers
    FROM public.token_claim_history h
    JOIN public.sightings s ON s.observed_token = h.token
    WHERE h.valid_from > NOW() - p_since
      AND h.approx_lat IS NOT NULL AND h.approx_lon IS NOT NULL
      AND s.observer_lat IS NOT NULL AND s.observer_lon IS NOT NULL
    GROUP BY h.user_id, h.token
  LOOP
    IF r.max_m > c_min_meters THEN
      IF public.note_abuse_flag(r.user_id, 'relay_geo',
           jsonb_build_object('token', r.token, 'max_meters', round(r.max_m), 'observers', r.observers))
      THEN v_count := v_count + 1; END IF;
    END IF;
  END LOOP;

  RETURN v_count;
END $$;
REVOKE ALL ON FUNCTION public.scan_relay_abuse(INTERVAL) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.scan_relay_abuse(INTERVAL) TO service_role;
