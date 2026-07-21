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

-- ============ TEST 11: response policy + cross-run evidence de-dupe ============
-- The production cron runs every 15 minutes with a 30-minute lookback. Move the
-- first flags outside the old five-minute de-dupe window, then scan the same
-- evidence again: stable evidence keys must keep each incident at one row.
UPDATE public.beacon_abuse_flags
SET created_at = NOW() - INTERVAL '10 minutes'
WHERE user_id IN (
  '61000000-0000-0000-0000-000000000061',
  '63000000-0000-0000-0000-000000000063'
);

DO $$ BEGIN
  PERFORM public.scan_relay_abuse(INTERVAL '1 day');
  ASSERT (
    SELECT count(*) FROM public.beacon_abuse_flags
    WHERE user_id = '61000000-0000-0000-0000-000000000061'
      AND reason = 'claim_teleport'
  ) = 1, 'T11 overlapping scan duplicated claim_teleport evidence';
  ASSERT (
    SELECT count(*) FROM public.beacon_abuse_flags
    WHERE user_id = '63000000-0000-0000-0000-000000000063'
      AND reason = 'relay_geo'
  ) = 1, 'T11 overlapping scan duplicated relay_geo evidence';

  -- Add two genuinely different incidents per reason to exercise thresholds.
  ASSERT public.note_abuse_flag(
    '61000000-0000-0000-0000-000000000061',
    'claim_teleport',
    '{"previous_token":"11111111111111111111111111111111","token":"22222222222222222222222222222222","meters":500000,"seconds":60,"mps":8333}'::jsonb
  ), 'T11 first distinct claim_teleport evidence was suppressed';
  ASSERT public.note_abuse_flag(
    '61000000-0000-0000-0000-000000000061',
    'claim_teleport',
    '{"previous_token":"22222222222222222222222222222222","token":"33333333333333333333333333333333","meters":600000,"seconds":60,"mps":10000}'::jsonb
  ), 'T11 second distinct claim_teleport evidence was suppressed';
  ASSERT public.note_abuse_flag(
    '63000000-0000-0000-0000-000000000063',
    'relay_geo',
    '{"token":"44444444444444444444444444444444","max_meters":50000,"observers":1}'::jsonb
  ), 'T11 first distinct relay_geo evidence was suppressed';
  ASSERT public.note_abuse_flag(
    '63000000-0000-0000-0000-000000000063',
    'relay_geo',
    '{"token":"55555555555555555555555555555555","max_meters":60000,"observers":2}'::jsonb
  ), 'T11 second distinct relay_geo evidence was suppressed';

  ASSERT (
    SELECT incident_count = 3
       AND priority = 'high'
       AND recommended_response = 'step_up_verification_and_manual_review'
       AND automatic_restriction IS FALSE
    FROM public.v_beacon_abuse_triage_24h
    WHERE user_id = '61000000-0000-0000-0000-000000000061'
      AND reason = 'claim_teleport'
  ), 'T11 repeated claim_teleport did not escalate to advisory step-up review';

  ASSERT (
    SELECT incident_count = 3
       AND priority = 'investigate'
       AND recommended_response = 'investigate_relay_pattern_no_user_restriction'
       AND automatic_restriction IS FALSE
    FROM public.v_beacon_abuse_triage_24h
    WHERE user_id = '63000000-0000-0000-0000-000000000063'
      AND reason = 'relay_geo'
  ), 'T11 relay_geo policy could punish the flagged token owner';

  ASSERT (
    SELECT incident_count = 3 AND affected_users = 1
    FROM public.v_beacon_abuse_digest_24h
    WHERE reason = 'claim_teleport'
  ), 'T11 24-hour digest did not aggregate distinct incidents';

  ASSERT NOT EXISTS (
    SELECT 1 FROM public.beacon_abuse_flags
    WHERE user_id IN (
      '61000000-0000-0000-0000-000000000061',
      '63000000-0000-0000-0000-000000000063'
    )
      AND (evidence_key IS NULL OR length(evidence_key) <> 64)
  ), 'T11 scanner evidence is missing a SHA-256 fingerprint';

  ASSERT has_table_privilege(
    'service_role', 'public.v_beacon_abuse_triage_24h', 'SELECT'
  ), 'T11 service role cannot read the abuse triage view';
  ASSERT NOT has_table_privilege(
    'authenticated', 'public.v_beacon_abuse_triage_24h', 'SELECT'
  ), 'T11 authenticated users can read the abuse triage view';
  ASSERT NOT has_table_privilege(
    'authenticated', 'public.beacon_abuse_flags', 'SELECT'
  ), 'T11 authenticated users can read raw abuse flags';
END $$;

-- ============ TEST 12: device-attestation gate (#6 step 3 scaffold) ============
-- When require_attestation is on, issue_token_batch needs a fresh, verified
-- device_attestations row (written only by the service-role Edge Function via
-- record_device_attestation). Off by default (non-breaking).
INSERT INTO auth.users (id,instance_id,aud,role,email,created_at,updated_at) VALUES
 ('71000000-0000-0000-0000-000000000071','00000000-0000-0000-0000-000000000000','authenticated','authenticated','att_g@t.local',now(),now());
UPDATE public.profiles SET display_name='G',dob='1990-01-01',is_active=true,age_verified=true,is_photo_verified=true,photo_urls=ARRAY['g.jpg'],is_paused=false,is_incognito=false WHERE id='71000000-0000-0000-0000-000000000071';
UPDATE public.app_settings SET value_num=1 WHERE key='require_attestation';
INSERT INTO public.app_settings (key,value_num) SELECT 'require_attestation',1
  WHERE NOT EXISTS (SELECT 1 FROM public.app_settings WHERE key='require_attestation');
DO $$ BEGIN
  PERFORM set_config('request.jwt.claims','{"sub":"71000000-0000-0000-0000-000000000071","role":"authenticated"}', true);
  -- no attestation on file -> rejected
  BEGIN
    PERFORM count(*) FROM public.issue_token_batch(CURRENT_DATE, 15);
    ASSERT false, 'T12 issued a batch with no attestation under require_attestation';
  EXCEPTION WHEN sqlstate '42501' THEN NULL; END;
  -- Edge Function (service role) records a verified attestation
  PERFORM public.record_device_attestation('71000000-0000-0000-0000-000000000071','android','pass', INTERVAL '24 hours', NULL);
  ASSERT (SELECT count(*) FROM public.issue_token_batch(CURRENT_DATE, 15)) = 96,
    'T12 attested account could not issue a batch';
  -- an expired attestation no longer satisfies the gate
  UPDATE public.device_attestations SET expires_at = NOW() - INTERVAL '1 minute'
    WHERE user_id='71000000-0000-0000-0000-000000000071';
  BEGIN
    PERFORM count(*) FROM public.issue_token_batch(CURRENT_DATE, 15);
    ASSERT false, 'T12 expired attestation still satisfied the gate';
  EXCEPTION WHEN sqlstate '42501' THEN NULL; END;
END $$;

-- ============ TEST 13: account deletion completeness (privacy) ============
-- request_account_deletion() must erase every regulated field synchronously,
-- and purge_deleted_accounts() must survive the ON DELETE NO ACTION foreign
-- keys (matches.user_a/user_b, messages.sender_id) that would otherwise make
-- DELETE FROM auth.users fail for any user who ever matched or chatted.
INSERT INTO auth.users (id,instance_id,aud,role,email,created_at,updated_at) VALUES
 ('81000000-0000-0000-0000-000000000081','00000000-0000-0000-0000-000000000000','authenticated','authenticated','del_h@t.local',now(),now()),
 ('82000000-0000-0000-0000-000000000082','00000000-0000-0000-0000-000000000000','authenticated','authenticated','del_i@t.local',now(),now());
UPDATE public.profiles SET display_name='H',dob='1990-01-01',gender='male',sexual_preference='women',
  interests=ARRAY['x'],photo_urls=ARRAY['h.jpg'],email_hint='h@t.local',phone_hint='555',
  neighborhood='Hoboken',is_active=true,age_verified=true
  WHERE id='81000000-0000-0000-0000-000000000081';
UPDATE public.profiles SET display_name='I',dob='1991-01-01',is_active=true
  WHERE id='82000000-0000-0000-0000-000000000082';

DO $$
DECLARE
  v_h UUID := '81000000-0000-0000-0000-000000000081';
  v_match BIGINT;
  v_purged INT;
BEGIN
  -- Give H the exact dependents that block a naive hard delete.
  INSERT INTO public.matches (user_a,user_b,status,matched_at)
    VALUES (v_h,'82000000-0000-0000-0000-000000000082','active',now())
    RETURNING id INTO v_match;
  INSERT INTO public.messages (match_id,sender_id,content,message_type,created_at)
    VALUES (v_match,v_h,'secret text', 'text', now());
  INSERT INTO public.location_pings (user_id,geo,created_at)
    VALUES (v_h, ST_SetSRID(ST_MakePoint(-74.03,40.74),4326)::geography, now());

  -- Phase 1: the user asks to be deleted.
  PERFORM set_config('request.jwt.claims',
    '{"sub":"81000000-0000-0000-0000-000000000081","role":"authenticated"}', true);
  PERFORM public.request_account_deletion();
  PERFORM set_config('request.jwt.claims', NULL, true);

  -- Every regulated field must be gone IMMEDIATELY, not at purge time.
  ASSERT (SELECT sexual_preference IS NULL AND dob IS NULL AND gender IS NULL
            AND email_hint IS NULL AND phone_hint IS NULL AND neighborhood IS NULL
            AND photo_urls IS NULL AND interests IS NULL AND bio IS NULL
            AND age_verified = FALSE AND is_active = FALSE
            AND deleted_at IS NOT NULL
          FROM public.profiles WHERE id = v_h),
    'T13 deletion left regulated PII on the profile';
  ASSERT NOT EXISTS (SELECT 1 FROM public.location_pings WHERE user_id = v_h),
    'T13 deletion left location history';
  ASSERT (SELECT content = '[deleted]' FROM public.messages WHERE sender_id = v_h),
    'T13 deletion did not redact message content';

  -- Not yet eligible: the grace window has not elapsed.
  ASSERT public.purge_deleted_accounts(INTERVAL '30 days') = 0,
    'T13 purge removed an account still inside its grace window';
  ASSERT EXISTS (SELECT 1 FROM auth.users WHERE id = v_h),
    'T13 account vanished before its grace window elapsed';

  -- Phase 2: age the request past the window and purge for real.
  UPDATE public.profiles SET deleted_at = NOW() - INTERVAL '31 days' WHERE id = v_h;
  v_purged := public.purge_deleted_accounts(INTERVAL '30 days');
  ASSERT v_purged = 1, format('T13 expected 1 purged account, got %s', v_purged);
  ASSERT NOT EXISTS (SELECT 1 FROM auth.users WHERE id = v_h),
    'T13 purge did not remove the auth.users row (NO ACTION FK likely blocked it)';
  ASSERT NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_h),
    'T13 purge left the profile behind';
  ASSERT NOT EXISTS (SELECT 1 FROM public.messages WHERE sender_id = v_h),
    'T13 purge left message rows behind';
  ASSERT NOT EXISTS (SELECT 1 FROM public.matches WHERE user_a = v_h OR user_b = v_h),
    'T13 purge left match rows behind';

  -- The counterpart must be untouched.
  ASSERT EXISTS (SELECT 1 FROM auth.users WHERE id = '82000000-0000-0000-0000-000000000082'),
    'T13 purge removed the counterpart account';
END $$;

-- Deletion is self-service only: it must key off auth.uid(), never a caller
-- argument, and the raw scrub helper must not be reachable by app users.
DO $$ BEGIN
  ASSERT NOT has_function_privilege('authenticated','public.scrub_account_pii(uuid)','EXECUTE'),
    'T13 authenticated users can execute scrub_account_pii directly';
  ASSERT NOT has_function_privilege('authenticated','public.purge_deleted_accounts(interval)','EXECUTE'),
    'T13 authenticated users can execute purge_deleted_accounts directly';
  ASSERT has_function_privilege('authenticated','public.request_account_deletion()','EXECUTE'),
    'T13 authenticated users cannot delete their own account';
END $$;

-- ============ TEST 14: data export scope (right of access) ============
-- export_my_data() must return the caller's own data and must NOT become a
-- bulk-extraction endpoint for the counterpart's profile.
INSERT INTO auth.users (id,instance_id,aud,role,email,created_at,updated_at) VALUES
 ('91000000-0000-0000-0000-000000000091','00000000-0000-0000-0000-000000000000','authenticated','authenticated','exp_j@t.local',now(),now()),
 ('92000000-0000-0000-0000-000000000092','00000000-0000-0000-0000-000000000000','authenticated','authenticated','exp_k@t.local',now(),now());
UPDATE public.profiles SET display_name='J',dob='1990-01-01',gender='female',
  sexual_preference='men',bio='my bio',is_active=true WHERE id='91000000-0000-0000-0000-000000000091';
UPDATE public.profiles SET display_name='KOUNTERPART',dob='1992-01-01',gender='male',
  sexual_preference='women',bio='counterpart secret bio',is_active=true
  WHERE id='92000000-0000-0000-0000-000000000092';

DO $$
DECLARE
  v_j UUID := '91000000-0000-0000-0000-000000000091';
  v_k UUID := '92000000-0000-0000-0000-000000000092';
  v_match BIGINT;
  v_doc JSONB;
  v_txt TEXT;
BEGIN
  INSERT INTO public.matches (user_a,user_b,status,matched_at)
    VALUES (v_j,v_k,'active',now()) RETURNING id INTO v_match;
  INSERT INTO public.messages (match_id,sender_id,content,message_type,created_at)
    VALUES (v_match,v_j,'mine',   'text', now()),
           (v_match,v_k,'theirs', 'text', now());
  INSERT INTO public.reports (reporter_id,reported_id,reason,details,status,created_at)
    VALUES (v_k,v_j,'spam','K reported J','open',now());

  PERFORM set_config('request.jwt.claims',
    '{"sub":"91000000-0000-0000-0000-000000000091","role":"authenticated"}', true);
  v_doc := public.export_my_data();
  PERFORM set_config('request.jwt.claims', NULL, true);

  ASSERT v_doc->>'export_format' = 'in_range.export.v1', 'T14 missing export format tag';
  ASSERT v_doc#>>'{profile,display_name}' = 'J', 'T14 export omitted the caller profile';
  ASSERT v_doc#>>'{account,email}' = 'exp_j@t.local', 'T14 export omitted the account email';
  ASSERT jsonb_array_length(v_doc->'matches') = 1, 'T14 export omitted matches';
  ASSERT jsonb_array_length(v_doc->'messages') = 2,
    'T14 export did not include the full conversation the caller took part in';

  -- The counterpart must appear ONLY as an opaque id.
  v_txt := v_doc::TEXT;
  ASSERT position('KOUNTERPART' in v_txt) = 0,
    'T14 export leaked the counterpart display_name';
  ASSERT position('counterpart secret bio' in v_txt) = 0,
    'T14 export leaked the counterpart bio';
  ASSERT position(v_k::TEXT in v_txt) > 0,
    'T14 export should still reference the counterpart by opaque id';

  -- Reports filed ABOUT the caller must not be disclosed (protects reporters).
  ASSERT position('K reported J' in v_txt) = 0,
    'T14 export disclosed a report filed about the caller';

  -- Unauthenticated callers get nothing.
  BEGIN
    PERFORM public.export_my_data();
    ASSERT false, 'T14 export succeeded with no authenticated user';
  EXCEPTION WHEN sqlstate '42501' THEN NULL; END;
END $$;

DO $$ BEGIN
  ASSERT has_function_privilege('authenticated','public.export_my_data()','EXECUTE'),
    'T14 authenticated users cannot export their own data';
  ASSERT NOT has_function_privilege('anon','public.export_my_data()','EXECUTE'),
    'T14 anonymous callers can execute the data export';
END $$;

-- ============ TEST 15: legal hold beats retention purge (§2258A) ============
-- A CyberTipline filing creates a 1-year preservation duty. The 15-minute
-- purge job must not destroy that evidence, and the subject must never be
-- able to see or lift the hold.
INSERT INTO auth.users (id,instance_id,aud,role,email,created_at,updated_at) VALUES
 ('a1000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','hold_l@t.local',now(),now());
UPDATE public.profiles SET display_name='L',dob='1990-01-01',gender='male',
  sexual_preference='women',is_active=true WHERE id='a1000000-0000-0000-0000-0000000000a1';

DO $$
DECLARE
  v_l UUID := 'a1000000-0000-0000-0000-0000000000a1';
  v_hold BIGINT;
BEGIN
  v_hold := public.place_legal_hold(v_l, 'cybertipline_2258a', 'test-runner', 'NCMEC report #1');

  -- §2258A(h)(1) is one year; the default must not be left to incident-response memory.
  ASSERT (SELECT expires_at > NOW() + INTERVAL '360 days'
            FROM public.legal_holds WHERE id = v_hold),
    'T15 cybertipline hold did not default to a 1-year preservation window';
  ASSERT public.has_legal_hold(v_l), 'T15 active hold not detected';

  -- The subject asks to be deleted. The request is recorded but NOT executed.
  PERFORM set_config('request.jwt.claims',
    '{"sub":"a1000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
  PERFORM public.request_account_deletion();
  PERFORM set_config('request.jwt.claims', NULL, true);

  ASSERT (SELECT deleted_at IS NOT NULL FROM public.profiles WHERE id = v_l),
    'T15 deletion request was not recorded for a held account';
  ASSERT (SELECT sexual_preference IS NOT NULL AND dob IS NOT NULL
            FROM public.profiles WHERE id = v_l),
    'T15 scrub ran despite an active preservation hold (evidence destroyed)';

  -- Age past the grace window: the purge must still refuse.
  UPDATE public.profiles SET deleted_at = NOW() - INTERVAL '400 days' WHERE id = v_l;
  ASSERT public.purge_deleted_accounts(INTERVAL '30 days') = 0,
    'T15 purge removed an account under an active preservation hold';
  ASSERT EXISTS (SELECT 1 FROM auth.users WHERE id = v_l),
    'T15 held account was destroyed by the retention job';

  -- Release the hold: the deferred deletion must then complete on its own.
  UPDATE public.legal_holds SET released_at = NOW(), released_by = 'test-runner'
   WHERE id = v_hold;
  ASSERT NOT public.has_legal_hold(v_l), 'T15 released hold still reads as active';
  ASSERT public.purge_deleted_accounts(INTERVAL '30 days') = 1,
    'T15 deferred deletion did not complete after the hold was released';
  ASSERT NOT EXISTS (SELECT 1 FROM auth.users WHERE id = v_l),
    'T15 account survived purge after hold release';

  -- An expired hold must not keep blocking.
  ASSERT NOT public.has_legal_hold('a2000000-0000-0000-0000-0000000000a2'),
    'T15 unheld user reads as held';
END $$;

-- The subject must never see, place, or lift a hold on themselves.
DO $$ BEGIN
  ASSERT NOT has_table_privilege('authenticated','public.legal_holds','SELECT'),
    'T15 users can read legal holds placed on them';
  ASSERT NOT has_function_privilege('authenticated','public.place_legal_hold(uuid,text,text,text,timestamptz)','EXECUTE'),
    'T15 users can place legal holds';
  ASSERT NOT has_function_privilege('authenticated','public.has_legal_hold(uuid)','EXECUTE'),
    'T15 users can probe whether they are under a legal hold';
END $$;

-- ============ TEST 16: TAKE IT DOWN NCII intake + copy removal ============
-- The intake must work with NO account (statutory), must not let anyone read
-- other people's reports, and removal must reach every identical copy.
INSERT INTO auth.users (id,instance_id,aud,role,email,created_at,updated_at) VALUES
 ('b1000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','ncii_m@t.local',now(),now()),
 ('b2000000-0000-0000-0000-0000000000b2','00000000-0000-0000-0000-000000000000','authenticated','authenticated','ncii_n@t.local',now(),now());

DO $$
DECLARE
  v_m UUID := 'b1000000-0000-0000-0000-0000000000b1';
  v_n UUID := 'b2000000-0000-0000-0000-0000000000b2';
  v_sha TEXT := repeat('ab', 32);   -- 64 hex chars
  v_other TEXT := repeat('cd', 32);
  v_id BIGINT;
  v_copies INT;
BEGIN
  -- The same image uploaded by two different users, into two buckets, plus an
  -- unrelated image that must survive.
  INSERT INTO public.media_hashes (bucket_id, object_name, sha256, user_id) VALUES
    ('profile_photos', v_m::TEXT || '/a.jpg', v_sha,   v_m),
    ('chat_media',     '1/' || v_n::TEXT || '/b.jpg', v_sha,   v_n),
    ('profile_photos', v_n::TEXT || '/c.jpg', v_other, v_n);

  -- Intake with NO authenticated user -- the statutory requirement.
  PERFORM set_config('request.jwt.claims', NULL, true);
  v_id := public.submit_ncii_report(
    'victim@example.com',
    'Intimate image of me posted without consent, visible on a profile.',
    'A Victim', 'profile: someuser', v_sha, TRUE);

  ASSERT v_id IS NOT NULL, 'T16 anonymous NCII intake failed';
  ASSERT (SELECT reporter_user_id IS NULL FROM public.ncii_reports WHERE id = v_id),
    'T16 anonymous report was attributed to a user';

  -- The 48-hour statutory clock must be stamped at intake.
  ASSERT (SELECT deadline_at BETWEEN NOW() + INTERVAL '47 hours'
                                 AND NOW() + INTERVAL '49 hours'
            FROM public.ncii_reports WHERE id = v_id),
    'T16 48-hour TAKE IT DOWN deadline was not stamped at intake';
  ASSERT (SELECT count(*) FROM public.v_ncii_sla WHERE id = v_id) = 1,
    'T16 open report is not on the SLA board';

  -- Garbage in must be rejected, not silently stored.
  BEGIN
    PERFORM public.submit_ncii_report('not-an-email', 'a valid description here');
    ASSERT false, 'T16 accepted a report with no usable contact address';
  EXCEPTION WHEN sqlstate '22023' THEN NULL; END;
  BEGIN
    PERFORM public.submit_ncii_report('v@example.com', 'short');
    ASSERT false, 'T16 accepted a report with no meaningful description';
  EXCEPTION WHEN sqlstate '22023' THEN NULL; END;

  -- Resolution must reach EVERY identical copy across buckets and owners.
  v_copies := public.ncii_resolve(v_id, 'removed', 'test-runner', 'verified');
  ASSERT v_copies = 2, format('T16 expected 2 identical copies queued, got %s', v_copies);
  ASSERT (SELECT count(*) FROM public.storage_deletion_queue
           WHERE object_name LIKE '%a.jpg' OR object_name LIKE '%b.jpg') = 2,
    'T16 identical copies were not queued for storage deletion';
  ASSERT NOT EXISTS (SELECT 1 FROM public.media_hashes WHERE sha256 = v_sha),
    'T16 hash rows for removed content survived';
  ASSERT EXISTS (SELECT 1 FROM public.media_hashes WHERE sha256 = v_other),
    'T16 removal destroyed an unrelated image';

  -- Resolved reports leave the SLA board but stay as the compliance record.
  ASSERT (SELECT count(*) FROM public.v_ncii_sla WHERE id = v_id) = 0,
    'T16 resolved report still shows as open';
  ASSERT (SELECT status = 'removed' AND resolved_at IS NOT NULL AND copies_removed = 2
            FROM public.ncii_reports WHERE id = v_id),
    'T16 resolution was not recorded for the compliance trail';
END $$;

-- Privilege boundaries on the only anon-writable surface in the system.
DO $$ BEGIN
  ASSERT has_function_privilege('anon','public.submit_ncii_report(text,text,text,text,text,boolean)','EXECUTE'),
    'T16 victims without an account cannot file a report (statutory requirement)';
  ASSERT NOT has_table_privilege('anon','public.ncii_reports','SELECT'),
    'T16 anonymous callers can read NCII reports';
  ASSERT NOT has_table_privilege('authenticated','public.ncii_reports','SELECT'),
    'T16 users can read NCII reports';
  ASSERT NOT has_function_privilege('authenticated','public.ncii_resolve(bigint,text,text,text)','EXECUTE'),
    'T16 users can resolve their own NCII reports';
  -- media_hashes must be write-only for users: readable, it is an oracle for
  -- whether a given image exists anywhere in the system.
  ASSERT NOT has_table_privilege('authenticated','public.media_hashes','SELECT'),
    'T16 media_hashes is readable by users (existence oracle)';
  ASSERT has_table_privilege('authenticated','public.media_hashes','INSERT'),
    'T16 users cannot record hashes for their own uploads';
END $$;

-- ============ TEST 17: unbundled, revocable, purpose-scoped consent ============
-- NJDPA excludes bundled ToS acceptance and dark patterns from "consent"; the
-- FTC orders require precise-location consent to be purpose-scoped. The schema
-- must make bundling impossible and keep an unforgeable audit trail.
INSERT INTO auth.users (id,instance_id,aud,role,email,created_at,updated_at) VALUES
 ('c1000000-0000-0000-0000-0000000000c1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','consent_o@t.local',now(),now());
UPDATE public.profiles SET display_name='O',dob='1990-01-01',is_active=true
  WHERE id='c1000000-0000-0000-0000-0000000000c1';

DO $$
DECLARE
  v_o UUID := 'c1000000-0000-0000-0000-0000000000c1';
  v_first BIGINT;
  v_again BIGINT;
  v_granted_at TIMESTAMPTZ;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"c1000000-0000-0000-0000-0000000000c1","role":"authenticated"}', true);

  v_first := public.grant_consent('precise_location','2026-07-20','onboarding.consent_step');
  ASSERT public.has_consent(v_o,'precise_location'), 'T17 granted consent not detected';

  -- Purpose-scoped: consenting to one purpose must NOT imply another.
  ASSERT NOT public.has_consent(v_o,'sensitive_profile'),
    'T17 consent for one purpose leaked into another (bundling)';
  ASSERT NOT public.has_consent(v_o,'background_location'),
    'T17 precise-location consent implied background collection';

  -- Re-granting is idempotent and must NOT restamp granted_at: the original
  -- moment of consent is the fact we have to evidence later.
  SELECT granted_at INTO v_granted_at FROM public.consent_records WHERE id = v_first;
  v_again := public.grant_consent('precise_location','2026-07-20','settings');
  ASSERT v_again = v_first, 'T17 re-grant created a duplicate active consent row';
  ASSERT (SELECT granted_at FROM public.consent_records WHERE id = v_first) = v_granted_at,
    'T17 re-grant overwrote the original granted_at';

  -- Consent must record which policy version it was given against.
  BEGIN
    PERFORM public.grant_consent('ble_proximity', '');
    ASSERT false, 'T17 accepted consent with no policy version';
  EXCEPTION WHEN sqlstate '22023' THEN NULL; END;

  -- Withdrawal must take effect AND actually stop the processing.
  INSERT INTO public.location_pings (user_id, geo, created_at)
    VALUES (v_o, ST_SetSRID(ST_MakePoint(-74.03,40.74),4326)::geography, now());
  ASSERT public.withdraw_consent('precise_location'), 'T17 withdrawal reported no effect';
  ASSERT NOT public.has_consent(v_o,'precise_location'), 'T17 withdrawn consent still active';
  ASSERT NOT EXISTS (SELECT 1 FROM public.location_pings WHERE user_id = v_o),
    'T17 withdrawing location consent left the location data in place';

  -- Append-only: the withdrawn grant survives as the audit trail.
  ASSERT (SELECT count(*) FROM public.consent_records
           WHERE user_id = v_o AND purpose = 'precise_location') = 1,
    'T17 withdrawal deleted the consent history';
  ASSERT (SELECT withdrawn_at IS NOT NULL FROM public.consent_records WHERE id = v_first),
    'T17 withdrawal did not stamp withdrawn_at';

  -- Re-granting after withdrawal is a NEW grant, not a resurrection.
  v_again := public.grant_consent('precise_location','2026-07-20','settings');
  ASSERT v_again <> v_first, 'T17 re-grant resurrected the withdrawn row';
  ASSERT (SELECT count(*) FROM public.consent_records
           WHERE user_id = v_o AND purpose = 'precise_location') = 2,
    'T17 re-grant did not preserve both grants in history';

  -- Enforcement is OFF by default (non-breaking rollout).
  PERFORM public.require_consent(v_o, 'sensitive_profile');   -- must not raise
  UPDATE public.app_settings SET value_num = 1 WHERE key = 'enforce_consent';
  BEGIN
    PERFORM public.require_consent(v_o, 'sensitive_profile');
    ASSERT false, 'T17 enforce_consent=1 did not gate an unconsented purpose';
  EXCEPTION WHEN sqlstate '42501' THEN NULL; END;
  PERFORM public.require_consent(v_o, 'precise_location');    -- consented, must not raise
  UPDATE public.app_settings SET value_num = 0 WHERE key = 'enforce_consent';

  PERFORM set_config('request.jwt.claims', NULL, true);
END $$;

DO $$ BEGIN
  ASSERT (SELECT value_num FROM public.app_settings WHERE key='enforce_consent') = 0,
    'T17 enforce_consent must ship OFF until the consent UI is on real devices';
  -- Clients may read their own consent (access right) but never write it
  -- directly, or the audit trail is forgeable.
  ASSERT has_table_privilege('authenticated','public.consent_records','SELECT'),
    'T17 users cannot see what they consented to';
  ASSERT NOT has_table_privilege('authenticated','public.consent_records','INSERT'),
    'T17 clients can forge consent records directly';
  ASSERT NOT has_table_privilege('authenticated','public.consent_records','UPDATE'),
    'T17 clients can rewrite their consent history';
  ASSERT NOT has_table_privilege('anon','public.consent_records','SELECT'),
    'T17 anonymous callers can read consent records';
END $$;

-- ============ TEST 18: the consent flag actually gates collection ============
-- 0039 shipped require_consent() with no callers, so flipping enforce_consent
-- would have been a silent no-op -- a control that reads as enforced while
-- collecting exactly as much data as before. Both halves are asserted here:
-- silent when OFF (non-breaking rollout), enforcing when ON.
INSERT INTO auth.users (id,instance_id,aud,role,email,created_at,updated_at) VALUES
 ('d1000000-0000-0000-0000-0000000000d1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','gate_p@t.local',now(),now());
UPDATE public.profiles SET display_name='P',dob='1990-01-01',is_active=true,
  age_verified=true,is_photo_verified=true,photo_urls=ARRAY['p.jpg'],
  is_paused=false,is_incognito=false WHERE id='d1000000-0000-0000-0000-0000000000d1';

DO $$
DECLARE
  v_p UUID := 'd1000000-0000-0000-0000-0000000000d1';
  v_tok TEXT := repeat('1a', 16);   -- 32 hex chars
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"d1000000-0000-0000-0000-0000000000d1","role":"authenticated"}', true);

  -- Isolate from earlier tests: T9 leaves enforce_batch_tokens = 1, and the
  -- whole harness runs in one transaction. This test is about the CONSENT
  -- gate, so the batch gate must not fire first and mask the result.
  UPDATE public.app_settings SET value_num = 0 WHERE key = 'enforce_batch_tokens';
  UPDATE public.app_settings SET value_num = 0 WHERE key = 'require_attestation';

  -- OFF (the shipped default): collection proceeds with no consent on file.
  -- If this raises, the rollout is breaking and must not ship.
  PERFORM public.claim_token(v_tok, NOW() + INTERVAL '15 minutes', 40.74, -74.03);
  PERFORM public.record_location_ping(40.74, -74.03);
  ASSERT NOT public.has_consent(v_p, 'ble_proximity'),
    'T18 precondition: user should have no consent on file';

  -- claim_token rate-limits to one claim per 5 seconds per user. Age the
  -- marker rather than sleeping, so the suite stays fast and deterministic.
  UPDATE public.token_claims SET last_claimed_at = NOW() - INTERVAL '1 minute'
   WHERE user_id = v_p;

  -- ON: every collection path must now refuse.
  UPDATE public.app_settings SET value_num = 1 WHERE key = 'enforce_consent';

  BEGIN
    PERFORM public.claim_token(repeat('2b', 16), NOW() + INTERVAL '15 minutes', 40.74, -74.03);
    ASSERT false, 'T18 claim_token collected a beacon token with no consent';
  EXCEPTION WHEN sqlstate '42501' THEN NULL; END;

  BEGIN
    PERFORM public.record_location_ping(40.74, -74.03);
    ASSERT false, 'T18 record_location_ping stored GPS with no consent';
  EXCEPTION WHEN sqlstate '42501' THEN NULL; END;

  BEGIN
    PERFORM public.record_sighting(repeat('3c', 16), 40.74, -74.03, -60);
    ASSERT false, 'T18 record_sighting stored an observation with no consent';
  EXCEPTION WHEN sqlstate '42501' THEN NULL; END;

  BEGIN
    PERFORM public.upsert_my_profile('P', NULL, '1990-01-01'::DATE, 'male', 'women');
    ASSERT false, 'T18 upsert_my_profile wrote sensitive fields with no consent';
  EXCEPTION WHEN sqlstate '42501' THEN NULL; END;

  -- Granting consent must unblock the corresponding path, and ONLY that one.
  PERFORM public.grant_consent('ble_proximity', '2026-07-20', 'test');
  UPDATE public.token_claims SET last_claimed_at = NOW() - INTERVAL '1 minute'
   WHERE user_id = v_p;
  PERFORM public.claim_token(repeat('4d', 16), NOW() + INTERVAL '15 minutes', 40.74, -74.03);

  BEGIN
    PERFORM public.record_location_ping(40.74, -74.03);
    ASSERT false, 'T18 BLE consent leaked into the location path';
  EXCEPTION WHEN sqlstate '42501' THEN NULL; END;

  -- Withdrawing must re-block immediately, not at some later sync.
  PERFORM public.withdraw_consent('ble_proximity');
  UPDATE public.token_claims SET last_claimed_at = NOW() - INTERVAL '1 minute'
   WHERE user_id = v_p;
  BEGIN
    PERFORM public.claim_token(repeat('5e', 16), NOW() + INTERVAL '15 minutes', 40.74, -74.03);
    ASSERT false, 'T18 withdrawn consent still permitted collection';
  EXCEPTION WHEN sqlstate '42501' THEN NULL; END;

  -- A profile write that does NOT touch sensitive fields must still work:
  -- clearing your orientation cannot require consent to clear it.
  PERFORM public.upsert_my_profile('P', NULL, '1990-01-01'::DATE, NULL, NULL);

  UPDATE public.app_settings SET value_num = 0 WHERE key = 'enforce_consent';
  PERFORM set_config('request.jwt.claims', NULL, true);
END $$;

-- ============ TEST 19: §2258A escalation preserves before it can be raced ===
-- Confirming an underage/enticement report must place a preservation hold that
-- survives the subject deleting their account, and must record a filing
-- obligation that cannot be silently dropped.
INSERT INTO auth.users (id,instance_id,aud,role,email,created_at,updated_at) VALUES
 ('e1000000-0000-0000-0000-0000000000e1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','esc_reporter@t.local',now(),now()),
 ('e2000000-0000-0000-0000-0000000000e2','00000000-0000-0000-0000-000000000000','authenticated','authenticated','esc_subject@t.local',now(),now());
UPDATE public.profiles SET display_name='Reporter',dob='1990-01-01',is_active=true
  WHERE id='e1000000-0000-0000-0000-0000000000e1';
UPDATE public.profiles SET display_name='Subject',dob='1990-01-01',sexual_preference='women',
  is_active=true WHERE id='e2000000-0000-0000-0000-0000000000e2';

DO $$
DECLARE
  v_reporter UUID := 'e1000000-0000-0000-0000-0000000000e1';
  v_subject  UUID := 'e2000000-0000-0000-0000-0000000000e2';
  v_report BIGINT;
  v_queue  BIGINT;
  v_match  BIGINT;
BEGIN
  -- A report requires a relationship; give them a match, then file.
  INSERT INTO public.matches (user_a,user_b,status,matched_at)
    VALUES (LEAST(v_reporter,v_subject),GREATEST(v_reporter,v_subject),'active',now())
    RETURNING id INTO v_match;
  PERFORM set_config('request.jwt.claims',
    '{"sub":"e1000000-0000-0000-0000-0000000000e1","role":"authenticated"}', true);
  v_report := public.report_user(v_subject, 'underage', 'Appears to be a minor', v_match);
  PERFORM set_config('request.jwt.claims', NULL, true);

  -- The report must surface for triage, minor-safety flagged.
  ASSERT EXISTS (SELECT 1 FROM public.v_report_triage
                  WHERE id = v_report AND review_for_2258a),
    'T19 underage report is not flagged for §2258A review';

  -- A reviewer confirms and escalates.
  v_queue := public.escalate_report(v_report, 'enticement_2422b', 'reviewer-1', 'confirmed minor');

  -- Preservation must be in place BEFORE any deletion can race it.
  ASSERT public.has_legal_hold(v_subject),
    'T19 escalation did not place a preservation hold on the subject';
  ASSERT EXISTS (SELECT 1 FROM public.v_cybertipline_pending WHERE id = v_queue),
    'T19 escalation did not open a CyberTipline filing obligation';
  ASSERT (SELECT status = 'actioned' FROM public.reports WHERE id = v_report),
    'T19 escalated report was left open';

  -- Now the subject tries to delete their account and age past the grace
  -- window. The purge must refuse -- evidence is under a §2258A hold.
  PERFORM set_config('request.jwt.claims',
    '{"sub":"e2000000-0000-0000-0000-0000000000e2","role":"authenticated"}', true);
  PERFORM public.request_account_deletion();
  PERFORM set_config('request.jwt.claims', NULL, true);
  UPDATE public.profiles SET deleted_at = NOW() - INTERVAL '400 days' WHERE id = v_subject;
  ASSERT public.purge_deleted_accounts(INTERVAL '30 days') = 0,
    'T19 purge destroyed evidence under an active §2258A hold';
  ASSERT (SELECT sexual_preference IS NOT NULL FROM public.profiles WHERE id = v_subject),
    'T19 the subject profile was scrubbed despite the hold';

  -- Filing records the NCMEC number and starts the 1-year preservation clock.
  PERFORM public.record_cybertipline_filing(v_queue, 'NCMEC-TEST-123', 'reporter-1');
  ASSERT (SELECT filed_at IS NOT NULL AND preserve_until > NOW() + INTERVAL '360 days'
            FROM public.cybertipline_queue WHERE id = v_queue),
    'T19 filing did not stamp the 1-year preservation window';
  ASSERT NOT EXISTS (SELECT 1 FROM public.v_cybertipline_pending WHERE id = v_queue),
    'T19 filed obligation still shows as pending';
END $$;

-- The whole surface is service-role only: a subject must never see it.
DO $$ BEGIN
  ASSERT NOT has_table_privilege('authenticated','public.cybertipline_queue','SELECT'),
    'T19 users can read the CyberTipline queue';
  ASSERT NOT has_function_privilege('authenticated','public.escalate_report(bigint,text,text,text)','EXECUTE'),
    'T19 users can escalate reports';
  ASSERT NOT has_table_privilege('authenticated','public.v_report_triage','SELECT'),
    'T19 users can read the report triage view';
END $$;

SELECT '✅ ALL RECIPROCITY SECURITY INVARIANTS PASSED' AS result;
ROLLBACK;
