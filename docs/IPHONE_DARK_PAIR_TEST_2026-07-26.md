# iPhone dark pair test — the measurement everything is gated on

**Date:** 2026-07-26 (first Mac session after `f6bf21e`)
**Builds:** `main` ≥ `f6bf21e` (`e71326d` for docs), iOS CI green
**Takes:** ~90 min + two iPhones + the Mac

Everything since 2026-07-24 was built on the hypothesis that the wake net
helps. The only empirical number anyone has is the **~4% field baseline**
from the July soak. This protocol produces the second number. Run it
mechanically; record everything; the decision rule is at the bottom.

---

## 0. Prerequisites (do these BEFORE the phones are touched)

1. **Xcode**: Runner → Signing & Capabilities → **+ Push Notifications**
   (creates `Runner.entitlements` with `aps-environment`). Confirm
   **Access WiFi Information** and the Background Modes list are still
   present. Commit the entitlements file from the Mac.
2. **Supabase secrets**: `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_KEY_P8`
   (from the paid Apple Developer account) set as Edge Function secrets.
3. **Cron**: `proximity-wake` Edge Function scheduled in the Supabase
   dashboard (every 5 min is the right starting cadence). This is the L5
   gap — without it tier 4 never fires even with perfect clients.
   **Verify it is armed, don't assume**: confirm `device_push_tokens` has
   `provider='apns'` rows for both test accounts, then fire the function
   manually (`POST /functions/v1/proximity-wake {"limit": 50}`) and read
   its response/logs. A run where the cron was never scheduled is NOT a
   tier-4 result — record it as the tier 0-3 floor (see §2).
4. **Migrations**: `bash scripts/rehearse_migrations.sh` green, then
   `supabase db push` (0055→0060 deploy together).
5. **Edge Function**: redeploy `proximity-wake` (payload now sends
   `nonce`, not `wake`).
6. **Build box `.env`**: `INRANGE_SUBTLE_WAKE=true`,
   `INRANGE_LOCATION_RESIDENCY=true`, `INRANGE_CALIB_SCAN=false`.
   `build-install-ios.sh --release` accepts this without the walk override
   (calib is off).
7. **Two accounts**, both fully discoverable (age + photo verified —
   `current_user_can_discover()` is a hard gate on every RPC in this path).
8. Both iPhones: Bluetooth on, **Location Always** granted through the
   in-app disclosure flow, notifications allowed.

## 1. The pair test (two stationary dark phones, one venue)

**Contamination rules — violations produce a false pass, which is worse
than no data:**

- Install the release build, then **detach the debugger** and launch from
  the home screen. A debugger-attached process changes background-push
  throttling (Apple, forums 745188), and silent pushes are capped at ~2-3
  per hour regardless — this test measures production behavior or it
  measures nothing.
- Keep the phones **out of BLE range of each other for all of setup**
  (different rooms). Every artifact produced before the dark interval
  must be excludable by timestamp — a foreground/setup sighting surfacing
  later as a "dark detection" is the classic false pass.
- Record an exact **UTC T0** (the moment both screens go dark). Either
  clear `Documents/bb_wake_log.txt` and any prior test rows first, or
  strictly filter every artifact — wake log, sightings, rssi_samples —
  by `observed_at >= T0`. Never eyeball unfiltered logs.

**Procedure:**

1. Apart (no BLE contact): sign in on both, beacon **on**, confirm UI on +
   `cloudSynced` true. Confirm Location Always on both.
2. Background both apps (home gesture — **never force-quit**; force-quit
   is the documented boundary where iOS refuses all restoration).
3. Screens dark. Record **T0**. Wait 5 minutes (let both processes fully
   suspend; a sighting in the first minutes after backgrounding is the
   foreground session draining, not a dark detection).
4. Without unlocking or touching either phone, carry them into the same
   room and place them on one table, ~3 m apart. The carry is the SLC
   trigger — that is intended; a run with NO movement is the CLVisit arm
   (§4 arms).
5. Leave them **60 minutes**, undisturbed.
6. **Do not open the apps.** Pull `Documents/bb_wake_log.txt` from each
   container (Xcode → Devices & Simulators → downloaded container, or
   `cfgutil`).
7. Foreground both apps (buffered sightings drain + upload). Wait 2 min.
8. Server check, filtered by T0: `sightings` rows for both directions,
   `token_claim_history` coverage for the slots served during the hour,
   `rssi_samples` if the upload flag was on.

## 2. What to record

**First, the armament line — without it the numbers get misquoted later:**

> Tiers live for this run: BLE (tier 0-1) ☐ · SLC/regions/CLVisit (tier 2-3)
> ☐ · silent push (tier 4 — cron armed AND verified per §0.3) ☐
> `.env` flags on the build: SUBTLE_WAKE=__ RESIDENCY=__

A run with tier 4 inert is still a genuinely useful measurement — it is the
floor without silent push — but the table must say that is what it was, or
the number gets quoted later as "with everything on."

| Field | A→B | B→A |
|---|---|---|
| Native capture latency (min, wake-log → first sighting ts ≥ T0) | | |
| Server-ingestion latency (min, T0 → first sightings row) | | |
| Total detections in 60 min | | |
| Native wakes by kind (slc / visit / region / push / bgtask / gatt-read) | | |
| Sightings reaching server (count) | | |
| First-detection path (which wake preceded it) | | |

The two latencies measure different failures: native capture is the BLE
carrier + wake net; server ingestion adds the drain, upload, and
resolution chain. A fast native capture with slow server ingestion is a
client-pipeline bug, not a BLE one.

**One run is a smoke test, not a result.** Call it a product result only
after **≥3 independent trials per arm** (fresh dark interval each, phones
re-separated between trials), reported as success rate plus median/worst
latency — never as the best trial.

The wake-log timestamps are what make "nothing happened" diagnosable:

- **Zero wakes on both** → iOS granted no windows. The entitlement/cron
  chain is suspect before the BLE path is.
- **Wakes, zero sightings** → BLE carrier broken in background (scan
  filter, advert degradation). This is the tier-0/1 failure.
- **Sightings, zero server rows** → claim/resolution broken (0060 path).
- **Sightings + rows, late** → working but slow; the tier mix decides
  whether tier 4 or tier 2/3 carried it.

## 3. Arms and controls

**Arms (each needs its own ≥3 trials — different builds, different
questions):**

- **Arm R-on**: `INRANGE_LOCATION_RESIDENCY=true` on both phones. The
  residency path is the compliance-sensitive one (continuous-location
  session); it must PROVE its value or ship off (handoff §16.2 #8).
- **Arm R-off**: same binary, `INRANGE_LOCATION_RESIDENCY=false`. This is
  the same-binary A/B the residency review has demanded since 2026-07-24 —
  R-on is only defensible if it beats R-off by a real margin.
- **CLVisit arm**: skip step 1.4's carry — place both phones at the venue
  BEFORE darkening them, so nothing moves during the hour. This isolates
  the no-motion arrival path. Note: CLVisit is **opportunistic** — Apple
  delivers visits with power-efficient delay, not as a deterministic
  arrival alarm — so a slow visit wake is expected behavior, not a bug.

**Controls (same session, after the arms):**

- **Force-quit boundary (expected failure)**: force-quit app A. iOS must
  NOT relaunch it (TN3115). Document what B hears over the next 15 min —
  this is the honest "what the user can break" number for the docs.
- **Token boundary**: if the hour straddles a 15-min slot rollover, check
  the server resolved sightings on BOTH slots (0060 pre-claim working).

## 4. Decision rule

- **Detection within ≤10 min of co-location, both directions, ≥3/3 trials
  of at least one arm** → the screen-off gap is closed for the
  stationary-venue case. Ship the capability commit, move to the
  persistent-GATT bench (handoff §16.2 #3) for latency, and start drafting
  the honest number — success rate + median/worst, per arm — into the
  product copy.
- **R-on materially beats R-off** (faster median or higher success) → the
  residency flag earns its compliance cost; document the margin in the
  handoff. **R-on ≈ R-off** → residency ships OFF; the continuous-location
  indicator is not defensible without a measured benefit.
- **Detection only after 30+ min, or only via BGTask overlap** → tier 4
  is not firing. Debug the APNs chain (token registered? `device_push_tokens`
  row with provider='apns'? Edge Function logs? APNs HTTP status?) before
  touching BLE.
- **Zero detections with zero wakes** → entitlement/capability problem,
  not BLE. Re-check §0.
- **Zero detections with wakes present** → BLE background carrier problem.
  That is a real architecture finding: escalate before building anything
  else on top.

Report the table + wake logs back before any further native work. Every
prior round has shown that "wired" and "measured" are different states.
