# Calibration freeze — 2026-07-18 (tag `calib-freeze-2026-07-18b`)

Everything a walk touches is pinned here. **Use exactly these versions for
every walk in this collection round** — if any component must change
mid-round, cut a new freeze doc + tags and note which walks used which
freeze (mixed-version walks cannot share a training dataset without review).

## Frozen components

| Component | Where | Version |
|---|---|---|
| App repo (capture, extractor, protocol, classifier stub) | `inrangeai/in-range` | tag `calib-freeze-2026-07-18b` = `a2de130` |
| Calibration repo (learn pipeline, monitor) | `hazypiff/in-range` (Work) | tag `calib-freeze-2026-07-18b` = `<this commit>` |
| Feature schema | `learn/train.py` / artifact | `inrange-gnb-1`: high_med, iqr_w, rate, high_n, med_n, venue_v, gps_delta |
| Extractor defaults | `scripts/extract_walk.py` | trim 20 s, max AP age 60 s, AP gate −70 dBm |
| Walk protocol | `docs/WALK4_PROTOCOL.md` (app repo, at tag) | stop-and-return, explicit host-clock stop times, 90 s stations |
| Capture | `scripts/walk_capture.sh` | 64M verified buffer + explicit clear, prep/pull meta with clock offsets |
| Installed S9 build | phones 324c…498 + 513…498 | versionName 1.0 (1), installed 2026-07-16 ~02:0x, calibration logging desk-verified 2026-07-18 |

## Collection round (before any promotion)

Target: **>=3 independent trainable walks, every class in >=2 walks; 5 walks
across venues/orientations is the comfortable target.** Vary: venue
(open outdoor / street / indoor), phone orientation/body position, and —
once the Android scan-filter widen (issue #1) lands post-round — device
pairings. After EVERY walk, before the next one:

1. `learn/loop.sh` on all archives — review capture quality (advert counts,
   stale-drop rates, scan/fix counts per station) and class coverage in the
   report.
2. Anything unmeasured or degraded → stamp `--trainable no`, note why in
   LEARNING_LOG.
3. Phones health check first (RH-1): fresh app start + beacon toggle —
   a wedged scanner wastes the whole walk.

## Gates recap (all must pass before runtime promotion)

Fail-closed in `train.py`/`export.py`: valid held-out folds only,
missing-class folds INVALID (never zero-scored), >=3 walks, >=2 walks per
class, beats rules baseline on macro-F1 without more dangerous
close↔inrange errors, human writes PROMOTED, export re-verifies.
RH-1/RH-2 stay on the separate reliability track — they gate *fleet
health*, not this dataset round.

## Freeze b (2026-07-18, supersedes the original tag — zero trainable walks existed)

Re-frozen after the architecture-contracts hardening landed:
walk_manifest.v1 identity (extract_walk `--pair --capture-meta --freeze`),
ingest pair verification, atomic registry publish + RUN_ID handoff,
path-hard LLM guard. Walks in this round must pass
`--pair <pair> --capture-meta <meta-pull.json> --freeze calib-freeze-2026-07-18b`
at extraction so every archive carries verifiable identity.
