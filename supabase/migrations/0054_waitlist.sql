-- 0054_waitlist.sql
--
-- Public early-access waitlist for inrange.life. The landing page's email
-- capture posts to the waitlist-join Edge function, which (like ncii-intake)
-- adds the one control an RPC can't: a per-IP rate limit. The function then
-- calls join_waitlist() as service-role. Nothing here is exposed to anon or
-- authenticated — the rate-limited edge path is the only way in.
--
-- Privacy posture matches the rest of the schema: we store the email, when it
-- arrived, and which page section sent it. No IPs (the rate counter stores a
-- SHA-256 hash that self-prunes), no tracking blob.

BEGIN;

CREATE TABLE IF NOT EXISTS public.waitlist (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  email      TEXT NOT NULL,
  source     TEXT,                       -- landing-page section ('hero', 'footer', …)
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT waitlist_email_len CHECK (length(email) BETWEEN 3 AND 320),
  CONSTRAINT waitlist_source_len CHECK (source IS NULL OR length(source) <= 40)
);
CREATE UNIQUE INDEX IF NOT EXISTS waitlist_email_uniq ON public.waitlist (lower(email));
ALTER TABLE public.waitlist ENABLE ROW LEVEL SECURITY;
-- No policies: service-role/definer only.

-- Per-IP hourly counter, same shape as ncii_ip_rate (0050) but a separate
-- table so waitlist noise can never starve NCII intake.
CREATE TABLE IF NOT EXISTS public.waitlist_ip_rate (
  ip_hash      TEXT PRIMARY KEY,
  window_start TIMESTAMPTZ NOT NULL DEFAULT now(),
  submissions  INT NOT NULL DEFAULT 0
);
ALTER TABLE public.waitlist_ip_rate ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.check_waitlist_ip_rate(
  p_ip_hash      TEXT,
  p_hourly_limit INT DEFAULT 20
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_count INT;
BEGIN
  IF p_ip_hash IS NULL OR length(p_ip_hash) = 0 THEN
    RETURN;
  END IF;

  DELETE FROM public.waitlist_ip_rate WHERE window_start < now() - INTERVAL '2 hours';

  INSERT INTO public.waitlist_ip_rate (ip_hash, window_start, submissions)
  VALUES (p_ip_hash, now(), 0)
  ON CONFLICT (ip_hash) DO NOTHING;

  UPDATE public.waitlist_ip_rate
     SET window_start = CASE WHEN now() - window_start > INTERVAL '1 hour' THEN now() ELSE window_start END,
         submissions  = CASE WHEN now() - window_start > INTERVAL '1 hour' THEN 1   ELSE submissions + 1 END
   WHERE ip_hash = p_ip_hash
   RETURNING submissions INTO v_count;

  IF v_count > p_hourly_limit THEN
    RAISE EXCEPTION 'Too many signups from this network in the last hour.'
      USING ERRCODE = '53400';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.check_waitlist_ip_rate(TEXT, INT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_waitlist_ip_rate(TEXT, INT) TO service_role;

-- Idempotent insert: signing up twice is a no-op, and the caller can't tell
-- whether an address was already on the list (no enumeration oracle).
CREATE OR REPLACE FUNCTION public.join_waitlist(
  p_email  TEXT,
  p_source TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF p_email IS NULL OR p_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' OR length(p_email) > 320 THEN
    RAISE EXCEPTION 'invalid email' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.waitlist (email, source)
  VALUES (lower(trim(p_email)), left(p_source, 40))
  ON CONFLICT (lower(email)) DO NOTHING;
END;
$$;

REVOKE ALL ON FUNCTION public.join_waitlist(TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.join_waitlist(TEXT, TEXT) TO service_role;

COMMIT;
