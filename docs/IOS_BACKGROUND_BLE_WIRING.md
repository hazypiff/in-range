# iOS background (locked-phone) BLE — wiring plan

**Date:** 2026-07-23. **Status:** ready to wire — design settled, code touch
points enumerated, nothing here is deployed yet.
**Prereq reading:** `IOS_CARRIER_DECISION_2026-07-16.md` (the peer-reviewed
carrier analysis this plan executes — its §3b "(a) GATT exchange" is the
production path chosen here).

**Goal:** an iPhone with the app backgrounded / screen locked / pocketed still
(1) discovers Android + iOS peers, and (2) is discoverable by them, well enough
to form confirmed encounters. Today iOS is **foreground-only** (service-UUID
carrier, "path b"); Android already works locked via its foreground service.

Nothing in this plan touches the server. `claim_token` / `record_sighting` /
reciprocity operate on the 32-hex token string and are carrier-agnostic
(decision doc §3a). The security harness (T1–T47) is unaffected.

---

## 1. The three iOS facts that force this design

1. **Backgrounded iOS strips the advertisement.** CBPeripheralManager moves all
   service UUIDs into Apple's proprietary *overflow area* and drops LocalName.
   The overflow area is only matched by an **iOS** device foreground-scanning
   for that exact UUID. An Android scanner sees a connectable advertisement
   with **no usable payload** — the token-as-service-UUID trick (today's
   foreground carrier) transmits nothing in background.
2. **Backgrounded iOS scanning requires an explicit service-UUID filter.**
   `scanForPeripherals(withServices:)` with exact UUIDs only — wildcard scans
   deliver nothing in background. Today's S9 advertisement is
   **manufacturerData-only** (mfg id 0xFFFF), which a service-UUID filter can
   never match → a backgrounded iPhone can't see an S9 *at all* until the S9
   also advertises a service UUID (§3, W1).
3. **A backgrounded iOS peripheral still answers GATT reads.** With the
   `bluetooth-peripheral` background mode (already in Info.plist), read
   requests wake the app. So the rotating token doesn't need to be on the air
   at all — a peer can connect and read it. This is the production carrier.

This is the Herald/Exposure-Notification-era, field-proven shape for
iOS↔Android background BLE. We are not inventing anything.

---

## 2. Design summary

**Fixed, filterable discovery UUID; rotating token behind a GATT read.**

- Discovery marker stays `0xCAFE` (16-bit) / `0000cafe-0000-1000-8000-00805f9b34fb`
  (128-bit) — already the app-wide marker (`beacon_service.dart:405-410`).
- **iPhone advertises** the marker as a service UUID *and* hosts a GATT service
  (same UUID) with one readable characteristic carrying the current 16-byte
  token. Foreground: peers read the token straight from the advertisement
  (today's path b, kept). Background: the advert degrades to
  overflow-area/anonymous, and peers **connect + read** instead.
- **iPhone scans** with `withServices:[CAFE]` — works locked, provided Android
  advertises the marker too (W1).
- **Token rotation without background timers:** the native module holds the
  whole prefetched day batch (`issue_token_batch` slots — `BatchSlot` already
  models this) and answers each GATT read with the slot valid *at read time*.
  No timer needs to fire in background; reads themselves wake the app.
- **RSSI for ranging always comes from the scan result** (the advertisement),
  never from the GATT connection. iOS has no TX-power control, so iOS-sourced
  sightings stay `power=high` (no feet_30 medium slot), exactly as foreground
  iOS today.

### Discovery matrix after wiring

| Direction | Foreground | iPhone locked |
|---|---|---|
| S9 sees iPhone | adv service-UUID (today) | GATT connect-read (W3) |
| iPhone sees S9 | unfiltered scan (today) | `withServices` scan vs W1 marker |
| iPhone sees iPhone | adv (today) | overflow-area scan (free with W2) |
| S9 sees S9 | manufacturerData (today) | unchanged (FGS) |

---

## 3. The four wiring tasks

### W1 — Android advertiser adds the 16-bit marker (small, Linux-testable)

Add the `0xCAFE` 16-bit service UUID to the existing Android advertisement so
backgrounded iPhones can filter-scan for it. Byte math for the 31-byte legacy
AD: flags (3) + mfgData AD (2 hdr + 2 company + 17 payload = 21) + 16-bit
service-UUID AD (2 hdr + 2 uuid = 4) = **28 ≤ 31**. Fits.

- Touch: `_startAdvertisingLocked` Android branch (`beacon_service.dart:495-508`)
  — add the service UUID to `AdvertiseData` alongside `manufacturerData`.
- Risk: some stacks mis-handle mixed AD payloads — verify on an S9 that the
  advert still starts and *both* fields arrive (S9→S9 desk check).
- **Do after the current walk**, not before — don't perturb a working Android
  advertisement the night before a field test.

### W2 — iOS native module (the core; Mac + Xcode required)

The Flutter plugins can't do this part: neither `flutter_ble_peripheral` nor
`flutter_blue_plus` supports CoreBluetooth **state restoration**, GATT-server
read handlers with dynamic values, or relaunch-after-termination. This is a
small Swift module in `ios/Runner/` bridged over a MethodChannel.

`BackgroundBeacon.swift` responsibilities:

1. `CBPeripheralManager` with
   `CBPeripheralManagerOptionRestoreIdentifierKey:"io.inrange.beacon.peripheral"`.
   - Publish GATT service `0000CAFE-…` with one characteristic
     (`0000CA7E-0000-1000-8000-00805f9b34fb`, read-only, no encryption) whose
     value is computed **per read**: current slot from the stored batch.
   - Advertise `[CBAdvertisementDataServiceUUIDsKey: [CAFE]]`. In foreground
     iOS this coexists with the Dart path-b advertiser — simpler: once W2 is
     in, **retire the Dart `FlutterBlePeripheral` path on iOS entirely** and
     let the native module own advertising in both lifecycles (one advertiser,
     no contention; keep advertising the token-as-second-UUID in foreground so
     the existing no-connect fast path still works).
2. `CBCentralManager` with restore key `"io.inrange.beacon.central"`.
   - `scanForPeripherals(withServices:[CAFE], options:[AllowDuplicates:false])`
     (duplicates are coalesced in background regardless).
   - On discovery: forward `(peripheralId, rssi, advertisedTokenBytes?)` to
     Dart. If the token was NOT in the advert (backgrounded iOS peer, or W1
     Android peer where mfgData didn't survive the filter path), connect →
     discover `CAFE` service → read `CA7E` → disconnect. Cache
     `peripheralId→token` for ~15 min so each rotation costs one connect.
3. **State restoration / relaunch:** implement
   `application(_:didFinishLaunchingWithOptions:)` handling of
   `UIApplication.LaunchOptionsKey.bluetoothCentrals/Peripherals` in
   `AppDelegate.swift`, re-instantiate the managers with the same restore
   identifiers, and — critically — persist the token batch + beacon-on flag in
   `UserDefaults` so a relaunched process can serve GATT reads and keep
   scanning **without the Flutter engine running**. Buffer sightings natively
   (ring buffer in UserDefaults) and flush to Dart when the engine attaches.
4. MethodChannel `io.inrange/background_beacon`:
   - Dart→native: `start(batchSlots)`, `stop()`, `updateBatch(batchSlots)`.
   - native→Dart: `onSighting(hexToken, rssi, timestampMs)` (+ batched
     `flushBufferedSightings` on engine attach).

### W3 — Android scanner sees a *backgrounded* iPhone

A locked iPhone's advert carries no CAFE UUID Android can filter on. Two-part
detection, both additive to the existing scan (`beacon_service.dart:687-694`):

- Add a **second MSD filter**: manufacturer `0x004C` (Apple) with the
  overflow-area indicator (first payload byte `0x01`) + mask. This is the
  Herald-protocol trick: it matches backgrounded-iOS adverts specifically, and
  it keeps the scan hardware-filtered (required — Android ≥8.1 suppresses
  unfiltered screen-off scans; walk #1 proved it).
- On such a hit: GATT connect → read `CA7E` → token; RSSI from the scan
  result; same `peripheralId→token` cache as W2. Connect via
  `flutter_blue_plus` from the existing Dart service — no Android native code
  needed.
- False positives (random backgrounded iPhones that aren't running In Range)
  cost one failed service-discovery and are dropped; rate-limit connects per
  device id (once / 5 min) so a busy street doesn't spam the radio.

### W4 — Dart glue in `beacon_service.dart`

- iOS branch of `_startAdvertisingLocked` → call the native module instead of
  `FlutterBlePeripheral` (W2 owns both lifecycles). `_discoverable` reflects
  the module's advertising callback, preserving the fail-closed rule.
- `BatchTokenSource` rotation → also `updateBatch` to the module.
- New sighting ingress: `onSighting` events join `_onScanResults`'s path at
  the `rangeEstimator.addSample(hexId, rssi, power)` point with
  `power=AdvertPower.high`; run the same `_ownCorrHexes` self-sight guard and
  the staleness/dedup logic.
- Keep scan-only fallback: if the module fails to start advertising, iOS
  stays scanning-only and says so in the UI (unchanged honesty rule).

---

## 4. Sequencing

1. **W2 first, on the Mac** (it's the only Xcode-bound piece; everything else
   can land from the Linux box afterward). Desk test: iPhone locked, S9
   foreground → S9 sees overflow advert, connects, reads token.
2. **W3** (Dart-only) → S9 *locked* sees iPhone locked. Desk test both locked.
3. **W1** (Dart-only, one line + on-air verify) → iPhone locked sees S9.
4. **Walk test**: all phones pocketed, screens off, full reciprocity → cloud
   encounter must confirm. Then update `PROXIMITY_TIERS.md` if locked-iPhone
   RSSI differs materially from the in-hand curve (it will — body attenuation;
   collect the offset the way walk #3 did).

Estimated Mac-side effort: W2 is ~300–400 lines of Swift + AppDelegate touch +
channel glue; the rest is Dart from this box.

## 5. On-device unknowns to close (carry-over of decision-doc §8)

- Overflow-area filter reliability across Android OEM stacks (Samsung S9 must
  match `0x004C/0x01`-masked adverts in hardware; Herald data says yes).
- GATT read latency/success rate at walk distances (~10–30 m) — connect range
  is shorter than advert-sighting range; expect token reads to succeed only at
  closer approach. Sightings without a token (RSSI-only) are useless to the
  server, so the effective *encounter* range becomes connect range. Measure.
- Whether iOS keeps advertising after force-quit (it does not — state
  restoration survives OS jetsam/reboot-until-unlock only; document to users
  that swiping the app away stops the beacon. Android FGS has the same rule).
- iPhone↔iPhone both-locked: overflow-scan should still surface it (Apple
  explicitly supports scanning-for + advertising overflow UUIDs); verify.

## 6. What this plan does NOT change

- Server/SQL: nothing. Tokens, claims, reciprocity, consent gates untouched.
- Android advertising/scanning behavior for S9↔S9 (only *adds* W1's UUID and
  W3's second filter).
- Foreground iOS UX for tomorrow's/this week's walks — until W2 lands, the
  rule remains: **iPhone screen on, app foreground**.
