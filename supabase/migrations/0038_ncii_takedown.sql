-- 0038_ncii_takedown.sql
--
-- TAKE IT DOWN Act — NCII notice-and-removal.
--
-- Platform obligations became enforceable 2026-05-19. Covered platforms include
-- any service "primarily providing a forum for user-generated content,"
-- expressly including messaging and image sharing. In Range qualifies: we have
-- profile photos, chat media, and private messaging. FTC-enforced as a §5
-- violation at $53,088 per violation.
--
-- Four statutory duties, and how each is met here:
--   1. Intake a victim can use WITHOUT AN ACCOUNT
--        -> submit_ncii_report(), granted to anon.
--   2. Removal within 48 hours of a valid request
--        -> deadline_at stamped at intake; v_ncii_sla surfaces the clock.
--   3. Remove known IDENTICAL COPIES, not just the reported item
--        -> media_hashes + ncii_resolve() fans out by sha256 across buckets.
--   4. Prove we did it
--        -> every request and transition retained; resolution timestamped.
--
-- DESIGN NOTE on the unauthenticated endpoint. It is a legal requirement, so it
-- cannot be locked behind auth, which makes it the only anon-writable surface in
-- the system. Two consequences we design around:
--   * Reports are CLAIMS, never automatic deletions. A human reviews before
--     ncii_resolve() runs. An anonymous endpoint that auto-deleted content would
--     be a trivially weaponisable takedown service.
--   * Submissions are rate-limited per email and globally. The per-IP limit
--     belongs at the edge (an RPC cannot see the client IP) -- see the OPEN
--     ITEM at the end of this file.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Content hashes — the substrate for "remove known identical copies".
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.media_hashes (
  bucket_id   TEXT NOT NULL,
  object_name TEXT NOT NULL,
  sha256      TEXT NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
  user_id     UUID,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (bucket_id, object_name)
);

-- The whole point: find every copy of a reported image.
CREATE INDEX IF NOT EXISTS idx_media_hashes_sha256 ON public.media_hashes (sha256);

ALTER TABLE public.media_hashes ENABLE ROW LEVEL SECURITY;

-- Uploaders record their own hashes; nobody can read the table. Read access
-- would turn it into a confirm-whether-this-image-exists oracle.
CREATE POLICY "Users record own media hashes"
  ON public.media_hashes FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

REVOKE ALL ON TABLE public.media_hashes FROM PUBLIC, anon;
GRANT INSERT ON TABLE public.media_hashes TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.media_hashes TO service_role;

COMMENT ON TABLE public.media_hashes IS
  'SHA-256 of uploaded media, so a TAKE IT DOWN removal can reach identical copies. Insert-only for users; never readable by them (would be an existence oracle).';

-- ---------------------------------------------------------------------------
-- 2. The report record.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ncii_reports (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  received_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- The 48-hour statutory clock, fixed at intake so later edits cannot move it.
  deadline_at     TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '48 hours'),

  reporter_email  TEXT NOT NULL,
  reporter_name   TEXT,
  -- Statute covers the depicted individual or an authorized representative.
  is_authorized   BOOLEAN NOT NULL DEFAULT TRUE,
  reporter_user_id UUID,          -- set only if they happened to be signed in

  description     TEXT NOT NULL,
  target_hint     TEXT,           -- username, profile link, where it was seen
  reported_sha256 TEXT CHECK (reported_sha256 IS NULL OR reported_sha256 ~ '^[0-9a-f]{64}$'),

  status          TEXT NOT NULL DEFAULT 'received'
                    CHECK (status IN ('received','triaged','removed','rejected','duplicate')),
  resolved_at     TIMESTAMPTZ,
  resolved_by     TEXT,
  resolution_note TEXT,
  copies_removed  INT
);

CREATE INDEX IF NOT EXISTS idx_ncii_reports_open
  ON public.ncii_reports (deadline_at) WHERE status IN ('received','triaged');

ALTER TABLE public.ncii_reports ENABLE ROW LEVEL SECURITY;
-- No policies. Submission goes through the SECURITY DEFINER RPC; reading is
-- service-role only. A reporter must not be able to enumerate other reports,
-- and the subject of a report must never see it.
REVOKE ALL ON TABLE public.ncii_reports FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.ncii_reports TO service_role;

COMMENT ON TABLE public.ncii_reports IS
  'TAKE IT DOWN Act NCII requests. deadline_at is the 48-hour statutory clock, fixed at intake. Retained as the compliance record.';

-- ---------------------------------------------------------------------------
-- 3. Abuse limiting for the unauthenticated endpoint.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ncii_submit_rate (
  email_hash   TEXT PRIMARY KEY,   -- sha256(lower(email)); we do not key on raw email
  window_start TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  submissions  INT NOT NULL DEFAULT 0
);
ALTER TABLE public.ncii_submit_rate ENABLE ROW LEVEL SECURITY;
-- No policies: only the SECURITY DEFINER RPC touches it.

-- ---------------------------------------------------------------------------
-- 4. Intake. Callable with NO ACCOUNT — that is the statutory requirement.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.submit_ncii_report(
  p_reporter_email TEXT,
  p_description    TEXT,
  p_reporter_name  TEXT DEFAULT NULL,
  p_target_hint    TEXT DEFAULT NULL,
  p_sha256         TEXT DEFAULT NULL,
  p_is_authorized  BOOLEAN DEFAULT TRUE
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, extensions
AS $$
DECLARE
  c_per_email_hourly CONSTANT INT := 5;
  c_global_hourly    CONSTANT INT := 200;
  v_hash  TEXT;
  v_count INT;
  v_id    BIGINT;
BEGIN
  IF p_reporter_email IS NULL OR position('@' in p_reporter_email) = 0 THEN
    RAISE EXCEPTION 'A contact email is required so we can reach you about this report'
      USING ERRCODE = '22023';
  END IF;
  IF p_description IS NULL OR length(trim(p_description)) < 10 THEN
    RAISE EXCEPTION 'Please describe the content and where it appears'
      USING ERRCODE = '22023';
  END IF;

  v_hash := encode(digest(lower(trim(p_reporter_email)), 'sha256'), 'hex');

  INSERT INTO public.ncii_submit_rate (email_hash, window_start, submissions)
  VALUES (v_hash, NOW(), 0)
  ON CONFLICT (email_hash) DO NOTHING;

  UPDATE public.ncii_submit_rate
     SET window_start = CASE WHEN NOW() - window_start > INTERVAL '1 hour' THEN NOW() ELSE window_start END,
         submissions  = CASE WHEN NOW() - window_start > INTERVAL '1 hour' THEN 1 ELSE submissions + 1 END
   WHERE email_hash = v_hash
   RETURNING submissions INTO v_count;

  IF v_count > c_per_email_hourly THEN
    RAISE EXCEPTION 'Too many reports from this address in the last hour. Contact support directly.'
      USING ERRCODE = '53400';
  END IF;

  -- Global backstop so one distributed flood cannot bury genuine reports.
  SELECT count(*) INTO v_count FROM public.ncii_reports
   WHERE received_at > NOW() - INTERVAL '1 hour';
  IF v_count >= c_global_hourly THEN
    RAISE EXCEPTION 'Report intake is temporarily saturated. Contact support directly.'
      USING ERRCODE = '53400';
  END IF;

  INSERT INTO public.ncii_reports (
    reporter_email, reporter_name, is_authorized, reporter_user_id,
    description, target_hint, reported_sha256
  ) VALUES (
    lower(trim(p_reporter_email)), p_reporter_name, COALESCE(p_is_authorized, TRUE),
    auth.uid(),   -- NULL when submitted without an account, which is expected
    p_description, p_target_hint, lower(p_sha256)
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

COMMENT ON FUNCTION public.submit_ncii_report IS
  'TAKE IT DOWN Act intake. Deliberately callable by anon: the statute requires a path usable without an account. Creates a claim for human review; never removes content directly.';

REVOKE ALL ON FUNCTION public.submit_ncii_report(TEXT,TEXT,TEXT,TEXT,TEXT,BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_ncii_report(TEXT,TEXT,TEXT,TEXT,TEXT,BOOLEAN)
  TO anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. Resolution — human-reviewed, and fans out to identical copies.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ncii_resolve(
  p_id     BIGINT,
  p_status TEXT,
  p_by     TEXT,
  p_note   TEXT DEFAULT NULL
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_sha    TEXT;
  v_copies INT := 0;
BEGIN
  IF p_status NOT IN ('triaged','removed','rejected','duplicate') THEN
    RAISE EXCEPTION 'Invalid resolution status: %', p_status USING ERRCODE = '22023';
  END IF;

  SELECT reported_sha256 INTO v_sha FROM public.ncii_reports WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No such NCII report: %', p_id USING ERRCODE = '22023';
  END IF;

  IF p_status = 'removed' AND v_sha IS NOT NULL THEN
    -- Statutory duty 3: every identical copy, wherever it lives, not just the
    -- object the reporter happened to find.
    INSERT INTO public.storage_deletion_queue (user_id, bucket_id, object_name)
    SELECT mh.user_id, mh.bucket_id, mh.object_name
      FROM public.media_hashes mh
     WHERE mh.sha256 = v_sha
    ON CONFLICT (bucket_id, object_name) DO NOTHING;
    GET DIAGNOSTICS v_copies = ROW_COUNT;

    -- Drop the hash rows too, so a re-upload of the same bytes is a NEW object
    -- rather than silently matching a row for a file that no longer exists.
    DELETE FROM public.media_hashes WHERE sha256 = v_sha;
  END IF;

  UPDATE public.ncii_reports
     SET status          = p_status,
         resolved_at     = CASE WHEN p_status = 'triaged' THEN NULL ELSE NOW() END,
         resolved_by     = p_by,
         resolution_note = COALESCE(p_note, resolution_note),
         copies_removed  = CASE WHEN p_status = 'removed' THEN v_copies ELSE copies_removed END
   WHERE id = p_id;

  RETURN v_copies;
END;
$$;

REVOKE ALL ON FUNCTION public.ncii_resolve(BIGINT,TEXT,TEXT,TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ncii_resolve(BIGINT,TEXT,TEXT,TEXT) TO service_role;

-- ---------------------------------------------------------------------------
-- 6. The SLA board. This is what someone actually looks at.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_ncii_sla
WITH (security_invoker = true, security_barrier = true) AS
SELECT
  id,
  received_at,
  deadline_at,
  status,
  reporter_email,
  target_hint,
  reported_sha256 IS NOT NULL AS has_hash,
  EXTRACT(EPOCH FROM (deadline_at - NOW())) / 3600.0 AS hours_remaining,
  NOW() > deadline_at AS breached
FROM public.ncii_reports
WHERE status IN ('received', 'triaged')
ORDER BY deadline_at;

REVOKE ALL ON public.v_ncii_sla FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.v_ncii_sla TO service_role;

COMMENT ON VIEW public.v_ncii_sla IS
  'Open NCII requests against the 48-hour statutory clock. breached=true is an FTC exposure event at $53,088 per violation.';

-- OPEN ITEM: per-IP rate limiting. An RPC cannot see the client IP, so the
-- limits above are per-email and global only. Before public launch, front this
-- with an Edge Function (or the API gateway) that applies a per-IP limit --
-- otherwise a single actor can rotate email addresses to reach the global cap
-- and deny service to genuine reporters.

COMMIT;
