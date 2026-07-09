-- =============================================================================
-- Migration 0013: Mandatory photo verification gates pre-match discoverability
-- =============================================================================
-- Product (outline §4, §11): photo verification is mandatory.
-- Pre-match feeds (Encounters + Locals) must not surface unverified profiles.
-- Post-match (get_my_matches) stays unlocked — verification already passed or
-- was mutual; chat should not re-hide photos after match.
--
-- Fixes:
--   1. get_my_encounters — dead CASE both arms returned photo_urls; WHERE now
--      requires is_photo_verified = TRUE.
--   2. get_locals_feed — same discoverability gate.
-- =============================================================================

-- ----------------------------------------------------------------------------
-- 1. get_my_encounters — verified only, photo-only pre-match
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_my_encounters(INT, INT);
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
  is_photo_verified BOOLEAN
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    e.id AS encounter_id,
    CASE WHEN e.user_a = auth.uid() THEN e.user_b ELSE e.user_a END AS other_user_id,
    -- Pre-match: name hidden (product rule)
    'Someone nearby'::TEXT AS display_name,
    -- Only verified profiles reach this query — return photos for swipe UI
    p.photo_urls,
    e.neighborhood,
    e.encounter_time,
    e.range_type,
    (SELECT action FROM public.encounter_actions WHERE user_id = auth.uid() AND encounter_id = e.id),
    (SELECT action FROM public.encounter_actions
     WHERE user_id <> auth.uid() AND encounter_id = e.id LIMIT 1),
    e.status,
    TRUE AS is_photo_verified
  FROM public.encounters e
  INNER JOIN public.profiles p
    ON p.id = CASE WHEN e.user_a = auth.uid() THEN e.user_b ELSE e.user_a END
  WHERE (e.user_a = auth.uid() OR e.user_b = auth.uid())
    AND e.status = 'active'
    AND e.encounter_time <= NOW() - make_interval(secs => (p_min_age_hours * 3600)::double precision)
    AND NOT public.is_blocked_pair(
      auth.uid(),
      CASE WHEN e.user_a = auth.uid() THEN e.user_b ELSE e.user_a END
    )
    AND COALESCE(p.is_paused, FALSE) = FALSE
    AND p.deleted_at IS NULL
    AND COALESCE(p.is_active, TRUE) = TRUE
    AND COALESCE(array_length(p.photo_urls, 1), 0) > 0
    -- Mandatory verification: not discoverable until approved
    AND COALESCE(p.is_photo_verified, FALSE) = TRUE
    AND NOT EXISTS (
      SELECT 1 FROM public.encounter_actions ea
      WHERE ea.encounter_id = e.id AND ea.user_id = auth.uid()
    )
  ORDER BY e.encounter_time DESC
  LIMIT p_limit
  OFFSET p_offset;
$$;

COMMENT ON FUNCTION public.get_my_encounters(INT, INT, NUMERIC) IS
  'Pre-match encounters: photo + neighborhood only. Requires other user is_photo_verified.';

-- ----------------------------------------------------------------------------
-- 2. get_locals_feed — verified only
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_locals_feed(
  p_lat DOUBLE PRECISION,
  p_lon DOUBLE PRECISION,
  p_range public.range_type DEFAULT 'miles_10',
  p_limit INT DEFAULT 50
)
RETURNS TABLE (
  user_id UUID,
  distance_m DOUBLE PRECISION,
  neighborhood TEXT,
  photo_urls TEXT[],
  is_photo_verified BOOLEAN,
  is_boosted BOOLEAN,
  last_ping_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_radius DOUBLE PRECISION;
  v_window INT;
  v_point GEOGRAPHY;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  v_radius := public.range_radius_meters(p_range);
  v_window := public.range_time_window_minutes(p_range);
  v_point := ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography;

  RETURN QUERY
  SELECT DISTINCT ON (lp.user_id)
    lp.user_id,
    ST_Distance(lp.geo, v_point) AS distance_m,
    lp.neighborhood,
    pr.photo_urls,
    TRUE AS is_photo_verified,
    public.has_active_boost(lp.user_id),
    lp.created_at
  FROM public.location_pings lp
  JOIN public.profiles pr ON pr.id = lp.user_id
  WHERE lp.user_id <> v_uid
    AND lp.created_at > NOW() - (v_window || ' minutes')::interval
    AND ST_DWithin(lp.geo, v_point, v_radius)
    AND COALESCE(pr.is_paused, FALSE) = FALSE
    AND pr.deleted_at IS NULL
    AND pr.is_active
    AND COALESCE(pr.is_incognito, FALSE) = FALSE
    AND COALESCE(array_length(pr.photo_urls, 1), 0) > 0
    -- Mandatory verification: not discoverable until approved
    AND COALESCE(pr.is_photo_verified, FALSE) = TRUE
    AND NOT public.is_blocked_pair(v_uid, lp.user_id)
    AND public.preferences_compatible(v_uid, lp.user_id)
  ORDER BY lp.user_id, public.has_active_boost(lp.user_id) DESC, lp.created_at DESC
  LIMIT p_limit;
END;
$$;

COMMENT ON FUNCTION public.get_locals_feed IS
  'Locals tab: nearby profiles with photos. Requires is_photo_verified (mandatory).';

-- ----------------------------------------------------------------------------
-- 3. Belt-and-suspenders: never return unverified photo_urls from public profile
--    SELECT policy remains, but clients should use RPCs for feeds.
-- ----------------------------------------------------------------------------
-- (No change to get_my_matches — post-match unlock is intentional.)
