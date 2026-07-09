# In Range — Full Stack Audit Report

**Date:** 2026-07-09
**Repo:** https://github.com/hazypiff/in-range (private)
**Branch:** main
**Base commit:** 9d26171 (prior hardening)
**Build:** flutter analyze (1 info lint), flutter test (1/1), flutter build apk --debug (pass)

---

## Executive Summary

4 specialized audit agents + direct code review covered security, product outline compliance, database migration health, BLE/GPS pipeline correctness, edge functions, and client architecture gaps. **14 issues fixed** across 12 files + 2 new migrations (0014). **7 findings remain** — 2 product gaps (age gate placement, cloud chat), 1 database dead code (migration 0003), 1 cron scheduling, and 3 minor items.

---

## A. Security — PASS with fixes

**Secrets:** Clean — no real keys in git history or tracked files. `.gitignore` covers all required patterns.

**Fixes applied:**

| ID | Severity | Issue | Fix |
|----|----------|-------|-----|
| S1 | High | `record_location_ping` + `miles-correlate` leaked lat/lon as neighborhood fallback (`Area 34.05, -118.24` → ~1.1km precision) | Fallback → `'Nearby'` |
| S2 | High | Profile SELECT policy granted all columns (email_hint, phone_hint, dob, gender, preferences, interests) to any authenticated user pre-match | Migration 0014: REVOKE sensitive columns from authenticated |
| S3 | High | send-push delivered notifications to blocked pairs | Block check added to drain loop via `is_blocked_pair` RPC |
| S4 | Medium | `batch_correlate_recent_pings` missing paused/deleted/incognito profile filters | Added EXISTS subquery on profiles with safety gates |
| S5 | Medium | `nearby_location_pings` RPC (deprecated, unused) still executable without safety filters | Marked deprecated via COMMENT |

**Remaining concerns:**
- `is_blocked_pair` RPC allows any authenticated user to probe block relationships between arbitrary pairs (M, privacy leak)
- Profile photo storage SELECT is `TO public` — photos readable by URL if known (acceptable for photo-first app)
- Edge function error messages use raw `String(e)` — could leak stack traces (L)

---

## B. Build & CI — PASS

| Command | Result |
|---------|--------|
| `flutter analyze` | 1 info lint (use_build_context_synchronously, pre-existing) |
| `flutter test` | 1/1 pass |
| `flutter build apk --debug` | pass (KGP warnings from flutter_ble_peripheral, upstream) |

**Fixes applied:**
- `.env` was the sole asset → added `.env.example` + `mergeWith` fallback so devs without `.env` can build
- Android 12+ BLE permissions (`BLUETOOTH_SCAN`, `BLUETOOTH_ADVERTISE`, `BLUETOOTH_CONNECT`) added to runtime permission request (manifest already declared them)

---

## C. Product Outline Compliance

| Area | Status | Notes |
|------|--------|-------|
| C1 Onboarding/Auth | **Partial** | All auth flows wired (email/phone/Google/Apple/guest). Age gate at profile save only — not at sign-up. |
| C2 Profile | **Implemented** | 6 photos max, bio ≤500, photo+neighborhood pre-match, verified gate (0013), photo verification state machine |
| C3 Beacon/Ranges | **Implemented** | All 10 range values (feet_10/20/30, miles_1/5/10/25/50/100/200), 24h feet expiry, FGS config, BLE+GSP |
| C4 Encounters/Matching | **Implemented** | Reveal delay configurable, unlimited swipes (no cap), mutual match, hybrid offline/cloud |
| C5 Chat | **Partial** | Local chat works (text + photo). Cloud realtime not wired — `send_message` RPC exists but never called from ChatThreadScreen; no Supabase channel/subscription. |
| C6 Monetization | **Implemented** | subscriptions/boosts/ad_impressions tables + UI shells (ad banner, subscriber toggle, boost simulation). Pricing TBD. |
| C7 Safety | **Implemented** | Block/report/pause/delete/incognito. All feeds/RPCs exclude blocked pairs. SafetyStore client-side. |
| C8 Hybrid Offline/Cloud | **Implemented** | Every feature gates on `hasRealSupabase`. Local fallback in Beacon/Locals/Encounters/Match/Profile/Auth. |

---

## D. Photo Verification Gating — PASS

**Post-0013 verification**: Confirmed strictly enforced.
- `get_my_encounters` (0013): requires `is_photo_verified = TRUE`, no dead CASE branch
- `get_locals_feed` (0013): same
- `get_my_matches` (0007): post-match unlock, intentionally unrestricted
- Client belt-and-suspenders: encounters_repository + locals_service filter residual unverified rows
- `syncProfile` now sends `session.photoPaths` (not null) — previously invisible-user bug fixed
- `STUB_AUTO_APPROVE=true` auto-verifies lab users; `STUB_AUTO_APPROVE=false` keeps users invisible until manual approval

---

## E. Proximity Pipeline

### E1. BLE / Feet — PASS

- Advertise: 16-byte raw correlation ID (mfg 0xFFFF), not raw ephemeral token. Hex used for logging only.
- `claim_token`: correlation-id hex → server. UTC + ≥20 min floor. Claim BEFORE advertise (correct ordering).
- `record_sighting`: single signature (post-0011) — no PostgREST overload risk.
- `correlate_encounter`: active/grace window, distance radius, pair dedupe, encounter create/refresh.
- Feet 24h expiry: function exists (`expire_feet_encounters`), called by `run_maintenance`, but **pg_cron schedule is commented out** — needs cron deployment.
- Local SQLite: works fully offline (local_encounter_store.dart).

### E2. Miles / GPS — PASS

- `record_location_ping`: inserts geography + triggers `correlate_miles_encounters`.
- `range_radius_meters`/`range_time_window_minutes`: all 10 enum ranges covered.
- Incognito/paused/deleted/blocked excluded in correlation.
- `preferences_compatible` function + `_pref_matches` helper correct.
- `batch_correlate_recent_pings` (15-min cron catch-up) now has profile safety filters.

### E3. Hybrid Feeds — PASS

- Server when `hasRealSupabase` + session; local fallback when offline.
- No hard crash on RPC failure — returns empty list + logs.
- Offline banner: shows for `offlineLocal`/`cloudUnreachable`, hidden for `cloudOnline`.

---

## F. Database & Migrations

**13 migrations (0001-0013) + new 0014**: All ordered, self-consistent.

**Critical finding:**
- **F1**: Migration 0003 `record_sighting` CASE references nonexistent enum values `feet_100`/`feet_500`. Dead code after 0008 replaces the path with helper functions. If migrations were applied to 0003 and then `record_sighting` was called before 0008, the CASE would silently hit the ELSE branch with wrong radius. New migration to add the enum values recommended.

**New migration 0014**: Restricts profile SELECT policy — REVOKE on email_hint, phone_hint, dob, gender, sexual_preference, interests, display_name, bio from authenticated role. Deprecates `nearby_location_pings` RPC.

---

## G. Edge Functions

| Function | Status |
|----------|--------|
| send-push | Updated: HTTP v1 (OAuth2 JWT to `v1/projects/{id}/messages:send`), block check, dry-run safe |
| miles-correlate | PASS — neighborhood leak fixed; synthetic-ping fallback works; Deno deployable |
| photo-review | PASS — `stub_auto_approve_photo` → `decide_photo_verification` → `is_photo_verified = TRUE` chain correct |
| maintenance | PASS — thin passthrough to `run_maintenance()` RPC |

---

## H. Client Architecture — PASS with notes

- **Permissions:** Android 10-14 coverage now complete (BLUETOOTH_SCAN/ADVERTISE/CONNECT runtime requests added)
- **Session:** local guest → cloud anonymous → full auth — all paths work
- **AuthService:** email/phone/OAuth/anonymous — all wired with offline gates
- **Profile sync:** `uploadPhotos` runs before `syncProfile` — ordering correct
- **Match store:** `autoMatchOnLike` gated by `!hasRealSupabase`
- **Chat:** local-only (no Supabase realtime after ChatSyncService deletion)
- **Timer/subscription cleanup:** all verified — no leaks
- **Timezone:** match expiry normalized to UTC

---

## I. Dual-Device Scenarios — Logic Audit

All 7 scenarios walk through correctly with expected table/RPC/UI states. Key verification points:

1. **Two guests, BLE feet_10, mutual RSSI** → both claim token → advertise → scan → flush → correlate → encounters ✓
2. **One user offline** → local-only continues; no crash ✓
3. **Swipe like both** → mutual match + chat ✓ (chat is local only)
4. **Miles range + GPS pings** → pings inserted → batch correlate (15-min cadence) → locals feed ✓
5. **Unverified profile** → absent from feeds (0013 gate) ✓
6. **Block** → excluded from all feeds/correlation/messages ✓
7. **Pause** → hidden ✓

---

## Top 6 Beta Next Steps

1. **Enable pg_cron + schedule run_maintenance** every 15 min (feet expiry, batch correlate, cleanup)
2. **Add age gate at sign-up time** (prevent underage cloud account registration)
3. **Wire cloud chat** — call `send_message` RPC from ChatThreadScreen + Supabase realtime subscription
4. **Deploy send-push with real FCM_SERVICE_ACCOUNT_JSON** + verify E2E push delivery
5. **Apply migration 0014** (profile SELECT restriction) to staging + production
6. **Track flutter_ble_peripheral KGP migration** upstream (before Flutter breaking release)