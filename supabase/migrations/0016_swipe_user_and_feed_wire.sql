-- =============================================================================
-- Migration 0016: swipe_user — like/pass a peer by user id (Locals + hybrid feed)
-- =============================================================================
-- Creates (or reuses) an active encounter between auth.uid() and p_other_user_id,
-- then applies swipe_encounter. Used when the UI has a user_id but not encounter_id.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.swipe_user(
  p_other_user_id UUID,
  p_action public.action_type,
  p_range public.range_type DEFAULT 'miles_10',
  p_neighborhood TEXT DEFAULT 'Nearby'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_user_a UUID;
  v_user_b UUID;
  v_enc_id BIGINT;
  v_result JSONB;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_other_user_id IS NULL OR p_other_user_id = v_uid THEN
    RAISE EXCEPTION 'Invalid other user';
  END IF;
  IF public.is_blocked_pair(v_uid, p_other_user_id) THEN
    RAISE EXCEPTION 'Blocked';
  END IF;

  IF v_uid < p_other_user_id THEN
    v_user_a := v_uid;
    v_user_b := p_other_user_id;
  ELSE
    v_user_a := p_other_user_id;
    v_user_b := v_uid;
  END IF;

  SELECT id INTO v_enc_id
  FROM public.encounters
  WHERE user_a = v_user_a AND user_b = v_user_b
    AND status IN ('active', 'matched')
  ORDER BY
    CASE WHEN status = 'active' THEN 0 ELSE 1 END,
    encounter_time DESC
  LIMIT 1;

  IF v_enc_id IS NULL THEN
    INSERT INTO public.encounters (
      user_a, user_b, neighborhood, encounter_time, range_type, confidence, status
    ) VALUES (
      v_user_a, v_user_b,
      COALESCE(NULLIF(trim(p_neighborhood), ''), 'Nearby'),
      NOW(), p_range, 0.75, 'active'
    )
    RETURNING id INTO v_enc_id;
  END IF;

  -- Delegate to swipe_encounter (same auth.uid())
  SELECT public.swipe_encounter(v_enc_id, p_action) INTO v_result;
  RETURN v_result || jsonb_build_object('encounter_id', v_enc_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.swipe_user TO authenticated;

COMMENT ON FUNCTION public.swipe_user IS
  'Like/pass by other user id: ensures an active encounter exists then swipes. For Locals UI.';
