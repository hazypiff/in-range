# iPhone beacon progress handoff

## Snapshot

- **Repo**: `in-range` (Flutter + iOS/Android)
- **Branch**: `main`
- **Current HEAD**: `605b121` (`docs: bump handoff HEAD`)
- **Remotes**: both `hazypiff/in-range` and `inrangeai/in-range` are at `605b121`
- **Test status**: `flutter test` passes 125/125; `flutter analyze --no-fatal-infos` clean

This handoff covers what landed after the audit and the completion-plan commit, what is still open, and the recommended order for the next agent.

---

## What landed

### 1. Completion plan committed + coverage annotation

- **Commit**: `c1e60cd`
- **File**: `docs/IN_RANGE_IPHONE_COMPLETION_PLAN.md`
- Added a coverage column to the evidence-stack table so NI's narrow real-world coverage is visible and persistent-GATT RSSI is shown as the common case.
- Split W6 into P3a (spike/bench) and P3b (production build), with the 18/20 delayed-join gate before any production work.
- The P0 preflight edit (`e551626`) was already pushed by the other agent and documents what tomorrow's walk cannot measure.

### 2. iOS WiFi scan guard

- **Commit**: `274af10`
- **File**: `lib/features/beacon/wifi_scanner.dart`
- `_scanOnce()` now returns early on iOS instead of throwing `MissingPluginException` on the missing `io.inrange.app/wifi` channel.
- Android behavior is unchanged; iOS venue assist moves to the connected-BSSID path.

### 3. Source-tagged observation envelope

- **Commit**: `c6569a9`
- **Files**:
  - `lib/features/beacon/proximity_observation.dart` (new)
  - `lib/features/beacon/range_estimator.dart`
  - `lib/features/beacon/beacon_service.dart`
  - `test/range_estimator_test.dart`
- `ProximitySource` enum distinguishes advert RSSI, connected RSSI, UWB, GPS gate, WiFi venue, and BSSID match.
- `RangeEstimator.addObservation()` is the single ingest point; `addSample()` remains a backwards-compatible wrapper for advert RSSI.
- Live band decisions (`classify`, `_isNear`, `evidenceFor`) still use **only** `ProximitySource.advertRssi`, so no uncalibrated source can silently move the product tier.
- `BeaconService._ingestForeignSample()` routes every foreign advert through the envelope with `localState: 'locked'` on iOS and `'scan'` otherwise.
- Tests prove non-advert observations are retained but do not affect the live band.

### 4. iOS connected-BSSID assist (native + Dart)

- **Commit**: `5715018`
- **Files**:
  - `lib/features/beacon/wifi_assist.dart` (new)
  - `ios/Runner/WifiAssistPlugin.swift` (new)
  - `ios/Runner/AppDelegate.swift`
- Dart `WifiAssist.currentBSSID()` calls `io.inrange.app/wifi_assist` and returns null on `MissingPluginException` so Android is unaffected.
- Swift handler uses `NEHotspotNetwork.fetchCurrent` and returns `{"bssid": ..., "ssid": ...}`.
- Plugin is registered in `AppDelegate.didInitializeImplicitFlutterEngine`.
- Returns `null` when the Access WiFi Information entitlement or precise location auth is absent.

### 5. Native iOS background-location coordinator (P1.4)

- **Commits**: `92a22e3` (spike), `106a619` (release-build bug fix), plus Swift delegate hardening on `main`.
- **Files**:
  - `ios/Runner/BackgroundLocationCoordinator.swift` (new)
  - `ios/Runner/AppDelegate.swift`
  - `lib/features/beacon/location_keepalive.dart`
  - `lib/features/beacon/beacon_service.dart`
  - `test/location_coordinator_test.dart` (new)
- Swift coordinator starts/stops a coarse `CLLocationManager` session while the beacon is on, persists fixes to a UserDefaults ring buffer, and exposes `start` / `stop` / `flush` on `io.inrange.app/location_coordinator`.
- `LocationKeepalive` prefers the native coordinator unconditionally; a missing binding/plugin is caught and it falls back to the Dart `geolocator` stream. The previous `BindingBase.debugBindingType()` guard was removed in `106a619` because its backing field is assigned inside an assert block and is therefore `null` in release/profile builds — it silently disabled the coordinator on real devices.
- `BackgroundLocationCoordinator` implements both the iOS 13 `locationManager(_:didChangeAuthorization:)` and the iOS 14+ `locationManagerDidChangeAuthorization(_:)` delegate methods so authorization grants actually start fixes on modern OS versions.
- `BeaconService` feeds every fix into the sighting cache via `locationKeepalive.onFix`, so `_ensureLocationCache()` has fresh coordinates without a per-sighting Geolocator call.
- Live product behavior is unchanged; the entire path is still gated by `INRANGE_LOCATION_RESIDENCY` (default off).

---

## Verification run

```bash
cd /home/hazypiff/in-range
flutter test          # +125, all passed
flutter analyze --no-fatal-infos   # no issues
```

The Swift side has **not** been built in Xcode on this machine. Both `WifiAssistPlugin` (`NEHotspotNetwork.fetchCurrent`) and `BackgroundLocationCoordinator` (`CLLocationManager`) need a real iOS archive/TestFlight build to confirm entitlements and background behavior.

---

## What is deliberately unchanged

- **Phones stay on freeze `calib-freeze-2026-07-24b` / `1a41d59`** — no client rebuild was done so today's calibration walk is not disturbed.
- **`med_n` from a locked iPhone is still structurally `0`** because `BackgroundBeaconChannel.onSighting` carries no power slot. This is documented in the preflight, not fixed in code, because a client change would require a new freeze and cannot be measured before the walk.
- **No connected-RSSI (GATT) loop yet** — the range estimator can store the source, but no one produces `ProximitySource.connectedRssi` samples.
- **No UWB / Nearby Interaction integration yet** — P3a remains a spike gated on the delayed-join bench.

---

## Open work (in recommended order)

### P1b — Actually use the connected-BSSID assist

`WifiAssist.currentBSSID()` exists but is **not yet called** by the estimator or venue matcher. Next steps:

1. Decide cadence: sample when another callback already provides runtime (BLE scan, location, foreground), not on a timer.
2. Hash the raw BSSID with the same rotating salt Android uses (see `VenueMatcher`).
3. Produce a `ProximityObservation(source: ProximitySource.bssidMatch)` only when the peer's hashed BSSID matches the local one.
4. Add a fusion rule: BSSID match can corroborate "same venue" but should not override BLE band decisions until calibrated.

### W5 — Persistent-GATT warm links + `readRSSI()`

- The estimator envelope is ready for `ProximitySource.connectedRssi`.
- Implement a warm GATT path on both platforms, sample `readRSSI()` on the persistent link, and feed it through `addObservation()`.
- Calibrate before it influences the live band.

### P3a / W6 — Nearby Interaction + Live Activity spike

- Do **not** start production code.
- Run the delayed-join bench first; only proceed if it hits the 18/20 criterion.
- Then evaluate whether NI's body-worn envelope reaches the far stations and whether the S22 even has a UWB radio.

---

## If you continue from here

- [ ] `git pull` on `main`; confirm HEAD is `f91588f`.
- [ ] On a Mac, open `ios/Runner.xcworkspace` and run a device/archive build to validate:
  - **Access WiFi Information** entitlement for `WifiAssistPlugin`,
  - background location mode / usage strings for `BackgroundLocationCoordinator`.
- [ ] Verify `WifiAssist.currentBSSID()` returns real data when WiFi is on and precise location is granted.
- [ ] Verify `BackgroundLocationCoordinator` starts, persists fixes, and flushes them on foreground.
- [ ] Wire BSSID sampling into `VenueMatcher`/fusion (see open work P1b).
- [ ] Run `flutter test` and `flutter analyze` before committing.
- [ ] Do **not** rebuild the freeze phone build or change advert power handling until after the calibration walk data is captured.

---

## Known caveats

- `WifiAssistPlugin` reports the **raw** BSSID/SSID. The Dart class returns them raw; do not upload or log them without hashing.
- The Swift WiFi plugin does not wake the app; it only works when Dart already has runtime.
- `BackgroundLocationCoordinator` has not been run on a real device; validate background location authorization and that fixes survive a suspend/foreground cycle.
- No iOS build or entitlement verification has been done from this machine.
