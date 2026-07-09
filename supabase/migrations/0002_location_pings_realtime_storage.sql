-- ============================================================================
-- IN RANGE — Migration 0002: location_pings + realtime + storage
-- ============================================================================
-- Adds:
--   1. location_pings table (pure-GPS "miles" mode when BLE is sparse/off)
--   2. Realtime publication for matches + messages
--   3. Storage bucket + policies for verified photos
--   4. Cleanup helper for expired token_claims / sightings / location_pings
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. location_pings — self-pings for miles-mode matching
-- ----------------------------------------------------------------------------
-- Per ephemeral-token-spec.md open question: "self pings" for pure miles
-- matching when BLE is off or sparse. Coarse, low-frequency, short-lived.

CREATE TABLE IF NOT EXISTS public.location_pings (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  geo             GEOGRAPHY(POINT, 4326) NOT NULL,
  range_type      public.range_type NOT NULL DEFAULT 'miles_10',
  neighborhood    TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_location_pings_user_time
  ON public.location_pings (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_location_pings_geo
  ON public.location_pings USING GIST (geo);

CREATE INDEX IF NOT EXISTS idx_location_pings_cleanup
  ON public.location_pings (created_at);

ALTER TABLE public.location_pings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users insert own location pings"
  ON public.location_pings FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users read own location pings"
  ON public.location_pings FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- ----------------------------------------------------------------------------
-- 2. Realtime publication
-- ----------------------------------------------------------------------------
-- Supabase Realtime delivers row changes over WebSocket. We add matches and
-- messages so the client can subscribe to new matches / incoming chats.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'matches'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.matches;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 3. Storage — verified photos bucket + RLS
-- ----------------------------------------------------------------------------
-- Two-bucket policy:
--   verified_photos  : upload restricted (moderation flow), public-read once approved
--   profile_photos   : user-managed, public-read
-- NOTE: storage buckets are idempotent via `insert ... on conflict do nothing`.

INSERT INTO storage.buckets (id, name, public)
VALUES
  ('verified_photos', 'verified_photos', true),
  ('profile_photos', 'profile_photos', true)
ON CONFLICT (id) DO NOTHING;

-- Profile photos: users CRUD their own.
CREATE POLICY "Users upload own profile photos"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'profile_photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Users update own profile photos"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'profile_photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Users delete own profile photos"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'profile_photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Public read for both buckets.
CREATE POLICY "Public read profile photos"
  ON storage.objects FOR SELECT
  TO public
  USING (bucket_id = 'profile_photos');

CREATE POLICY "Public read verified photos"
  ON storage.objects FOR SELECT
  TO public
  USING (bucket_id = 'verified_photos');

-- Verified photos: only service_role (moderation pipeline) can write.
CREATE POLICY "Service role uploads verified photos"
  ON storage.objects FOR INSERT
  TO service_role
  WITH CHECK (bucket_id = 'verified_photos');

CREATE POLICY "Service role updates verified photos"
  ON storage.objects FOR UPDATE
  TO service_role
  USING (bucket_id = 'verified_photos');

CREATE POLICY "Service role deletes verified photos"
  ON storage.objects FOR DELETE
  TO service_role
  USING (bucket_id = 'verified_photos');

-- ----------------------------------------------------------------------------
-- 4. nearby_location_pings RPC — miles-mode proximity query
-- ----------------------------------------------------------------------------
-- Given a user's current position, return recent nearby pings from OTHER
-- users within a radius (default 1 mile / ~1609 meters) and time window
-- (default 60 minutes). Used to surface "miles" encounters when BLE is off.

CREATE OR REPLACE FUNCTION public.nearby_location_pings(
  p_lat           DOUBLE PRECISION,
  p_lon           DOUBLE PRECISION,
  p_radius_meters INTEGER DEFAULT 1609,
  p_window_minutes INTEGER DEFAULT 60,
  p_limit         INTEGER DEFAULT 50
)
RETURNS TABLE (
  user_id      UUID,
  distance_m   DOUBLE PRECISION,
  neighborhood TEXT,
  created_at   TIMESTAMPTZ
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    lp.user_id,
    ST_Distance(lp.geo, ST_MakePoint(p_lon, p_lat)::geography) AS distance_m,
    lp.neighborhood,
    lp.created_at
  FROM public.location_pings lp
  WHERE lp.created_at > now() - (p_window_minutes || ' minutes')::interval
    AND lp.user_id <> auth.uid()
    AND ST_DWithin(lp.geo, ST_MakePoint(p_lon, p_lat)::geography, p_radius_meters)
  ORDER BY lp.created_at DESC
  LIMIT p_limit;
$$;

GRANT EXECUTE ON FUNCTION public.nearby_location_pings TO authenticated;

-- ----------------------------------------------------------------------------
-- 5. Cleanup function — purge stale ephemeral rows
-- ----------------------------------------------------------------------------
-- Safe to run from a Supabase scheduled function (pg_cron) or a backend job.
-- Recommended schedule: every 15 minutes.

CREATE OR REPLACE FUNCTION public.cleanup_ephemeral_data()
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  -- Token claims: hard-expire after 30 min past valid_until
  DELETE FROM public.token_claims
  WHERE valid_until < now() - interval '30 minutes';

  -- Sightings: purge after 48h or once encounter exists (cascade handles the latter)
  DELETE FROM public.sightings
  WHERE observed_at < now() - interval '48 hours';

  -- Location pings: keep 24h for miles matching, then purge
  DELETE FROM public.location_pings
  WHERE created_at < now() - interval '24 hours';
$$;

GRANT EXECUTE ON FUNCTION public.cleanup_ephemeral_data TO service_role;

-- Optional pg_cron schedule (uncomment once pg_cron extension is enabled):
-- SELECT cron.schedule(
--   'in-range-cleanup',
--   '*/15 * * * *',
--   $$ SELECT public.cleanup_ephemeral_data(); $$
-- );

-- ----------------------------------------------------------------------------
-- 6. Schema comments
-- ----------------------------------------------------------------------------
COMMENT ON TABLE public.location_pings IS
  'Self-reported coarse GPS pings for miles-mode matching when BLE is sparse. Purged after 24h by cleanup_ephemeral_data().';
COMMENT ON FUNCTION public.nearby_location_pings IS
  'Returns recent nearby location_pings from other users within radius + time window. SECURITY DEFINER so the geo index is used efficiently across users.';
COMMENT ON FUNCTION public.cleanup_ephemeral_data IS
  'Purges expired token_claims (>30min past validity), sightings (>48h), location_pings (>24h). Call from pg_cron or backend.';
