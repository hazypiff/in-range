#!/usr/bin/env python3
"""Ingest extract_walk.py JSON outputs into a labeled feature dataset.

Rows come ONLY from stations whose label carries a measured distance
("35ft", "10ft-blocked"). Stations without one (indoor venue stops like
"same-room") are skipped for tier training — they calibrate the venue score,
not the distance classifier. Two rows per station: one per receive direction.

Usage:
  python3 learn/ingest.py run_logs/walks/*/walk.json --pair s9-s9 \
      --out learn/data/dataset.jsonl
"""
import argparse
import hashlib
import json
import os
import re

DIST_RE = re.compile(r"(\d+)\s*ft", re.I)

FEATURES = ["high_med", "iqr_w", "rate", "high_n", "med_n", "venue_v", "gps_delta"]


def station_meta(label):
    m = DIST_RE.search(label)
    if not m:
        return None
    return int(m.group(1)), ("block" in label.lower())


def phone_features(p, venue_v, gps_delta):
    iqr = None
    if "high_p25" in p and "high_p75" in p:
        iqr = p["high_p75"] - p["high_p25"]
    return {
        "high_med": p.get("high_med"),     # None when silent — silence is a
        "iqr_w": iqr,                      # missing feature, not an imputed 0
        "rate": p.get("rate", 0.0),        # 0.0 when silent — rate IS the signal
        "high_n": p.get("high_n", 0),
        "med_n": p.get("med_n", 0),
        "venue_v": venue_v,
        "gps_delta": gps_delta,
    }


def rows_from_walk(walk, walk_id, pair):
    rows = []
    for s in walk["stations"]:
        meta = station_meta(s["station"])
        if meta is None:
            continue
        dist, blocked = meta
        venue_v = (s.get("venue") or {}).get("V")
        gps_delta = s.get("gps_delta_m")
        for d in ("a", "b"):
            rows.append({
                "walk_id": walk_id, "pair": pair, "station": s["station"],
                "direction": d, "distance_ft": dist, "blocked": blocked,
                "features": phone_features(s[d], venue_v, gps_delta),
            })
    return rows


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("walks", nargs="+", help="walk.json files from extract_walk.py")
    ap.add_argument("--pair", required=True,
                    help="device pair label, e.g. s9-s9 or iphone14-iphone15")
    ap.add_argument("--out", required=True, help="dataset.jsonl output path")
    args = ap.parse_args()

    rows = []
    for path in args.walks:
        walk_id = os.path.basename(os.path.dirname(os.path.abspath(path))) or path
        rows.extend(rows_from_walk(json.load(open(path)), walk_id, args.pair))

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w") as f:
        for r in rows:
            f.write(json.dumps(r, sort_keys=True) + "\n")

    walks = sorted({r["walk_id"] for r in rows})
    print(f"{len(rows)} rows from {len(walks)} walk(s): {', '.join(walks)}")
    print(f"dataset sha256: {sha256_file(args.out)}")
    if len(walks) < 2:
        print("WARNING: <2 walks — training will run but is NOT PROMOTABLE "
              "(no held-out group).")


if __name__ == "__main__":
    main()
