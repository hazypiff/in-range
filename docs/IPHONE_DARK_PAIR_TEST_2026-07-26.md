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

1. Sign in on both phones, turn the beacon **on** on both. Confirm the UI
   shows on and `cloudSynced` true (claim landed).
2. Background both apps (home gesture — **never force-quit**; a force-quit
   is the documented boundary where iOS refuses all restoration).
3. Screens off. Place both phones on one table, ~3 m apart, stationary.
   Start a wall-clock timer.
4. Leave them **60 minutes**, undisturbed, in normal room conditions
   (WiFi on, cellular on).
5. **Do not open the apps.** Pull the native wake logs via USB:
   `Documents/bb_wake_log.txt` from each app container
   (Xcode → Devices & Simulators → downloaded container, or `cfgutil`).
6. Foreground both apps (buffered sightings drain + upload). Wait 2 min.
7. Server check: `sightings` rows for both directions,
   `token_claim_history` coverage for the slots served during the hour,
   `rssi_samples` if the upload flag was on.

## 2. What to record

| Field | A→B | B→A |
|---|---|---|
| Time to first detection (min) | | |
| Total detections in 60 min | | |
| Native wakes by kind (slc / visit / region / push / bgtask / gatt-read) | | |
| Sightings reaching server (count) | | |
| First-detection path (which wake preceded it) | | |

The wake-log timestamps are what make "nothing happened" diagnosable:

- **Zero wakes on both** → iOS granted no windows. The entitlement/cron
  chain is suspect before the BLE path is.
- **Wakes, zero sightings** → BLE carrier broken in background (scan
  filter, advert degradation). This is the tier-0/1 failure.
- **Sightings, zero server rows** → claim/resolution broken (0060 path).
- **Sightings + rows, late** → working but slow; the tier mix decides
  whether tier 4 or tier 2/3 carried it.

## 3. Controls (same session, after the pair test)

- **Force-quit boundary (expected failure)**: force-quit app A. iOS must
  NOT relaunch it (TN3115). Document what B hears over the next 15 min —
  this is the honest "what the user can break" number for the docs.
- **Token boundary**: if the hour straddles a 15-min slot rollover, check
  the server resolved sightings on BOTH slots (0060 pre-claim working).

## 4. Decision rule

- **Detection within ≤10 min of co-location, both directions, on the
  first trial** → the screen-off gap is closed for the stationary-venue
  case. Ship the capability commit, move to the persistent-GATT bench
  (handoff §16.2 #3) for latency, and start drafting the honest number
  into the product copy.
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
