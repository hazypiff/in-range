# iOS beacon carrier — findings & decision

**Author:** Claude (in-range #6 security/protocol work). **Date:** 2026-07-16.
**Status:** peer-reviewed and corrected (a second agent caught a wrong
current-state matrix and an under-specified Q1; both fixed below).
**Repo state:** synced to `f901345` (origin/main); prod at migration `0034`;
security harness green (T1–T12 + concurrency); `flutter analyze` clean, 73 tests
pass. Plugins pinned: `flutter_blue_plus 2.3.10`, `_android`/`_darwin 9.0.3`.

Answers the two asks in `docs/IOS_ADVERTISING_CARRIER.md` from the protocol/
security owner's side. **Q1 is a foreground-prototype approval only — the
production carrier is blocked on an unresolved filterable-discovery design (§3).**

---

## 1. Review of the 3 new iOS commits (`4317480..f901345`)

| Commit | Change | Verdict |
|---|---|---|
| `f0af00f` | `ios/Podfile` `PERMISSION_*` macros + `PermissionService.diagnose()` on-screen statuses | Correct. Without the macros `permission_handler` compiles iOS handlers out → every request returns denied, no prompt. Real latent bug. |
| `6d6b441` | `Podfile.lock` regen from the macro `pod install` | Mechanical, fine. |
| `f901345` | Platform-branch the BLE permission gate: iOS checks `Permission.bluetooth` only | Correct root-cause fix. The gate demanded `bluetoothScan`/`bluetoothAdvertise` *granted*, but those are **Android-12-only** perms; iOS always reports them denied, so no iPhone could ever start the beacon. |

**Caveat on `f901345` (permission_service.dart:34):** it returns
`!bt.isPermanentlyDenied`, which also accepts `restricted` (Bluetooth blocked by
MDM / parental controls / Screen-Time). That state would pass the gate and then
fail cryptically inside CoreBluetooth. The pinned `permission_handler` maps
`restricted` separately from `denied`. Prefer `bt.isGranted`, or explicitly
handle `restricted` with its own message. Minor (P2), not a blocker — the
partner's comment shows this was a deliberate "let CoreBluetooth surface the real
block" choice, but `restricted` deserves its own branch.

## 2. Current state — CORRECTED

Earlier drafts (mine **and** `IOS_ADVERTISING_CARRIER.md`) claimed "iPhone scans
S9 works now." **That is wrong.** In `turnOnBeacon` (`beacon_service.dart:179`)
the order is:

```
await _refreshClaim(...);
await _startAdvertising();   // iOS guard THROWS here (beacon_service.dart:453)
await _startScanning();      // never reached on iOS
... catch { _stopBle(); rethrow; }   // tears down BOTH paths
```

So on iOS the advertise-guard throws **before scanning starts**, the catch stops
BLE and rethrows, and the beacon never comes up. **Today the iPhone does nothing
— it cannot even scan.** The true matrix:

| Direction | Today | After Q2 (scan-only) | After Q1 (advertiser) |
|---|---|---|---|
| iPhone scans S9 (S9 → iPhone) | ❌ (guard tears down startup) | ✅ | ✅ |
| S9 scans iPhone (iPhone → S9) | ❌ | ❌ | ✅ (foreground; see §3) |
| iPhone ↔ iPhone | ❌ | ❌ | ✅ (foreground; see §3) |

The advertise guard (`beacon_service.dart:453-455`) is a **deliberate
fail-closed** (reviewer #2: never lie about discoverability), not a bug. The root
cause: the token's 16-byte correlation id rides in BLE **manufacturerData**
(`beacon_service.dart:464-470`, mfg id `0xFFFF`), and iOS `CBPeripheralManager`
cannot advertise manufacturerData — it honors only `ServiceUUIDs` and
`LocalName`.

## 3. Q1 — service-UUID carrier: **CONDITIONAL YES (foreground prototype only)**

### 3a. Server compatibility — NO conflict with #6 (authoritative, holds up)

The entire server side is **carrier-agnostic**. `claim_token`,
`record_sighting`, `correlate_encounter`, `issue_token_batch`, reciprocity, and
attestation operate **only on the 32-hex token string**; none knows which BLE AD
field carried the 16 bytes. The only invariant is client-side:

```
advertiser_hex  ==  scanner_recovered_hex  ==  claimed_hex
```

`_currentCorrelationId = _hexTo16Bytes(token)` (`beacon_service.dart:891`) is the
raw 16 bytes of the server-issued opaque token. Which AD field carries those
bytes is irrelevant to the server. **Confirmed compatible with steps 1–4.** No
migration/harness change needed for any carrier work.

### 3b. The blocker Q1's earlier draft missed — filterable discovery (P1)

The original proposal (make the *rotating token itself* the service UUID) is
**internally contradictory and not production-viable**:

- Scanners can't filter for a value they don't know in advance. Peers' tokens
  rotate every 15 min and are random — a scanner cannot list them.
- **iOS** `CBCentralManager.scanForPeripherals(withServices:)` requires **exact**
  UUIDs (no masks), and **background** discovery only surfaces peripherals whose
  service UUID you *explicitly* scanned for (Apple: background overflow-area UUIDs
  are visible only to a device explicitly scanning that UUID). A random rotating
  UUID can never be pre-listed.
- **Android** `ScanFilter` supports masked UUID matches natively, **but** the
  pinned `flutter_blue_plus_android 9.0.3` applies an exact `setServiceUuid`
  (no mask exposed); `_darwin 9.0.3` is exact-only too. And today's scan filter
  is `withMsd:[MsdFilter(0xFFFF)]` (`beacon_service.dart:601`), which excludes
  pure service-UUID advertisers entirely.
- My earlier "filter `withServices:[_inRangeServiceUuid]`" note contradicts
  "advertise the token as the UUID" — the fixed discovery UUID and the rotating
  token UUID are not the same value, so that filter would never match the token.

**Correct production shape needs a fixed, filterable discovery UUID plus a
separate channel for the rotating token — and on iOS the only app-settable
advertisement fields are ServiceUUIDs + LocalName** (serviceData and
manufacturerData are ignored by `CBPeripheralManager`). Viable directions, none
free:

- **(a) GATT exchange** — advertise a fixed discovery UUID; on discovery the
  scanner connects and reads the rotating token from a characteristic.
  Cross-platform, background-capable on iOS via state restoration, but heavier
  (a connection per peer) and the biggest change. Most robust for production.
- **(b) Two service UUIDs** — advertise a fixed discovery UUID *and* the
  token-as-UUID; filter on the fixed one, then read the second UUID from the
  discovered peripheral's advertised list. Works **foreground**; iOS background
  moves extra UUIDs to the overflow area (only visible to iOS explicitly scanning
  that UUID) → degrades. Good prototype path.
- **(c) LocalName carries token** — foreground only (iOS strips LocalName in
  background). Prototype-grade.
- **(d) Fixed 16-bit UUID + serviceData** (the Apple/Google ENS pattern) — **not
  app-settable on iOS** (serviceData ignored by `CBPeripheralManager`). Rejected
  at app level.

### 3c. Verdict

**Conditional yes:** approve (b)/(c) as a **foreground experiment** to prove the
byte round-trip and get *some* iPhone→S9 data on a walk. **Do NOT treat Q1 as a
settled production carrier** until a filterable-discovery design (likely (a) GATT,
or accepting foreground-only) is chosen and validated on-device — especially
background Android→iPhone, which is the core empirical unknown.

### 3d. Implementation notes (whichever path)

- **Byte-order round-trip test (required):** the iOS `Guid`-build and the
  scanner's `Guid`→bytes→hex parse must agree, or `advertiser_hex !=
  scanner_recovered_hex`. Add a unit test asserting `parse(build(hex)) == hex`.
- **Scanner companion change:** widen the filter beyond `withMsd:[0xFFFF]`
  (`beacon_service.dart:601`) to include the fixed discovery UUID, and add a parse
  branch. NOTE the existing serviceData fallback (`beacon_service.dart:663`) reads
  *serviceData*, a different AD structure than the service *UUID* — new path.
- **Power slot:** iOS has no TX-power control (`CBPeripheralManager`), so iOS is
  high-power only and loses the feet_30 medium-slot gate regardless of carrier.
  Keep Android on manufacturerData (it still carries the power flag byte).
- **Self-sight guard:** `_ownCorrHexes` must key on the same recovered hex for the
  new path or an iPhone self-sights its own advert.

## 4. Q2 — interim iOS scan-only mode: **YES, ship now**

iPhone skips advertising, keeps scanning + logging RSSI, UI honestly shows "not
discoverable — scanning only" (respects the fail-closed rule). Protocol
untouched, low risk. It is also **functionally required**: because the advertise
guard currently tears down the whole startup (§2), scan-only is what lets the
iPhone scan *at all*. This unblocks the S9 → iPhone calibration curve today.

## 5. Walk expectations (today, with Q2 scan-only)

- ✅ iPhone collects the **S9 → iPhone RSSI curve** — calibration works (this is
  newly enabled by Q2, not something that worked before).
- ✅ Android-side encounters + local one-way cards function.
- ❌ **iPhone ↔ S9 will NOT form confirmed cloud encounters** — #6 step-1
  reciprocity needs both directions within ~3 min by server receipt; the S9
  cannot see the iPhone until Q1 ships. Expected, not a bug.

## 6. Suggested sequencing (corrected)

1. **Now:** iOS **scan-only** (Q2) → enables **S9 → iPhone** calibration today.
2. **Next (prototype):** foreground service-UUID advertiser (Q1 path b/c) + both-
   platform scanner parse + round-trip test → restores **iPhone → S9** and
   **iPhone ↔ iPhone** in the foreground.
3. **Production (design first):** choose the filterable-discovery approach
   (GATT (a), or accept foreground-only), then validate background behavior on a
   walk before calling iOS a shipped carrier.
4. **Unchanged:** #6 server + `BatchTokenSource` need no changes for any carrier —
   `_currentCorrelationId` stays the raw 16 bytes of the server token; only the AD
   field changes. Security harness unaffected (SQL layer never sees the carrier).

## 7. Correction to `IOS_ADVERTISING_CARRIER.md` (partner doc)

Its iBeacon rejection rationale is factually wrong: iBeacon is a **128-bit
proximity UUID + 16-bit major + 16-bit minor** (20 identifier bytes), not "only
four identifier bytes." iBeacon is still unsuitable, but for the **right**
reasons: the scanner needs a *known* proximity UUID (same discovery problem as
§3b), and iBeacon has no background advertising. Recommend updating that line so
the record isn't wrong.

## 8. Open empirical unknowns a reviewer/tester must close on-device

- Does `flutter_blue_plus` report a full 128-bit custom advertised service UUID
  in `advertisementData.serviceUuids` in a form convertible to the exact 16 bytes
  (some stacks short-form 16-bit UUIDs)? Verify on-device.
- Does foreground iOS service-UUID advertising reach an Android scanner at useful
  range on a walk? (The core unknown.)
- Background Android → iPhone visibility — likely poor; must be measured before
  any production claim.
