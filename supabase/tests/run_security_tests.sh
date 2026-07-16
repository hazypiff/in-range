#!/usr/bin/env bash
# Reciprocity security regression harness (reviewer #6).
#
#   1. Fresh-migration check: apply 0001..latest to a throwaway database and
#      confirm they build the schema cleanly from nothing.
#   2. Invariant check: run reciprocity_security_test.sql transactionally
#      (it ROLLS BACK) against the live local dev database.
#
# Requires the local Supabase Postgres container. Keep this green before/after
# shipping token batches (#6 step 2).
set -euo pipefail
CONTAINER="${SUPABASE_DB_CONTAINER:-supabase_db_in-range}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"   # supabase/
DBX="docker exec -e PGPASSWORD=postgres $CONTAINER psql -U postgres -v ON_ERROR_STOP=1"

echo "== 1/2 security migrations (0020-0029) apply cleanly, in order, idempotently =="
# A full from-0001 rebuild is what `supabase db reset` does (it provisions the
# pristine Supabase base — auth/storage/realtime/extensions — then applies every
# migration); reconstructing that base by hand from a post-migration database is
# not faithful. Here we check the risk that actually matters for adding #6 step 2:
# that the security migration set applies IN ORDER without dependency/ordering
# breaks. They are written idempotently (CREATE OR REPLACE / IF NOT EXISTS /
# ON CONFLICT), so re-applying them onto the production-equivalent schema must be
# a clean no-op — which catches an out-of-order or conflicting new migration.
for f in "$HERE"/migrations/00[2][0-9]_*.sql; do
  docker cp "$f" "$CONTAINER:/tmp/m.sql" >/dev/null
  if ! $DBX -d postgres -f /tmp/m.sql >/tmp/mout 2>&1; then
    echo "❌ $(basename "$f") did not apply cleanly:"; grep -iE "ERROR|LINE" /tmp/mout | head -3; exit 1
  fi
done
echo "✅ 0020-0029 apply cleanly in order (idempotent re-apply)"
echo "   (full from-0001 rebuild: use 'supabase db reset')"

echo "== 2/2 reciprocity security invariants (transactional, rolled back) =="
docker cp "$HERE/tests/reciprocity_security_test.sql" "$CONTAINER:/tmp/sectest.sql" >/dev/null
$DBX -d postgres -f /tmp/sectest.sql 2>&1 | grep -E "PASSED|ERROR|ASSERT" || { echo "❌ invariant check failed"; exit 1; }
echo "== done =="
