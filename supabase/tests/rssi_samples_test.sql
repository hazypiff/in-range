-- rssi_samples_test.sql — invariants for 0056_calibration_rssi_samples.sql
--
-- Transactional: BEGIN ... ROLLBACK, so it leaves no rows behind and can be run
-- against any environment that already has the migration applied.
--
--   docker exec -i <db> psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
--     < supabase/tests/rssi_samples_test.sql
--
-- The properties under test are the ones that, if they broke, would corrupt
-- training data rather than throw: idempotent replay (a walk ingested twice
-- satisfies the >=3-walk trainer gate with copies of itself) and exact at_ms
-- pass-through (the walk_id digest hashes it).

\set ON_ERROR_STOP on

BEGIN;

-- Two users. The B user exists only to prove RLS isolation.
INSERT INTO auth.users (id, email) VALUES
  ('aaaaaaaa-0056-0056-0056-aaaaaaaaaaaa', 'walk-a@test.invalid'),
  ('bbbbbbbb-0056-0056-0056-bbbbbbbbbbbb', 'walk-b@test.invalid')
ON CONFLICT (id) DO NOTHING;

SELECT set_config('request.jwt.claim.sub',
                  'aaaaaaaa-0056-0056-0056-aaaaaaaaaaaa', true);

DO $$
DECLARE
  v_uid   UUID := 'aaaaaaaa-0056-0056-0056-aaaaaaaaaaaa';
  v_n     INT;
  v_cnt   INT;
  v_at    BIGINT;
  v_err   TEXT;
  v_big   JSONB;
  i       INT;
BEGIN
  -- === grants / RLS ========================================================
  ASSERT (SELECT c.relrowsecurity FROM pg_class c
           JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE n.nspname = 'public' AND c.relname = 'rssi_samples'),
    'rssi_samples lacks RLS';
  ASSERT (SELECT c.relrowsecurity FROM pg_class c
           JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE n.nspname = 'public' AND c.relname = 'rssi_batch_rate'),
    'rssi_batch_rate lacks RLS';

  ASSERT NOT has_table_privilege('anon', 'public.rssi_samples', 'SELECT'),
    'anon can read the co-location log';
  ASSERT has_table_privilege('authenticated', 'public.rssi_samples', 'SELECT'),
    'authenticated cannot read own samples (breaks export_my_data path)';
  -- Writes must go through the RPC or the batch cap and rate limit are moot.
  ASSERT NOT has_table_privilege('authenticated', 'public.rssi_samples', 'INSERT'),
    'authenticated can bypass record_rssi_batch';
  ASSERT NOT has_table_privilege('authenticated', 'public.rssi_samples', 'UPDATE'),
    'authenticated can mutate recorded samples';
  ASSERT NOT has_table_privilege('authenticated', 'public.rssi_samples', 'DELETE'),
    'authenticated can delete recorded samples';
  ASSERT NOT has_table_privilege('authenticated', 'public.rssi_batch_rate', 'SELECT'),
    'authenticated can inspect the rate bucket';

  ASSERT NOT has_function_privilege('anon',
    'public.record_rssi_batch(TEXT,TEXT,JSONB)', 'EXECUTE'),
    'anon can write RSSI samples';
  ASSERT has_function_privilege('authenticated',
    'public.record_rssi_batch(TEXT,TEXT,JSONB)', 'EXECUTE'),
    'authenticated cannot upload samples';

  -- === happy path ==========================================================
  v_n := public.record_rssi_batch('dev-aaaaaaaa', 'ios', '[
    {"device_seq": 1, "at_ms": 1784900000123, "correlation_id": "c0ffee01", "rssi": -57, "power": "H"},
    {"device_seq": 2, "at_ms": 1784900001123, "correlation_id": "c0ffee01", "rssi": -59, "power": "H"},
    {"device_seq": 3, "at_ms": 1784900002123, "correlation_id": "c0ffee01", "rssi": -61, "power": "M"}
  ]'::jsonb);
  ASSERT v_n = 3, format('expected 3 inserted, got %s', v_n);

  -- at_ms is the DEVICE clock and must survive verbatim: extract_walk.py
  -- windows on it and the walk_id digest hashes it.
  SELECT at_ms INTO v_at FROM public.rssi_samples
   WHERE user_id = v_uid AND device_seq = 1;
  ASSERT v_at = 1784900000123, format('at_ms rewritten: %s', v_at);

  -- === idempotent replay ===================================================
  -- The property that stops one walk being ingested as three.
  v_n := public.record_rssi_batch('dev-aaaaaaaa', 'ios', '[
    {"device_seq": 1, "at_ms": 1784900000123, "correlation_id": "c0ffee01", "rssi": -57, "power": "H"},
    {"device_seq": 2, "at_ms": 1784900001123, "correlation_id": "c0ffee01", "rssi": -59, "power": "H"},
    {"device_seq": 3, "at_ms": 1784900002123, "correlation_id": "c0ffee01", "rssi": -61, "power": "M"}
  ]'::jsonb);
  ASSERT v_n = 0, format('replay inserted %s rows', v_n);
  SELECT count(*) INTO v_cnt FROM public.rssi_samples WHERE user_id = v_uid;
  ASSERT v_cnt = 3, format('replay duplicated rows: %s', v_cnt);

  -- Partial overlap: only the new sequence lands.
  v_n := public.record_rssi_batch('dev-aaaaaaaa', 'ios', '[
    {"device_seq": 3, "at_ms": 1784900002123, "correlation_id": "c0ffee01", "rssi": -61, "power": "M"},
    {"device_seq": 4, "at_ms": 1784900003123, "correlation_id": "c0ffee01", "rssi": -63, "power": "H"}
  ]'::jsonb);
  ASSERT v_n = 1, format('partial overlap inserted %s rows, want 1', v_n);

  -- Identical CONTENT at a different device_seq is a distinct measurement and
  -- must NOT be deduped — two adverts can share (at_ms, corr, rssi, power),
  -- and dropping one would skew high_n/med_n in the trained features.
  v_n := public.record_rssi_batch('dev-aaaaaaaa', 'ios', '[
    {"device_seq": 5, "at_ms": 1784900003123, "correlation_id": "c0ffee01", "rssi": -63, "power": "H"}
  ]'::jsonb);
  ASSERT v_n = 1, 'content-identical sample at a new device_seq was dropped';

  -- Same device_seq under a DIFFERENT device_id is a different phone.
  v_n := public.record_rssi_batch('dev-bbbbbbbb', 'android', '[
    {"device_seq": 1, "at_ms": 1784900000456, "correlation_id": "deadbeef", "rssi": -70, "power": "H"}
  ]'::jsonb);
  ASSERT v_n = 1, 'device_id is not part of the identity key';

  -- Gap detection: seq 1..5 present on dev-aaaaaaaa, so a hole is visible.
  ASSERT (SELECT max(device_seq) - min(device_seq) + 1 = count(*)
            FROM public.rssi_samples
           WHERE user_id = v_uid AND device_id = 'dev-aaaaaaaa'),
    'sequence is not contiguous — gap detection would misreport';

  -- === input validation ====================================================
  v_n := public.record_rssi_batch('dev-aaaaaaaa', 'ios', '[]'::jsonb);
  ASSERT v_n = 0, 'empty batch should be a no-op';

  BEGIN
    v_n := public.record_rssi_batch('short', 'ios', '[]'::jsonb);
    ASSERT FALSE, 'short device_id accepted';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
  END;

  BEGIN
    v_n := public.record_rssi_batch('dev-aaaaaaaa', 'ios', '{"not":"array"}'::jsonb);
    ASSERT FALSE, 'non-array p_samples accepted';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
  END;

  BEGIN
    v_n := public.record_rssi_batch('dev-aaaaaaaa', 'linux', '[
      {"device_seq": 99, "at_ms": 1, "correlation_id": "x", "rssi": -1, "power": "H"}
    ]'::jsonb);
    ASSERT FALSE, 'unknown platform accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    v_n := public.record_rssi_batch('dev-aaaaaaaa', 'ios', '[
      {"device_seq": 98, "at_ms": 1, "correlation_id": "x", "rssi": -57, "power": "LOW"}
    ]'::jsonb);
    ASSERT FALSE, 'unknown power class accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    v_n := public.record_rssi_batch('dev-aaaaaaaa', 'ios', '[
      {"device_seq": 97, "at_ms": 1, "correlation_id": "x", "rssi": 999, "power": "H"}
    ]'::jsonb);
    ASSERT FALSE, 'out-of-range rssi accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- 501 rows: one past the client page size.
  SELECT jsonb_agg(jsonb_build_object(
           'device_seq', 1000 + g, 'at_ms', 1784900000000::BIGINT + g,
           'correlation_id', 'c0ffee01', 'rssi', -60, 'power', 'H'))
    INTO v_big FROM generate_series(1, 501) g;
  BEGIN
    v_n := public.record_rssi_batch('dev-aaaaaaaa', 'ios', v_big);
    ASSERT FALSE, 'oversized batch accepted';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
  END;

  -- === rate limit ==========================================================
  -- Fresh user so earlier calls in this test do not pollute the bucket.
  PERFORM set_config('request.jwt.claim.sub',
                     'bbbbbbbb-0056-0056-0056-bbbbbbbbbbbb', true);
  FOR i IN 1..20 LOOP
    PERFORM public.record_rssi_batch('dev-ratelimit', 'android', '[]'::jsonb);
  END LOOP;
  BEGIN
    PERFORM public.record_rssi_batch('dev-ratelimit', 'android', '[]'::jsonb);
    ASSERT FALSE, 'rate limit did not fire on the 21st call';
  EXCEPTION WHEN SQLSTATE '54000' THEN NULL;
  END;
  PERFORM set_config('request.jwt.claim.sub',
                     'aaaaaaaa-0056-0056-0056-aaaaaaaaaaaa', true);

  -- === unauthenticated =====================================================
  PERFORM set_config('request.jwt.claim.sub', '', true);
  BEGIN
    v_n := public.record_rssi_batch('dev-aaaaaaaa', 'ios', '[]'::jsonb);
    ASSERT FALSE, 'unauthenticated upload accepted';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;
END $$;

-- === RLS isolation ==========================================================
-- User B must not see user A's samples. Runs as a non-superuser so RLS applies.
SELECT set_config('request.jwt.claim.sub',
                  'bbbbbbbb-0056-0056-0056-bbbbbbbbbbbb', true);
SET LOCAL ROLE authenticated;

DO $$
BEGIN
  ASSERT (SELECT count(*) FROM public.rssi_samples) = 0,
    'RLS leak: another user can read the co-location log';
END $$;

RESET ROLE;
ROLLBACK;
