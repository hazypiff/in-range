#!/usr/bin/env bash
# Deploy web/ (index, report, delete-account pages) to Cloudflare Pages.
#
# Auth: `npx wrangler login` once (browser OAuth), or export
# CLOUDFLARE_API_TOKEN with Pages Write on the account.
#
# GOTCHA (from the louddelivery deploy): wrangler pages deploy must run from
# INSIDE the directory being deployed or functions/ would be silently skipped.
# No functions here (report.html posts straight to the Supabase Edge
# function), but keep the pattern anyway.
#
# report.html/delete-account.html are gitignored: the deployable copies carry
# the real Supabase project ref (filled from .env). Re-fill after a clone.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="${1:-inrange-life}"

if grep -q "YOUR-PROJECT-REF" "$ROOT/web/report.html"; then
  echo "ERROR: web/report.html still has placeholder config — fill CONFIG" >&2
  echo "from .env (SUPABASE_URL + SUPABASE_PUBLISHABLE_KEY) first." >&2
  exit 1
fi

cd "$ROOT/web"
npx wrangler pages deploy . --project-name "$PROJECT" --branch main --commit-dirty=true
echo
echo "Live at https://$PROJECT.pages.dev — attach inrange.life in the"
echo "Cloudflare dashboard: Pages → $PROJECT → Custom domains."
