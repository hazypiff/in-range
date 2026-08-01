-- 0062_waitlist_zone.sql
--
-- Launch-zone capture for the waitlist (marketing round 2026-07-31, joint
-- report docs/MARKETING_PRELAUNCH_2026-07-31_JOINT.md). The landing page adds
-- optional area chips (NYC metro / DC / MD / NoVA); the edge function
-- whitelists the value and passes it through. join_waitlist() gains p_zone and
-- returns zone_count + zone_rank so the confirmation card can show honest
-- per-zone progress (real counts only) without any new public read path.
--
-- DEPLOY-ORDER NOTE: applied to prod on 2026-07-31 while 0056-0061 were still
-- local-only (they ship with the app rollout, not the website). This file only
-- touches the waitlist objects from 0054/0055 — it is independent of 0056-0061
-- and written to be idempotent, so a later `supabase db push --include-all`
-- that replays it is harmless.

BEGIN;

ALTER TABLE public.waitlist ADD COLUMN IF NOT EXISTS zone TEXT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'waitlist_zone_len' AND conrelid = 'public.waitlist'::regclass
  ) THEN
    ALTER TABLE public.waitlist
      ADD CONSTRAINT waitlist_zone_len CHECK (zone IS NULL OR length(zone) <= 20);
  END IF;
END;
$$;

-- Zone progress is computed on every join/status call.
CREATE INDEX IF NOT EXISTS waitlist_zone_idx ON public.waitlist (zone) WHERE zone IS NOT NULL;

-- Replace the 3-arg ladder version (0055) with the zone-aware one.
DROP FUNCTION IF EXISTS public.join_waitlist(TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.join_waitlist(
  p_email  TEXT,
  p_source TEXT DEFAULT NULL,
  p_ref    TEXT DEFAULT NULL,
  p_zone   TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_email       TEXT;
  v_zone        TEXT;
  v_row         public.waitlist%ROWTYPE;
  v_new         BOOLEAN := FALSE;
  v_referrer_id BIGINT;
  v_code        TEXT;
  v_pos         BIGINT;
  v_total       BIGINT;
  v_zone_count  BIGINT;
  v_zone_rank   BIGINT;
BEGIN
  IF p_email IS NULL OR p_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' OR length(p_email) > 320 THEN
    RAISE EXCEPTION 'invalid email' USING ERRCODE = '22023';
  END IF;
  v_email := lower(trim(p_email));
  v_zone  := NULLIF(left(lower(trim(p_zone)), 20), '');

  SELECT * INTO v_row FROM public.waitlist WHERE lower(email) = v_email;

  IF NOT FOUND THEN
    IF p_ref IS NOT NULL AND length(trim(p_ref)) BETWEEN 4 AND 16 THEN
      SELECT id INTO v_referrer_id FROM public.waitlist WHERE ref_code = lower(trim(p_ref));
    END IF;

    -- Collision-proof code allocation (41-bit space; loop is belt+braces).
    LOOP
      v_code := public.gen_waitlist_ref_code();
      EXIT WHEN NOT EXISTS (SELECT 1 FROM public.waitlist WHERE ref_code = v_code);
    END LOOP;

    INSERT INTO public.waitlist (email, source, ref_code, referred_by, zone)
    VALUES (v_email, left(p_source, 40), v_code, v_referrer_id, v_zone)
    ON CONFLICT ((lower(email))) DO NOTHING
    RETURNING * INTO v_row;

    IF v_row.id IS NOT NULL THEN
      v_new := TRUE;
      -- Credit the referrer once, capped.
      IF v_referrer_id IS NOT NULL THEN
        UPDATE public.waitlist
           SET referral_count = referral_count + 1,
               priority = priority + CASE WHEN referral_count < 100 THEN 10 ELSE 0 END
         WHERE id = v_referrer_id;
      END IF;
    ELSE
      -- Concurrent insert won the race: fall back to their row.
      SELECT * INTO v_row FROM public.waitlist WHERE lower(email) = v_email;
    END IF;
  ELSIF v_zone IS NOT NULL AND v_zone IS DISTINCT FROM v_row.zone THEN
    -- Repeat post with a (different) zone: last-wins so a mis-tap is correctable.
    UPDATE public.waitlist SET zone = v_zone WHERE id = v_row.id;
    v_row.zone := v_zone;
  END IF;

  SELECT rn, t INTO v_pos, v_total
  FROM (
    SELECT id,
           ROW_NUMBER() OVER (ORDER BY priority DESC, id ASC) AS rn,
           COUNT(*) OVER () AS t
    FROM public.waitlist
  ) x
  WHERE x.id = v_row.id;

  IF v_row.zone IS NOT NULL THEN
    SELECT COUNT(*) INTO v_zone_count FROM public.waitlist WHERE zone = v_row.zone;
    SELECT rnk INTO v_zone_rank FROM (
      SELECT zone, RANK() OVER (ORDER BY COUNT(*) DESC) AS rnk
      FROM public.waitlist WHERE zone IS NOT NULL GROUP BY zone
    ) z WHERE z.zone = v_row.zone;
  END IF;

  RETURN jsonb_build_object(
    'position',       v_pos,
    'total',          v_total,
    'behind',         v_total - v_pos,
    'ref_code',       v_row.ref_code,
    'referral_count', (SELECT referral_count FROM public.waitlist WHERE id = v_row.id),
    'new',            v_new,
    'zone',           v_row.zone,
    'zone_count',     v_zone_count,
    'zone_rank',      v_zone_rank
  );
END;
$$;

REVOKE ALL ON FUNCTION public.join_waitlist(TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.join_waitlist(TEXT, TEXT, TEXT, TEXT) TO service_role;

COMMIT;
