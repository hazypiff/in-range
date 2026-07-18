#!/usr/bin/env python3
"""Export the PROMOTED model as the app-ready artifact.

Reads learn/registry/PROMOTED (one line: the run directory name — written by
a HUMAN after reviewing that run's report.md), verifies the run exists and
its dataset hash is recorded, and writes the artifact JSON for the app's
GnbClassifier.fromJson (lib/features/beacon/proximity_classifier.dart).

Usage:
  python3 learn/export.py [--out ../in-range/assets/proximity_model.json]

The default --out only STAGES the artifact next to the registry
(learn/registry/promoted_model.json); copying it into the app and wiring the
runtime stays a deliberate, reviewed app-repo change (deferred 2026-07-18
until a walk-validated promoted model exists).
"""
import argparse
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
REGISTRY = os.path.join(HERE, "registry")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", default=os.path.join(REGISTRY, "promoted_model.json"))
    ap.add_argument("--non-production", action="store_true",
                    help="allow exporting a model trained on identity-"
                         "unverified walks; the artifact is stamped "
                         "non_production=true and must never ship")
    args = ap.parse_args()

    pointer = os.path.join(REGISTRY, "PROMOTED")
    if not os.path.exists(pointer):
        raise SystemExit("no learn/registry/PROMOTED pointer — promotion is a "
                         "human step: review a run's report.md, then write its "
                         "run name into that file.")
    run = open(pointer).read().strip()
    model_path = os.path.join(REGISTRY, run, "model.json")
    if not os.path.exists(model_path):
        raise SystemExit(f"PROMOTED points at {run!r} but {model_path} does not exist")

    model = json.load(open(model_path))
    if not model.get("dataset_sha256") or model.get("schema") != "inrange-gnb-1":
        raise SystemExit("model.json missing schema/dataset hash — refusing to export")
    cv = model.get("cv", {})
    if not cv.get("held_out"):
        raise SystemExit(f"{run} was trained without valid held-out folds — "
                         "refusing to export")
    if not cv.get("coverage_ok"):
        raise SystemExit(f"{run} misses the coverage floor (>=3 walks, >=2 "
                         "walks per class) — refusing to export")
    if cv.get("invalid_folds"):
        raise SystemExit(f"{run} had invalid folds (training sets missing "
                         "classes) — refusing to export")
    unverified = cv.get("unverified_walks")
    if unverified is None:
        raise SystemExit(f"{run} predates the identity contract (no "
                         "unverified_walks record) — retrain before export")
    if unverified:
        if not args.non_production:
            raise SystemExit(
                f"{run} trained on identity-unverified walks "
                f"({', '.join(unverified)}) — refusing production export. "
                "Re-extract those walks with --pair/--capture-meta, or pass "
                "--non-production for a stamped non-shippable artifact.")
        model["non_production"] = True
        print("WARNING: artifact stamped non_production=true — NOT for runtime")

    with open(args.out, "w") as f:
        json.dump(model, f, indent=1, sort_keys=True)
    print(f"exported {run} -> {args.out}")
    print("next (deliberate app-repo step): copy into the app, load via "
          "GnbClassifier.fromJson, and wire behind a flag.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
