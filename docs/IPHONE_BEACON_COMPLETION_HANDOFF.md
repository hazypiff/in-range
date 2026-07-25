# iPhone Beacon — Completion Handoff

**Date:** 2026-07-25  
**Repo:** `in-range` (Flutter + iOS/Android)  
**Current HEAD:** `348f97e`  
**Remotes:** `hazypiff/in-range` and `inrangeai/in-range` both at `348f97e`  
**Author of this handoff:** Linux-side agent, after audit + hardening + build fixes

This document is the single source of truth for the next agent. It combines the strategic completion plan, the current tactical state, and the exact Mac/Xcode steps required before any further native iOS work can be trusted.

> **2026-07-25 update:** A code review found that `BackgroundLocationCoordinator.swift` and `WifiAssistPlugin.swift` were not in the Xcode target, and `NEHotspotNetwork.fetchCurrent` lacked the required iOS 14+ guard. Both files are now added to `project.pbxproj`, the availability guard is in place, and several logic bugs in the location coordinator are fixed. See §3.6.

---

## 1. The goal (still)

Get the iPhone side to behave like an *active* beacon — or, where iOS platform limits make that impossible, supplement BLE with GPS and WiFi assists so the product still detects encounters reliably while the iPhone is locked and black.

The honest definition of "active" for iOS:

> After a single foreground user action, the iPhone can (a) be discovered by peers and (b) discover peers with useful proximity evidence while the screen is locked and black.

---

## 2. What just happened (verified state)

### 2.1 Linux-side verification

Run from `/home/hazypiff/in-range`:

```bash
flutter test                    # +125, all passed
flutter analyze --no-fatal-infos # no issues
```

Both are clean as of this handoff.

### 2.2 Commits landed since the audit

| Commit | Message | What changed |
|---|---|---|
| `c1e60cd` | docs: commit iPhone completion plan with coverage annotation | `docs/IN_RANGE_IPHONE_COMPLETION_PLAN.md` — strategic plan, coverage column added |
| `274af10` | feat: guard WifiScanner on iOS | `lib/features/beacon/wifi_scanner.dart` — no-op on iOS instead of `MissingPluginException` spam |
| `c6569a9` | feat: source-tagged ProximityObservation envelope | `proximity_observation.dart`, `range_estimator.dart`, `beacon_service.dart`, tests |
| `5715018` | feat: iOS connected-BSSID assist (WifiAssist) | `wifi_assist.dart`, `WifiAssistPlugin.swift`, `AppDelegate.swift` |
| `92a22e3` | spike: native iOS background-location coordinator | `BackgroundLocationCoordinator.swift`, `location_keepalive.dart` |
| `106a619` | fix: native location coordinator was dead code in release builds | removed `BindingBase.debugBindingType()` guard |
| `3faec05` | ios: harden BackgroundLocationCoordinator for release/profile builds | iOS 14+ authorization delegate, class fallback for iOS 13 |
| `f91588f` | docs: update MAC_SETUP for WifiAssist + BackgroundLocationCoordinator capabilities | `docs/MAC_SETUP.md` |
| `8427ffb` | docs: handoff reflects 106a619 release bug + 3faec05 Swift hardening | `docs/IPHONE_BEACON_PROGRESS_HANDOFF.md` |
| `605b121` | docs: bump handoff HEAD | `docs/IPHONE_BEACON_PROGRESS_HANDOFF.md` |
| `7e327e2` | docs: sync handoff HEAD to current commit | `docs/IPHONE_BEACON_PROGRESS_HANDOFF.md` |

---

## 3. What is now wired

### 3.1 iOS WiFi scan guard

- File: `lib/features/beacon/wifi_scanner.dart:53`
- Behavior: on iOS, `_scanOnce()` returns immediately with a single debug line. Android behavior unchanged.
- Rationale: iOS has no public nearby-WiFi-scan API. Repeated `MissingPluginException` would only spam logs.

### 3.2 Source-tagged observation envelope

- File: `lib/features/beacon/proximity_observation.dart`
- `ProximitySource` enum: `advertRssi`, `connectedRssi`, `nearbyInteraction`, `gpsGate`, `wifiVenue`, `bssidMatch`.
- `RangeEstimator.addObservation()` is the single ingest point.
- **Live band decisions still use only `ProximitySource.advertRssi`.** Non-advert sources are retained but cannot silently change the product tier until calibrated.
- `BeaconService._ingestForeignSample()` routes native iOS sightings through the envelope with `localState: 'locked'`.
- Tests in `test/range_estimator_test.dart` prove non-advert observations are stored but do not affect classification.

### 3.3 iOS connected-BSSID assist

- Files:
  - `lib/features/beacon/wifi_assist.dart`
  - `ios/Runner/WifiAssistPlugin.swift`
  - `ios/Runner/AppDelegate.swift:23`
- Dart `WifiAssist.currentBSSID()` calls `io.inrange.app/wifi_assist`.
- Swift handler uses `NEHotspotNetwork.fetchCurrent` and returns `{"bssid": ..., "ssid": ...}`.
- Returns `null` on `MissingPluginException` so Android is unaffected.
- Returns `null` when Access WiFi Information entitlement or precise location auth is absent.
- **Not yet consumed by fusion.** See §6.2 P1b.

### 3.4 Native iOS background-location coordinator

- Files:
  - `ios/Runner/BackgroundLocationCoordinator.swift`
  - `lib/features/beacon/location_keepalive.dart`
  - `ios/Runner/AppDelegate.swift:26`
- Swift coordinator starts/stops a coarse `CLLocationManager` session while the beacon is on, persists fixes to a `UserDefaults` ring buffer, and exposes `start` / `stop` / `flush` on `io.inrange.app/location_coordinator`.
- `LocationKeepalive` prefers the native coordinator unconditionally; missing binding/plugin is caught and it falls back to the Dart `geolocator` stream.
- The previous `BindingBase.debugBindingType()` guard was removed because its backing field is assigned inside an `assert(() {...})` block — stripped in release/profile builds — so it silently disabled the coordinator on real devices.
- `BackgroundLocationCoordinator` implements both `locationManager(_:didChangeAuthorization:)` (iOS 13) and `locationManagerDidChangeAuthorization(_:)` (iOS 14+) so authorization grants actually start fixes on modern OS versions.
- `BeaconService` feeds every fix into the sighting cache via `locationKeepalive.onFix`.
- Entire path is gated by `INRANGE_LOCATION_RESIDENCY` (default off).

### 3.5 Build fixes from code review (2026-07-25)

A subsequent review found that the new Swift files were not actually in the Xcode target, and the location coordinator had several logic bugs that would strand or silently disable the feature.

**Xcode target membership**

- `BackgroundLocationCoordinator.swift` and `WifiAssistPlugin.swift` are now added to `ios/Runner.xcodeproj/project.pbxproj` in the `PBXBuildFile`, `PBXFileReference`, `PBXGroup`, and `PBXSourcesBuildPhase` sections.
- Without this, dropping the files into `ios/Runner/` did nothing — Xcode compiles only what is in the Sources build phase, and `AppDelegate.swift:23-27` would fail with `cannot find 'WifiAssistPlugin' in scope`.

**`WifiAssistPlugin.swift` fixes**

- `NEHotspotNetwork.fetchCurrent` requires iOS 14.0+; added `if #available(iOS 14.0, *)` guard with a `result(nil)` fallback for iOS 13.
- Removed invalid `?? ""` on non-optional `net.bssid` / `net.ssid`.
- Hopped to `DispatchQueue.main.async` before invoking `FlutterResult`, because the completion queue for `fetchCurrent` is undocumented.

**`BackgroundLocationCoordinator.swift` fixes**

- **Denied authorization no longer strands the session.** `start()` returns `false` for `.notDetermined` so Dart falls back to the gated permission flow; on `.denied` / `.restricted` it returns `false` immediately. `applyAuthorizationStatus` now tears the session down (`isRunning = false`, `locationManager = nil`) if authorization is revoked while running.
- **Buffered fixes are no longer destroyed before delivery is confirmed.** `appDidBecomeActive` now uses `peekBuffer()` and Dart acknowledges receipt by calling a new `clear` method. `drainBuffer()` is reserved for the Dart-initiated `flush` pull.
- **Removed the disclosure bypass.** `requestAlwaysAuthorization()` is no longer called from native code. Dart's `PermissionService.requestBackgroundLocation` owns the disclosure-gated request flow.
- **Removed the main-thread-blocking `CLLocationManager.locationServicesEnabled()` guard.** The authorization switch already covers the disabled case.
- **Fixed `moving` nil flattening.** `location.speed < 0` now yields `NSNull()` instead of `false`, so Dart sees `isMoving == null` as documented.
- Added `stop` / `clear` methods to the channel handler for full lifecycle control.

---

## 4. What is deliberately unchanged

- **Phones stay on freeze `calib-freeze-2026-07-24b` / `1a41d59`.** No client rebuild was done so the 2026-07-25 calibration walk is not disturbed.
- **`med_n` from a locked iPhone is still structurally `0`** because `BackgroundBeaconChannel.onSighting` carries no power slot. This is documented in the preflight, not fixed in code, because a client change would require a new freeze and cannot be measured before the walk.
- **No connected-RSSI (GATT) loop yet.** The range estimator can store the source, but no one produces `ProximitySource.connectedRssi` samples.
- **No UWB / Nearby Interaction integration yet.** P3a remains a spike gated on the delayed-join bench.
- **No `Access WiFi Information` entitlement file in the repo.** Xcode must add it to the provisioning profile (see §8.2).
- **No `nearby-interaction` background mode or `NSNearbyInteractionUsageDescription` yet.** These are only needed for P3.

---

## 5. Honest evidence stack

Ordered by **coverage** first, precision second — so the common case is not mistaken for the best case:

| Priority | Source | Coverage | Precision | Status |
|---|---|---|---|---|
| 1 | **Persistent-GATT connected RSSI** | Widest practical fallback: Android↔iPhone and non-UWB iPhones. This is the common-case workhorse. | Medium | Not built (W5) |
| 2 | **Advertisement RSSI** | Universal; current baseline. | Low | Shipped |
| 3 | **GPS + WiFi assists** | Candidate pruning / venue corroboration only; never a distance classifier. | N/A | Partially wired, not fused |
| 4 | **Nearby Interaction (UWB) distance** | Narrowest: no iPhone↔Android interop; requires UWB on both peers; body-worn envelope may fall short of far stations. Warm-session only. | Highest | Not built (W6 spike gated) |

---

## 6. Remaining work (in order)

### 6.1 P1b — Actually use the connected-BSSID assist

`WifiAssist.currentBSSID()` exists but is **not yet called** by the estimator or venue matcher.

Next steps:

1. Decide cadence: sample when another callback already provides runtime (BLE scan, location fix, foreground), not on a timer.
2. Hash the raw BSSID with the same rotating salt Android uses (see `VenueMatcher.hashed`).
3. Produce a `ProximityObservation(source: ProximitySource.bssidMatch)` only when the peer's hashed BSSID matches the local one.
4. Add a fusion rule: BSSID match can corroborate "same venue" but should not override BLE band decisions until calibrated.

Files: `lib/features/beacon/beacon_service.dart`, `lib/features/beacon/venue_matcher.dart`, `lib/features/beacon/wifi_assist.dart`.

### 6.2 P2 — W5 warm-link BLE continuity + `readRSSI()`

This is the most important build for Android↔iPhone reliability.

iOS side (`ios/Runner/BackgroundBeacon.swift`):
- Add second characteristic `0xCA7F` (read/write/notify) to the `CAFE` service.
- Implement subscribe/unsubscribe, write handling, wake frame, `peripheral(_:didReadRSSI:error:)`.
- Maintain per-peer state machine.
- Fill in `willRestoreState` for central and peripheral.

Android side:
- Change advert to `connectable: true` when W5 enabled.
- Add GATT server in `android/app/src/main/kotlin/io/inrange/app/`.
- Retain `BluetoothGatt` client objects; implement `readRemoteRssi()` loop.

Dart glue:
- Extend `BackgroundBeaconChannel` for connected-RSSI events and link-state changes.
- Route W5 observations through `RangeEstimator.addObservation()`.
- Add feature flag `INRANGE_W5_LINKS=true`.

### 6.3 P3a — W6 spike (Live Activity + Nearby Interaction)

**Gate first, build second.**

Research showed:
- No iPhone↔Android UWB interop.
- Base S22 likely has no UWB radio.
- NI's realistic body-worn envelope falls short of far stations.

Run the delayed-join bench first; only proceed if it hits 18/20.

### 6.4 P4 — Fusion & retraining

- Train source-aware model only on post-W5/W6 walks.
- `extract_walk.py` should tag regime.
- `learn/ingest.py` should refuse to mix regimes by default.

### 6.5 P5 — Harden & ship

- Consent records for active proximity sessions.
- Privacy policy updates.
- App Review package.
- Production freeze after W5/W6 are bench-tested.

---

## 7. Mac readiness checklist (do this before any further native work)

The Swift files have **never been compiled in Xcode on the Linux box**. `flutter test` and `flutter analyze` cover zero native code. A broken iOS build discovered on walk morning is a lost day.

### 7.1 Toolchain

1. Install Xcode from the App Store.
2. `xcode-select --install`
3. `sudo xcodebuild -license accept`
4. `brew install cocoapods`
5. Install Flutter 3.44.5 stable.
6. `flutter doctor` — clear any iOS-toolchain ✗.

### 7.2 Repo + secrets

1. `git clone` / `git pull` the repo.
2. Copy `.env` from the Linux box. It is gitignored and holds prod Supabase URL + key.
3. Verify `SUPABASE_URL=https://riigipzlyqeaadyvbuty.supabase.co`.

### 7.3 Xcode signing + capabilities

1. `open ios/Runner.xcworkspace` (the workspace, not the project).
2. Select **Runner** target → **Signing & Capabilities**.
3. Tick **Automatically manage signing**, pick your Team.
4. Add capabilities:
   - **Background Modes** → tick **Location updates** (BLE modes should already be set).
   - **Access WiFi Information** (needed by `WifiAssistPlugin.swift`).
5. Bundle id is `io.inrange.inRange`. Change if it collides.

### 7.4 Connect + trust the iPhone

1. Plug in iPhone, unlock, tap **Trust This Computer**.
2. `flutter devices` should list it.
3. After first install, trust the developer cert on the phone:
   **Settings → General → VPN & Device Management**.

### 7.5 First Mac build

```bash
bash scripts/build-install-ios.sh            # debug, live logs
bash scripts/build-install-ios.sh --release  # standalone, persists after unplug
```

**Do this immediately.** If `WifiAssistPlugin.swift` or `BackgroundLocationCoordinator.swift` has a syntax or API error, this is where it surfaces.

---

## 8. Component validation plan (Mac only)

After the build succeeds, validate each new native component before declaring the repo ready for field work.

### 8.1 `WifiAssistPlugin`

1. Build with `--release`.
2. Install on iPhone, grant **precise location** permission.
3. Connect to a Wi-Fi network.
4. Turn beacon on.
5. Look in logs for evidence that `WifiAssist.currentBSSID()` returns a real BSSID. There is no production log line yet; add a temporary debug call in `beacon_service.dart` or use a small test widget.
6. Expected: non-null BSSID string.
7. Toggle Wi-Fi off; expected: returns null.
8. Revoke precise location; expected: returns null.
9. Remove **Access WiFi Information** capability; expected: returns null or build fails.

### 8.2 `BackgroundLocationCoordinator`

1. Set `INRANGE_LOCATION_RESIDENCY=true` in `.env`.
2. Build with `--release`.
3. Turn beacon on, grant **Always** location authorization.
4. Lock the phone, wait 2–5 minutes, unlock.
5. Look for `LocationAssist lat=... lon=... acc=...` lines in logs (only in calibration mode or with `INRANGE_CALIB_SCAN=true`).
6. Expected: at least one buffered fix delivered via `onLocationFixes` after foregrounding.
7. With `INRANGE_CALIB_SCAN=false`, verify no coordinates are logged (privacy check).
8. Turn beacon off; verify location indicator disappears.

### 8.3 CoreBluetooth background advertising (existing W2/W4)

This is unchanged by recent commits, but re-validate because the Mac build is new:

1. Build `--release`.
2. iPhone locked and dark, Android peer scanning.
3. Verify Android sees `0xCAFE` marker or succeeds in GATT read.
4. Unlock iPhone; verify buffered sightings flush to Dart.

---

## 9. What the 2026-07-25 walk produces

The walk is today. Do not rebuild the freeze phone build or change advert power handling until after the data is captured.

Honest deliverables:
- A real, trainable advert-detection curve for S22 ↔ locked iPhone.
- Six distances × two body positions.

What it does **not** measure:
- No connected-RSSI data.
- No medium-power slot from the locked iPhone side (`med_n` is structurally 0).
- No WiFi or GPS from the iPhone side.

---

## 10. Immediate next actions for the next agent

1. On a Mac, run `bash scripts/build-install-ios.sh` and fix any Swift compilation errors.
2. Add **Access WiFi Information** and **Location Updates** capabilities in Xcode if not already present.
3. Validate `WifiAssistPlugin` and `BackgroundLocationCoordinator` per §8.
4. Run `flutter test` and `flutter analyze --no-fatal-infos` before committing.
5. Do **not** rebuild the freeze phone build or change advert power handling until after the 2026-07-25 walk data is captured.
6. After the walk, branch from `main` for `feature/w5-warm-links`.
7. Implement P1b (BSSID sampling into fusion) before W5.
8. Implement W5 before any P3b production work.
9. Run the P3a W6 spike before scheduling P3b. If the 18/20 delayed-join gate fails, drop P3b and double down on W5 + venue anchors.

---

## 11. Risk register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `WifiAssistPlugin.swift` or `BackgroundLocationCoordinator.swift` has a compile/API error | High until built | Blocks all iOS work | Build in Xcode immediately on Mac |
| Access WiFi Information entitlement not provisioned correctly | Medium | `WifiAssist` always returns null | Add capability in Xcode, validate on device |
| Background location authorization denied or misbehaves | Medium | `LocationKeepalive` falls back to Dart stream, which suspends | Test locked-phone fix buffering |
| P3a NI spike fails the 18/20 gate | Medium-high | Wasted weeks if production code built first | Gate P3b behind spike result |
| Mixing pre-W5 and post-W5 walks in training | Medium | Model learns apples-and-oranges data | Enforce regime tags in `extract_walk.py` and `ingest.py` |
| Governance objection to coupling location to beacon toggle | Medium | P1.4 feature blocked | Document decision; keep flag default off |

---

## 12. File map

| File | Role |
|---|---|
| `lib/features/beacon/beacon_service.dart` | Main BLE orchestrator; add W5/W6 observation routing |
| `lib/features/beacon/range_estimator.dart` | Classifier; consumes source-tagged observations |
| `lib/features/beacon/proximity_observation.dart` | Source-tagged observation envelope |
| `lib/features/beacon/background_beacon_channel.dart` | iOS native bridge; extend for link state + connected RSSI |
| `lib/features/beacon/wifi_scanner.dart` | iOS guard; Android venue scanning |
| `lib/features/beacon/wifi_assist.dart` | Dart side of iOS connected-BSSID assist |
| `lib/features/beacon/venue_matcher.dart` | Venue fingerprint hashing + scoring |
| `lib/features/beacon/location_keepalive.dart` | Dart wrapper for native coordinator + Dart-stream fallback |
| `ios/Runner/BackgroundBeacon.swift` | W2/W4 native module; add CA7F, readRSSI, restoration |
| `ios/Runner/AppDelegate.swift` | Boot persistence; attach new coordinators |
| `ios/Runner/Info.plist` | Add Live Activity, NI, usage strings when P3 lands |
| `ios/Runner/BackgroundLocationCoordinator.swift` | Native iOS location session |
| `ios/Runner/WifiAssistPlugin.swift` | Native iOS connected-BSSID sampling |
| `android/app/src/main/kotlin/io/inrange/app/GattTokenReader.kt` | Convert to retained-link client for W5 |
| `android/app/src/main/kotlin/io/inrange/app/MainActivity.kt` | Host GATT server channel for W5 |
| `docs/IN_RANGE_IPHONE_COMPLETION_PLAN.md` | Strategic completion plan |
| `docs/MAC_SETUP.md` | Mac toolchain + signing steps |
| `docs/IPHONE_BEACON_PROGRESS_HANDOFF.md` | Prior progress summary |
| `docs/IPHONE_BEACON_COMPLETION_HANDOFF.md` | **This file** — current state + Mac readiness |

---

## 13. Notes on the two GitHub remotes

- `hazypiff/in-range` (personal fork)
- `origin` → `inrangeai/in-range` (canonical org repo)

Push to both:

```bash
git push hazypiff main
git push origin main
```

---

## 14. Verification log (copy this section forward)

```
2026-07-25 Linux agent:
  flutter test          → +125 passed
  flutter analyze       → no issues
  Swift compile (Xcode) → NOT RUN (no Mac available)
  Device test           → NOT RUN
  project.pbxproj       → BackgroundLocationCoordinator.swift and WifiAssistPlugin.swift added to Runner target
```
