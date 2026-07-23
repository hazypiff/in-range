-- 0049_schedule_maintenance_edge_worker.sql
--
-- Closes the OPS GAP from the privacy audits: prod cron ran only
-- run_maintenance() (SQL, which just ENQUEUES deleted objects), so queued
-- profile photos were never physically deleted. Postgres cannot delete
-- storage.objects — only the Storage API can, and that lives in the
-- `maintenance` Edge function. This schedules that Edge worker every 15 min via
-- pg_net, so the storage_deletion_queue actually drains.
--
-- The existing `in-range-maintenance` SQL cron is intentionally LEFT in place as
-- a reliable belt: core maintenance (feet expiry, account purge, reveals) keeps
-- running even if pg_net/Edge is unavailable. The Edge worker also calls
-- run_maintenance() first — that is idempotent/time-gated, so the small overlap
-- is harmless; its unique contribution is the physical Storage-API deletion and
-- the notification-outbox drain.
--
-- SECURITY: the service key is read from Vault (`edge_service_key`) at call time.
-- It is never written into this migration or stored as plaintext in
-- cron.job.command — the command only contains a SELECT against
-- vault.decrypted_secrets. The Vault secret is provisioned out-of-band (it is a
-- credential, not migration content); on a fresh/local rebuild where it is
-- absent, the cron simply posts an unauthorized request that the Edge function
-- rejects with 401 — no data effect.

-- Enable pg_net (guarded: absent on some local/dev images).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_net') THEN
    EXECUTE 'CREATE EXTENSION IF NOT EXISTS pg_net';
  ELSE
    RAISE NOTICE 'pg_net unavailable; edge maintenance cron not scheduled (dev)';
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'pg_net enable failed: % — schedule the maintenance Edge cron in the Dashboard', SQLERRM;
END $$;

-- Unschedule prior copy if re-running.
DO $$
BEGIN
  PERFORM cron.unschedule(jobid)
  FROM cron.job
  WHERE jobname = 'in-range-storage-drain';
EXCEPTION
  WHEN undefined_table THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN OTHERS THEN NULL;
END $$;

-- Schedule the Edge worker every 15 min (only if pg_net is present).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN
    PERFORM cron.schedule(
      'in-range-storage-drain',
      '*/15 * * * *',
      $job$
      SELECT net.http_post(
        url     := 'https://riigipzlyqeaadyvbuty.supabase.co/functions/v1/maintenance',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (
            SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'edge_service_key'
          )
        ),
        body    := '{}'::jsonb,
        timeout_milliseconds := 20000
      );
      $job$
    );
    RAISE NOTICE 'Scheduled in-range-storage-drain (maintenance Edge worker) every 15 minutes';
  ELSE
    RAISE NOTICE 'pg_net not installed; skipping edge maintenance cron (dev)';
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Could not schedule edge cron: % — use the Dashboard scheduled function instead', SQLERRM;
END $$;
