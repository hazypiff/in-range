-- Recurrence: "you've crossed paths with this person N times."
--
-- Why the server: a peer's BLE token rotates every 15 minutes, so the SAME
-- person is a different anonymous correlation-id each time — locally there is
-- nothing to link. The server maps every token back to a stable user via
-- token_claims, and the encounters table is already one canonical row per
-- (user_a, user_b) pair. Recurrence is therefore a natural server feature.
--
-- Model:
--   * encounter_sessions — one row per DISTINCT co-presence session between a
--     pair. A new session starts when the pair is seen again after a gap
--     longer than SESSION_GAP. This is the queryable recurrence history
--     ("3 times this week" = sessions in the last 7 days). Bounded: one row
--     per crossing, not per packet.
--   * denormalized counters on encounters (session_count, distinct_day_count,
--     first_seen_at, last_recurrence_at) for cheap reads in the feed.

-- How long a quiet gap must be before the next sighting counts as a NEW
-- crossing rather than the same one continuing. 1 hour: long enough that
-- stepping away and coming back is the "same" encounter, short enough that
-- meeting again after lunch counts as a second crossing.
CREATE OR REPLACE FUNCTION public.encounter_session_gap()
RETURNS INTERVAL LANGUAGE sql IMMUTABLE AS $$ SELECT INTERVAL '1 hour' $$;

CREATE TABLE IF NOT EXISTS public.encounter_sessions (
  id            BIGSERIAL PRIMARY KEY,
  encounter_id  BIGINT NOT NULL REFERENCES public.encounters(id) ON DELETE CASCADE,
  started_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- Strongest band reached during this session (narrowest = closest).
  best_range    public.range_type
);

CREATE INDEX IF NOT EXISTS idx_encounter_sessions_enc
  ON public.encounter_sessions (encounter_id, started_at DESC);

ALTER TABLE public.encounters
  ADD COLUMN IF NOT EXISTS session_count INT NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS distinct_day_count INT NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS first_seen_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_recurrence_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_seen_day DATE;

-- Backfill existing rows so the counters, timestamps, and session history are
-- consistent before the recurrence correlator runs (reviewer #14). Without
-- this, a first post-migration sighting within the hour would target a
-- nonexistent "latest session" and silently update zero rows, and null
-- last_seen_day would mis-count distinct days.
UPDATE public.encounters e
SET first_seen_at = COALESCE(e.first_seen_at, e.encounter_time),
    last_recurrence_at =
      COALESCE(e.last_recurrence_at, e.last_seen_at, e.encounter_time),
    last_seen_day =
      COALESCE(e.last_seen_day, (COALESCE(e.last_seen_at, e.encounter_time))::DATE)
WHERE e.first_seen_at IS NULL OR e.last_seen_day IS NULL;

-- One session row per existing encounter that has none.
INSERT INTO public.encounter_sessions (encounter_id, started_at, last_seen_at, best_range)
SELECT e.id, e.encounter_time, COALESCE(e.last_seen_at, e.encounter_time), e.range_type
FROM public.encounters e
WHERE NOT EXISTS (
  SELECT 1 FROM public.encounter_sessions s WHERE s.encounter_id = e.id
);

-- RLS: sessions are readable only by the two participants (defense in depth;
-- all access goes through SECURITY DEFINER RPCs, but never leave it open).
ALTER TABLE public.encounter_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS encounter_sessions_participant_read ON public.encounter_sessions;
CREATE POLICY encounter_sessions_participant_read
  ON public.encounter_sessions FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM public.encounters e
    WHERE e.id = encounter_sessions.encounter_id
      AND (e.user_a = auth.uid() OR e.user_b = auth.uid())
  ));

-- correlate_encounter, recurrence-aware. Same body as 0024 plus session
-- bookkeeping on the encounter update path.
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
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_claim public.token_claims%ROWTYPE;
  v_user_a UUID;
  v_user_b UUID;
  v_enc_id BIGINT;
  v_distance DOUBLE PRECISION;
  v_rssi INTEGER;
  v_min_rssi INTEGER;
  v_new BOOLEAN := FALSE;
  v_sight_range public.range_type;
  v_band public.range_type;
  v_prev_seen TIMESTAMPTZ;
  v_prev_day DATE;
  v_now TIMESTAMPTZ := NOW();
  v_session_id BIGINT;
BEGIN
  IF v_uid IS NULL OR NOT public.current_user_can_discover() THEN
    RETURN;
  END IF;

  SELECT * INTO v_claim
  FROM public.token_claims tc
  WHERE tc.token = lower(p_observed_token)
    AND tc.user_id <> v_uid
    AND tc.valid_from > NOW() - make_interval(mins => LEAST(30, GREATEST(1, p_time_window_minutes)))
    AND tc.valid_until > NOW() - INTERVAL '2 minutes'
  LIMIT 1;

  IF NOT FOUND OR NOT public.is_discoverable_user(v_claim.user_id) THEN
    RETURN;
  END IF;
  IF public.is_blocked_pair(v_uid, v_claim.user_id) THEN
    RETURN;
  END IF;

  SELECT s.rssi, s.range_type INTO v_rssi, v_sight_range
  FROM public.sightings s
  WHERE s.observer_user_id = v_uid
    AND s.observed_token = lower(p_observed_token)
  ORDER BY s.observed_at DESC
  LIMIT 1;

  v_min_rssi := CASE COALESCE(v_claim.range_type, 'feet_10')
    WHEN 'feet_10' THEN -75
    WHEN 'feet_20' THEN -85
    ELSE -95
  END;
  IF v_rssi IS NULL OR v_rssi < v_min_rssi THEN
    RETURN;
  END IF;

  IF p_lat IS NOT NULL AND p_lon IS NOT NULL
     AND v_claim.approx_lat IS NOT NULL AND v_claim.approx_lon IS NOT NULL THEN
    v_distance := ST_Distance(
      ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography,
      ST_SetSRID(ST_MakePoint(v_claim.approx_lon, v_claim.approx_lat), 4326)::geography
    );
    IF v_distance > LEAST(400.0, GREATEST(5.0, p_radius_meters)) THEN
      RETURN;
    END IF;
  END IF;

  IF v_sight_range IS NOT NULL AND v_sight_range::TEXT LIKE 'feet_%' THEN
    v_band := v_sight_range;
  ELSE
    v_band := COALESCE(v_claim.range_type, 'feet_10');
  END IF;

  v_user_a := LEAST(v_uid, v_claim.user_id);
  v_user_b := GREATEST(v_uid, v_claim.user_id);
  PERFORM pg_advisory_xact_lock(hashtextextended(v_user_a::TEXT || v_user_b::TEXT, 0));

  SELECT id, last_seen_at, last_seen_day
    INTO v_enc_id, v_prev_seen, v_prev_day
  FROM public.encounters
  WHERE user_a = v_user_a AND user_b = v_user_b AND status = 'active'
  ORDER BY encounter_time DESC
  LIMIT 1
  FOR UPDATE;

  IF v_enc_id IS NULL THEN
    INSERT INTO public.encounters (
      user_a, user_b, neighborhood, encounter_time, last_seen_at,
      range_type, confidence, status,
      session_count, distinct_day_count, first_seen_at,
      last_recurrence_at, last_seen_day
    ) VALUES (
      v_user_a, v_user_b, 'Near you', v_now, v_now,
      v_band,
      -- Neutral confidence: GPS is a VETO only (it already passed above), it
      -- must not add positive confidence — otherwise a forged coordinate could
      -- manufacture 1.0 (reviewer #16). BLE-derived confidence is computed
      -- client-side (§5b); the server stores a constant until it is uploaded.
      0.8,
      'active',
      1, 1, v_now, v_now, v_now::DATE
    ) RETURNING id INTO v_enc_id;
    v_new := TRUE;

    INSERT INTO public.encounter_sessions (encounter_id, started_at, last_seen_at, best_range)
    VALUES (v_enc_id, v_now, v_now, v_band);
  ELSE
    -- New crossing? Only when the quiet gap since we last saw them exceeds
    -- the session threshold. Otherwise it's the same crossing continuing.
    IF v_prev_seen IS NULL OR v_prev_seen < v_now - public.encounter_session_gap() THEN
      UPDATE public.encounters
      SET session_count = session_count + 1,
          last_recurrence_at = v_now,
          -- Increment when the calendar day changed (reviewer #15).
          distinct_day_count = distinct_day_count
            + CASE WHEN v_prev_day IS DISTINCT FROM v_now::DATE THEN 1 ELSE 0 END,
          last_seen_day = v_now::DATE,
          last_seen_at = v_now,
          range_type = CASE
            WHEN range_type::TEXT LIKE 'feet_%' AND v_band::TEXT LIKE 'feet_%'
                 AND public.range_band_rank(v_band) < public.range_band_rank(range_type)
              THEN v_band ELSE range_type END
          -- confidence unchanged (GPS is veto-only; reviewer #16)
      WHERE id = v_enc_id;

      INSERT INTO public.encounter_sessions (encounter_id, started_at, last_seen_at, best_range)
      VALUES (v_enc_id, v_now, v_now, v_band);
    ELSE
      -- Same crossing: extend it, keep the running best band. A crossing that
      -- spans midnight (23:50 -> 00:10, under the gap) still touches TWO
      -- calendar days, so the day counter must advance here too (reviewer #15).
      UPDATE public.encounters
      SET last_seen_at = v_now,
          distinct_day_count = distinct_day_count
            + CASE WHEN last_seen_day IS DISTINCT FROM v_now::DATE THEN 1 ELSE 0 END,
          last_seen_day = v_now::DATE,
          range_type = CASE
            WHEN range_type::TEXT LIKE 'feet_%' AND v_band::TEXT LIKE 'feet_%'
                 AND public.range_band_rank(v_band) < public.range_band_rank(range_type)
              THEN v_band ELSE range_type END
      WHERE id = v_enc_id;

      UPDATE public.encounter_sessions es
      SET last_seen_at = v_now,
          best_range = CASE
            WHEN es.best_range IS NULL THEN v_band
            WHEN es.best_range::TEXT LIKE 'feet_%' AND v_band::TEXT LIKE 'feet_%'
                 AND public.range_band_rank(v_band) < public.range_band_rank(es.best_range)
              THEN v_band ELSE es.best_range END
      WHERE es.id = (
        SELECT id FROM public.encounter_sessions
        WHERE encounter_id = v_enc_id ORDER BY started_at DESC LIMIT 1
      );
    END IF;
  END IF;

  encounter_id := v_enc_id;
  other_user_id := v_claim.user_id;
  created_new := v_new;
  RETURN NEXT;
END;
$$;

-- Recurrence summary for a pair (participant-only). Powers "seen N times",
-- "N times in the last 7 days", and the familiarity signal in the feed.
CREATE OR REPLACE FUNCTION public.encounter_recurrence(
  p_encounter_id BIGINT,
  p_window_days INT DEFAULT 7
)
RETURNS TABLE (
  session_count INT,
  distinct_day_count INT,
  first_seen_at TIMESTAMPTZ,
  last_seen_at TIMESTAMPTZ,
  sessions_in_window INT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT
    e.session_count,
    e.distinct_day_count,
    e.first_seen_at,
    e.last_seen_at,
    (SELECT count(*)::INT FROM public.encounter_sessions es
       WHERE es.encounter_id = e.id
         AND es.started_at > NOW() - make_interval(days => GREATEST(1, p_window_days)))
  FROM public.encounters e
  WHERE e.id = p_encounter_id
    AND (e.user_a = auth.uid() OR e.user_b = auth.uid());
$$;

GRANT EXECUTE ON FUNCTION public.encounter_recurrence(BIGINT, INT) TO authenticated;

-- get_my_encounters: carry the recurrence counters so the feed can show
-- "you've crossed paths N times" and rank familiar faces higher.
--
-- This ADDS output columns (11 -> 15). PostgreSQL forbids changing a function's
-- return-row type via CREATE OR REPLACE (OUT params are part of the type), so
-- the old definition must be dropped first — and the DROP discards its ACL, so
-- the GRANT below is required to restore authenticated access.
DROP FUNCTION IF EXISTS public.get_my_encounters(INT, INT, NUMERIC);

CREATE OR REPLACE FUNCTION public.get_my_encounters(
  p_limit INT DEFAULT 50,
  p_offset INT DEFAULT 0,
  p_min_age_hours NUMERIC DEFAULT 4
)
RETURNS TABLE (
  encounter_id BIGINT,
  other_user_id UUID,
  display_name TEXT,
  photo_urls TEXT[],
  neighborhood TEXT,
  encounter_time TIMESTAMPTZ,
  range_type public.range_type,
  my_action public.action_type,
  other_action public.action_type,
  status public.encounter_status,
  is_photo_verified BOOLEAN,
  session_count INT,
  distinct_day_count INT,
  first_seen_at TIMESTAMPTZ,
  last_seen_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT
    e.id,
    CASE WHEN e.user_a = auth.uid() THEN e.user_b ELSE e.user_a END,
    'Someone nearby'::TEXT,
    p.photo_urls,
    e.neighborhood,
    e.encounter_time,
    e.range_type,
    (SELECT ea.action FROM public.encounter_actions ea
     WHERE ea.user_id = auth.uid() AND ea.encounter_id = e.id),
    NULL::public.action_type,
    e.status,
    TRUE,
    e.session_count,
    e.distinct_day_count,
    COALESCE(e.first_seen_at, e.encounter_time),
    COALESCE(e.last_seen_at, e.encounter_time)
  FROM public.encounters e
  JOIN public.profiles p
    ON p.id = CASE WHEN e.user_a = auth.uid() THEN e.user_b ELSE e.user_a END
  WHERE public.current_user_can_discover()
    AND (e.user_a = auth.uid() OR e.user_b = auth.uid())
    AND e.status = 'active'
    AND e.encounter_time <= NOW() - make_interval(
      secs => (public.encounter_reveal_delay_hours() * 3600)::DOUBLE PRECISION
    )
    AND public.is_discoverable_user(p.id)
    AND NOT public.is_blocked_pair(auth.uid(), p.id)
    AND NOT EXISTS (
      SELECT 1 FROM public.encounter_actions mine
      WHERE mine.encounter_id = e.id AND mine.user_id = auth.uid()
    )
  -- Familiar faces first, then most recent.
  ORDER BY e.session_count DESC, e.encounter_time DESC
  LIMIT LEAST(100, GREATEST(1, COALESCE(p_limit, 50)))
  OFFSET GREATEST(0, COALESCE(p_offset, 0));
$$;

-- Restore the ACL the DROP above discarded.
GRANT EXECUTE ON FUNCTION public.get_my_encounters(INT, INT, NUMERIC) TO authenticated;
