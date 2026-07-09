# Go-live checklist — In Range

Everything offline is implemented. Complete only these credential/config steps:

## Cloud project

- [ ] Create Supabase project
- [ ] Enable PostGIS
- [ ] Run migrations `0001` → `0010` in order
- [ ] (Optional) Run `supabase/seed/seed_test_data.sql`
- [ ] Copy Project URL + anon key into `.env`

## Auth

- [ ] Enable Email (and optionally disable confirm for MVP)
- [ ] Enable Anonymous (lab / guest)
- [ ] Phone: Twilio (or MessageBird) credentials
- [ ] Google OAuth client IDs in Supabase
- [ ] Apple Services ID in Supabase
- [ ] Redirect URL: `io.inrange.app://login-callback`

## Storage

- [ ] Confirm buckets: `profile_photos`, `chat_media`, `verified_photos`
- [ ] (Optional) Set `STUB_AUTO_APPROVE=false` and moderate via `v_pending_photo_reviews`

## Edge + push

- [ ] Deploy functions: `send-push`, `miles-correlate`, `photo-review`, `maintenance`
- [ ] Schedule crons (see SUPABASE_SETUP.md)
- [ ] Set `FCM_SERVER_KEY` when Firebase is ready
- [ ] Add `google-services.json` + firebase_messaging when ready

## App secrets

- [ ] `INRANGE_HMAC_SECRET` / `INRANGE_USER_ID_SECRET` (prod random hex)
- [ ] `ENCOUNTER_REVEAL_DELAY_HOURS=4` for production
- [ ] Rebuild & reinstall

## Pricing (later — schema ready)

- [ ] Decide subscription / boost product IDs and prices
- [ ] Wire IAP receipt validation → `subscriptions` / `boosts` tables

## Done when

App shows **Cloud connected**, Locals/Encounters pull server data, matches chat sync, and push outbox drains (or dry-runs until FCM key).
