# Reinstall before the next walk — S22 + iPhone 15 Plus

Both your devices are running builds from **before `95c6eae`**. They're missing two
changes that alter what we measure, so any walk on the current installs isn't
comparable to the S9 data:

- **`95c6eae` — W3 connect-read went native Android.** Changes W3 behavior. This one
  hits the **S22**, not the iPhone.
- **`2383fdd` + server migration `0053` — client timestamp pass-through.** Without it a
  locked iPhone's late flush misses the 15-minute late-evidence window, so encounter
  confirmation timing reads differently.

Takes about 15 minutes for both.

---

## 0. Get the code (once, covers both phones)

```bash
cd ~/in-range
git fetch --tags
git checkout calib-freeze-2026-07-24b
```

This puts you on a detached HEAD — that's expected and correct for a calibration round.

> Note the **07-24b** suffix. This additive freeze includes the locked-phone wake-log
> instrumentation needed for the baseline walk. The published 07-24 tag still exists
> and was not moved.

**Check `.env`** — it's gitignored, so it survives a checkout, but confirm **both** keys.
Run these before you build, not after:

```bash
grep SUPABASE_URL .env         # expect riigipzlyqeaadyvbuty.supabase.co
grep INRANGE_CALIB_SCAN .env   # MUST be true — see below
```

If `SUPABASE_URL` is missing, copy `.env` over from the Linux box (see `docs/MAC_SETUP.md` §1).

⚠️ **If `INRANGE_CALIB_SCAN` is missing or `false`, add `INRANGE_CALIB_SCAN=true` and rebuild.**
This single key gates every line the walk produces — the `Advert` and `WifiAp` entries the
extractor parses, the lat/lon on `GpsFix`, and `rssi_log` inserts on the iPhone. It defaults
to **false**, and a walk with it off looks completely normal the whole way through: the app
runs, the phones pair, nothing errors. You find out the walk was empty at extraction, hours
later. It was absent from `.env.example` until 2026-07-24, so an `.env` created from that
template does not have it.

---

## 1. S22 (Android) — 5 min

Plug in the S22, USB debugging on, then:

```bash
adb devices                       # confirm ONLY the S22 is listed
bash scripts/build-install-s9.sh
```

The script permanently protects the Pixel proxy and IG-fleet S9
`3931395a4d583398`. It still installs to every other connected Android, so unplug
anything else that is not part of this build.

It builds a multi-ABI debug APK, installs with `-r`, force-stops, and relaunches
`io.inrange.app`. When it prints `Done. Multi-ABI APK on 1 device(s).` you're good.

Sanity-check the stamp — it should equal the freeze commit, with **no** `-dirty`
suffix:

```bash
git rev-parse --short 'calib-freeze-2026-07-24b^{commit}'
adb shell dumpsys package io.inrange.app | grep -m1 versionName
```

`walk_capture.sh prep` now checks this automatically on every connected Android and
refuses to start the capture if it doesn't match, so a stale S22 can't quietly poison
a round again.

---

## 2. iPhone 15 Plus — 10 min

Plug in, unlock, **Trust This Computer**, then:

```bash
flutter devices                              # confirm the iPhone shows up
bash scripts/build-install-ios.sh --release
```

**Use `--release`, not debug.** Debug builds stay attached to the Mac and die when you
unplug — useless for a walk. Release persists standalone.

After the first install: **Settings → General → VPN & Device Management → trust your
developer certificate**, or the app installs but refuses to launch.

### The 7-day thing

On a free Apple account the provisioning profile expires after **7 days** and the app
stops launching. Until we pay the $99/yr Developer Program:

**Rebuild the morning of each walk, not "sometime that week."** If the cert lapses
mid-session you get a silently truncated leg, and under the fail-closed gates that's a
wasted walk rather than a partial one.

---

## 3. Verify before you walk

1. Both phones: open the app, confirm **Cloud connected**.
2. Desk check — phones ~1 m apart, confirm **mutual** sighting (each sees the other,
   not just one direction). Per-direction tiers are load-bearing now, so a
   one-directional desk check doesn't prove anything.
3. Confirm rows are landing in `rssi_log` for **both** directions.

If mutual sighting fails on the desk, stop — don't burn a walk on it.

---

## 4. During the walk

- Protocol unchanged: `docs/WALK4_PROTOCOL.md` — stop-and-return, 90 s per station,
  explicit host-clock stop times, beacon off between stations.
- **Record per station which lifecycle the iPhone was in** (foreground vs locked).
  Locked-iPhone RSSI arrives in wake-bursts and via Android-side GATT-anchored
  sightings — a completely different sampling shape. Mixing them unlabelled makes the
  station unusable.
- Capture **both directions'** logs, not just one.

Extraction (unchanged):

```bash
python3 scripts/extract_walk.py --pair <pair> \
  --capture-meta <meta-pull.json> \
  --freeze calib-freeze-2026-07-24b
```

---

## One heads-up on your earlier sweep

The S22↔iPhone six-station sweep (`978001b`) that produced the per-direction cutoffs in
`docs/PROXIMITY_TIERS.md` was collected **before** `95c6eae` — i.e. on pre-native-GATT
behavior. The doc already marks those cutoffs provisional; this is the concrete reason
to re-confirm them on the current build rather than treating them as settled.
