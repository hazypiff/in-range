# S22 ↔ iPhone Locked-Bridge Walk — Operator Checklist

Walk date: 2026-07-25

Freeze: `calib-freeze-2026-07-24b`

Freeze commit: `1a41d59`

Pair: Galaxy S22 ↔ iPhone 15 Plus

Capture path: S22 logcat + iPhone SQLite over USB

## Decision

Run the existing freeze. Do not cut or install a build from current `main`.

This walk does not need:

- migration `0055` or `0056`;
- `supabase db push`;
- the calibration RSSI uploader;
- `cloud:<device_id>`;
- location residency; or
- a new freeze.

Migration `0056` is not deployed, and the `07-24b` build does not contain the
uploader. That is intentional. USB is the source of truth for this walk.

Current `main` contains client changes after the freeze. Building from `main`
would add a failing upload retry against the absent RPC and would make the
capture script reject the S22 as a client-code mismatch.

## Exact scope

This checklist assumes “the full ladder” means the documented repeat of the
provisional S22 ↔ iPhone calibration:

| Station | Distance | Dwell |
|---|---:|---:|
| 1 | 25 ft | 90 s |
| 2 | 65 ft | 90 s |
| 3 | 90 ft | 90 s |
| 4 | 130 ft | 90 s |
| 5 | 175 ft | 90 s |
| 6 | 200 ft | 90 s |

This is **not** the `WALK4_PROTOCOL.md` S9/Wi-Fi experiment with 5–50 ft and
indoor room stations.

The walk measures a warm-start, locked-screen bridge:

- iPhone 15 Plus remains at the origin, off-body, propped in a fixed
  orientation;
- both Beacon sessions are started while foregrounded at each station;
- both screens are then black for the measured dwell;
- S22 is the walking phone;
- S22 spends the first 45 s pocketed and the second 45 s in hand at chest
  height, facing the iPhone; and
- both directions are captured simultaneously.

It does not test two dormant iPhones discovering each other cold.

Expected directions:

| Capture side | Physical direction | Expected shape |
|---|---|---|
| S22 logcat | iPhone → S22 | Dense locked-iPhone bridge samples |
| iPhone `rssi_log` | S22 → iPhone | Sparse/coalesced return samples and wake bursts |

Sparse iPhone return data is a result, not permission to substitute S22 data
for both directions.

## Hard no-go actions

- Do not run `supabase db push`.
- Do not install current `main` (`614f5ff` or later) on either walk phone.
- Do not set `ALLOW_BUILD_MISMATCH=1`.
- Do not enable `INRANGE_LOCATION_RESIDENCY`.
- Do not use `--allow-seq-gaps`; this is a USB capture.
- Do not include the Pixel proxy or IG-fleet S9 `3931395a4d583398`.
- Do not use cloud extraction for this walk.
- Do not force-quit the iPhone app after the walk and before its buffer flush.

## 1. Confirm the freeze

Run from the repository containing the current capture scripts:

```bash
git fetch --tags
git rev-parse --short 'calib-freeze-2026-07-24b^{commit}'
```

Required output:

```text
1a41d59
```

The host repository may remain on `main` for capture and extraction. Only an
app rebuild must be performed from the freeze tag.

If either installed build is uncertain, stop and follow
`docs/RAHUL_REINSTALL.md` from the exact tag. Use an iOS **release** build.
Do not rebuild merely for convenience if both phones are already verified on
the freeze.

## 2. Device and environment checks

Before running prep:

- S22 and iPhone battery at least 80%;
- Low Power Mode / Battery Saver off;
- Bluetooth on;
- Airplane Mode off;
- Wi-Fi on, but hotspot/tethering off on both phones;
- cellular/network available independently if the frozen token flow needs it;
- automatic date, time, and time zone enabled on the host and both phones;
- iPhone release app launches without a signing-expiry error;
- both phones show the expected test accounts;
- location and Bluetooth grants have not been revoked; and
- measured course is open line-of-sight and reaches 200 ft.

Check Android USB scope:

```bash
adb devices
```

Only the S22 should be an active, non-protected walk device. Unplug any other
Android device rather than depending on exclusions.

Check iPhone visibility:

```bash
xcrun devicectl list devices
flutter devices
```

The iPhone must be unlocked and trusted by the Mac.

## 3. Run the fail-closed Android prep

Use the same name for prep and pull:

```bash
bash scripts/walk_capture.sh prep s22-iphone15p-locked
```

This must:

- resolve `calib-freeze-2026-07-24b` to `1a41d59`;
- report the S22 build as `ok`;
- resize the S22 logcat buffer to 64M;
- clear the buffer;
- verify the buffer is not already consumed; and
- write
  `run_logs/walks/2026-07-25-s22-iphone15p-locked/meta-prep.json`.

Any `FAIL`, build mismatch, dirty build, buffer error, or missing app is a
hard stop. Do not override it.

There is no equivalent installed-commit check for iOS. The iPhone build
remains a procedural verification: known release build from `07-24b`, installed
and launched successfully.

## 4. Mandatory bilateral desk smoke

Do this after prep so its records prove the calibration flag is active.

1. Place the phones about 1 m apart.
2. Open In Range on both.
3. Turn Beacon on on both.
4. Keep both foregrounded for 60 seconds.
5. Confirm each phone sees the other.
6. Confirm the S22 produced calibration records:

```bash
adb logcat -d -v threadtime | rg 'Advert corr=' | tail -n 10
```

7. Confirm the iPhone database has a fresh return-direction burst:

```bash
bash scripts/ios_station_check.sh 15p
```

If either direction is empty, stop. A green Beacon toggle is not enough; a
phone can advertise while its scanner is unhealthy.

After the smoke test, turn both Beacons off before travelling to station 1.
Smoke rows remain safe because the extractor uses explicit station windows.

## 5. Prepare the station record

Use the same clock as the prep host, or a watch visibly synchronized to it.
Record the exact Beacon-on/start time for every station.

Suggested local-only `stations.json` template:

```json
[
  {"label": "25ft",  "start": "HH:MM:SS", "dur": 90},
  {"label": "65ft",  "start": "HH:MM:SS", "dur": 90},
  {"label": "90ft",  "start": "HH:MM:SS", "dur": 90},
  {"label": "130ft", "start": "HH:MM:SS", "dur": 90},
  {"label": "175ft", "start": "HH:MM:SS", "dur": 90},
  {"label": "200ft", "start": "HH:MM:SS", "dur": 90}
]
```

Store it under the walk directory. `run_logs/` is local-only and gitignored.

Also record, separately:

- actual measured distance;
- the pocket → hand transition time, expected at start +45 s;
- any accidental screen wake;
- any phone movement or orientation change;
- any call, notification, Bluetooth interruption, or app error;
- weather/crowd obstruction; and
- whether a station was repeated.

## 6. Run every station identically

At each distance:

1. Keep both Beacons off while moving into position.
2. Keep the iPhone at the same origin, off-body, orientation, and height.
3. Move only the S22 to the measured distance.
4. Wait 10 seconds for both phones and the environment to settle.
5. Open both apps and turn both Beacons on.
6. Record that instant as the station start.
7. Lock both screens and verify they go fully black.
8. Put the S22 in the same pocket used at every station.
9. At +45 s, move the S22 to the same chest-height hand orientation without
   waking its display.
10. At +90 s, end the dwell and record any deviation.
11. Turn both Beacons off.
12. Move to the next station.

The iPhone remains propped at the origin. Do not pocket it during this ladder.

If a screen wakes briefly because of an ordinary notification, write it down.
If an app is foregrounded or the display remains lit for a material part of
the dwell, repeat the station; foreground and locked samples must not be mixed
without a label.

Do not inspect live UI counts during a measured dwell. That changes the
lifecycle being measured.

## 7. Flush the iPhone before copying

After station 6:

1. Open the iPhone app normally.
2. Leave it foregrounded and unlocked for at least 15 seconds.
3. Do not force-quit it.

Foregrounding is load-bearing. Native locked-screen sightings are buffered and
only enter Dart/SQLite after the engine is active. Copying first can produce an
empty or truncated `rssi_log`.

The final USB copy and SQLite query below verify the flush. The last station may
still contain no iPhone-side rows because the return direction is sparse and
200 ft previously reached its detection ceiling.

## 8. Pull both sources

Pull the Android log and re-measure its host clock offset:

```bash
bash scripts/walk_capture.sh pull s22-iphone15p-locked
```

This must create:

- one S22 `.threadtime.log.gz`;
- `meta-pull.json`; and
- the already existing `meta-prep.json`.

Copy the iPhone database into the same walk directory:

```bash
xcrun devicectl device copy from \
  --device <IPHONE_DEVICE_ID> \
  --user mobile \
  --domain-type appDataContainer \
  --domain-identifier io.inrange.inRange \
  --source Documents/in_range_local.db \
  --destination run_logs/walks/2026-07-25-s22-iphone15p-locked/iphone15p.db
```

Preserve the raw `.gz`, `.db`, both meta files, station record, and field
notes. They contain sensitive location/device information and remain local;
do not commit or paste their contents into chat.

## 9. Immediate integrity checks

Confirm the archive:

```bash
ls -lh run_logs/walks/2026-07-25-s22-iphone15p-locked
```

Confirm Android observations exist:

```bash
gzip -cd run_logs/walks/2026-07-25-s22-iphone15p-locked/*.threadtime.log.gz \
  | rg -c 'Advert corr='
```

Confirm iPhone rows exist and span the walk:

```bash
sqlite3 run_logs/walks/2026-07-25-s22-iphone15p-locked/iphone15p.db \
  'SELECT COUNT(*), datetime(MIN(at_ms)/1000,"unixepoch","localtime"), datetime(MAX(at_ms)/1000,"unixepoch","localtime") FROM rssi_log;'
```

Inspect the pull metadata and copy the S22 `host_minus_device_s` value:

```bash
jq '.devices[] | {label, build, host_minus_device_s}' \
  run_logs/walks/2026-07-25-s22-iphone15p-locked/meta-pull.json
```

Do not leave the site until:

- the S22 advert count is nonzero;
- iPhone `rssi_log` is nonempty;
- at least one iPhone row lands inside the recorded walk windows;
- `meta-prep.json` and `meta-pull.json` exist;
- all six station start times are recorded; and
- field notes identify every lifecycle deviation.

## 10. USB extraction command

Use S22 as side A and iPhone as side B:

```bash
python3 scripts/extract_walk.py \
  run_logs/walks/2026-07-25-s22-iphone15p-locked/<S22_LOG>.threadtime.log.gz \
  run_logs/walks/2026-07-25-s22-iphone15p-locked/iphone15p.db \
  --stations-file run_logs/walks/2026-07-25-s22-iphone15p-locked/stations.json \
  --ios-date 2026-07-25 \
  --offset-a <S22_HOST_MINUS_DEVICE_S> \
  --pair s22-iphone15p \
  --capture-meta run_logs/walks/2026-07-25-s22-iphone15p-locked/meta-pull.json \
  --freeze calib-freeze-2026-07-24b \
  --json run_logs/walks/2026-07-25-s22-iphone15p-locked/walk.json \
  --csv run_logs/walks/2026-07-25-s22-iphone15p-locked/walk.csv
```

Do not add `cloud:<device_id>` or `--allow-seq-gaps`.

The mixed pair intentionally has no iPhone Wi-Fi/GPS stream, so venue and GPS
fusion fields will abstain. This walk validates BLE carrier behavior and
per-direction observations, not the three-radio fusion model.

## Trainability decision

Archive the walk even if the locked iPhone return direction is sparse.

Mark it trainable only after extraction confirms:

- measured station distances;
- all station clocks are usable;
- no mixed foreground/locked station;
- expected source ordering;
- useful coverage across the ladder; and
- no capture loss.

If a protocol or capture failure occurred, rerun extraction with
`--trainable no`. Never conceal a loss by changing a station window or
accepting a cloud sequence gap.

## Final departure gate

- [ ] `07-24b` resolves to `1a41d59`
- [ ] S22 passes `walk_capture.sh prep`
- [ ] iPhone is a known `07-24b` release build
- [ ] calibration rows proved on both devices
- [ ] hotspot off; Bluetooth and automatic time on
- [ ] 25/65/90/130/175/200 ft measured
- [ ] timing record ready
- [ ] iPhone origin placement fixed
- [ ] protected devices absent
- [ ] no migration, cloud upload, residency, or new build introduced

If any box is false, fix it at the desk rather than at the trailhead.
