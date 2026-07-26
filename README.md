# In Range (Flutter + Supabase)

Real Encounters. Real Connections.

Location-based dating app using Bluetooth (feet) + GPS (miles) to surface only
people you've physically crossed paths with.

## Start here

**[`docs/README.md`](docs/README.md) is the documentation index** — one line per
doc, grouped by architecture / walks + calibration / compliance / setup + ops /
research. Read that before opening anything else in `docs/`.

Fast paths for the three most common jobs:

| I'm here to… | Read |
|---|---|
| Run tomorrow's calibration walk | [`docs/WALK_PREFLIGHT_2026-07-25.md`](docs/WALK_PREFLIGHT_2026-07-25.md) |
| Continue the iPhone beacon work | [`docs/IPHONE_BEACON_COMPLETION_HANDOFF.md`](docs/IPHONE_BEACON_COMPLETION_HANDOFF.md) |
| Continue proximity-security ("#6") | [`docs/SECURITY_HANDOFF.md`](docs/SECURITY_HANDOFF.md) |

Settled platform/product decisions that should not be re-debated live in
[`docs/ARCHITECTURE_CONTRACTS.md`](docs/ARCHITECTURE_CONTRACTS.md) Part 0.

## Getting started

```bash
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs   # Riverpod + Freezed
flutter test
```

- Mac / iOS toolchain and signing: [`docs/MAC_SETUP.md`](docs/MAC_SETUP.md)
- Backend setup: [`docs/SUPABASE_SETUP.md`](docs/SUPABASE_SETUP.md)
- Migration ledger is `supabase/migrations/` — treat the directory as the
  authority for what has shipped, not a number quoted in prose.

Gate for any proximity-security change:
`bash supabase/tests/run_security_tests.sh`

## Project structure

```
in-range/
├── supabase/
│   ├── migrations/     # schema + PostGIS RPCs (0001_init.sql is the baseline)
│   ├── functions/      # Edge Functions
│   └── tests/          # security harness (the gate)
├── lib/
│   ├── core/           # config, db, di, network, notifications, permissions
│   ├── features/
│   │   ├── auth/  profile/
│   │   ├── beacon/     # advertise + scan, range estimation, tier classification
│   │   ├── encounters/ # swipe feed (photo + neighborhood only)
│   │   ├── matches/  chat/  settings/
│   └── shared/
├── ios/  android/  web/
├── learn/              # self-learning calibration loop (GNB trainer, registry)
├── scripts/            # build/install, walk capture + extraction
├── docs/               # see docs/README.md
└── test/
```

## Design notes that still hold

- Background BLE/GPS is **best-effort** (foreground service + notification on
  Android; on iOS see `docs/IOS_BACKGROUND_BLE_WIRING.md`).
- Rotating ephemeral tokens — `docs/ephemeral-token-spec.md`.
- Correlation happens **server-side** via PostGIS for accuracy + privacy.
- RLS is enabled — test with authenticated users.
- The UI shows a **tier name, never feet** (`docs/PROXIMITY_TIERS.md`).

Historical: an early research-backed plan lives **outside this repo** at
`../in-range-enhanced-plan-2026.md`.
