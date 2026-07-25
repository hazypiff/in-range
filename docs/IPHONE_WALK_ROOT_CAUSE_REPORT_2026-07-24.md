# iPhone Walk Usability — Root-Cause Report

**Date:** 2026-07-24  
**Repo:** `~/in-range`  
**Starting host commit reviewed:** `9ced273`  
**Required host behavior now:** absolute-time station check + thin-median
ingest gate + product body-position filter  
**Installed app freeze for tomorrow:** `calib-freeze-2026-07-24b` → `1a41d59`  
**Pair:** Galaxy S22 ↔ iPhone 15 Plus (locked-bridge ladder)  
**Related ops doc:** [`WALK_PREFLIGHT_2026-07-25.md`](WALK_PREFLIGHT_2026-07-25.md)

---

## 1. Question this report answers

Two related questions got tangled:

1. **Product:** how does In Range “work on iPhone” when screens are locked?
2. **Tomorrow’s walk:** what must be true so the S22 ↔ locked-iPhone ladder produces *trainable* data rather than a clean-looking but corrupted archive?

This report root-causes the capture/train path. It does **not** re-litigate the product stack (Live Activity + NI + warm BLE from `IOS_PROXIMITY_RESEARCH_2026-07-24.md` / `IOS_SCREEN_OFF_FUSION_2026-07-24.md`). Calibration data is still required for the single-tier “IN RANGE” launch promise and for any later Close By revival — so a wasted afternoon tomorrow still matters.

**Bottom line:** three problems. The host tooling now handles thin medians and
body-position selection; the protocol must still record two windows; and every
mid-walk check must use the operator's absolute station clock. Together they
decide whether tomorrow’s iPhone data is usable at all.

---

## 2. What “works on iPhone” means in this codebase

| Layer | Status | Source of truth |
|---|---|---|
| Foreground BLE advertise/scan with `CAFE` + rotating token | Works (bench) | `IOS_CARRIER_DECISION`, journal |
| Android reading locked iPhone overflow manufacturer data | Works (S22 bridge) | `IOS_PROXIMITY_RESEARCH` |
| Locked iPhone *return* samples (S22 → iPhone) | Sparse wake bursts | preflight + extract comments |
| Two cold, locked iPhones discovering each other | **Not supported** | Apple/Core Bluetooth boundary |
| User-started active session, screens mostly dark | Design path (W5/W6/W8) | screen-off fusion doc |
| Calibration → `learn/` → thresholds | Thin/body gates added; field validation pending | `extract_walk.py`, `learn/ingest.py`, `train.py` |

Tomorrow’s walk is **not** “two dormant iPhones cold-discover.” It is the **warm-start locked bridge**: both beacons started foregrounded, then both screens black for the dwell; S22 walks; iPhone stays at origin. That is the realistic S22↔iPhone product path today and the row still missing solid pocket-separated data.

---

## 3. Three root problems (not two competing checklists)

Earlier agent checklists disagreed on ladder range, dwell, and integrity steps. Root-causing the pipeline instead of picking a side:

### Root problem 1 — Thin iPhone stations looked trainable (**now fail-safe**)

**Failure mode:** a station where the locked iPhone caught one advert rendered
a clean-looking median, visually identical to one with 200 samples. The old
`learn/ingest.py` forwarded every distance-labeled station median. Downstream,
silence (`n=0`, no `high_med`) was safe — `train.py` skips missing features.
The dangerous middle was **`n = 1..4`**: it *looked* like a measurement.

That is exactly the locked-iPhone regime (sparse wake bursts). A far station can yield 1–3 adverts on the iPhone while the S22 yields ~60, and the walk comes back looking complete.

**Surfacing added at `9ced273`:**

- `MIN_HIGH_N = 5` (same conservative bar as the S9 rules baseline)
- per-side `thin: 0 < high_n < 5`
- table prints `n` with a trailing `!` on thin sides
- loud WARNING block names stations so you can re-walk **today** while phones and geometry are still set up

**The remaining hole is now closed in `learn/ingest.py`:** thin rows retain
`high_n` and rate (sparsity is real evidence), but `high_med` and IQR become
missing features. Pre-flag archives get the same `n=1..4` fallback. A
single-packet median can no longer silently train GNB.

### Root problem 2 — Pocket/hand corrupts medians unless logged separately

**Protocol (established):**

> The 90 s dwell is pocket-first then hand, so the burst splits at +45 s.  
> — `scripts/ios_station_check.sh:10`, `docs/FEET_TEST_PLAN_2026-07-22.md`

**Extractor behavior:** `extract_walk.py` does **not** split a station window. It trims the walk-in, then takes **one median over the whole remaining window**. A single 90 s station therefore averages ~45 s pocket + ~45 s hand into one number across an attenuation difference literature (and prior field work) puts around **~15 dB**. That number describes neither carry position.

Pocket is the real-carry product curve. Hand is the physics reference. Mixing them is worse than picking one.

**Free fix — log two stations per distance (labels already parse):**

```text
25ft-pocket@10:00:00+45  25ft-hand@10:00:45+45  ...
```

`learn/ingest.py` uses `DIST_RE = (\d+)\s*ft`, so `25ft-pocket` still
becomes `distance_ft = 25`. It also records the suffix as `body_position` and
the default product selector excludes explicitly tagged hand rows.

**Trim must change for 45 s windows.** Default `TRIM_S = 20` on a 45 s station discards **44%** of the window (25 s usable). Use **`--trim 10`** so each half keeps ~35 s after walk-in discard.

Physical choreography is unchanged: still one continuous 90 s dwell, pocket then hand at +45 s, beacons off between distances. Only the **station log / `stations.json`** changes shape.

### Root problem 3 — A first-packet clock mislabels sparse halves (**fixed in the checker**)

The locked iPhone is opaque until USB pull. The previous
`scripts/ios_station_check.sh` chose the latest burst and treated its **first
observed row** as station `t0`. That is unsafe in exactly this regime: if
pocket gets no callback and the first row arrives at physical +56 s, the old
script calls the hand row “pocket” and shifts the entire split.

The checker now requires the operator-recorded date/start and mirrors final
extraction: pocket uses +10..+45 s and hand uses +55..+90 s. The +45 boundary
cannot drift with callback timing. It also handles `n=1` without the old
`statistics.quantiles` crash.

Run it **between distances**, after beacons are off and the iPhone app has
been foregrounded for 15 seconds to flush the native buffer:

```bash
bash scripts/ios_station_check.sh 15p \
  --date 2026-07-25 --start <THIS_DISTANCE_POCKET_START>
```

Decide as follows:

- `n >= 5`: usable RSSI median.
- `THIN!` (`n=1..4`): repeat the distance once and preserve both trials.
- `SILENT` (`n=0`): safe missing median. Repeat once only if silence is
  unexpected; at the far ceiling, silence is the measurement.

When repeating, append `-r2` station labels and new clocks. Do not replace the
first trial after seeing its count; that selection would bias the dataset.

---

## 4. Checklist errors (do not re-import)

| Claim | Verdict | Why |
|---|---|---|
| “Confirm walk_id matches the USB pull” (Agent 1 style) | **No-op tomorrow** | `walk_id` equality is USB-vs-**cloud** lossless check (`extract_walk.py` docstring). Cloud path needs migration `0056` + uploader; freeze `07-24b` does not ship that. USB only. |
| 60 s dwell | **Wrong for this ladder** | Conflicts with 90 s protocol and with default trim (60 − 20 = 40 s). Agent 2 / preflight 90 s is correct for the full pocket+hand cycle. |
| Build phone apps from current `main` for the walk | **Hard no** | `main` after freeze adds upload retry against absent RPC and fails capture build match. **Apps stay on `1a41d59`.** The host repo should use current scripts; `9ced273` alone lacks the absolute-time checker and ingest gate. |
| Cloud extraction / `--allow-seq-gaps` | **Hard no** | USB is source of truth for this freeze. |
| Agent 1 ladder 2–100 ft vs Agent 2 25–200 ft | **Different questions** | See §5. |

---

## 5. Ladder recommendation (single-tier pivot)

Product pivot (2026-07-24): launch with **one** user-facing tier — **IN RANGE** (any detection while beacons are on). Granular Close/Near machinery stays dormant. Deliverable for tomorrow is therefore **where detection dies** on the locked bridge, not dense close anchors.

| Plan | Stations | Answers |
|---|---|---|
| Close-heavy (e.g. 2–100 ft) | Near anchors | Good for Close By revival later; weak on far envelope |
| **Far envelope (recommended)** | **25 · 65 · 90 · 130 · 175 · 200** | Matches `FEET_TEST_PLAN` Session A and preflight; brackets drop-off where `PROXIMITY_TIERS` already shows BLE past 175 ft |

With pocket/hand as separate extract stations:

- **6 distances × 2 body positions = 12 extract rows**
- Field time: still ~6 × 90 s dwell + walking + mid-checks (not double wall-clock)

If time forces a cut: **cut the middle, keep the ends.** Ends bracket the drop-off. Suggested cut order: drop 90, then 130, never drop 25 or 200 first.

---

## 6. Corrected station log and extract invocation

### 6.1 `stations.json` (recommended)

One continuous 90 s dwell per distance; two labeled windows for extract:

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

Hand `start` = pocket `start` + 45 s (same host clock used for prep). Write
the actual hand clock value; the JSON parser does not evaluate “+45”.

CLI equivalent:

```text
# One-distance example only:
25ft-pocket@10:00:00+45 25ft-hand@10:00:45+45
```

### 6.2 Exact `extract_walk.py` invocation

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

**Must:**

- `--trim 10` (not default 20) for 45 s halves  
- no `cloud:<device_id>`, no `--allow-seq-gaps`  
- S22 = side A, iPhone DB = side B  
- host scripts include the absolute-time checker and thin-ingest gate

**Trainability:** archive even if return direction is sparse. Current ingest
keeps thin count/rate but discards its median/IQR. Its safe default
`--body-position product` includes pocket and legacy untagged stations while
excluding explicitly tagged hand stations:

```bash
python3 learn/ingest.py \
  run_logs/walks/2026-07-25-s22-iphone15p-locked/walk.json \
  --pair s22-iphone15p \
  --body-position product \
  --out learn/data/s22-iphone15p-pocket.jsonl
```

Use `--body-position hand` for a separate physics-reference dataset or `all`
only for deliberate analysis. Mark the walk trainable only after:

- all clocks usable and measured distances recorded,
- no mixed foreground/locked dwell without label,
- thin `!` stations re-walked once or accepted as count/rate-only,
- pocket and hand halves not silently averaged.

---

## 7. Operator sequence (tonight → tomorrow)

### Tonight (desk)

1. Confirm apps still on freeze `07-24b` / `1a41d59` — **do not reinstall from `main`**.
2. Confirm the host scripts expose the corrected interface:
   `python3 scripts/ios_station_summary.py --help` must require `--date` and
   `--start`.
3. Print / phone-note the **12-row station template** and the mid-walk check command.
4. Dry-run the desk smoke with its recorded clock:
   `bash scripts/ios_station_check.sh 15p --date <LOCAL_DATE>
   --start <SMOKE_START> --window smoke:0:60 --trim 0`.

### Tomorrow (field)

1. Preflight hard gates (battery, BT, no hotspot, prep, bilateral desk smoke) — unchanged.
2. Each distance: settle → beacons ON → lock → **45 s pocket → 45 s hand** → beacons OFF.
3. **Between stations:** foreground iPhone 15 s, then run
   `bash scripts/ios_station_check.sh 15p --date 2026-07-25
   --start <POCKET_START>`.
4. After station 6: foreground iPhone ≥15 s, then pull both sources.
5. Extract with §6.2; re-walk any `!` thin stations **before packing up** if geometry still stands.

### After (train)

1. Ingest the product dataset with `--body-position product`; use
   `--body-position hand` for a separate reference dataset.
2. Thin median/IQR rejection is automatic; still inspect the `!` warnings and
   retain both trials when a distance was repeated.
3. Journal outcomes into `DEVICE_TESTING_JOURNAL.md` and update the S22↔iPhone row in `PROXIMITY_TIERS.md` only after pocket-separated curves exist.

---

## 8. Product path (beyond tomorrow)

Tomorrow’s walk improves **calibration evidence**. Making the *app* work for real iPhone users still tracks the research order:

| Priority | Work | Why |
|---|---|---|
| P0 field | This locked-bridge ladder, pocket/hand split, mid-walk checks | Usable training rows for current radio |
| P0 eng | W6 NI + Live Activity spike | Supported dark-screen ranging after user start |
| P0 eng | W5 warm-link BLE + `readRSSI()` | Android↔iOS continuity; connected RSSI sampling |
| Required | W8 restoration lifecycle | W5 must survive suspension honestly |
| Later | RSSI fusion thresholds from tagged field data | Do not promote fixed dBm cutoffs before instrumentation |
| Explicit non-goal | Silent all-day cold discovery, two dark iPhones, no session | Platform boundary — do not promise |

Single-tier launch (“IN RANGE = any detection”) is the correct product compression while W5/W6 mature. That does **not** excuse corrupted calibration: sparse false medians and pocket+hand averages will still poison any future Close By revival and any rules/LLM baseline that trusts `high_med`.

---

## 9. Decision matrix

| If you only do one thing tonight… | Do this |
|---|---|
| Highest leverage free fix | Split station log into `NNft-pocket` / `NNft-hand` + plan `--trim 10` |
| Highest leverage field habit | Dated/start-anchored mid-walk iPhone check |
| Done in current host tooling | Thin median rejection + exact clock split + product body filter |
| Do not re-open | Cloud walk_id match, 60 s dwell, building apps from `main`, 2–100 ft close ladder as the primary deliverable |

---

## 10. Sources (in-repo)

| Artifact | Role |
|---|---|
| `scripts/extract_walk.py` | Windows, trim, thin flag, iOS DB side, cloud walk_id note |
| `scripts/test_extract_walk.py` | Thin / silence / train-bar tests |
| `scripts/ios_station_check.sh` | USB pull wrapper for an exact station |
| `scripts/ios_station_summary.py` | Absolute clock split, per-half trim, thin status |
| `scripts/test_ios_station_summary.py` | Late-first-callback and trim regression tests |
| `learn/ingest.py` | Thin-feature rejection and body-position selection |
| `learn/train.py` | `high_n >= 5` in S9 rules baseline |
| `docs/WALK_PREFLIGHT_2026-07-25.md` | Operator checklist (updated with this report’s station-spec) |
| `docs/FEET_TEST_PLAN_2026-07-22.md` | 90 s pocket→hand protocol, 25–200 ladder |
| `docs/PROXIMITY_TIERS.md` | Single-tier pivot; BLE past 175 ft; pair-specific rows |
| `docs/IOS_PROXIMITY_RESEARCH_2026-07-24.md` | W5/W6/W8, overflow, connected RSSI |
| `docs/IOS_SCREEN_OFF_FUSION_2026-07-24.md` | Active-session dark-screen design |

---

## 11. One-paragraph summary for Rahul

Run freeze `07-24b` apps only and current host scripts. Walk the **25–200 ft**
ladder with **90 s dwells**, but log each distance as **two 45 s stations**
(`25ft-pocket` / `25ft-hand`, …) and extract with **`--trim 10`**. Between
distances, foreground the iPhone 15 seconds and run the checker with the
recorded `--date` and pocket `--start`; never infer the split from its first
callback. Repeat `THIN!` once and preserve both trials. Ingest product data
with `--body-position product`: thin median/IQR is rejected automatically and
hand rows remain an explicit physics reference. Ignore cloud walk_id matching
and 60 s dwell advice for this freeze.
