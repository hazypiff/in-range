-- 0050_ncii_per_ip_ratelimit.sql
--
-- Closes the OPEN ITEM flagged in 0038: the anonymous NCII intake was limited
-- per-email and globally, but not per-IP. A per-email limit is trivially evaded
-- with fresh addresses, leaving only the global backstop — so one source could
-- consume the whole hourly budget and bury genuine reports ("intake saturated").
--
-- An RPC cannot see the client IP, so the per-IP check lives at the edge
-- (functions/ncii-intake), which hashes the IP and calls check_ncii_ip_rate()
-- below. This migration adds that counter and, crucially, REVOKEs anon EXECUTE
-- on submit_ncii_report so the rate-limited Edge function is the only intake
-- path (it calls the RPC as service-role).

BEGIN;

-- Per-IP hourly counter. Raw IPs are never stored — the edge passes a SHA-256
-- hash. Service-role/definer only; no RLS policies, so app roles can't read it.
CREATE TABLE IF NOT EXISTS public.ncii_ip_rate (
  ip_hash      TEXT PRIMARY KEY,
  window_start TIMESTAMPTZ NOT NULL DEFAULT now(),
  submissions  INT NOT NULL DEFAULT 0
);
ALTER TABLE public.ncii_ip_rate ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.check_ncii_ip_rate(
  p_ip_hash      TEXT,
  p_hourly_limit INT DEFAULT 5
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_count INT;
BEGIN
  -- Unknown IP: don't block; the email + global backstops still apply.
  IF p_ip_hash IS NULL OR length(p_ip_hash) = 0 THEN
    RETURN;
  END IF;

  -- Opportunistic self-prune: counters are spent after 1 hour, and NCII intake
  -- is low-volume, so keeping the table bounded here avoids coupling to
  -- run_maintenance().
  DELETE FROM public.ncii_ip_rate WHERE window_start < now() - INTERVAL '2 hours';

  INSERT INTO public.ncii_ip_rate (ip_hash, window_start, submissions)
  VALUES (p_ip_hash, now(), 0)
  ON CONFLICT (ip_hash) DO NOTHING;

  UPDATE public.ncii_ip_rate
     SET window_start = CASE WHEN now() - window_start > INTERVAL '1 hour' THEN now() ELSE window_start END,
         submissions  = CASE WHEN now() - window_start > INTERVAL '1 hour' THEN 1   ELSE submissions + 1 END
   WHERE ip_hash = p_ip_hash
   RETURNING submissions INTO v_count;

  IF v_count > p_hourly_limit THEN
    RAISE EXCEPTION 'Too many reports from this network in the last hour. Contact support directly.'
      USING ERRCODE = '53400';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.check_ncii_ip_rate(TEXT, INT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_ncii_ip_rate(TEXT, INT) TO service_role;

-- Route all intake through the rate-limited Edge function: anon can no longer
-- call the RPC directly. The edge invokes it as service-role, so grant that
-- role EXECUTE (0038 granted only anon+authenticated). authenticated is left
-- intact for any in-app report flow.
REVOKE EXECUTE ON FUNCTION public.submit_ncii_report(TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_ncii_report(TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN) TO service_role;

COMMIT;
