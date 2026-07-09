# In Range — Build Plan (2026-07-07)

> Goal: ship a Flutter BLE proximity dating app that compiles cleanly, installs on 4 Galaxy S9s (Android 10), requests permissions correctly, advertises+scans BLE beacons, and round-trips encounter data to Supabase PostGIS.

## Audit Summary (from project auditor + BLE research)

### DONE
- Flutter SDK 3.44.5 stable at `~/flutter/bin` (PATH wired in `~/.bashrc`)
- `pubspec.yaml` — all key deps declared (`flutter_blue_plus ^2.3.10`, `flutter_ble_peripheral ^0.1.4`, `permission_handler ^11.3.1`, `flutter_background_service ^5.0.0`, `supabase_flutter ^2.8.0`, `riverpod ^2.6.1`, `geolocator ^13.0.2`, `crypto`, `freezed`)
- Supabase schema migrations 0001 + 0002 (`profiles`, `token_claims`, `sightings` w/ PostGIS geography + GIST, `encounters`, `encounter_actions`, `matches`, `messages`, `location_pings`, RLS on every table, RPCs `claim_token`, `record_sighting`, `correlate_encounter`, `get_my_encounters`)
- `ephemeral_token_generator.dart` — HMAC-SHA256, base64url, 15-min epoch rotation ✓
- `beacon_service.dart` — rotation timer, 30s batch flush, advertise via `flutter_ble_peripheral`, scan via `flutter_blue_plus`, foreground-service invoke
- `beacon_provider.dart` + `beacon_screen.dart` — Riverpod controller + working UI
- `encounters_repository.dart` — `getMyEncounters` + `recordAction` RPCs
- `supabase_client.dart` — thin wrapper
- `AndroidManifest.xml` — full perms + foregroundServiceType=connectedDevice|location + IsolateHolderService
- `main.dart` — ProviderScope, background service config, 30s heartbeat
- Docs: `HANDOFF.md`, `README.md`, `docs/ephemeral-token-spec.md`

### PARTIAL
- `main.dart` Supabase init — commented out, no `.env`, no `flutter_dotenv`
- `beacon_provider.dart` — hardcoded dummy secrets (`test-user-secret-12345678`)
- `beacon_service.dart` scan — untested, 1h timeout, no adaptive re-start, `Geolocator` fire-and-forget no error handling
- `beacon_service.dart` advertising — **TOKEN TRUNCATED TO 20 BYTES** (token is ~52 chars base64). Scanner decodes raw charcodes → garbage. Round-trip broken.
- Background service `onStart` — only sets foreground notification, does NOT drive BLE from service isolate

### MISSING
- No `pubspec.lock` (never ran `pub get` successfully)
- Android scaffolding: NO `build.gradle`, `settings.gradle`, `MainActivity.kt`, `kotlin/`, `res/`, `gradle/wrapper` — only `AndroidManifest.xml` exists
- No `.env` / `flutter_dotenv` dep
- No runtime permission request code anywhere in `lib/`
- No auth flow (every RPC throws "Not authenticated" because `auth.uid()` is null)
- No profile/matches/chat screens
- No tests
- No CI

### BROKEN
1. **BLE token round-trip** — advertiser truncates to 20 bytes, scanner produces garbage → `record_sighting` uploads junk → `correlate_encounter` never matches. **Core feature broken.**
2. **`record_sighting` radius** — hardcoded 50m + 90min regardless of `range_type` (miles modes never correlate)
3. **`correlate_encounter` time filter** — `valid_until > NOW() - window` should be `valid_until > NOW()` (expired claims pass)
4. **`Geolocator.getCurrentPosition()`** — no try/catch, throws if location denied

## Research Findings (verified against pub.dev + Android docs)

- **flutter_ble_peripheral (v2.1.1) + flutter_blue_plus (v2.3.10)** is the correct pair (flutter_blue_plus README explicitly recommends flutter_ble_peripheral for peripheral role)
- **Android 10 perms**: `BLUETOOTH`/`BLUETOOTH_ADMIN` are normal (install-time); `ACCESS_FINE_LOCATION` is runtime; `ACCESS_BACKGROUND_LOCATION` for background scan; `BLUETOOTH_SCAN/ADVERTISE/CONNECT` runtime perms are **Android 12+ only** — do NOT request them on API 29
- **Permission sequence**: must request `locationWhenInUse` FIRST, then `locationAlways` — direct `locationAlways` request is ignored on Android 10
- **Background BLE survival**: flutter_blue_plus README explicitly disclaims background support ("you may have to fork it"). `flutter_background_service` doesn't mention BLE. **Foreground service with FOREGROUND_SERVICE_LOCATION is required but not guaranteed to keep advertising alive.** This is a known integration risk; document as best-effort.
- **PostGIS**: `geography(Point, 4326)`, `ST_DWithin` for radius, **longitude first** (`ST_Point(long, lat)`), GIST index. Use RPC to handle geography encoding.
- **Shorebird**: supports Flutter ≥3.24.0, so 3.44.5 ✓
- **permission_handler v12.0.3**: `Permission.bluetooth` returns `granted` on Android 10 (BLUETOOTH is normal perm). No `undefined` status.

## Top 5 Implementation Risks
1. Background BLE advertising not guaranteed on Android 10 (flutter_blue_plus disclaims it; need foreground service + FOREGROUND_SERVICE_LOCATION, document as best-effort)
2. Permission sequence (locationWhenInUse → locationAlways) — must be in order, graceful degrade if user denies second prompt
3. BLE token truncation — must redesign to use a fixed-size correlation ID (16 bytes) instead of truncating a 52-char token
4. `flutter_ble_peripheral` v2.1.1 maturity — advertising reliability on Android 10 undocumented; may need testing/tuning on real S9 hardware
5. PostGIS geography encoding — long/lat order, must use RPC not direct select

---

## TODO List (numbered, in execution order)

### Phase A — Foundation (blocker for everything)
- [ ] **A1.** Run `flutter pub get` in `~/in-range` — generates `pubspec.lock`, resolves deps
- [ ] **A2.** Run `flutter create . --platforms=android --org com.inrange --project-name in_range` — populates Android scaffolding (build.gradle, MainActivity.kt, res/, gradle wrapper). Restore our pre-built AndroidManifest.xml from `.bak` if overwritten.
- [ ] **A3.** Verify `flutter analyze` passes with zero errors (warnings OK initially)

### Phase B — Fix Broken Code (core feature)
- [ ] **B1.** Fix BLE token round-trip: replace 20-byte utf8 slice with a 16-byte correlation ID derived from `HMAC-SHA256(token, salt)[:16]`. Advertise as manufacturerData with a 16-byte payload. Scanner extracts the 16 bytes, hex-encodes, sends to `correlate_encounter` RPC.
- [ ] **B2.** Fix `correlate_encounter` SQL: `valid_until > NOW()` (not `> NOW() - window`). Add migration 0003.
- [ ] **B3.** Fix `record_sighting` radius: pass `range_type` to RPC, let SQL pick window (50m/100m for near modes, 1km/5km for miles modes — currently all 50m). Add migration 0003 update.
- [ ] **B4.** Wrap `Geolocator.getCurrentPosition()` in try/catch, skip sighting if location denied (don't crash, just log + continue)

### Phase C — Supabase + Auth + Secrets
- [ ] **C1.** Add `flutter_dotenv` to pubspec, run `pub get`
- [ ] **C2.** Create `.env.example` with `SUPABASE_URL=` and `SUPABASE_ANON_KEY=` placeholders; create `.env` (gitignored) with same. Document user must fill real values.
- [ ] **C3.** Uncomment + fix `InRangeSupabase.init` in `main.dart` — load `.env` before `runApp`, init Supabase
- [ ] **C4.** Add minimal auth flow: anonymous sign-in on first launch (`Supabase.instance.client.auth.signInAnonymously()`), persist session. (Real email/OAuth deferred — documented.)
- [ ] **C5.** Replace hardcoded `_userIdSecretProvider`/`_hmacSecretProvider` with values from `.env` (or derived from auth.uid + supabase project ref)

### Phase D — Permissions (Android 10 correctness)
- [ ] **D1.** Add `permission_handler` runtime request flow in `beacon_provider.dart` before `turnOnBeacon`: request `locationWhenInUse` → if granted → request `locationAlways` (for background). On Android 10, skip `Permission.bluetooth*` (they're normal perms, auto-granted).
- [ ] **D2.** Add `<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30"/>` to manifest (limit to Android 10/11 since 12+ uses BLUETOOTH_SCAN)
- [ ] **D3.** Add permission rationale UI: if denied, show dialog explaining why location is needed for BLE proximity

### Phase E — Background Service
- [ ] **E1.** Wire `setBeaconActive` handler in `main.dart` service `onStart` to actually call `BeaconService.start()` / `stop()` via platform channel or service-to-main-isolate message
- [ ] **E2.** Document background BLE as best-effort (flutter_blue_plus disclaims it). Add persistent notification via `flutter_background_service` foreground service.

### Phase F — Screens
- [ ] **F1.** Profile screen: display user_id (anon), allow display name + age gate (must be 18+). Store in `profiles` table.
- [ ] **F2.** Encounters list screen: show `get_my_encounters` results, like/pass buttons wired to `recordAction`
- [ ] **F3.** Matches + chat screen: realtime subscription on `matches` + `messages` (best-effort, depends on auth)

### Phase G — Tests
- [ ] **G1.** Unit test `ephemeral_token_generator.dart` — rotation, HMAC, base64url
- [ ] **G2.** Unit test correlation ID derivation (16 bytes, deterministic, same input → same output)
- [ ] **G3.** Widget test `BeaconScreen` toggle
- [ ] **G4.** Run `flutter test` — all pass

### Phase H — Build + Deploy
- [ ] **H1.** `flutter build apk --debug` — succeeds with zero errors
- [ ] **H2.** Install APK on 1 Galaxy S9 via `adb install`
- [ ] **H3.** Launch app, verify permission prompts, verify beacon toggle, verify BLE advertising starts (check via `adb logcat | grep -i ble`)
- [ ] **H4.** Install on all 4 S9s, verify cross-detection (phone A sees phone B's advertisement)
- [ ] **H5.** `flutter analyze` zero errors, zero warnings

### Phase I — Docs + Handoff
- [ ] **I1.** Update `HANDOFF.md` with final state, known limitations, how to run
- [ ] **I2.** Update `README.md` with setup + run instructions
- [ ] **I3.** Document decisions: anon auth (deferred email), background BLE best-effort, 16-byte correlation ID design, permission sequence

---

## Known Limitations (to document honestly)
- **No real Supabase project**: `.env` has placeholders; user must create Supabase project, run migrations 0001-0003, paste URL+anonKey. App will crash on RPC calls until then.
- **Anonymous auth only**: no email/OAuth — real auth deferred
- **Background BLE survival**: best-effort, flutter_blue_plus disclaims it. May need fork or alternative plugin for reliable background advertising.
- **No matches/chat UI**: server-side exists, client UI deferred (Phase F3)
- **No CI**: deferred
- **No Shorebird integration**: deferred (SDK supports it; just not wired)

## Success Criteria
1. `flutter analyze` — zero errors, zero warnings
2. `flutter test` — all pass
3. `flutter build apk --debug` — succeeds
4. App installs + launches on a Galaxy S9 without crashing
5. Permission prompts fire in correct order (locationWhenInUse → locationAlways)
6. Beacon toggle starts BLE advertising (verifiable via `adb logcat`)
7. All broken bugs (B1-B4) fixed with tests
8. Docs updated

## Tools
- Flutter SDK: `~/flutter/bin/flutter` (3.44.5 stable)
- 4 Galaxy S9s (SM-G960U, Android 10) via USB
- Supabase (placeholder until user provides real project)
- Shorebird (deferred)
