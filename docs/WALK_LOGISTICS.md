# Walk logistics — what needs a computer, what the phones log themselves

Status report, 2026-07-18 (calibration freeze `calib-freeze-2026-07-18`).
**Required reading for anyone (human or agent) running or processing a
calibration walk — including the Mac/iOS side.**

## Short answer

No computer is needed **during** a walk. The laptop (Android) / Mac (iOS)
bookends it: a prep step before, a pull step after. All three radios log
on-device in between.

## Android (S9 fleet) — fully self-contained

| Phase | Where | What happens |
|---|---|---|
| Before (desk, ~10 s) | laptop, phones on USB | `scripts/walk_capture.sh prep` — resizes logcat ring buffer to 64M, **verifies it took (aborts if not)**, clears it explicitly (`-G` does NOT clear on S9), records host-minus-device clock offsets to `meta-prep.json` |
| During walk | phones only | App logs every BLE advert (`Advert corr=… rssi=… pw=H\|M`), WiFi fingerprint (`WifiScan`/`WifiAp` incl. cache age), and GPS fix (`GpsFix … acc=`) into the on-device ring buffer. Human notes each stop's **start time** on any clock synced to the prep host clock. Stops do NOT need to be back-to-back — stop-and-return with gaps is the validated method |
| After (desk) | laptop, USB | `scripts/walk_capture.sh pull` — raw threadtime dumps → dated gzip archive under `run_logs/walks/` + `meta-pull.json` (offsets re-measured). Then `scripts/extract_walk.py … --json walk.json` |

Optional: `CALIB=1 bash scripts/beacon_monitor.sh` (Work repo) streams the
calibration records live over tethered/wireless adb — a health view only,
never the data source. Skipping it changes nothing.

Pre-walk health check (RH-1, see RUNTIME_HEALTH.md): a phone can advertise
while its scanner is silently dead. Fresh app start + beacon toggle + confirm
`Advert` lines appear in logcat before leaving.

## iPhone — logs on-device, but retrieval is the Mac's job

- The iOS build persists the **raw `rssi_log` stream on-device** (added
  eea557c) — no computer needed during a walk, same as Android.
- There is **no adb for iOS**: `walk_capture.sh` and `extract_walk.py`
  (which parses Android logcat threadtime format) do not apply. iPhone walk
  data is retrieved and processed through the Mac-side flow.
- Platform constraint, not a gap to fix: **iOS has no public WiFi-scan API**,
  so iPhone rows are BLE + GPS only, permanently. The WiFi venue layer is
  Android-only data.
- Cross-platform pairings (iPhone↔S9) are additionally blocked by the
  Android scan-filter widen (issue #1) — this collection round is
  S9↔S9 (laptop side) plus iPhone↔iPhone (Mac side).

## For the Mac-side agent: joining the shared training dataset

The self-learning loop (Work repo `learn/`, see
`CALIBRATION_FREEZE_2026-07-18.md` there) trains on `walk.json` archives.
For iPhone walks to ever enter that dataset, each capture needs the same
discipline the Android path now enforces:

1. **Explicit per-station start times + durations** on a recorded clock
   (stop-and-return gaps are fine and expected).
2. **Clock offset** between the noting clock and the phones' log timestamps,
   measured at capture time (Android records host_minus_device_s in
   meta.json; the Mac flow needs an equivalent).
3. **Raw log preserved** (gzip) as source of truth; derived files must be
   reproducible from it.
4. **Measured distances only** — anything eyeballed or degraded gets marked
   `trainable: false` in the archive metadata (Android:
   `extract_walk.py --trainable no`) so it is archived but never trained on.
5. Output shaped like `extract_walk.py --json` (per-station per-direction:
   high-power median/IQR/rate/count, medium-slot count, plus GPS delta;
   feature schema `inrange-gnb-1` — see Work repo `learn/README.md`) or the
   raw log + station times handed over for extraction here.

Promotion gates (fail-closed, already live): ≥3 independent trainable
walks, every class in ≥2 walks, valid held-out folds only, must beat the
rules baseline. Nothing about a single walk — iPhone or Android — unlocks
runtime changes.
