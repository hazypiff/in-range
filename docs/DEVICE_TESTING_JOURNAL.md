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

### (add Android baseline summary here — hazypiff: link walks #1–4 data and
the S9 RSSI curve so the iOS sweep has a comparison target)
