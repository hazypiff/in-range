#!/usr/bin/env python3
"""Train the tiny proximity model: Gaussian naive Bayes vs the rules baseline,
leave-one-walk-out cross-validation, human-gated registry run output.

Pure stdlib — no sklearn. The model is means/variances/priors; inference is
mirrored exactly by GnbClassifier in the app repo
(lib/features/beacon/proximity_classifier.dart).

Usage:
  python3 learn/train.py learn/data/dataset.jsonl \
      --tiers "close:0-75,near:76-150,inrange:151-100000" \
      --rules iphone --registry learn/registry
"""
import argparse
import datetime
import hashlib
import json
import math
import os
from collections import defaultdict

FEATURES = ["high_med", "iqr_w", "rate", "high_n", "med_n", "venue_v", "gps_delta"]
VAR_EPS = 1e-6
DANGEROUS = {("close", "inrange"), ("inrange", "close")}


def parse_tiers(spec):
    """'close:0-75,near:76-150,inrange:151-100000' -> [(name, lo, hi)]"""
    out = []
    for part in spec.split(","):
        name, rng = part.split(":")
        lo, hi = rng.split("-")
        out.append((name.strip(), int(lo), int(hi)))
    return out


def tier_for(dist, tiers):
    for name, lo, hi in tiers:
        if lo <= dist <= hi:
            return name
    raise ValueError(f"distance {dist} outside tier spec")


# --- Gaussian naive Bayes -------------------------------------------------

def fit_gnb(rows, tiers):
    by_class = defaultdict(list)
    for r in rows:
        by_class[tier_for(r["distance_ft"], tiers)].append(r["features"])
    n = len(rows)
    classes = {}
    for cls, feats in by_class.items():
        stats = {}
        for f in FEATURES:
            vals = [x[f] for x in feats if x.get(f) is not None]
            if len(vals) >= 2:
                mean = sum(vals) / len(vals)
                var = sum((v - mean) ** 2 for v in vals) / (len(vals) - 1)
                stats[f] = [mean, max(var, VAR_EPS)]
            elif len(vals) == 1:
                stats[f] = [vals[0], 1.0]  # single sample: wide-ish guess
        classes[cls] = {"prior": len(feats) / n, "stats": stats}
    return classes


def gnb_scores(classes, features):
    scores = {}
    for cls, c in classes.items():
        s = math.log(c["prior"])
        for f, (mean, var) in c["stats"].items():
            x = features.get(f)
            if x is None:
                continue  # missing feature: skipped, never imputed
            s += -0.5 * math.log(2 * math.pi * var) - (x - mean) ** 2 / (2 * var)
        scores[cls] = s
    return scores


def gnb_predict(classes, features):
    scores = gnb_scores(classes, features)
    best = max(scores, key=scores.get)
    # softmax over log scores for a (crude, uncalibrated) confidence
    m = max(scores.values())
    exps = {c: math.exp(s - m) for c, s in scores.items()}
    z = sum(exps.values())
    return best, exps[best] / z


# --- Rules baselines (the current hand-tuned heuristics) ------------------

def rules_s9(f):
    if f.get("high_med") is not None and f["high_med"] >= -80 and f["high_n"] >= 5:
        return "close"
    if f["med_n"] > 0:
        return "near"
    return "inrange"


def rules_iphone(f):
    m = f.get("high_med")
    if m is None:
        return "inrange"
    if m >= -84:
        return "close"
    if m >= -96:
        return "near"
    return "inrange"


RULES = {"s9": rules_s9, "iphone": rules_iphone}


# --- Evaluation -----------------------------------------------------------

def evaluate(pairs, class_names):
    """pairs: [(true, pred)] -> metrics dict."""
    cm = {t: {p: 0 for p in class_names} for t in class_names}
    for t, p in pairs:
        cm[t][p] += 1
    f1s = []
    for c in class_names:
        tp = cm[c][c]
        fp = sum(cm[t][c] for t in class_names if t != c)
        fn = sum(cm[c][p] for p in class_names if p != c)
        prec = tp / (tp + fp) if tp + fp else 0.0
        rec = tp / (tp + fn) if tp + fn else 0.0
        f1s.append(2 * prec * rec / (prec + rec) if prec + rec else 0.0)
    dangerous = sum(cm[t][p] for (t, p) in DANGEROUS
                    if t in cm and p in cm[t])
    acc = sum(cm[c][c] for c in class_names) / max(1, len(pairs))
    return {"macro_f1": round(sum(f1s) / len(f1s), 4), "accuracy": round(acc, 4),
            "dangerous": dangerous, "confusion": cm, "n": len(pairs)}


def cross_validate(rows, tiers, rules_fn):
    """Leave-one-walk-out with fold-validity rules:
    - a fold whose TRAINING set is missing any target class is INVALID —
      recorded and excluded from metrics, never scored as zero-evidence;
    - coverage_ok (required for promotion) needs >=3 walks total and every
      class present in >=2 independent walks, so any single held-out walk
      still leaves every class represented in training.
    Returns (gnb_metrics, rules_metrics, info)."""
    class_names = [t[0] for t in tiers]
    groups = sorted({r["walk_id"] for r in rows})
    walks_per_class = defaultdict(set)
    for r in rows:
        walks_per_class[tier_for(r["distance_ft"], tiers)].add(r["walk_id"])
    coverage_ok = (len(groups) >= 3 and
                   all(len(walks_per_class.get(c, ())) >= 2 for c in class_names))

    gnb_pairs, rules_pairs, invalid_folds = [], [], []
    held_out = False
    if len(groups) >= 2:
        for g in groups:
            train_rows = [r for r in rows if r["walk_id"] != g]
            test_rows = [r for r in rows if r["walk_id"] == g]
            train_classes = {tier_for(r["distance_ft"], tiers) for r in train_rows}
            missing = sorted(set(class_names) - train_classes)
            if missing:
                invalid_folds.append({"held_out_walk": g,
                                      "training_missing": missing})
                continue
            model = fit_gnb(train_rows, tiers)
            for r in test_rows:
                true = tier_for(r["distance_ft"], tiers)
                gnb_pairs.append((true, gnb_predict(model, r["features"])[0]))
                rules_pairs.append((true, rules_fn(r["features"])))
        held_out = bool(gnb_pairs)
    if not held_out:
        # in-sample fallback: numbers are printed for orientation only and
        # can never promote (held_out stays False)
        gnb_pairs, rules_pairs = [], []
        model = fit_gnb(rows, tiers)
        for r in rows:
            true = tier_for(r["distance_ft"], tiers)
            gnb_pairs.append((true, gnb_predict(model, r["features"])[0]))
            rules_pairs.append((true, rules_fn(r["features"])))
    info = {"held_out": held_out, "coverage_ok": coverage_ok,
            "invalid_folds": invalid_folds, "n_walks": len(groups),
            "walks_per_class": {c: sorted(walks_per_class.get(c, []))
                                for c in class_names}}
    return evaluate(gnb_pairs, class_names), evaluate(rules_pairs, class_names), info


def confusion_md(cm):
    names = sorted(cm)
    head = "| true \\ pred | " + " | ".join(names) + " |"
    sep = "|---" * (len(names) + 1) + "|"
    body = "\n".join(
        "| " + t + " | " + " | ".join(str(cm[t][p]) for p in names) + " |"
        for t in names)
    return "\n".join([head, sep, body])


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("dataset", help="dataset.jsonl from ingest.py")
    ap.add_argument("--tiers", required=True,
                    help="e.g. close:0-75,near:76-150,inrange:151-100000")
    ap.add_argument("--rules", required=True, choices=sorted(RULES),
                    help="which hand-tuned baseline this pair currently uses")
    ap.add_argument("--registry", default="learn/registry")
    args = ap.parse_args()

    rows = [json.loads(l) for l in open(args.dataset)]
    if not rows:
        raise SystemExit("empty dataset")
    tiers = parse_tiers(args.tiers)
    dataset_sha = hashlib.sha256(open(args.dataset, "rb").read()).hexdigest()
    pair = rows[0]["pair"]
    walks = sorted({r["walk_id"] for r in rows})

    gnb_m, rules_m, info = cross_validate(rows, tiers, RULES[args.rules])
    beats = (gnb_m["macro_f1"] >= rules_m["macro_f1"]
             and gnb_m["dangerous"] <= rules_m["dangerous"])
    promotable = (info["held_out"] and info["coverage_ok"]
                  and not info["invalid_folds"] and beats)

    final_model = fit_gnb(rows, tiers)  # deployed artifact trains on ALL walks
    now = datetime.datetime.now(datetime.timezone.utc)
    run = now.strftime("%Y%m%d-%H%M%S") + "-" + pair
    run_dir = os.path.join(args.registry, run)
    os.makedirs(run_dir, exist_ok=True)

    model = {"schema": "inrange-gnb-1", "trained_at": now.isoformat(),
             "dataset_sha256": dataset_sha, "pair": pair, "walks": walks,
             "tiers": args.tiers, "features": FEATURES, "classes": final_model,
             "cv": {"gnb": gnb_m, "rules": rules_m, **info}}
    with open(os.path.join(run_dir, "model.json"), "w") as f:
        json.dump(model, f, indent=1, sort_keys=True)

    if promotable:
        verdict = ("PROMOTABLE — human review required (write run name into "
                   "learn/registry/PROMOTED to deploy)")
    elif not info["held_out"]:
        verdict = ("NOT PROMOTABLE — no valid held-out folds (needs >=2 walks "
                   "whose training sets contain every class)")
    elif not info["coverage_ok"]:
        wpc = {c: len(w) for c, w in info["walks_per_class"].items()}
        verdict = ("NOT PROMOTABLE — coverage floor not met: needs >=3 walks "
                   f"and >=2 walks per class (have {info['n_walks']} walks, "
                   f"walks-per-class {wpc})")
    elif info["invalid_folds"]:
        verdict = ("NOT PROMOTABLE — invalid folds present (training sets "
                   "missing classes)")
    else:
        verdict = ("NOT PROMOTABLE — does not beat the rules baseline "
                   "(macro-F1 and dangerous errors)")

    invalid_md = ""
    if info["invalid_folds"]:
        invalid_md = "\n## Invalid folds (excluded from metrics, NOT zero-scored)\n" + "\n".join(
            f"- held-out `{f['held_out_walk']}`: training missing "
            f"{', '.join(f['training_missing'])}" for f in info["invalid_folds"]) + "\n"

    wpc_md = ", ".join(f"{c}: {len(w)}" for c, w in info["walks_per_class"].items())
    report = f"""# Training run {run}

- pair: **{pair}**, walks: {', '.join(walks)} ({gnb_m['n']} eval rows)
- dataset sha256: `{dataset_sha}`
- tiers: `{args.tiers}` | baseline: `{args.rules}`
- validation: {"leave-one-walk-out (valid folds only)" if info['held_out'] else "IN-SAMPLE ONLY — cannot promote"}
- walks per class: {wpc_md} (promotion floor: >=3 walks, >=2 per class)
{invalid_md}

| metric | GNB | rules |
|---|---|---|
| macro-F1 | {gnb_m['macro_f1']} | {rules_m['macro_f1']} |
| accuracy | {gnb_m['accuracy']} | {rules_m['accuracy']} |
| dangerous (close<->inrange) | {gnb_m['dangerous']} | {rules_m['dangerous']} |

## GNB confusion
{confusion_md(gnb_m['confusion'])}

## Rules confusion
{confusion_md(rules_m['confusion'])}

## Verdict

**{verdict}**
"""
    with open(os.path.join(run_dir, "report.md"), "w") as f:
        f.write(report)

    print(report)
    print(f"registry run: {run_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
