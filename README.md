# In Range (Flutter + Supabase)

Real Encounters. Real Connections.

Location-based dating app using Bluetooth (feet) + GPS (miles) to surface only people you've physically crossed paths with.

## Current Status (2026-07-07)
- Phase 0 approved (Flutter + Supabase foundation)
- Supabase schema + PostGIS RPCs delivered (`supabase/migrations/0001_init.sql`)
- Flutter project skeleton prepared (no SDK required for file prep)
- See full research-backed plan: `../in-range-enhanced-plan-2026.md`

## Getting Started (once Flutter SDK is available)

```bash
cd in-range
flutter pub get

# For codegen (Riverpod + Freezed)
flutter pub run build_runner build --delete-conflicting-outputs
```

## Project Structure (matches enhanced plan)

```
in-range/
├── supabase/
│   └── migrations/
│       └── 0001_init.sql          # Profiles, token_claims, sightings, encounters, matches, messages + RPCs
├── lib/
│   ├── core/
│   │   ├── di/
│   │   ├── network/               # Supabase client wrapper
│   │   └── utils/
│   ├── features/
│   │   ├── auth/
│   │   ├── profile/
│   │   ├── beacon/                # Toggle, range, scanning service (foreground on Android)
│   │   ├── encounters/            # Swipe feed (photo + neighborhood only)
│   │   ├── matches/
│   │   ├── chat/
│   │   └── settings/
│   └── shared/
├── pubspec.yaml
└── README.md
```

## Key Phase 0 Deliverables Delivered
1. ✅ Supabase schema + PostGIS RPCs (`claim_token`, `record_sighting`, `correlate_encounter`, `get_my_encounters`)
2. (Next) Ephemeral token format spec
3. ✅ Flutter scaffold (pubspec with flutter_blue_plus, geolocator, supabase_flutter, riverpod, freezed + feature folders)

## Next (unblocked)
- Install Flutter SDK if needed (`snap install flutter` or tarball)
- `flutter pub get` + verify
- Implement ephemeral token spec + client claim logic
- Wire basic beacon service that calls the RPCs (test on Android device)

## Important Notes from Research
- Background BLE/GPS is best-effort (foreground service + notification on Android)
- Use rotating ephemeral tokens (see token spec when created)
- All correlation happens server-side via PostGIS for accuracy + privacy
- RLS policies are enabled — test with authenticated users

Run `supabase db reset` (local) or apply migration to start testing the backend foundation.
