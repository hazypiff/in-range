-- =============================================================================
-- Migration 0006: Storage buckets + photo verification RPCs + chat media
-- =============================================================================
-- Profile photos: max 6 per user under profile_photos/{uid}/{slot}.ext
-- Chat media: chat_media/{match_id}/{message_id}/...
-- Verification state machine advances via RPCs (AI stub ready for Edge Function).
-- =============================================================================

-- ----------------------------------------------------------------------------
-- 1. Buckets
-- ----------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  (
    'profile_photos',
    'profile_photos',
    true,
    5242880,  -- 5 MB
    ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/heic']
  ),
  (
    'chat_media',
    'chat_media',
    false,
    20971520, -- 20 MB
    ARRAY[
      'image/jpeg', 'image/png', 'image/webp', 'image/heic',
      'audio/mp4', 'audio/mpeg', 'audio/m4a', 'audio/aac',
      'video/mp4', 'video/quicktime'
    ]
  ),
  (
    'verified_photos',
    'verified_photos',
    true,
    5242880,
    ARRAY['image/jpeg', 'image/png', 'image/webp']
  )
ON CONFLICT (id) DO UPDATE SET
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Drop policies that may already exist from 0002 so we can re-create cleanly
DO $$
BEGIN
  DROP POLICY IF EXISTS "Users upload own profile photos" ON storage.objects;
  DROP POLICY IF EXISTS "Users update own profile photos" ON storage.objects;
  DROP POLICY IF EXISTS "Users delete own profile photos" ON storage.objects;
  DROP POLICY IF EXISTS "Public read profile photos" ON storage.objects;
  DROP POLICY IF EXISTS "Public read verified photos" ON storage.objects;
  DROP POLICY IF EXISTS "Service role uploads verified photos" ON storage.objects;
  DROP POLICY IF EXISTS "Service role updates verified photos" ON storage.objects;
  DROP POLICY IF EXISTS "Service role deletes verified photos" ON storage.objects;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- Profile photos: path must be {auth.uid()}/{slot}-{filename}
CREATE POLICY "Users upload own profile photos"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'profile_photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Users update own profile photos"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'profile_photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Users delete own profile photos"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'profile_photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Public read profile photos"
  ON storage.objects FOR SELECT
  TO public
  USING (bucket_id = 'profile_photos');

CREATE POLICY "Public read verified photos"
  ON storage.objects FOR SELECT
  TO public
  USING (bucket_id = 'verified_photos');

CREATE POLICY "Service role manages verified photos"
  ON storage.objects FOR ALL
  TO service_role
  USING (bucket_id = 'verified_photos')
  WITH CHECK (bucket_id = 'verified_photos');

-- Chat media: only match participants (folder = match_id as text)
CREATE POLICY "Match participants upload chat media"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'chat_media'
    AND EXISTS (
      SELECT 1 FROM public.matches m
      WHERE m.id::text = (storage.foldername(name))[1]
        AND (m.user_a = auth.uid() OR m.user_b = auth.uid())
    )
  );

CREATE POLICY "Match participants read chat media"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'chat_media'
    AND EXISTS (
      SELECT 1 FROM public.matches m
      WHERE m.id::text = (storage.foldername(name))[1]
        AND (m.user_a = auth.uid() OR m.user_b = auth.uid())
    )
  );

CREATE POLICY "Match participants delete own chat media"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'chat_media'
    AND (storage.foldername(name))[2] = auth.uid()::text
  );

-- ----------------------------------------------------------------------------
-- 2. Submit photo for verification
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.submit_photo_for_verification(
  p_photo_path TEXT,
  p_slot_index SMALLINT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_id UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_slot_index < 0 OR p_slot_index > 5 THEN
    RAISE EXCEPTION 'slot_index must be 0..5';
  END IF;
  IF p_photo_path IS NULL OR length(trim(p_photo_path)) = 0 THEN
    RAISE EXCEPTION 'photo_path required';
  END IF;
  -- Path must start with own uid
  IF split_part(p_photo_path, '/', 1) <> v_uid::text THEN
    RAISE EXCEPTION 'photo_path must be under your user folder';
  END IF;

  INSERT INTO public.photo_verifications (user_id, photo_path, slot_index, state)
  VALUES (v_uid, p_photo_path, p_slot_index, 'ai_review')
  RETURNING id INTO v_id;

  -- Keep profile photo_urls in sync (upsert slot)
  UPDATE public.profiles
  SET
    photo_urls = (
      SELECT array_agg(u ORDER BY ord)
      FROM (
        SELECT
          CASE WHEN ord - 1 = p_slot_index THEN p_photo_path ELSE COALESCE(photo_urls[ord], '') END AS u,
          ord
        FROM generate_series(1, GREATEST(COALESCE(array_length(photo_urls, 1), 0), p_slot_index + 1)) ord
      ) s
      WHERE u <> ''
    ),
    photo_verification_status = 'pending',
    is_photo_verified = FALSE,
    updated_at = NOW()
  WHERE id = v_uid;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.submit_photo_for_verification TO authenticated;

-- ----------------------------------------------------------------------------
-- 3. AI review stub (callable by Edge Function with service_role)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.complete_ai_photo_review(
  p_verification_id UUID,
  p_score NUMERIC,
  p_passed BOOLEAN,
  p_notes TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.photo_verifications
  SET
    ai_score = p_score,
    ai_notes = p_notes,
    state = CASE
      WHEN p_passed THEN 'manual_review'::public.photo_verification_state
      ELSE 'ai_failed'::public.photo_verification_state
    END,
    updated_at = NOW()
  WHERE id = p_verification_id
    AND state = 'ai_review';

  -- Auto-queue notification if AI failed hard
  IF NOT p_passed THEN
    INSERT INTO public.notification_outbox (user_id, kind, title, body, payload)
    SELECT
      pv.user_id,
      'photo_rejected'::public.notification_kind,
      'Photo needs a retake',
      'Our automated check could not verify that photo. Please upload a clear selfie.',
      jsonb_build_object('verification_id', p_verification_id)
    FROM public.photo_verifications pv
    WHERE pv.id = p_verification_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.complete_ai_photo_review TO service_role;

-- ----------------------------------------------------------------------------
-- 4. Manual review decision
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.decide_photo_verification(
  p_verification_id UUID,
  p_approve BOOLEAN,
  p_notes TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user UUID;
BEGIN
  UPDATE public.photo_verifications
  SET
    state = CASE
      WHEN p_approve THEN 'approved'::public.photo_verification_state
      ELSE 'rejected'::public.photo_verification_state
    END,
    review_notes = p_notes,
    decided_at = NOW(),
    updated_at = NOW()
  WHERE id = p_verification_id
    AND state IN ('manual_review', 'ai_passed', 'ai_review')
  RETURNING user_id INTO v_user;

  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Verification not found or not reviewable';
  END IF;

  IF p_approve THEN
    -- Mark profile verified if at least one approved primary photo
    UPDATE public.profiles
    SET
      is_photo_verified = TRUE,
      photo_verification_status = 'verified',
      updated_at = NOW()
    WHERE id = v_user;

    INSERT INTO public.notification_outbox (user_id, kind, title, body, payload)
    VALUES (
      v_user,
      'photo_verified',
      'You''re verified ✓',
      'Your photo passed review. Full access unlocked.',
      jsonb_build_object('verification_id', p_verification_id)
    );
  ELSE
    UPDATE public.profiles
    SET
      photo_verification_status = 'rejected',
      is_photo_verified = FALSE,
      updated_at = NOW()
    WHERE id = v_user;

    INSERT INTO public.notification_outbox (user_id, kind, title, body, payload)
    VALUES (
      v_user,
      'photo_rejected',
      'Photo not approved',
      COALESCE(p_notes, 'Please upload a different photo that clearly shows your face.'),
      jsonb_build_object('verification_id', p_verification_id)
    );
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.decide_photo_verification TO service_role;

-- ----------------------------------------------------------------------------
-- 5. Dev/local stub: auto-approve after "AI" (pass-through for testing)
-- Call from Edge Function photo-review with STUB_AI=true
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.stub_auto_approve_photo(p_verification_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.complete_ai_photo_review(p_verification_id, 0.95, TRUE, 'stub AI pass');
  PERFORM public.decide_photo_verification(p_verification_id, TRUE, 'stub auto-approve');
END;
$$;

GRANT EXECUTE ON FUNCTION public.stub_auto_approve_photo TO service_role;

COMMENT ON FUNCTION public.submit_photo_for_verification IS
  'Client uploads to storage then calls this to enter AI review queue.';
COMMENT ON FUNCTION public.complete_ai_photo_review IS
  'Edge Function sets AI score; passed → manual_review, failed → ai_failed.';
COMMENT ON FUNCTION public.decide_photo_verification IS
  'Moderator (or stub) final approve/reject; updates profile flags + push outbox.';
