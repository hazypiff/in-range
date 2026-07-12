-- Migration 0004: Encounter reveal delay
-- Product (Rahul 2026-07-08): people should not appear on Encounters instantly.
-- Production target: 4 hours after first correlation (saves processing, UX).
-- Testing uses client-side ENCOUNTER_REVEAL_DELAY_HOURS=0 for instant reveal.
--
-- Server-side: get_my_encounters only returns rows older than p_min_age_hours.
-- Default 4. Clients in test mode can pass 0.

-- The return shape gains display_name in this migration. PostgreSQL does not
-- allow CREATE OR REPLACE to change OUT parameters, so remove the 0001
-- signature first. Without this, a clean `supabase db reset` stops here.
DROP FUNCTION IF EXISTS public.get_my_encounters(INT, INT);

CREATE OR REPLACE FUNCTION public.get_my_encounters(
  p_limit INT DEFAULT 50,
  p_offset INT DEFAULT 0,
  p_min_age_hours NUMERIC DEFAULT 4
)
RETURNS TABLE (
  encounter_id BIGINT,
  other_user_id UUID,
  display_name TEXT,
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
    e.id AS encounter_id,
    CASE WHEN e.user_a = auth.uid() THEN e.user_b ELSE e.user_a END AS other_user_id,
    COALESCE(p.display_name, 'Someone') AS display_name,
    e.neighborhood,
    e.encounter_time,
    e.range_type,
    (SELECT action FROM public.encounter_actions WHERE user_id = auth.uid() AND encounter_id = e.id),
    (SELECT action FROM public.encounter_actions WHERE user_id != auth.uid() AND encounter_id = e.id LIMIT 1),
    e.status
  FROM public.encounters e
  LEFT JOIN public.profiles p
    ON p.id = CASE WHEN e.user_a = auth.uid() THEN e.user_b ELSE e.user_a END
  WHERE (e.user_a = auth.uid() OR e.user_b = auth.uid())
    AND e.status = 'active'
    -- Reveal delay: only show after min age (4h prod default, 0 for test clients).
    AND e.encounter_time <= NOW() - make_interval(secs => (p_min_age_hours * 3600)::double precision)
  ORDER BY e.encounter_time DESC
  LIMIT p_limit
  OFFSET p_offset;
$$;

COMMENT ON FUNCTION public.get_my_encounters(INT, INT, NUMERIC) IS
  'Active encounters for current user. p_min_age_hours gates reveal (default 4h). Pass 0 for test/instant.';
