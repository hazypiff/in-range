# In Range — Code Hardening TODO

Generated 2026-07-09 after deep audit of `1c80498` (post go-live push).
All items are code-fixable in-repo (excludes operational: KGP upstream, FCM E2E, prod ops).

## STATUS

| ID | Sev | Title | Status |
|----|-----|-------|--------|
| C1 | Critical | Hardcoded HMAC fallback secrets | **FIXED** |
| C2 | Critical | send-push legacy FCM API | **FIXED** (HTTP v1) |
| H1 | High | Fake auto-match + canned opener | **FIXED** |
| H2 | High | Dead ChatSyncService | **FIXED** (deleted) |
| M1 | Medium | swipe_feed 1s timer rebuild | **FIXED** (ValueNotifier) |
| M2 | Medium | photo_urls stays null → invisible | **FIXED** (syncProfile sends paths) |
| M3 | Medium | Expired match crash | Deferred (needs UI state work) |
| L1 | Low | Beacon state not reset on sign-out | **FIXED** |
| L2 | Low | No network timeout | Dropped (supabase_flutter API doesn't support fetchTimeout cleanly) |
| L3 | Low | Empty catch swallows errors | Deferred (non-critical) |

## Critical

### C1. Hardcoded HMAC fallback secrets in client binary
- **Files:** `lib/core/config/app_config.dart:19-23`, `lib/features/beacon/beacon_provider.dart:9-15`
- **Problem:** `hmacSecret` / `userIdSecret` fall back to `'inrange-hmac-fallback'` / `'inrange-user-id-fallback'` when env unset. These strings ship in every APK → anyone can forge `claim_token` payloads or `user_hash`.
- **Fix:** Remove string fallback. Return empty string when env missing; `BeaconService` refuses to advertise when secret empty (safety, not silent fallback).

### C2. send-push Edge Function uses deprecated legacy FCM API
- **File:** `supabase/functions/send-push/index.ts:23,115-133`
- **Problem:** Legacy `fcm.googleapis.com/fcm/send` was shut down by Google (2024). Every send with a real key returns 404 → rows stuck `failed`.
- **Fix:** Switch to HTTP v1: `oauth2/v4/token` + `v1/projects/{id}/messages:send` using `FCM_SERVICE_ACCOUNT_JSON`.

## High

### H1. Auto-match creates fake matches + canned opener when cloud is real
- **File:** `lib/features/matches/match_store.dart:166,283-296,404-417`
- **Problem:** `autoMatchOnLike = true` (always) + `_upsertMatch` hardcodes bio `'I love coffee shops...'`, age `28`, interests `['Music','Travel']`, opener `'I saw you were near...'`. When server says `matched != true`, local fallback still creates a fake match visible to the user.
- **Fix:** Gate `autoMatchOnLike` by `!AppConfig.hasRealSupabase`. Remove canned opener message from `_upsertMatch` (empty messages on real match).

### H2. Dead code: ChatSyncService never imported
- **File:** `lib/shared/services/chat_sync_service.dart`
- **Problem:** Zero imports across the codebase. Cloud chat RPCs (`send_message`, `mark_messages_read`, realtime) are never called by the UI.
- **Fix:** Delete the file (rely on `EncountersApi` directly when wiring cloud chat later).

## Medium

### M1. swipe_feed 1s Timer.periodic causes full rebuilds
- **File:** `lib/features/encounters/swipe_feed.dart:23,30`
- **Problem:** 1s `Timer.periodic` + `setState` on `ConsumerStatefulWidget` rebuilds the entire swipe stack every second — battery/CPU drain on a foreground screen.
- **Fix:** Replace with a `ValueNotifier<int>` (seconds remaining) listened to only by the expiring card, or scope `setState` to only the single expiring card.

### M2. Profile photos uploaded but `photo_urls` stays null on server → user invisible
- **File:** `lib/shared/services/profile_sync_service.dart:38,57-92`
- **Problem:** `syncProfile` sends `p_photo_urls: null` (line 38). `uploadPhotos` uploads to storage + queues verification but never re-runs `syncProfile`. With migration 0013's strict filter (requires non-empty `photo_urls`), this user is invisible in everyone's Encounters/Locals feed even after uploading.
- **Fix:** After `uploadPhotos` completes, call `syncProfile` again with the uploaded paths (or pass paths in the same RPC). Wire `uploadPhotos` return into `syncProfile`.

### M3. MessagesScreen / MatchProfileScreen crash on expired match
- **Files:** `lib/features/chat/messages_screen.dart:150-157`, `lib/features/matches/match_profile_screen.dart:16-23`
- **Problem:** `firstWhere(orElse: MatchRecord(...))` returns a ghost match when the real one expired (24h no-reply prune). User lands on empty chat with a no-op Send button.
- **Fix:** Show "This match expired" state and pop the screen.

## Low

### L1. BeaconController state not reset on sign-out
- **File:** `lib/core/session/app_session.dart`
- **Problem:** `signOut` clears prefs but not `beaconControllerProvider` state. A re-signed-in user sees stale "Beacon ON" while BLE is off.
- **Fix:** `ref.invalidate(beaconControllerProvider)` in `signOut`.

### L2. No network timeout on Supabase calls
- **File:** `lib/core/network/supabase_client.dart`
- **Problem:** Default client has no `fetchTimeout`. Stale network hangs auth silently.
- **Fix:** Set `SupabaseClientOptions(fetchTimeout: Duration(seconds: 15))` in `InRangeSupabase.init`.

### L3. Empty catch swallows profile photo upload failures
- **File:** `lib/features/settings/settings_screen.dart:171-173`
- **Problem:** `deleteLocationHistory()` in `catch (_) {}` swallows errors silently.
- **Fix:** Surface via snackbar (low priority — location history delete is non-critical).
