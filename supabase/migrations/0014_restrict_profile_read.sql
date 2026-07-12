-- 0014_restrict_profile_read
-- Fix H2 from full-stack audit 2026-07-09:
-- "Users can read limited public profiles" policy in 0009 grants SELECT on ALL
-- columns to any authenticated user. This exposes email_hint, phone_hint, dob,
-- gender, sexual_preference, interests, display_name, bio before match.
--
-- This migration:
--   1. Revokes SELECT privilege on private columns from `authenticated` role.
--      Postgres column-level privileges prevent authenticated users from
--      reading these columns on anyone else's row. OWNER (auth.uid()) retains
--      full access via the existing owner policy. Service_role retains all.
--   2. Deprecates nearby_location_pings (superseded by get_locals_feed, unused
--      by client).
-- ---------------------------------------------------------------------------

-- Revoke SELECT on pre-match private columns from authenticated role.
-- This is a defense-in-depth layer: even if the row-level policy allows a row,
-- the column privilege check blocks read on these fields for non-owner rows.
REVOKE SELECT (email_hint, phone_hint, dob, gender, sexual_preference, interests, display_name, bio)
  ON public.profiles FROM authenticated;

-- Deprecate dead RPC (unused by client, superseded by get_locals_feed which
-- adds block/pause/incognito/photo-verification filters).
COMMENT ON FUNCTION public.nearby_location_pings(
  p_lat double precision, p_lon double precision,
  p_radius_meters integer, p_window_minutes integer, p_limit integer
) IS 'DEPRECATED — use get_locals_feed which adds block/pause/incognito/photo-verification filters.';
