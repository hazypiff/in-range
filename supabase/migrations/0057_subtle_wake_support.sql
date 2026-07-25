-- 0057_subtle_wake_support.sql
--
-- Server half of the subtle multi-radio tracking architecture
-- (docs/SUBTLE_TRACKING_ARCHITECTURE.md). Two tables:
--
--   venue_anchors            — coarse geohash + hashed BSSID hints the client
--                              uploads so the server can infer co-location
--                              WITHOUT continuous raw GPS. Privacy model: the
--                              geohash is city-level and the BSSID is hashed
--                              with a rotating salt before it leaves the device,
--                              so this table cannot reconstruct where a user is.
--   proximity_wake_requests  — internal outbox drained by the proximity-wake
--                              Edge Function, which sends APNs silent pushes to
--                              likely co-located devices so they run a BLE burst.
--
-- SENSITIVITY: joined with sightings, venue_anchors approximates a co-location
-- log. It therefore carries no raw coordinates, and the silent pushes it
-- triggers contain no user data — only a wake hint and a nonce.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. venue_anchors
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.venue_anchors (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  -- Coarse (city-level) geohash for candidate pruning. Never a precise fix.
  geohash       TEXT NOT NULL,
  radius_m      INT NOT NULL CHECK (radius_m > 0),
  -- BSSID of the current network, hashed with the rotating device salt.
  -- Nullable: an anchor can exist on geohash alone when WiFi info is
  -- unavailable (e.g. no Access WiFi Information entitlement).
  hashed_bssid  TEXT,
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Co-location matching: recent anchors by hash or geohash.
CREATE INDEX IF NOT EXISTS idx_venue_anchors_bssid
  ON public.venue_anchors (hashed_bssid, updated_at DESC)
  WHERE hashed_bssid IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_venue_anchors_geohash
  ON public.venue_anchors (geohash, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_venue_anchors_user
  ON public.venue_anchors (user_id);

DROP TRIGGER IF EXISTS venue_anchors_updated_at ON public.venue_anchors;
CREATE TRIGGER venue_anchors_updated_at
  BEFORE UPDATE ON public.venue_anchors
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

ALTER TABLE public.venue_anchors ENABLE ROW LEVEL SECURITY;

-- Users read/write their own anchors; service_role reads all (the
-- proximity-wake function matches anchors across users).
DROP POLICY IF EXISTS "Users manage own venue anchors" ON public.venue_anchors;
CREATE POLICY "Users manage own venue anchors"
  ON public.venue_anchors FOR ALL
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Service role reads venue anchors" ON public.venue_anchors;
CREATE POLICY "Service role reads venue anchors"
  ON public.venue_anchors FOR SELECT
  TO service_role
  USING (true);

-- ---------------------------------------------------------------------------
-- 2. proximity_wake_requests
-- ---------------------------------------------------------------------------
-- Outbox drained by the proximity-wake Edge Function. peer_hint carries the
-- requesting client's coarse hints: { "geohash": ..., "hashed_bssid": ... }.
-- status is deliberately the same four-state vocabulary as
-- notification_outbox; the claim RPC uses attempts + processing_at for the
-- in-flight window instead of a 'processing' status.

CREATE TABLE IF NOT EXISTS public.proximity_wake_requests (
  id            BIGSERIAL PRIMARY KEY,
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  peer_hint     JSONB NOT NULL DEFAULT '{}'::jsonb,
  status        TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'sent', 'failed', 'skipped')),
  attempts      INT NOT NULL DEFAULT 0,
  last_error    TEXT,
  processing_at TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  sent_at       TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_proximity_wake_pending
  ON public.proximity_wake_requests (status, created_at)
  WHERE status = 'pending';

-- Rate limiting: recent sends per user.
CREATE INDEX IF NOT EXISTS idx_proximity_wake_user_sent
  ON public.proximity_wake_requests (user_id, sent_at DESC)
  WHERE status = 'sent';

ALTER TABLE public.proximity_wake_requests ENABLE ROW LEVEL SECURITY;

-- Clients never touch this table; service_role + edge only.
DROP POLICY IF EXISTS "Service role manages proximity wake requests"
  ON public.proximity_wake_requests;
CREATE POLICY "Service role manages proximity wake requests"
  ON public.proximity_wake_requests FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Atomically claims a pending batch for the proximity-wake function. Unlike
-- claim_notification_batch there is no 'processing' status (the CHECK above
-- is the four-state spec), so a claimed row stays 'pending' but is invisible
-- to other workers until processing_at goes stale — the same crash-recovery
-- window as 0019, expressed inside the claim predicate.
CREATE OR REPLACE FUNCTION public.claim_proximity_wake_batch(p_limit INT DEFAULT 50)
RETURNS TABLE (
  id BIGINT,
  user_id UUID,
  peer_hint JSONB,
  attempts INT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  WITH picked AS (
    SELECT r.id
    FROM public.proximity_wake_requests r
    WHERE r.status = 'pending'
      AND r.attempts < 5
      AND (
        r.processing_at IS NULL
        OR r.processing_at < NOW() - INTERVAL '10 minutes'
      )
    ORDER BY r.created_at ASC
    FOR UPDATE SKIP LOCKED
    LIMIT LEAST(200, GREATEST(1, COALESCE(p_limit, 50)))
  )
  UPDATE public.proximity_wake_requests r
  SET attempts = r.attempts + 1, processing_at = NOW()
  FROM picked
  WHERE r.id = picked.id
  RETURNING r.id, r.user_id, r.peer_hint, r.attempts;
$$;

COMMENT ON TABLE public.venue_anchors IS 'Coarse geohash + hashed-BSSID hints for privacy-preserving co-location inference.';
COMMENT ON TABLE public.proximity_wake_requests IS 'Silent-push wake jobs drained by the proximity-wake Edge Function.';

COMMIT;
