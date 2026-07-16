-- OPS (not a schema migration): schedule the #6 step-4 relay-abuse scan.
--
-- scan_relay_abuse() (migration 0032) is inert until something runs it. This
-- registers a pg_cron job to run it every 15 minutes over a 30-minute lookback
-- (overlap so nothing between runs is missed; migration 0033 assigns a stable
-- evidence fingerprint, so overlap does not count one incident twice).
--
-- Idempotent and safe to re-run: cron.schedule upserts by job name. Guarded so
-- it no-ops where pg_cron is absent. Run this against a project that has pg_cron
-- installed (prod does).
--
--   Deploy: psql / Supabase SQL editor / management API — run this file once.
--   Inspect: SELECT * FROM cron.job WHERE jobname = 'relay-abuse-scan';
--            SELECT * FROM cron.job_run_details WHERE jobid =
--              (SELECT jobid FROM cron.job WHERE jobname='relay-abuse-scan')
--            ORDER BY start_time DESC LIMIT 20;
--   Disable: SELECT cron.unschedule('relay-abuse-scan');
--
-- Flags land in public.beacon_abuse_flags (ops/service only). After migration
-- 0033, use v_beacon_abuse_triage_24h / v_beacon_abuse_digest_24h; see
-- docs/RELAY_ABUSE_RUNBOOK.md for the response policy and health queries.

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule(
      'relay-abuse-scan',
      '*/15 * * * *',
      $cmd$ SELECT public.scan_relay_abuse(INTERVAL '30 minutes'); $cmd$
    );
    RAISE NOTICE 'scheduled relay-abuse-scan (every 15 min)';
  ELSE
    RAISE NOTICE 'pg_cron not installed; enable it, then re-run this file';
  END IF;
END $$;
