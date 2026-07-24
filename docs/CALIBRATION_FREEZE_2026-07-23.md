# Calibration freeze — 2026-07-23 (tag `calib-freeze-2026-07-23`)

Supersedes `calib-freeze-2026-07-18b`. Cut because 2026-07-23 changed the
app under the walkers' feet: locked-phone BLE carrier (W1–W4), per-direction
iPhone tier locks from the real-carry sweep, the tier-picker UI, beacon-path
RPC timeouts, the native Android GATT connect, and server migration 0053
(late-evidence windows). None of the 07-18b walks exist yet, so nothing is
mixed — this round simply starts here instead.

**One repo now.** The app and calibration (learn/) trees were unified
2026-07-23 (merge `106612a`); one tag on one history pins everything.
Both remotes (`inrangeai/in-range`, `hazypiff/in-range`) carry it.

## Frozen components

| Component | Where | Version |
|---|---|---|
| Unified repo (capture, extractor, protocol, learn pipeline, app) | both remotes | tag `calib-freeze-2026-07-23` = `9c23359` (this doc); client code identical to `95c6eae`, the last commit touching `lib/ android/ ios/ scripts/` |
| Feature schema | `learn/train.py` / artifact | `inrange-gnb-1` (unchanged) |
| Extractor defaults | `scripts/extract_walk.py` | trim 20 s, max AP age 60 s, AP gate −70 dBm (unchanged) |
| Walk protocol | `docs/WALK4_PROTOCOL.md` at tag | stop-and-return, explicit host-clock stop times, 90 s stations |
| Capture | `scripts/walk_capture.sh` | 64M verified buffer + explicit clear, prep/pull meta with clock offsets |
| Installed S9 builds (324c…498, 513…498) | this box, debug multi-ABI | built from `95c6eae`, installed 2026-07-23 ~18:2x, desk-verified (advertise + cross-sight + upload). **Predate build stamping** — `walk_capture.sh prep` now rejects them (`versionName=1.0`); one rebuild makes them walk-eligible |
| **Rahul's devices (S22, iPhone 15 Plus)** | Mac side | **REINSTALL REQUIRED from ≥ `95c6eae` before the next walk** — their installed builds predate the native-GATT swap (W3 behavior differs) and 0053 client timestamp pass-through |
| Server (prod riigipzlyqeaadyvbuty) | migrations ledger | `0053` — `late_evidence_window_minutes = 15`. Server state is now walk-relevant: encounter confirmation tolerates late flushes; note it when interpreting confirm timing |

## New in this round vs 07-18b

- **Locked-phone legs are now in scope.** S9s pocketed/screen-off as
  always; iPhone may be tested BOTH ways (foreground, and locked once the
  W2/W3 desk check passes). Record per-station which lifecycle the iPhone
  was in — locked-iPhone RSSI comes in wake-bursts and via Android-side
  GATT-anchored sightings, a different sampling shape than foreground.
- **Per-direction tiers:** the 2026-07-23 sweep locked provisional
  per-direction cutoffs (`docs/PROXIMITY_TIERS.md`); bilateral fusion is
  load-bearing. Walks should capture both directions' logs, not just one.
- Extraction unchanged: `--pair <pair> --capture-meta <meta-pull.json>
  --freeze calib-freeze-2026-07-23`.

## Collection round (unchanged targets)

>=3 independent trainable walks, every class in >=2 walks; 5 across
venues/orientations is the comfortable target. After every walk:
`learn/loop.sh` → review capture quality + class coverage → stamp bad
captures `--trainable no` → RH-1 phone health check before the next.

## Build verification (new — added 2026-07-24)

Device drift is what actually broke this round: Rahul's S22 and iPhone ran a
pre-native-GATT build for a whole round and nothing said so. A stale install
does not fail loudly — it emits plausible rows under different behavior, and
the fail-closed trainer gates will pass a model fit on that mixture.

- `build-install-s9.sh` stamps the source commit into `versionName`
  (`0.1.0-<sha>`, `-dirty` suffix if the client tree is dirty).
- `walk_capture.sh prep` resolves `$FREEZE` (default this tag) and **aborts
  before touching buffers or creating the archive dir** unless every connected
  phone matches. A later commit passes if it changes nothing under
  `lib/ android/ ios/ scripts/` — docs and web churn must not block a walk.
- Each device's actual stamp is recorded as `build` in `meta-<phase>.json`, so
  the archive states the data-producing code instead of trusting the prep.
- `ALLOW_BUILD_MISMATCH=1` downgrades the abort to a warning for deliberate
  cross-build experiments. Walks captured that way are not comparable to this
  round — stamp them `--trainable no`.

iOS has no equivalent check (no `adb`); the Mac side stays procedural, see
`docs/RAHUL_REINSTALL.md`.

## Gates recap (unchanged)

Fail-closed in `train.py`/`export.py`: valid held-out folds only,
missing-class folds INVALID, >=3 walks, >=2 walks per class, beats rules
baseline on macro-F1 without more dangerous close↔inrange errors, human
writes PROMOTED, export re-verifies.
