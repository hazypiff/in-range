-- 0052_photo_review_queue.sql
--
-- Makes the human photo-moderation queue operable. Audit finding: photo-review
-- is a stub (no automated AI), so passing photos land in 'manual_review' and a
-- human must approve them via decide_photo_verification() before the user gets
-- an approved photo_verifications row (which is_discoverable_user requires).
-- The DECISION function already exists and is service-role only; what was
-- missing is a way to SEE the queue. This adds that board — nothing else was
-- needed to work the queue, mirroring v_ncii_sla / v_report_triage.
--
-- Service-role only. security_invoker so it reads photo_verifications with the
-- caller's privileges (service_role bypasses RLS; app roles are also explicitly
-- revoked below), never leaking pending photos/display names to app users.

BEGIN;

CREATE OR REPLACE VIEW public.v_photo_review_queue
WITH (security_invoker = true) AS
SELECT
  pv.id                       AS verification_id,
  pv.user_id,
  p.display_name,
  pv.state,
  'profile_photos'::text      AS bucket_id,
  pv.photo_path,
  pv.slot_index,
  pv.ai_score,
  pv.ai_notes,
  pv.submitted_at,
  (NOW() - pv.submitted_at)   AS waiting
FROM public.photo_verifications pv
LEFT JOIN public.profiles p ON p.id = pv.user_id
-- Everything a human still has to look at. 'ai_failed'/'rejected'/'approved'
-- are terminal and stay off the board; 'ai_review' appears because the AI is a
-- stub, so those never auto-advance and must be reviewed by hand too.
WHERE pv.state IN ('manual_review', 'ai_review', 'ai_passed')
ORDER BY pv.submitted_at ASC;

REVOKE ALL ON public.v_photo_review_queue FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.v_photo_review_queue TO service_role;

COMMENT ON VIEW public.v_photo_review_queue IS
  'Service-role moderation board: photo_verifications awaiting a human decision, oldest first. Approve/reject with review_photo(verification_id, approve, notes).';

-- One-call moderator action. Photos enter at 'ai_review' and nothing advances
-- them (photo-review is a stub with no trigger/cron), so decide_photo_verification
-- — which only acts on 'manual_review'/'ai_passed' — cannot reach them. With no
-- automated AI a human IS the reviewer, so this advances a fresh submission out
-- of 'ai_review' (via complete_ai_photo_review, which keeps the storage
-- anti-tamper check) and then records the human decision. Both underlying
-- security-reviewed functions are unchanged. Forward-compatible: once a real AI
-- + scheduled photo-review land, photos arrive already in 'manual_review' and
-- this simply skips the advance step.
CREATE OR REPLACE FUNCTION public.review_photo(
  p_verification_id UUID,
  p_approve BOOLEAN,
  p_notes TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_state public.photo_verification_state;
BEGIN
  SELECT state INTO v_state FROM public.photo_verifications WHERE id = p_verification_id;
  IF v_state IS NULL THEN
    RAISE EXCEPTION 'Verification not found' USING ERRCODE = '55000';
  END IF;

  IF v_state = 'ai_review' THEN
    PERFORM public.complete_ai_photo_review(p_verification_id, 1.0, TRUE, 'manual review');
  END IF;

  PERFORM public.decide_photo_verification(p_verification_id, p_approve, p_notes);
END;
$$;

REVOKE ALL ON FUNCTION public.review_photo(UUID, BOOLEAN, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.review_photo(UUID, BOOLEAN, TEXT) TO service_role;

COMMENT ON FUNCTION public.review_photo IS
  'Service-role moderator action: approve/reject a photo_verifications row from the v_photo_review_queue board, advancing it out of ai_review first if needed.';

COMMIT;
