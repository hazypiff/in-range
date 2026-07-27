# S22 ↔ iPhone Locked-Bridge Walk — Operator Checklist

Walk date: 2026-07-25

Freeze (installed apps): `calib-freeze-2026-07-24b` → `1a41d59`

Host scripts: current `main`, including absolute-time station checks, thin
median rejection, and body-position filtering (`9ced273` alone only surfaces
thin stations)

Pair: Galaxy S22 ↔ iPhone 15 Plus

Capture path: S22 logcat + iPhone SQLite over USB

Root-cause report (why these corrections exist):
[`IPHONE_WALK_ROOT_CAUSE_REPORT_2026-07-24.md`](IPHONE_WALK_ROOT_CAUSE_REPORT_2026-07-24.md)

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

**Do not** require a USB-vs-cloud `walk_id` match. That equality only checks
cloud upload losslessness; cloud does not exist on this freeze.

Current `main` contains client changes after the freeze. Building from `main`
would add a failing upload retry against the absent RPC and would make the
capture script reject the S22 as a client-code mismatch. The **host** may stay
on current `main` for capture/extract scripts; only the **phone apps** must
remain on `07-24b`. Do not reset the host to `9ced273`: that commit surfaces
thin counts but predates the exact-window checker and ingest protections.

## What this walk does NOT measure

Read this before quoting the results. All three were verified against the
freeze build itself (`1a41d59`), not against `main`.

**No connected-RSSI / GATT link quality.** `git grep -E "readRSSI|connected_rssi"`
returns nothing in `lib`, `ios` or `android` at the freeze, and
`extract_walk.py` parses no GATT line. This walk measures the **advert
detection envelope** — scan RSSI plus token recovery — i.e. the distance at
which the S22 stops being able to see and identify a locked iPhone. It is NOT
the distance at which a persistent GATT link dies; W5 (the persistent
GATT + `readRSSI()` loop) is still unbuilt. A curve from this walk must never
be described as connected-link quality.

**No `med_n` from the locked iPhone.** `beacon_service.dart:60` hardcodes
`AdvertPower.high` for every background sighting, because the native channel
signature is `onSighting(String tokenHex, int rssi, DateTime at)` — the
medium/high slot is discarded before Dart sees it. So `med_n` reads **0 at
every station** on the iPhone side, meaning *unknown*, not *no medium packets
arrived*. Do not read it as evidence, and do not let a model lean on it: it
would learn "iPhone ⇒ far". (Same class of trap as the thin medians fixed in
`9ced273`, but this one needs a client change, so it cannot be fixed for this
walk.)

**No WiFi and no GPS from the iPhone.** `rssi_log` is BLE-only, so `venue_v`
and `gps_delta` come out `None` for every iPhone-side station. That is correct
and safe — `train.py:73-74` skips a `None` feature rather than imputing zero —
but it means the iPhone contributes BLE features only.

What the walk DOES produce: a trainable advert-detection curve for
S22 ↔ locked iPhone across six distances and two body positions, in both
directions. That is the most valuable iPhone dataset collected so far. It is
just narrower than "the GATT range envelope", which is how it has been
described in conversation.

## Exact scope

This checklist assumes “the full ladder” means the documented far-envelope
repeat of the provisional S22 ↔ iPhone calibration (single-tier pivot:
where detection dies, not a dense close-only ladder):

| Field stop | Distance | Physical dwell | Extract stations |
|---|---:|---:|---|
| 1 | 25 ft | 90 s | `25ft-pocket` 45 s + `25ft-hand` 45 s |
| 2 | 65 ft | 90 s | `65ft-pocket` + `65ft-hand` |
| 3 | 90 ft | 90 s | `90ft-pocket` + `90ft-hand` |
| 4 | 130 ft | 90 s | `130ft-pocket` + `130ft-hand` |
| 5 | 175 ft | 90 s | `175ft-pocket` + `175ft-hand` |
| 6 | 200 ft | 90 s | `200ft-pocket` + `200ft-hand` |

**Why two extract stations per distance:** `extract_walk.py` does not split a
window into pocket/hand. One 90 s median averages ~15 dB body-position
difference into a number that describes neither. Labels like `25ft-pocket`
still parse to `distance_ft = 25` via `learn/ingest.py`'s `DIST_RE`.

If time forces a cut: drop middle distances first (90, then 130). Keep 25 and
200 — ends bracket the drop-off.

This is **not** the `WALK4_PROTOCOL.md` S9/Wi-Fi experiment with 5–50 ft and
indoor room stations. Dwell is **90 s**, not 60 s.

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
4. Record the host-clock instant when both are on as `<SMOKE_START>`.
5. Keep both foregrounded for 60 seconds.
6. Confirm each phone sees the other.
7. Confirm the S22 produced calibration records:

```bash
adb logcat -d -v threadtime | rg 'Advert corr=' | tail -n 10
```

8. Confirm that exact iPhone interval has a return-direction burst:

```bash
bash scripts/ios_station_check.sh 15p \
  --date 2026-07-25 --start <SMOKE_START> \
  --window smoke:0:60 --trim 0
```

If either direction is empty, or the foreground iPhone smoke has fewer than
five high-power rows, stop. A green Beacon toggle is not enough; a phone can
advertise while its scanner is unhealthy. This command uses the recorded
clock window, so stale rows from an earlier session cannot make the smoke pass.

After the smoke test, turn both Beacons off before travelling to station 1.
Smoke rows remain safe because the extractor uses explicit station windows.

## 5. Prepare the station record

Use the same clock as the prep host, or a watch visibly synchronized to it.
Record the exact Beacon-on/start time for every distance. Hand half starts at
pocket start + 45 s (same continuous beacon-on dwell). Write the hand clock
time out explicitly; `stations.json` does not evaluate arithmetic.

Suggested local-only `stations.json` template (**12 rows**, pocket then hand):

```json
[
  {"label": "25ft-pocket",  "start": "<25_POCKET_START>", "dur": 45},
  {"label": "25ft-hand",    "start": "<25_START_PLUS_45S>", "dur": 45},
  {"label": "65ft-pocket",  "start": "<65_POCKET_START>", "dur": 45},
  {"label": "65ft-hand",    "start": "<65_START_PLUS_45S>", "dur": 45},
  {"label": "90ft-pocket",  "start": "<90_POCKET_START>", "dur": 45},
  {"label": "90ft-hand",    "start": "<90_START_PLUS_45S>", "dur": 45},
  {"label": "130ft-pocket", "start": "<130_POCKET_START>", "dur": 45},
  {"label": "130ft-hand",   "start": "<130_START_PLUS_45S>", "dur": 45},
  {"label": "175ft-pocket", "start": "<175_POCKET_START>", "dur": 45},
  {"label": "175ft-hand",   "start": "<175_START_PLUS_45S>", "dur": 45},
  {"label": "200ft-pocket", "start": "<200_POCKET_START>", "dur": 45},
  {"label": "200ft-hand",   "start": "<200_START_PLUS_45S>", "dur": 45}
]
```

CLI equivalent (same shape):

```text
# Example only: the hand time is exactly 45 seconds after pocket start.
25ft-pocket@10:00:00+45 25ft-hand@10:00:45+45
```

Store it under the walk directory. `run_logs/` is local-only and gitignored.

Also record, separately:

- actual measured distance;
- the pocket → hand transition time, expected at distance start +45 s;
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
6. Record that instant as the **pocket** station start (`NNft-pocket`).
7. Lock both screens and verify they go fully black.
8. Put the S22 in the same pocket used at every station.
9. At +45 s, move the S22 to the same chest-height hand orientation without
   waking its display; that instant is the **hand** station start
   (`NNft-hand`).
10. At +90 s, end the dwell and record any deviation.
11. Turn both Beacons off.
12. **Mid-walk iPhone check (mandatory between distances):** unlock the iPhone
    and leave the app foregrounded for 15 seconds so native samples flush.
    Then plug in USB and run this with the recorded pocket start:

    ```bash
    bash scripts/ios_station_check.sh 15p \
      --date 2026-07-25 --start <THIS_DISTANCE_POCKET_START>
    ```

    The helper uses the absolute operator clock and the same per-half 10-second
    trim as final extraction. It does **not** anchor the split to the first
    callback; doing that can label a late hand callback as pocket.

    - `n >= 5`: usable RSSI median.
    - `THIN!` (`n = 1..4`): repeat this distance once while geometry is set.
      The final ingest keeps count/rate but rejects this median and IQR.
    - `SILENT` (`n = 0`): no false median. Repeat once if silence is
      unexpected at this distance; at the far ceiling it is valid evidence.

    If repeating, preserve both trials. Append `-r2` windows (for example
    `25ft-pocket-r2` / `25ft-hand-r2`) with the new clocks; never replace the
    first trial after looking at its result.
13. Move to the next station.

The iPhone remains propped at the origin. Do not pocket it during this ladder.

If a screen wakes briefly because of an ordinary notification, write it down.
If an app is foregrounded or the display remains lit for a material part of
the dwell, repeat the station; foreground and locked samples must not be mixed
without a label.

Do not inspect live UI counts **during** a measured dwell. That changes the
lifecycle being measured. Mid-walk checks happen only with beacons off between
distances.

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
- all six physical starts and all twelve pocket/hand window times are
  recorded; and
- field notes identify every lifecycle deviation.

## 10. USB extraction command

Use S22 as side A and iPhone as side B. **Require `--trim 10`** because each
extract window is 45 s; default `--trim 20` would discard 44% of every half.

Host scripts must include the post-`9ced273` exact-window checker and thin
ingest gate:

```bash
python3 scripts/extract_walk.py \
  run_logs/walks/2026-07-25-s22-iphone15p-locked/<S22_LOG>.threadtime.log.gz \
  run_logs/walks/2026-07-25-s22-iphone15p-locked/iphone15p.db \
  --stations-file run_logs/walks/2026-07-25-s22-iphone15p-locked/stations.json \
  --ios-date 2026-07-25 \
  --offset-a <S22_HOST_MINUS_DEVICE_S> \
  --trim 10 \
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

Read the extract table carefully:

- `n` with a trailing `!` means `0 < high_n < 5` — a thin median that *looks*
  like a measurement. Re-walk once if phones/geometry still allow. Current
  `learn/ingest.py` keeps its count/rate but sets its median and IQR missing.
- Product ingest defaults to `--body-position product`: explicitly tagged
  **hand** rows remain archived but do not train the product model. Use
  `--body-position hand` or `all` only for deliberate reference analysis.
- Never train on a single 90 s pocket+hand median.

## Trainability decision

Archive the walk even if the locked iPhone return direction is sparse.

Mark it trainable only after extraction confirms:

- measured station distances;
- all station clocks are usable;
- no mixed foreground/locked station;
- pocket and hand halves logged as separate stations (not one averaged 90 s);
- expected source ordering;
- useful coverage across the ladder;
- thin (`!`) station-sides re-walked once or accepted as count/rate-only; and
- no capture loss.

If a protocol or capture failure occurred, rerun extraction with
`--trainable no`. Never conceal a loss by changing a station window or
accepting a cloud sequence gap.

## Final departure gate

- [ ] `07-24b` resolves to `1a41d59` (installed apps only)
- [ ] host scripts include absolute-time checker + thin-ingest safety
- [ ] S22 passes `walk_capture.sh prep`
- [ ] iPhone is a known `07-24b` release build
- [ ] calibration rows proved on both devices
- [ ] desk smoke ran the dated/start-anchored iPhone check successfully
- [ ] hotspot off; Bluetooth and automatic time on
- [ ] 25/65/90/130/175/200 ft measured
- [ ] `stations.json` has 12 pocket/hand rows (not 6×90 s)
- [ ] plan is `--trim 10` at extract
- [ ] dated/start-anchored iPhone check ran between distances
- [ ] iPhone origin placement fixed
- [ ] protected devices absent
- [ ] no migration, cloud upload, residency, or new phone build introduced

If any box is false, fix it at the desk rather than at the trailhead.

---

# ⚠️ ADDENDUM 2026-07-26 — the build changed. Read before using the gate above.

**The last box of the departure gate — "no migration, cloud upload, residency, or new
phone build introduced" — is now FALSE by design.** Four commits landed on
`feat/ble-prior-art-tier1` after this checklist was written. The gate's build
references (`07-24b` → `1a41d59`) are stale. **Re-validate the build; do not assume
it is the one this checklist was written against.**

No migration, cloud-upload or residency change was introduced. The change is
BLE-layer only, plus one dependency pin.

## What changed, and why it matters to the walk

| Change | Walk impact |
| --- | --- |
| **iPhone→Android detection restored** (B1) | This direction was **broken outright** before: the iPhone saw the Android's CAFE marker, found no token, and fell through to a connect that could never succeed. If prior walks showed a dead iPhone→Android direction, **that is expected and now fixed** — do not re-diagnose it |
| **Scan restart 25 min → 8 min** | Shorter scan sessions. Segment boundaries move |
| **`androidLegacy: true`** | Android now scans legacy-1M only, not both PHYs |
| **Scan retry backoff + 4-per-30 s token bucket** | A scan-start storm can no longer silently wedge the radio |
| **adapterState listener** | A Bluetooth toggle now recovers in seconds instead of up to 25 min |
| **`discoverable` is now composed** | It means advertise-up **AND** receive-path-alive. The badge can now go false with no user action — that is correct, not a bug |
| **flutter_blue_plus pinned 2.3.10 → 1.36.8** | Licensing. Behaviourally equivalent for our six entry points, but it **is** a different plugin build — worth one smoke check that scanning works before departure |

## Instruments — set these or the walk produces less than it should

All of W1–W9 are gated behind `AppConfig.calibScanMode`. **If calib mode is off, you
get no instrument data at all.** Confirm it is on for both devices.

**W8 is the one not to skip:** it logs scan-start outcomes and the gap since the last
scan result *of any kind*. Before this, a dead scanner and an empty room were
indistinguishable, so a silent scan death mid-walk read as "nobody around" and
contaminated the whole segment. **Read W8 first when reviewing the data** — if it
shows a scan death, every other number from that segment is suspect.

**W10:** record the exact OS build of every device, per segment. Android's scan
demotion is 30 min on ≤13 but **10 min on 14+**, where a filtered client is
downgraded *stickily* for the scanner's life. Two handsets on one walk can therefore
run at materially different duty cycles, and their RSSI and detection-rate numbers
are **not comparable**. `platformInfo` on the `io.inrange.app/advert` channel returns
this without touching the radio.

## Run one leg on the OLD scan arm

Two of the shipped changes were originally meant to be measured before shipping, and
shipping them removed the baseline. To recover it, put **one handset on the old arm**:

```
INRANGE_SCAN_LEGACY_ONLY=false     # old: scan both PHYs
INRANGE_SCAN_RESTART_MINUTES=25    # old cadence
```

Defaults are `true` / `8`. The resolved arm is logged unconditionally at every scan
start (`BLE scan arm: …`), so any log can be attributed after the fact. Without an
old-arm leg, W9's gap histogram can only show gaps are *absent* — equally consistent
with the fix working and with the effect never existing on your hardware.

### ⚠️ The two flags need DIFFERENT hardware. Do not set both on one phone.

Verified 2026-07-26: the attached S9s (`SM-G960U`) report **API 29 / Android 10**.

| Flag | Valid on | Why |
| --- | --- | --- |
| `INRANGE_SCAN_LEGACY_ONLY` | **S9 (API 29)** ✅ | `setLegacy`/`setPhy` are guarded at API ≥ 26, so dual-PHY scanning is active. And these are **Samsungs** — exactly the vendor upstream #938 reports the 4-second time-slicing on. The S9 is the *right* phone for this arm |
| `INRANGE_SCAN_RESTART_MINUTES` | **S22 only** (API 34+) | AOSP's 10-minute demotion is **Android 14+**. On API 29 the timeout is **30 minutes**, which the old 25-minute restart already beat — so an 8-vs-25 comparison on an S9 measures **nothing**. The sticky `LOW_POWER` downgrade also only exists on 14+ |

So: run the **legacy-only A/B across two S9s** (one `true`, one `false`, same room,
same leg), and run the **restart-cadence A/B on the S22** if you have a second 14+
handset — otherwise skip that arm and record that it was not testable, rather than
collecting a null result and reading it as a pass.

Also note API 29 puts the S9s in AOSP's **`last_wins`** bucket for duplicate Apple
manufacturer ADs (`appleBlobSemantics`, from `platformInfo`), so any D3 offset
observed on an S9 is the last-AD-wins case and does **not** transfer to Android 15+.

## ⛔ Do not enable these during the walk

- **The native Android scanner** (`AdvertScanner.startScan`). It is a **second**
  `BluetoothLeScanner` registration; it charges the AOSP 5-per-30 s quota, and AOSP
  delivers *no callback at all* when that trips. `platformInfo` and `classify` are
  radio-free and safe. There is a banner in the file.
- **The Apple overflow-bit scan filter.** `apple_overflow_bit.dart` is tested and
  ready but deliberately unwired — it needs a bench measurement first (see
  [`POST_WALK_UPGRADE_QUEUE.md`](POST_WALK_UPGRADE_QUEUE.md) item 1).

## Pulling the data

- Android calib logs: as per the existing capture flow in this document.
- **iOS: `bb_wake_log.txt`** via USB pull from the app's Documents directory. It now
  also carries central- and peripheral-manager state transitions (`central-state:…`,
  `periph-state:…`), change-only. This is the only record of whether iOS granted
  background windows at all, separately from whether anything was seen during them.

## After the walk

[`POST_WALK_UPGRADE_QUEUE.md`](POST_WALK_UPGRADE_QUEUE.md) is the ordered queue, with
the specific instrument that gates each item. Three entries can be **cancelled** by
the data rather than built — check those gates before writing code.

## CI note

The GitHub Actions **account owning the private repo (`inrangeai`) is under a
spending-limit block** — jobs there start and die in ~3 s with a billing annotation,
which looks like a code failure and is not. Public-repo minutes are free and work:

```bash
gh workflow run ios-build.yml --repo hazypiff/in-range --ref feat/ble-prior-art-tier1
```

That is how the current iOS build was verified green (run `30224433032`).
