-- =============================================================================
-- IN RANGE - Supabase Initial Migration (Phase 0)
-- 0001_init.sql
-- =============================================================================
-- This migration sets up the core relational + geospatial schema for:
-- - User profiles
-- - Ephemeral token claims (for privacy-preserving BLE proximity)
-- - Sightings (BLE + GPS observations)
-- - Encounters (server-correlated real-world crossings)
-- - Swipes / actions on encounters
-- - Matches
-- - Messages (chat)
--
-- Key 2026 design principles from plan:
-- * Privacy-first: rotating tokens, minimization, RLS, ephemeral data
-- * PostGIS for efficient proximity (feet + miles)
-- * Server-side correlation for accuracy and anti-spoofing
-- * TTL-friendly sightings (app + optional cleanup)
-- * Support for both BLE token exchange and geo-based matching
--
-- Usage:
--   supabase db reset   (local)
--   Or apply via dashboard / migrations in CI
--
-- After apply:
--   1. Enable PostGIS in Supabase dashboard (Extensions) if not auto.
--   2. Set up Auth providers (Email, Phone, Google, Apple).
--   3. Configure RLS + storage buckets for photos.
-- =============================================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS postgis;
-- CREATE EXTENSION IF NOT EXISTS pg_cron;  -- Uncomment if your project has pg_cron for automated cleanup

-- =============================================================================
-- ENUMS
-- =============================================================================
CREATE TYPE public.range_type AS ENUM (
  'feet_10',
  'feet_20',
  'feet_30',
  'miles_1',
  'miles_5',
  'miles_10',
  'miles_25',
  'miles_50',
  'miles_100',
  'miles_200'
);

CREATE TYPE public.encounter_status AS ENUM (
  'active',      -- Available for swiping
  'expired',     -- Feet-based 24h timeout
  'matched'      -- Converted to match
);

CREATE TYPE public.action_type AS ENUM (
  'like',
  'pass'
);

CREATE TYPE public.message_type AS ENUM (
  'text',
  'photo',
  'voice',
  'video'
);

-- =============================================================================
-- PROFILES
-- =============================================================================
CREATE TABLE public.profiles (
  id                  UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name        TEXT,
  bio                 TEXT CHECK (char_length(bio) <= 500),
  dob                 DATE NOT NULL,
  gender              TEXT CHECK (gender IN ('male','female','non-binary','prefer-not-to-say','other')),
  sexual_preference   TEXT CHECK (sexual_preference IN ('men','women','both')),
  interests           TEXT[],                    -- Free text + curated list combined
  photo_urls          TEXT[] CHECK (array_length(photo_urls, 1) <= 6),
  is_photo_verified   BOOLEAN NOT NULL DEFAULT FALSE,
  photo_verification_status TEXT DEFAULT 'pending', -- pending | verified | rejected
  is_active           BOOLEAN NOT NULL DEFAULT TRUE,
  beacon_default_range public.range_type DEFAULT 'miles_10',
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- =============================================================================
-- TOKEN CLAIMS (Ephemeral - what THIS user is currently advertising via BLE)
-- =============================================================================
-- Client generates rotating token and calls claim_token() while beacon is ON.
-- Short validity windows (e.g. 10-15 minutes) for privacy.
CREATE TABLE public.token_claims (
  id            BIGSERIAL PRIMARY KEY,
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token         TEXT NOT NULL,                    -- Ephemeral token (see separate spec)
  valid_from    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  valid_until   TIMESTAMPTZ NOT NULL,
  approx_lat    DOUBLE PRECISION,
  approx_lon    DOUBLE PRECISION,
  range_type    public.range_type,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Fast lookup by token + time window (core for correlation)
CREATE INDEX idx_token_claims_lookup 
  ON public.token_claims (token, valid_from, valid_until);

CREATE INDEX idx_token_claims_user_active 
  ON public.token_claims (user_id, valid_until) 
  WHERE valid_until > NOW();

-- =============================================================================
-- SIGHTINGS (What OTHER devices were observed - BLE + GPS)
-- =============================================================================
-- Uploaded in batches by the observer while beacon is ON.
-- Contains observed_token (from scanner) + observer's location at time of sighting.
-- Ephemeral: app should prune old records; server can also clean.
CREATE TABLE public.sightings (
  id                  BIGSERIAL PRIMARY KEY,
  observer_user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  observed_token      TEXT NOT NULL,
  rssi                INTEGER,                     -- For feet-range distance estimation
  observed_at         TIMESTAMPTZ NOT NULL,
  observer_lat        DOUBLE PRECISION NOT NULL,
  observer_lon        DOUBLE PRECISION NOT NULL,
  observer_location   GEOGRAPHY(POINT, 4326) GENERATED ALWAYS AS (
    ST_SetSRID(ST_MakePoint(observer_lon, observer_lat), 4326)::geography
  ) STORED,
  range_type          public.range_type,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Critical indexes for correlation queries
CREATE INDEX idx_sightings_token_time 
  ON public.sightings (observed_token, observed_at DESC);

CREATE INDEX idx_sightings_observer 
  ON public.sightings (observer_user_id, observed_at DESC);

CREATE INDEX idx_sightings_geo 
  ON public.sightings USING GIST (observer_location);

-- Optional: composite for recent sightings cleanup queries
CREATE INDEX idx_sightings_recent_cleanup 
  ON public.sightings (created_at) 
  WHERE created_at < NOW() - INTERVAL '7 days';   -- Example retention

-- =============================================================================
-- ENCOUNTERS (Server-created real-world crossings)
-- =============================================================================
CREATE TABLE public.encounters (
  id              BIGSERIAL PRIMARY KEY,
  user_a          UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_b          UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  CHECK (user_a < user_b),                        -- Canonical ordering prevents dups
  neighborhood    TEXT,                           -- e.g. "Downtown LA" (never precise coords)
  encounter_time  TIMESTAMPTZ NOT NULL,
  range_type      public.range_type,
  confidence      NUMERIC(4,2) DEFAULT 0.75,      -- 0.0 - 1.0 based on RSSI + time + geo
  status          public.encounter_status NOT NULL DEFAULT 'active',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_a, user_b, encounter_time)         -- De-dupe
);

CREATE INDEX idx_encounters_participants 
  ON public.encounters (user_a, user_b);

CREATE INDEX idx_encounters_time_status 
  ON public.encounters (encounter_time DESC, status);

-- =============================================================================
-- ENCOUNTER ACTIONS (Swipes / likes / passes)
-- =============================================================================
CREATE TABLE public.encounter_actions (
  id            BIGSERIAL PRIMARY KEY,
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  encounter_id  BIGINT NOT NULL REFERENCES public.encounters(id) ON DELETE CASCADE,
  action        public.action_type NOT NULL,
  acted_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, encounter_id)                  -- One action per user per encounter
);

CREATE INDEX idx_encounter_actions_user 
  ON public.encounter_actions (user_id, acted_at DESC);

-- =============================================================================
-- MATCHES (Mutual likes)
-- =============================================================================
CREATE TABLE public.matches (
  id            BIGSERIAL PRIMARY KEY,
  encounter_id  BIGINT UNIQUE REFERENCES public.encounters(id) ON DELETE SET NULL,
  user_a        UUID NOT NULL REFERENCES auth.users(id),
  user_b        UUID NOT NULL REFERENCES auth.users(id),
  matched_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_matches_users 
  ON public.matches (user_a, user_b);

-- =============================================================================
-- MESSAGES (Post-match chat)
-- =============================================================================
CREATE TABLE public.messages (
  id            BIGSERIAL PRIMARY KEY,
  match_id      BIGINT NOT NULL REFERENCES public.matches(id) ON DELETE CASCADE,
  sender_id     UUID NOT NULL REFERENCES auth.users(id),
  content       TEXT,
  message_type  public.message_type NOT NULL DEFAULT 'text',
  metadata      JSONB,                            -- For photo urls, voice duration, etc.
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  read_at       TIMESTAMPTZ
);

CREATE INDEX idx_messages_match_time 
  ON public.messages (match_id, created_at DESC);

-- =============================================================================
-- RPCs (as specified in Phase 0 plan)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- claim_token: Client calls this periodically while Beacon is ON
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.claim_token(
  p_token TEXT,
  p_valid_until TIMESTAMPTZ,
  p_lat DOUBLE PRECISION DEFAULT NULL,
  p_lon DOUBLE PRECISION DEFAULT NULL,
  p_range public.range_type DEFAULT 'miles_10'
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Invalidate any previous active claims for this user
  UPDATE public.token_claims
  SET valid_until = NOW()
  WHERE user_id = v_user_id
    AND valid_until > NOW();

  -- Insert new claim
  INSERT INTO public.token_claims (
    user_id, token, valid_until, approx_lat, approx_lon, range_type
  )
  VALUES (
    v_user_id, p_token, p_valid_until, p_lat, p_lon, p_range
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- record_sighting: Client uploads observed BLE/GPS data
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_sighting(
  p_observed_token TEXT,
  p_rssi INTEGER DEFAULT NULL,
  p_observed_at TIMESTAMPTZ DEFAULT NOW(),
  p_lat DOUBLE PRECISION,
  p_lon DOUBLE PRECISION,
  p_range public.range_type DEFAULT NULL
)
RETURNS BIGINT   -- returns the sighting id
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_sighting_id BIGINT;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  INSERT INTO public.sightings (
    observer_user_id,
    observed_token,
    rssi,
    observed_at,
    observer_lat,
    observer_lon,
    range_type
  )
  VALUES (
    v_user_id,
    p_observed_token,
    p_rssi,
    p_observed_at,
    p_lat,
    p_lon,
    COALESCE(p_range, 'miles_10')
  )
  RETURNING id INTO v_sighting_id;

  -- Immediately attempt correlation (fire-and-forget style)
  PERFORM public.correlate_encounter(
    p_observed_token,
    p_lat,
    p_lon,
    50,   -- default meters for feet; caller can use larger for miles
    90    -- minutes window
  );

  RETURN v_sighting_id;
END;
$$;

-- -----------------------------------------------------------------------------
-- correlate_encounter (core function referenced in the plan)
-- Finds claims for the observed token and creates encounters when proximity matches.
-- Can be called manually or from record_sighting trigger.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.correlate_encounter(
  p_observed_token TEXT,
  p_lat DOUBLE PRECISION,
  p_lon DOUBLE PRECISION,
  p_radius_meters DOUBLE PRECISION DEFAULT 50,
  p_time_window_minutes INT DEFAULT 60
)
RETURNS TABLE (
  encounter_id BIGINT,
  other_user_id UUID,
  created_new BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_observer_id UUID := auth.uid();
  v_claim RECORD;
  v_distance NUMERIC;
  v_enc_id BIGINT;
  v_user_a UUID;
  v_user_b UUID;
  v_new BOOLEAN := FALSE;
BEGIN
  IF v_observer_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Find recent claims for this token from OTHER users
  FOR v_claim IN
    SELECT 
      tc.user_id,
      tc.approx_lat,
      tc.approx_lon,
      tc.range_type,
      tc.valid_from
    FROM public.token_claims tc
    WHERE tc.token = p_observed_token
      AND tc.user_id != v_observer_id
      AND tc.valid_from > NOW() - (p_time_window_minutes || ' minutes')::interval
      AND tc.valid_until > NOW() - (p_time_window_minutes || ' minutes')::interval
    ORDER BY tc.valid_from DESC
    LIMIT 5
  LOOP
    -- Compute distance using PostGIS
    IF v_claim.approx_lat IS NOT NULL AND v_claim.approx_lon IS NOT NULL THEN
      v_distance := ST_Distance(
        ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography,
        ST_SetSRID(ST_MakePoint(v_claim.approx_lon, v_claim.approx_lat), 4326)::geography
      );

      IF v_distance <= p_radius_meters THEN
        -- Canonical user order
        IF v_observer_id < v_claim.user_id THEN
          v_user_a := v_observer_id;
          v_user_b := v_claim.user_id;
        ELSE
          v_user_a := v_claim.user_id;
          v_user_b := v_observer_id;
        END IF;

        -- Insert encounter (idempotent)
        INSERT INTO public.encounters (
          user_a,
          user_b,
          neighborhood,
          encounter_time,
          range_type,
          confidence
        )
        VALUES (
          v_user_a,
          v_user_b,
          'Neighborhood',  -- TODO: reverse geocode or pass from client
          NOW(),
          COALESCE(v_claim.range_type, 'miles_10'),
          LEAST(1.0, GREATEST(0.5, 1.0 - (v_distance / 100.0)))  -- crude confidence
        )
        ON CONFLICT (user_a, user_b, encounter_time) DO NOTHING
        RETURNING id INTO v_enc_id;

        IF v_enc_id IS NOT NULL THEN
          v_new := TRUE;
        ELSE
          -- Find existing
          SELECT id INTO v_enc_id 
          FROM public.encounters 
          WHERE user_a = v_user_a AND user_b = v_user_b 
          ORDER BY encounter_time DESC 
          LIMIT 1;
        END IF;

        RETURN QUERY SELECT v_enc_id, v_claim.user_id, v_new;
      END IF;
    END IF;
  END LOOP;

  -- TODO (future): Also support pure geo-based miles correlation using recent self-location pings
  -- if no token match (for users who were in same broad area at similar times).
END;
$$;

-- -----------------------------------------------------------------------------
-- Helper: Get active encounters for current user (for the Encounters feed)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_my_encounters(
  p_limit INT DEFAULT 50,
  p_offset INT DEFAULT 0
)
RETURNS TABLE (
  encounter_id BIGINT,
  other_user_id UUID,
  neighborhood TEXT,
  encounter_time TIMESTAMPTZ,
  range_type public.range_type,
  my_action public.action_type,
  other_action public.action_type,
  status public.encounter_status
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT 
    e.id,
    CASE WHEN e.user_a = auth.uid() THEN e.user_b ELSE e.user_a END AS other_user_id,
    e.neighborhood,
    e.encounter_time,
    e.range_type,
    (SELECT action FROM public.encounter_actions WHERE user_id = auth.uid() AND encounter_id = e.id),
    (SELECT action FROM public.encounter_actions WHERE user_id != auth.uid() AND encounter_id = e.id),
    e.status
  FROM public.encounters e
  WHERE (e.user_a = auth.uid() OR e.user_b = auth.uid())
    AND e.status = 'active'
  ORDER BY e.encounter_time DESC
  LIMIT p_limit
  OFFSET p_offset;
$$;

-- =============================================================================
-- ROW LEVEL SECURITY (RLS) - Privacy critical
-- =============================================================================

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.token_claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sightings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.encounters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.encounter_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.matches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- Profiles: own profile full access; others can see limited public fields (via view or future policy)
CREATE POLICY "Users can manage their own profile"
  ON public.profiles
  FOR ALL
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

-- Token claims: only the owner can insert/read their own (server correlates via RPC)
CREATE POLICY "Users manage own token claims"
  ON public.token_claims
  FOR ALL
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Sightings: user can insert their own observations; no broad read (only server RPCs use them)
CREATE POLICY "Users insert own sightings"
  ON public.sightings
  FOR INSERT
  WITH CHECK (observer_user_id = auth.uid());

-- Encounters: only participants can see their encounters
CREATE POLICY "Users see their own encounters"
  ON public.encounters
  FOR SELECT
  USING (user_a = auth.uid() OR user_b = auth.uid());

CREATE POLICY "System can insert encounters"   -- via SECURITY DEFINER functions
  ON public.encounters
  FOR INSERT
  WITH CHECK (true);

-- Encounter actions: only actor
CREATE POLICY "Users manage own actions"
  ON public.encounter_actions
  FOR ALL
  USING (user_id = auth.uid());

-- Matches: only participants
CREATE POLICY "Users see their matches"
  ON public.matches
  FOR SELECT
  USING (user_a = auth.uid() OR user_b = auth.uid());

-- Messages: only participants in the match
CREATE POLICY "Users see messages in their matches"
  ON public.messages
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.matches m
      WHERE m.id = messages.match_id
        AND (m.user_a = auth.uid() OR m.user_b = auth.uid())
    )
  );

CREATE POLICY "Users can send messages in their matches"
  ON public.messages
  FOR INSERT
  WITH CHECK (
    sender_id = auth.uid() AND
    EXISTS (
      SELECT 1 FROM public.matches m
      WHERE m.id = messages.match_id
        AND (m.user_a = auth.uid() OR m.user_b = auth.uid())
    )
  );

-- =============================================================================
-- STORAGE BUCKETS (Photos)
-- =============================================================================
-- Run these in Supabase dashboard or via SQL if supported:
-- INSERT INTO storage.buckets (id, name, public) VALUES ('profile-photos', 'profile-photos', false);
-- Then add policies for authenticated users to upload their own folder.

-- =============================================================================
-- NOTES & FUTURE IMPROVEMENTS (documented in plan)
-- =============================================================================
-- 1. Token format & rotation spec lives in a separate doc (see Phase 0 task #2).
-- 2. Neighborhood population: client can pass coarse reverse-geocoded value, or add server function.
-- 3. Cleanup of old sightings: 
--    - Client prunes locally.
--    - Add pg_cron job or Edge Function to delete sightings older than N days.
-- 4. For pure miles-based (no BLE token): extend with a "location_pings" table + geo correlation RPC.
-- 5. Photo verification queue: add a separate table later (or use status fields).
-- 6. Call correlate_encounter() from record_sighting or as a separate background job for batching.
-- 7. Add triggers or Edge Functions to notify on new encounters/matches (realtime + push).
-- 8. Test heavily with real devices before relying on background uploads.

-- =============================================================================
-- END OF MIGRATION
-- =============================================================================
COMMENT ON SCHEMA public IS 'In Range - location-based real encounter dating (2026 plan)';
