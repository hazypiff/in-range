# In Range — Ultimate Audit, Remediation, and Verification Report

Audit window: 2026-07-11 through 2026-07-12
Baseline: `b00fc7a` on `main`
Scope audited: 44 Dart files, 19 SQL migrations after remediation, 4 Edge Functions, Android build/deploy configuration, scripts, docs, tests, tracked history, and the generated debug APK.
Toolchain: Flutter 3.44.5, Dart 3.12.2, Supabase CLI 2.109.1, Deno 2.9.2, PostgreSQL 15/PostGIS.

## Overall verdict

**BLOCKED** for an external/public beta.

The code-level Critical findings discovered at baseline were remediated and the local stack now fails closed. A clean database replay, executable authorization tests, Dart analysis, Flutter tests, Edge Function type checks, and a three-ABI APK build all pass.

The release remains blocked by four items that cannot be truthfully certified from this repository alone:

1. The client still contains a shared beacon HMAC/user-hash secret when configured. APK extraction means that secret is an obfuscation input, not a durable trust anchor (`lib/core/config/app_config.dart:52`, `lib/features/beacon/ephemeral_token_generator.dart:87`). Server-side claim uniqueness, short validity, GPS, RSSI, age/photo gates, and rate limits now reduce the blast radius, but Play Integrity/device registration or server-issued beacon material is still required for strong anti-relay/anti-forgery claims.
2. There is no real FCM client token source yet (`lib/core/notifications/push_service.dart:11-47`). The server sender is hardened, but a real Firebase project, `google-services.json`, `firebase_messaging`, token refresh wiring, and live delivery tests are absent.
3. Photo review is intentionally a format-only stub that routes remote deployments to manual review (`supabase/functions/photo-review/index.ts:7-9`, `:108-110`, `:283`). A real moderation/liveness provider or staffed review operation is not present.
4. Foreground/background BLE behavior, Doze/App Standby, process death, reboot, permission recovery, and four-device Galaxy S9 interoperability have not been exercised on physical devices. The FGS now has a real 30-second heartbeat, but it does not provide a verified reboot receiver or prove OEM survival (`lib/main.dart:78-123`).

The account-deletion RPC is also a soft deactivation/scrub, not a hard auth/storage purge (`supabase/migrations/0009_auth_profile_account.sql:150-180`). That must be paired with a defined retention/purge worker before making deletion-compliance promises.

## Severity summary

| Severity | Fixed | Mitigated / open | External blocker |
|---|---:|---:|---:|
| Critical | 8 | 0 | 0 |
| High | 10 | 2 | 3 |
| Medium | 9 | 5 | 0 |
| Low | 2 | 4 | 0 |
| Info | 4 | 0 | 0 |

“Fixed” means covered by current code and, where practical, an executable regression. It does not substitute for staging or device validation.

## Critical findings

| ID | Status | Exact location | Impact, reproduction, and remediation |
|---|---|---|---|
| C-01 | Fixed | `supabase/migrations/0019_beta_security_hardening.sql:2485-2576`; `supabase/tests/security_regression.sql:44-54` | **Impact:** PostgreSQL grants `EXECUTE` to `PUBLIC` on new functions by default. Service-only `SECURITY DEFINER` maintenance, moderation, correlation, and AI-log RPCs were callable through the API. **Baseline repro:** call `run_maintenance`, moderation, or batch correlation with an anon/authenticated JWT. **Fix:** revoke every application RPC from `PUBLIC`, `anon`, `authenticated`, and `service_role`, then grant explicit client/service allowlists; trigger functions and future default privileges are also closed. |
| C-02 | Fixed | `supabase/config.toml:49-58`; `supabase/functions/_shared/service_auth.ts:2-18`; each Edge entry at `maintenance/index.ts:91`, `miles-correlate/index.ts:100`, `photo-review/index.ts:105`, `send-push/index.ts:184` | **Impact:** all four internet endpoints had `verify_jwt=false` and immediately used the service role, allowing unauthenticated maintenance, synthetic GPS pings, photo decisions, and push draining. **Baseline repro:** POST to a function URL without Authorization. **Fix:** gateway JWT verification is enabled, only POST is accepted, and the handler compares the bearer credential to the service-role key before parsing a body, logging a run, or creating a privileged client. |
| C-03 | Fixed | `supabase/migrations/0019_beta_security_hardening.sql:197-411`, `:434-486`; `supabase/tests/security_regression.sql:30-42`, `:137-147` | **Impact:** permissive table/storage policies let clients bypass RPC validation: profile verification/subscriber flags, photo-review state, encounter/action creation, message mutation, and private AI references were client-writable. **Baseline repro:** direct REST UPDATE of another participant’s message or own `is_photo_verified`. **Fix:** application tables are RPC-only, direct authenticated DML is revoked, message history is the only direct client table read, storage policies use active/unblocked match or revealed encounter helpers, and service-role DML is explicit. |
| C-04 | Fixed | `supabase/migrations/0019_beta_security_hardening.sql:1626-1664`; `supabase/tests/security_regression.sql:149-160` | **Impact:** `swipe_user` could manufacture an encounter from any target UUID, destroying the “real encounter” invariant and enabling targeted harassment. **Baseline repro:** enumerate/obtain a UUID and call `swipe_user` without proximity. **Fix:** it can only resolve an already-created, active, server-revealed encounter; it never inserts proximity. The test inserts a fresh encounter and proves a caller still cannot swipe it early. |
| C-05 | Fixed | `supabase/migrations/0019_beta_security_hardening.sql:149-161`, `:414-431`, `:1099-1154`, `:2273-2352`; `supabase/tests/security_regression.sql:67`, `:175-179` | **Impact:** the caller-controlled minimum age, direct tables, realtime publication, and insert-trigger push could reveal an encounter immediately. Continuous correlation also moved `encounter_time`, preventing the four-hour clock from ever completing. **Baseline repro:** pass `p_min_age_hours=0`, subscribe to `encounters`, or observe the instant push. **Fix:** server-owned setting defaults to four hours, caller input is ignored for compatibility, encounters/actions were removed from realtime, alerts are queued only after reveal, and `last_seen_at` now updates without changing first encounter time. |
| C-06 | Fixed | `supabase/migrations/0019_beta_security_hardening.sql:1339-1415`; `lib/features/locals/locals_service.dart:144-208` | **Impact:** Locals accepted arbitrary query coordinates and returned precise distance and timestamps, creating a trilateration/online-status oracle. The client also embedded two-decimal lat/lon in “Area x,y”. **Baseline repro:** repeatedly query around chosen coordinates and intersect exact distances. **Fix:** origin is the caller’s fresh server-recorded ping, responses use 250 m bands and 15-minute timestamps, only revealed real encounters appear, and the client sends/displays `Nearby`, never coordinate text. |
| C-07 | Fixed | `supabase/functions/photo-review/index.ts:108-110`, `:157-166`, `:261-285`; `supabase/migrations/0019_beta_security_hardening.sql:2114-2257`; `supabase/tests/security_regression.sql:82-113` | **Impact:** the default stub approved any non-empty path as “face/liveness”, so an attacker could become verified with arbitrary content. **Baseline repro:** submit any existing path and invoke/schedule photo review. **Fix:** remote auto-approval is impossible; the function downloads the bound immutable object, checks supported image magic, labels the check honestly, and advances to manual review. Approval/rejection validates the unchanged storage object. Runtime transition tests caught and fixed three enum-cast defects. |
| C-08 | Fixed | `lib/main.dart:50-64`; `lib/core/session/app_session.dart:124-221`, `:348-401`, `:526-553`; `lib/app_root.dart:24-110`; `lib/core/session/age_gate.dart:2-43` | **Impact:** startup created anonymous cloud users before the age gate; email failure silently became sign-up/guest; sign-out retained another account’s profile, likes, blocks, matches, chat, signed URLs, SQLite sightings, GPS, and BLE. **Baseline repro:** sign in as A, sign out, sign in as B, and inspect cached UI/preferences. **Fix:** guest creation is explicit and exact-DOB gated, sign-in never auto-signs-up/falls back, auth changes hydrate or clear state, and account transitions stop discovery and purge all user-scoped stores/caches. |

## High findings

| ID | Status | Exact location | Impact, reproduction, and remediation |
|---|---|---|---|
| H-01 | Open; mitigated | `lib/core/config/app_config.dart:52-69`; `lib/features/beacon/ephemeral_token_generator.dart:25-96`; `lib/features/beacon/beacon_service.dart:205-208` | A shared secret compiled into an APK can be extracted. The server sees only a derived 128-bit correlation ID and cannot verify the client HMAC, so HMAC does not authenticate a genuine app/device. Current mitigation: strong-secret refusal, per-user binding, random 128-bit input, unique claim ownership, 1–21 minute validity, fresh coordinates, RSSI, discovery gates, and rate limits. Recommended fix: server-issued short-lived correlation material plus device attestation/registration; keep random offline-local IDs separate. |
| H-02 | Fixed | `supabase/migrations/0019_beta_security_hardening.sql:114-117`, `:811-985`; `supabase/tests/security_regression.sql:162-172` | Claims/sightings lacked format, freshness, coordinate, RSSI, uniqueness, dedupe, and rate checks. An authenticated modified client could replay/relay indefinitely. Claims are now unique per user/token, require lower-case 32-hex IDs, fresh coordinates, bounded validity, and rate limits; sightings require a live other-user claim, fresh time/coords/RSSI, dedupe, and a capped physical radius. The residual rooted-GPS/relay risk is H-01. |
| H-03 | Fixed | `supabase/migrations/0019_beta_security_hardening.sql:197-218`, `:303-411`, `:1879-2000`; `lib/core/privacy/safety_store.dart:61-101` | Blocking was local-only in key UI paths and did not end matches, close chat/storage reads, remove encounters, or suppress all push actor shapes. It now runs server RPCs, ends encounters/matches, applies to message and media RLS, suppresses outbox rows, and uses the other user UUID rather than a numeric match ID. Unblocking never resurrects a match. New-account block evasion remains an identity/attestation policy issue. |
| H-04 | Fixed | `supabase/migrations/0019_beta_security_hardening.sql:2425-2452`; `supabase/functions/send-push/index.ts:226-459` | Push workers selected pending rows non-atomically, minted OAuth per row, ignored `other_user_id` blocks and paused/deleted recipients, double-counted attempts, leaked message previews, and never retried transient failures. The queue now uses `FOR UPDATE SKIP LOCKED`, marks processing atomically, recovers stale workers, mints once per batch, rechecks recipient/block state, sends generic message text, and requeues up to five attempts. A narrow block-vs-external-send race remains unavoidable and is listed as L-04. |
| H-05 | Fixed | `lib/core/privacy/image_sanitizer.dart:8-40`; `lib/shared/services/profile_sync_service.dart:61-101`; `lib/shared/services/photo_url_service.dart:9-50` | Profile uploads retained possible EXIF/GPS metadata, always claimed JPEG regardless of extension, used overwrite (`upsert=true`), kept a failed local absolute path in cloud profile state, and allowed external tracking URLs/global signed-URL cache. Images are bounded, decoded, orientation-baked, resized, JPEG re-encoded, uniquely uploaded with `upsert=false`, and failures abort sync. URLs are restricted to the configured Supabase host and cache keys include user ID. |
| H-06 | Fixed | `lib/features/beacon/beacon_service.dart:53-180`, `:360-457`, `:517-544`; `lib/features/beacon/beacon_provider.dart:34-108` | Beacon state became ON before BLE succeeded; advertisement errors were swallowed; scanning ended after one hour; queues were cleared before upload and lost on error; maps were unbounded; stale location and a 0,0 fallback were uploaded; auth/secret changes left a stale service. Startup is transactional, failures reach UI, scanning restarts at 55 minutes, queues retry with hard caps, cache maps are bounded, fresh coordinates are required, claims release on stop, and providers rebuild on identity changes. Cloud-claim failure is visible as local-only. |
| H-07 | Fixed | `lib/features/locals/locals_service.dart:72-208`; `lib/features/home/home_shell.dart:92-107`; `lib/features/beacon/beacon_screen.dart:18-70` | Locals started GPS merely because its IndexedStack page was constructed, timer/stream syncs overlapped, last-known fixes could be stale, and GPS continued after beacon off/sign-out/pause. Location starts on tab selection or Miles beacon mode, uses freshness and concurrency guards, and stops on exit unless an active Miles beacon owns it; account/pause/incognito transitions stop it. |
| H-08 | Fixed | `supabase/migrations/0019_beta_security_hardening.sql:1776-1857`; `lib/shared/services/chat_sync_service.dart:108-149`; `lib/features/matches/match_store.dart:593-661`; `lib/features/chat/messages_screen.dart:190-392` | “Photo messages” were stored only on the sender’s filesystem while UI implied cloud delivery. Message table policies also allowed unsafe mutation. Photos now upload to `chat_media/{match}/{sender}/{uuid}.jpg`, the RPC validates the active match and exact object, metadata/realtime hydrate the peer, signed URLs render remotely, and optimistic failures roll back. Cloud-history failure is now visible rather than indistinguishable from empty chat. |
| H-09 | Fixed | `supabase/migrations/0019_beta_security_hardening.sql:46-67`, `:2375-2392`; `lib/features/matches/match_store.dart:501-559` | Match expiry existed only in local clocks; stale/blocked/deleted server matches were merged forever and could reappear. The server owns active/expired/blocked state and the 24-hour no-message expiration, maintenance expires rows, and successful sync replaces the server subset instead of retaining ghosts. |
| H-10 | Fixed | `lib/core/session/age_gate.dart:7-43`; `lib/features/auth/auth_screen.dart:49-170`; `lib/core/session/app_session.dart:339-401`; `supabase/migrations/0019_beta_security_hardening.sql:512-648` | Birth-year subtraction admitted users before their birthday, OAuth skipped the gate, and editable profile flags could fake verification. Exact ISO DOB is required and tested at the birthday boundary; email/phone/guest/OAuth paths collect it, the server derives `age_verified`, and discovery requires both exact adult DOB and server-owned age/photo flags. Self-asserted DOB still needs product/legal identity policy. |
| H-11 | Fixed | `supabase/migrations/0004_encounter_reveal_delay.sql:12`; `supabase/migrations/0014_restrict_profile_read.sql:24-28`; `supabase/migrations/0019_beta_security_hardening.sql:2114-2257` | A clean install could fail because `CREATE OR REPLACE get_my_encounters` changed its result shape and a function comment named the wrong signature. Runtime photo-review CASE expressions also resolved as text instead of enums. Old signature is dropped explicitly, the five-argument comment is corrected, enum branches are cast, and the clean chain plus live transitions are tested. |
| H-12 | External blocker | `lib/core/notifications/push_service.dart:11-51`; `docs/SUPABASE_SETUP.md:108-151` | No Firebase Messaging SDK/config means production devices cannot produce or refresh tokens. Server outbox delivery can only dry-run or use a mock token. Wire Firebase, notification permission UX, token rotation/logout unregister, foreground/background handlers, and live Android 10 delivery before beta. |
| H-13 | External blocker | `supabase/functions/photo-review/index.ts:7-9`, `:225-236`; `docs/GO_LIVE_CHECKLIST.md:24-32` | Remote photos stop at `manual_review`; no model, moderator UI/SLA, escalation, or abuse retention workflow exists. This is deliberately fail-closed, but photo-first discovery cannot operate at beta scale until moderation is staffed or integrated. |
| H-14 | External blocker | `lib/main.dart:78-123`; `android/app/src/main/AndroidManifest.xml:21-65` | The foreground service now maintains a notification heartbeat, but BLE/GPS remain app-process plugin operations and there is no verified reboot auto-start. Run the four-S9 matrix, one-hour scan rollover, 8–24 hour soak, Doze, force-stop, process kill, reboot, Bluetooth/location toggle, permission denial/regrant, and simultaneous advertise/scan tests. |
| H-15 | Open | `supabase/migrations/0009_auth_profile_account.sql:150-180`; `lib/features/settings/settings_screen.dart:316-370` | “Deletion” deactivates and scrubs the public profile and removes ephemeral location/token/device data, but retains the auth record and some relational/storage data. UI now states this honestly. Implement a documented retention window and service/storage-API purge job, preserving only legally required pseudonymized abuse evidence. |

## Medium, Low, and informational findings

| ID | Severity / status | Exact location | Finding and action |
|---|---|---|---|
| M-01 | Medium / Fixed | `lib/core/config/app_config.dart:12-105`; `test/app_config_test.dart:6-44`; `.env.example:1-16` | Compile-time define lookup could select the wrong value; flags ignored defines; weak placeholders counted as secrets; reveal default could be zero. Exact switch-based precedence, placeholder/length rejection, a four-hour default, blank example secrets, and both normal/define-mode tests now cover it. |
| M-02 | Medium / Fixed with residual | `scripts/build-install-s9.sh:8-18` | The lab script sourced `.env` as shell code and omitted x64. Flutter now parses it with `--dart-define-from-file` and builds all three ABIs. Residual: any Dart define is embedded in the artifact, which is why H-01 must not treat app secrets as server trust. |
| M-03 | Medium / Fixed | `android/app/build.gradle.kts:10-40`; `android/app/src/main/AndroidManifest.xml:18-37` | Example application ID, debug release signing, missing x86_64, cleartext, backup, inconsistent `neverForLocation`, unused storage/media/boot permissions were release hazards. Package is `io.inrange.app`, release signing must come from CI/Play, x64 is included, backup/cleartext are off, and permissions are reduced/honest. |
| M-04 | Medium / Fixed | `lib/core/backend/backend_status.dart:70-104`; `lib/core/session/app_session.dart:174-217` | A cached session was treated as network-online and anonymous was mislabeled. Status now calls `backend_health`, distinguishes anonymous, and clears stale persisted cloud sessions when no auth session exists. |
| M-05 | Medium / Fixed | `lib/core/privacy/safety_store.dart:61-142`; `lib/features/matches/match_profile_screen.dart:66-81` | Reports/blocks were local and Match Profile passed a match/correlation ID instead of the other user UUID. Server RPCs, valid enum mapping, match context, local fail-closed cache, unblock, and cross-account clearing are wired. |
| M-06 | Medium / Fixed | `lib/features/encounters/swipe_feed.dart:31`, `:66`, `:89`, `:107-163`, `:307-313` | Dismiss state watched only a notifier, rapid taps raced, and “undo” implied a server rollback it did not perform. State is watched, one action can run at a time, and undo is local-lab only. |
| M-07 | Medium / Partly fixed | `lib/features/matches/match_store.dart:254-258`, `:501-559`; `lib/app_root.dart:104-110` | Server chat bodies are no longer persisted in plaintext preferences and account changes clear all caches. Match metadata/local-mode messages remain device-sandbox plaintext. For a higher-risk beta, use encrypted account-scoped storage with a Keystore-backed key and migration/erase tests. |
| M-08 | Medium / Mitigated | `supabase/migrations/0019_beta_security_hardening.sql:738-806`; `lib/features/settings/settings_screen.dart:417-429` | AI feedback accepted unbounded frequency/metadata and free text can contain PII. RPC now validates type/rating/text/JSON object, caps metadata at 16 KiB, rate-limits 20/hour, and UI warns against names/contact/location. Free text still requires privacy policy, retention, and moderator access controls. |
| M-09 | Medium / Fixed | `supabase/functions/*/index.ts` `publicError`; `supabase/functions/_shared/service_auth.ts:2-28` | Edge responses could return short internal database/error messages. Public failures are now stable generic codes; details remain server logs/AI ops only. |
| M-10 | Medium / Open | `pubspec.yaml:17-50` | Several major dependency upgrades are available. Build runner also warns that Dart language 3.12 is newer than its analyzer language 3.9; `flutter_ble_peripheral` warns that future Flutter built-in Kotlin migration will break its current KGP behavior. Upgrade in a dedicated native release with S9 regression tests. |
| M-11 | Medium / Open | `lib/shared/services/encounters_api.dart:18-42`, `:175`; `supabase/migrations/0019_beta_security_hardening.sql:1099`, `:1339`, `:1679` | Feeds/matches use fixed pages (typically 50) and the UI has no cursor/infinite-scroll contract. Server limits are safely capped at 100, but 1,000+ histories need cursor pagination and deterministic tie-breakers. |
| M-12 | Medium / Partly fixed | `lib/shared/services/chat_sync_service.dart:69-104`, `:165-211`; `lib/features/chat/messages_screen.dart:139-332` | Initial history failure is now visible and message-send failures roll back. Realtime subscription status/reconnect is still not surfaced, and background sync refresh can remain debug-log-only. Add explicit channel status, retry/backoff, and stale-data indicators. |
| M-13 | Medium / Fixed | `docs/SUPABASE_SETUP.md:20-151`; `docs/GO_LIVE_CHECKLIST.md:1-36`; `scripts/go-live.sh:1-34` | Migration counts, legacy FCM server keys, insecure stub instructions, package ID, and cron auth were stale. Docs now describe migrations 0001–0019, FCM HTTP v1 credentials, manual review, and service bearer schedules. |
| M-14 | Medium / Open | generated `build/app/outputs/flutter-apk/app-debug.apk` | The universal debug APK is 183,868,348 bytes (175.35 MiB). Debug/multi-ABI overhead is expected but not a distribution target. Measure signed release and use Play App Bundle or `--split-per-abi`; set a CI size budget. |
| L-01 | Low / Improved, still open | `test/age_gate_test.dart`, `test/app_config_test.dart`, `test/ephemeral_token_generator_test.dart`, `test/widget_test.dart` | Coverage grew from one non-hermetic widget test to four files/eight tests plus SQL regressions, but core Riverpod state machines, BLE plugin adapters, chat media, auth transitions, and UI golden/accessibility paths remain lightly tested. |
| L-02 | Low / Open | UI strings throughout `lib/features/` | No localization framework or locale-ready string catalog exists. Before wider beta, extract user-visible strings and test large fonts/long translations. |
| L-03 | Low / Open | debug logging sites in `lib/features/` and `lib/shared/services/` | Sensitive correlation IDs and full user IDs were removed from logs, but many operational failures still use `debugPrint`. Add structured redacted telemetry/crash reporting with consent and retention limits. |
| L-04 | Low / Residual | `supabase/functions/send-push/index.ts:274-459`; `supabase/migrations/0019_beta_security_hardening.sql:1879-1922` | A block can occur after the worker’s final database check but before FCM accepts an external request. Database status updates cannot atomically cancel an already-started third-party HTTP call. Keep push copy generic and document this narrow race. |
| L-05 | Low / Open | `lib/shared/services/photo_url_service.dart:36-50`; `lib/shared/services/chat_sync_service.dart:140-149` | Profile signed URLs are cached; chat media signed URLs are not, so rebuilds can create extra signing requests. Add a short account-scoped chat URL cache and clear it with auth transitions. |
| L-06 | Low / Open | `lib/features/profile/profile_setup_screen.dart:82-128`; `lib/shared/services/profile_sync_service.dart:52-104` | Photo processing/upload has a busy state and honest failure, but no per-file progress/cancel/retry UI. This matters on older S9 storage and weak networks. |
| I-01 | Info / Verified | `supabase/migrations/0001_init.sql:143-158`; `supabase/migrations/0019_beta_security_hardening.sql:976-977`, `:1212`, `:1391` | Sightings have the required GIST geography index; points use lon/lat with SRID 4326 and geography; `ST_DWithin` radii are meters. `spatial_ref_sys` is a PostGIS extension table and is intentionally outside application RLS assertions. |
| I-02 | Info / Verified | `.gitignore:35-45`; `supabase/functions/send-push/index.ts:126` | `.env`, keystores, service config, and local Supabase files are ignored. Working tree/history scans found no credential-shaped material; the sole history match is the literal PEM header used by the FCM private-key parser, not a key. Final APK contains none of the current ignored `.env` values. |
| I-03 | Info / Verified | `supabase/migrations/0018_security_correlate_photos.sql:10-68`; `supabase/migrations/0019_beta_security_hardening.sql:327-411` | The prompt permits public-read photo URLs as a tradeoff, but baseline migration 0018 had already made these buckets private. This audit retained the stricter owner/revealed-encounter/active-match policy and did not re-open public access. UUID paths are not authorization. |
| I-04 | Info / Deployment classification | native/config files above and SQL/Edge/Dart paths | Dart-only follow-up changes can use Shorebird after a compatible base release. This remediation changes `pubspec`, Android package/manifest/ABI/signing, Kotlin source path, and plugins; it therefore requires a new Play Store/base release. Migration 0019 and Edge Functions deploy separately and must precede the matching client rollout. |

## RLS, RPC, storage, and realtime audit result

- Every privacy-sensitive application table has RLS enabled. Migration 0019 fails installation if any listed table does not (`supabase/migrations/0019_beta_security_hardening.sql:2591-2620`).
- `blocked_pairs` does not exist in this schema; the audited table is `public.blocks`.
- Authenticated clients have direct `SELECT` only on `messages`, filtered by active/unblocked match RLS. All application mutations go through explicit RPCs.
- Service-role table/sequence privileges are explicit; `BYPASSRLS` alone was correctly recognized as insufficient (`supabase/migrations/0019_beta_security_hardening.sql:458-486`).
- Trigger helpers no longer retain default `PUBLIC` execute. Future functions/tables/sequences default closed (`:2485-2588`).
- Realtime publishes `matches` and `messages`; only message rows have a client table grant, and message RLS requires an active unblocked match. Fresh `encounters` and `encounter_actions` were removed from publication.
- `profile_photos`, `verified_photos`, and `chat_media` are private. Reads require owner/revealed encounter/active match; writes require an owner path and immutable or active-match rules.
- Pre-match `display_name` is always masked as `Someone nearby`; `other_action` is returned as null. Verified photos and coarse neighborhood are the intentional photo-first surface.

## Maintenance behavior

`run_maintenance` is service-only and performs the following (`supabase/migrations/0019_beta_security_hardening.sql:2273-2479`):

- removes token claims more than 30 minutes past validity;
- removes sightings older than 48 hours and location pings older than 24 hours;
- recovers push rows stuck in `processing` for 10 minutes, with a five-attempt cap;
- removes sent/skipped outbox rows after 30 days and failed rows after 7 days;
- removes AI runs/events after 90 days;
- expires feet encounters 24 hours after `last_seen_at`;
- expires active no-message matches at server-owned expiry;
- queues post-reveal and two-hour-expiry alerts with block/discovery checks.

It does **not** hard-delete soft-deactivated auth users or physical Storage objects. That is H-15.

## Bug inventory

### Silent failures and dishonest state

| Surface | Baseline behavior | Result |
|---|---|---|
| Email auth (`app_session.dart`) | Any sign-in error attempted sign-up, then guest/local state; confirmation could create a different anonymous identity. | Fixed: sign-in and sign-up are explicit, cloud-only operations; guest is a separate exact-age-gated action. |
| Cloud profile/pause/delete | Errors were logged or swallowed while local flags advanced. | Fixed: profile and pause fail visibly; deletion does not clear local data when the cloud request fails. Incognito updates server before local. |
| Beacon controller/advertiser | Controller swallowed startup errors and service marked ON before BLE success; both advertiser attempts could fail while UI stayed green. | Fixed: transactional start, exception propagation, generic user error, cloud-claim status. |
| Sighting upload | Queue cleared before RPC; failures dropped permanently; missing GPS became 0,0. | Fixed: bounded retry queue, removal only after success, fresh non-null coordinates. |
| Scan stream | One-hour timeout had no restart; stream error only logged. | Fixed: 55-minute restart plus error-triggered restart. Physical validation remains H-14. |
| Locals GPS | Stale last-known accepted, timer/stream overlapped, background state started from hidden tab. | Fixed: freshness/concurrency guards and lifecycle ownership. |
| Backend status | Cached auth session was called online without a network request. | Fixed: `backend_health` reachability and anonymous mode. |
| Safety | Block/report were local; wrong match ID sent; unblock not cloud-wired. | Fixed: server RPCs, other UUID, valid report enum/details, fail-closed local state. |
| Chat photo | Sender saw a local file bubble; peer received nothing. | Fixed: match-scoped upload/RPC/realtime/signed URL. |
| Chat history | Network/RLS error returned an empty list. | Fixed: error rethrows through store and thread shows a cloud-history warning. `markRead` remains best-effort/debug-only. |
| Optimistic message | RPC failure could be hidden by local bubble. | Fixed: bubble rollback and draft restoration. |
| Match sync | Remote deletion/block/expiry did not remove cached server rows. | Fixed on successful sync; transient sync failure deliberately preserves last-known state and logs. Add a stale indicator (M-12). |
| Push drain | Duplicate workers, no retries, repeated OAuth, incomplete block checks. | Fixed with atomic claim, retries, one token/batch, recipient/block gates. |
| Edge errors | Some internal error messages returned to caller. | Fixed: generic public codes, internal server logging. |
| Local moderation JSON | Corruption silently became an empty list. | Startup remains fail-safe, but now emits a debug breadcrumb (`lib/core/privacy/safety_store.dart:30-42`). |
| Photo URL/media signing | Failures intentionally render a broken-image fallback. | Accepted UI fallback; add retry affordance/cache as L-05/L-06. |
| Push client register/unregister | Failures are debug-only and there is no real token provider. | Open external blocker H-12. |
| Background service | Previously only logged `setBeaconActive`. | Improved with foreground notification heartbeat/stop handling; survival/reboot remains H-14. |

### State machines, races, and consistency

| State machine | Finding | Result |
|---|---|---|
| Auth | OAuth deep-link session was not reliably applied; cached cloud session could outlive auth; cross-account state was global. | Auth-state subscription, cloud hydration, stale-session clearing, and user-runtime purge added. |
| Age/profile | Year-only check and fake default DOB; client could finish without a photo. | Exact DOB, server-owned verification, conservative legacy migration, and at least one photo required. |
| Beacon | ON→OFF→ON could retain timers/maps/claims; secret/user changes did not reconstruct service. | Timers/subscriptions/maps/claim reset; provider watches user ID and disposes service. |
| Encounter | Repeated correlation moved first-seen time; caller/realtime/push bypassed reveal. | Separate immutable first time and `last_seen_at`; server reveal everywhere. |
| Token | Duplicate claims and unbounded replay window. | Unique user/token, bounded time, coordinate/RSSI/rate validation. Rooted relay residual is H-01. |
| Swipe | Mutual-like race and rapid UI taps; cloud undo was false. | Advisory/row locks and unique match; UI serializes actions; no cloud undo claim. |
| Match | Client-only expiry and asymmetric local ghosts. | Server status/expiry/maintenance plus replacement sync. |
| Message | Direct row UPDATE could edit other messages/columns; media object could be unrelated. | RPC-only mutation and exact active-match object validation. |
| Photo | Approved object could be overwritten under same path between submission and decision. | No client UPDATE/upsert; decision binds storage object ID and update timestamp. |
| Push | Two workers could send one row; dead worker stranded processing forever. | `SKIP LOCKED` claim plus stale-processing recovery. |
| Local/cloud | Server chat was stored in plaintext prefs and old account SQLite/preferences persisted. | Server message bodies are not persisted; all user stores clear on auth transitions. Local-mode content remains sandbox plaintext (M-07). |

### Edge cases checked

- Empty Encounters, Locals, Matches, History, and Chat have non-crashing empty/unavailable states.
- Fresh encounters remain hidden even when a caller supplies zero hours.
- Arbitrary UUID swipe is rejected even for a discoverable peer with only a fresh/unrevealed encounter.
- Direct profile verification update is permission denied.
- `other_action` is null before a match.
- Claim without coordinates is rejected.
- Duplicate push claim returns zero rows to the second worker.
- Photo state transitions execute against a bound Storage object.
- Invalid AI feedback metadata is rejected.
- Profile image size/dimension/corruption is bounded before upload.
- Legacy invalid Miles range is sanitized to one of 1/5/10 miles, avoiding dropdown assertions/server enum misuse.

## Threat model result

| Threat | Current result | Residual |
|---|---|---|
| Pre-match anonymity | Name, bio, DOB, interests, reciprocal swipe, exact time, exact distance, and online state are withheld. Verified photo(s), coarse neighborhood, range band, and an opaque UUID only appear after a real server-revealed encounter. | Repeated encounters can still reveal routines; add user-facing safety education, retention controls, and abuse analytics. |
| Block evasion | Block ends encounters/matches, removes chat/media access, suppresses pushes, and excludes correlation/feed. | A new account/email/device is a new identity. Device attestation, abuse signals, moderator tooling, and appeal policy are required. |
| Location inference | Own fresh server ping anchors Locals; distance/time are banded; human-readable coordinate cells removed; pings expire. | Rooted/mock GPS and repeated observations remain. Do not market this as anti-spoof without attestation. |
| Photo enumeration | Buckets are private and UUID knowledge is insufficient; policies require owner/revealed encounter/active match. | Signed URLs are bearer URLs until expiry. Keep expiry short and clear caches on auth, which the client now does. |
| Token spoof/relay | 128-bit advertised IDs, unique short claims, fresh coordinates, RSSI, blocks, verification, and rates materially limit casual abuse. | Shared APK secrets are extractable and the server cannot validate their HMAC. H-01 remains. |
| Realtime eavesdropping | Fresh encounters/actions are not published; message rows require direct SELECT plus active-unblocked match RLS. | Validate with the live Supabase Realtime service and revoked/blocked sessions during staging, not only local Postgres. |

## Build and verification evidence

| Check | Command/result |
|---|---|
| Clean dependency restore | `.env`-excluded temporary copy: `flutter pub get` passed. 39 packages report newer incompatible versions; no restore failure. |
| Config precedence | Normal `flutter test` plus a dedicated run with `--dart-define=EXPECT_DART_DEFINE=true ...`: 3/3 config tests passed; define wins over dotenv and blank config fails closed. |
| Code generation | `dart run build_runner build --delete-conflicting-outputs`: passed, wrote 0 outputs. Warning remains: SDK language 3.12 vs analyzer language 3.9 (M-10). |
| Flutter analyze | `flutter analyze`: **No issues found**. |
| Flutter tests | `flutter test`: **8 passed, 0 failed, 0 skipped** across four test files. The widget test no longer reads the real `.env`. |
| Edge type check | `deno check` on shared auth + all four functions: passed. |
| Database clean replay | `supabase db reset`: migrations 0001–0019 and seed passed from an empty local Postgres instance. This was repeated after final SQL changes. |
| SQL security regressions | `psql < supabase/tests/security_regression.sql`: transaction completed and rolled back cleanly; all assertions and expected-denial paths passed. |
| Database lint | Supabase lint reports no issues for the remediated photo/feedback functions. Remaining app warnings are intentionally unused legacy API parameters whose values are no longer trusted; other reported errors are PostGIS extension/plpgsql-check false positives. |
| Debug APK | `flutter build apk --debug --target-platform android-arm,android-arm64,android-x64`: passed. Current Flutter warns that `flutter_ble_peripheral` must migrate from KGP before a future Flutter release. |
| APK contents | 183,868,348 bytes; native libs for `armeabi-v7a`, `arm64-v8a`, `x86_64`; application ID `io.inrange.app`; `allowBackup=false`; `usesCleartextTraffic=false`. |
| Artifact secret check | No current ignored `.env` URL/key/HMAC/user-secret value was found in the APK. This build deliberately used no local defines. |
| Tracked/history secret scan | No credential-shaped tracked/history value found. PEM-header matches are the FCM key parser literal at `send-push/index.ts:126`. |

Not verified here:

- signed release/AAB, Play signing, or Shorebird base release;
- real Supabase project migration/deploy and Realtime websocket behavior;
- real Firebase token acquisition/delivery/invalid-token cleanup;
- real moderation provider or moderator operation;
- any physical Galaxy S9, BLE, GPS, Doze, reboot, or multi-device test;
- network adversary/rooted-device/Play Integrity test;
- accessibility, localization, penetration test, or legal/privacy review.

## Prioritized improvements

| Priority | Recommendation | Impact | Effort |
|---|---|---:|---:|
| P0 | Replace APK-wide beacon trust secrets with server-issued short-lived correlation material; add per-install keypair/device registration and Play Integrity where policy permits. | Very high | High |
| P0 | Wire Firebase Core/Messaging, notification channels/permission UX, refresh/unregister, and live delivery tests. | High | Medium |
| P0 | Integrate real moderation/liveness or staff the manual queue with SLA, appeal, audit, and access policy. | Very high | High |
| P0 | Execute the four-S9 matrix and 8–24 hour background soak, including Doze, reboot, process death, and permission toggles. | Very high | Medium |
| P0 | Implement retention-backed hard purge using privileged auth deletion and Storage API deletion; test cascades and legal abuse-evidence handling. | High | Medium |
| P1 | Upgrade Riverpod/geolocator/permission/config/tooling in a dedicated branch; resolve build-runner analyzer and Flutter built-in Kotlin warnings. | High | Medium |
| P1 | Encrypt account-scoped local match/history/local-mode message data with an Android Keystore-backed key and versioned migration. | Medium | Medium |
| P1 | Add cursor pagination, stale/sync indicators, channel reconnect status, and exponential backoff with jitter. | Medium | Medium |
| P1 | Add server/client telemetry for scan restart, claim sync, queue age/drop, FGS liveness, correlation latency, and battery—redacted and consented. | High | Medium |
| P1 | Handle FCM invalid-token responses by deleting dead tokens while retaining transient retry behavior. | Medium | Low |
| P2 | Cache chat signed URLs briefly per account and add photo upload progress/cancel/retry. | Low | Low |
| P2 | Add localization, large-font/accessibility tests, UI integration/golden tests, and device screenshot automation. | Medium | Medium |
| P2 | Ship App Bundle/split ABIs and enforce release size/native-ABI checks in CI. | Medium | Low |

## Release/deployment notes

This remediation is **not Shorebird-only**. A new native base/Play release is required because it changes Android application ID/package, manifest permissions/security flags, ABI filters, release signing behavior, Kotlin source path, and the dependency graph. Existing test installs under `com.example.in_range` will not update in place; uninstall or migrate intentionally.

Recommended deployment order:

1. Back up/stage the Supabase project and apply migration 0019; run `supabase/tests/security_regression.sql` against a disposable clone, not production data.
2. Deploy all four Edge Functions with JWT verification and service bearer schedules/webhooks.
3. Configure manual/real photo review and Firebase HTTP v1 secrets; confirm dry-run is off only when ready.
4. Build/sign a new `io.inrange.app` AAB/base release with production reveal set to four hours and no client “secret” used as a server trust boundary.
5. Run physical S9/device and live-service test matrices.
6. Only after those gates pass, reassess verdict from **BLOCKED** to `READY_FOR_BETA`.
