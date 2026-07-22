-- 0043_media_hash_ownership.sql
--
-- Close the media_hashes forgery hole (2026-07-22 re-audit, HIGH).
--
-- The 0038 INSERT policy checked only user_id = auth.uid() — nothing tied
-- (bucket_id, object_name) to the caller. Two attacks followed:
--
--   1. Weaponized takedown: attacker inserts a row mapping a VICTIM's
--      legitimate object path to the sha256 of genuine NCII, then reports
--      that hash. The reviewer correctly approves removal of the reported
--      content, and ncii_resolve()'s identical-copy fan-out — which trusts
--      media_hashes blindly — queues the victim's innocent photo for
--      deletion. The reviewer cannot see the forgery.
--   2. Pre-claim DoS: the PK is (bucket_id, object_name), so an attacker
--      could claim another user's predictable object path first, making the
--      victim's own hash INSERT fail forever (their uploads then never
--      participate in takedown fan-out).
--
-- Fix: the WITH CHECK now mirrors the storage-bucket ownership conventions
-- already used by the 0019 storage policies and 0037's deletion queue:
-- profile_photos / verified_photos paths are <uid>/..., chat_media paths are
-- <match>/<uid>/... . Unknown buckets are rejected outright.

BEGIN;

-- Remove any existing rows that violate ownership (forged or misattributed).
-- Rows recorded by the legitimate client always satisfy the convention, so
-- this only ever deletes rows the new policy would have rejected.
DELETE FROM public.media_hashes
 WHERE user_id IS NULL
    OR NOT (
      (bucket_id IN ('profile_photos', 'verified_photos')
         AND (storage.foldername(object_name))[1] = user_id::TEXT)
      OR (bucket_id = 'chat_media'
         AND (storage.foldername(object_name))[2] = user_id::TEXT)
    );

DROP POLICY IF EXISTS "Users record own media hashes" ON public.media_hashes;
CREATE POLICY "Users record own media hashes"
  ON public.media_hashes FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND (
      (bucket_id IN ('profile_photos', 'verified_photos')
         AND (storage.foldername(object_name))[1] = auth.uid()::TEXT)
      OR (bucket_id = 'chat_media'
         AND (storage.foldername(object_name))[2] = auth.uid()::TEXT)
    )
  );

COMMIT;
