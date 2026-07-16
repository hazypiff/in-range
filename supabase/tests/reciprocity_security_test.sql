-- Security regression harness for the reciprocal-confirmation gate (#6 step 1).
-- Run transactionally against local Supabase/Postgres; it ROLLS BACK, leaving no
-- residue. Every check is a plpgsql ASSERT — the script fails loudly on the
-- first violated invariant. This is the guardrail for step 2 (server-issued
-- token batches): it must stay green as that lands.
--
--   docker cp this into the db container, then:
--   psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f reciprocity_security_test.sql
--
-- "Fresh migrations 0001-0029 apply cleanly" is checked separately by the
-- shell runner (a throwaway database), not here.

BEGIN;

-- ---------- fixtures ----------
INSERT INTO auth.users (id,instance_id,aud,role,email,created_at,updated_at) VALUES
 ('a0000000-0000-0000-0000-00000000000a','00000000-0000-0000-0000-000000000000','authenticated','authenticated','sec_a@t.local',now(),now()),
 ('b0000000-0000-0000-0000-00000000000b','00000000-0000-0000-0000-000000000000','authenticated','authenticated','sec_b@t.local',now(),now()),
 ('c0000000-0000-0000-0000-00000000000c','00000000-0000-0000-0000-000000000000','authenticated','authenticated','sec_c@t.local',now(),now());

UPDATE public.profiles SET display_name='A', dob='1990-01-01', age_verified=true, is_photo_verified=true, photo_urls=ARRAY['a.jpg'], is_paused=false, is_incognito=false WHERE id='a0000000-0000-0000-0000-00000000000a';
UPDATE public.profiles SET display_name='B', dob='1990-01-01', age_verified=true, is_photo_verified=true, photo_urls=ARRAY['b.jpg'], is_paused=false, is_incognito=false WHERE id='b0000000-0000-0000-0000-00000000000b';
UPDATE public.profiles SET display_name='C', dob='1990-01-01', age_verified=true, is_photo_verified=true, photo_urls=ARRAY['c.jpg'], is_paused=false, is_incognito=false WHERE id='c0000000-0000-0000-0000-00000000000c';

-- live token claims (in history, which is what the server resolves against)
INSERT INTO public.token_claim_history (token,user_id,valid_from,valid_until,approx_lat,approx_lon,range_type) VALUES
 ('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','a0000000-0000-0000-0000-00000000000a', now()-interval '10 s', now()+interval '10 min', 38.9,-76.9,'feet_10'),
 ('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb','b0000000-0000-0000-0000-00000000000b', now()-interval '10 s', now()+interval '10 min', 38.9,-76.9,'feet_10'),
 ('cccccccccccccccccccccccccccccccc','c0000000-0000-0000-0000-00000000000c', now()-interval '10 s', now()+interval '10 min', 38.9,-76.9,'feet_10'),
 -- grace: valid_until 1 min ago (inside the 2-min grace) -> still usable
 ('dddddddddddddddddddddddddddddddd','b0000000-0000-0000-0000-00000000000b', now()-interval '16 min', now()-interval '1 min', 38.9,-76.9,'feet_10'),
 -- expired: valid_until 5 min ago (past grace) -> must be rejected
 ('eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee','b0000000-0000-0000-0000-00000000000b', now()-interval '20 min', now()-interval '5 min', 38.9,-76.9,'feet_10');

-- helper: act as `actor`, report observing `token`. Optionally backdate the
-- server received_at (to simulate a stale reverse / prove observed_at can't help).
CREATE OR REPLACE FUNCTION pg_temp.sight(actor UUID, tok TEXT, rssi INT, band public.range_type, recv_shift INTERVAL DEFAULT INTERVAL '0')
RETURNS VOID LANGUAGE plpgsql AS $fn$
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub',actor,'role','authenticated')::text, true);
  PERFORM public.record_sighting(tok, 38.9, -76.9, rssi, now(), band, 10.0);
  IF recv_shift <> INTERVAL '0' THEN
    UPDATE public.sightings SET received_at = now() + recv_shift
    WHERE observer_user_id = actor AND observed_token = lower(tok);
  END IF;
END $fn$;

CREATE OR REPLACE FUNCTION pg_temp.enc_count(u1 UUID, u2 UUID) RETURNS INT LANGUAGE sql AS
$c$ SELECT count(*)::int FROM public.encounters WHERE user_a=LEAST(u1,u2) AND user_b=GREATEST(u1,u2) $c$;
CREATE OR REPLACE FUNCTION pg_temp.pair_sessions(u1 UUID, u2 UUID) RETURNS INT LANGUAGE sql AS
$c$ SELECT COALESCE((SELECT session_count FROM public.encounter_pairs WHERE user_a=LEAST(u1,u2) AND user_b=GREATEST(u1,u2)),0)::int $c$;
CREATE OR REPLACE FUNCTION pg_temp.session_rows(u1 UUID, u2 UUID) RETURNS INT LANGUAGE sql AS
$c$ SELECT count(*)::int FROM public.encounter_sessions s JOIN public.encounters e ON e.id=s.encounter_id
     WHERE e.user_a=LEAST(u1,u2) AND e.user_b=GREATEST(u1,u2) $c$;

\set A '''a0000000-0000-0000-0000-00000000000a'''
\set B '''b0000000-0000-0000-0000-00000000000b'''
\set C '''c0000000-0000-0000-0000-00000000000c'''

-- ============ TEST 1: one-way report creates nothing ============
SELECT pg_temp.sight(:A, 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', -60, 'feet_10');
DO $$ BEGIN
  ASSERT pg_temp.enc_count('a0000000-0000-0000-0000-00000000000a','b0000000-0000-0000-0000-00000000000b') = 0, 'T1 one-way created an encounter';
  ASSERT pg_temp.pair_sessions('a0000000-0000-0000-0000-00000000000a','b0000000-0000-0000-0000-00000000000b') = 0, 'T1 one-way bumped recurrence';
END $$;

-- ============ TEST 2: stale reverse (server received_at) creates nothing ============
-- B's report has observed_at=now() (fresh-looking) but received_at backdated 5 min:
-- proves the window uses server received_at, and a forged observed_at cannot widen it.
SELECT pg_temp.sight(:B, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', -85, 'feet_60', INTERVAL '-5 min');
SELECT pg_temp.sight(:A, 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', -60, 'feet_10'); -- retrigger correlate
DO $$ BEGIN
  ASSERT pg_temp.enc_count('a0000000-0000-0000-0000-00000000000a','b0000000-0000-0000-0000-00000000000b') = 0, 'T2 stale reverse (forged observed_at) confirmed an encounter';
END $$;

-- ============ TEST 3: reciprocal (fresh) creates exactly one, wider band ============
UPDATE public.sightings SET received_at = now() WHERE observer_user_id = 'b0000000-0000-0000-0000-00000000000b' AND observed_token='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
SELECT pg_temp.sight(:A, 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', -60, 'feet_10');
DO $$ BEGIN
  ASSERT pg_temp.enc_count('a0000000-0000-0000-0000-00000000000a','b0000000-0000-0000-0000-00000000000b') = 1, 'T3 reciprocal did not create exactly one encounter';
  ASSERT pg_temp.pair_sessions('a0000000-0000-0000-0000-00000000000a','b0000000-0000-0000-0000-00000000000b') = 1, 'T3 recurrence session_count != 1';
  ASSERT (SELECT range_type FROM public.encounters WHERE user_a=LEAST('a0000000-0000-0000-0000-00000000000a'::uuid,'b0000000-0000-0000-0000-00000000000b'::uuid) AND user_b=GREATEST('a0000000-0000-0000-0000-00000000000a'::uuid,'b0000000-0000-0000-0000-00000000000b'::uuid)) = 'feet_60',
    'T3 displayed band is not the wider (conservative) of the two directions';
  ASSERT (SELECT trust_level FROM public.encounters WHERE user_a=LEAST('a0000000-0000-0000-0000-00000000000a'::uuid,'b0000000-0000-0000-0000-00000000000b'::uuid) AND user_b=GREATEST('a0000000-0000-0000-0000-00000000000a'::uuid,'b0000000-0000-0000-0000-00000000000b'::uuid)) = 'mutual_ble',
    'T3 trust_level is not mutual_ble';
END $$;

-- ============ TEST 4: repeated reciprocal reports stay exactly one ============
-- Recurrence lives in encounter_pairs (the durable aggregate); a repeat report
-- within the session gap must NOT create a second encounter or bump the count.
-- NOTE: this is SEQUENTIAL idempotency (same transaction, one call after
-- another). The pg_advisory_xact_lock only matters under two OVERLAPPING
-- committed transactions, which a rolled-back single-txn fixture cannot stage —
-- that race is covered by check 3 in run_security_tests.sh.
SELECT pg_temp.sight(:B, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', -85, 'feet_60');
SELECT pg_temp.sight(:A, 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', -60, 'feet_10');
DO $$ BEGIN
  ASSERT pg_temp.enc_count('a0000000-0000-0000-0000-00000000000a','b0000000-0000-0000-0000-00000000000b') = 1, 'T4 duplicate encounter created';
  ASSERT pg_temp.pair_sessions('a0000000-0000-0000-0000-00000000000a','b0000000-0000-0000-0000-00000000000b') = 1, 'T4 repeat report bumped recurrence session_count (same crossing)';
END $$;

-- ============ TEST 5: a block on EITHER direction prevents confirmation ============
INSERT INTO public.blocks (blocker_id, blocked_id) VALUES ('a0000000-0000-0000-0000-00000000000a','c0000000-0000-0000-0000-00000000000c');
SELECT pg_temp.sight(:C, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', -60, 'feet_10');
SELECT pg_temp.sight(:A, 'cccccccccccccccccccccccccccccccc', -60, 'feet_10');
DO $$ BEGIN
  ASSERT pg_temp.enc_count('a0000000-0000-0000-0000-00000000000a','c0000000-0000-0000-0000-00000000000c') = 0, 'T5 blocked pair was confirmed';
END $$;

-- ============ TEST 6: token rotation grace works, expired fails ============
DO $$ BEGIN
  -- expired token (valid_until 5 min ago, past 2-min grace) must be rejected
  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub','a0000000-0000-0000-0000-00000000000a','role','authenticated')::text, true);
    PERFORM public.record_sighting('eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee', 38.9,-76.9,-60,now(),'feet_10',10.0);
    ASSERT false, 'T6 expired token was accepted';
  EXCEPTION WHEN sqlstate '22023' THEN NULL; -- expected 'Unknown or expired beacon token'
  END;
  -- grace token (valid_until 1 min ago, inside grace) must be accepted
  PERFORM set_config('request.jwt.claims', json_build_object('sub','a0000000-0000-0000-0000-00000000000a','role','authenticated')::text, true);
  PERFORM public.record_sighting('dddddddddddddddddddddddddddddddd', 38.9,-76.9,-60,now(),'feet_10',10.0);
  ASSERT EXISTS (SELECT 1 FROM public.sightings WHERE observer_user_id='a0000000-0000-0000-0000-00000000000a' AND observed_token='dddddddddddddddddddddddddddddddd'),
    'T6 in-grace token was rejected';
END $$;

-- ============ TEST 7: protected evidence is not directly readable ============
-- Raw proximity evidence (sightings, token_claim_history) and the durable
-- recurrence aggregate (encounter_pairs) are RPC-only: the authenticated role
-- has NO direct grant, so no user — participant or not — can read them
-- directly. Access is mediated by the participation-checking SECURITY DEFINER
-- RPCs. That is strictly stronger than RLS row-filtering, and it's what stops a
-- nonparticipant from reading another pair's evidence.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub','c0000000-0000-0000-0000-00000000000c','role','authenticated')::text, true);
DO $$
DECLARE tbl TEXT; ok BOOLEAN;
BEGIN
  FOREACH tbl IN ARRAY ARRAY['sightings','token_claim_history','encounter_pairs'] LOOP
    ok := FALSE;
    BEGIN
      EXECUTE format('SELECT 1 FROM public.%I LIMIT 1', tbl);
    EXCEPTION WHEN insufficient_privilege THEN ok := TRUE;
    END;
    ASSERT ok, format('T7 %s is directly readable by the authenticated role (should be RPC-only)', tbl);
  END LOOP;
END $$;
RESET ROLE;

-- ============ TEST 8: end-of-life reciprocal token still confirms ============
-- Regression for the rotation-boundary bug (migration 0030). Both phones observe
-- each other in the token's 2-min grace window, so valid_until is ~1 min past but
-- valid_from is ~16 min ago. record_sighting accepts it (valid_until grace), and
-- correlate_encounter MUST also confirm — before 0030 its valid_from > now-15min
-- floor silently dropped these, so the sighting stored but no encounter formed.
INSERT INTO auth.users (id,instance_id,aud,role,email,created_at,updated_at) VALUES
 ('d0000000-0000-0000-0000-00000000000d','00000000-0000-0000-0000-000000000000','authenticated','authenticated','sec_d@t.local',now(),now()),
 ('e0000000-0000-0000-0000-00000000000e','00000000-0000-0000-0000-000000000000','authenticated','authenticated','sec_e@t.local',now(),now());
UPDATE public.profiles SET display_name='D', dob='1990-01-01', age_verified=true, is_photo_verified=true, photo_urls=ARRAY['d.jpg'], is_paused=false, is_incognito=false WHERE id='d0000000-0000-0000-0000-00000000000d';
UPDATE public.profiles SET display_name='E', dob='1990-01-01', age_verified=true, is_photo_verified=true, photo_urls=ARRAY['e.jpg'], is_paused=false, is_incognito=false WHERE id='e0000000-0000-0000-0000-00000000000e';
-- both tokens in grace: valid_from 16 min ago, valid_until 1 min ago
INSERT INTO public.token_claim_history (token,user_id,valid_from,valid_until,approx_lat,approx_lon,range_type) VALUES
 ('d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1','d0000000-0000-0000-0000-00000000000d', now()-interval '16 min', now()-interval '1 min', 38.9,-76.9,'feet_10'),
 ('e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1','e0000000-0000-0000-0000-00000000000e', now()-interval '16 min', now()-interval '1 min', 38.9,-76.9,'feet_10');
SELECT pg_temp.sight('e0000000-0000-0000-0000-00000000000e', 'd1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1', -60, 'feet_10'); -- E observes D (fresh receipt)
SELECT pg_temp.sight('d0000000-0000-0000-0000-00000000000d', 'e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1', -60, 'feet_10'); -- D observes E -> confirm
DO $$ BEGIN
  ASSERT pg_temp.enc_count('d0000000-0000-0000-0000-00000000000d','e0000000-0000-0000-0000-00000000000e') = 1,
    'T8 end-of-life (grace) reciprocal token did not confirm — correlate valid_from floor too tight';
END $$;

-- ============ TEST 9: server-issued token batches (#6 step 2) ============
-- issue_token_batch mints opaque, server-owned tokens; a peer cannot claim a
-- token the server didn't issue to them (once enforcement is on). Uses A and B
-- from the fixtures above.
DO $$
DECLARE v_cnt INT; v_distinct INT; v_hexok BOOLEAN; v_first TEXT[]; v_second TEXT[];
        v_a_tok TEXT; v_b_tok TEXT;
BEGIN
  PERFORM set_config('request.jwt.claims','{"sub":"a0000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);
  SELECT count(*), count(DISTINCT token), bool_and(token ~ '^[0-9a-f]{32}$')
    INTO v_cnt, v_distinct, v_hexok FROM public.issue_token_batch(CURRENT_DATE, 15);
  ASSERT v_cnt = 96 AND v_distinct = 96, 'T9 batch is not 96 distinct tokens';
  ASSERT v_hexok, 'T9 batch tokens are not opaque 32-hex';
  -- idempotent: a re-fetch returns the identical set (no churn)
  SELECT array_agg(token ORDER BY slot) INTO v_first FROM public.issue_token_batch(CURRENT_DATE, 15);
  SELECT array_agg(token ORDER BY slot) INTO v_second FROM public.beacon_token_batch
    WHERE user_id='a0000000-0000-0000-0000-00000000000a' AND batch_day=CURRENT_DATE;
  ASSERT v_first = v_second, 'T9 re-issue was not idempotent';

  SELECT token INTO v_a_tok FROM public.beacon_token_batch
    WHERE user_id='a0000000-0000-0000-0000-00000000000a' AND valid_from<=now() AND valid_until>now() LIMIT 1;
  PERFORM set_config('request.jwt.claims','{"sub":"b0000000-0000-0000-0000-00000000000b","role":"authenticated"}', true);
  PERFORM public.issue_token_batch(CURRENT_DATE, 15);
  SELECT token INTO v_b_tok FROM public.beacon_token_batch
    WHERE user_id='b0000000-0000-0000-0000-00000000000b' AND valid_from<=now() AND valid_until>now() LIMIT 1;

  -- enforcement ON for the binding checks
  UPDATE public.app_settings SET value_num=1 WHERE key='enforce_batch_tokens';
  INSERT INTO public.app_settings (key,value_num) SELECT 'enforce_batch_tokens',1
    WHERE NOT EXISTS (SELECT 1 FROM public.app_settings WHERE key='enforce_batch_tokens');

  -- A can claim A's own issued token
  PERFORM set_config('request.jwt.claims','{"sub":"a0000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);
  PERFORM public.claim_token(v_a_tok, now()+interval '15 min', 38.9,-76.9,'feet_10',10.0);
  ASSERT (SELECT consumed_at IS NOT NULL FROM public.beacon_token_batch WHERE token=v_a_tok),
    'T9 own batch token was not consumed on claim';

  -- A cannot claim a self-minted (non-issued) token under enforcement
  BEGIN
    PERFORM public.claim_token('deadbeefdeadbeefdeadbeefdeadbeef', now()+interval '15 min',38.9,-76.9,'feet_10',10.0);
    ASSERT false, 'T9 self-minted token accepted under enforcement';
  EXCEPTION WHEN sqlstate '22023' THEN NULL; END;

  -- A cannot claim B's issued token (not in A's batch)
  BEGIN
    PERFORM public.claim_token(v_b_tok, now()+interval '15 min',38.9,-76.9,'feet_10',10.0);
    ASSERT false, 'T9 cross-user batch token accepted';
  EXCEPTION WHEN sqlstate '22023' THEN NULL; END;
END $$;

-- ============ TEST 10: relay-abuse detection (#6 step 4) ============
-- scan_relay_abuse flags impossible movement (spoofed GPS) and tokens observed
-- implausibly far from where they were claimed (relayed), and leaves honest
-- movement / nearby observers alone.
INSERT INTO auth.users (id,instance_id,aud,role,email,created_at,updated_at) VALUES
 ('61000000-0000-0000-0000-000000000061','00000000-0000-0000-0000-000000000000','authenticated','authenticated','ab_tp@t.local',now(),now()),
 ('62000000-0000-0000-0000-000000000062','00000000-0000-0000-0000-000000000000','authenticated','authenticated','ab_nm@t.local',now(),now()),
 ('63000000-0000-0000-0000-000000000063','00000000-0000-0000-0000-000000000000','authenticated','authenticated','ab_rl@t.local',now(),now()),
 ('64000000-0000-0000-0000-000000000064','00000000-0000-0000-0000-000000000000','authenticated','authenticated','ab_nr@t.local',now(),now()),
 ('65000000-0000-0000-0000-000000000065','00000000-0000-0000-0000-000000000000','authenticated','authenticated','ab_ob@t.local',now(),now());
-- teleporter: ~1010 km in 60 s
INSERT INTO public.token_claim_history (token,user_id,valid_from,valid_until,approx_lat,approx_lon,range_type) VALUES
 ('e1e1aaaae1e1aaaae1e1aaaae1e1aaaa','61000000-0000-0000-0000-000000000061', now()-interval '60 s', now()+interval '10 min', 38.9,-76.9,'feet_10'),
 ('e2e2aaaae2e2aaaae2e2aaaae2e2aaaa','61000000-0000-0000-0000-000000000061', now(),                now()+interval '10 min', 48.0,-76.9,'feet_10'),
-- normal mover: ~130 m in 15 min (control)
 ('f1f1bbbbf1f1bbbbf1f1bbbbf1f1bbbb','62000000-0000-0000-0000-000000000062', now()-interval '15 min', now()+interval '10 min', 38.9000,-76.9,'feet_10'),
 ('f2f2bbbbf2f2bbbbf2f2bbbbf2f2bbbb','62000000-0000-0000-0000-000000000062', now(),                  now()+interval '10 min', 38.9012,-76.9,'feet_10'),
-- relayed owner (token seen ~55 km away) + near owner (control)
 ('a1a1cccca1a1cccca1a1cccca1a1cccc','63000000-0000-0000-0000-000000000063', now(), now()+interval '10 min', 38.9,-76.9,'feet_10'),
 ('a1a1dddda1a1dddda1a1dddda1a1dddd','64000000-0000-0000-0000-000000000064', now(), now()+interval '10 min', 38.9,-76.9,'feet_10');
INSERT INTO public.sightings (observer_user_id,observed_token,received_at,rssi,observed_at,observer_lat,observer_lon,range_type) VALUES
 ('65000000-0000-0000-0000-000000000065','a1a1cccca1a1cccca1a1cccca1a1cccc', now(), -60, now(), 39.4,   -76.9,'feet_10'),  -- 55 km -> relay
 ('65000000-0000-0000-0000-000000000065','a1a1dddda1a1dddda1a1dddda1a1dddd', now(), -60, now(), 38.9012,-76.9,'feet_10'); -- 130 m -> ok
DO $$ BEGIN
  PERFORM public.scan_relay_abuse(INTERVAL '1 day');
  ASSERT (SELECT count(*) FROM public.beacon_abuse_flags WHERE user_id='61000000-0000-0000-0000-000000000061' AND reason='claim_teleport') = 1,
    'T10 teleporting account was not flagged';
  ASSERT (SELECT count(*) FROM public.beacon_abuse_flags WHERE user_id='62000000-0000-0000-0000-000000000062' AND reason='claim_teleport') = 0,
    'T10 normal movement was wrongly flagged as teleport';
  ASSERT (SELECT count(*) FROM public.beacon_abuse_flags WHERE user_id='63000000-0000-0000-0000-000000000063' AND reason='relay_geo') = 1,
    'T10 relayed token (far observer) was not flagged';
  ASSERT (SELECT count(*) FROM public.beacon_abuse_flags WHERE user_id='64000000-0000-0000-0000-000000000064' AND reason='relay_geo') = 0,
    'T10 nearby observer was wrongly flagged as relay';
END $$;

SELECT '✅ ALL RECIPROCITY SECURITY INVARIANTS PASSED' AS result;
ROLLBACK;
