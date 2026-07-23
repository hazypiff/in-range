-- 0051_harden_pg_net_and_ncii_rate.sql
--
-- Follow-ups from the 0049/0050 adversarial audit.
--
-- Index ncii_ip_rate(window_start): check_ncii_ip_rate() self-prunes on every
-- call with `WHERE window_start < now() - 2h`; without an index that is a full
-- scan per intake. (Audit MEDIUM-4.)
--
-- ── Audit notes (no code change possible/needed) ────────────────────────────
-- MEDIUM-5 (pg_net key transit): net.http_request_queue holds the resolved
--   `Authorization: Bearer <service-role key>` header until the worker drains
--   it, and Supabase's default pg_net install grants the `net` schema to
--   PUBLIC/anon/authenticated (grantor = supabase_admin). This CANNOT be revoked
--   as `postgres` (verified: REVOKE is a no-op, we lack authority over
--   supabase_admin's grants). It is NOT app-reachable regardless: PostgREST does
--   not expose `net` (REST → 406 "Invalid schema: net"), and anon/authenticated
--   are NOLOGIN roles with no direct SQL path, so the grant is inert for them.
--   The key is readable only by roles that already have full DB access
--   (postgres/supabase_admin/service_role). To eliminate the transit entirely,
--   switch scheduling from pg_net to a Dashboard Scheduled Function (manual, no
--   key in any table) — optional hardening, tracked in SAFETY_RUNBOOK §0.
-- MEDIUM-3 (payload caps): fixed in the ncii-intake Edge function (max lengths
--   on email/description/name/target_hint), not here.
-- HIGH-1 (XFF[0] spoofing): empirically DISPROVEN — Supabase controls the
--   leftmost X-Forwarded-For entry, so a stored ip_hash never matches a
--   client-supplied value; taking [0] is correct on this platform.

BEGIN;

CREATE INDEX IF NOT EXISTS ncii_ip_rate_window_start_idx
  ON public.ncii_ip_rate (window_start);

COMMIT;
