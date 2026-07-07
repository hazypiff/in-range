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
