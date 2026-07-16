# Walk protocol — iPhone ↔ iPhone calibration (session 1)

**Goal:** fill the `iPhone 14 → iPhone 14` row of the tier table
(`docs/PROXIMITY_TIERS.md`) with real RSSI-vs-distance data. **No Android
needed** — this session is fully self-contained on the two iPhones. Android is
added in a later session once hazypiff widens the Android scan filter to the
`0xCAFE` marker (see IOS_CARRIER_DECISION §7 / issue #1).

## What works today (hardware-verified 2026-07-16)

| Direction | This session |
|---|---|
| iPhone A → iPhone B | ✅ capture |
| iPhone B → iPhone A | ✅ capture (not symmetric — capture both) |
| Each iPhone self-baseline | ✅ |
| iPhone ↔ S9 | ⛔ later session (needs Android filter change) |

iOS advertising is a **foreground** prototype — keep **both apps open and
phones unlocked** the entire walk. Backgrounding moves the token to the iOS
overflow area and discovery degrades.

## Pre-walk setup

**Second iPhone (one-time):**
1. Plug into the Mac. `xcrun devicectl list devices` → note its device id.
2. Build + install (same as phone 1, swap the device id):
   ```sh
   cd ~/in-range
   flutter build ios --release \
     --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=... \
     --dart-define=INRANGE_USER_ID_SECRET=... --dart-define=INRANGE_HMAC_SECRET=... \
     --dart-define=ENCOUNTER_REVEAL_DELAY_HOURS=0 --dart-define=INRANGE_ENABLE_FGS=true \
     --dart-define=INRANGE_PREFER_SERVER=true --dart-define=INRANGE_CALIB_SCAN=true
   xcrun devicectl device install app --device <PHONE2_ID> build/ios/iphoneos/Runner.app
   ```
   (secrets are in `~/in-range/.env`; both phones MUST use the same secrets.)
3. On phone 2: Settings → General → VPN & Device Management → trust the dev
   cert. Launch the app; sign in / onboard.

**Both phones, every session:**
- Charged; Bluetooth ON (Control Center icon solid blue); Location = While
  Using granted; app open and **foreground**.
- Optional sanity: run `swiftc scratchpad/blescan.swift && ./blescan` with a
  phone's beacon on — confirms it's broadcasting `CAFE` + a 128-bit token.

## Step 0 — smoke test (DO THIS FIRST, ~90 s)

Both phones ~1 ft apart, beacons ON, foreground.
- Watch each phone's Encounters/Beacon screen: each should see the other
  (reveal delay is 0 in lab config).
- After ~60 s, pull one DB (command below) and confirm `rssi_log` has rows.
  **If the table is empty, stop — do not walk.** Something isn't logging.

## Step 1 — static distance sweep

Open outdoor line-of-sight, ≥250 ft. Both phones held at chest height,
screens on, apps foreground. Both advertise AND scan simultaneously, so one
pass captures BOTH directions (A→B and B→A).

Stations (ft): **5, 25, 50, 75, 100, 125, 150, 175, 200, 225, 250**
- 60 s dwell per station.
- **Record wall-clock arrive/leave time at each station** (photo of a watch,
  or a notes-app timestamp). The `rssi_log` rows are timestamped; station times
  are the only ground-truth distance labels — without them the log can't be
  sliced.
- Note per station whether detection happens at all (the far stations test
  where iPhone BLE stops reaching — expect a ceiling somewhere past ~150 ft).

## Step 2 — boundary dwell

Hold at **100 ft** and **200 ft** (the current tier edges), 3 min each,
foreground. Measures classification flicker → sizes the hysteresis band.

## Step 3 — extract both DBs

```sh
xcrun devicectl device copy from --device <PHONE1_ID> \
  --domain-type appDataContainer --domain-identifier io.inrange.inRange \
  --source Documents/in_range_local.db \
  --destination run_logs/sessions/2026MMDD_iphoneA.db
# repeat with <PHONE2_ID> → 2026MMDD_iphoneB.db
```

Per-station slice (fill from your recorded times):
```sql
SELECT power, COUNT(*), MIN(rssi), MAX(rssi), AVG(rssi)
FROM rssi_log
WHERE at_ms BETWEEN <station_start_ms> AND <station_end_ms>
GROUP BY power;
```
(iOS is high-power only — expect all rows `power='H'`.)

## Step 4 — analyze

Hand both DBs + the station time log back to Claude. Output:
- RSSI-vs-distance curve per direction (A→B, B→A), with spread per station.
- Where the curves separate cleanly → the real tier boundaries for the
  `iPhone 14 → iPhone 14` row (replaces the 100/200 ft guesses if data says so).
- The detection ceiling (last station with reliable rows).
- Journal entry in `docs/DEVICE_TESTING_JOURNAL.md`.

## Known caveats for this session
- Foreground-only: don't pocket the phones or lock them mid-station.
- No medium-power slot on iOS → no `feet_30`-style power gate; tiers lean on
  windowed RSSI alone. Expect the same "RSSI flattens past ~50 ft" effect the
  S9 showed — the far stations may not separate; that's data, not failure.
- Free-team signing expires 7 days after each build — rebuild if a phone's app
  stops launching.
