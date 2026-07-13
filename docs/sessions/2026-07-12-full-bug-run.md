# Session record — 2026-07-12: Full bug run + device verification + multi-phone test prep

Continue-from-here doc. Everything below was done and **verified live on the Galaxy S9
(SM-G960U, serial 5137455958483498)** unless noted. Laptop = Ubuntu, repo at
`/home/hazypiff/in-range`. The Pixel 4a (0A081JECB06627) is infra — **never provision it**.

## Bugs found & fixed (all committed to `main`, pushed)

| Commit | Bug | Fix | Verified |
|---|---|---|---|
| `96663ca` | `_DatePickerTile` referenced 3× but never defined (interrupted agent) → auth screen didn't compile | Widget added; native `showDatePicker` | ✅ on-device |
| `96663ca` | Profile screen DOB was a raw text field — phone number-pad has **no dash**, can't type `YYYY-MM-DD` | Read-only field + tap-to-pick calendar | ✅ on-device |
| `96663ca` | Beacon errors blamed "permissions" for config/crypto StateErrors | Real reason surfaced in `beacon_screen.dart` catch | ✅ |
| (ops, no code) | "Cloud connection unavailable" — migration `0019` (defines `backend_health`, `release_token`, security gates) was committed but **never applied** to live Supabase | `supabase db push` applied `0019` (CLI binary at `~/.local/share/supabase/`) | ✅ log: `Cloud bind OK anon=true` |
| `4392dad` | **Incognito desync**: free-tier `set_incognito` refusal still persisted `incognito=true` locally (prefs key shared with SafetyStore) → beacon silently blocked after restart | Cloud-gate-first in `AppSessionController.setIncognito` (mirrors `setPaused`) | ✅ both directions on-device |

**Key operational discovery:** on-device builds get **no secrets from `.env`** (file
isn't in the app sandbox; `String.fromEnvironment` is compile-time). Always build/run with:

```
flutter run|build apk --debug --dart-define-from-file=.env
```

Without it: `supabase=false`, local/offline mode, beacon refuses (crypto secrets missing).

## Full user flow walked on the S9 (all passing)

Fresh install (`pm clear`) → onboarding 4 pages → real permission dialogs
(while-in-use → all-the-time, Android 10 two-step) → guest auth: **underage (2015)
rejected** at field + hard block `_assertAgeGate`; adult (2001) accepted → profile
setup: gallery photo picker, name, bio (counter), gender/pref dropdowns, interest
chips, save validation chain (name → photo required) → beacon **feet mode** (BLE
advertise + scan confirmed in logs) and **miles mode** (GPS ping + locals sync +
hybrid BLE) → Encounters/Locals/Msgs tabs (correct empty states) → Settings
(backend status accurate, pause/incognito toggles).

Server-side gates confirmed working as designed for guests (42501s are intentional):
- `claim_token` / `record_location_ping`: "Complete age and photo verification…"
- `set_incognito` enable: "Subscription required" (disable is allowed — escape path)

Static: `flutter analyze` clean; all 8 tests pass.

## Known non-blocking improvements (not fixed)
- Auth screen: age-gate error text renders above "Or continue with", far from the
  guest button; stale error doesn't clear when the date becomes valid again.
- Auth screen nested scrollables: inner tab ListView swallows swipes.
- History screen never visually walked (no entry point exercised).
- `adb shell input text` can't type emoji (test-tooling note, not app bug).

## Multi-phone beacon calibration test — STAGED, waiting on phones

- **Monitor:** `scripts/beacon_monitor.sh` — streams every Android's flutter log
  (Pixel hard-excluded), filters beacon/sighting lines, combined + per-device logs
  under `run_logs/beacon_test/`. Calibration signal = `Sighting observed rssi=-XX`.
  NOTE: app records raw RSSI but does **not** yet classify distance by RSSI — the
  10/20/30 ft chips are advertised claims. This walk produces the data to set
  real thresholds.
- **FGS build staged** (`--dart-define=INRANGE_ENABLE_FGS=true`) so BLE survives
  pockets/screen-off. Session copy at scratchpad `inrange-fgs.apk`; rebuild with
  the flag if lost.
- **Per-phone provisioning (scripted, ~3 min each):** install APK → `pm grant`
  location perms → guest profile named Phone-A/B/C/… → beacon ON 10 ft →
  `logcat -G 16M` so the whole walk buffers offline.
- **Walk protocol:** cluster 2 min → line 10 ft apart 2 min → pairs at 30 ft 2 min
  → two groups a block apart 3 min → merge 2 min. Note formation change times.
- **Extraction:** replug → pull logcat + SQLite sightings DB per phone → RSSI-vs-
  distance matrix → pick thresholds, flag scan stalls / rotation issues.
- Build has `ENCOUNTER_REVEAL_DELAY_HOURS=0` → encounters reveal instantly.

## iOS / iPhones — blocked on ONE user action

Everything code-side is DONE and pushed (`96663ca`):
- `ios/` scaffold, bundle id `io.inrange.app`, Info.plist permission strings +
  BLE/location background modes, Podfile (iOS 14, permission_handler macros)
- `.github/workflows/ios-build.yml` — unsigned IPA artifact on `macos-latest`;
  repo Actions secrets already set (SUPABASE_URL/KEY, HMAC, USER_ID secrets)
- iPhones on the bench: iPhone 15 (`iPhone16,1`) iOS 26.5, UDID
  `00008130-0001641E34E1001C` (+ a second iPhone seen on USB). Pairing/inspection
  from Linux works via `pymobiledevice3` (venv in session scratchpad).

**Blocker:** GitHub Actions on the private repo fails at `startup_failure` with no
jobs created — account-level billing/entitlement (even a trivial ubuntu job won't
start; probe workflow `ci probe` is in the repo to re-test). Unblock = ONE of:
1. github.com → Settings → Billing: add payment method + small spending limit, or
2. make `hazypiff/in-range` public, or
3. free Codemagic account (500 macOS min/mo) connected to the repo.

Then: run `ci probe` → green → `gh workflow run "iOS build"` → IPA artifact →
sign/sideload with the owner's Apple ID (free 7-day cert) → install from this
laptop. iCloud login on the iPhones alone does NOT unblock step 1.

## Account / sharing state
- `inrangeai` invited as collaborator (write) on `hazypiff/in-range`; invite id
  `325443134` — accept at github.com/hazypiff/in-range/invitations while logged
  in as inrangeai. The fine-grained `inrangeai` PAT floating around is
  **metadata read-only** — it cannot push or accept invites; rotate it.
- Supabase project `riigipzlyqeaadyvbuty` linked; access token in repo-root
  `.supabase_access_token` (gitignored); migrations 0001–0019 all applied.

## Fastest resume checklist
1. Plug Androids (USB debugging ON, accept prompt) — S9 already provisioned.
2. `bash scripts/beacon_monitor.sh` → walk protocol above → replug → extract.
3. Fix GitHub billing → `gh workflow run "ci probe"` → then "iOS build".
4. Delete `.github/workflows/ci-probe.yml` once Actions is confirmed working.
