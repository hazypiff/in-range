# Device Testing Journal — iPhone vs Android

Running comparison log for proximity testing across platforms. One entry per
test session on either platform; keep entries short and comparable. Raw data
stays in `run_logs/`; this journal is for observations and cross-platform
deltas that affect the algorithm.

## Device / rig matrix

| | iOS rig | Android rig |
|---|---|---|
| Dev machine | Arti's MacBook Pro (Tahoe 26.5.2, Flutter 3.44.6, Xcode 26.5) | hazypiff's Dell (Linux) |
| Test device | iPhone 14 (iPhone14,7), iOS 26.5.2 | (fill in: Galaxy S9 lab device + others) |
| Deploy | `flutter run` via USB; free-team signing (**re-deploy every 7 days**) | adb / `flutter run` |
| Log capture | `flutter run` console; Xcode devices window | `adb logcat` (rtk-filtered, ~86% compressed) |
| First deployed | 2026-07-15 (In Range 0.1.0, build 1) | (predates journal — walks #1–4) |

## Known platform differences to test around (BLE proximity)

These are *expected* asymmetries — log entries should confirm/quantify them,
not rediscover them:

1. **Background advertising**: iOS moves service UUIDs to the "overflow area"
   when backgrounded — other iPhones can only see it via specific scan modes;
   Android scanners may not see backgrounded iPhones at all. Android keeps
   advertising via foreground service. → test all 4 pairings (iOS↔iOS,
   iOS↔Android, Android↔iOS fg/bg).
2. **Scan throttling**: iOS coalesces/throttles duplicate advertisements in
   background; Android (with fg service) delivers steadier RSSI streams.
   Sample-rate deltas will skew smoothing windows.
3. **RSSI calibration**: different radios/antennas — iPhone 14 vs Galaxy S9
   will need per-model TX-power/RSSI offsets. Never mix devices in one
   calibration curve.
4. **Permission UX**: iOS asks Bluetooth + location separately with our
   Info.plist strings; Android 12+ needs BLUETOOTH_SCAN/ADVERTISE runtime
   grants. Note any silent-denial states.
5. **7-day build expiry (iOS free signing)**: a "dead app" on walk day may
   just be an expired provisioning profile.

## Entry template

```
### YYYY-MM-DD — <short title>
- Platform(s): iOS / Android / cross
- Devices: <model, OS version, app build>
- Setup: <foreground/background, screen on/off, pocket/hand, distance protocol>
- What we did:
- Numbers: <RSSI ranges, detection latency, drop rate — or link to run_logs/>
- Platform delta observed:
- Action items:
```

---

## Entries

### 2026-07-15 — iOS rig online; first iPhone deployment
- Platform(s): iOS
- Devices: iPhone 14 (iOS 26.5.2), In Range 0.1.0+1 debug, free-team signed
- Setup: first install via USB from the Mac; fallback config (`.env.example`,
  no cloud) — local-only operation
- What we did: stood up the full iOS toolchain (Tahoe upgrade → Xcode 26.5 →
  CocoaPods 1.17) and deployed the first iOS build. Info.plist configured for
  BLE central+peripheral, location always, background modes
  (bluetooth-central, bluetooth-peripheral, location, processing).
- Numbers: n/a (bring-up session, no proximity data)
- Platform delta observed: n/a yet — iOS side has zero proximity data; all
  existing calibration (walks #1–4) is Android-only and does NOT transfer
  (see difference #3).
- Action items:
  - [ ] Copy real `.env` from the Dell so iPhone joins the cloud environment
  - [ ] First iOS↔Android detection smoke test (both foreground, 1 m apart)
  - [ ] Baseline RSSI-vs-distance sweep for iPhone 14 (repeat walk #4
        distances) before any cross-platform math
  - [ ] Decide on paid Apple Developer account before any multi-day walk
        (7-day expiry kills longer studies)

### 2026-07-17 — iPhone↔iPhone indoor bring-up + close-range findings
- Platform(s): iOS↔iOS (iPhone 14 + iPhone 15 Plus, both foreground service-UUID carrier)
- Setup: enclosed indoor room; stop-and-return method, beacon off between stations,
  90 s/station, per-station isolated by rssi_log id baseline.
- **Pipeline verified end-to-end**: both phones advertise (Mac CoreBluetooth
  scanner confirmed marker+token on both), mutual detection confirmed, rssi_log
  captures abundantly (1549 / 1137 rows in a 1–2 ft smoke test). RSSI=127 is a
  BLE "invalid" sentinel — filter `rssi < 0`.
- Readings (median, both directions agree within 1 dB):
  - 5 ft → **−73 dBm** (~1150 samples/dir)
  - 25 ft run 1 → **−63 dBm** (~2200 samples)
  - 25 ft run 2 → **−73 dBm** (~2100 samples)
- **KEY FINDING — RSSI is NOT distance-tracking at 5–25 ft indoors.** The same
  25 ft gave −63 then −73 on repeat (10 dB), and run-2 25 ft == 5 ft. Between-repeat
  variance ≈ between-distance variance ≈ within-station IQR (~8–10 dB). Multipath +
  phone orientation dominate over distance at this scale in an enclosed space.
  Confirms the qualitative-tier design; precise close-range feet are not
  recoverable indoors.
- **Method notes:** continuous back-to-back stations FAILED — a 4.5 min data gap
  showed screen-lock/backgrounding kills iOS advertising mid-walk. Stop-and-return
  with beacon-off-between is the reliable method. Auto-Lock must be Never (or
  screens kept awake). iOS advertising does NOT survive lock/background (payload →
  overflow area) — foreground-only prototype; production background needs the GATT
  carrier (IOS_CARRIER_DECISION §3).
- **Action:** close-range boundaries are unresolvable indoors. NEXT = outdoor
  high-distance sweep (docs/WALK_IPHONE_FIRST_PROTOCOL.md, high-distance section)
  to (1) find the phone↔phone detection ceiling and (2) test whether 60/100/200 ft
  separate — the data decides the tier boundaries. Far tier (201+) likely exceeds
  BLE range → may need GPS (the app's miles mode), TBD by the ceiling measurement.

### 2026-07-17 (afternoon) — outdoor iPhone↔iPhone distance sweep (CALIBRATION DONE)
- iPhone 14 + iPhone 15 Plus, outdoor line-of-sight, stop-and-return, beacon-on-
  only-at-station, 90 s each, isolated by rssi_log id baseline.
- Clean monotonic curve (median RSSI, both directions within ~2 dB):
  35 ft −77 · 65 ft −83 · 110 ft −89 · 150 ft −96 · 175 ft −90.
- **Calibrated tier cutoffs:** Close 0–75 = RSSI ≥ **−84**; Near 76–150 =
  **−85…−96**; In Range 151+ = **< −96** (integer-dBm bands; closer tier owns
  its cutoff, so −84 is Close, not Near). Written into PROXIMITY_TIERS.
- **BLE reaches past 151 ft** — 175 ft still 1,540 samples at −90, robust. So In
  Range 151+ is BLE, NOT GPS (earlier "dies at 150" was a contaminated reading:
  beacon turned on while phones were close → −34 burst + only 3 real 150 ft
  packets; redo with beacon-on-at-station gave the clean −96).
- **Distance-tracking zone is 35–110 ft** (monotonic). Past ~110 ft RSSI is noisy
  (150 ft −96 vs 175 ft −90 — station-to-station scatter 6–8 dB from
  multipath/orientation). Fine for QUALITATIVE tiers (UI shows tier name not
  feet); the Near/In-Range boundary is intentionally soft.
- **Method lessons:** (1) beacon must be turned on only AFTER reaching the station
  separated — a close-range setup burst contaminates the window. (2) Continuous
  back-to-back with one timestamp is unsliceable + screen-lock kills advertising;
  stop-and-return with id baselines is the reliable method. (3) Keep both phones
  same orientation/height every station (±20 dB otherwise). (4) rssi=127 = BLE
  invalid sentinel, filter rssi<0.
- **Beacon lag bug found + FIXED (commit pending):** the iPhone 14 beacon
  intermittently needed 2–3 toggle presses / errored after many on/off cycles.
  Root cause: the BLE-adapter-ready wait used adapterState.firstWhere (emits only
  on CHANGE) — if BT flipped to `on` between the check and subscribe, the event
  was missed and it spuriously timed out (6 s). Fixed: poll adapterStateNow
  (can't miss the transition) + 12 s window + one-shot auto-retry on transient
  not-ready, so no repeated pressing.

### 2026-07-23 — two-person real-carry sweep (iPhone↔iPhone) — TIERS LOCKED
- Platform(s): iOS↔iOS (iPhone 14 + iPhone 15 Plus), TWO people — each holds a
  phone, both mirror the protocol. Outdoor, origin phone at waist height.
- Method: 6 stations 25/65/90/130/175/200 ft; per station beacon ON → 45 s
  both in hand facing each other → 45 s both POCKETED → beacon OFF between
  stations (bursts self-delimit in rssi_log; no manual timestamps).
- Both directions agreed within 1 dB at every station. Pooled medians
  (hand / pocket): 25 ft −73/−67 · 65 −79/−74 · 90 −84/−90 · 130 −88/−90 ·
  175 −92/−98 (pocket nearly dead: 28 pkts) · 200 −89/−96.
- **Owner locked tier thresholds from the POCKET curve (deployment
  condition): Close By ≥ −82 · Near By −83…−93 · In Range < −93.** Set in
  `RulesClassifier.iphone()`; supersedes 2026-07-17's −84/−96 (single-person,
  in-hand).
- Method findings: (1) origin phone on/near the ground costs ~15 dB — waist
  height minimum, cost us one 25 ft redo; (2) grip beats fabric close-in
  (pocket read ~5 dB STRONGER than hand at 25/65 ft — antenna death-grip),
  flips past 90 ft as pocket height + body loss grow with range; (3) past
  ~130 ft RSSI stops tracking distance (−89…−98 band, multipath) — the
  qualitative In Range tier design is confirmed; (4) both-pocketed detection
  is sparse past ~175 ft = the tier's honest BLE ceiling; (5) one station's
  on-screen beacon error was a false alarm — the burst recorded fine on both
  phones; trust the DB pull over the red error line; (6) beacon failed once
  mid-session on the 14 after ~8 toggle cycles (CoreBluetooth wedge class) —
  resilience layer (auto re-arm + backoff + watchdog) queued as next client
  work alongside W2.

### 2026-07-23 (evening) — locked-phone carrier bench (W2/W4 verified)
- Desk test, iPhone 14 + 15 Plus ~2 ft apart, three rounds against rssi_log:
  1. Round 1 (discovery-chained scan restarts): both phones went silent ~5 s
     after beacon-on — restart-only-on-discovery deadlocks once duplicates
     are suppressed. Fixed with an 8 s scan-restart heartbeat + restarting
     the scan whenever a peer READS our token (that read = background
     execution time on the locked side).
  2. Round 2 (one phone locked): **continuous both directions** — foreground
     14 logged the locked 15 Plus in every 30 s bucket (2–5 samples/bucket,
     GATT connect-read path); the locked 15 Plus logged the 14 back within
     seconds of each read-wake.
  3. Round 3 (BOTH locked): zero samples on either side for 3 min — Apple's
     app-level ceiling, expected (wiring doc §5). Mitigations queued: W1/W3
     Android bridges, silent-push wake off Locals-area overlap, natural
     screen-wakes.
- Product takeaway: locked↔awake iPhone encounters now work end-to-end;
  locked↔locked needs an external wake source. GATT connect range vs advert
  range at walk distances still unmeasured (field regression pending).

### (add Android baseline summary here — hazypiff: link walks #1–4 data and
the S9 RSSI curve so the iOS sweep has a comparison target)
