# Supabase go-live guide (In Range)

**Goal:** Create a project, run migrations + seed, deploy edge functions, paste URL/anon key + OAuth IDs — app goes live. No further product code required.

---

## 1. Create the project

1. Open https://supabase.com → New project  
2. Name: `in-range` · region closest to users · save DB password  
3. Wait until **Healthy**

## 2. Enable extensions

Dashboard → **Database → Extensions**:

- `postgis` (required)
- `pgcrypto` (usually on)
- `pg_cron` (optional; for maintenance schedule)

## 3. Run migrations (in order)

Dashboard → **SQL Editor** → paste & Run each file:

| # | File |
|---|------|
| 1 | `supabase/migrations/0001_init.sql` |
| 2 | `supabase/migrations/0002_location_pings_realtime_storage.sql` |
| 3 | `supabase/migrations/0003_correlation_fixes.sql` |
| 4 | `supabase/migrations/0004_encounter_reveal_delay.sql` |
| 5 | `supabase/migrations/0005_safety_monetization_fcm.sql` |
| 6 | `supabase/migrations/0006_photo_storage_chat_media.sql` |
| 7 | `supabase/migrations/0007_swipe_match_chat_rpcs.sql` |
| 8 | `supabase/migrations/0008_miles_correlation.sql` |
| 9 | `supabase/migrations/0009_auth_profile_account.sql` |
| 10 | `supabase/migrations/0010_realtime_grants_cleanup.sql` |
| 11 | `supabase/migrations/0011_record_sighting_single_sig.sql` |
| 12 | `supabase/migrations/0012_correlate_grace_dedupe.sql` |
| 13 | `supabase/migrations/0013_photo_verification_gating.sql` |
| 14 | `supabase/migrations/0014_restrict_profile_read.sql` |
| 15 | `supabase/migrations/0015_audit_remaining_fixes.sql` |

Or CLI:

```bash
cd /home/hazypiff/in-range
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
```

## 4. Seed (optional lab data)

```bash
# SQL Editor: run
supabase/seed/seed_test_data.sql
```

Test users (password `TestPass123!`):

- alice@inrange.test / bob@inrange.test / cara@inrange.test / dan@inrange.test

## 5. App `.env`

```env
SUPABASE_URL=https://xxxxxxxx.supabase.co
SUPABASE_PUBLISHABLE_KEY=eyJhbGciOi...anon...
INRANGE_USER_ID_SECRET=<openssl rand -hex 32>
INRANGE_HMAC_SECRET=<openssl rand -hex 32>
ENCOUNTER_REVEAL_DELAY_HOURS=0
INRANGE_ENABLE_FGS=false
AUTH_REDIRECT_URL=io.inrange.app://login-callback
```

Generate secrets:

```bash
openssl rand -hex 32
openssl rand -hex 32
```

Keep HMAC secret identical on every client for the same environment.

## 6. Auth providers

**Authentication → Providers**

| Provider | Action |
|----------|--------|
| Email | Enable; for MVP you can disable confirmations |
| Phone | Add Twilio/MessageBird under Auth settings |
| Google | Google Cloud OAuth client → Client ID/secret |
| Apple | Apple Services ID → paste into Supabase |
| Anonymous | Enable for guest cloud sessions / lab |

**URL config:** Site URL + redirect `io.inrange.app://login-callback`

## 7. Storage

Migrations create buckets:

- `profile_photos` (public read, user upload own folder)
- `chat_media` (private, match participants)
- `verified_photos` (service_role write)

Confirm under **Storage**. Policies are in `0002` + `0006`.

## 8. Edge Functions

```bash
supabase secrets set FCM_SERVER_KEY=YOUR_FCM_SERVER_KEY
supabase secrets set STUB_AUTO_APPROVE=true   # lab: auto photo verify
# Production: STUB_AUTO_APPROVE=false — unverified profiles are hidden from
# Encounters + Locals until decide_photo_verification / stub approve.

supabase functions deploy send-push
supabase functions deploy miles-correlate
supabase functions deploy photo-review
supabase functions deploy maintenance
```

**Cron (Dashboard → Edge Functions → Schedules):**

| Function | Schedule |
|----------|----------|
| `maintenance` | `*/15 * * * *` (or DB `pg_cron` → `run_maintenance`) |
| `send-push` | `* * * * *` |
| `photo-review` | `*/2 * * * *` |
| `miles-correlate` | `*/10 * * * *` |

Migration **0015** also tries to schedule `cron.schedule('in-range-maintenance', '*/15 * * * *', …)` when `pg_cron` is enabled.

Without `FCM_SERVER_KEY`, `send-push` dry-runs and marks rows `skipped` / `dry_run_no_fcm_key`.

## 9. Firebase (push — when ready)

1. Create Firebase project · Android app package `com.example.in_range` (or your id)  
2. Download `google-services.json` → `android/app/`  
3. Add `firebase_core` + `firebase_messaging` to pubspec  
4. Call `PushService.bindFirebaseToken` from `onTokenRefresh`  
5. Set `FCM_SERVER_KEY` secret for Edge `send-push`

Until then, optional: `FCM_MOCK_TOKEN=any-string` exercises `register_push_token`.

## 10. Smoke tests

```sql
select public.get_my_encounters(10, 0, 0);
select public.run_maintenance();
```

App logs after rebuild should show `supabase=true` / `Cloud connected`.

## 11. Product RPCs (client already calls these)

| RPC | Purpose |
|-----|---------|
| `claim_token` | BLE advertise claim |
| `record_sighting` | BLE observe + correlate |
| `record_location_ping` | Miles GPS ping + correlate |
| `get_my_encounters` | Encounters feed |
| `get_locals_feed` | Locals tab |
| `swipe_encounter` | Like/pass + match |
| `get_my_matches` / `send_message` | Chat |
| `upsert_my_profile` / `submit_photo_for_verification` | Profile |
| `register_push_token` | FCM |
| `block_user` / `report_user` | Safety |
| `set_account_paused` / `request_account_deletion` | Account |

## 12. Pricing / IAP (structure only)

Tables `subscriptions` and `boosts` are ready. Wire App Store / Play Billing → service_role insert. Pricing TBD.

---

**When keys are in:** rebuild APK, reinstall both phones, sign in (or guest anonymous), turn Beacon ON — server correlation + local BLE both run.
