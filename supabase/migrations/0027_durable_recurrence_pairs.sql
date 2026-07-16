-- #8: recurrence lived on the `encounters` row, which the correlator only finds
-- while status='active'. A feet encounter expires after 24 h, so a pair that
-- crosses paths again next week starts a NEW encounter with session_count=1 —
-- the UI reports a first meeting and the crossing history is split.
--
-- Fix: a DURABLE per-pair aggregate (`encounter_pairs`) that is independent of
-- the ephemeral/swipeable encounter row's lifecycle. The correlator updates it
-- every crossing regardless of encounter status, and get_my_encounters reads
-- the counters from it. The `encounters` row stays the swipeable unit.

CREATE TABLE IF NOT EXISTS public.encounter_pairs (
  user_a             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_b             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  session_count      INT NOT NULL DEFAULT 1,
  distinct_day_count INT NOT NULL DEFAULT 1,
  first_seen_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_day      DATE NOT NULL DEFAULT CURRENT_DATE,
  last_recurrence_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  best_range         public.range_type,
  CHECK (user_a < user_b),
  PRIMARY KEY (user_a, user_b)
);
ALTER TABLE public.encounter_pairs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS encounter_pairs_participant_read ON public.encounter_pairs;
CREATE POLICY encounter_pairs_participant_read
  ON public.encounter_pairs FOR SELECT
  USING (user_a = auth.uid() OR user_b = auth.uid());

-- Seed from existing encounters (aggregate in case of historical splits).
INSERT INTO public.encounter_pairs (
  user_a, user_b, session_count, distinct_day_count,
  first_seen_at, last_seen_at, last_seen_day, last_recurrence_at, best_range
)
SELECT e.user_a, e.user_b,
       GREATEST(1, SUM(e.session_count))::INT,
       GREATEST(1, MAX(e.distinct_day_count))::INT,
       MIN(COALESCE(e.first_seen_at, e.encounter_time)),
       MAX(COALESCE(e.last_seen_at, e.encounter_time)),
       MAX(COALESCE(e.last_seen_day, (COALESCE(e.last_seen_at, e.encounter_time))::DATE)),
       MAX(COALESCE(e.last_recurrence_at, e.last_seen_at, e.encounter_time)),
       (ARRAY_AGG(e.range_type ORDER BY public.range_band_rank(e.range_type)))[1]
FROM public.encounters e
GROUP BY e.user_a, e.user_b
ON CONFLICT (user_a, user_b) DO NOTHING;

-- Recurrence bookkeeping moves into a helper the correlator calls. Returns the
-- durable session count so the correlator can also mirror it onto the active
-- encounter row for the current feed.
CREATE OR REPLACE FUNCTION public.bump_encounter_pair(
  p_user_a UUID, p_user_b UUID, p_band public.range_type
)
RETURNS TABLE (session_count INT, distinct_day_count INT, is_new_session BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_now  TIMESTAMPTZ := NOW();
  v_prev TIMESTAMPTZ;
  v_new  BOOLEAN;
BEGIN
  SELECT ep.last_seen_at INTO v_prev
  FROM public.encounter_pairs ep
  WHERE ep.user_a = p_user_a AND ep.user_b = p_user_b
  FOR UPDATE;

  IF NOT FOUND THEN
    INSERT INTO public.encounter_pairs (
      user_a, user_b, session_count, distinct_day_count,
      first_seen_at, last_seen_at, last_seen_day, last_recurrence_at, best_range
    ) VALUES (
      p_user_a, p_user_b, 1, 1, v_now, v_now, v_now::DATE, v_now, p_band
    );
    RETURN QUERY SELECT 1, 1, TRUE;
    RETURN;
  END IF;

  -- New crossing when the quiet gap exceeds the session threshold.
  v_new := v_prev < v_now - public.encounter_session_gap();

  UPDATE public.encounter_pairs ep
  SET session_count = ep.session_count + CASE WHEN v_new THEN 1 ELSE 0 END,
      last_recurrence_at = CASE WHEN v_new THEN v_now ELSE ep.last_recurrence_at END,
      -- Advance the day counter whenever the calendar day changes, in BOTH
      -- the new-crossing and same-crossing (midnight) cases (reviewer #15).
      distinct_day_count = ep.distinct_day_count
        + CASE WHEN ep.last_seen_day IS DISTINCT FROM v_now::DATE THEN 1 ELSE 0 END,
      last_seen_at = v_now,
      last_seen_day = v_now::DATE,
      best_range = CASE
        WHEN ep.best_range IS NULL THEN p_band
        WHEN ep.best_range::TEXT LIKE 'feet_%' AND p_band::TEXT LIKE 'feet_%'
             AND public.range_band_rank(p_band) < public.range_band_rank(ep.best_range)
          THEN p_band ELSE ep.best_range END
  WHERE ep.user_a = p_user_a AND ep.user_b = p_user_b
  RETURNING ep.session_count, ep.distinct_day_count INTO session_count, distinct_day_count;
  is_new_session := v_new;
  RETURN NEXT;
END;
$$;

-- correlate_encounter: recurrence now lives in encounter_pairs (durable), so it
-- survives the 24 h encounter-row expiry (#8). The encounters row stays the
-- ephemeral feed/swipe unit; we still create/refresh the active one.
CREATE OR REPLACE FUNCTION public.correlate_encounter(
  p_observed_token TEXT,
  p_lat DOUBLE PRECISION,
  p_lon DOUBLE PRECISION,
  p_radius_meters DOUBLE PRECISION DEFAULT 50,
  p_time_window_minutes INT DEFAULT 60
)
RETURNS TABLE (encounter_id BIGINT, other_user_id UUID, created_new BOOLEAN)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_claim public.token_claims%ROWTYPE;
  v_user_a UUID; v_user_b UUID; v_enc_id BIGINT;
  v_distance DOUBLE PRECISION; v_rssi INTEGER; v_min_rssi INTEGER;
  v_new BOOLEAN := FALSE; v_sight_range public.range_type; v_band public.range_type;
  v_now TIMESTAMPTZ := NOW();
BEGIN
  IF v_uid IS NULL OR NOT public.current_user_can_discover() THEN RETURN; END IF;
  SELECT * INTO v_claim FROM public.token_claims tc
  WHERE tc.token = lower(p_observed_token) AND tc.user_id <> v_uid
    AND tc.valid_from > NOW() - make_interval(mins => LEAST(30, GREATEST(1, p_time_window_minutes)))
    AND tc.valid_until > NOW() - INTERVAL '2 minutes' LIMIT 1;
  IF NOT FOUND OR NOT public.is_discoverable_user(v_claim.user_id) THEN RETURN; END IF;
  IF public.is_blocked_pair(v_uid, v_claim.user_id) THEN RETURN; END IF;

  SELECT s.rssi, s.range_type INTO v_rssi, v_sight_range FROM public.sightings s
  WHERE s.observer_user_id = v_uid AND s.observed_token = lower(p_observed_token)
  ORDER BY s.observed_at DESC LIMIT 1;
  v_min_rssi := CASE COALESCE(v_claim.range_type,'feet_10')
                  WHEN 'feet_10' THEN -75 WHEN 'feet_20' THEN -85 ELSE -95 END;
  IF v_rssi IS NULL OR v_rssi < v_min_rssi THEN RETURN; END IF;

  IF p_lat IS NOT NULL AND p_lon IS NOT NULL
     AND v_claim.approx_lat IS NOT NULL AND v_claim.approx_lon IS NOT NULL THEN
    v_distance := ST_Distance(
      ST_SetSRID(ST_MakePoint(p_lon, p_lat),4326)::geography,
      ST_SetSRID(ST_MakePoint(v_claim.approx_lon, v_claim.approx_lat),4326)::geography);
    IF v_distance > LEAST(400.0, GREATEST(5.0, p_radius_meters)) THEN RETURN; END IF;
  END IF;

  IF v_sight_range IS NOT NULL AND v_sight_range::TEXT LIKE 'feet_%'
    THEN v_band := v_sight_range;
    ELSE v_band := COALESCE(v_claim.range_type, 'feet_10'); END IF;

  v_user_a := LEAST(v_uid, v_claim.user_id);
  v_user_b := GREATEST(v_uid, v_claim.user_id);
  PERFORM pg_advisory_xact_lock(hashtextextended(v_user_a::TEXT || v_user_b::TEXT, 0));

  -- Durable recurrence (survives encounter expiry).
  PERFORM public.bump_encounter_pair(v_user_a, v_user_b, v_band);

  -- Ephemeral feed row: reuse the active one or create it.
  SELECT id INTO v_enc_id FROM public.encounters
  WHERE user_a = v_user_a AND user_b = v_user_b AND status = 'active'
  ORDER BY encounter_time DESC LIMIT 1 FOR UPDATE;

  IF v_enc_id IS NULL THEN
    INSERT INTO public.encounters (user_a,user_b,neighborhood,encounter_time,last_seen_at,range_type,confidence,status)
    VALUES (v_user_a,v_user_b,'Near you',v_now,v_now,v_band,0.8,'active') RETURNING id INTO v_enc_id;
    v_new := TRUE;
  ELSE
    UPDATE public.encounters e SET last_seen_at = v_now,
      range_type = CASE WHEN e.range_type::TEXT LIKE 'feet_%' AND v_band::TEXT LIKE 'feet_%'
                        AND public.range_band_rank(v_band) < public.range_band_rank(e.range_type)
                        THEN v_band ELSE e.range_type END
    WHERE e.id = v_enc_id;
  END IF;

  encounter_id := v_enc_id; other_user_id := v_claim.user_id; created_new := v_new;
  RETURN NEXT;
END;
$$;

-- get_my_encounters: recurrence counters now come from encounter_pairs.
DROP FUNCTION IF EXISTS public.get_my_encounters(INT, INT, NUMERIC);
CREATE OR REPLACE FUNCTION public.get_my_encounters(
  p_limit INT DEFAULT 50, p_offset INT DEFAULT 0, p_min_age_hours NUMERIC DEFAULT 4
)
RETURNS TABLE (
  encounter_id BIGINT, other_user_id UUID, display_name TEXT, photo_urls TEXT[],
  neighborhood TEXT, encounter_time TIMESTAMPTZ, range_type public.range_type,
  my_action public.action_type, other_action public.action_type,
  status public.encounter_status, is_photo_verified BOOLEAN,
  session_count INT, distinct_day_count INT, first_seen_at TIMESTAMPTZ, last_seen_at TIMESTAMPTZ
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
  SELECT e.id,
    CASE WHEN e.user_a = auth.uid() THEN e.user_b ELSE e.user_a END,
    'Someone nearby'::TEXT, p.photo_urls, e.neighborhood, e.encounter_time, e.range_type,
    (SELECT ea.action FROM public.encounter_actions ea WHERE ea.user_id = auth.uid() AND ea.encounter_id = e.id),
    NULL::public.action_type, e.status, TRUE,
    COALESCE(ep.session_count, 1), COALESCE(ep.distinct_day_count, 1),
    COALESCE(ep.first_seen_at, e.encounter_time), COALESCE(ep.last_seen_at, e.last_seen_at, e.encounter_time)
  FROM public.encounters e
  JOIN public.profiles p ON p.id = CASE WHEN e.user_a = auth.uid() THEN e.user_b ELSE e.user_a END
  LEFT JOIN public.encounter_pairs ep ON ep.user_a = e.user_a AND ep.user_b = e.user_b
  WHERE public.current_user_can_discover()
    AND (e.user_a = auth.uid() OR e.user_b = auth.uid()) AND e.status = 'active'
    AND e.encounter_time <= NOW() - make_interval(secs => (public.encounter_reveal_delay_hours() * 3600)::DOUBLE PRECISION)
    AND public.is_discoverable_user(p.id) AND NOT public.is_blocked_pair(auth.uid(), p.id)
    AND NOT EXISTS (SELECT 1 FROM public.encounter_actions mine WHERE mine.encounter_id = e.id AND mine.user_id = auth.uid())
  ORDER BY COALESCE(ep.session_count, 1) DESC, e.encounter_time DESC
  LIMIT LEAST(100, GREATEST(1, COALESCE(p_limit, 50))) OFFSET GREATEST(0, COALESCE(p_offset, 0));
$$;
GRANT EXECUTE ON FUNCTION public.get_my_encounters(INT, INT, NUMERIC) TO authenticated;
