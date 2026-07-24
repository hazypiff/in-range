-- 0055_waitlist_referral.sql
--
-- Waitlist referral ladder (MARKETING_PLAN.md §3.3, Robinhood mechanic):
-- every signup gets a share code; each NEW signup that arrives with your code
-- bumps your priority, moving you up the line. Position is rank by
-- (priority DESC, id ASC) — referrers rise, ties resolve by signup order.
--
-- Anti-farming: credit is granted only when the referred email is a brand-new
-- insert (duplicates never re-credit), self-referral is ignored, and priority
-- gain caps at 100 credited referrals. The per-IP limit from 0054 still
-- fronts the only entry path (waitlist-join edge fn).

BEGIN;

ALTER TABLE public.waitlist
  ADD COLUMN IF NOT EXISTS ref_code       TEXT,
  ADD COLUMN IF NOT EXISTS referred_by    BIGINT REFERENCES public.waitlist(id),
  ADD COLUMN IF NOT EXISTS referral_count INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS priority       INT NOT NULL DEFAULT 0;

-- Short, unambiguous share code (no 0/O/1/l/i). ~41 bits at 8 chars.
CREATE OR REPLACE FUNCTION public.gen_waitlist_ref_code()
RETURNS TEXT
LANGUAGE sql
VOLATILE
SET search_path = pg_catalog, public, extensions
AS $$
  SELECT string_agg(
    substr('abcdefghjkmnpqrstuvwxyz23456789',
           (get_byte(extensions.gen_random_bytes(1), 0) % 31) + 1, 1), '')
  FROM generate_series(1, 8);
$$;
REVOKE ALL ON FUNCTION public.gen_waitlist_ref_code() FROM PUBLIC, anon, authenticated;

-- Backfill any pre-ladder rows, then lock the column.
UPDATE public.waitlist SET ref_code = public.gen_waitlist_ref_code() WHERE ref_code IS NULL;
ALTER TABLE public.waitlist ALTER COLUMN ref_code SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS waitlist_ref_code_uniq ON public.waitlist (ref_code);
CREATE INDEX IF NOT EXISTS waitlist_rank_idx ON public.waitlist (priority DESC, id ASC);

-- Replace the void-returning v1 (0054) with the ladder-aware version.
DROP FUNCTION IF EXISTS public.join_waitlist(TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.join_waitlist(
  p_email  TEXT,
  p_source TEXT DEFAULT NULL,
  p_ref    TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_email       TEXT;
  v_row         public.waitlist%ROWTYPE;
  v_new         BOOLEAN := FALSE;
  v_referrer_id BIGINT;
  v_code        TEXT;
  v_pos         BIGINT;
  v_total       BIGINT;
BEGIN
  IF p_email IS NULL OR p_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' OR length(p_email) > 320 THEN
    RAISE EXCEPTION 'invalid email' USING ERRCODE = '22023';
  END IF;
  v_email := lower(trim(p_email));

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

    INSERT INTO public.waitlist (email, source, ref_code, referred_by)
    VALUES (v_email, left(p_source, 40), v_code, v_referrer_id)
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
  END IF;

  SELECT rn, t INTO v_pos, v_total
  FROM (
    SELECT id,
           ROW_NUMBER() OVER (ORDER BY priority DESC, id ASC) AS rn,
           COUNT(*) OVER () AS t
    FROM public.waitlist
  ) x
  WHERE x.id = v_row.id;

  RETURN jsonb_build_object(
    'position',       v_pos,
    'total',          v_total,
    'behind',         v_total - v_pos,
    'ref_code',       v_row.ref_code,
    'referral_count', (SELECT referral_count FROM public.waitlist WHERE id = v_row.id),
    'new',            v_new
  );
END;
$$;

REVOKE ALL ON FUNCTION public.join_waitlist(TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.join_waitlist(TEXT, TEXT, TEXT) TO service_role;

COMMIT;
