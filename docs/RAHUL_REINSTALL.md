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
git checkout calib-freeze-2026-07-23     # = 95c6eae
```

This puts you on a detached HEAD — that's expected and correct for a calibration round.

> FYI: right now `main` is identical to the tag for client code — everything since the
> freeze is web/docs/waitlist only, nothing in `lib/`, `android/`, `ios/`, or `scripts/`.
> So `git checkout main && git pull` would build the same app **today**. Use the tag
> anyway; the moment app code lands on main that stops being true and the tag is what
> the walk manifest records.

**Check `.env` exists and points at prod** — it's gitignored, so it survives a checkout,
but confirm:

```bash
grep SUPABASE_URL .env      # expect riigipzlyqeaadyvbuty.supabase.co
```

If it's missing, copy it over from the Linux box (see `docs/MAC_SETUP.md` §1).

---

## 1. S22 (Android) — 5 min

Plug in the S22, USB debugging on, then:

```bash
adb devices                       # confirm ONLY the S22 is listed
bash scripts/build-install-s9.sh
```

⚠️ **That script installs to every connected adb device.** Unplug any other Android
first or you'll flash something you didn't mean to.

It builds a multi-ABI debug APK, installs with `-r`, force-stops, and relaunches
`io.inrange.app`. When it prints `Done. Multi-ABI APK on 1 device(s).` you're good.

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
  --freeze calib-freeze-2026-07-23
```

---

## One heads-up on your earlier sweep

The S22↔iPhone six-station sweep (`978001b`) that produced the per-direction cutoffs in
`docs/PROXIMITY_TIERS.md` was collected **before** `95c6eae` — i.e. on pre-native-GATT
behavior. The doc already marks those cutoffs provisional; this is the concrete reason
to re-confirm them on the current build rather than treating them as settled.
