#!/usr/bin/env bash
# Helper after Supabase project exists.
# Usage:
#   export SUPABASE_PROJECT_REF=xxxx
#   export SUPABASE_DB_PASSWORD=...
#   ./scripts/go-live.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -z "${SUPABASE_PROJECT_REF:-}" ]]; then
  echo "Set SUPABASE_PROJECT_REF first (Dashboard → Project Settings → General)."
  exit 1
fi

echo "==> Linking project $SUPABASE_PROJECT_REF"
supabase link --project-ref "$SUPABASE_PROJECT_REF"

echo "==> Pushing migrations 0001–0010"
supabase db push

echo "==> Deploying edge functions"
supabase functions deploy send-push
supabase functions deploy miles-correlate
supabase functions deploy photo-review
supabase functions deploy maintenance

echo "==> Optional secrets (skip if not ready)"
echo "  supabase secrets set FCM_SERVER_KEY=..."
echo "  supabase secrets set STUB_AUTO_APPROVE=true"

echo "==> Seed (optional)"
echo "  Run supabase/seed/seed_test_data.sql in SQL Editor"

echo ""
echo "Next: put SUPABASE_URL + SUPABASE_PUBLISHABLE_KEY in .env and rebuild."
echo "  flutter build apk"
echo "Done."
