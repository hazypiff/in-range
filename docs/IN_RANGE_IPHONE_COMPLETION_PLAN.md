# In Range — iPhone Beacon Completion Plan

**Date:** 2026-07-25  
**Audit base:** `in-range` @ `bd0787e` (`main`), freeze `calib-freeze-2026-07-24b` → `1a41d59`  
**Goal:** Get the iPhone side to behave like an *active* beacon — or, where iOS platform limits make that impossible, honestly supplement BLE with GPS and WiFi assists so the product still detects encounters reliably.

This document is a handoff: it assumes the reader has the repo, can build Flutter, and will own the iOS native work. Everything below is grounded in the actual files on disk, not aspirational architecture.

---

## 1. Honest current state

### What is already wired and working

| Piece | Status | Evidence in repo |
|---|---|---|
| Android advertise + scan + foreground service | Production shape, mostly done | `android/app/src/main/AndroidManifest.xml`, `lib/features/beacon/beacon_service.dart` Android branch |
| Android native GATT token read (W3) | Shipped | `android/app/src/main/kotlin/io/inrange/app/GattTokenReader.kt`, `lib/features/beacon/gatt_token_reader.dart` |
| iOS native locked-phone BLE carrier (W2/W4) | Shipped | `ios/Runner/BackgroundBeacon.swift`, `lib/features/beacon/background_beacon_channel.dart` |
| Mixed-pair advert path (W1) | Shipped | `beacon_service.dart` advertises `0xCAFE` service UUID + mfg data; scan filters Apple `0x004C/0x01` |
| Calibration data pipeline | End-to-end consistent | `local_db.dart` → `rssi_uploader.dart` → `RssiUploadService` → `record_rssi_batch` (migration `0056`) |
| Walk extraction + training | Consistent, fail-safe | `scripts/extract_walk.py`, `learn/ingest.py`, `learn/train.py` |
| Late-evidence server tolerance | Shipped | migration `0053_late_evidence_tolerance.sql` |

### What is *not* true yet

1. **There is no connected-RSSI instrumentation.** `readRSSI` / `connected_rssi` does not appear anywhere. The walk tomorrow measures advert-detection range, not persistent-GATT link quality. (`docs/IOS_BACKGROUND_BLE_WIRING.md` W5 is unbuilt.)
2. **A locked iPhone can never report `med_n`.** `BackgroundBeaconChannel.onSighting` signature is `(token, rssi, at)` with no power field; `beacon_service.dart:60` hardcodes `AdvertPower.high` for every native sighting. `med_n` is a training feature; it will read 0 for the iPhone side.
3. **iPhone contributes no WiFi and no GPS to a walk.** `WifiScanner` calls `io.inrange.app/wifi`, which only exists in `MainActivity.kt` (Android). iOS has no platform implementation. `Geolocator` timers stop when the Flutter engine suspends; `LocationKeepalive` exists but is gated and explicitly *not* proven to help BLE.
4. **iOS background advertising is overflow-only.** CoreBluetooth moves the rotating token into the overflow area when locked. The iPhone is *discoverable* via GATT read, but it is not "actively broadcasting a rich beacon" the way Android is.
5. **Restoration callbacks are empty.** `BackgroundBeacon.swift` has restore identifiers, but `willRestoreState` on both central and peripheral does nothing. Any W5 persistent link will not survive eviction.
6. **No source-tagged observation envelope.** The estimator mixes advert RSSI, future connected RSSI, and future NI distance in one bucket. That is dangerous for training.
7. **Calibration upload is not deployed in the freeze.** Migration `0056` exists but the `07-24b` build does not include the uploader; USB is the source of truth for the 2026-07-25 walk.
8. **Background-location + Live Activity + NI consent paths are not built.** The Info.plist lacks `nearby-interaction`, `NSNearbyInteractionUsageDescription`, and `NSSupportsLiveActivities`.

---

## 2. Definition of "iPhone beacon active"

We will not pretend iOS can broadcast like Android. The honest definition is:

> An iPhone is "active" when, after a single foreground user action, it can both (a) be discovered by peers and (b) discover peers with useful proximity evidence while the screen is locked and black.

The evidence stack, ordered by **precision when available**, with **coverage** annotated so the common case isn't mistaken for the best case:

| Priority | Source | Precision | Coverage / caveats |
|---|---|---|---|
| 1 | **Nearby Interaction (UWB) distance** | Highest | Narrowest: no iPhone↔Android interop; requires UWB on both peers; body-worn envelope may fall short of far stations. Warm-session only. |
| 2 | **Persistent-GATT connected RSSI** | Medium | Widest practical fallback: covers Android↔iPhone and non-UWB iPhones. This is the common-case workhorse. |
| 3 | **Advertisement RSSI** | Low | Current baseline; coarse and sparse when locked, but universal. |
| 4 | **GPS + WiFi assists** | N/A | Candidate pruning / venue corroboration only; never a distance classifier. |

Cold discovery of two dark iPhones with no prior session remains a documented platform boundary.

---

## 3. Strategic sequence

Do **not** try to land all of this at once. The sequence below protects the calibration dataset from mixing incompatible sampling regimes.

| Phase | Goal | Freezes code? | Approximate effort |
|---|---|---|---|
| **P0 — Freeze hygiene** | Capture the 2026-07-25 walk honestly; document what it does not measure | No client changes | 1 day |
| **P1 — Telemetry & platform guards** | Add source-tagged observations, iOS WiFi guard, connected-BSSID sampling, basic native logs | No behavior change when flags off | 2–3 days |
| **P2 — W5 warm-link BLE continuity** | Persistent GATT + `readRSSI()` on iOS and Android; reciprocal connection | New freeze required | 1–2 weeks |
| **P3a — W6 spike** | Bench Live Activity + Nearby Interaction + server-brokered delayed join before building production code | No shipped code | 3–5 days |
| **P3b — W6 active-session assist** | Only if spike passes 18/20 gate: Live Activity + NI + server broker + background Core Location | New freeze required | 2–3 weeks |
| **P4 — Fusion & retraining** | Train source-aware model only on post-W5/W6 walks | No client changes | 1–2 weeks |
| **P5 — Harden & ship** | Consent, App Review, production freeze, staged rollout | Release build | 1 week |

---

## 4. P0 — Freeze hygiene (do this first)

### 4.1 Do not touch the 2026-07-25 walk client

The phones must stay on `calib-freeze-2026-07-24b` (`1a41d59`). The host can stay on `main` for scripts.

### 4.2 Update `docs/WALK_PREFLIGHT_2026-07-25.md`

Add a new section after the Decision block:

```markdown
## What this walk does NOT measure

- **No connected-RSSI data.** The freeze has no `readRSSI()` loop. The walk measures advert detection range + token-recovery, not the range where a persistent GATT link dies.
- **No medium-power slot from the locked iPhone side.** Native iOS sightings arrive without a TX-power class, so `med_n` on the iPhone side is 0 by construction. Do not read it as "no medium packets arrived."
- **No WiFi or GPS from the iPhone side.** Venue score and GPS delta are None for the iPhone side. `train.py` skips missing features rather than imputing zeros.
```

### 4.3 Extraction command for tomorrow

Use the exact command from the preflight, but mark the walk `trainable` only after verifying the archive:

```bash
python3 scripts/extract_walk.py \
  run_logs/walks/2026-07-25-s22-iphone15p-locked/<S22_LOG>.threadtime.log.gz \
  run_logs/walks/2026-07-25-s22-iphone15p-locked/iphone15p.db \
  --stations-file run_logs/walks/2026-07-25-s22-iphone15p-locked/stations.json \
  --ios-date 2026-07-25 \
  --offset-a <S22_HOST_MINUS_DEVICE_S> \
  --trim 10 \
  --pair s22-iphone15p \
  --capture-meta run_logs/walks/2026-07-25-s22-iphone15p-locked/meta-pull.json \
  --freeze calib-freeze-2026-07-24b \
  --json run_logs/walks/2026-07-25-s22-iphone15p-locked/walk.json \
  --csv run_logs/walks/2026-07-25-s22-iphone15p-locked/walk.csv
```

Acceptance: the walk is archived; its JSON `meta.trainable` is set to `no` if any protocol failure occurred.

---

## 5. P1 — Telemetry & platform guards

These changes are additive and safe: they do not change BLE behavior when their flags are off.

### 5.1 Add a source-tagged observation envelope

Create a new model in `lib/features/beacon/proximity_observation.dart`:

```dart
enum ProximitySource {
  advertRssi,
  connectedRssi,
  nearbyInteraction,
  gpsGate,
  wifiVenue,
  bssidMatch,
}

class ProximityObservation {
  final String correlationId;
  final DateTime at;
  final ProximitySource source;
  final int? rssi;
  final double? distanceM;
  final double? horizontalAccuracyM;
  final String? localState;      // fg/bg/locked/live_activity
  final String? linkState;       // discovered/connecting/connected/subscribed
  final String? tokenSlot;
}
```

Refactor `RangeEstimator.addSample` to accept `ProximityObservation` rather than raw `(rssi, power)`. Keep the existing classifier behavior for advert-RSSI samples.

Files: `lib/features/beacon/range_estimator.dart`, `lib/features/beacon/beacon_service.dart`.

### 5.2 Guard `WifiScanner` on iOS

`lib/features/beacon/wifi_scanner.dart` currently invokes `io.inrange.app/wifi` unconditionally. On iOS this throws `MissingPluginException` repeatedly.

Change `_scanOnce` to:

```dart
if (defaultTargetPlatform == TargetPlatform.iOS) {
  debugPrint('WiFi scan: iOS has no scan API; using connected-BSSID assist only');
  return;
}
```

### 5.3 Add iOS connected-BSSID sampling (native spike)

Add a new method channel `io.inrange.app/wifi_ios` with one method: `currentBSSID()`.

Native iOS implementation (Swift):

```swift
import NetworkExtension

func currentBSSID(result: @escaping FlutterResult) {
    NEHotspotNetwork.fetchCurrent { network in
        guard let bssid = network?.bssid else {
            result(nil)
            return
        }
        result(["bssid": bssid, "ssid": network?.ssid ?? ""])
    }
}
```

Prerequisites:
- Add `Access WiFi Information` entitlement in Xcode.
- Precise location authorization must be granted (Apple runtime requirement).

Dart consumer: sample connected BSSID only when another callback (location/BLE/foreground) already provides runtime. Do not wake the app just for WiFi.

Files: `ios/Runner/AppDelegate.swift` or new `ios/Runner/WifiAssist.swift`, `lib/features/beacon/wifi_scanner.dart`.

### 5.4 Add native iOS background-location coordinator

The current Dart `LocationKeepalive` holds a location stream but discards fixes. Replace it with a native coordinator that:

1. Is started/stopped by the beacon toggle.
2. Uses `CLLocationUpdate.liveUpdates` where available, else `CLLocationManager`.
3. Persists fixes to a native ring buffer.
4. Bridges the buffer to Dart on foreground transitions.
5. Reports horizontal accuracy, timestamp, and stationary/moving state.

This is *not* for distance classification; it is for candidate pruning and runtime.

Files: `ios/Runner/BackgroundLocationCoordinator.swift`, `lib/features/beacon/location_keepalive.dart`.

### 5.5 Acceptance for P1

- [ ] `WifiScanner` no longer throws on iOS.
- [ ] A new debug line `WifiAssist bssid=...` appears in iOS logs when sampled.
- [ ] `LocationCoordinator` produces `LocationAssist lat=... lon=... acc=...` lines in calibration mode.
- [ ] Unit tests cover the observation envelope and source routing.
- [ ] No change to BLE advertising/scan behavior.

---

## 6. P2 — W5: warm-link BLE continuity

This is the most important build for Android↔iPhone reliability.

### 6.1 iOS side

In `ios/Runner/BackgroundBeacon.swift`:

1. Add a second characteristic `0xCA7F` to the `CAFE` service:
   - properties: `[.read, .write, .notify]`
   - permissions: `[.readable, .writeable]`
2. Implement `peripheralManager(_:central:didSubscribeTo:)` and `didUnsubscribeFrom`.
3. Implement `peripheralManager(_:didReceiveWrite:)` to accept a small wake frame and echo/notify subscribers.
4. Implement `peripheral(_:didReadRSSI:error:)` and emit source-tagged `connectedRssi` observations.
5. Maintain a per-peer state machine:
   - `discovered → connecting → connected → services → subscribed → active`
   - last wake / RSSI / token slot / backoff count
6. When an incoming central connects and writes, treat it as a signal to open a reciprocal central connection to that peer.
7. Queue notifications; handle `peripheralManagerIsReady(toUpdateSubscribers:)` retry.
8. Fill in `willRestoreState` for both central and peripheral.

### 6.2 Android side

Currently the Android advert is `connectable: false` and `GattTokenReader.kt` closes the GATT after each read.

1. Change the Android advert to `connectable: true` when W5 is enabled.
2. Add a GATT server in `MainActivity.kt` (or a dedicated service):
   - Service `CAFE`
   - Characteristics `CA7E` (read, dynamic token) and `CA7F` (write+notify, wake frame)
3. Retain `BluetoothGatt` client objects instead of closing after read.
4. Implement notification subscription, wake writes, and periodic `readRemoteRssi()` callbacks.
5. Add a bounded LRU of links (start with max 8) and exponential backoff.

Files: `android/app/src/main/kotlin/io/inrange/app/GattServer.kt` (new), `android/app/src/main/kotlin/io/inrange/app/GattTokenReader.kt`, `lib/features/beacon/beacon_service.dart`.

### 6.3 Dart glue

1. Extend `BackgroundBeaconChannel` to report connected-RSSI events and link-state changes.
2. In `BeaconService`, route W5 observations through the new observation envelope.
3. Add a feature flag `INRANGE_W5_LINKS=true` for bench builds.

### 6.4 Protocol constants (versioned)

```dart
class W5Constants {
  static const signalCharUuid = '0000ca7f-0000-1000-8000-00805f9b34fb';
  static const protocolVersion = 1;
  static const wakeFrameSize = 2; // version + seq
  static const defaultWakeCadenceMs = 4000; // to be tuned from power data
  static const maxConcurrentLinks = 8;
  static const reconnectBackoffBaseMs = 1000;
  static const reconnectBackoffMaxMs = 30000;
}
```

### 6.5 Acceptance for P2

Bench legs (real devices, locked/dark):

- [ ] S22 ↔ iPhone 15 Plus, warm link, both locked, 30 min → bilateral connected-RSSI samples.
- [ ] No 60-second silent gap during steady state.
- [ ] Token rotation while connected maps the link to the new slot.
- [ ] Walk out of range and back → bounded reconnect behavior.
- [ ] Bluetooth off/on and Airplane Mode labeled against TN3115 expectations.
- [ ] Process eviction/restoration behavior documented by termination category.
- [ ] Eight-hour stationary power/thermal soak completed.

---

## 7. P3 — W6: active-session assist (Live Activity + Nearby Interaction)

**Gate first, build second.** Research showed no iPhone↔Android UWB interop, the S22 likely has no UWB radio, and NI's realistic body-worn envelope falls short of the far stations. Do **not** schedule the production build until a small spike proves the delayed-join bench works. If the spike fails, skip P3b and invest more in W5 + venue anchors.

This is the path that can make iPhones feel "active" with UWB distance while dark.

### 7.1 Spike: minimal Live Activity + NI + server-brokered delayed join

Build the smallest throwaway version first:

1. Temporary widget extension + Info.plist entries in a branch.
2. Manual test endpoint on the server (or a hard-coded pair) to exchange `NIDiscoveryToken`s.
3. Run the delayed-join bench: Phone A dark 10 min, Phone B starts later, server attempts to deliver tokens without BLE discovery.
4. Accept only if 18/20 trials establish bilateral NI without foregrounding Phone A.

If the spike fails, document why and abandon P3b.

### 7.3 Production build: ActivityKit widget extension

Only after the spike passes:

1. In Xcode: File → New → Target → Widget Extension.
2. Add minimal Live Activity views:
   - "Finding nearby people…"
   - "Ranging with N nearby people"
   - "Bluetooth fallback"
   - "Paused — open In Range to resume"
3. Add `NSSupportsLiveActivities` to `ios/Runner/Info.plist`.
4. Add `nearby-interaction` to `UIBackgroundModes`.
5. Add `NSNearbyInteractionUsageDescription`.

### 7.4 Native coordinators

Create three Swift files:

- `ios/Runner/ActiveProximitySession.swift`
  - owns foreground start/stop, expiry timer, session restoration
- `ios/Runner/BackgroundLocationCoordinator.swift`
  - `CLLocationUpdate.liveUpdates` / `CLLocationManager`, candidate pruning input
- `ios/Runner/NearbyInteractionCoordinator.swift`
  - one `NISession` per candidate, source-tagged output

### 7.5 Server-brokered NI tokens

Add Supabase RPCs in a new migration `0057_active_proximity_sessions.sql`:

```sql
CREATE TABLE public.active_proximity_sessions (...);

CREATE OR REPLACE FUNCTION public.upsert_active_proximity_session(
  p_install_id TEXT,
  p_ni_discovery_token BYTEA,
  p_coarse_geo GEOGRAPHY,
  p_venue_id TEXT DEFAULT NULL,
  p_ttl_minutes INT DEFAULT 30
) RETURNS UUID ...;

CREATE OR REPLACE FUNCTION public.get_eligible_ni_candidates(
  p_session_id UUID,
  p_max_candidates INT DEFAULT 4
) RETURNS TABLE (opaque_peer_id TEXT, discovery_token BYTEA, capabilities TEXT) ...;

CREATE OR REPLACE FUNCTION public.end_active_proximity_session(
  p_session_id UUID
) RETURNS VOID ...;
```

Rules enforced server-side:
- mutual proximity/location consent
- block/safety/age/eligibility
- GPS uncertainty overlap or venue match
- candidate cap
- short TTL
- no raw coordinates exposed to peers

### 7.6 Dart session API

Add `lib/features/beacon/active_proximity_session.dart`:

```dart
class ActiveProximitySession {
  Future<void> start();
  Future<void> stop();
  Stream<ProximityObservation> get observations;
}
```

This is invoked from the Beacon toggle or a separate "Start In Range" UX.

### 7.7 Acceptance for P3

**Spike gate (must pass before any production build):**

- [ ] 18/20 delayed-join trials succeed: Phone A dark 10 min, Phone B starts later, server brokers token, A ranges B without foregrounding.
- [ ] One-sided vs two-sided Live Activity behavior documented.
- [ ] Median and p95 time-to-first-NI update recorded.

**Production build acceptance (only if spike passes):**

- [ ] Repeatable background NI updates while dark after a warm handshake.
- [ ] 1/2/4/8 candidate sessions; record `activeSessionsLimitExceeded`.
- [ ] Walk out of NI range and back; W5 fallback transition visible.
- [ ] Network loss, Focus, Bluetooth toggles, memory pressure labeled.
- [ ] Two-hour power/thermal soak.

---

## 8. P4 — Fusion & retraining

Do not retrain on pre-W5 walks mixed with post-W5 walks. They are different sampling regimes.

### 8.1 New feature schema

Extend `learn/train.py` `FEATURES` to include source flags, but keep missing-value semantics:

```python
FEATURES = [
    "high_med", "iqr_w", "rate", "high_n", "med_n",
    "venue_v", "gps_delta",
    "has_connected_rssi", "connected_rssi_med",
    "has_ni_distance", "ni_distance_med",
    "has_bssid_match",
]
```

`train.py` already skips `None` features; preserve that.

### 8.2 Walk regime tagging

In `extract_walk.py` output, add:

```json
"meta": {
  "sampling_regime": "advert-only|w5-ble|w6-ni",
  "has_wifi": bool,
  "has_gps": bool,
  "has_connected_rssi": bool,
  "has_ni": bool
}
```

### 8.3 Ingest rules

In `learn/ingest.py`:

- Refuse to mix regimes in one dataset unless `--allow-mixed-regimes` is passed.
- Default `--body-position product` remains.
- Add `source_aware` feature flags.

### 8.4 Acceptance for P4

- [ ] A model trained only on W5+W6 walks beats the `rules_iphone` baseline in leave-one-walk-out CV.
- [ ] No dangerous `close ↔ inrange` errors increase vs baseline.
- [ ] Model artifact includes `sampling_regime` and refuses to load on mismatched regime.

---

## 9. P5 — Harden & ship

### 9.1 Consent & privacy

Before enabling W6 for users:

- [ ] Add consent record for `active_proximity_session` (reuses `public.consent_records` from migration `0040`).
- [ ] Add data-retention and export handling for `active_proximity_sessions` and NI tokens in `scrub_account_pii` / `export_my_data`.
- [ ] Privacy policy section for Live Activity, UWB, background location, and BLE.
- [ ] Never turn on `rssi_samples` uploads for production users; keep `INRANGE_CALIB_SCAN` lab-only.

### 9.2 App Review package

Prepare:

- Video demo of the "Start In Range" session + Live Activity.
- Explanation of why `bluetooth-central`, `bluetooth-peripheral`, `location`, `nearby-interaction`, `processing`, and Live Activity are required.
- Battery/thermal test summary.

### 9.3 Production freeze

Create `calib-freeze-2026-08-xx` after W5/W6 land and have been bench-tested. Do not reuse `07-24b` data for training post-W5 models.

---

## 10. Immediate next actions for the next agent

1. ~~Read `docs/WALK_PREFLIGHT_2026-07-25.md` and add the "What this walk does NOT measure" section.~~ (Done in `e551626`.)
2. Do **not** modify `lib/` or native code before the 2026-07-25 walk is extracted.
3. After the walk is archived, branch from `main` for `feature/w5-warm-links`.
4. Start P1: create `ProximityObservation`, guard `WifiScanner`, add `WifiAssist`.
5. Land P1 behind flags; merge only when tests pass and a desk smoke shows no BLE regression.
6. Then begin P2 (W5) before P3; W5 is required fallback for non-UWB devices.
7. Run the P3a W6 spike **before** scheduling P3b production work. If the 18/20 delayed-join gate fails, drop P3b and double down on W5 + venue anchors.

---

## 11. File map for the work

| File | Role |
|---|---|
| `lib/features/beacon/beacon_service.dart` | Main BLE orchestrator; add W5/W6 observation routing |
| `lib/features/beacon/range_estimator.dart` | Classifier; consume source-tagged observations |
| `lib/features/beacon/proximity_classifier.dart` | Model loader; ensure regime mismatch fails closed |
| `lib/features/beacon/background_beacon_channel.dart` | iOS native bridge; extend for link state + connected RSSI |
| `lib/features/beacon/wifi_scanner.dart` | iOS guard + connected-BSSID consumer |
| `lib/features/beacon/location_keepalive.dart` | Replace with native background-location coordinator |
| `ios/Runner/BackgroundBeacon.swift` | W2/W4 native module; add CA7F, readRSSI, restoration |
| `ios/Runner/AppDelegate.swift` | Boot persistence; attach new coordinators |
| `ios/Runner/Info.plist` | Add Live Activity, NI, usage strings |
| `ios/Runner/BackgroundLocationCoordinator.swift` | New: native iOS location session |
| `ios/Runner/NearbyInteractionCoordinator.swift` | New: NISession management |
| `ios/Runner/WifiAssist.swift` | New: connected-BSSID sampling |
| `android/app/src/main/kotlin/io/inrange/app/GattTokenReader.kt` | Convert to retained-link client |
| `android/app/src/main/kotlin/io/inrange/app/GattServer.kt` | New: Android GATT server for CAFE/CA7E/CA7F |
| `android/app/src/main/kotlin/io/inrange/app/MainActivity.kt` | Host GATT server channel |
| `android/app/src/main/AndroidManifest.xml` | Ensure connectable advert + GATT server permissions |
| `supabase/migrations/0057_active_proximity_sessions.sql` | New: NI session broker RPCs/tables |
| `scripts/extract_walk.py` | Add regime tags |
| `learn/ingest.py` | Regime-aware ingest |
| `learn/train.py` | Source-aware features |
| `docs/IN_RANGE_IPHONE_COMPLETION_PLAN.md` | This file |

---

## 12. Non-goals and traps

- Do not claim cold discovery of two dark iPhones without a session.
- Do not use `BGAppRefreshTask` as a discovery clock.
- Do not copy Herald's 2 s / 12 link constants as production values.
- Do not turn `rssi_samples` on for normal users.
- Do not mix pre-W5 and post-W5 walks in one training dataset.
- Do not present RSSI-derived metres as ground truth.
- Do not add AccessorySetupKit merely to regain relaunch behavior.

---

## 13. Notes on the two GitHub remotes

The local clone has two remotes:

- `hazypiff/in-range` (personal fork)
- `inrangeai/in-range` (canonical org repo)

`gh auth status` confirms the token is present on this laptop. There is no separate backend repo in the accessible account list; backend migrations live in `supabase/` inside this repo. If a second private backend repo exists elsewhere, the server-brokered NI work (P3) needs its credentials before migration `0057` can be deployed.
