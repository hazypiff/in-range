#!/usr/bin/env python3
"""Walk #4 extraction — turn two phones' logcat into per-station calibration.

Reads the calibration log lines this build emits (INRANGE_CALIB_SCAN=true):
  Advert corr=XXXXXXXX rssi=-NN pw=H|M          — one per received BLE packet
  WifiScan seq=N aps=N fresh=N usable=N          — one WiFi scan header
  WifiAp seq=N bssid=.. rssi=-NN band=2|5 age=Ns — one per AP in that scan
  GpsFix lat=.. lon=.. acc=Nm [(claim)]          — one GPS fix

Given the stations (label, start-time, end-time), it produces, per station and
per phone: BLE median/IQR/rate by power slot, the WiFi fingerprint, GPS accuracy,
and — across the two phones — the WiFi venue score and the GPS inter-phone
distance. This is the labeled dataset the fusion research says to FIT weights on.

Usage:
  # 1. pull both phones' logs (do this the moment the walk ends):
  adb -s <A> logcat -d -v threadtime > walkA.txt
  adb -s <B> logcat -d -v threadtime > walkB.txt
  # 2. run with the noted station times (HH:MM:SS, 24h):
  python3 extract_walk.py walkA.txt walkB.txt \
      --start 03:48:00 --stations 5:90 10:90 15:90 25:90 35:90 50:90 \
      --blocked 10:90 35:90
"""
import argparse
import math
import re
import statistics as st
from collections import defaultdict

TRIM_S = 20  # drop the first 20 s of each station (walking-into-position)


def ts(s):
    h, m, sec = s.split(":")
    return int(h) * 3600 + int(m) * 60 + float(sec)


def parse_log(path):
    adverts, gps = [], []
    wifi = defaultdict(list)  # seq -> [(bssid, rssi, band, age)]
    wifi_at = {}              # seq -> log time (s)
    for line in open(path, errors="ignore"):
        m = re.search(r"(\d\d:\d\d:\d\d\.\d+).*Advert corr=(\w+) rssi=(-?\d+) pw=(\w)", line)
        if m:
            adverts.append((ts(m.group(1)), m.group(2), int(m.group(3)), m.group(4)))
            continue
        m = re.search(r"(\d\d:\d\d:\d\d\.\d+).*WifiAp seq=(\d+) bssid=(\S+) rssi=(-?\d+) band=(\d) age=(\d+)", line)
        if m:
            seq = int(m.group(2))
            wifi[seq].append((m.group(3), int(m.group(4)), int(m.group(5)), int(m.group(6))))
            wifi_at.setdefault(seq, ts(m.group(1)))
            continue
        m = re.search(r"(\d\d:\d\d:\d\d\.\d+).*GpsFix lat=(-?\d+\.\d+) lon=(-?\d+\.\d+) acc=(-?[\d.]+)m", line)
        if m:
            gps.append((ts(m.group(1)), float(m.group(2)), float(m.group(3)), float(m.group(4))))
    return adverts, wifi, wifi_at, gps


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


def fingerprint(aps, gate=-70):
    """Latest-per-bssid, gated. Returns {bssid: rssi}."""
    best = {}
    for bssid, rssi, band, age in aps:
        if rssi >= gate and (bssid not in best or rssi > best[bssid]):
            best[bssid] = rssi
    return best


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


def station_windows(start, stations, blocked):
    out, t = [], ts(start)
    for spec in stations:
        ft, dur = spec.split(":")
        out.append((f"{ft}ft", t, t + int(dur)))
        t += int(dur)
    for spec in blocked:
        ft, dur = spec.split(":")
        out.append((f"{ft}ft-blocked", t, t + int(dur)))
        t += int(dur)
    return out


def phone_station(adv, wifi, wifi_at, gps, a, b):
    lo, hi = a + TRIM_S, b
    band = [r for (t, c, r, p) in adv if lo <= t < hi and p == "H"]
    med = [r for (t, c, r, p) in adv if lo <= t < hi and p == "M"]
    dur = max(1, hi - lo)
    # freshest wifi scan whose header time falls in the window
    fp = {}
    seqs = [s for s, wt in wifi_at.items() if lo <= wt < hi]
    if seqs:
        fp = fingerprint(wifi[max(seqs, key=lambda s: wifi_at[s])])
    fixes = [(la, lo_, ac) for (t, la, lo_, ac) in gps if lo <= t < hi]
    res = {"high_n": len(band), "med_n": len(med), "rate": round(len(band) / dur, 2), "fp": fp}
    if band:
        p25, m, p75 = quart(band)
        res.update(high_med=m, high_iqr=(p25, p75))
    if med:
        _, mm, _ = quart(med)
        res["med_med"] = mm
    if fixes:
        res["gps"] = fixes[-1]
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("logA")
    ap.add_argument("logB")
    ap.add_argument("--start", required=True, help="first station start HH:MM:SS")
    ap.add_argument("--stations", nargs="+", required=True, help="ft:dur e.g. 5:90 10:90")
    ap.add_argument("--blocked", nargs="*", default=[], help="body-blocked ft:dur")
    args = ap.parse_args()

    A = parse_log(args.logA)
    B = parse_log(args.logB)
    print(f"Phone A: {len(A[0])} adverts, {len(A[1])} wifi scans, {len(A[3])} gps fixes")
    print(f"Phone B: {len(B[0])} adverts, {len(B[1])} wifi scans, {len(B[3])} gps fixes")

    print(f"\n{'station':>14} | {'A high med/IQR':>18} {'rate':>5} {'medN':>4} | "
          f"{'B high med':>10} | {'venue V':>8} | {'GPS Δm':>7}")
    print("-" * 92)
    for label, a, b in station_windows(args.start, args.stations, args.blocked):
        pa = phone_station(*A, a, b)
        pb = phone_station(*B, a, b)
        am = f"{pa.get('high_med','—')}/{pa.get('high_iqr','')}" if 'high_med' in pa else "SILENT"
        bm = pb.get('high_med', 'SILENT')
        vs = venue_score(pa["fp"], pb["fp"])
        v = vs["V"] if vs else "—"
        gd = "—"
        if "gps" in pa and "gps" in pb:
            gd = round(haversine(pa["gps"][0], pa["gps"][1], pb["gps"][0], pb["gps"][1]), 1)
        print(f"{label:>14} | {am:>18} {pa.get('rate','—'):>5} {pa.get('med_n',0):>4} | "
              f"{str(bm):>10} | {str(v):>8} | {str(gd):>7}")

    print("\nNotes:")
    print("  * high med/IQR = median (p25,p75) of HIGH-power RSSI — the Close By signal")
    print("  * medN = medium-slot packets received — the Near By gate (>0 => within medium range)")
    print("  * venue V >=0.60 same venue, 0.30-0.60 same building, <0.30 different (both phones' WiFi)")
    print("  * GPS Δm = distance between the two phones' fixes (should be small; bounds GPS usefulness)")


if __name__ == "__main__":
    main()
