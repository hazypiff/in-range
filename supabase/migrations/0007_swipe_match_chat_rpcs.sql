-- =============================================================================
-- Migration 0007: Swipe, match, chat, block/report RPCs + feet expiry
-- =============================================================================

-- ----------------------------------------------------------------------------
-- 1. swipe_encounter — like/pass; create match on mutual like
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.swipe_encounter(
  p_encounter_id BIGINT,
  p_action public.action_type
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_enc public.encounters%ROWTYPE;
  v_other UUID;
  v_other_action public.action_type;
  v_match_id BIGINT;
  v_user_a UUID;
  v_user_b UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_enc FROM public.encounters WHERE id = p_encounter_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Encounter not found';
  END IF;
  IF v_enc.user_a <> v_uid AND v_enc.user_b <> v_uid THEN
    RAISE EXCEPTION 'Not a participant';
  END IF;
  IF v_enc.status NOT IN ('active', 'matched') THEN
    RAISE EXCEPTION 'Encounter not swipeable (status=%)', v_enc.status;
  END IF;

  v_other := CASE WHEN v_enc.user_a = v_uid THEN v_enc.user_b ELSE v_enc.user_a END;

  IF public.is_blocked_pair(v_uid, v_other) THEN
    RAISE EXCEPTION 'Blocked';
  END IF;

  INSERT INTO public.encounter_actions (user_id, encounter_id, action)
  VALUES (v_uid, p_encounter_id, p_action)
  ON CONFLICT (user_id, encounter_id) DO UPDATE
    SET action = EXCLUDED.action, acted_at = NOW();

  IF p_action = 'pass' THEN
    RETURN jsonb_build_object(
      'matched', false,
      'match_id', null,
      'action', 'pass'
    );
  END IF;

  -- Mutual like?
  SELECT action INTO v_other_action
  FROM public.encounter_actions
  WHERE encounter_id = p_encounter_id AND user_id = v_other;

  IF v_other_action = 'like' THEN
    IF v_enc.user_a < v_enc.user_b THEN
      v_user_a := v_enc.user_a;
      v_user_b := v_enc.user_b;
    ELSE
      v_user_a := v_enc.user_b;
      v_user_b := v_enc.user_a;
    END IF;

    INSERT INTO public.matches (encounter_id, user_a, user_b)
    VALUES (p_encounter_id, v_user_a, v_user_b)
    ON CONFLICT (encounter_id) DO UPDATE SET matched_at = public.matches.matched_at
    RETURNING id INTO v_match_id;

    IF v_match_id IS NULL THEN
      SELECT id INTO v_match_id FROM public.matches WHERE encounter_id = p_encounter_id;
    END IF;

    UPDATE public.encounters SET status = 'matched' WHERE id = p_encounter_id;

    -- Notify both users
    INSERT INTO public.notification_outbox (user_id, kind, title, body, payload)
    VALUES
      (
        v_uid,
        'new_match',
        'It''s a match 🔥',
        'You both liked each other. Say hi!',
        jsonb_build_object('match_id', v_match_id, 'other_user_id', v_other)
      ),
      (
        v_other,
        'new_match',
        'It''s a match 🔥',
        'You both liked each other. Say hi!',
        jsonb_build_object('match_id', v_match_id, 'other_user_id', v_uid)
      );

    RETURN jsonb_build_object(
      'matched', true,
      'match_id', v_match_id,
      'action', 'like',
      'other_user_id', v_other
    );
  END IF;

  RETURN jsonb_build_object(
    'matched', false,
    'match_id', null,
    'action', 'like'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.swipe_encounter TO authenticated;

-- ----------------------------------------------------------------------------
-- 2. get_my_matches
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_my_matches(
  p_limit INT DEFAULT 50,
  p_offset INT DEFAULT 0
)
RETURNS TABLE (
  match_id BIGINT,
  other_user_id UUID,
  display_name TEXT,
  photo_urls TEXT[],
  bio TEXT,
  age INT,
  gender TEXT,
  interests TEXT[],
  neighborhood TEXT,
  matched_at TIMESTAMPTZ,
  last_message TEXT,
  last_message_at TIMESTAMPTZ,
  unread_count BIGINT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    m.id AS match_id,
    CASE WHEN m.user_a = auth.uid() THEN m.user_b ELSE m.user_a END AS other_user_id,
    COALESCE(p.display_name, 'Match') AS display_name,
    p.photo_urls,
    p.bio,
    CASE WHEN p.dob IS NOT NULL
      THEN EXTRACT(YEAR FROM age(p.dob))::INT
      ELSE NULL
    END AS age,
    p.gender,
    p.interests,
    p.neighborhood,
    m.matched_at,
    (
      SELECT msg.content FROM public.messages msg
      WHERE msg.match_id = m.id
      ORDER BY msg.created_at DESC LIMIT 1
    ) AS last_message,
    (
      SELECT msg.created_at FROM public.messages msg
      WHERE msg.match_id = m.id
      ORDER BY msg.created_at DESC LIMIT 1
    ) AS last_message_at,
    (
      SELECT COUNT(*) FROM public.messages msg
      WHERE msg.match_id = m.id
        AND msg.sender_id <> auth.uid()
        AND msg.read_at IS NULL
    ) AS unread_count
  FROM public.matches m
  JOIN public.profiles p
    ON p.id = CASE WHEN m.user_a = auth.uid() THEN m.user_b ELSE m.user_a END
  WHERE (m.user_a = auth.uid() OR m.user_b = auth.uid())
    AND NOT public.is_blocked_pair(
      auth.uid(),
      CASE WHEN m.user_a = auth.uid() THEN m.user_b ELSE m.user_a END
    )
    AND COALESCE(p.is_paused, FALSE) = FALSE
    AND p.deleted_at IS NULL
  ORDER BY COALESCE(
    (SELECT msg.created_at FROM public.messages msg
     WHERE msg.match_id = m.id ORDER BY msg.created_at DESC LIMIT 1),
    m.matched_at
  ) DESC
  LIMIT p_limit OFFSET p_offset;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_matches TO authenticated;

-- ----------------------------------------------------------------------------
-- 3. get_who_liked_you (subscriber feature)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_who_liked_you(
  p_limit INT DEFAULT 50
)
RETURNS TABLE (
  encounter_id BIGINT,
  other_user_id UUID,
  neighborhood TEXT,
  encounter_time TIMESTAMPTZ,
  range_type public.range_type
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_subscriber(auth.uid()) THEN
    RAISE EXCEPTION 'Subscription required for See Who Liked You'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    e.id,
    CASE WHEN e.user_a = auth.uid() THEN e.user_b ELSE e.user_a END,
    e.neighborhood,
    e.encounter_time,
    e.range_type
  FROM public.encounters e
  JOIN public.encounter_actions ea
    ON ea.encounter_id = e.id
   AND ea.action = 'like'
   AND ea.user_id <> auth.uid()
  LEFT JOIN public.encounter_actions my
    ON my.encounter_id = e.id AND my.user_id = auth.uid()
  WHERE (e.user_a = auth.uid() OR e.user_b = auth.uid())
    AND e.status = 'active'
    AND my.id IS NULL
  ORDER BY ea.acted_at DESC
  LIMIT p_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_who_liked_you TO authenticated;

-- ----------------------------------------------------------------------------
-- 4. send_message
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.send_message(
  p_match_id BIGINT,
  p_content TEXT,
  p_message_type public.message_type DEFAULT 'text',
  p_metadata JSONB DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_match public.matches%ROWTYPE;
  v_other UUID;
  v_msg_id BIGINT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_match FROM public.matches WHERE id = p_match_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Match not found';
  END IF;
  IF v_match.user_a <> v_uid AND v_match.user_b <> v_uid THEN
    RAISE EXCEPTION 'Not a participant';
  END IF;

  v_other := CASE WHEN v_match.user_a = v_uid THEN v_match.user_b ELSE v_match.user_a END;
  IF public.is_blocked_pair(v_uid, v_other) THEN
    RAISE EXCEPTION 'Blocked';
  END IF;

  IF p_message_type = 'text' AND (p_content IS NULL OR length(trim(p_content)) = 0) THEN
    RAISE EXCEPTION 'Message content required';
  END IF;

  INSERT INTO public.messages (match_id, sender_id, content, message_type, metadata)
  VALUES (p_match_id, v_uid, p_content, p_message_type, p_metadata)
  RETURNING id INTO v_msg_id;

  INSERT INTO public.notification_outbox (user_id, kind, title, body, payload)
  VALUES (
    v_other,
    'new_message',
    'New message',
    CASE
      WHEN p_message_type = 'text' THEN left(COALESCE(p_content, ''), 120)
      WHEN p_message_type = 'photo' THEN 'Sent a photo'
      WHEN p_message_type = 'voice' THEN 'Sent a voice note'
      ELSE 'Sent a message'
    END,
    jsonb_build_object(
      'match_id', p_match_id,
      'message_id', v_msg_id,
      'sender_id', v_uid
    )
  );

  RETURN v_msg_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.send_message TO authenticated;

-- ----------------------------------------------------------------------------
-- 5. mark_messages_read
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.mark_messages_read(p_match_id BIGINT)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_count INT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  UPDATE public.messages
  SET read_at = NOW()
  WHERE match_id = p_match_id
    AND sender_id <> v_uid
    AND read_at IS NULL
    AND EXISTS (
      SELECT 1 FROM public.matches m
      WHERE m.id = p_match_id
        AND (m.user_a = v_uid OR m.user_b = v_uid)
    );

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.mark_messages_read TO authenticated;

-- ----------------------------------------------------------------------------
-- 6. block_user / unblock_user / report_user
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.block_user(p_blocked_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_blocked_id = auth.uid() THEN
    RAISE EXCEPTION 'Cannot block yourself';
  END IF;
  INSERT INTO public.blocks (blocker_id, blocked_id)
  VALUES (auth.uid(), p_blocked_id)
  ON CONFLICT DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION public.unblock_user(p_blocked_id UUID)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  DELETE FROM public.blocks
  WHERE blocker_id = auth.uid() AND blocked_id = p_blocked_id;
$$;

CREATE OR REPLACE FUNCTION public.report_user(
  p_reported_id UUID,
  p_reason public.report_reason,
  p_details TEXT DEFAULT NULL,
  p_match_id BIGINT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id BIGINT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  INSERT INTO public.reports (reporter_id, reported_id, reason, details, match_id)
  VALUES (auth.uid(), p_reported_id, p_reason, p_details, p_match_id)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.block_user TO authenticated;
GRANT EXECUTE ON FUNCTION public.unblock_user TO authenticated;
GRANT EXECUTE ON FUNCTION public.report_user TO authenticated;

-- ----------------------------------------------------------------------------
-- 7. expire_feet_encounters — 24h rule for feet-based
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.expire_feet_encounters()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INT;
BEGIN
  UPDATE public.encounters
  SET status = 'expired'
  WHERE status = 'active'
    AND range_type::text LIKE 'feet_%'
    AND encounter_time < NOW() - INTERVAL '24 hours';

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.expire_feet_encounters TO service_role;

-- Notify users of encounters expiring soon (within 2h)
CREATE OR REPLACE FUNCTION public.queue_expiring_encounter_alerts()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INT := 0;
  r RECORD;
BEGIN
  FOR r IN
    SELECT e.id, e.user_a, e.user_b, e.encounter_time
    FROM public.encounters e
    WHERE e.status = 'active'
      AND e.range_type::text LIKE 'feet_%'
      AND e.encounter_time < NOW() - INTERVAL '22 hours'
      AND e.encounter_time >= NOW() - INTERVAL '24 hours'
  LOOP
    INSERT INTO public.notification_outbox (user_id, kind, title, body, payload)
    SELECT u, 'expiring_encounter', 'Encounter expiring soon',
           'A nearby run-in expires in under 2 hours. Swipe before it disappears.',
           jsonb_build_object('encounter_id', r.id)
    FROM unnest(ARRAY[r.user_a, r.user_b]) AS u
    WHERE NOT EXISTS (
      SELECT 1 FROM public.notification_outbox o
      WHERE o.user_id = u
        AND o.kind = 'expiring_encounter'
        AND o.payload->>'encounter_id' = r.id::text
        AND o.created_at > NOW() - INTERVAL '6 hours'
    );
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.queue_expiring_encounter_alerts TO service_role;

-- ----------------------------------------------------------------------------
-- 8. Filter get_my_encounters for blocks + paused + photo pre-match shape
-- ----------------------------------------------------------------------------
-- Drop prior signatures (return type changed across migrations).
DROP FUNCTION IF EXISTS public.get_my_encounters(INT, INT);
DROP FUNCTION IF EXISTS public.get_my_encounters(INT, INT, NUMERIC);

CREATE OR REPLACE FUNCTION public.get_my_encounters(
  p_limit INT DEFAULT 50,
  p_offset INT DEFAULT 0,
  p_min_age_hours NUMERIC DEFAULT 4
)
RETURNS TABLE (
  encounter_id BIGINT,
  other_user_id UUID,
  display_name TEXT,
  photo_urls TEXT[],
  neighborhood TEXT,
  encounter_time TIMESTAMPTZ,
  range_type public.range_type,
  my_action public.action_type,
  other_action public.action_type,
  status public.encounter_status,
  is_photo_verified BOOLEAN
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    e.id AS encounter_id,
    CASE WHEN e.user_a = auth.uid() THEN e.user_b ELSE e.user_a END AS other_user_id,
    -- Pre-match: name hidden in product; still return opaque label for client
    'Someone nearby'::TEXT AS display_name,
    -- Photos only (product rule)
    CASE
      WHEN p.is_photo_verified THEN p.photo_urls
      ELSE p.photo_urls  -- still show; verification gates discoverability separately
    END AS photo_urls,
    e.neighborhood,
    e.encounter_time,
    e.range_type,
    (SELECT action FROM public.encounter_actions WHERE user_id = auth.uid() AND encounter_id = e.id),
    (SELECT action FROM public.encounter_actions
     WHERE user_id <> auth.uid() AND encounter_id = e.id LIMIT 1),
    e.status,
    COALESCE(p.is_photo_verified, FALSE)
  FROM public.encounters e
  LEFT JOIN public.profiles p
    ON p.id = CASE WHEN e.user_a = auth.uid() THEN e.user_b ELSE e.user_a END
  WHERE (e.user_a = auth.uid() OR e.user_b = auth.uid())
    AND e.status = 'active'
    AND e.encounter_time <= NOW() - make_interval(secs => (p_min_age_hours * 3600)::double precision)
    AND NOT public.is_blocked_pair(
      auth.uid(),
      CASE WHEN e.user_a = auth.uid() THEN e.user_b ELSE e.user_a END
    )
    AND COALESCE(p.is_paused, FALSE) = FALSE
    AND p.deleted_at IS NULL
    AND COALESCE(p.is_active, TRUE) = TRUE
    -- Only show users who have at least submitted photos
    AND COALESCE(array_length(p.photo_urls, 1), 0) > 0
    -- Hide if I already acted
    AND NOT EXISTS (
      SELECT 1 FROM public.encounter_actions ea
      WHERE ea.encounter_id = e.id AND ea.user_id = auth.uid()
    )
  ORDER BY e.encounter_time DESC
  LIMIT p_limit
  OFFSET p_offset;
$$;

COMMENT ON FUNCTION public.swipe_encounter IS
  'Like/pass on encounter; mutual like creates match + push outbox rows.';
COMMENT ON FUNCTION public.get_my_matches IS
  'Post-match list with unlocked profile fields + last message preview.';
COMMENT ON FUNCTION public.expire_feet_encounters IS
  'Marks feet-based encounters older than 24h as expired. Schedule via cron/edge.';
