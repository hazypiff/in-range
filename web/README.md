# Public compliance pages

Static, dependency-free pages that must be reachable **without an account and
without the app installed**. Both are hard requirements, not nice-to-haves.

| Page | Required by | Where the URL goes |
|---|---|---|
| `report.html` | **TAKE IT DOWN Act** (enforceable 2026-05-19, $53,088/violation) | In-app link, both store listings, privacy policy |
| `delete-account.html` | **Google Play** account-deletion policy | Play Console data-safety form |

Apple requires in-app deletion only; **Play requires the web URL as well**. The
asymmetry is easy to miss and it is a certain rejection.

## Deploy

Any static host. Cloudflare Pages is what the other projects here use.

1. In `report.html`, fill in `CONFIG.url` and `CONFIG.publishableKey`.
   **Publishable key only — never the service role key.** It is the same key the
   mobile client ships, and `submit_ncii_report()` is granted to `anon`
   precisely so this page can work unauthenticated.
2. In `delete-account.html`, replace `privacy@inrange.app` if the support
   address differs.
3. Host both at stable URLs and paste them where the table above says.

## The half these pages don't cover

`report.html` starts a **48-hour statutory clock** on submit. Nothing here
watches it. Someone has to:

- poll `v_ncii_sla` (service role) for `hours_remaining` / `breached`
- verify the claim
- call `ncii_resolve(id, 'removed'|'rejected'|'duplicate', who, note)`

`ncii_resolve` with `'removed'` fans out across `media_hashes` and queues every
identical copy for deletion — but only for uploads that were hashed, which
means uploads from a client build that includes `MediaHashService`.

**Named owner required.** A 48-hour clock with nobody watching it is worse than
no intake form, because the report exists and the breach is documented.

## Keep in sync

`delete-account.html` states retention periods. They must match the code:

- 30-day account purge — `0035`, `app_settings.deletion_grace_days`
- 24h location, 48h sightings — `0002`, `cleanup_ephemeral_data()`
- legal-hold carve-out — `0037`, `legal_holds`

If those change, change the page. A retention claim that does not match
behaviour is the exact "you said X, you did Y" shape the FTC charged in
*Match/OkCupid*.
