# iOS Location Residency Review

Date: 2026-07-24

Reviewed commit: `3d98316` (`ios: hold the process resident while the beacon is on`)

Status: code is merged; claimed Bluetooth benefit is not yet established on-device

## Executive verdict

The new `LocationKeepalive` uses a real, supported Core Location configuration:

- start standard location updates while the app is in use;
- allow background delivery;
- show the background location indicator;
- use coarse accuracy and a large distance filter; and
- disable automatic pausing so a stationary session does not end.

That can keep a When-In-Use-authorized app considered in use and prevent its
normal suspension while the location session remains active. It may therefore
keep Dart timers, network work, and app-owned state machines runnable.

It does **not** make Core Bluetooth foreground-like, remove iOS background scan
throttling, or create repeated advertisement callbacks. Apple engineering
answered the same location-stream-plus-BLE design in February 2026:

> “The background location models [have] nothing to do with BLE scanning in the background.”

Core Bluetooth still applies background rules:

- duplicate discoveries are coalesced;
- the scan interval increases when all scanning apps are backgrounded;
- the system may terminate the app;
- Bluetooth state restoration remains necessary; and
- one `didDiscover` per peripheral can still be the practical ceiling.

Treat `3d98316` as an **unproven runtime experiment**, not as evidence that
locked iPhone discovery is fixed.

## Claim-by-claim audit

| Claim | Verdict | Reason |
|---|---|---|
| An active location service can keep the app from normal suspension | Supported, subject to lifecycle and authorization | Apple documents background location sessions for timely updates and continued background use |
| `pauseLocationUpdatesAutomatically: false` prevents the stationary auto-pause | Supported | Apple explicitly describes this behavior and suggests coarse accuracy to reduce power |
| The configuration avoids storing its streamed fixes | Verified in current Dart code | The listener body discards each `Position` |
| Keeping the process runnable makes BLE scan continuously at foreground behavior | Unsupported/incorrect | App state remains background; Apple says the location model does not alter BLE background scanning |
| This improves every device pairing | Not established | It might help app-owned timers or connection maintenance, but cold discovery and coalescing need separate device results |
| The app now survives background termination | Incorrect | iOS may terminate any background app; the current location stream is not rebuilt from the native relaunch path |
| Eleven tests validate the residency result | Incorrect | They validate settings and subscription lifecycle against an injected Dart stream, not Core Location or Core Bluetooth on iOS |
| Beacon regions require a permission the app does not currently request | Incorrect | `PermissionService.requestAllForBeacon()` already calls `Permission.locationAlways.request()` |
| Beacon regions solve locked iPhone-to-iPhone discovery | Incorrect | An iPhone app can advertise the iBeacon payload only while foregrounded |
| Beacon regions can help Android/dedicated beacon → iPhone recovery | Credible, needs bench | Always-authorized region monitoring can ask iOS to launch the app when a matching iBeacon appears |

## Repository evidence

### What `3d98316` added

`lib/features/beacon/location_keepalive.dart` opens
`Geolocator.getPositionStream()` with:

```text
LocationAccuracy.lowest
distanceFilter = 100 m
pauseLocationUpdatesAutomatically = false
showBackgroundLocationIndicator = true
allowBackgroundLocationUpdates = true
```

`BeaconService.turnOnBeacon()` starts it after BLE setup, and
`turnOffBeacon()` cancels it.

The stream listener intentionally ignores its `Position` values. That is a
valid data-minimization choice, but it also makes the background service's
declared purpose “keep the process alive for Bluetooth,” rather than processing
location information.

### The tests are not a radio test

`test/location_keepalive_test.dart` injects a
`StreamController<Position>`. The tests correctly pin:

- the Apple settings;
- iOS-only activation;
- idempotent start;
- stop/cancel;
- error cleanup; and
- fail-open behavior.

They never instantiate Core Location, move an app to the background, lock a
screen, trigger process termination, or observe Core Bluetooth callbacks.

Passing those tests proves the wrapper contract. It cannot prove residency,
scan cadence, discovery, battery behavior, or App Review suitability.

### Always authorization is already requested

`lib/core/permissions/permission_service.dart` currently:

1. requests `Permission.locationWhenInUse`;
2. displays the background-location disclosure;
3. calls `Permission.locationAlways.request()`; and
4. tells a denied user to grant “Allow all the time” in Settings.

Therefore, “CLBeaconRegion is a heavier permission than what just shipped” is
not accurate for the present repository. It is a heavier product commitment
and review justification, but not a new permission class.

### It conflicts with a recorded product decision

`lib/features/beacon/beacon_screen.dart` still records:

> “The beacon is a pure BLE switch (owner decision 2026-07-21, issue #2).”

Starting a Core Location stream from the Beacon toggle reverses that behavior,
even when the samples are discarded. This needs an explicit owner decision;
the distinction between “not storing coordinates” and “not using background
location” does not remove the conflict.

### The native relaunch path does not restore the location session

`AppDelegate.application(_:didFinishLaunchingWithOptions:)` calls only
`BackgroundBeacon.shared.bootFromPersistence()`.

There is no native location coordinator, no handling that recreates the
location service after a location relaunch, and no path from
`bootFromPersistence()` to `LocationKeepalive`. Apple says apps must recreate
active location APIs after the system terminates and relaunches them.

Core Bluetooth restoration also remains incomplete for connected-peer state:
both `willRestoreState` callbacks currently rely on `didUpdateState` and do not
reattach restored peripherals, delegates, subscriptions, or W5 link state.

## App Review and privacy boundary

Apple's rules permit background location when location is directly relevant to
the app's feature. They also say background services may be used only for their
intended purposes.

The current code comment says:

> “The location data is not the point — the session is.”

That is the riskiest possible framing for App Review. It describes a location
background mode being used as a general execution assertion for a Bluetooth
feature. A visible indicator and an explicit toggle improve transparency, but
they do not by themselves establish that the API is being used for its intended
purpose.

A safer production design is the one in
`IOS_SCREEN_OFF_FUSION_2026-07-24.md`: use coarse location for a real,
user-visible function—accuracy-aware candidate selection or venue presence—
while the same explicit session supports server-brokered Nearby Interaction.
Minimize, quantize, or compare location server-side without exposing one user’s
coordinates to another.

Also reconcile the current disclosure:

- it says the app collects precise location to match encounters;
- the new keepalive says its fixes are discarded;
- other Beacon code can still obtain and cache fixes; and
- the 2026-07-21 owner decision says real-time proximity is BLE-only.

The UX, privacy policy, App Privacy answers, review notes, and implementation
must tell one consistent story before production submission.

## What location residency may still help

The experiment is not necessarily worthless. Keeping the app runnable may help:

- Dart timers and upload queues continue;
- a server-brokered candidate list can be refreshed;
- a new NI discovery token can be fetched and configured;
- a warm BLE connection loop can run app-owned scheduling;
- telemetry can distinguish “scan active but no callback” from suspension; and
- the current native/Dart split can be observed more clearly.

These are separate hypotheses. None imply that a dark iPhone gets foreground
advertisement delivery.

## Required A/B bench before relying on `3d98316`

Add an experimental feature flag so the same binary can run with the location
session enabled or disabled. Reinstalling different commits adds avoidable
confounders.

Run at least these legs:

1. iPhone 14 ↔ iPhone 15 Plus, both Beacon sessions started, then both screens
   fully black;
2. iPhone 14 ↔ iPhone 15 Plus, phone A dark for ten minutes before phone B
   starts;
3. S22 advertising ↔ locked iPhone scanning;
4. locked iPhone advertising ↔ S22 scanning;
5. warm iPhone ↔ iPhone GATT connection; and
6. ordinary memory pressure/termination, separately from user force-quit.

For each leg, compare keepalive off/on over 30 minutes, two hours, and an
overnight soak. Record natively:

```text
location_session_started/stopped/error
location_callback_count
application state
process launch reason
scan start/stop
didDiscover count and unique peripheral count
GATT connect/notify/readRSSI cadence
longest observation gap
battery drop and thermal state
```

The load-bearing outcomes are:

- Does a previously unseen dark iPhone produce a first discovery?
- Does the same peripheral produce more than the normal coalesced delivery?
- Is time-to-first Android → iPhone discovery materially better?
- Does a warm connected-RSSI loop become more reliable?
- Does the app actually relaunch and restore its useful state after termination?
- What is the two-hour and overnight battery cost?

More Dart timer ticks alone are not a passing radio result.

## Beacon-region decision

Do not implement `CLBeaconRegion` as a general iPhone-to-iPhone fix.

Apple requires an app using an iPhone as an iBeacon to remain foregrounded.
Therefore, beacon-region monitoring is useful only when the transmitter is:

- an Android phone deliberately advertising a standards-compliant iBeacon;
- a dedicated venue iBeacon; or
- another powered hardware anchor.

With Always authorization and full-accuracy access, a matching region
transition can cause iOS to try to launch an app that is not running. It still
has boundaries:

- user force-quit remains unsupported;
- monitoring begins only after first launch/unlock;
- region state changes are not a continuous RSSI sampling clock;
- reduced-accuracy authorization disables beacon monitoring/ranging;
- system delivery is not instantaneous or guaranteed under every lifecycle
  condition; and
- the app must recreate the monitor and its Bluetooth state on relaunch.

This makes region monitoring a useful **Android/venue-to-iPhone wake
experiment**, not the next universal proximity layer.

## Recommended next action

1. Complete `extract_walk.py --from-cloud` now; it is independent, reversible,
   and validates the new calibration transport.
2. Do not expand `3d98316` or describe it as a solved Bluetooth problem until
   the A/B device bench is complete.
3. Obtain an explicit owner decision before shipping any Beacon-triggered
   location session, because it changes the recorded 2026-07-21 behavior.
4. If location is accepted, implement it as an honest active-proximity input
   for the server-brokered NI candidate gate, not as a discarded-coordinate
   keepalive.
5. Bench `CLBeaconRegion` afterward only for Android/dedicated-beacon →
   terminated-iPhone recovery.
6. Continue W5 restoration and persistent connected-RSSI work; location
   residency does not replace it.

## Primary sources

- [Apple Developer Forums: BLE Scanning — Apple engineering says background
  location does not change BLE scanning](https://developer.apple.com/forums/thread/815286)
- [Core Bluetooth Background Processing for iOS
  Apps](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html)
- [Handling location updates in the
  background](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background)
- [Requesting authorization to use location
  services](https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services)
- [`pausesLocationUpdatesAutomatically`](https://developer.apple.com/documentation/corelocation/cllocationmanager/pauseslocationupdatesautomatically)
- [Determining proximity to an iBeacon
  device](https://developer.apple.com/documentation/corelocation/determining-the-proximity-to-an-ibeacon-device)
- [Turning an iOS device into an iBeacon
  device](https://developer.apple.com/documentation/corelocation/turning-an-ios-device-into-an-ibeacon-device)
- [App Review Guidelines 2.5.4 and
  5.1.5](https://developer.apple.com/app-store/review/guidelines/)
