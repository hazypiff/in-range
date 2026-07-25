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

iPHONE SIDE. Either input may instead be an iPhone's in_range_local.db (there
is no adb for iOS; pull it with `xcrun devicectl device copy from` — see
scripts/ios_station_check.sh). Mixed pairs are the normal case for S22<->iPhone:

  python3 scripts/extract_walk.py s22.threadtime.log.gz iphone.db \
      --stations 10ft@10:00:00+90 25ft@10:05:00+90 \
      --pair s22-iphone15p --offset-a 1.2 --json walk.json

Three things differ on that side, all handled here:
  * rssi_log is BLE-only, so venue V and GPS delta are None for those stations.
    train.py:73-74 SKIPS a None feature rather than imputing it, so the walk
    still trains on its BLE features.
  * at_ms is absolute epoch, so there is no midnight unwrapping and no clock
    offset needed — but the walk DATE must be established. --ios-date sets it;
    otherwise it is inferred by station-window coverage.
  * rssi_log is append-only across sessions, so a soak or desk test from
    another day sits in the same table. Windows exclude it; --ios-corr also
    filters by peer. IMPORTANT: the iPhone must be foregrounded once after the
    walk before pulling, or buffered samples never flush and the table is empty.

CLOUD SIDE. Either input may instead be `cloud:<device_id>`, which fetches that
device's rssi_samples (migration 0056) instead of reading a file — for phones
you cannot plug in, which is every real user. Needs SUPABASE_URL and
SUPABASE_SERVICE_ROLE_KEY in the environment:

  python3 scripts/extract_walk.py s22.threadtime.log.gz cloud:<device-uuid> \
      --stations 10ft@10:00:00+90 --pair s22-iphone15p --json walk.json

Requires a build carrying the uploader; a walk run from an older calibration
freeze has no server rows and must be pulled over USB. Rows are ordered by
device_seq (the phone's rssi_log rowid), and a HOLE in that sequence is fatal
by default: dropped rows and a quiet peer are indistinguishable from the RSSI
stream alone. --allow-seq-gaps accepts it, and that walk is not trainable.

The walk_id digest covers in-window SAMPLES, not the source file, so the same
walk extracted over USB and over the network yields the SAME walk_id. That
equality is the end-to-end check that the upload was lossless — keep pulling
the DB alongside the cloud fetch until you trust it.
"""
import argparse
import csv
import datetime as dt
import gzip
import hashlib
import json
import math
import os
import re
import sqlite3
import statistics as st
import time

DAY = 86400
TRIM_S = 20        # drop the first N s of each station (walking-into-position)
MAX_AP_AGE = 60    # reject cached APs older than this (s) — Android returns
                   # CACHED scan results; stale entries describe where the
                   # phone WAS, not where it is
GATE = -70         # AP RSSI gate (mirrors venue_matcher.dart fingerprint gate)
MIN_HIGH_N = 5     # below this a station's median is noise, not a measurement.
                   # Same bar learn/train.py:93 already applies in the rules
                   # baseline — one definition of "enough samples", not two.
                   # This matters most on a LOCKED iPHONE side, where samples
                   # arrive in sparse wake bursts: n=1 and n=200 produce the
                   # same-looking median, and ingest.py:39 forwards both as
                   # training rows with nothing but high_n to tell them apart.


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


# --- iOS side -------------------------------------------------------------
# There is no adb for iOS. The iPhone persists its own received adverts to
# rssi_log in Documents/in_range_local.db (local_db.dart:38-46), pulled with
# `xcrun devicectl device copy from` — see scripts/ios_station_check.sh.
#
# rssi_log carries BLE only: no WifiAp, no GpsFix. An iPhone side therefore
# produces empty wifi/gps lists, so venue_score() returns None and gps_delta_m
# is None for those stations. That is correct and safe: learn/train.py:73-74
# SKIPS a None feature rather than imputing it, so the walk trains on its BLE
# features instead of being poisoned by fabricated zeros.
IOS_EXTS = (".db", ".sqlite", ".sqlite3")


def is_ios_db(path):
    return str(path).lower().endswith(IOS_EXTS)


def local_midnight_epoch(date_str):
    """Epoch seconds of local midnight on YYYY-MM-DD (host timezone, which is
    the clock the station times were noted on)."""
    y, m, d = (int(x) for x in date_str.split("-"))
    return time.mktime(dt.date(y, m, d).timetuple())


def _local_date(epoch_s):
    return dt.datetime.fromtimestamp(epoch_s).strftime("%Y-%m-%d")


def ios_rows(path, corr_prefix=None):
    """Raw rssi_log rows as [(at_ms, correlation_id, rssi, power)]."""
    con = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    try:
        rows = con.execute(
            "SELECT at_ms, correlation_id, rssi, power FROM rssi_log "
            "ORDER BY at_ms ASC").fetchall()
    finally:
        con.close()
    if corr_prefix:
        # The Android log truncates to 8 hex chars (beacon_service.dart:973)
        # while rssi_log stores the full id, so this is a PREFIX match.
        rows = [r for r in rows if str(r[1]).startswith(corr_prefix)]
    return rows


CLOUD_PREFIX = "cloud:"
CLOUD_PAGE = 1000  # PostgREST's default max_rows


def is_cloud(path):
    return str(path).startswith(CLOUD_PREFIX)


def cloud_rows(spec, corr_prefix=None, allow_gaps=False):
    """rssi_samples for one device, in the same shape as ios_rows().

    Spec is `cloud:<device_id>`. Reads SUPABASE_URL and a key from the
    environment (SUPABASE_SERVICE_ROLE_KEY, else SUPABASE_KEY) — the service
    role is needed because the walker's rows belong to their auth user, not to
    whoever runs the extractor.

    Ordered by device_seq, NOT at_ms: device_seq is the phone's rssi_log rowid,
    so ordering by it is insertion order, and a hole in it is the one thing a
    stream of RSSI values cannot tell you — "the peer went quiet" and "the
    upload dropped rows" look identical otherwise.
    """
    import urllib.error
    import urllib.parse
    import urllib.request

    device_id = spec[len(CLOUD_PREFIX):]
    if not device_id:
        raise SystemExit("cloud spec needs a device id: cloud:<device_id>")
    base = os.environ.get("SUPABASE_URL", "").rstrip("/")
    key = (os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
           or os.environ.get("SUPABASE_KEY", ""))
    if not base or not key:
        raise SystemExit(
            "cloud extraction needs SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY "
            "(or SUPABASE_KEY) in the environment")

    out, offset = [], 0
    while True:
        q = urllib.parse.urlencode({
            "device_id": f"eq.{device_id}",
            "select": "device_seq,at_ms,correlation_id,rssi,power",
            "order": "device_seq.asc",
            "limit": CLOUD_PAGE,
            "offset": offset,
        })
        req = urllib.request.Request(
            f"{base}/rest/v1/rssi_samples?{q}",
            headers={"apikey": key, "Authorization": f"Bearer {key}",
                     "Accept": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                page = json.load(r)
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", "replace")[:400]
            raise SystemExit(f"cloud fetch failed ({e.code}): {body}")
        except urllib.error.URLError as e:
            raise SystemExit(f"cloud fetch failed: {e.reason}")
        out.extend(page)
        if len(page) < CLOUD_PAGE:
            break
        offset += CLOUD_PAGE

    if not out:
        raise SystemExit(
            f"no rssi_samples for device_id={device_id}. Check the id, and "
            "that the walk phone foregrounded the app after the walk so the "
            "uploader drained.")

    seqs = [int(r["device_seq"]) for r in out]
    missing = (seqs[-1] - seqs[0] + 1) - len(seqs)
    if missing and not allow_gaps:
        raise SystemExit(
            f"device_seq has {missing} missing row(s) between {seqs[0]} and "
            f"{seqs[-1]}. Either the upload dropped samples or the 7-day local "
            "prune deleted them before they shipped — both make this walk's "
            "sample counts wrong. Re-run with --allow-seq-gaps to accept it, "
            "and stamp the walk --trainable no.")
    if missing:
        print(f"WARNING: accepting {missing} missing device_seq row(s) — "
              "high_n/med_n are undercounts for this side")

    rows = [(int(r["at_ms"]), str(r["correlation_id"]), int(r["rssi"]),
             str(r["power"])) for r in out]
    rows.sort(key=lambda r: r[0])
    if corr_prefix:
        rows = [r for r in rows if r[1].startswith(corr_prefix)]
    return rows


def ios_dates(rows):
    """{local_date: n_rows} — used to pick the walk day and to show the
    operator what else is sitting in an append-only table."""
    out = {}
    for (at_ms, _c, _r, _p) in rows:
        d = _local_date(at_ms / 1000.0)
        out[d] = out.get(d, 0) + 1
    return out


def ios_best_date(rows, stations, offset=0.0):
    """Pick the local date whose rows best fill the station windows.

    NOT the densest day and NOT the latest row: rssi_log is append-only, and an
    overnight soak routinely holds far more rows than a 90 s-per-station walk
    (the S22 logged ~100 samples/30 s against a locked iPhone). Both of those
    heuristics therefore anchor to the soak and every station reports SILENT.
    Scoring candidate dates by in-window coverage optimises the only thing that
    matters, and degrades to an explicit warning when nothing fits.
    """
    best, best_n = None, -1
    for date in sorted(ios_dates(rows)):
        base = local_midnight_epoch(date)
        n = 0
        for (at_ms, _c, _r, _p) in rows:
            t = at_ms / 1000.0 - base + offset
            if any(lo <= t < hi for (_l, lo, hi) in stations):
                n += 1
        if n > best_n:
            best, best_n = date, n
    return best, best_n


def parse_ios_db(path, offset=0.0, date=None, corr_prefix=None, stations=None):
    """Same shape as parse_log(), from an iPhone's rssi_log.

    at_ms is ABSOLUTE epoch, so unlike logcat there is nothing to unwrap and
    no year to guess: times are converted directly to seconds-since-local-
    midnight of `date`. That also makes this immune to the stale-row hazard —
    rssi_log is append-only across sessions (only clearRssiLog empties it), so
    a prior soak's rows sit in the same table and an unwrapper seeded on "the
    first row in the file" would anchor the whole walk to the wrong day.
    """
    return parse_ios_rows(ios_rows(path, corr_prefix), offset, date, stations)


def parse_ios_rows(rows, offset=0.0, date=None, stations=None):
    """The half of parse_ios_db() that does not care where the rows came from.

    Shared with the cloud path so a walk extracted over the network goes
    through byte-identical windowing and digest arithmetic as the same walk
    extracted over USB — which is what makes the two comparable at all.
    """
    if not rows:
        return {"adverts": [], "wifi": [], "gps": [], "ios": {
            "date": date, "n_total": 0, "n_day": 0, "dates": {}}}
    dates = ios_dates(rows)
    inferred_n = None
    if date is None:
        if stations:
            date, inferred_n = ios_best_date(rows, stations, offset)
        else:
            date = max(dates, key=lambda d: (dates[d], d))
    base = local_midnight_epoch(date)
    adverts = []
    for (at_ms, corr, rssi, power) in rows:
        t = at_ms / 1000.0 - base + offset
        adverts.append((t, str(corr)[:8], int(rssi),
                        "H" if str(power).upper().startswith("H") else "M"))
    return {"adverts": adverts, "wifi": [], "gps": [], "ios": {
        "date": date, "n_total": len(rows), "n_day": dates.get(date, 0),
        "dates": dates, "inferred_in_window": inferred_n}}


def ios_digest(rows, side):
    """Content hash of the IN-WINDOW SAMPLES — not the file, and not the whole
    table.

    An Android .gz is immutable once pulled. An iPhone .db is a LIVING file:
    rssi_log keeps appending after the walk, so hashing the file (or even every
    row in it) mints a fresh walk_id on every re-pull. Two extractions of ONE
    walk would then present as two walks and satisfy the >=3-walk promotion
    gate with duplicates of itself — precisely what walk_manifest.v1 exists to
    prevent. Hashing only the samples that landed inside the station windows
    makes identity a property of the walk, not of when the DB was copied.
    """
    h = hashlib.sha256()
    for r in rows:
        p = r[side]
        for (t, rssi) in p["raw"]["adverts_high"]:
            h.update(f"H|{t}|{rssi}\n".encode())
        for (t, rssi) in p["raw"]["adverts_med"]:
            h.update(f"M|{t}|{rssi}\n".encode())
    return h.hexdigest()


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
        # Present but under-sampled. Distinct from SILENT (n=0), which is
        # already safe: no high_med key at all, so train.py skips the feature.
        # A thin station is the dangerous case — it looks like a measurement.
        "thin": 0 < len(high) < MIN_HIGH_N,
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


def file_sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def build_manifest(log_a, log_b, pair, capture_meta_path=None, freeze=None,
                   digests=None):
    """walk_manifest.v1 — immutable identity for this walk. walk_id is a
    content hash of the raw archives, so it survives renames and cannot
    collide across walks; pair/devices are captured HERE so training can
    VERIFY identity instead of assigning it via CLI.

    `digests` overrides the per-input hash for sources where the FILE is not
    a stable identity — see ios_digest()."""
    if digests is None:
        digests = {os.path.basename(p): file_sha256(p) for p in (log_a, log_b)}
    walk_id = hashlib.sha256(
        "".join(sorted(digests.values())).encode()).hexdigest()[:16]
    devices = None
    if capture_meta_path:
        devices = json.load(open(capture_meta_path)).get("devices")
    return {"version": "walk_manifest.v1", "walk_id": walk_id,
            "pair_id": pair, "devices": devices, "freeze": freeze,
            "archive_digests": digests}


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
    ap.add_argument("logA", help="phone A: logcat (threadtime, .gz ok) or "
                    "iPhone in_range_local.db")
    ap.add_argument("logB", help="phone B: logcat (threadtime, .gz ok) or "
                    "iPhone in_range_local.db")
    ap.add_argument("--ios-date", help="YYYY-MM-DD (host-local) the walk ran "
                    "on, for .db inputs. Default: the densest day in rssi_log. "
                    "rssi_log is append-only across sessions, so set this "
                    "explicitly when the DB also holds soak/desk-test rows")
    ap.add_argument("--allow-seq-gaps", action="store_true",
                    help="accept missing device_seq rows on a cloud side "
                         "(sample counts become undercounts; stamp the walk "
                         "--trainable no)")
    ap.add_argument("--ios-corr", help="only count rssi_log rows whose "
                    "correlation_id starts with this prefix (the peer being "
                    "measured) — use when the DB saw more than one peer")
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
    ap.add_argument("--trainable", choices=["yes", "no"], default="yes",
                    help="stamp meta.trainable — 'no' marks a smoke fixture / "
                         "unmeasured capture that the learn pipeline must "
                         "archive but never train on")
    ap.add_argument("--pair", help="device pair id for the walk manifest "
                    "(e.g. s9-s9) — ingest VERIFIES against this instead of "
                    "trusting its own CLI stamp")
    ap.add_argument("--capture-meta",
                    help="walk_capture meta-pull.json — copies device "
                         "serials/models into the manifest")
    ap.add_argument("--freeze", help="calibration freeze tag this walk ran "
                    "under (e.g. calib-freeze-2026-07-18)")
    args = ap.parse_args()

    if not args.stations and not args.stations_file:
        ap.error("need --stations or --stations-file")
    stations = (load_stations_file(args.stations_file) if args.stations_file
                else parse_stations(args.stations))

    def load(path, offset):
        if is_cloud(path):
            return parse_ios_rows(
                cloud_rows(path, args.ios_corr, args.allow_seq_gaps),
                offset, args.ios_date, stations)
        if is_ios_db(path):
            return parse_ios_db(path, offset, args.ios_date, args.ios_corr,
                                stations)
        return parse_log(path, offset)

    dataA = load(args.logA, args.offset_a)
    dataB = load(args.logB, args.offset_b)
    for side, path, data, off in (("A", args.logA, dataA, args.offset_a),
                                  ("B", args.logB, dataB, args.offset_b)):
        print(f"Phone {side}: {len(data['adverts'])} adverts, "
              f"{len(data['wifi'])} wifi scans, {len(data['gps'])} gps fixes "
              f"(offset {off:+.1f}s)")
        if "ios" not in data:
            continue
        io = data["ios"]
        how = ("" if args.ios_date else
               f" (inferred — {io['inferred_in_window']} rows land in station "
               "windows)" if io["inferred_in_window"] is not None
               else " (inferred — densest day)")
        print(f"          iOS rssi_log: {io['n_total']} rows total, "
              f"{io['n_day']} on {io['date']}{how}")
        if len(io["dates"]) > 1:
            other = ", ".join(f"{d}:{n}" for d, n in sorted(io["dates"].items())
                              if d != io["date"])
            print(f"          other days present (ignored): {other}")
        print("          NOTE: rssi_log is BLE-only — no WiFi/GPS from this "
              "phone, so venue V and GPS Δ are unavailable for these stations")

    rows = extract(dataA, dataB, stations, args.trim, args.max_ap_age)

    # A wrong --ios-date is the one failure that looks like a successful run:
    # every station reports SILENT and the walk quietly becomes untrainable.
    for side, path, data in (("A", args.logA, dataA), ("B", args.logB, dataB)):
        if not (is_ios_db(path) or is_cloud(path)) or not data["adverts"]:
            continue
        in_win = sum(r[side.lower()]["high_n"] + r[side.lower()]["med_n"]
                     for r in rows)
        if in_win == 0:
            print(f"\nWARNING: phone {side} has {len(data['adverts'])} rssi_log "
                  f"samples on {data['ios']['date']} but ZERO fell inside any "
                  "station window.")
            print("  Almost always a date/clock mismatch, not a silent walk. "
                  "Check --ios-date against the day the stations were timed, "
                  f"and that {data['ios']['date']} is the right day "
                  f"(rows by day: {data['ios']['dates']}).")

    def _n(p):
        # '!' marks a station whose median rests on too few samples to mean
        # anything. Printed next to the median it qualifies, because the whole
        # failure mode is that a thin median looks exactly like a solid one.
        return f"{p['high_n']}{'!' if p['thin'] else ''}"

    print(f"\n{'station':>14} | {'A high med/IQR':>18} {'A n':>5} {'rate':>5} "
          f"{'medN':>4} | {'B high med':>10} {'B n':>5} | {'venue V':>8} "
          f"{'scans':>5} | {'GPS Δm':>7} {'fixes':>5}")
    print("-" * 112)
    for r in rows:
        pa, pb = r["a"], r["b"]
        am = (f"{pa['high_med']}/({pa['high_p25']},{pa['high_p75']})"
              if "high_med" in pa else "SILENT")
        bm = pb.get("high_med", "SILENT")
        v = r["venue"]["V"] if r["venue"] else "—"
        gd = r["gps_delta_m"] if r["gps_delta_m"] is not None else "—"
        print(f"{r['station']:>14} | {am:>18} {_n(pa):>5} {pa['rate']:>5} "
              f"{pa['med_n']:>4} | {str(bm):>10} {_n(pb):>5} | "
              f"{str(v):>8} {pa['scan_n']}+{pb['scan_n']:>3} | "
              f"{str(gd):>7} {pa['fix_n']}+{pb['fix_n']:>3}")
        if pa["stale_dropped"] or pb["stale_dropped"]:
            print(f"{'':>14}   (stale APs dropped: A={pa['stale_dropped']} "
                  f"B={pb['stale_dropped']}, age > {args.max_ap_age}s)")

    # Loud, because the only cheap fix is to re-walk the station TODAY, while
    # the phones are still on this build and the geometry is still set up.
    thin = [(r["station"], side.upper(), r[side]["high_n"])
            for r in rows for side in ("a", "b") if r[side]["thin"]]
    if thin:
        print(f"\nWARNING: {len(thin)} station-side(s) below {MIN_HIGH_N} high "
              "samples — the median is noise, not a measurement:")
        for (label, side, n) in thin:
            print(f"  {label} phone {side}: high_n={n}")
        print("  Re-walk these stations now if you can. Ingesting them trains "
              "on single samples\n  dressed as medians; nothing downstream "
              "rejects them (learn/ingest.py:39).")

    if args.json:
        meta = {"logA": args.logA, "logB": args.logB,
                "offset_a": args.offset_a, "offset_b": args.offset_b,
                "trim_s": args.trim, "max_ap_age_s": args.max_ap_age,
                "gate_dbm": GATE, "trainable": args.trainable == "yes",
                "manifest": build_manifest(
                    args.logA, args.logB, args.pair, args.capture_meta,
                    args.freeze,
                    digests={
                        # A cloud side has no file to hash — and must not: the
                        # digest covers IN-WINDOW SAMPLES, which is exactly why
                        # the same walk pulled over USB and fetched from the
                        # server yields the same walk_id. That equality is the
                        # end-to-end proof the upload was lossless.
                        os.path.basename(p): (
                            ios_digest(rows, side)
                            if (is_ios_db(p) or is_cloud(p))
                            else file_sha256(p))
                        for (p, side) in ((args.logA, "a"), (args.logB, "b"))}),
                "stations": [{"label": l, "start": hms(a), "end": hms(b)}
                             for (l, a, b) in stations]}
        with open(args.json, "w") as f:
            json.dump({"meta": meta, "stations": rows}, f, indent=1)
        print(f"\nwrote {args.json} (walk_id {meta['manifest']['walk_id']}, "
              f"pair {args.pair or 'UNSET — ingest cannot verify identity'})")
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
    print("  * venue V thresholds PROVISIONAL (0.60/0.30 uncalibrated — "
          "co-located phones measured V=0.48 on 2026-07-18)")
    print("  * fingerprints union ALL in-window scans (best RSSI per BSSID), stale APs rejected")
    print("  * GPS Δm from per-phone MEDIAN fix; worst accuracy per phone is in the CSV/JSON")


if __name__ == "__main__":
    main()
