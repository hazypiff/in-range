# iOS Screen-Off Proximity Fusion — Real-World Design

Date: 2026-07-24

Status: research/design; not implemented

Scope: getting useful iPhone proximity evidence after a user starts an explicit session and turns the screen off

This document answers a narrower question than the general BLE research:

> Can In Range combine several supported iPhone mechanisms to match nearby people while their screens are mostly off?

Yes, with an important boundary. There is no supported way for an ordinary app to silently perform arbitrary all-day sensor scans. There is, however, a credible **user-started active-session** design:

1. start one honest Live Activity;
2. receive background Core Location updates;
3. use the server to select eligible nearby candidates and exchange temporary Nearby Interaction discovery tokens;
4. use background NI for accurate relative distance;
5. use persistent BLE connected RSSI as fallback;
6. opportunistically add same-BSSID, motion, and venue-anchor evidence.

The key correction is that **BLE is not mandatory for exchanging NI discovery tokens**. Apple explicitly lists a custom server as a supported peer-discovery/handshake channel and suggests GPS coordinates for matching candidates.

## Executive decision

Build and bench this no-hardware path first:

```text
User taps “Start In Range” while foregrounded
                 │
                 ├── start visible Live Activity
                 ├── start native Core Location live updates
                 ├── create NISession + temporary discoveryToken
                 └── publish short-lived session/capability/location record
                                      │
                           server eligibility + coarse location gate
                                      │
                         exchange candidate NI discovery tokens
                                      │
                    one NISession per bounded candidate peer
                                      │
                 ┌────────────────────┴────────────────────┐
                 │                                         │
          NI distance/direction                     W5 connected RSSI
          preferred evidence                        fallback evidence
                 │                                         │
                 └──────── source-aware fusion ─────────────┘
```

This is not passive “always detect everybody.” Both users must have intentionally started an active session. After that single foreground action, the design is intended to function with both displays black.

## What changes from the earlier model

The earlier plan treated BLE discovery as the unavoidable first step for NI. Apple's current NI guidance is broader:

- discover/handshake with Core Bluetooth;
- use Multipeer Connectivity;
- use another local network;
- **or use a custom server, with GPS coordinates selecting candidate peers.**

That server path can bypass the both-dark BLE cold-discovery ceiling during an already-active session.

It does not bypass these requirements:

- each side still creates its own `NISession`;
- each discovery token is temporary and session-specific;
- both sides need the other side's token;
- the app needs background runtime to publish/fetch tokens and configure sessions;
- the devices must be within the NI operating envelope;
- iOS 18.4+ background peer ranging needs an active Live Activity and the NI background capability;
- concurrent-session limits vary by device and must be measured.

## The supported “combo effect”

### Layer 1 — Live Activity as the visible active-session contract

The user starts a bounded “In Range is active” session in the foreground. The Live Activity is not decoration; it is the visible contract that proximity and location work continue after the screen locks.

One Live Activity can support three distinct benefits:

1. **Core Location:** Apple's Core Location guidance describes a Live Activity as a way for live location updates to continue while the app is backgrounded.
2. **Nearby Interaction:** iOS 18.4+ officially supports background NI ranging with an active Live Activity.
3. **Core Bluetooth on iOS 26:** an Apple staff forum answer reports foreground-like scanning while the display is lit; normal background restrictions return when it is black. Treat this third benefit as uncontracted.

Use the Live Activity to show honest state:

```text
Finding nearby people…
Ranging with 2 nearby people
Bluetooth fallback
Paused — open In Range to resume
```

The session should expire automatically after a product-defined venue/event window rather than track indefinitely.

### Layer 2 — Core Location is a candidate gate and runtime source

The current Dart implementation requests one-shot fixes from timers. Those timers stop when the Flutter engine is suspended, so they do not form a locked-screen location layer.

Implement the active-session location path natively on iOS:

- `CLLocationUpdate.liveUpdates(...)` on supported releases, or a correctly configured `CLLocationManager` fallback;
- retain a `CLBackgroundActivitySession` when the Live Activity path is unavailable or when explicit background-session diagnostics are needed;
- configure background location from the foreground;
- use automatic stationary pause/resume and an appropriate distance filter;
- persist callbacks natively before bridging or uploading;
- record `horizontalAccuracy`, timestamp, motion/stationary state, and source diagnostics.

Core Location can keep an app in use in the background when configured for an explicit location session. That supplies execution opportunities to publish the local NI token and fetch a changed candidate set.

GPS is **not** the distance classifier. Treat it like this:

- clearly separated uncertainty circles: reject the candidate;
- overlapping uncertainty circles: candidate remains possible;
- same venue/check-in: stronger candidate prior;
- NI or connected BLE: confirm relative proximity.

Never convert two noisy GPS points directly into the 10/25/35/60-foot product tiers.

### Layer 3 — server-brokered Nearby Interaction

At session start, each authenticated installation creates an `NISession`, archives its `discoveryToken`, and publishes a short-lived record equivalent to:

```text
proximity_session_id
authenticated_user_id
installation_id
temporary_ni_discovery_token
ni_capabilities
coarse_location_or_server-side_distance_input
horizontal_accuracy_m
venue_id?
updated_at
expires_at
```

The server:

1. considers only users with the required proximity/location consent;
2. applies dating eligibility, safety/block, age, and visibility rules before token exchange;
3. limits candidates by venue or accuracy-aware GPS overlap;
4. returns opaque candidate handles plus temporary NI tokens;
5. never exposes another user's coordinates;
6. expires tokens and mappings with the NI/app session;
7. caps candidate fan-out.

Each client creates one `NISession` per returned candidate. Apple supports separate sessions for multiple objects, but the maximum concurrent count varies by hardware/platform and reports `activeSessionsLimitExceeded` when exceeded. Begin with a small server-selected set and benchmark 1, 2, 4, and 8.

This server path also improves privacy relative to open local discovery: the server can refuse to exchange NI tokens for blocked or ineligible pairs before either device ranges the other.

### Layer 4 — W5 connected BLE fallback

NI will not cover every phone, every range, or every body orientation. Keep W5:

- reciprocal persistent GATT links;
- wake write/notify loop;
- `CBPeripheral.readRSSI()` while connected;
- source-tagged bilateral RSSI;
- restoration and bounded reconnect state.

Use connected RSSI for:

- iPhones without UWB;
- Android ↔ iPhone;
- NI timeout/obstruction;
- distances outside ordinary NI range;
- continuity evidence when NI quality degrades.

Do not make connected RSSI a metric-distance substitute. It remains coarse evidence.

### Layer 5 — cheap opportunistic corroborators

#### Connected BSSID

iOS cannot scan nearby Wi-Fi access points, but `NEHotspotNetwork.fetchCurrent()` can return the current network's SSID/BSSID when the app:

- has the Access Wi-Fi Information entitlement; and
- satisfies Apple's runtime criteria, normally precise Core Location authorization for this app.

This is not a fingerprint and does not wake the app. Sample it when a location, BLE, or foreground callback already provides runtime.

Interpretation:

- same BSSID at similar time: useful same-access-point/venue evidence;
- different BSSID: weak or no negative evidence in multi-AP venues;
- missing/not connected: abstain.

Hash it with a rotating/session salt before upload. Raw BSSIDs are location fingerprints.

The current `WifiScanner` should also be platform-guarded so iOS does not repeatedly invoke a nonexistent channel and swallow `MissingPluginException`.

#### Motion history

Core Motion can return current or historical activity categories and pedometer data collected by the motion coprocessor. It does not locate another person and does not create general background runtime.

Useful features after another callback wakes the app:

- stationary/walking/running/vehicle state;
- steps or movement since the last sample;
- whether an RSSI transition occurred while the phone was stationary;
- adaptive sampling and hysteresis.

Core Location's own stationary signal may be enough for the first spike, avoiding another permission until motion proves incremental value.

#### Visible notification or Live Activity alert

A genuine candidate/venue alert may light the screen and create an iOS 26 Bluetooth discovery opportunity. Focus, Apple Watch routing, notification settings, and delivery policies make this an assist only. Never use repeated notifications as a hidden scheduling mechanism.

## The load-bearing bench question

The first spike must answer:

> Phone A started an In Range session and has been locked/dark for ten minutes. Phone B starts later. Can A receive a background location/runtime opportunity, fetch B's server-brokered NI token, start/configure a new NI session, and range B without A's display lighting?

Apple documents all of the component mechanisms, but this exact delayed-join composition needs device proof.

If the answer is yes, the server + location + Live Activity path closes the most important practical first-contact gap for active iOS sessions.

If the answer is no, the supported fallback is:

- prefetch the initial candidate set before locking;
- update it on later foreground/screen-lit opportunities;
- use a genuine visible alert for a newly eligible candidate;
- or use venue infrastructure to create a reliable wake/zone signal.

## Venue infrastructure option

If In Range controls or partners with venues, fixed infrastructure changes the problem from unstable phone-to-phone radio geometry to multiple known anchors.

### Option A — iBeacon entry/zone anchors

Deploy powered iBeacons with one app UUID and venue/zone major/minor values.

Benefits:

- iBeacon region monitoring is low power;
- entering a monitored region can launch/wake an authorized app;
- beacon identity provides a strong same-venue or same-zone fact;
- anchors advertise continuously and are not subject to an iPhone app's background advertising restrictions.

Limitations:

- region/ranging authorization and App Review/privacy cost;
- ranging reports broad immediate/near/far behavior, not dependable metric distance;
- entry events are not a continuous sampling clock;
- force-quit remains a boundary.

Use an entry event to refresh the server candidate set and NI tokens, not to infer that two people are within ten feet.

### Option B — multiple connectable BLE anchors

Place three or more connectable anchors with known positions around a venue. Each exposes a small notify characteristic. After initial discovery, the phone retains bounded connections and reads RSSI to each anchor while locked.

Each phone then emits an anchor vector:

```text
venue_id
timestamp
anchor_A_rssi
anchor_B_rssi
anchor_C_rssi
anchor_D_rssi?
```

Compare two users' vectors or classify venue zones from calibrated fingerprints. Do **not** use free-space path-loss trilateration indoors; body blockage and multipath invalidate it. Multiple stable anchors help because their positions, antennas, and transmit powers do not move.

This is the cheapest practical way to obtain more independent screen-off radio evidence in partner venues.

### Option C — UWB accessory anchors

Nearby Interaction supports paired third-party UWB accessories in the background. Fixed UWB accessories with known coordinates can provide substantially better anchor distance than BLE RSSI, at greater hardware, certification, and pairing cost.

Prototype only after the no-hardware NI broker proves the product flow.

### Future — DL-TDoA UWB anchors

Apple now documents Downlink Time-Difference-of-Arrival positioning:

- multiple synchronized IEEE 802.15.4z anchors;
- anchor coordinates and timing measurements delivered to the app;
- sub-meter positioning in a defined deployment area;
- relative or geodetic 3D coordinates.

This is the closest public Apple mechanism to real indoor positioning.

It is **not a current production plan**:

- on iOS 26 the DL-TDoA entitlement supports development and Ad Hoc builds only, not App Store or TestFlight distribution;
- Apple says iOS 27 removes the entitlement requirement, but the current API/hardware/deployment path remains a forward-looking validation item;
- background behavior for this exact configuration must be tested rather than inferred from peer NI.

Keep a small hardware discovery spike on the roadmap; do not block W5/W6 on it.

## Mechanisms that do not solve the problem

| Mechanism | Useful information | Screen-off verdict |
|---|---|---|
| iOS nearby Wi-Fi scan | AP fingerprint | No public API |
| Connected BSSID | Same current AP | Opportunistic only; no wake |
| Wi-Fi Aware, iOS 26 | Paired-device connection and link signal strength | Requires system pairing and existing runtime; not stranger discovery |
| Silent background push | Chance to fetch candidate data | Opportunistic and throttled; not correctness |
| `BGAppRefreshTask` | Deferred maintenance | System-scheduled; not a proximity clock |
| Core Motion | Movement/activity | Context only; does not locate peers |
| Barometer | Possible floor/altitude clue | No dependable continuous background path; calibration-heavy |
| Ambient audio correlation | Potential same-room evidence | Technically possible only with explicit mic recording; privacy and App Review cost are unacceptable for the default dating flow |
| Multipeer Connectivity | Local token exchange | No dependable general screen-off discovery |
| Wi-Fi Aware signal strength | Second-radio link evidence | Possible only after explicit pairing; does not grant runtime |
| Bluetooth Channel Sounding | Real BLE distance | iOS 27/iPhone 17+, paired accessories, foreground-only in Apple's current guidance |
| Location Push Service Extension | On-demand GPS while app is not running | Limited to explicitly approved person-to-person location sharing; post-match feature at most, not anonymous candidate discovery |

## Recommended evidence policy

Use signals according to what they can actually prove:

| Evidence | Role |
|---|---|
| Server venue/check-in | Candidate pool |
| GPS + horizontal accuracy | Far-away veto / candidate pruning |
| Same connected BSSID | Same-access-point corroboration |
| iBeacon venue/zone | Venue or zone presence |
| NI distance | Preferred relative-distance evidence |
| NI direction/quality | Confidence and UX, not required for a match |
| Connected bilateral RSSI | Coarse fallback and continuity |
| Multiple anchor RSSIs | Zone fingerprint, not metres |
| Motion/stationary state | Temporal model and sampling policy |

A match should require persistent evidence, not one sample:

```text
eligible pair
AND coarse location/venue overlap
AND (
      stable NI distance
      OR persistent bilateral connected-RSSI evidence
      OR same calibrated anchor zone with supporting BLE evidence
    )
AND no safety/block/consent veto
```

## Privacy and data handling

This design adds a more sensitive live data path than calibration uploads.

Required boundaries:

- explicit user-started active session;
- visible Live Activity and truthful location disclosure;
- mutual proximity/location consent before server token exchange;
- short session/token TTL;
- no peer receives another person's coordinates;
- server returns opaque candidate handles;
- coarse cells or transient server-side comparison instead of durable exact-location history where possible;
- automatic cleanup when the session ends;
- deletion/export/retention coverage before shipping;
- abuse/block rules applied before candidate token exchange;
- logs distinguish calibration from production and omit raw coordinates/BSSIDs in production.

`CLOUD_RSSI_UPLOAD_SPEC.md` remains a calibration-only transport. Do not turn its raw RSSI table on for production users as part of this work.

## Implementation sketch

Suggested native components:

```text
ios/Runner/ActiveProximitySession.swift
  owns foreground start/stop, expiry, and state restoration

ios/Runner/BackgroundLocationCoordinator.swift
  owns CLLocationUpdate / CLLocationManager callbacks and native buffering

ios/Runner/NearbyInteractionCoordinator.swift
  owns one bounded NISession per candidate and source-tagged output

ActivityKit widget extension
  renders session/ranging/fallback/paused state
```

Suggested server boundary:

```text
upsert_active_proximity_session(...)
get_eligible_ni_candidates(...)
end_active_proximity_session(...)
```

Do not expose the session table directly. Use authenticated RPCs that enforce consent, block/safety rules, expiry, install identity, geographic uncertainty, and candidate caps.

Suggested client observation envelope:

```text
timestamp
session_id
opaque_candidate_id
source = gps_gate | ni | connected_rssi | bssid_match | venue_anchor | motion
distance_m?
rssi_dbm?
horizontal_accuracy_m?
anchor_vector?
motion_state?
quality/confidence
app/screen/live_activity state
```

Keep the native buffer as the screen-off source of truth. Dart timers and an in-memory uploader are not sufficient.

## Bench plan

### Phase 1 — no-hardware broker

Use the current iPhone 14 and iPhone 15 Plus.

1. Start both active sessions in foreground; broker tokens through a manual test endpoint.
2. Lock both until both displays are black.
3. Verify location callbacks and NI updates for 30 minutes.
4. Repeat with Phone A dark for ten minutes before Phone B starts.
5. Verify A can receive/fetch B's token and start a new NI session without foregrounding.
6. Repeat with one and two Live Activities.
7. Test 1, 2, 4, and 8 candidate sessions and record `activeSessionsLimitExceeded`.
8. Walk out of NI range and back; verify W5/fallback transitions.
9. Test network loss, Focus, Bluetooth toggles, ordinary memory pressure, and user force-quit as separately labeled states.
10. Run a two-hour power/thermal soak.

Provisional delayed-join gate:

- at least 18 of 20 trials establish bilateral NI without foregrounding Phone A;
- report median and p95 time-to-first-NI update;
- no hidden dependence on a visible notification lighting the screen;
- every failure has a lifecycle/runtime reason in native logs.

### Phase 2 — opportunistic context

During the same callbacks:

- sample connected BSSID when authorized;
- record Core Location stationary state;
- compare GPS uncertainty-circle overlap with actual NI distance;
- quantify whether either feature reduces false candidate sessions.

Do not request Motion permission until Core Location's stationary signal has been evaluated.

### Phase 3 — cheap venue anchor pilot

Deploy three or four stable BLE anchors in one test room:

- keep positions and transmit settings fixed;
- collect front pocket, rear pocket, hand, bag, facing, and walking cases;
- train zone/fingerprint classification;
- compare one-anchor versus multi-anchor error;
- verify retained anchor connections and samples with the display black;
- measure whether anchor vectors separate adjacent zones better than bilateral RSSI alone.

### Phase 4 — future UWB anchors

Only after the no-hardware product flow and venue business case are proven:

- identify NI-compatible UWB accessory hardware;
- request/test the iOS 26 DL-TDoA development capability if useful;
- track iOS 27 production availability;
- benchmark anchor count, coverage, body blockage, power, and installation cost.

## Recommended execution order

1. Finish the current frozen baseline walk; do not alter its client.
2. Fix the iOS Wi-Fi platform guard in the next client freeze.
3. Build the smallest server-brokered NI + native background-location + Live Activity spike.
4. Bench the delayed-join case before building a production broker.
5. Build W5 connected BLE fallback/restoration.
6. Add connected-BSSID sampling only after the core spike works.
7. Decide whether partner-venue BLE anchors fit the business model.
8. Keep audio, Wi-Fi Aware, DL-TDoA, and Channel Sounding out of the critical path.

## Sources

### Apple — active background location

- [Handling location updates in the background](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background)
- [`CLLocationManager.allowsBackgroundLocationUpdates`](https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates)
- [`CLLocationUpdate`](https://developer.apple.com/documentation/corelocation/cllocationupdate)
- [WWDC23: Discover streamlined location updates](https://developer.apple.com/videos/play/wwdc2023/10180/)
- [Requesting authorization to use location services](https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services)

### Apple — Nearby Interaction and token transport

- [Nearby Interaction](https://developer.apple.com/documentation/nearbyinteraction)
- [Initiating and maintaining a session — Bluetooth, local network, or custom server using GPS](https://developer.apple.com/documentation/nearbyinteraction/initiating-and-maintaining-a-session)
- [`NISession` — one session per object](https://developer.apple.com/documentation/nearbyinteraction/nisession)
- [`activeSessionsLimitExceeded`](https://developer.apple.com/documentation/nearbyinteraction/nierror/code/activesessionslimitexceeded)
- [`NISession.discoveryToken`](https://developer.apple.com/documentation/nearbyinteraction/nisession/discoverytoken)

### Apple — venue and future radio options

- [Determining proximity to an iBeacon device](https://developer.apple.com/documentation/corelocation/determining-the-proximity-to-an-ibeacon-device)
- [Third-party UWB accessories](https://developer.apple.com/documentation/nearbyinteraction/ninearbyaccessoryconfiguration)
- [DL-TDoA ranging — sub-meter anchor positioning](https://developer.apple.com/documentation/nearbyinteraction/dl-tdoa-ranging)
- [iOS 26 DL-TDoA development entitlement limitation](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.nearbyinteraction.dltdoa)
- [Wi-Fi Aware](https://developer.apple.com/documentation/wifiaware)
- [Wi-Fi Aware path performance, including link signal strength](https://developer.apple.com/documentation/wifiaware/waperformancereport)
- [Bluetooth Channel Sounding requirements](https://developer.apple.com/documentation/corebluetooth/measuring-distance-between-devices-using-channel-sounding)

### Apple — supporting context and policy

- [`NEHotspotNetwork.fetchCurrent()`](https://developer.apple.com/documentation/networkextension/nehotspotnetwork/fetchcurrent%28completionhandler%3A%29)
- [`CMMotionActivityManager`](https://developer.apple.com/documentation/coremotion/cmmotionactivitymanager)
- [`CMPedometer`](https://developer.apple.com/documentation/coremotion/cmpedometer)
- [Location Push Service Extension constraints](https://developer.apple.com/documentation/corelocation/creating-a-location-push-service-extension)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

## Bottom line

The highest-value experiment is not “make iOS scan harder.” It is:

> Start one visible active session, keep Core Location and NI legitimately active, use the server to broker temporary NI tokens for a bounded eligible candidate set, and let UWB confirm proximity while both screens are black.

If delayed background candidate joins work on the bench, this is the best no-hardware iPhone-to-iPhone design available to the app. If they do not, fixed venue beacons/anchors are the next meaningful lever; more RSSI thresholds are not.
