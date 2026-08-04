# iOS Proximity Upgrade — Research and Agent Handoff

Date: 2026-07-24  
Status: research complete; implementation not started  
Scope: cold discovery, background continuity, connected RSSI, Nearby Interaction, Live Activities, restoration, and validation

This document is the implementation handoff for the next proximity upgrade. It corrects several assumptions in the older iOS notes and turns the research into bounded work items and bench gates.

Related repository context:

- [`IOS_BACKGROUND_BLE_WIRING.md`](IOS_BACKGROUND_BLE_WIRING.md) — existing W1–W5 wiring/bench record; retain its measurements, but use this document's corrected carrier and lifecycle model.
- [`IOS_SCREEN_OFF_FUSION_2026-07-24.md`](IOS_SCREEN_OFF_FUSION_2026-07-24.md) — active-session design using background Core Location and server-brokered NI tokens, plus venue-anchor options.
- [`IOS_LOCATION_RESIDENCY_REVIEW_2026-07-24.md`](IOS_LOCATION_RESIDENCY_REVIEW_2026-07-24.md) — audit of commit `3d98316`; background location may keep app work runnable but does not remove Core Bluetooth background scan rules.
- [`PROXIMITY_ALGORITHM.md`](PROXIMITY_ALGORITHM.md) — existing fusion direction.
- [`PROXIMITY_TIERS.md`](PROXIMITY_TIERS.md) — provisional thresholds, not physical truth.
- [`CALIBRATION_FREEZE_2026-07-23.md`](CALIBRATION_FREEZE_2026-07-23.md) — current walk freeze and device-build preflight.

## Read this first

1. **Two iPhones that are already locked and dark still have no dependable cold-discovery path.** Our bench result — “both iPhones locked, no assists: silent” — remains the correct baseline.
2. **The iOS overflow area is not invisible to background iOS scanners.** An iOS scanner must explicitly request the service UUID; this app already does. Android can parse the raw Apple manufacturer data and is why the S22-to-locked-iPhone bridge works.
3. **Persistent GATT is a warm-link continuity mechanism, not a cold-discovery fix.** Once connected, wake writes/notifications can drive `readRSSI()` without waiting for another advertisement callback.
4. **Nearby Interaction (NI) plus a Live Activity is the best supported iOS-to-iOS continuity path on iOS 18.4+.** NI needs an out-of-band peer handshake, but BLE is only one option: Apple also supports a custom server and explicitly suggests GPS-based candidate matching. The server path may bypass BLE cold discovery during a user-started active session and is now a load-bearing bench spike.
5. **A Live Activity has a second benefit on iOS 26:** it gives Core Bluetooth foreground-like scanning while the app is backgrounded and the display is lit. Apple confirms that the normal background restrictions return when the Lock Screen goes fully black. This improves “user glances at phone,” not “both phones stay dark.”
6. **The current restoration setup is incomplete.** Restore identifiers are present, but both restoration callbacks are empty. W5 must not claim resilient persistent links until restored peripherals, delegates, subscriptions, and link state are reattached.
7. **Do not tune the current `-84` / `-96` dBm tier cutoffs first.** RSSI is coarse, body-dependent evidence. Preserve it for fallback/fusion; use NI distance where available.

## Evidence labels used below

- **Verified — Apple:** current or archived Apple documentation.
- **Verified — source:** inspected app or Herald source.
- **Bench:** result recorded by this project.
- **Historical lead:** a useful result from old Herald testing, not a current iOS guarantee.
- **Needs bench:** deliberately unresolved.

## Recommended work order

| Work item | Outcome | Priority |
|---|---|---|
| **W6 — NI + Live Activity spike** | Prove supported background UWB ranging and server-brokered active-session first contact on the current iPhone pair; also A/B test the iOS 26 Core Bluetooth Live Activity behavior | P0 spike |
| **W5 — warm-link BLE continuity** | Replace one-shot connect/read/disconnect with a bounded persistent GATT wake/notify/`readRSSI()` loop, including Android peripheral/server support | P0 build |
| **W8 — restoration and lifecycle hardening** | Make W5 survive ordinary suspension/eviction where Apple permits restoration, and report unsupported termination cases honestly | Required before W5 ships |
| **W7 — Core Location screen-lit assist** | Optional experiment for older iOS only if the Live Activity tests leave a real product gap | Defer |
| **RSSI/fusion calibration** | Train or calibrate from source-tagged field data after W5/W6; do not promote fixed RSSI thresholds to ground truth | After instrumentation |

W6 is listed first because it is a small, high-information spike and the same Live Activity can test both NI and iOS 26 Core Bluetooth behavior. W5 is still required for Android-to-iOS continuity, non-UWB devices, and fallback.

## Capability matrix

| Situation | Expected behavior | What solves it |
|---|---|---|
| Two iPhones, no active proximity session, no prior link, both screens dark | No dependable discovery | Nothing currently supported; state this as a platform boundary |
| Both iPhones started a Live Activity/location session, server brokers NI tokens, then both screens go dark | Potential active-session first contact without BLE discovery | W6 delayed-join bench; do not claim it until measured |
| Explicit UUID scan, iPhone backgrounded | Overflow UUID can be matched, but callbacks are coalesced/throttled | Current filter is correct; do not rely on callback cadence |
| Warm iOS BLE connection, both apps backgrounded | Connection events can wake apps; connected RSSI can be requested | W5, subject to lifecycle and power validation |
| iOS 18.4+ NI session, app enters background with Live Activity | NI ranging may continue in background | W6 |
| iOS 26 Core Bluetooth + Live Activity, Lock Screen lit | Foreground-like scan behavior, including unfiltered scanning/duplicate delivery | W6 A/B test |
| iOS 26 Core Bluetooth + Live Activity, Lock Screen black | Normal background scan limits return | No cold-discovery fix |
| Android scanning locked iPhone overflow advertisement | Android can parse the raw manufacturer payload | Existing S22 bridge |
| Fictional iBeacon region/ranging assist | May create screen-lit opportunities in old Herald design | W7 only; undocumented and review-sensitive |
| `BGAppRefreshTask` scheduled for a future time | Opportunistic execution only | Telemetry/refresh, never a discovery guarantee |

## Corrections to older guidance

### 1. Overflow advertisements

Apple's archived Core Bluetooth guide says that, in the background:

- the local name is not advertised;
- service UUIDs move to an overflow area;
- an iOS device can discover an overflow UUID when it explicitly scans for that UUID.

The current app does the important part correctly:

```swift
scanForPeripherals(
    withServices: [Self.serviceUUID],
    options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
)
```

This is in `ios/Runner/BackgroundBeacon.swift` around line 261. A `nil` service filter would not be equivalent in the background.

The overflow payload is also not opaque to Android. David Young's reverse engineering identifies an Apple manufacturer-data prefix followed by a 128-bit bloom-like bitmask. Android can inspect those bytes directly; it is not bound by Core Bluetooth's iOS scan API. Hash collisions are possible, so an overflow hit remains a candidate until the rotating token is read and validated.

Consequences:

- retain the explicit `CAFE` UUID filter on iOS;
- retain the Android Apple manufacturer-data filter/parser;
- do not describe the overflow area as “iOS-only” or “foreground-only”;
- do not treat a bitmask hit as authenticated identity.

### 2. Advertisement RSSI versus connected RSSI

Background advertisement delivery is coalesced and slowed. With duplicate delivery disabled — and under background rules even when requested — `didDiscover` is not a sampling clock.

Apple explicitly supports `CBPeripheral.readRSSI()` while the peripheral is connected and returns the result through `peripheral(_:didReadRSSI:error:)`. That is the API W5 should sample from.

Herald's inspected loop is:

```text
scan
  → connect / wake transmitter
  → notification arrives in didUpdateValueFor
  → readRSSI()
  → didReadRSSI
  → notify delegates
  → schedule the next wake
```

The signal characteristic in the inspected Herald revision is:

```text
0eb0d5f2-eae4-4a9a-8af3-a4adb02d4363
```

Its current source default is a **2-second** notification delay. Nearby constants are **12** concurrent connections and a **12-second** connection-attempt timeout. These are Herald defaults, not Apple limits and not approved production values for this app. Herald prose that says eight seconds is stale relative to that source revision.

Herald also connects back after observing an incoming central. Its source calls the reciprocal connection essential for iOS-to-iOS background detection. This is the mechanism relevant to our sparse return direction.

### 3. Live Activity behavior has two separate layers

Do not conflate them:

#### Nearby Interaction, iOS 18.4+

Apple documents that an app can keep an NI session ranging in the background when it starts a Live Activity as it goes to the background. The app also needs the `nearby-interaction` background mode.

NI does not discover peers. Each side creates an `NISession`, exchanges that session's temporary `discoveryToken` over BLE or another channel, and runs the peer's configuration. Recreate/re-exchange tokens whenever the NI session changes; do not cache them as durable user identifiers.

**Needs bench:** the safest product assumption is that each app must own an active Live Activity when that app backgrounds. Test one-sided and two-sided variants, but do not design around a one-sided loophole.

#### Core Bluetooth, iOS 26+

**Source strength differs sharply from the NI half above — weigh it accordingly.** This
behavior is **not in any Apple documentation**. `scanForPeripherals(withServices:options:)`
and the ActivityKit docs were both checked and neither mentions Live Activities, Bluetooth
privileges, or display state. The sole source is one accepted answer from an Apple Staff
Engineer on [forums thread 815189](https://developer.apple.com/forums/thread/815189)
(Feb 2026), verbatim:

> "iOS 26 adds the existence of a Live Activity for an app to be considered sufficiently in
> use to continue scanning without these limitations, but on a locked screen which is turned
> off even the Live Activity is no longer sufficiently in use, so the scanning behavior will
> change. **There are no supported workarounds for this limitation.**"

Real, but an undocumented behavior with no API contract and no deprecation path — Apple can
change it silently, as it did to background scanning in iOS 18.0. Do not make it load-bearing.
Note also that Apple's phrasing is "locked screen which is turned off," not "display lit";
the reporting developer observed enhanced behavior persisting while backgrounded behind
another foreground app. The staff answer narrows it to:

- backgrounded behind another app: enhanced behavior;
- Lock Screen visible/lit: enhanced behavior;
- Lock Screen fully black: restricted background service-filtered, throttled, coalesced behavior returns.

This is still valuable UX. An honest “In Range is active” Lock Screen surface can turn a glance or notification-lit interval into a discovery opportunity. It does not make two untouched, dark phones continuously discover one another.

### 4. Nearby Interaction range and current hardware

Use Apple's public terms: **Ultra Wideband** and **second-generation Ultra Wideband**, not an assumed “U2” product name.

The current iPhone 14 and iPhone 15 Plus can test ordinary peer NI ranging. They **cannot** test Extended Distance Measurement (EDM) together, because Apple requires second-generation UWB on both peers; iPhone 15 and later meet that requirement, while iPhone 14 does not.

Apple's EDM sample uses a 50 m maximum-distance quality gate. That is sample logic, not a guaranteed operating radius. Do not put “60 m” or “3× range” into a product requirement until it is measured on two eligible devices in our environments.

### 5. State restoration changed in iOS 26, but was not removed

TN3115 distinguishes ordinary restoration from several user/system termination cases. Starting in iOS 26, only apps using AccessorySetupKit qualify for relaunch after the note-5 cases, including certain force-quit, Control Center Bluetooth-toggle, and Airplane Mode sequences.

Do not simplify this to “restoration no longer works.” Ordinary cases such as eligible memory eviction still matter. Also do not add AccessorySetupKit merely to regain relaunch behavior: this is a peer-phone app, not obviously an accessory-setup workflow.

The immediate repository issue is more basic:

- `CBCentralManagerOptionRestoreIdentifierKey` and the peripheral restore identifier are configured in `BackgroundBeacon.swift`;
- `centralManager(_:willRestoreState:)` is empty;
- `peripheralManager(_:willRestoreState:)` is empty.

W5 must restore the actual link model, not merely instantiate managers with identifiers.

### 6. Background task scheduling

`BGTaskRequest.earliestBeginDate` means “not before,” not “run at this time.” The system decides whether and when a task launches based on opaque scheduling factors.

Any comment or design claim that periodic 30-second windows will eventually overlap between sleeping iPhones is invalid as a correctness argument. Keep background refresh for opportunistic maintenance or telemetry only. The overnight zero-sample bench result is the relevant product evidence.

### 7. RSSI cannot support precise distance tiers by itself

Leith and Farrell measured effects large enough to cross our proposed thresholds without a meaningful distance change:

- roughly 20 dB change from rotating a person;
- about 15 dB between front- and rear-pocket placements;
- readings around `-80` to `-90` dBm with phones less than a metre apart in trouser pockets;
- a reproducible RSSI increase when separation grew from 2 m to 2.5 m.

Their separate tram field experiment reported a tested threshold rule at approximately 50% true positive and 50% false positive in that setup. The measurements were Android-based, so do not claim they are an iPhone calibration. They are strong evidence that RSSI should be treated as noisy context rather than metric distance.

Policy for the upgrade:

- never label a single RSSI threshold crossing as authoritative proximity;
- preserve bilateral BLE, Wi-Fi, GPS, temporal smoothing, and learned fusion;
- prefer NI distance/direction for supported warm iOS pairs;
- record measurement source and confidence so advertisement RSSI, connected RSSI, and UWB are not silently mixed.

## Current repository audit

### iOS

Primary file: `ios/Runner/BackgroundBeacon.swift`

- advertises fixed service UUID `CAFE`;
- exposes rotating token characteristic `CA7E`;
- background scan explicitly filters `[Self.serviceUUID]`;
- connects, discovers `CAFE`, reads `CA7E`, and disconnects;
- feeds the advertisement callback's RSSI into the estimator;
- has no `readRSSI()` / `didReadRSSI` loop;
- has no writable/notifiable signal characteristic;
- has no reciprocal-connection state machine;
- supplies central and peripheral restoration identifiers;
- leaves both restoration callbacks empty.

`ios/Runner/AppDelegate.swift` boots persisted state but does not currently rebuild a restored BLE graph.

`ios/Runner/Info.plist` already contains Bluetooth and location purpose strings and the `bluetooth-central`, `bluetooth-peripheral`, `fetch`, `location`, and `processing` background modes. It does **not** yet declare:

- `nearby-interaction` in `UIBackgroundModes`;
- `NSNearbyInteractionUsageDescription`;
- `NSSupportsLiveActivities`.

No app/widget extension for a Live Activity is present. No Nearby Interaction or ActivityKit implementation is present.

### Android

Primary files:

- `lib/features/beacon/beacon_service.dart`
- `lib/features/beacon/gatt_token_reader.dart`
- `android/app/src/main/kotlin/io/inrange/app/GattTokenReader.kt`
- `android/app/src/main/kotlin/io/inrange/app/MainActivity.kt`

Current behavior:

- advertises and scans for the `CAFE` carrier;
- hardware-filters the app manufacturer ID, Apple `0x004C` overflow prefix, and `CAFE`;
- parses/caches an overflow candidate, then connects to read `CA7E`;
- native token reading closes the `BluetoothGatt` after each read;
- the Android advertisement is currently non-connectable;
- there is no Android GATT server for the reciprocal iPhone-to-Android link.

This confirms the current carrier is **connect → read → disconnect**, not a persistent link.

## W5 implementation contract — warm-link BLE continuity

### Goal

After a legitimate initial discovery, retain a bounded connection and obtain regular, bilateral connected-RSSI observations while both devices are backgrounded/locked. Cold discovery while both iPhone screens are black is explicitly out of scope.

### Protocol shape

Keep:

- service UUID `CAFE`;
- rotating token read characteristic `CA7E`.

Add an app-owned signal characteristic, for example `CA7F`, rather than copying Herald's public UUID:

- properties: write plus notify;
- an empty or tiny versioned wake frame is sufficient initially;
- central subscribes to notifications;
- central periodically writes a wake frame;
- peripheral responds by notifying subscribers;
- notification callback triggers `readRSSI()` on the connected peripheral;
- successful RSSI callback emits a source-tagged observation;
- incoming central activity queues a reciprocal central connection when possible.

The exact wire frame, timeout, cadence, and quota must be versioned constants. Herald's 2 s / 12 links / 12 s are starting references only.

### Required iOS state

Track per peer:

- Core Bluetooth identifier and current rotating token association;
- discovery, connecting, connected, service-ready, subscribed, and backoff states;
- retained `CBPeripheral` object with delegate;
- `CBMutableCharacteristic` subscription set;
- last wake/write/notification/RSSI timestamps;
- reconnect attempt count and reason;
- token slot and expiry;
- whether the link was restored or freshly discovered.

Implement:

- `peripheral(_:didReadRSSI:error:)`;
- incoming write validation and a response for every ATT write request;
- `peripheralManager(_:central:didSubscribeTo:)`;
- `peripheralManager(_:central:didUnsubscribeFrom:)`;
- notification queuing;
- `peripheralManagerIsReady(toUpdateSubscribers:)` retry when `updateValue` returns `false`;
- reciprocal-connect scheduling without unbounded connection fan-out;
- real central and peripheral `willRestoreState` reconstruction.

### Required Android state

- make the relevant advertisement connectable and revalidate payload/filter behavior;
- implement a GATT server exposing `CAFE`, `CA7E`, and the signal characteristic;
- support notification subscription, wake writes, and dynamic token reads;
- retain central/client links instead of closing every `BluetoothGatt`;
- serialize GATT operations and close links deterministically on eviction/failure;
- add a bounded LRU/quota and exponential backoff;
- protect against Android client-ID/resource exhaustion and rapid reconnect loops.

### Token and trust rules

- A connection is transport state, not user identity.
- Read the current rotating token dynamically and remap the connection as token slots rotate.
- Do not keep a stale 15-minute overflow cache as durable identity.
- Validate protocol version and frame size.
- Rate-limit unauthenticated writers and candidate peers to prevent battery/wake denial of service.
- Apply server-side encounter/match authorization separately; neither RSSI nor NI is cryptographic proof of identity.

### Observation envelope

Before emitting W5/W6 data into one estimator, add or preserve an envelope equivalent to:

```text
peer_candidate
timestamp_monotonic
source = adv_rssi | connected_rssi | nearby_interaction
rssi_dbm?
distance_m?
direction?
quality?
local_state
remote/link_state
token_slot
```

Do not make `connected_rssi` look like a denser version of the same statistically independent advertisement stream. The estimator needs source and correlation context.

## W6 implementation contract — Nearby Interaction + Live Activity

### Goal

Prove background NI continuity on iOS 18.4+, determine whether a trusted server can broker first contact during a user-started active session while displays are dark, and test whether the Live Activity also provides enough screen-lit Core Bluetooth improvement to avoid W7.

### Minimal spike

1. Add an ActivityKit widget extension with an honest, minimal Lock Screen activity such as “In Range is active.”
2. Add `NSSupportsLiveActivities`, `NSNearbyInteractionUsageDescription`, and the `nearby-interaction` background mode.
3. Create one `NISession` per active peer.
4. Encode and exchange each `NIDiscoveryToken` through an authenticated/versioned BLE characteristic or a trusted backend association.
5. Add a server-brokered test mode that uses coarse GPS/venue eligibility to exchange tokens, then bench the delayed-join case where one phone has already been dark for ten minutes.
6. Start/update the Live Activity while foregrounded before the app backgrounds.
7. Run the peer configuration and log NI updates, suspension/invalidation reasons, Live Activity state, and app/Lock Screen state.
8. Expire the Live Activity and session promptly when proximity mode ends.

Do not use UWB output for security/access-control decisions; Apple does not describe nearby-object distance as secure ranging.

### Product behavior

- Unsupported device or iOS version: fall back to W5/fusion.
- NI warm session: NI distance/direction is the preferred geometric input.
- NI unavailable/suspended: degrade to connected RSSI, then advertisement/fusion.
- Peer token unavailable: NI cannot start. A token may arrive through BLE or the server; the server-brokered active-session path is a W6 bench target, not a shipped guarantee.
- Live Activity dismissed/expired: surface degraded state in telemetry; do not silently imply full ranging continues.

## W7 decision gate — Core Location screen-lit assist

Herald historically ranged a fictional beacon UUID to subscribe to screen-on/location wake opportunities. In its old iOS tests, that helped advertisement delivery while the display was lit. This is an implementation lead, not a documented BLE guarantee.

Costs:

- Always authorization and likely precise/full location behavior for beacon features;
- location background mode and persistent privacy disclosure;
- App Review risk under Guidelines 2.5.4 and 5.1.5 if location is used mainly to manipulate BLE scheduling;
- notification/screen behavior varies with Focus, Apple Watch routing, and user settings.

The app already requests background location, but that does not make the technique low-risk or justified.

Decision rule:

> Do not implement W7 unless W6's iOS 26 Live Activity Bluetooth A/B test shows a concrete older-OS or reliability gap, product explicitly accepts the permission/review cost, and a current-iOS bench reproduces the benefit.

## W8 implementation contract — restoration and lifecycle

On central restoration:

- recover retained/scanning/connected peripherals from Apple's restoration dictionary;
- set each peripheral delegate immediately;
- rebuild service/characteristic references or rediscover them;
- identify which links were subscribed and resume the W5 state machine;
- reconcile restored Core Bluetooth identifiers with rotating-token mappings.

On peripheral restoration:

- recover services and advertising state supplied by Core Bluetooth;
- recover mutable characteristic references;
- rebuild subscribed-central bookkeeping as callbacks permit;
- resume only valid queued notifications.

Lifecycle reporting must distinguish:

- ordinary background/suspension;
- eligible restoration after memory pressure;
- reboot and first-unlock behavior;
- Bluetooth powered off/on;
- Airplane Mode;
- Control Center Bluetooth toggle;
- user force-quit;
- process crash.

TN3115's iOS 26 note-5 cases are expected limitations for a non-AccessorySetupKit app, not test failures to hide.

## Bench plan and acceptance gates

### Instrumentation required before the walk

Every log row should include:

```text
monotonic timestamp
wall-clock timestamp
device/install alias
peer candidate alias
OS/app build
screen lit/dark if observable
app foreground/background
Live Activity state
BLE role and connection state
sample source
RSSI/distance/direction/quality
token slot
event/error/reconnect reason
```

Export raw events. Do not retain only tier transitions.

### W6: current iPhone 14 + iPhone 15 Plus

Run each Live Activity variant in three acquisition modes:

1. **Warm BLE:** exchange NI tokens over BLE and establish NI in the foreground.
2. **Server before lock:** both phones start the active proximity session, upload their NI tokens and coarse locations, receive the server match, then lock.
3. **Delayed join:** phone A starts the active session and remains screen-off for ten minutes; phone B starts later and the server attempts to deliver both tokens without a BLE discovery callback.

For each acquisition mode, test:

1. one Live Activity, two Live Activities, and no Live Activity;
2. both apps backgrounded with screens still lit;
3. both screens locked and fully black;
4. one screen woken without foregrounding the app;
5. another app foregrounded while the Live Activity remains active;
6. 1 m, 3 m, and 8 m placements with multiple body orientations;
7. leaving range and returning;
8. memory pressure/normal app eviction where practical; and
9. ending/dismissing the Live Activity and verifying explicit degradation.

Record:

- NI update cadence and longest gap by state;
- token-upload, candidate-match, token-delivery, and first-NI-update timestamps;
- whether delayed join succeeds while phone A remains dark, and which callback/runtime delivered the match;
- whether a one-sided Live Activity preserves both directions;
- Core Bluetooth `didDiscover` count/cadence with display lit versus black;
- duplicate/coalescing behavior;
- session invalidation and recovery;
- battery and thermal effect over at least two hours.

**Pass for the spike:** repeatable background NI updates while dark after a warm handshake, a documented answer for one-sided versus two-sided Live Activities, and at least 18 successful delayed joins in 20 controlled attempts before treating server-brokered first contact as a product path.

**EDM:** blocked until a second iPhone 15-or-later device is available.

### W5: cross-platform and iOS-to-iOS

Required legs:

1. S22 ↔ iPhone 15 Plus, warm link, both locked, 30 minutes.
2. iPhone 14 ↔ iPhone 15 Plus, warm link, both locked/dark, 30 minutes.
3. Cold-start both iPhones while already dark; record the expected non-discovery separately.
4. Token rotation while connected.
5. Walk out of range and return.
6. Bluetooth off/on and Airplane Mode, labeled against TN3115 expectations.
7. Ordinary process eviction/restoration.
8. Connection pressure at 2, 4, and the configured maximum peer count.
9. Eight-hour stationary power/thermal soak.

Initial acceptance target, to be refined from power data:

- bilateral connected-RSSI observations for a warm link;
- no 60-second silent gap during the 30-minute steady-state leg;
- current token mapping remains correct across rotation;
- bounded reconnect/backoff behavior;
- no Android GATT resource exhaustion;
- no unbounded wake loop or notification queue;
- restoration behavior matches the documented termination category;
- raw logs make every fallback visible.

Do not require a two-second sample rate merely because Herald uses a two-second default.

### RSSI/fusion collection

For each distance, collect front pocket, rear pocket, hand, bag, facing, back-to-back, and walking cases. A single station is a point, not an envelope. Compare:

- advertisement RSSI;
- connected RSSI;
- bilateral RSSI agreement;
- NI distance/direction where available;
- Wi-Fi/GPS/fusion outputs;
- false tier transitions and dwell time.

Only adjust tier boundaries after this data exists.

## Calibration freeze and immediate preflight

**Resolved with a new additive baseline tag:** `calib-freeze-2026-07-24b`. The
published `calib-freeze-2026-07-24` tag remains at `793f278`; it was not moved.

The `07-24b` baseline includes Rahul's `6827be3` wake-log observability. It
records BGTask grants and GATT-read wakes, which is exactly the instrumentation
needed to interpret a locked-phone leg. `walk_capture.sh` and
`RAHUL_REINSTALL.md` now default to the new tag.

The device-install blocker is not resolved merely by creating the tag. The
freeze document records:

- the installed S9 builds predate build stamping and must be rebuilt;
- the S22 and iPhone 15 Plus must be reinstalled from at least the current native-GATT client baseline;
- `walk_capture.sh prep` intentionally rejects a mismatched client build.
- IG-fleet S9 the protected IG-fleet S9 (serial omitted) is protected by default and is not part of the
  In Range walk rig.

Do not bypass that check for a training walk. W5 and W6 will materially change the sampling process, so their implementation requires:

1. a new explicit calibration freeze;
2. fresh builds on every participating device;
3. the build stamp captured in walk metadata;
4. baseline and upgraded walks kept as different sampling regimes.

The new research document itself is docs-only and does not change the client build.

## Known unknowns

- Whether both peers need their own Live Activity for reliable two-phone NI background continuity.
- NI longevity under ordinary memory pressure and session invalidation.
- Sustainable W5 wake cadence and connection quota on the target device mix.
- Whether reciprocal connection remains reliable on current iOS 26 builds.
- How long a warm BLE/NI state can be reacquired after an out-of-range interval without a foreground assist.
- Whether the iOS 26 Core Bluetooth Live Activity benefit is large enough in our app to eliminate any reason to prototype W7.
- EDM performance; the current device pair cannot test it.

## Non-goals and traps

- Do not claim that background overflow advertisements are unreadable by iOS or Android.
- Do not use `scanForPeripherals(withServices: nil)` as an iOS background solution.
- Do not use `BGAppRefreshTask` scheduling as peer-discovery correctness.
- Do not call W5 a cold-discovery solution.
- Do not copy Herald's constants as Apple requirements.
- Do not ship a fictional-beacon permission strategy based only on iOS 14-era results.
- Do not present RSSI-derived metres or fixed proximity tiers as ground truth.
- Do not promise EDM range from an iPhone 14 ↔ iPhone 15 Plus test.
- Do not claim state restoration covers force-quit/toggle cases that TN3115 excludes.

## Sources

### Apple — Core Bluetooth

- [Core Bluetooth background processing for iOS apps (archived)](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html)
- [`scanForPeripherals(withServices:options:)`](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/scanforperipherals%28withservices%3Aoptions%3A%29)
- [Core Bluetooth overview, including Live Activity integration](https://developer.apple.com/documentation/corebluetooth)
- [Apple staff clarification: iOS 26 Live Activity scan behavior with Lock Screen lit versus black](https://developer.apple.com/forums/thread/815189)
- [`CBPeripheral.readRSSI()`](https://developer.apple.com/documentation/corebluetooth/cbperipheral/readrssi%28%29)
- [`peripheral(_:didReadRSSI:error:)`](https://developer.apple.com/documentation/corebluetooth/cbperipheraldelegate/peripheral%28_%3Adidreadrssi%3Aerror%3A%29)
- [`peripheralManagerIsReady(toUpdateSubscribers:)`](https://developer.apple.com/documentation/corebluetooth/cbperipheralmanagerdelegate/peripheralmanagerisready%28toupdatesubscribers%3A%29)
- [TN3115: Bluetooth state-restoration app-relaunch rules](https://developer.apple.com/documentation/technotes/tn3115-bluetooth-state-restoration-app-relaunch-rules)

### Apple — Nearby Interaction, ActivityKit, and hardware

- [Nearby Interaction overview](https://developer.apple.com/documentation/nearbyinteraction)
- [Initiating and maintaining a Nearby Interaction session](https://developer.apple.com/documentation/nearbyinteraction/initiating-and-maintaining-a-session)
- [`NISession.discoveryToken`](https://developer.apple.com/documentation/nearbyinteraction/nisession/discoverytoken)
- [Extended Distance Measurement](https://developer.apple.com/documentation/nearbyinteraction/extending-advanced-direction-finding-and-ranging)
- [Live Activities with ActivityKit](https://developer.apple.com/documentation/activitykit/activity)
- [Nearby Interaction analytics report fields](https://developer.apple.com/documentation/analytics-reports/nearby-interaction-sessions)
- [Apple devices with Ultra Wideband](https://support.apple.com/en-us/109512)

### Apple — location, scheduling, and review

- [Determining proximity to an iBeacon device](https://developer.apple.com/documentation/corelocation/determining-the-proximity-to-an-ibeacon-device)
- [`CLLocationManager.accuracyAuthorization`](https://developer.apple.com/documentation/corelocation/cllocationmanager/accuracyauthorization)
- [`BGTaskRequest.earliestBeginDate`](https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate)
- [Apple staff background-task scheduling explanation](https://developer.apple.com/forums/thread/124320)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

### Herald and overflow research

- [Herald iOS source revision inspected for this document](https://github.com/theheraldproject/herald-for-ios/tree/584d0379246261df10099a15ca285534a6cf6db5)
- [Herald `BLEReceiver.swift`: reciprocal connection and wake/RSSI loop](https://github.com/theheraldproject/herald-for-ios/blob/584d0379246261df10099a15ca285534a6cf6db5/Herald/Herald/Sensor/BLE/BLEReceiver.swift)
- [Herald `BLESensor.swift`: UUID and timing/quota defaults](https://github.com/theheraldproject/herald-for-ios/blob/584d0379246261df10099a15ca285534a6cf6db5/Herald/Herald/Sensor/BLE/BLESensor.swift)
- [Herald protocol design](https://heraldprox.io/design/protocol)
- [Herald iOS guide](https://heraldprox.io/guide/ios)
- [David Young: reverse engineering the iOS overflow area](https://davidgyoungtech.com/2020/05/07/hacking-the-overflow-area)

Herald's repository revision inspected here dates from 2023 and its published iOS continuity results are largely from the iOS 14 era. Use the mechanism as an implementation lead and reproduce every claim on the shipping OS/device matrix.

### RSSI measurement work

- [Leith and Farrell, Bluetooth RSSI measurement study (PDF)](https://www.scss.tcd.ie/Doug.Leith/pubs/bluetooth_rssi_study.pdf)
- [Leith and Farrell, tram field trial, PLOS ONE](https://doi.org/10.1371/journal.pone.0239943)

## Definition of done for this upgrade phase

The phase is complete only when:

1. W6 has an iPhone 14 ↔ iPhone 15 Plus result for dark-screen NI continuity, one-versus-two Live Activities, and the server-brokered delayed-join case.
2. W5 produces bilateral, source-tagged connected-RSSI samples on S22 ↔ iPhone and iPhone ↔ iPhone warm links.
3. Restoration callbacks rebuild real link state and lifecycle limitations are documented by termination category.
4. Cold, both-dark iPhone discovery with no user-started active session remains labeled unsupported rather than hidden behind scheduled-task optimism.
5. Tier/fusion work consumes source-tagged observations and is calibrated from a multi-placement walk, not one RSSI cutoff.
6. Privacy and review copy truthfully explains any Live Activity, UWB, Bluetooth, and location behavior that actually ships.
