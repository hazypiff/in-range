#!/usr/bin/env bash
# Reciprocity security regression harness (reviewer #6).
#
#   1. Migration-ordering check: apply the security migrations (0020+) in order,
#      idempotently, onto the production-equivalent schema.
#   2. Invariant check: run reciprocity_security_test.sql transactionally
#      (it ROLLS BACK) against the live local dev database.
#   3. Concurrency check: two OVERLAPPING committed transactions confirm the same
#      pair at once; the pg_advisory_xact_lock must serialize them to exactly one
#      encounter. This is the only check that exercises the lock (the fixture's
#      T4 is sequential and cannot). It seeds and then deletes its own rows.
#
# Requires the local Supabase Postgres container. Keep this green before/after
# shipping token batches (#6 step 2).
set -euo pipefail
CONTAINER="${SUPABASE_DB_CONTAINER:-supabase_db_in-range}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"   # supabase/
# -i so heredoc/stdin actually attaches (without it docker exec discards stdin
# and psql runs nothing, exiting 0 — a silent no-op seed).
DBX="docker exec -i -e PGPASSWORD=postgres $CONTAINER psql -U postgres -v ON_ERROR_STOP=1"

echo "== 1/3 security migrations (0020+) apply cleanly, in order, idempotently =="
# A full from-0001 rebuild is what `supabase db reset` does (it provisions the
# pristine Supabase base — auth/storage/realtime/extensions — then applies every
# migration); reconstructing that base by hand from a post-migration database is
# not faithful. Here we check the risk that actually matters for adding new
# migrations: that the security set applies IN ORDER without dependency/ordering
# breaks. They are written idempotently (CREATE OR REPLACE / IF NOT EXISTS /
# ON CONFLICT), so re-applying them onto the production-equivalent schema must be
# a clean no-op — which catches an out-of-order or conflicting new migration.
for f in "$HERE"/migrations/00[2-9][0-9]_*.sql; do
  docker cp "$f" "$CONTAINER:/tmp/m.sql" >/dev/null
  if ! $DBX -d postgres -f /tmp/m.sql >/tmp/mout 2>&1; then
    echo "❌ $(basename "$f") did not apply cleanly:"; grep -iE "ERROR|LINE" /tmp/mout | head -3; exit 1
  fi
done
echo "✅ 0020+ apply cleanly in order (idempotent re-apply)"
echo "   (full from-0001 rebuild: use 'supabase db reset')"

echo "== 2/3 reciprocity security invariants (transactional, rolled back) =="
docker cp "$HERE/tests/reciprocity_security_test.sql" "$CONTAINER:/tmp/sectest.sql" >/dev/null
$DBX -d postgres -f /tmp/sectest.sql 2>&1 | grep -E "PASSED|ERROR|ASSERT" || { echo "❌ invariant check failed"; exit 1; }

echo "== 3/3 advisory lock serializes truly concurrent reciprocal confirms =="
# Two users, both directions primed and fresh, then two overlapping correlate
# calls race on the pair. Without pg_advisory_xact_lock both would try to INSERT
# the encounter; the lock must serialize them into exactly one. Committed rows
# (can't roll back — the race needs separate transactions), so cleanup runs on
# entry and exit.
X='c1c1c1c1-0000-0000-0000-0000000000c1'
Y='c2c2c2c2-0000-0000-0000-0000000000c2'
XT='c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1'
YT='c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2'
conc_cleanup() {
  $DBX -d postgres -q <<SQL >/dev/null 2>&1 || true
DELETE FROM public.encounters      WHERE user_a=LEAST('$X'::uuid,'$Y'::uuid) AND user_b=GREATEST('$X'::uuid,'$Y'::uuid);
DELETE FROM public.encounter_pairs WHERE user_a=LEAST('$X'::uuid,'$Y'::uuid) AND user_b=GREATEST('$X'::uuid,'$Y'::uuid);
DELETE FROM public.sightings           WHERE observer_user_id IN ('$X','$Y');
DELETE FROM public.token_claim_history WHERE user_id IN ('$X','$Y');
DELETE FROM public.token_claims        WHERE user_id IN ('$X','$Y');
DELETE FROM auth.users WHERE id IN ('$X','$Y');
SQL
}
trap conc_cleanup EXIT
conc_cleanup   # pre-clean any residue from a prior aborted run

$DBX -d postgres -q >/dev/null <<SQL
INSERT INTO auth.users (id,instance_id,aud,role,email,created_at,updated_at) VALUES
 ('$X','00000000-0000-0000-0000-000000000000','authenticated','authenticated','conc_x@t.local',now(),now()),
 ('$Y','00000000-0000-0000-0000-000000000000','authenticated','authenticated','conc_y@t.local',now(),now());
UPDATE public.profiles SET display_name='X',dob='1990-01-01',is_active=true,age_verified=true,is_photo_verified=true,photo_urls=ARRAY['x.jpg'],is_paused=false,is_incognito=false WHERE id='$X';
UPDATE public.profiles SET display_name='Y',dob='1990-01-01',is_active=true,age_verified=true,is_photo_verified=true,photo_urls=ARRAY['y.jpg'],is_paused=false,is_incognito=false WHERE id='$Y';
-- 0045: discoverability requires an approved verification row for the current photo
INSERT INTO public.photo_verifications (user_id,photo_path,slot_index,state,decided_at) VALUES
 ('$X','x.jpg',0,'approved',now()),
 ('$Y','y.jpg',0,'approved',now());
INSERT INTO public.token_claim_history (token,user_id,valid_from,valid_until,approx_lat,approx_lon,range_type) VALUES
 ('$XT','$X', now()-interval '10 s', now()+interval '10 min', 38.9,-76.9,'feet_10'),
 ('$YT','$Y', now()-interval '10 s', now()+interval '10 min', 38.9,-76.9,'feet_10');
-- both forward + reverse sightings, fresh server receipt (primes reciprocity both ways)
INSERT INTO public.sightings (observer_user_id,observed_token,observed_user_id,received_at,rssi,observed_at,observer_lat,observer_lon,range_type) VALUES
 ('$X','$YT','$Y', now(), -60, now(), 38.9,-76.9,'feet_10'),
 ('$Y','$XT','$X', now(), -60, now(), 38.9,-76.9,'feet_10');
SQL

# Fire both correlate calls in overlapping transactions; pg_sleep aligns them
# inside the lock window. Each -c string runs in one implicit transaction.
race() {  # $1=actor uuid, $2=observed token
  $DBX -d postgres -q -c "SELECT set_config('request.jwt.claims','{\"sub\":\"$1\",\"role\":\"authenticated\"}',true); SELECT pg_sleep(0.5); SELECT count(*) FROM public.correlate_encounter('$2',38.9,-76.9,50,15);" >/dev/null 2>&1
}
race "$X" "$YT" &
race "$Y" "$XT" &
wait

N=$($DBX -d postgres -Atc "SELECT count(*) FROM public.encounters WHERE user_a=LEAST('$X'::uuid,'$Y'::uuid) AND user_b=GREATEST('$X'::uuid,'$Y'::uuid);")
if [ "$N" = "1" ]; then
  echo "✅ exactly one encounter under two concurrent confirms (advisory lock holds)"
else
  echo "❌ concurrency produced $N encounters (expected 1 — advisory lock regressed)"; exit 1
fi

echo "== done =="
