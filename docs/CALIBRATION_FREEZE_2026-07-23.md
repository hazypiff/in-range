# Calibration freeze — 2026-07-23 (tag `calib-freeze-2026-07-23`)

> **Current baseline freeze: `calib-freeze-2026-07-24b`.** This additive tag
> includes `6827be3`, the locked-phone BGTask/GATT wake-log instrumentation needed
> to interpret the next S22 ↔ iPhone walk. The published `07-24` tag remains at
> `793f278`; it was not moved. W5/W6 will require another freeze because they
> change the sampling regime.
>
> **2026-07-25 S22 ↔ iPhone locked-bridge walk:** use
> [`WALK_PREFLIGHT_2026-07-25.md`](WALK_PREFLIGHT_2026-07-25.md). It pins the
> six-station ladder, USB-only capture, foreground-before-copy flush, and
> explicit no-migration/no-cloud boundary for this walk.
>
> **Re-pinned 2026-07-24 → tag `calib-freeze-2026-07-24` (`793f278`).** Everything
> below still describes this round; only the pinned commit moved. The client build
> changed because Android now stamps its source commit into `versionName` (see
> *Build verification*), so the freeze had to name the stamped build. `07-23` is
> **not** moved — it is published to both remotes. Nothing was orphaned: this round
> has collected zero trainable walks so far.

Supersedes `calib-freeze-2026-07-18b`. Cut because 2026-07-23 changed the
app under the walkers' feet: locked-phone BLE carrier (W1–W4), per-direction
iPhone tier locks from the real-carry sweep, the tier-picker UI, beacon-path
RPC timeouts, the native Android GATT connect, and server migration 0053
(late-evidence windows). None of the 07-18b walks exist yet, so nothing is
mixed — this round simply starts here instead.

**One repo now.** The app and calibration (learn/) trees were unified
2026-07-23 (merge `106612a`); one tag on one history pins everything.
Both remotes (`inrangeai/in-range`, `hazypiff/in-range`) carry it.

**Caveat for the pre-unification freezes (`07-18`, `07-18b`).** Those predate
the merge, when two trees existed — and each remote had tagged its *own* tree,
so the same tag name resolved to different commits depending on which repo you
cloned. The two sides differ by ~73 files: `inrangeai` tagged the **app** tree
(`extract_walk.py`, `walk_capture.sh`), `hazypiff` tagged the **learn/**
tree (GNB trainer, registry, self-learning loop). Neither was wrong; they were
answering different questions.

Aligned 2026-07-24 to `inrangeai`'s targets on both remotes, so a clone of
either now reproduces the same code. `hazypiff`'s previous targets are recorded
here so the change is reversible:

| Tag | Now (both remotes) | `hazypiff` before 2026-07-24 |
|---|---|---|
| `calib-freeze-2026-07-18` | `225b661` | `91e954a` |
| `calib-freeze-2026-07-18b` | `a2de130` | `5f8497d` |

Low stakes — both rounds are superseded and produced zero trainable walks. From
`07-23` onward there is one history, so this cannot recur.

## Frozen components

| Component | Where | Version |
|---|---|---|
| Unified repo (capture, extractor, protocol, learn pipeline, app) | both remotes | current baseline tag `calib-freeze-2026-07-24b`; resolve its commit with `git rev-parse --short 'calib-freeze-2026-07-24b^{commit}'` |
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
  --freeze calib-freeze-2026-07-24b`.

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
- `walk_capture.sh prep` resolves `$FREEZE` (default `calib-freeze-2026-07-24b`) and **aborts
  before touching buffers or creating the archive dir** unless every connected
  phone matches. A later commit passes if it changes nothing under
  `lib/ android/ ios/` — the stamp describes an APK, so host-side `scripts/`
  is deliberately excluded; docs and web churn must not block a walk.
- The Pixel proxy and IG-fleet S9 the protected IG-fleet S9 (serial omitted) are protected defaults in
  the build, monitor, and capture scripts. The frozen In Range Android pair
  remains `324c…498` and `513…498`.
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
