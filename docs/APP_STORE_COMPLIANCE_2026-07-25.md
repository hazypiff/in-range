# App Store compliance review — 2026-07-25

Handoff for the next coding agent. Every finding below was verified against the
tree at `65349dd` from Linux; none of it required a Mac. Items needing Xcode are
marked. Nothing here is speculative — where I could not verify something, it
says so.

Fix C1 before any TestFlight or App Store build. The rest are paperwork-shaped
but two of them are rejection causes on their own.

---

## C1 — Calibration logging is enabled in `.env` (privacy defect)

**Severity: blocker for any distributed build.**

```
$ grep INRANGE_CALIB_SCAN .env
INRANGE_CALIB_SCAN=true
```

`AppConfig.calibScanMode` gates verbose diagnostics that include **raw
coordinates and the full BLE advert stream**:

- `beacon_service.dart` `_logGpsFix()` — `GpsFix lat=… lon=… acc=…m`
- `beacon_service.dart` `_ingestForeignSample()` — `Advert corr=… rssi=… pw=…`
- `wifi_scanner.dart` — `WifiAp seq=… bssid=… rssi=…`
- `rssi_log` inserts on iOS, and the `rssi_samples` upload path

`.env` is consumed by `--dart-define-from-file` in `build-install-ios.sh` and
`build-install-s9.sh`, so **whatever is in `.env` at build time ships**. A store
build with this true writes user location to the device console.

It is correct to leave `true` for calibration walks. It must be `false` for
anything distributed.

**Fix:** set `INRANGE_CALIB_SCAN=false` before any TestFlight/App Store archive.
Better: make the release build refuse to proceed while it is true — a check in
`build-install-ios.sh` when `--release` is passed costs three lines and removes
the failure mode permanently.

---

## C2 — Unused background mode: `processing` (Guideline 2.5.4)

**Severity: rejection cause.**

`ios/Runner/Info.plist` declares six background modes:

```xml
<string>bluetooth-central</string>
<string>bluetooth-peripheral</string>
<string>fetch</string>
<string>location</string>
<string>processing</string>
<string>remote-notification</string>
```

`BGTaskSchedulerPermittedIdentifiers` lists only `io.inrange.beacon.wake`, and
the only scheduling call in the tree submits a **`BGAppRefreshTaskRequest`**. I
found no `BGProcessingTaskRequest` anywhere.

Guideline 2.5.4: *"Multitasking apps may only use background services for their
intended purposes."* Declaring a mode nothing uses is exactly what it targets,
and it is trivially visible to review.

**Fix:** remove `processing` from `UIBackgroundModes`, or schedule a real
`BGProcessingTaskRequest`. Removing is almost certainly correct.

---

## C3 — `remote-notification` declared with no push capability

**Severity: rejection risk; also means push cannot work.**

`remote-notification` is declared, but **there is no `.entitlements` file
anywhere in `ios/`**, so `aps-environment` is absent. The mode is declared and
unusable.

This resolves as part of the Mac checklist (Push Notifications capability), but
until it does, the same 2.5.4 argument as C2 applies.

**Fix (Xcode):** add the Push Notifications capability, which generates
`Runner.entitlements` with `aps-environment`. Verify the file is added to the
target — two Swift files were already missing from `project.pbxproj` once.

---

## C4 — Privacy manifest is stale (Guideline 5.1.2 / App Privacy accuracy)

**Severity: rejection cause.**

`ios/Runner/PrivacyInfo.xcprivacy` declares these collected types:

```
PreciseLocation, SensitiveInfo, Name, EmailAddress,
PhotosorVideos, OtherUserContent, UserID
```

Since it was written, the app began collecting:

| Data | Where | Declared? |
|---|---|---|
| Coarse geohash (venue hints) | `SubtleWakeService` → `venue_anchors` | **No** |
| Hashed BSSID | `WifiAssist` → `venue_anchors` | **No** |
| Per-advert RSSI + correlation id | `rssi_log` → `rssi_samples` (0056) | **No** |

`NSPrivacyCollectedDataTypeCoarseLocation` is absent and should be present. An
inaccurate manifest or nutrition label is independently a rejection cause, and
this one is inaccurate today.

**Fix:** add `CoarseLocation`. Decide explicitly whether hashed BSSID and RSSI
samples are "Other Diagnostic Data" or "Other Data Types" and declare whichever
applies — they are collected, so *something* must cover them.

---

## H1 — Residency flag flipped on in a gitignored file

**Severity: governance, not compliance — but it feeds C5 below.**

```
INRANGE_LOCATION_RESIDENCY=true
```

This reverses a deliberate default. `LocationKeepalive` is documented OFF
because (a) it couples location to the beacon toggle, contradicting *"the beacon
is a pure BLE switch"* (owner decision 2026-07-21, `beacon_screen.dart:26`), and
(b) its BLE benefit is **unmeasured** — the stated gate is a same-binary A/B on
locked hardware, which has never been run.

Because `.env` is gitignored, this reversal appears nowhere in history. If it is
on for benching, that is fine and expected. It should not become the shipped
default by staying set.

**Fix:** confirm the intent. If it ships on, record the owner decision in
`beacon_screen.dart` next to the one it overrides, and run the A/B first.

---

## C5 — The 2.5.4 narrative for `location` must be honest

**Severity: judgement call at review time.**

The `location` background mode originally existed to keep the process resident
so BLE timers keep firing. An app that holds the location background mode and
**discards every fix** is the textbook 2.5.4 problem: if you never use the
location, you have no business holding the mode.

The subtle-wake work improves this materially — SLC, region monitoring and venue
anchors are genuine location features, so the mode now serves a location
purpose. Keep it that way:

- The review narrative is **"location powers venue-based encounter matching."**
  It is not "location keeps Bluetooth awake."
- If residency ships on (H1) while its fixes are discarded, that argument gets
  weaker, not stronger.
- `NSLocationAlwaysAndWhenInUseUsageDescription` currently reads *"Background
  location lets In Range detect encounters while the app is not open."* That is
  accurate for the subtle-wake design. Do not let it drift.

---

## What is already in good shape

- `UIBackgroundModes` correctly declares both BLE modes for a peripheral+central
  app; that is the supported shape for this product category.
- Usage strings exist for Bluetooth (always + peripheral), location (when-in-use
  + always), camera, and photo library, and each describes a real feature.
- `NSPrivacyTracking` is `false` with an empty `NSPrivacyTrackingDomains` — no
  IDFA, no ATT prompt needed.
- The Play prominent-disclosure gate (`PermissionService.requestBackgroundLocation`,
  fail-closed: *no disclosure, no request*) is the right pattern and native code
  no longer bypasses it.
- Server-side deletion, export and retention now cover every table the client
  writes, verified by `scripts/rehearse_migrations.sh`.

---

## Things that will get an app pulled — confirmed absent, keep them absent

Checked and **not present**, which is correct. Do not let any future "keep the
app alive" work reintroduce them:

- **Silent audio session** as a background keepalive — App Review rejects it.
- **VoIP / PushKit push** in a non-VoIP app — Apple closed this in iOS 13
  specifically because apps used it as a background keepalive.
- **Find My network** — MFi hardware only, no public API. Do not design around it.

If a future agent proposes any of these as a way to improve dark-iPhone
discovery, that is the reason to refuse.

---

## Checklist before submission

- [ ] `INRANGE_CALIB_SCAN=false` in the build `.env` (**C1** — do not skip)
- [ ] Decide `INRANGE_LOCATION_RESIDENCY` deliberately; record it (**H1**)
- [ ] Remove `processing` from `UIBackgroundModes` (**C2**)
- [ ] Add Push Notifications capability → `Runner.entitlements` (**C3**, Xcode)
- [ ] Add Access WiFi Information capability — without it `WifiAssistPlugin`
      returns nil on every device, so the WiFi leg does nothing today (Xcode)
- [ ] Add `CoarseLocation` + cover hashed BSSID / RSSI samples in
      `PrivacyInfo.xcprivacy` (**C4**)
- [ ] Confirm every new file is in the Runner target in `project.pbxproj` —
      this has already been wrong once and the build failed silently
- [ ] App Privacy answers in App Store Connect match the manifest

## Not verifiable from Linux

Everything above was checked by reading the tree. These need the Mac:

- Whether the project actually compiles — roughly 400 lines of Swift across
  `BackgroundLocationCoordinator.swift`, `WifiAssistPlugin.swift` and
  `SubtleWakeCoordinator.swift` have never been through a compiler.
- Whether capabilities were added to the right target and configuration.
- Whether background location, SLC and region wakes behave as designed on a
  locked device.
