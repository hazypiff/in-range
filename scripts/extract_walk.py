#!/usr/bin/env python3
"""Walk extraction — turn two phones' logcat into per-station calibration data.

Reads the calibration log lines this build emits (INRANGE_CALIB_SCAN=true):
  Advert corr=XXXXXXXX rssi=-NN pw=H|M          — one per received BLE packet
  WifiScan seq=N aps=N fresh=N usable=N          — one WiFi scan header
  WifiAp seq=N bssid=.. rssi=-NN band=2|5 age=Ns — one per AP in that scan
  GpsFix lat=.. lon=.. acc=Nm [(claim)]          — one GPS fix

Stations carry EXPLICIT per-station start times (the validated walk method is
stop-and-return with gaps between stations — see DEVICE_TESTING_JOURNAL
2026-07-17; back-to-back timing is NOT assumed). Within each window, ALL WiFi
scans are aggregated (best RSSI per BSSID, stale APs rejected by cache age)
and ALL GPS fixes are aggregated (median position, worst accuracy).

Outputs the human table plus machine-readable JSON (raw observations included,
so aggregates are reproducible) and CSV.

Usage:
  # capture with scripts/walk_capture.sh (prep before, pull after) — it writes
  # gzipped threadtime logs + meta.json with per-device clock offsets.
  python3 scripts/extract_walk.py walkA.threadtime.log.gz walkB.threadtime.log.gz \
      --stations 35ft@14:05:00+90 65ft@14:12:30+90 110ft@14:21:00-14:22:30 \
      --json walk.json --csv walk.csv \
      --offset-a 1.2 --offset-b -0.4

  Station spec: LABEL@HH:MM:SS+DURSEC or LABEL@HH:MM:SS-HH:MM:SS (24h, host
  clock). Gaps between stations are fine; labels are free-form (e.g.
  "10ft-blocked"). --stations-file takes a JSON list of
  {"label":..,"start":"HH:MM:SS","dur":90} or {...,"end":"HH:MM:SS"}.

  --offset-a/--offset-b = host_minus_device_s from walk_capture.sh meta.json
  (seconds ADDED to that phone's log timestamps to align them to the host
  clock the station times were noted on).
"""
import argparse
import csv
import gzip
import json
import math
import re
import statistics as st

DAY = 86400
TRIM_S = 20        # drop the first N s of each station (walking-into-position)
MAX_AP_AGE = 60    # reject cached APs older than this (s) — Android returns
                   # CACHED scan results; stale entries describe where the
                   # phone WAS, not where it is
GATE = -70         # AP RSSI gate (mirrors venue_matcher.dart fingerprint gate)


def ts(s):
    h, m, sec = s.split(":")
    return int(h) * 3600 + int(m) * 60 + float(sec)


def hms(t):
    t = t % DAY
    return f"{int(t // 3600):02d}:{int(t % 3600 // 60):02d}:{int(t % 60):02d}"


class Unwrapper:
    """Turns wall-clock HH:MM:SS times into a monotonic stream across
    midnight: a backwards jump of more than half a day means we rolled over."""

    def __init__(self):
        self.prev = None
        self.day = 0

    def __call__(self, t):
        if self.prev is not None and t < self.prev - DAY / 2:
            self.day += 1
        self.prev = t
        return t + self.day * DAY


def openlog(path):
    if str(path).endswith(".gz"):
        return gzip.open(path, "rt", errors="ignore")
    return open(path, errors="ignore")


ADVERT_RE = re.compile(r"(\d\d:\d\d:\d\d\.\d+).*Advert corr=(\w+) rssi=(-?\d+) pw=(\w)")
WIFIAP_RE = re.compile(
    r"(\d\d:\d\d:\d\d\.\d+).*WifiAp seq=(\d+) bssid=(\S+) rssi=(-?\d+) band=(\d) age=(\d+)")
GPS_RE = re.compile(
    r"(\d\d:\d\d:\d\d\.\d+).*GpsFix lat=(-?\d+\.\d+) lon=(-?\d+\.\d+) acc=(-?[\d.]+)m")


def parse_log(path, offset=0.0):
    """-> {"adverts": [(t, corr, rssi, pw)], "wifi": [{"seq", "t", "aps"}],
    "gps": [(t, lat, lon, acc)]}. Times are monotonic (midnight-unwrapped)
    seconds, shifted by `offset` onto the host clock."""
    unwrap = Unwrapper()
    adverts, gps = [], []
    scans = {}      # seq -> {"seq", "t", "aps": [(bssid, rssi, band, age)]}
    with openlog(path) as f:
        for line in f:
            m = ADVERT_RE.search(line)
            if m:
                adverts.append((unwrap(ts(m.group(1))) + offset,
                                m.group(2), int(m.group(3)), m.group(4)))
                continue
            m = WIFIAP_RE.search(line)
            if m:
                t = unwrap(ts(m.group(1))) + offset
                seq = int(m.group(2))
                s = scans.setdefault(seq, {"seq": seq, "t": t, "aps": []})
                s["aps"].append((m.group(3), int(m.group(4)),
                                 int(m.group(5)), int(m.group(6))))
                continue
            m = GPS_RE.search(line)
            if m:
                gps.append((unwrap(ts(m.group(1))) + offset, float(m.group(2)),
                            float(m.group(3)), float(m.group(4))))
    return {"adverts": adverts,
            "wifi": sorted(scans.values(), key=lambda s: s["t"]),
            "gps": gps}


STATION_RE = re.compile(
    r"^(?P<label>.+)@(?P<start>\d\d:\d\d:\d\d)"
    r"(?:\+(?P<dur>\d+)|-(?P<end>\d\d:\d\d:\d\d))$")


def parse_stations(specs):
    """['35ft@14:05:00+90', ...] -> [(label, start_s, end_s)], start times
    midnight-unwrapped across the list, end always > start."""
    unwrap = Unwrapper()
    out = []
    for spec in specs:
        m = STATION_RE.match(spec)
        if not m:
            raise SystemExit(f"bad station spec: {spec!r} "
                             "(want LABEL@HH:MM:SS+DUR or LABEL@HH:MM:SS-HH:MM:SS)")
        start = unwrap(ts(m.group("start")))
        if m.group("dur"):
            end = start + int(m.group("dur"))
        else:
            day_base = start - (start % DAY)
            end = day_base + ts(m.group("end"))
            if end <= start:
                end += DAY
        out.append((m.group("label"), start, end))
    return out


def load_stations_file(path):
    specs = []
    for s in json.load(open(path)):
        if "dur" in s:
            specs.append(f"{s['label']}@{s['start']}+{int(s['dur'])}")
        else:
            specs.append(f"{s['label']}@{s['start']}-{s['end']}")
    return parse_stations(specs)


def quart(vals):
    vals = sorted(vals)
    if len(vals) >= 4:
        q = st.quantiles(vals, n=4)
        return q[0], st.median(vals), q[2]
    return min(vals), st.median(vals), max(vals)


# --- WiFi venue score (mirrors lib/features/beacon/venue_matcher.dart) ---
RSSI_FLOOR = -100
BETA = math.e


def powed(rssi):
    if rssi <= RSSI_FLOOR:
        return 0.0
    return ((rssi - RSSI_FLOOR) / (-RSSI_FLOOR)) ** BETA


def venue_score(a, b):
    if not a or not b:
        return None
    union = set(a) | set(b)
    shared = len(set(a) & set(b))
    jac = shared / len(union)
    num = sum(abs(powed(a.get(k, RSSI_FLOOR)) - powed(b.get(k, RSSI_FLOOR))) for k in union)
    den = sum(powed(a.get(k, RSSI_FLOOR)) + powed(b.get(k, RSSI_FLOOR)) for k in union)
    sor = 1 - (num / den if den else 1)
    return dict(V=round(0.5 * jac + 0.5 * sor, 3), jaccard=round(jac, 3),
                sorensen=round(sor, 3), shared=shared, total=len(union))


def haversine(lat1, lon1, lat2, lon2):
    R = 6371000
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    x = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return R * 2 * math.asin(math.sqrt(x))


def phone_station(data, lo, hi, trim=TRIM_S, max_ap_age=MAX_AP_AGE, gate=GATE):
    """One phone, one station window [lo, hi). Aggregates EVERY WiFi scan and
    GPS fix in the window; raw observations are preserved in the result."""
    lo2 = lo + trim
    dur = max(1.0, hi - lo2)
    high = [(t, r) for (t, c, r, p) in data["adverts"] if lo2 <= t < hi and p == "H"]
    med = [(t, r) for (t, c, r, p) in data["adverts"] if lo2 <= t < hi and p == "M"]

    scans = [s for s in data["wifi"] if lo2 <= s["t"] < hi]
    fp, stale_dropped = {}, 0
    for s in scans:
        for (bssid, rssi, band, age) in s["aps"]:
            if age > max_ap_age:
                stale_dropped += 1
                continue
            if rssi < gate:
                continue
            if bssid not in fp or rssi > fp[bssid]:
                fp[bssid] = rssi

    fixes = [(t, la, ln, ac) for (t, la, ln, ac) in data["gps"] if lo2 <= t < hi]

    res = {
        "high_n": len(high), "med_n": len(med),
        "rate": round(len(high) / dur, 2),
        "fp": fp, "scan_n": len(scans), "stale_dropped": stale_dropped,
        "fix_n": len(fixes),
        "raw": {
            "adverts_high": [(round(t, 3), r) for (t, r) in high],
            "adverts_med": [(round(t, 3), r) for (t, r) in med],
            "wifi_scans": [{"seq": s["seq"], "t": round(s["t"], 3), "aps": s["aps"]}
                           for s in scans],
            "gps_fixes": [(round(t, 3), la, ln, ac) for (t, la, ln, ac) in fixes],
        },
    }
    if high:
        p25, m, p75 = quart([r for (_, r) in high])
        res.update(high_med=m, high_p25=p25, high_p75=p75)
    if med:
        _, mm, _ = quart([r for (_, r) in med])
        res["med_med"] = mm
    if fixes:
        res["gps_med"] = (st.median([la for (_, la, _, _) in fixes]),
                          st.median([ln for (_, _, ln, _) in fixes]))
        res["gps_worst_acc"] = max(ac for (_, _, _, ac) in fixes)
    return res


def extract(dataA, dataB, stations, trim=TRIM_S, max_ap_age=MAX_AP_AGE):
    rows = []
    for label, a, b in stations:
        pa = phone_station(dataA, a, b, trim, max_ap_age)
        pb = phone_station(dataB, a, b, trim, max_ap_age)
        vs = venue_score(pa["fp"], pb["fp"])
        gd = None
        if "gps_med" in pa and "gps_med" in pb:
            gd = round(haversine(*pa["gps_med"], *pb["gps_med"]), 1)
        rows.append({"station": label, "start": hms(a), "end": hms(b),
                     "start_s": a, "end_s": b,
                     "a": pa, "b": pb, "venue": vs, "gps_delta_m": gd})
    return rows


CSV_FIELDS = ["station", "start", "end",
              "a_high_n", "a_high_med", "a_high_p25", "a_high_p75", "a_rate", "a_med_n",
              "b_high_n", "b_high_med", "b_high_p25", "b_high_p75", "b_rate", "b_med_n",
              "venue_V", "venue_jaccard", "venue_sorensen", "venue_shared",
              "a_scan_n", "b_scan_n", "a_stale_dropped", "b_stale_dropped",
              "gps_delta_m", "a_fix_n", "b_fix_n", "a_gps_worst_acc", "b_gps_worst_acc"]


def csv_row(r):
    v = r["venue"] or {}
    out = {"station": r["station"], "start": r["start"], "end": r["end"],
           "venue_V": v.get("V"), "venue_jaccard": v.get("jaccard"),
           "venue_sorensen": v.get("sorensen"), "venue_shared": v.get("shared"),
           "gps_delta_m": r["gps_delta_m"]}
    for side in "ab":
        p = r[side]
        out.update({f"{side}_high_n": p["high_n"], f"{side}_high_med": p.get("high_med"),
                    f"{side}_high_p25": p.get("high_p25"), f"{side}_high_p75": p.get("high_p75"),
                    f"{side}_rate": p["rate"], f"{side}_med_n": p["med_n"],
                    f"{side}_scan_n": p["scan_n"], f"{side}_stale_dropped": p["stale_dropped"],
                    f"{side}_fix_n": p["fix_n"], f"{side}_gps_worst_acc": p.get("gps_worst_acc")})
    return out


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("logA", help="phone A logcat (threadtime, .gz ok)")
    ap.add_argument("logB", help="phone B logcat (threadtime, .gz ok)")
    ap.add_argument("--stations", nargs="+",
                    help="LABEL@HH:MM:SS+DUR or LABEL@HH:MM:SS-HH:MM:SS per station")
    ap.add_argument("--stations-file", help="JSON station list (see module docstring)")
    ap.add_argument("--offset-a", type=float, default=0.0,
                    help="host_minus_device_s for phone A (from walk_capture meta.json)")
    ap.add_argument("--offset-b", type=float, default=0.0,
                    help="host_minus_device_s for phone B")
    ap.add_argument("--trim", type=int, default=TRIM_S,
                    help=f"seconds trimmed from each station start (default {TRIM_S})")
    ap.add_argument("--max-ap-age", type=int, default=MAX_AP_AGE,
                    help=f"reject cached APs older than this, s (default {MAX_AP_AGE})")
    ap.add_argument("--json", help="write full results (incl. raw observations)")
    ap.add_argument("--csv", help="write per-station summary CSV")
    args = ap.parse_args()

    if not args.stations and not args.stations_file:
        ap.error("need --stations or --stations-file")
    stations = (load_stations_file(args.stations_file) if args.stations_file
                else parse_stations(args.stations))

    dataA = parse_log(args.logA, args.offset_a)
    dataB = parse_log(args.logB, args.offset_b)
    print(f"Phone A: {len(dataA['adverts'])} adverts, {len(dataA['wifi'])} wifi scans, "
          f"{len(dataA['gps'])} gps fixes (offset {args.offset_a:+.1f}s)")
    print(f"Phone B: {len(dataB['adverts'])} adverts, {len(dataB['wifi'])} wifi scans, "
          f"{len(dataB['gps'])} gps fixes (offset {args.offset_b:+.1f}s)")

    rows = extract(dataA, dataB, stations, args.trim, args.max_ap_age)

    print(f"\n{'station':>14} | {'A high med/IQR':>18} {'rate':>5} {'medN':>4} | "
          f"{'B high med':>10} | {'venue V':>8} {'scans':>5} | {'GPS Δm':>7} {'fixes':>5}")
    print("-" * 100)
    for r in rows:
        pa, pb = r["a"], r["b"]
        am = (f"{pa['high_med']}/({pa['high_p25']},{pa['high_p75']})"
              if "high_med" in pa else "SILENT")
        bm = pb.get("high_med", "SILENT")
        v = r["venue"]["V"] if r["venue"] else "—"
        gd = r["gps_delta_m"] if r["gps_delta_m"] is not None else "—"
        print(f"{r['station']:>14} | {am:>18} {pa['rate']:>5} {pa['med_n']:>4} | "
              f"{str(bm):>10} | {str(v):>8} {pa['scan_n']}+{pb['scan_n']:>3} | "
              f"{str(gd):>7} {pa['fix_n']}+{pb['fix_n']:>3}")
        if pa["stale_dropped"] or pb["stale_dropped"]:
            print(f"{'':>14}   (stale APs dropped: A={pa['stale_dropped']} "
                  f"B={pb['stale_dropped']}, age > {args.max_ap_age}s)")

    if args.json:
        meta = {"logA": args.logA, "logB": args.logB,
                "offset_a": args.offset_a, "offset_b": args.offset_b,
                "trim_s": args.trim, "max_ap_age_s": args.max_ap_age,
                "gate_dbm": GATE,
                "stations": [{"label": l, "start": hms(a), "end": hms(b)}
                             for (l, a, b) in stations]}
        with open(args.json, "w") as f:
            json.dump({"meta": meta, "stations": rows}, f, indent=1)
        print(f"\nwrote {args.json}")
    if args.csv:
        with open(args.csv, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=CSV_FIELDS)
            w.writeheader()
            for r in rows:
                w.writerow(csv_row(r))
        print(f"wrote {args.csv}")

    print("\nNotes:")
    print("  * high med/IQR = median (p25,p75) of HIGH-power RSSI — the Close By signal")
    print("  * medN = medium-slot packets received — the Near By gate (>0 => within medium range)")
    print("  * venue V >=0.60 same venue, 0.30-0.60 same building, <0.30 different")
    print("  * fingerprints union ALL in-window scans (best RSSI per BSSID), stale APs rejected")
    print("  * GPS Δm from per-phone MEDIAN fix; worst accuracy per phone is in the CSV/JSON")


if __name__ == "__main__":
    main()
