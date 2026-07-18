# Walk #4 — the calibration walk

One walk, three radios, every remaining unknown. The phones are already built,
installed, and beaconing — nothing to set up.

> Logistics (who needs a computer when, Android vs iPhone capture paths,
> and the requirements for a walk to join the training dataset):
> **docs/WALK_LOGISTICS.md** — required reading before running a walk.

**What this walk decides:**
1. The **Near** tier's real distance (BLE medium-power cutoff) — the last uncalibrated number.
2. Whether **WiFi can tell "same room" from "next room"** — and at what score.
3. Whether **body-blocking** is distinguishable from distance when WiFi is added.
4. What GPS accuracy actually is, indoors and out.

---

## Before you leave

0. **Run `bash scripts/walk_capture.sh prep`** (phones plugged in). It resizes
   every phone's logcat ring buffer (64M — 16M was ~60% consumed before full
   WiFi AP logging existed), **verifies the effective size and aborts if the
   resize didn't take**, and records each phone's clock offset vs this laptop
   into `run_logs/walks/<date>/meta-prep.json`. Note: resizing clears the
   buffer, which is exactly what you want pre-walk.
1. **Turn the phones' WiFi hotspot/tethering OFF** (leave WiFi itself ON).
   An active hotspot shares the 2.4 GHz antenna with the BLE scanner and is a
   self-inflicted handicap — every previous walk ran with `pixhub` tethering
   active on both phones. WiFi must stay *on* so it can scan for access points.
2. Both beacons **ON** (they already are). Don't touch them again.
3. **Screens dark.** They stay dark the whole walk — that is now proven to work.
4. **Measure the distances.** Tape, or counted paces you've calibrated. The
   footage errors in walks #1–#2 are exactly why we're redoing this.

---

## Part A — outdoors, measured distances (the Near tier)

Six stops, **90 seconds each**, phones **off-body** where possible (set them on
a chair/ledge/ground facing each other — a torso costs more dB than 40 feet of air):

| Stop | Distance |
|---|---|
| 1 | **5 ft** |
| 2 | **10 ft** |
| 3 | **15 ft** |
| 4 | **25 ft** |
| 5 | **35 ft** |
| 6 | **50 ft** |

Then **two body-blocked repeats**, 90 s each — same distance, but you stand
directly between the phones:

| Stop | Distance | Note |
|---|---|---|
| 7 | **10 ft** | body in the path |
| 8 | **35 ft** | body in the path |

These two are what prove (or kill) the blocked-vs-far rule.

## Part B — indoors, same-room vs next-room (the WiFi venue layer)

WiFi fingerprinting only works where there are access points. Do this **inside**,
90 s per stop:

| Stop | Setup |
|---|---|
| 9 | Both phones **same room**, ~10 ft apart |
| 10 | Both phones **same room**, opposite corners |
| 11 | **Different rooms**, one wall between |
| 12 | One phone inside, one **outside the building** (~30 ft) |

This is the only part that can calibrate the venue score. If your home has few
access points, a café/store/mall does this far better — denser APs, and it's the
real target environment anyway.

---

## What to record

**The clock time (this laptop's / your watch synced to it) at the start of each
stop.** That's it. Stops do NOT need to be back-to-back — the extractor takes
an explicit start time per station and handles gaps (stop-and-return is the
validated method per DEVICE_TESTING_JOURNAL 2026-07-17). Say the times and
I'll do the rest — the phones are logging every BLE advert, every WiFi
fingerprint, and every GPS fix with its accuracy.

If something feels wrong, keep going. The logs will tell us.

Optional live view while walking (tethered/wireless adb):
`CALIB=1 bash scripts/beacon_monitor.sh` (Work repo) — shows the calibration
record types streaming. View only; extraction uses the raw dumps below.

---

## When you're back

Plug both phones in, run **`bash scripts/walk_capture.sh pull`** (raw
threadtime dumps → dated gzip archive + `meta-pull.json` with clock offsets),
and say **"extract"** with the station times. Extraction:

```
python3 scripts/extract_walk.py <A>.threadtime.log.gz <B>.threadtime.log.gz \
    --stations 5ft@HH:MM:SS+90 10ft@HH:MM:SS+90 ... \
    --offset-a <A host_minus_device_s> --offset-b <B ...> \
    --json walk.json --csv walk.csv
```

You'll get: the Near tier's real cutoff, the venue-score thresholds measured
rather than guessed, a verdict on blocked-vs-far, GPS's true error, and the
fusion table with every number in it earned.
