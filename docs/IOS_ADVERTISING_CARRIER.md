# iOS beacon advertising — carrier gap + proposed fix

**For:** hazypiff (beacon protocol owner). **From:** iOS-side bring-up,
2026-07-16. **Decision needed before:** iPhones can be *discovered* (they can
already *scan*).

## The problem

The beacon protocol carries the 16-byte correlation id in BLE
**manufacturerData** (mfg id `0xFFFF`, `beacon_service.dart:469`). iOS
`CBPeripheralManager` (via the pinned `flutter_ble_peripheral`) **cannot
advertise manufacturerData** — iOS only exposes `CBAdvertisementDataServiceUUIDsKey`
and a local name, and backgrounded it strips the name and moves UUIDs to the
overflow area. So `_startAdvertisingLocked` correctly **fails closed on iOS**
(`beacon_service.dart:454`) rather than broadcast an empty, unreadable packet.

Result: an iPhone can **scan and log** other beacons, but **cannot be
discovered**. Half the cross-platform matrix works today:

| Direction | Status |
|---|---|
| S9 → iPhone (iPhone scans Android) | ✅ works now |
| iPhone → S9 (Android scans iPhone) | ❌ blocked (this doc) |
| iPhone → iPhone | ❌ blocked (this doc) |

## Proposed fix — token as a 128-bit service UUID

A BLE 128-bit service UUID is **exactly 16 bytes** — the correlation id fits
with zero loss. iOS *can* advertise service UUIDs (foreground and, in the
overflow area, background), and Android scanners can read them. This is the
standard cross-platform BLE identity trick.

**Advertiser (iOS):** build a `Guid` from the 16 correlation bytes and
advertise it as the service UUID (no manufacturerData). The current medium/
high power-slot flag (bit in the mfg payload today) needs a new home — options:
alternate between two UUID *prefixes*, or accept that iOS loses the medium-slot
feet_30 gate (it already has no calibration on iOS).

**Scanner (both platforms) — REQUIRED companion change:** the scan filter is
currently `withMsd: [MsdFilter(0xFFFF)]` (`beacon_service.dart:601`), which
**excludes pure service-UUID advertisers** — so today's scanner would never
even see an iOS advertiser. Add `withServices: [inRangeServiceUuid]` (or widen
the filter) AND a parse branch that recovers the 16 bytes from the advertised
service UUID. Note the existing serviceData fallback parse
(`beacon_service.dart:662`) reads *serviceData*, not the service *UUID* — a
new path is needed.

**Rotation:** the UUID must rotate with the token every 15 min like the mfg
payload does today; iOS re-advertise on rotation is already the model.

**Constraints to design around:**
- iOS background advertising: service UUID only visible to other iOS devices
  scanning explicitly; Android may not see a backgrounded iPhone at all. FGS/
  foreground keeps it visible. Quantify on a walk.
- No medium/high TX power control on iOS (`CBPeripheralManager` gives none) —
  iOS loses the power-slot distance gate; leans harder on windowed RSSI.
- Reciprocity/security (#6): confirm the server's token-batch model is carrier-
  agnostic (it should be — it's the same 16-byte id, just a different AD field).

## Alternatives considered
- **iBeacon:** major+minor is only 4 bytes — can't carry a 16-byte id, and no
  background advertising. Rejected.
- **Keep manufacturerData, different iOS plugin:** no maintained Flutter iOS
  peripheral plugin forwards arbitrary mfg data — it's an iOS platform limit,
  not a plugin gap. Rejected.

## Interim option (iOS-side, needs your OK)
Add an **iOS scan-only mode**: skip advertising, still scan + log RSSI, and
have the UI honestly show "not discoverable — scanning only" (respecting the
existing fail-closed / don't-lie-about-discoverability rule, reviewer #2).
This unblocks the **S9 → iPhone** calibration curve on walks *today* without
touching the protocol. Say the word and the iOS side ships it.

## Ask
1. OK to move the iOS carrier to a 128-bit service UUID (+ the scanner filter/
   parse companion change on both platforms)? Any conflict with the #6
   token-batch / attestation work in flight?
2. Meanwhile, OK to ship the interim iOS **scan-only** mode so iPhones collect
   the Android→iPhone curve on calibration walks now?
