-- 0061_close_wake_batch_privilege_hole.sql
--
-- SECURITY FIX. public.claim_proximity_wake_batch (0057:120) shipped with no
-- GRANT and no REVOKE — the only function in the schema with neither. Its
-- proacl was therefore NULL, which in Postgres means "built-in default", and
-- the built-in default for a function is EXECUTE TO PUBLIC. anon and
-- authenticated inherit through PUBLIC.
--
-- Confirmed by execution, not by reading, against a Supabase-bootstrapped
-- database with 0001..0060 applied:
--
--   SET ROLE anon;
--   SELECT * FROM public.proximity_wake_requests;      -- permission denied
--   SELECT * FROM public.claim_proximity_wake_batch(200);
--     -> 1 | 11111111-... | {"geohash":"u4pruyd","hashed_bssid":"abc"}
--
-- SECURITY DEFINER bypasses both the table's service_role-only RLS (0057:109)
-- and its service_role-only grant (0058:38). The function takes no caller
-- filter, so an unauthenticated caller holding only the publishable anon key
-- could drain up to 200 rows of {user_id, geohash, hashed_bssid} for arbitrary
-- users, and burn each row's 5-attempt budget (0057:135) while doing it.
--
-- NOT EXPLOITABLE IN PRODUCTION AS OF THIS COMMIT: prod is at 0055; migrations
-- 0056-0060 are undeployed. This lands before them so the chain is safe to
-- deploy as a unit. Do not deploy 0056-0060 without this file.
--
-- ---------------------------------------------------------------------------
-- Why this migration does not simply "fix the default-privilege net"
-- ---------------------------------------------------------------------------
-- 0019:2578 already contains
--
--   ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS
--     FROM PUBLIC;
--
-- and it does not work. Measured on the same database: creating a fresh
-- SECURITY DEFINER function as postgres in schema public yields proacl NULL
-- and has_function_privilege('anon', ..., 'EXECUTE') = true. Adding
-- "FROM anon, authenticated" to that statement was also tested and also left
-- the new function anon-executable.
--
-- So every function in this schema is protected by its own explicit REVOKE and
-- nothing else. The 0019 net has never caught anything, and a comment that
-- says "Lock down future migrations too" has been giving false assurance for
-- 42 migrations. The durable control is therefore NOT another default-privilege
-- statement — it is the enumerating assertion added to
-- supabase/tests/security_regression.sql in this same commit, which fails if
-- ANY SECURITY DEFINER function in public is executable by anon.
--
-- The ALTER DEFAULT PRIVILEGES below is kept as defence in depth only. It is
-- harmless if it is inert, and it may bind on a cluster whose role setup
-- differs from the one measured here. It is explicitly NOT the fix.

-- ---------------------------------------------------------------------------
-- 1. The instance
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.claim_proximity_wake_batch(INT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_proximity_wake_batch(INT) TO service_role;

COMMENT ON FUNCTION public.claim_proximity_wake_batch IS
  'Drains pending proximity wake requests for the Edge worker. service_role ONLY — SECURITY DEFINER, no caller filter, returns other users'' user_id and coarse location hint. Never grant to anon or authenticated.';

-- ---------------------------------------------------------------------------
-- 2. The class (defence in depth; see header — measured inert, kept anyway)
-- ---------------------------------------------------------------------------
-- Without FOR ROLE these bind only to the role executing the migration, which
-- is why 0019's version never covered objects created by other roles. Naming
-- the roles explicitly is a no-op where they are absent, so this is safe to
-- run on any cluster; failure to alter a role we are not a member of is
-- caught and reported rather than aborting the migration.
DO $$
BEGIN
  EXECUTE 'ALTER DEFAULT PRIVILEGES IN SCHEMA public '
          'REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'default privileges (current role) not altered: %', SQLERRM;
END $$;

DO $$
BEGIN
  EXECUTE 'ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public '
          'REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'default privileges (supabase_admin) not altered: %', SQLERRM;
END $$;

-- ---------------------------------------------------------------------------
-- 3. Sweep: any other SECURITY DEFINER function anon can reach
-- ---------------------------------------------------------------------------
-- The audit at the time of writing found claim_proximity_wake_batch to be the
-- only application function anon could execute (PostGIS's st_estimatedextent
-- is an extension-owned exception and is excluded). This block is written as a
-- sweep rather than a single statement so that anything else that slipped in
-- undetected is closed here, and so re-running the migration is idempotent.
--
-- It revokes from anon only. authenticated is the legitimate client RPC
-- surface for ~42 functions and must not be swept.
DO $$
DECLARE
  r RECORD;
  v_count INT := 0;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef
      AND has_function_privilege('anon', p.oid, 'EXECUTE')
      AND NOT EXISTS (
        SELECT 1 FROM pg_depend d
        JOIN pg_extension e ON e.oid = d.refobjid
        WHERE d.objid = p.oid AND d.deptype = 'e'
      )
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', r.sig);
    RAISE NOTICE 'revoked anon EXECUTE on %', r.sig;
    v_count := v_count + 1;
  END LOOP;
  RAISE NOTICE 'privilege sweep complete: % function(s) closed', v_count;
END $$;

-- ---------------------------------------------------------------------------
-- 4. Assert the hole is shut, in the same transaction that opened the fix
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  ASSERT NOT has_function_privilege(
    'anon', 'public.claim_proximity_wake_batch(int)', 'EXECUTE'),
    'anon can still execute claim_proximity_wake_batch';
  ASSERT NOT has_function_privilege(
    'authenticated', 'public.claim_proximity_wake_batch(int)', 'EXECUTE'),
    'authenticated can still execute claim_proximity_wake_batch';
  ASSERT has_function_privilege(
    'service_role', 'public.claim_proximity_wake_batch(int)', 'EXECUTE'),
    'service_role lost EXECUTE on claim_proximity_wake_batch';
END $$;
