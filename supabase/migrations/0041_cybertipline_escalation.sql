-- 0041_cybertipline_escalation.sql
--
-- Connects the report queue to §2258A: preservation + filing obligation.
--
-- The pieces already existed in isolation:
--   * report_user() writes reports, and the reason enum already includes
--     'underage' -- the §2258A trigger signal.
--   * 0037 place_legal_hold() can preserve evidence against the retention purge.
-- Nothing joined them. A reviewer confirming an underage / enticement report
-- had no path that (a) preserved the evidence before the subject could delete
-- it away, and (b) recorded the federal filing obligation. This adds that path.
--
-- WHAT §2258A ACTUALLY REQUIRES, and what is / isn't automatable here:
--   * Report to NCMEC's CyberTipline "as soon as reasonably possible" once we
--     have actual knowledge. The SUBMISSION is a human act against NCMEC's
--     system -- it cannot and must not be automated from SQL. What we automate
--     is the OBLIGATION TRACKING: a queue row the moment a reviewer confirms,
--     so the duty cannot be silently dropped.
--   * §2258A(h)(1): 1-year preservation from filing. escalate_report() places
--     the legal hold immediately on confirmation, which is stricter (preserve
--     from knowledge, not from filing) and safe.
--   * §2258A(f): NO duty to affirmatively search. This is reviewer-triggered
--     from user reports only; nothing here scans or monitors.
--
-- The realistic trigger for a proximity dating app is §2422(b) enticement -- an
-- adult soliciting a minor in chat -- which is why 'harassment' and 'other'
-- reports can also be escalated, not just 'underage'. The reviewer decides;
-- the reason enum is a hint, not the gate.
--
-- Everything here is service-role only. Reported users must never see triage
-- state, an escalation, or a hold placed on them.

BEGIN;

-- ---------------------------------------------------------------------------
-- The filing obligation. One row per confirmed incident that must reach NCMEC.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.cybertipline_queue (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  report_id     BIGINT REFERENCES public.reports(id) ON DELETE SET NULL,
  subject_id    UUID,          -- the reported user; kept even if the account is later purged
  legal_hold_id BIGINT REFERENCES public.legal_holds(id) ON DELETE SET NULL,

  -- Which statute the reviewer believes is implicated. Drives nothing
  -- automatically -- it is the reviewer's classification, for the filing.
  category      TEXT NOT NULL CHECK (category IN (
                  'csam',              -- §2258A / §2252
                  'enticement_2422b',  -- adult soliciting a minor (the common one)
                  'trafficking_1591',
                  'other_minor_harm'
                )),
  detail        TEXT,

  opened_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  opened_by     TEXT NOT NULL,

  -- The actual NCMEC submission, recorded by the human who files it.
  filed_at      TIMESTAMPTZ,
  ncmec_report_number TEXT,
  filed_by      TEXT,

  -- §2258A(h)(1): one year of preservation from filing. Set when filed.
  preserve_until TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_cybertipline_unfiled
  ON public.cybertipline_queue (opened_at) WHERE filed_at IS NULL;

ALTER TABLE public.cybertipline_queue ENABLE ROW LEVEL SECURITY;
-- No policies. Service-role only: this is the most sensitive queue in the
-- system, and the subject learning of it risks obstruction.
REVOKE ALL ON TABLE public.cybertipline_queue FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.cybertipline_queue TO service_role;

COMMENT ON TABLE public.cybertipline_queue IS
  '§2258A filing obligations. Opened automatically on reviewer confirmation; the NCMEC submission is a human act recorded here. Service-role only.';

-- ---------------------------------------------------------------------------
-- Escalation: one reviewer action that preserves AND records the obligation.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.escalate_report(
  p_report_id BIGINT,
  p_category  TEXT,
  p_by        TEXT,
  p_detail    TEXT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_subject UUID;
  v_hold    BIGINT;
  v_queue   BIGINT;
BEGIN
  SELECT reported_id INTO v_subject FROM public.reports WHERE id = p_report_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No such report: %', p_report_id USING ERRCODE = '22023';
  END IF;

  -- 1. Preserve FIRST, before anything else can race a deletion. §2258A(h)(1)
  --    is 1 year from filing; we hold from confirmation, which is stricter.
  --    place_legal_hold defaults a cybertipline_2258a hold to 1 year.
  v_hold := public.place_legal_hold(
    v_subject, 'cybertipline_2258a', p_by,
    format('report #%s (%s)', p_report_id, p_category));

  -- 2. Record the filing obligation so it cannot be silently dropped.
  INSERT INTO public.cybertipline_queue
    (report_id, subject_id, legal_hold_id, category, detail, opened_by)
  VALUES (p_report_id, v_subject, v_hold, p_category, p_detail, p_by)
  RETURNING id INTO v_queue;

  -- 3. Move the report out of the open queue.
  UPDATE public.reports
     SET status = 'actioned', resolved_at = NOW()
   WHERE id = p_report_id;

  RETURN v_queue;
END;
$$;

REVOKE ALL ON FUNCTION public.escalate_report(BIGINT,TEXT,TEXT,TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.escalate_report(BIGINT,TEXT,TEXT,TEXT) TO service_role;

-- ---------------------------------------------------------------------------
-- Record the NCMEC submission after the human files it. Starts the statutory
-- 1-year preservation clock and extends the hold to match.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_cybertipline_filing(
  p_queue_id BIGINT,
  p_ncmec_number TEXT,
  p_by TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_hold BIGINT;
  v_until TIMESTAMPTZ := NOW() + INTERVAL '1 year';
BEGIN
  UPDATE public.cybertipline_queue
     SET filed_at = NOW(),
         ncmec_report_number = p_ncmec_number,
         filed_by = p_by,
         preserve_until = v_until
   WHERE id = p_queue_id
   RETURNING legal_hold_id INTO v_hold;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No such cybertipline queue row: %', p_queue_id USING ERRCODE = '22023';
  END IF;

  -- Re-anchor the preservation window to the filing date (§2258A(h)(1) runs
  -- from the report), extending but never shortening the hold.
  IF v_hold IS NOT NULL THEN
    UPDATE public.legal_holds
       SET expires_at = GREATEST(COALESCE(expires_at, v_until), v_until)
     WHERE id = v_hold AND released_at IS NULL;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.record_cybertipline_filing(BIGINT,TEXT,TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_cybertipline_filing(BIGINT,TEXT,TEXT) TO service_role;

-- ---------------------------------------------------------------------------
-- What the on-call reviewer looks at: open reports, worst first, with the
-- §2258A-relevant reasons surfaced.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_report_triage
WITH (security_invoker = true, security_barrier = true) AS
SELECT
  r.id,
  r.created_at,
  r.reason,
  r.reported_id,
  r.match_id,
  r.details,
  -- A prompt, not a gate: these reasons MAY implicate §2258A and should be
  -- read first. The reviewer still classifies.
  (r.reason IN ('underage', 'harassment', 'inappropriate_photos')) AS review_for_2258a,
  EXISTS (SELECT 1 FROM public.cybertipline_queue q WHERE q.report_id = r.id) AS already_escalated
FROM public.reports r
WHERE r.status IN ('open', 'reviewing')
ORDER BY
  (r.reason = 'underage') DESC,   -- the explicit minor-safety signal first
  r.created_at ASC;

REVOKE ALL ON public.v_report_triage FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.v_report_triage TO service_role;

COMMENT ON VIEW public.v_report_triage IS
  'Open user reports for review, minor-safety signals first. review_for_2258a is a prompt, not a classification.';

-- Unfiled §2258A obligations -- the queue nobody is allowed to forget.
CREATE OR REPLACE VIEW public.v_cybertipline_pending
WITH (security_invoker = true, security_barrier = true) AS
SELECT id, report_id, subject_id, category, detail, opened_at, opened_by,
       EXTRACT(EPOCH FROM (NOW() - opened_at)) / 3600.0 AS hours_open
FROM public.cybertipline_queue
WHERE filed_at IS NULL
ORDER BY opened_at ASC;

REVOKE ALL ON public.v_cybertipline_pending FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.v_cybertipline_pending TO service_role;

COMMIT;
