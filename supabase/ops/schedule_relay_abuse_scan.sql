-- OPS (not a schema migration): schedule the #6 step-4 relay-abuse scan.
--
-- scan_relay_abuse() (migration 0032) is inert until something runs it. This
-- registers a pg_cron job to run it every 15 minutes over a 30-minute lookback
-- (overlap so nothing between runs is missed; note_abuse_flag de-dupes per
-- (user, reason) over 5 min, so overlap does not spam the table).
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
-- Flags land in public.beacon_abuse_flags (ops/service only). Read them with the
-- service role:
--   SELECT reason, count(*), max(created_at)
--   FROM public.beacon_abuse_flags
--   WHERE created_at > now() - interval '24 hours'
--   GROUP BY reason ORDER BY 2 DESC;

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
