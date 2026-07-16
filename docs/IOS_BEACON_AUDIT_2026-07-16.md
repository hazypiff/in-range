# iOS beacon start-failure audit — 2026-07-16

**Device:** iPhone 14 (iOS 26.5.2) · **Machine:** Mac (Tahoe 26.5.2, Flutter
3.44.6, Xcode 26.5) · **Status:** ROOT-CAUSED. Permission bug **FIXED**; a
second, deeper blocker (iOS advertising) surfaced behind it and is **deferred
to hazypiff** — see `docs/IOS_ADVERTISING_CARRIER.md`.

## RESOLUTION (permission gate)

On-screen diagnostic returned:
`loc=granted locAlways=permanentlyDenied btScan=denied btAdv=denied btConn=denied bt=granted`

**Root cause:** `PermissionService.requestForegroundBle()` required
`bluetoothScan` + `bluetoothAdvertise` to be *granted*. Those are **Android 12+
only** permissions (`BLUETOOTH_SCAN`/`ADVERTISE`); on iOS permission_handler
returns them permanently `denied`. So the gate could never pass on any iPhone
— the beacon was unreachable on iOS regardless of build or settings. The
real iOS permission (`bluetooth`) was granted the whole time. Fixed: the gate
is now platform-branched — iOS checks `Permission.bluetooth` only.

The Podfile `PERMISSION_*` macros (added earlier this session) were also a
genuine latent bug (permission_handler compiles handlers out without them),
kept. The `strings`-based binary gate used mid-debug is unreliable on Dart AOT
snapshots (false negatives) — do not trust it.

## SECOND BLOCKER (now the real one) — iOS advertising not implemented
Fixing permissions let the beacon reach `_startAdvertisingLocked`, which
**deliberately throws on iOS** (`beacon_service.dart:454`): the token rides in
BLE manufacturerData, which the iOS `flutter_ble_peripheral` bridge can't
send. Correct fail-closed guard, not a bug. Full spec + options handed to
hazypiff in `docs/IOS_ADVERTISING_CARRIER.md`.

---
_Original investigation below (permission hunt) kept for the record._

---

## Symptom

Tapping the beacon toggle shows *"Beacon stayed off — check location
permission + Bluetooth"* immediately. No iOS permission prompt ever appears
for the beacon path. The iOS beacon has **never** been on (yesterday's blocker
was missing crypto secrets; after fixing that with the shared `.env`, this
appeared). Android beacon works.

## Code-path fact (from `beacon_screen.dart`)

That exact message fires ONLY on the silent-denial path:
`PermissionService.requestAllForBeacon()` returned `canUseBeacon=false`
without an exception. Config/crypto/sign-in failures throw `StateError` and
render a different message. So this IS a permission-gate failure —
`locationWhenInUse`, `bluetoothScan`, or `bluetoothAdvertise` reporting
not-granted, instantly, with no prompt.

## Found & fixed along the way (real bug, kept)

`ios/Podfile` had **no `PERMISSION_*` macros** — `permission_handler` compiles
its iOS handlers OUT without them, making every request return denied with no
prompt and no log. Fixed in the Podfile post_install
(PERMISSION_LOCATION/WHENINUSE, BLUETOOTH, CAMERA, PHOTOS, NOTIFICATIONS);
verified present in `Pods.xcodeproj` (12 build configs). **This fix is
necessary but was not sufficient** — symptom persists.

## Verified NOT the cause

- Info.plist: NSBluetooth*/NSLocation* usage strings + UIBackgroundModes
  present since the scaffold commit.
- User-verified on device: master Location Services ON; In Range = While
  Using; Privacy → Bluetooth → In Range ON.
- Secrets: config boot line shows cloud connected, reveal 0, calib on.
- Same failure on debug and release builds → not a build-mode artifact.

## Open hypotheses (in likelihood order)

1. `permission_handler` 11.x iOS mapping quirk: `bluetoothScan`/`bluetoothAdvertise`
   may report from `CBCentralManager`/`CBPeripheralManager` state in a way that
   returns denied/restricted despite the Settings toggle (e.g. manager not yet
   instantiated). Would explain: no prompt + all Settings look correct.
2. `locationAlways.request()` interplay marking the WhenInUse result stale.
3. Stale permission state cached by iOS for the app — deleting the app from
   the phone and reinstalling resets ALL permission records (untested).

## Diagnostic shipped (this commit)

`PermissionService.diagnose()` — the refusal message now prints every
permission's actual status on-screen, e.g.
`Beacon stayed off — loc=granted locAlways=denied btScan=denied ...`.
No debug tether needed (the Mac↔iPhone debug attach was unreliable today:
repeated CoreDevice tunnel wedges; killing stray `devicectl` processes and
`CoreDeviceService`/`remotepairingd` un-wedges it — replug as last resort).

## Next actions

1. Read the on-screen statuses from the new build; fix the named permission.
2. If statuses look granted yet gate still fails → instrument
   `requestForegroundBle` return path (bug in our gate logic).
3. If `btScan/btAdv` denied despite Settings → delete app + reinstall (fresh
   permission state), grant prompts on first tap.
4. Fold the verdict back into this doc and close it.
