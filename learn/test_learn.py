#!/usr/bin/env python3
"""Tests for the learn/ pipeline — run: python3 learn/test_learn.py"""
import json
import os
import random
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ingest  # noqa: E402
import train  # noqa: E402

TIERS = train.parse_tiers("close:0-75,near:76-150,inrange:151-100000")


def phone(high_med=None, p25=None, p75=None, rate=0.0, high_n=0, med_n=0):
    p = {"rate": rate, "high_n": high_n, "med_n": med_n}
    if high_med is not None:
        p.update(high_med=high_med, high_p25=p25 if p25 is not None else high_med - 2,
                 high_p75=p75 if p75 is not None else high_med + 2)
    return p


def synth_walk(rng, shift=0.0):
    """One synthetic walk: separable close/near/inrange stations."""
    stations = []
    for dist, base in [(35, -77), (65, -83), (110, -89), (150, -95), (175, -98)]:
        med = base + shift + rng.uniform(-1.5, 1.5)
        stations.append({
            "station": f"{dist}ft",
            "a": phone(round(med, 1), rate=1.0 - dist / 300, high_n=60),
            "b": phone(round(med + rng.uniform(-2, 2), 1), rate=1.0 - dist / 300, high_n=55),
            "venue": {"V": 0.8},
            "gps_delta_m": dist / 3.3,
        })
    # a silent far station: no packets at all (missing high_med, rate 0)
    stations.append({"station": "250ft", "a": phone(), "b": phone(),
                     "venue": None, "gps_delta_m": None})
    # an unlabeled indoor stop that must be ignored by ingest
    stations.append({"station": "same-room", "a": phone(-60), "b": phone(-62),
                     "venue": {"V": 0.9}, "gps_delta_m": 4.0})
    return {"meta": {}, "stations": stations}


def make_dataset(n_walks=3):
    rng = random.Random(42)
    rows = []
    for i in range(n_walks):
        walk = synth_walk(rng, shift=rng.uniform(-1, 1))
        rows.extend(ingest.rows_from_walk(walk, f"walk{i}", "iphone14-iphone15"))
    return rows


class IngestTest(unittest.TestCase):
    def test_labeled_stations_only(self):
        rows = ingest.rows_from_walk(synth_walk(random.Random(1)), "w", "p")
        self.assertEqual(len(rows), 12)  # 6 distance stations x 2 directions
        self.assertTrue(all("same-room" not in r["station"] for r in rows))

    def test_blocked_flag(self):
        walk = {"stations": [{"station": "10ft-blocked", "a": phone(-80),
                              "b": phone(-81), "venue": None, "gps_delta_m": None}]}
        rows = ingest.rows_from_walk(walk, "w", "p")
        self.assertTrue(all(r["blocked"] for r in rows))
        self.assertEqual(rows[0]["distance_ft"], 10)

    def test_silence_is_missing_not_zero(self):
        rows = ingest.rows_from_walk(synth_walk(random.Random(1)), "w", "p")
        silent = [r for r in rows if r["station"] == "250ft"]
        self.assertEqual(len(silent), 2)
        self.assertIsNone(silent[0]["features"]["high_med"])
        self.assertEqual(silent[0]["features"]["rate"], 0.0)


class GnbTest(unittest.TestCase):
    def test_fit_and_predict_separable(self):
        rows = make_dataset()
        model = train.fit_gnb(rows, TIERS)
        self.assertEqual(set(model), {"close", "near", "inrange"})
        pred, conf = train.gnb_predict(model, {"high_med": -78.0, "rate": 0.9,
                                               "high_n": 60, "med_n": 0})
        self.assertEqual(pred, "close")
        self.assertGreater(conf, 0.5)
        pred, _ = train.gnb_predict(model, {"high_med": -97.5, "rate": 0.4,
                                            "high_n": 55, "med_n": 0})
        self.assertEqual(pred, "inrange")

    def test_missing_features_skipped(self):
        rows = make_dataset()
        model = train.fit_gnb(rows, TIERS)
        # silence: only rate/high_n/med_n present — must not crash, and low
        # rate + zero packets should NOT look "close"
        pred, _ = train.gnb_predict(model, {"high_med": None, "iqr_w": None,
                                            "rate": 0.0, "high_n": 0, "med_n": 0,
                                            "venue_v": None, "gps_delta": None})
        self.assertNotEqual(pred, "close")

    def test_cv_beats_or_ties_rules_on_separable_data(self):
        rows = make_dataset(3)
        gnb_m, rules_m, held_out = train.cross_validate(rows, TIERS,
                                                        train.RULES["iphone"])
        self.assertTrue(held_out)
        self.assertGreaterEqual(gnb_m["macro_f1"], 0.8)
        self.assertGreaterEqual(gnb_m["macro_f1"], rules_m["macro_f1"] - 0.05)

    def test_single_walk_not_held_out(self):
        rows = [r for r in make_dataset(3) if r["walk_id"] == "walk0"]
        _, _, held_out = train.cross_validate(rows, TIERS, train.RULES["iphone"])
        self.assertFalse(held_out)

    def test_model_json_roundtrip(self):
        rows = make_dataset()
        model = train.fit_gnb(rows, TIERS)
        clone = json.loads(json.dumps(model))
        feats = {"high_med": -85.5, "rate": 0.7, "high_n": 50, "med_n": 0}
        self.assertEqual(train.gnb_predict(model, feats),
                         train.gnb_predict(clone, feats))

    def test_dangerous_error_counting(self):
        m = train.evaluate([("close", "inrange"), ("inrange", "close"),
                            ("close", "near"), ("near", "near")],
                           ["close", "near", "inrange"])
        self.assertEqual(m["dangerous"], 2)


class RulesTest(unittest.TestCase):
    def test_iphone_rules_boundaries(self):
        self.assertEqual(train.rules_iphone({"high_med": -84}), "close")
        self.assertEqual(train.rules_iphone({"high_med": -85}), "near")
        self.assertEqual(train.rules_iphone({"high_med": -96}), "near")
        self.assertEqual(train.rules_iphone({"high_med": -97}), "inrange")
        self.assertEqual(train.rules_iphone({"high_med": None}), "inrange")

    def test_s9_rules(self):
        self.assertEqual(train.rules_s9({"high_med": -78, "high_n": 6, "med_n": 0}),
                         "close")
        self.assertEqual(train.rules_s9({"high_med": -90, "high_n": 6, "med_n": 2}),
                         "near")
        self.assertEqual(train.rules_s9({"high_med": None, "high_n": 0, "med_n": 0}),
                         "inrange")


class EndToEndTest(unittest.TestCase):
    def test_ingest_train_cli(self):
        rng = random.Random(7)
        tmp = tempfile.mkdtemp()
        walks = []
        for i in range(2):
            d = os.path.join(tmp, f"2026-07-2{i}-walk")
            os.makedirs(d)
            p = os.path.join(d, "walk.json")
            json.dump(synth_walk(rng), open(p, "w"))
            walks.append(p)
        dataset = os.path.join(tmp, "dataset.jsonl")
        registry = os.path.join(tmp, "registry")

        import subprocess
        here = os.path.dirname(os.path.abspath(__file__))
        r = subprocess.run([sys.executable, os.path.join(here, "ingest.py"),
                            *walks, "--pair", "test", "--out", dataset],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("24 rows from 2 walk(s)", r.stdout)

        r = subprocess.run([sys.executable, os.path.join(here, "train.py"),
                            dataset, "--tiers", "close:0-75,near:76-150,inrange:151-100000",
                            "--rules", "iphone", "--registry", registry],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        runs = os.listdir(registry)
        self.assertEqual(len(runs), 1)
        model = json.load(open(os.path.join(registry, runs[0], "model.json")))
        self.assertEqual(model["schema"], "inrange-gnb-1")
        self.assertTrue(model["dataset_sha256"])
        self.assertTrue(model["cv"]["held_out"])
        self.assertTrue(os.path.exists(os.path.join(registry, runs[0], "report.md")))


if __name__ == "__main__":
    unittest.main(verbosity=2)
