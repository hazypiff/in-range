-- =============================================================================
-- Migration 0015: Remaining full-stack audit items (F1, P3, M6, M8)
-- =============================================================================
-- F1  Note: migration 0003 CASE used feet_100/feet_500 (not in enum). Superseded
--     by range_radius_meters() in 0008 / single_sighting in 0011 — no runtime path.
-- M6  Drop dead nearby_location_pings (use get_locals_feed).
-- M8  is_blocked_pair: only participants (or service_role / null auth) may probe.
-- P3  Schedule run_maintenance every 15 min when pg_cron is available.
-- =============================================================================

-- ----------------------------------------------------------------------------
-- M6: Drop deprecated nearby_location_pings overloads
-- ----------------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'nearby_location_pings'
  LOOP
    EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig || ' CASCADE';
  END LOOP;
END $$;

-- ----------------------------------------------------------------------------
-- M8: Harden is_blocked_pair — no arbitrary pair probing by third parties
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_blocked_pair(a UUID, b UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Authenticated callers may only check pairs they belong to.
  -- service_role / background jobs often have auth.uid() IS NULL — allow.
  IF auth.uid() IS NOT NULL
     AND auth.uid() IS DISTINCT FROM a
     AND auth.uid() IS DISTINCT FROM b THEN
    RAISE EXCEPTION 'Not authorized to probe block status'
      USING ERRCODE = '42501';
  END IF;

  RETURN EXISTS (
    SELECT 1 FROM public.blocks
    WHERE (blocker_id = a AND blocked_id = b)
       OR (blocker_id = b AND blocked_id = a)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.is_blocked_pair(UUID, UUID)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.is_blocked_pair(UUID, UUID) IS
  'True if either user blocked the other. Caller must be a participant (or service).';

-- ----------------------------------------------------------------------------
-- P3: Feet expiry + cleanup cron (best-effort when pg_cron available)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  -- Supabase: enable pg_cron in Dashboard → Database → Extensions if this fails.
  CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'pg_cron not available: % — schedule Edge Function maintenance instead', SQLERRM;
END $$;

DO $$
BEGIN
  -- Unschedule prior job if re-running
  PERFORM cron.unschedule(jobid)
  FROM cron.job
  WHERE jobname = 'in-range-maintenance';
EXCEPTION
  WHEN undefined_table THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  PERFORM cron.schedule(
    'in-range-maintenance',
    '*/15 * * * *',
    $cron$ SELECT public.run_maintenance(); $cron$
  );
  RAISE NOTICE 'Scheduled in-range-maintenance every 15 minutes';
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Could not schedule cron: % — use Edge Function maintenance cron in Dashboard', SQLERRM;
END $$;

-- ----------------------------------------------------------------------------
-- F1 documentation
-- ----------------------------------------------------------------------------
COMMENT ON FUNCTION public.range_radius_meters(public.range_type) IS
  'Canonical range→meters map (feet_10/20/30 + miles_1..200). Replaces obsolete feet_100/feet_500 CASE arms from migration 0003.';

COMMENT ON SCHEMA public IS
  'In Range — migrations 0001–0015. 0003 feet_100/feet_500 CASE is dead; use range_radius_meters.';
