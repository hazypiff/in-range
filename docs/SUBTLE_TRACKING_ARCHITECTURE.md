# Subtle Multi-Radio Tracking Architecture

**Date:** 2026-07-25
**Status:** Implementation spec
**Goal:** Make the iPhone track Bluetooth, WiFi, and GPS well enough that In Range detects encounters reliably while locked, without burning battery or tripping App Review.

## The problem

iOS will not let an app run continuous high-power BLE scans while locked and black. Background scanning is duty-cycled, filtered, and coalesced. Continuous background location is possible but expensive and hard to justify to App Review. The current design relies on BLE background modes plus opportunistic `BGTaskScheduler` wakes, which leaves long gaps.

## The strategy

Stop fighting iOS's radio scheduler. Instead of trying to keep BLE hot all the time, use every low-power wake source iOS *does* provide, and do a BLE burst whenever one fires. GPS and WiFi are not distance classifiers — they are wake triggers and venue corroboration.

| Tier | Source | Power cost | What it does |
|---|---|---|---|
| 0 | CoreBluetooth background modes | Very low | Filtered scan + overflow advert. Always on, sparse. |
| 1 | `BGTaskScheduler` | Low | Opportunistic ~30 s windows. BLE burst. |
| 2 | Significant Location Change | Very low | Wakes app when the user actually moves (~500 m). BLE burst + cache refresh. |
| 3 | Region monitoring | Very low | Wakes app when entering/leaving a venue anchor. BLE burst. |
| 4 | Silent push (APNs) | Low | Server says "a peer is probably here." BLE burst. |
| 5 | Live Activity + NI | Medium-high | Active session. Process stays alive; UWB if both devices support it. |

Tiers 0–4 are the "subtle" path: invisible to the user, low battery, and built entirely on Apple-approved APIs. Tier 5 is the "warm session" path: visible but functional.

## Privacy model

- **Raw coordinates are not uploaded continuously.** The client uploads:
  - Coarse geohash (city-level) for candidate pruning.
  - Hashed BSSID for venue matching.
  - Full GPS only with a sighting record, as today.
- **BSSIDs are hashed with a rotating salt** before leaving the device, same as the Android venue matcher.
- **Push tokens** are stored in the existing `public.device_push_tokens` table (migration 0005).
- **Silent pushes contain no user data** — only a wake hint and a nonce.

## Components

### iOS native

- `SubtleWakeCoordinator.swift`
  - Starts/stops with the beacon.
  - Manages `CLLocationManager` significant-location-change monitoring.
  - Manages `CLCircularRegion` monitoring for venue anchors.
  - Receives silent pushes and forwards them to Dart.
  - On any wake, tells Dart, which triggers a BLE burst via `BackgroundBeacon`.
- `BackgroundLocationCoordinator.swift` (existing)
  - Keeps the coarse fix cache fresh. SLC is a separate, lower-power session.
- `AppDelegate.swift`
  - Registers for remote notifications.
  - Forwards the APNs device token to Dart.

### Dart

- `SubtleWakeService`
  - Receives wake events from native.
  - Triggers a BLE burst (scan restart) and a location cache refresh.
  - Uploads coarse geohash + hashed BSSID to the server for co-location inference.
  - Registers/unregisters venue anchors.
- `VenueAnchorService`
  - Maintains a local set of venue anchors (geohash center + radius).
  - Converts anchors into `CLCircularRegion`s and hands them to native.
  - Anchors come from: server-provided hot venues, learned local venues, or manual test anchors.
- `BeaconService` integration
  - Exposes a `burst()` method that restarts the scan for a bounded window.
  - Routes wake-triggered sightings through the existing envelope.

### Server

- `public.venue_anchors` (new migration)
  - `geohash TEXT`, `radius_m INT`, `hashed_bssid TEXT`, `updated_at`.
  - RLS: users read/write own anchors; service_role reads all.
- `public.proximity_wake_requests` (new migration)
  - `id`, `user_id`, `peer_hint JSONB`, `status`, `created_at`.
  - Internal table drained by the `proximity-wake` Edge Function.
- `proximity-wake` Edge Function
  - Checks recent sightings / venue reports for likely co-located pairs.
  - Sends APNs silent pushes to the likely co-located devices.
  - Rate-limited and fail-closed.

## What is deliberately NOT done

- **No audio background mode.** Would be rejected and is dishonest.
- **No VoIP pushes.** Restricted to actual VoIP apps.
- **No continuous background location while locked.** Battery and App Review risk; SLC + regions give the same wake benefit at a fraction of the cost.
- **No raw BSSID upload.** Only hashed.
- **No evasion.** Every background mode we use is declared in `Info.plist` and tied to a visible feature.

## The honest "novel" part

The combination is the novel part, not any single API:

1. **BSSID venue anchors as privacy-preserving geofences.** Instead of geofencing raw coordinates, the client geofences the *hashed BSSID* of the current network. When the phone joins a network whose hash matches a peer's recent network, the server can infer co-location without either side revealing where they are.
2. **Server-side co-location from sparse hints.** The server does not need continuous GPS. A coarse geohash plus a hashed BSSID is enough to say "these two devices are probably in the same coffee shop" and trigger a silent push.
3. **BLE burst on co-location inference.** The expensive radio (BLE) only runs hot when the cheap radios (GPS + WiFi) say it is worth it.

## Setup requirements (Mac / Apple Developer)

- **APNs Auth Key (.p8)** in the Apple Developer portal.
- **Push Notifications capability** in Xcode.
- **Background Modes** → add **Remote notifications** to `Info.plist`.
- **Access WiFi Information** capability (already documented).
- **Location Always** authorization for SLC and region monitoring.

## Rollout plan

1. Land client + server code behind flags (`INRANGE_SUBTLE_WAKE=true`, `INRANGE_PROXIMITY_WAKE=true`).
2. Mac build adds capabilities and compiles.
3. Field-test SLC and region wakes on a real device.
4. Add APNs key and test silent push delivery.
5. Tune wake cadence and BLE burst length from power data.
6. Enable for beta users with consent copy.
