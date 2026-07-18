# learn/ — the In Range self-learning calibration loop

Every walk makes the proximity model measurably better — or gets rejected.
The "small AI" is a **Gaussian naive-Bayes tier classifier** (pure Python
training, pure Dart inference, <100 KB artifact), not an LLM. The local LLM
(Ministral :18080) is limited to **post-hoc report narration** — it never
touches labels, features, or promotion.

## The loop

```
walk_capture.sh prep                      (app repo — verified 64M buffers + clock offsets)
   → walk, noting explicit stop times     (stop-and-return, host clock)
   → walk_capture.sh pull                 (raw gzip archive = source of truth)
   → extract_walk.py … --json walk.json   (gap-aware, stale-AP-rejecting)
   → learn/loop.sh                        (ingest → train → evaluate → report)
   → HUMAN reviews report, promotes or rejects
   → learn/export.py                      (promoted model → Dart-loadable JSON)
```

## Guardrails (non-negotiable)

1. **Labeled calibration walks only.** No self-labeling of production data —
   distribution shift + label noise. A row exists only because a human stood
   at a measured distance.
2. **Grouped hold-out with fold validity.** Cross-validation is
   leave-one-WALK-out (group = walk archive). A fold whose training set is
   missing any class is INVALID — excluded from metrics, never scored as
   zero-evidence. Promotion floor: **>=3 walks and every class present in
   >=2 independent walks** (5 walks across venues/orientations is the
   comfortable target). Smoke fixtures (`extract_walk.py --trainable no`,
   `meta.trainable=false`) are archived but never ingested.
3. **Rules baseline always runs.** The fitted model must beat (or tie) the
   current hand-tuned thresholds on macro-F1 AND not increase dangerous
   errors (Close↔In-Range swaps) before it can be promoted.
4. **Human-gated registry.** Training writes `learn/registry/<run>/` with
   model.json (dataset sha256 + metrics inside), report.md, and confusion
   matrices. Promotion = a human writes the run name into
   `learn/registry/PROMOTED`. Rollback = edit that file back. Nothing
   auto-promotes, ever.
5. **Losses are data.** Every run appends one line to `LEARNING_LOG.md` —
   failed experiments stay on the record with why.

## Files

- `ingest.py` — walk.json archives → labeled feature rows (dataset.jsonl)
- `train.py` — GNB fit + leave-one-walk-out CV + rules baseline + registry run
- `report_llm.py` — optional Ministral narration of a run's report (post-hoc)
- `export.py` — PROMOTED model → app-ready artifact JSON
- `loop.sh` — orchestrates ingest → train → narrate; prints the human review step
- `test_learn.py` — synthetic-walk tests for the whole pipeline

## Model artifact schema (`inrange-gnb-1`)

```json
{"schema": "inrange-gnb-1", "trained_at": "...", "dataset_sha256": "...",
 "pair": "s9-s9", "features": ["high_med", "iqr_w", "rate", "high_n", "med_n",
 "venue_v", "gps_delta"],
 "classes": {"close": {"prior": 0.33, "stats": {"high_med": [-78.2, 12.1]}}}}
```

Inference (Dart `GnbClassifier` in the app repo, `proximity_classifier.dart`):
argmax over classes of `ln(prior) + Σ_present_features ln N(x | mean, var)`.
Missing features (silence, no WiFi, no GPS) are skipped — never imputed.
The classifier is NOT wired into the runtime pipeline until a promoted,
walk-validated model exists (deferral decision 2026-07-18).
