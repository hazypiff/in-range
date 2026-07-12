# IN RANGE — Handoff Sheet

**Last updated:** 2026-07-07  
**Repo:** `/home/hazypiff/in-range/` (git: `main` branch)  
**Plan:** `/home/hazypiff/in-range-enhanced-plan-2026.md` (486 lines, master)

## Current State — Phase 0 (Foundation) ~75% complete

### Done (committed)
| Commit | Area | Summary |
|---|---|---|
| `65308dc` | Backend | Migration 0001: tables, PostGIS, RPCs (`claim_token`, `record_sighting`, `correlate_encounter`, `get_my_encounters`), RLS |
| `65308dc` | Spec | `docs/ephemeral-token-spec.md` — v1 token format, rotation, anti-spoof |
| `65308dc` | Scaffold | Flutter project + feature folders + `pubspec.yaml` |
| `30236d9` | Beacon | `ephemeral_token_generator.dart` — v1 format, base64url, 15min epoch |
| `30236d9` | Beacon | `beacon_service.dart` — rotation timer, sighting buffer, batch flush to RPCs |
| `a9b7489` | UI | Riverpod providers (`beacon_provider`, `encounters_provider`) + `BeaconScreen` |
| `4da8317` | Backend | Migration 0002: `location_pings`, realtime pub, storage buckets, cleanup fn |

### Not Done (next up)
1. **Flutter SDK install** — `flutter` not on PATH. Snap or tarball; needed for `pub get` / build / run.
2. **Apply migrations to a real Supabase project** + smoke-test the RPCs.
3. **`flutter_blue_plus` scan/advertise wiring** — `beacon_service.dart` has placeholders; needs actual BLE scan callback → `observeSighting()`.
4. **Permissions layer** — `permission_handler` flow for Android 12+ (`BLUETOOTH_SCAN/CONNECT`, `ACCESS_FINE_LOCATION`, `ACCESS_BACKGROUND_LOCATION`, `FOREGROUND_SERVICE_CONNECTED_DEVICE`). iOS later.
5. **Android foreground service** — manifest + plugin (`flutter_background_service` or platform-specific). Persistent notification required for background BLE/GPS.
6. **Auth flow** — `supabase_flutter` auth (email/Apple/Google), link to `profiles` row, inject `userIdSecret` into `beaconServiceProvider` override.
7. **Photo upload UI** — `profile_photos` bucket is ready; need image picker + upload + RLS path test.
8. **Realtime subscriptions** — `matches` + `messages` published; need `supabase.channel(...)` wiring in chat/matches providers.
9. **Tests** — unit (token generator, RPC params), widget (BeaconScreen states), integration (BLE mock).
10. **CI** — Codemagic or GitHub Actions: lint, test, build APK. Shorebird setup post-launch.

## Architecture Quick Reference
- **Client:** Flutter + Riverpod + freezed, feature-folder layout under `lib/features/`.
- **Backend:** Supabase (Postgres + PostGIS + Realtime + Storage + Auth).
- **Token flow:** client generates → `claim_token` → advertises → others scan → `record_sighting` → `correlate_encounter` → `encounters` row → swipe via `encounter_actions` → mutual → `matches` → realtime → `messages`.
- **Two range modes:** `feet` (BLE RSSI, 24h expiry) and `miles` (GPS + PostGIS, `location_pings` + `nearby_location_pings`).

## Key Files
```
in-range/
├── README.md
├── pubspec.yaml
├── supabase/migrations/
│   ├── 0001_init.sql                       # tables, RPCs, RLS
│   └── 0002_location_pings_realtime_storage.sql
├── docs/ephemeral-token-spec.md
├── lib/
│   ├── main.dart                           # → BeaconScreen
│   ├── core/network/supabase_client.dart
│   └── features/
│       ├── beacon/
│       │   ├── beacon_service.dart         # rotation + sighting flush
│       │   ├── beacon_provider.dart        # Riverpod controller
│       │   ├── beacon_screen.dart          # status + toggle + encounters list
│       │   └── ephemeral_token_generator.dart
│       └── encounters/
│           ├── encounters_repository.dart
│           └── encounters_provider.dart
```

## Secrets / Config (still TODO)
- Supabase URL + anon key (use `.env` + `flutter_dotenv`).
- `hmacSecret` for token generator (load from remote config, not bundled).
- `userIdSecret` per session (derive from auth.uid + server-issued salt).

## How to Resume
1. `cd /home/hazypiff/in-range && git log --oneline` to confirm state.
2. Pick the next item from "Not Done" above.
3. If continuing Flutter work, install SDK first: `sudo snap install flutter --classic` (or tarball to `~/flutter` + add to PATH).
4. To test backend: `supabase db push` against a fresh project, then run SQL smoke tests in Supabase SQL editor (e.g. `SELECT claim_token(...)`).
5. Commit after each discrete unit of work — keeps the history reviewable.

## Open Questions (from spec / plan)
- pg_cron extension: enable on Supabase + schedule `cleanup_ephemeral_data()` every 15 min.
- Token replay protection: server should reject `record_sighting` for tokens whose `claim_token` is past `valid_until + grace`. Needs a CHECK in `record_sighting` (currently relies on token_claims DELETE in cleanup).
- Neighborhood reverse-geocoding: server-side (Edge Function) or client-side? Affects privacy + cost.

## Update 2026-07-07 (post-freeze)
- Flutter installed via snap (0+git.1fa6fd6).
- 4x physical test devices confirmed: SM-G960U (Galaxy S9) running Android 10, USB adb connected.
- PATH: /snap/bin added to ~/.bashrc.
- pub get + flutter create . --platforms android launched (first-run downloads in progress).
- Code updates: dummy secrets in providers (for early device testing), improved beacon_service with scan/advertise skeleton + sighting buffer.
- main.dart already points to BeaconScreen.
- Still needed: complete BLE integration, Android foreground service + manifest perms, real Supabase config, build_runner, test run on device.

Next priority: Let SDK finish init → pub get success → flutter devices → implement real BLE callbacks → run on one S9.

## Latest (during slow first-run)
- Flutter snap wrapper is present. Real SDK tarball (~1.47GB) is downloading in background via curl (currently ~567MB in ~/snap/flutter cache as of last check). Multiple old `flutter --version` tasks keep getting killed (signal 9) while this happens.
- `pubspec.lock` still missing.
- `android/app` directory exists (partial create + manual skeleton).
- 4x Galaxy S9 (Android 10, USB) still attached.
- Code improvements: flutter_ble_peripheral now used in _startAdvertising, scan listener made idempotent, range mapper added, foreground service trigger started, flutter_background_service added to pubspec.
- Pre-created AndroidManifest.xml with all required BLE + background location + foreground service permissions is in place.

**Do not hammer flutter commands** until a clean `flutter --version` succeeds.
When the tarball finishes extracting, run:
  export PATH="/snap/bin:$PATH"
  cd /home/hazypiff/in-range
  flutter pub get
  dart run build_runner build --delete-conflicting-outputs
  flutter devices
  flutter run -d <one S9 id>

## Update after pub get timeout
- pub get (the one launched earlier) timed out after 300s with no output (Flutter still "Initializing Flutter", downloading the 1.47GB tarball).
- Current tar size ~47M, ~11 curls running. Download is extremely slow.
- `flutter --version` still shows progress + "Initializing".
- No pubspec.lock.
- android/app/src exists + our pre-created AndroidManifest.xml (3303 bytes).
- 4x Galaxy S9 (Android 10) still attached.
- Code prep continues (advertising improved with serviceData, scan extraction, stop logic, bg service callback with heartbeat).

**Do not run flutter pub get or long commands yet.** Monitor tar size and curl count only.

When `flutter --version` returns a clean version (no "Initializing", no % lines):
1. flutter pub get
2. dart run build_runner build --delete-conflicting-outputs
3. flutter devices
4. flutter run -d <one of the S9 ids>  (e.g. 324c305855433498)


## After flutter create timeout (same as pub get)
- flutter create . --platforms=android also timed out (300s, no output).
- Tar size fluctuating (was 390M, now ~127M) — download appears to be restarting or having network issues. 11 curls active.
- Flutter still "Initializing".
- android/app/src/main only has our pre-created AndroidManifest.xml (backed up as .bak). No full gradle/MainActivity yet because create didn't finish.
- No pubspec.lock.
- Devices still ready.

**Critical**: Do not retry flutter create or pub get until `flutter --version` is clean *and* tar size is stable and growing toward 1.47G.
Use /tmp/monitor_flutter_download.sh or similar.

When ready:
1. flutter create . --platforms=android   # to generate full platform code
2. (if needed) cp android/app/src/main/AndroidManifest.xml.bak android/app/src/main/AndroidManifest.xml
3. flutter pub get
4. dart run build_runner build --delete-conflicting-outputs
5. flutter devices
6. flutter run -d <S9 id>


## Monitoring (survives agent drops)

All monitoring is designed to keep working even if this agent session dies.

### Quick commands (run these anytime)
```bash
# One-shot status
bash scripts/status.sh

# Live updating dashboard (refreshes every 10s)
bash scripts/monitor.sh

# Raw files (very lightweight)
cat /tmp/inrange_live_status.txt
tail -f /tmp/flutter_pub_get.log
tail -f /tmp/flutter_download_monitor.log
```

### Restart background monitors (if killed or after reboot)
```bash
bash scripts/start-persistent-monitors.sh
```

The background updaters use `nohup` + `disown` so they run independently of this shell/agent.

### What the monitors track

## 2026-07-08 Update: "lets get this built" — APK build phase

**Environment:** Flutter 3.44.5 stable (extracted, no downloads). pubspec.lock present. 4x Galaxy S9 (SM-G960U, Android 10) adb-connected including target `324c305855433498`.

**Completed this session:**
- `flutter pub get` → Got dependencies!
- `dart run build_runner build --delete-conflicting-outputs` → 0 new outputs (clean).
- Gradle fixes:
  - `android/app/build.gradle.kts`: added `@file:Suppress`, moved to top-level `kotlin { compilerOptions { jvmTarget.set(JvmTarget.JVM_11) } }` (replaces deprecated `kotlinOptions` inside `android {}`), bumped `compileSdk`/`targetSdk` from 35→36 to satisfy plugin deps (url_launcher_android, androidx, etc.) now that Android SDK 36 present.
  - `gradle.properties` already had `android.newDsl=false` + `android.builtInKotlin=false` (for legacy KGP plugins).
- APK build started via safe nohup: `flutter build apk --release` (backgrounded to /tmp/flutter_build_apk.log). Currently "Running Gradle task 'assembleRelease'..." with expected KGP warning for `flutter_ble_peripheral`. Kotlin compile dir growing. Monitors + watchers active via scripts/.

**Code state (ready for device test):**
- Beacon: full `BeaconService` (ephemeral tokens + correlation ID, flutter_blue_plus scan + flutter_ble_peripheral advertise, sighting buffer + RPC flush, rotation, FGS trigger).
- UI: `BeaconScreen` with status, range selector (feet_*/miles_*), toggle, encounters list (graceful on no Supabase).
- Providers, permission_service (API29/Android10 correct flow), main.dart (dotenv + anon auth + bg service).
- Repos: try/catch safe for placeholder .env (returns []).
- Manifest + gradle + foreground service declared.
- .env present with fallbacks.

**Next (execute immediately on APK success):**
1. `adb -s 324c305855433498 install -r build/app/outputs/flutter-apk/app-release.apk`
2. Launch: `adb -s 324c305855433498 shell am start -n io.inrange.app/.MainActivity`
3. `adb logcat | grep -E 'Beacon|Encounter|flutter|In Range'`
4. On device: grant perms (location when-in-use + always), toggle Beacon ON (pick feet_10), verify notification + scanning.
5. Test with 2+ devices for real BLE sightings/encounters.
6. Once stable on device: update HANDOFF, note for LLM restart.

**Monitors (keep running):**
`bash scripts/status.sh`, `bash scripts/monitor.sh`, `tail -f /tmp/flutter_build_apk.log`

**Blockers cleared:** SDK version, Gradle DSL/Kotlin target, previous freezes (LLM killed).

**Historical status:** the original example-package MainActivity mismatch was fixed; the app now uses production package `io.inrange.app`.

Root cause: Kotlin source was in `com/inrange/in_range/MainActivity.kt` (package com.inrange.in_range) while Gradle namespace + manifest relative name + applicationId used `com.example.in_range`.

Fix applied:
- MainActivity now lives at `android/app/src/main/kotlin/io/inrange/app/MainActivity.kt` with matching package/application ID.
- Removed mismatched source tree.
- Manifest already cleaned of legacy `package=` attr (was causing one assembleRelease failure).

Current: Fresh `flutter build apk --debug` running (after the fix). Release 48M APK was the one installed (crashes). Watcher on /tmp/build_watcher2.log.

Once new APK ready: install -r + launch should give working MainActivity. Then toggle beacon on device.

SDK/Gradle state good (compile/target 36, android-36 present, local.properties correct). KGP warning for ble_peripheral expected/ignored for now.

---

## Older monitoring notes (preserved)
- Flutter SDK download progress (tar size + curl count)
- Whether pubspec.lock exists
- Android folder status
- Connected devices
- Last lines from pub get and download logs

Created: 2026-07-07

## Handoff Update — 2026-07-08 (SDK Ready)

**Current Reality Check (verified):**
- Flutter SDK: **Ready** — `Flutter 3.44.5 • channel stable` reports cleanly. No more "Initializing".
- Download: Complete. Tarball gone. SDK extracted to `~/snap/flutter/common/flutter` (size ~2.3G in recent checks).
- No active aria2c/curl downloads.
- `pubspec.lock`: Present (37k).
- Android: Has `build.gradle.kts`, `src/`, and our pre-created `AndroidManifest.xml` (with BLE scan/advertise, background location, foreground service permissions).
- 4 Galaxy S9 (SM-G960U, Android 10) devices attached via adb (plus desktop/web).

**What Was Fixed / Done:**
- Switched from slow/flaky snap first-run to direct aria2c download for reliability.
- Killed interfering monitor loops (they were calling `flutter --version` and restarting the init/download).
- Created safe monitoring in `scripts/`:
  - `status.sh` — quick one-shot (safe, no flutter calls).
  - `monitor.sh` — live dashboard.
  - `start-persistent-monitors.sh` — launches nohup background updaters.
  - `inrange-watcher.sh` — writes to `/tmp/inrange_progress.txt` every 30s (file/dir checks only).
  - `GO.sh` + `go-when-ready.sh` — auto-run the full sequence when SDK ready.
- Pre-created full `AndroidManifest.xml` with required permissions.
- Beacon code skeleton improved (advertising with serviceData, scanning, stop logic, foreground trigger).
- `main.dart` has background service configuration.
- Range selector uses real plan values (`feet_10`, `miles_*` etc.).
- Dummy secrets in providers for early testing.
- Encounters repo now gracefully handles missing Supabase.

**Monitoring (Survives Agent Drops):**
Run these from **any terminal**:
```bash
bash scripts/status.sh                    # quick status
bash scripts/monitor.sh                   # live view
cat /tmp/inrange_progress.txt             # or watch -n 5 ...
tail -f /tmp/flutter_pub_get.log
bash scripts/start-persistent-monitors.sh # restart updaters if needed
```

**Next Steps to Complete (pick up here):**
1. (Optional but recommended) Re-run to ensure everything is fresh:
   ```bash
   export PATH="/snap/bin:$PATH"
   cd /home/hazypiff/in-range
   flutter pub get
   dart run build_runner build --delete-conflicting-outputs
   ```
2. Verify hardware:
   ```bash
   flutter devices
   ```
   You should see the 4 S9s.

3. Launch and test on a real phone (core goal — test beacon + encounters):
   ```bash
   flutter run -d 324c305855433498   # or any of the four device IDs
   ```
   - Grant location + Bluetooth permissions on the device.
   - Toggle beacon ON, select range.
   - Use two phones: turn both beacons on, get them within ~10-30 ft.
   - Watch for encounters appearing (photo + neighborhood only until match).

4. If you want fully automatic (waits for SDK if needed, then runs everything):
   ```bash
   nohup bash scripts/GO.sh > /tmp/go.log 2>&1 &
   tail -f /tmp/go.log
   ```

**Known Gotchas / Notes:**
- Older monitor versions called `flutter --version` in loops — this was killing the download. Current scripts avoid this.
- First `flutter run` on Android will do a full Gradle build (can take a few minutes).
- Background BLE scanning requires the foreground service (we have the manifest + trigger code; test on-device).
- For full end-to-end: apply the Supabase migrations (`supabase/migrations/`) to a real project, add real auth secrets, and wire `.env`.
- If Flutter ever complains about "working copy" or re-inits, just wait or re-run `flutter --version` once.
- Java may be needed for full Android Gradle on some hosts (install openjdk-11-jdk if `assembleRelease` fails).

**Files of Note:**
- `scripts/GO.sh` and `scripts/go-when-ready.sh` — the automation.
- `scripts/monitor.sh` + `status.sh` — your daily drivers for status.
- `android/app/src/main/AndroidManifest.xml` (and .bak) — critical permissions.
- `lib/features/beacon/` — the heart of the app.

**If you hit issues:**
- Run `bash scripts/status.sh` first.
- Check the /tmp/ logs.
- Re-run `start-persistent-monitors.sh`.
- The 4 S9s are the best test hardware — use at least two for mutual encounters.

Pick up from "Launch and test on device". The environment is ready. Good luck — let's get real encounters flowing.

**End of Handoff**
