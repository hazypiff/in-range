#!/usr/bin/env bash
# rehearse_migrations.sh — apply the full 0001→00NN chain to a throwaway
# database and assert the three re-declared functions still carry every
# accumulated clause. Run before any `supabase db push` that includes a
# function re-declaration.
#
# Requires: Docker with the local Supabase Postgres container running, or a
# local postgres server with the same extensions (pgcrypto, pg_cron, pg_net).
# The script creates and drops its own database; it does not touch dev/prod.

set -euo pipefail

DB_NAME="inrange_rehearsal_$(date +%s)"

# Prefer a local psql; fall back to the Supabase container, which is how the
# dev box is actually set up — there is no psql binary on the host there, so a
# hardcoded `psql` meant this script could never run on the machine it was
# written for.
if command -v psql >/dev/null 2>&1; then
  PSQL="psql -h localhost -U postgres -d"
else
  CONTAINER="${SUPABASE_DB_CONTAINER:-supabase_db_in-range}"
  if ! docker exec "$CONTAINER" true 2>/dev/null; then
    printf 'FAIL: no psql on PATH and container "%s" is not running.\n' "$CONTAINER" >&2
    printf '      Start the local Supabase stack, or set SUPABASE_DB_CONTAINER.\n' >&2
    exit 1
  fi
  PSQL="docker exec -i $CONTAINER psql -U postgres -d"
fi

say() { printf '%s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

say "Creating rehearsal database: $DB_NAME"
$PSQL postgres -c "CREATE DATABASE $DB_NAME;"

cleanup() {
  say "Dropping rehearsal database: $DB_NAME"
  $PSQL postgres -c "DROP DATABASE IF EXISTS $DB_NAME;" >/dev/null
}
trap cleanup EXIT

say "Bootstrapping Supabase platform stubs"
$PSQL "$DB_NAME" <<'SQL'
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
-- pg_cron can only be installed into the database named in cron.database_name
-- (normally 'postgres'). The rehearsal DB is throwaway, so skipping it is
-- expected and does not affect the migration chain being tested.
DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron skipped: only installable in the cron.database_name database';
END $$;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;
CREATE SCHEMA IF NOT EXISTS auth;
-- Columns chosen to match every auth.users field the migrations and tests
-- actually reference (NEW.raw_user_meta_data / NEW.phone / NEW.updated_at are
-- read by handle_new_user; u.created_at / u.last_sign_in_at by the reporting
-- views). Without raw_user_meta_data the handle_new_user trigger raises
-- 'record "new" has no field ...' and nothing that inserts a user can run —
-- which is why security_regression.sql could not be rehearsed before
-- 2026-07-25.
CREATE TABLE auth.users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  instance_id UUID,
  aud TEXT DEFAULT 'authenticated',
  role TEXT DEFAULT 'authenticated',
  email TEXT,
  phone TEXT,
  raw_user_meta_data JSONB DEFAULT '{}'::JSONB,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  last_sign_in_at TIMESTAMPTZ
);
CREATE OR REPLACE FUNCTION auth.uid() RETURNS UUID LANGUAGE sql STABLE AS $$
  SELECT NULLIF(current_setting('request.jwt.claims', true)::jsonb->>'sub', '')::UUID;
$$;
CREATE OR REPLACE FUNCTION auth.role() RETURNS TEXT LANGUAGE sql STABLE AS $$
  SELECT current_setting('request.jwt.claims', true)::jsonb->>'role';
$$;
CREATE OR REPLACE FUNCTION auth.jwt() RETURNS JSONB LANGUAGE sql STABLE AS $$
  SELECT current_setting('request.jwt.claims', true)::jsonb;
$$;
CREATE SCHEMA IF NOT EXISTS storage;
CREATE TABLE storage.buckets (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  public BOOLEAN NOT NULL DEFAULT false,
  file_size_limit BIGINT,
  allowed_mime_types TEXT[]
);
CREATE TABLE storage.objects (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bucket_id TEXT REFERENCES storage.buckets(id),
  name TEXT NOT NULL,
  owner UUID,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
CREATE OR REPLACE FUNCTION storage.foldername(name TEXT) RETURNS TEXT[] LANGUAGE sql IMMUTABLE AS $$
  SELECT string_to_array(name, '/');
$$;
CREATE SCHEMA IF NOT EXISTS vault;
CREATE TABLE vault.decrypted_secrets (
  name TEXT PRIMARY KEY,
  decrypted_secret TEXT
);
-- Empty, NOT "FOR ALL TABLES": that is how Supabase actually creates it, and
-- 0019 does ALTER PUBLICATION ... DROP TABLE, which Postgres rejects outright
-- on a FOR ALL TABLES publication. With the wrong form the rehearsal dies at
-- migration 19 of 59.
CREATE PUBLICATION supabase_realtime;
SQL

say "Applying migrations"
for f in supabase/migrations/*.sql; do
  say "  $f"
  # stdin, not -f: under `docker exec` the path would have to exist INSIDE the
  # container, so -f silently breaks the container fallback.
  $PSQL "$DB_NAME" -v ON_ERROR_STOP=1 < "$f" >/dev/null
done

say "Asserting accumulated clauses"
$PSQL "$DB_NAME" -v ON_ERROR_STOP=1 <<'SQL'
DO $$
DECLARE
  v_scrub TEXT;
  v_export TEXT;
  v_cleanup TEXT;
BEGIN
  SELECT pg_get_functiondef('public.scrub_account_pii(uuid)'::regprocedure) INTO v_scrub;
  SELECT pg_get_functiondef('public.export_my_data()'::regprocedure) INTO v_export;
  SELECT pg_get_functiondef('public.cleanup_ephemeral_data()'::regprocedure) INTO v_cleanup;

  -- scrub_account_pii must delete every sensitive table.
  ASSERT v_scrub LIKE '%DELETE FROM public.location_pings%', 'scrub missing location_pings';
  ASSERT v_scrub LIKE '%DELETE FROM public.token_claims%', 'scrub missing token_claims';
  ASSERT v_scrub LIKE '%DELETE FROM public.token_claim_history%', 'scrub missing token_claim_history';
  ASSERT v_scrub LIKE '%DELETE FROM public.sightings%', 'scrub missing sightings';
  ASSERT v_scrub LIKE '%DELETE FROM public.beacon_token_batch%', 'scrub missing beacon_token_batch';
  ASSERT v_scrub LIKE '%DELETE FROM public.device_attestations%', 'scrub missing device_attestations';
  ASSERT v_scrub LIKE '%DELETE FROM public.device_push_tokens%', 'scrub missing device_push_tokens';
  ASSERT v_scrub LIKE '%DELETE FROM public.notification_outbox%', 'scrub missing notification_outbox';
  ASSERT v_scrub LIKE '%DELETE FROM public.photo_verifications%', 'scrub missing photo_verifications';
  ASSERT v_scrub LIKE '%DELETE FROM public.rssi_samples%', 'scrub missing rssi_samples';
  ASSERT v_scrub LIKE '%DELETE FROM public.venue_anchors%', 'scrub missing venue_anchors';
  ASSERT v_scrub LIKE '%DELETE FROM public.proximity_wake_requests%', 'scrub missing proximity_wake_requests';

  -- export_my_data must include every user-facing key.
  ASSERT v_export LIKE '%''rssi_samples''%', 'export missing rssi_samples';
  ASSERT v_export LIKE '%''venue_anchors''%', 'export missing venue_anchors';
  ASSERT v_export LIKE '%''proximity_wake_requests''%', 'export missing proximity_wake_requests';

  -- cleanup_ephemeral_data must sweep every ephemeral table.
  ASSERT v_cleanup LIKE '%DELETE FROM public.location_pings%', 'cleanup missing location_pings';
  ASSERT v_cleanup LIKE '%DELETE FROM public.sightings%', 'cleanup missing sightings';
  ASSERT v_cleanup LIKE '%DELETE FROM public.token_claim_history%', 'cleanup missing token_claim_history';
  ASSERT v_cleanup LIKE '%DELETE FROM public.rssi_samples%', 'cleanup missing rssi_samples';
  ASSERT v_cleanup LIKE '%DELETE FROM public.rssi_batch_rate%', 'cleanup missing rssi_batch_rate';
  ASSERT v_cleanup LIKE '%DELETE FROM public.venue_anchors%', 'cleanup missing venue_anchors';
  ASSERT v_cleanup LIKE '%DELETE FROM public.proximity_wake_requests%', 'cleanup missing proximity_wake_requests';
  ASSERT v_cleanup LIKE '%DELETE FROM public.notification_outbox%', 'cleanup missing notification_outbox';
END $$;
SQL

say "PASS: migration chain 0001→latest rehearsed successfully"
