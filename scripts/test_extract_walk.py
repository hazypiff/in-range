#!/usr/bin/env python3
"""Tests for extract_walk.py — run: python3 scripts/test_extract_walk.py"""
import gzip
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import extract_walk as ew  # noqa: E402


def advert(t, rssi=-70, pw="H", corr="AAAA1111"):
    return f"07-17 {t}  1000  2000 I flutter : Advert corr={corr} rssi={rssi} pw={pw}\n"


def wifiap(t, seq, bssid, rssi=-60, band=5, age=2):
    return (f"07-17 {t}  1000  2000 I flutter : WifiAp seq={seq} bssid={bssid} "
            f"rssi={rssi} band={band} age={age}s\n")


def gpsfix(t, lat, lon, acc):
    return f"07-17 {t}  1000  2000 I flutter : GpsFix lat={lat} lon={lon} acc={acc}m\n"


def write_log(lines, gz=False):
    fd, path = tempfile.mkstemp(suffix=".log.gz" if gz else ".log")
    os.close(fd)
    if gz:
        with gzip.open(path, "wt") as f:
            f.writelines(lines)
    else:
        with open(path, "w") as f:
            f.writelines(lines)
    return path


class StationSpecTest(unittest.TestCase):
    def test_duration_and_end_forms(self):
        s = ew.parse_stations(["35ft@14:05:00+90", "65ft@14:12:30-14:14:00"])
        self.assertEqual(s[0], ("35ft", ew.ts("14:05:00"), ew.ts("14:05:00") + 90))
        self.assertEqual(s[1][1], ew.ts("14:12:30"))
        self.assertEqual(s[1][2] - s[1][1], 90)

    def test_gaps_are_preserved(self):
        s = ew.parse_stations(["a@10:00:00+60", "b@10:10:00+60"])
        self.assertEqual(s[1][1] - s[0][2], 540)  # 9-min gap, not contiguous

    def test_midnight_rollover_stations(self):
        s = ew.parse_stations(["a@23:58:00+60", "b@00:03:00+60"])
        self.assertGreater(s[1][1], s[0][2])  # b unwrapped past midnight
        self.assertEqual(s[1][1] - s[0][1], 5 * 60)

    def test_end_form_across_midnight(self):
        s = ew.parse_stations(["a@23:59:30-00:00:30"])
        self.assertEqual(s[0][2] - s[0][1], 60)

    def test_bad_spec_rejected(self):
        with self.assertRaises(SystemExit):
            ew.parse_stations(["nonsense"])


class ExtractionTest(unittest.TestCase):
    def data(self, lines, offset=0.0):
        path = write_log(lines)
        self.addCleanup(os.remove, path)
        return ew.parse_log(path, offset)

    def test_gap_excludes_between_station_adverts(self):
        d = self.data([
            advert("10:00:10.000", -70),
            advert("10:03:00.000", -50),   # in the gap — must not count anywhere
            advert("10:10:10.000", -90),
        ])
        stations = ew.parse_stations(["near@10:00:00+60", "far@10:10:00+60"])
        rows = ew.extract(d, d, stations, trim=0)
        self.assertEqual(rows[0]["a"]["high_n"], 1)
        self.assertEqual(rows[0]["a"]["high_med"], -70)
        self.assertEqual(rows[1]["a"]["high_n"], 1)
        self.assertEqual(rows[1]["a"]["high_med"], -90)

    def test_trim_drops_walkin(self):
        d = self.data([advert("10:00:05.000", -40), advert("10:00:30.000", -70)])
        rows = ew.extract(d, d, ew.parse_stations(["s@10:00:00+60"]), trim=20)
        self.assertEqual(rows[0]["a"]["high_n"], 1)
        self.assertEqual(rows[0]["a"]["high_med"], -70)

    def test_stale_aps_rejected(self):
        d = self.data([
            wifiap("10:00:10.000", 1, "aa:aa", rssi=-50, age=2),
            wifiap("10:00:10.100", 1, "bb:bb", rssi=-40, age=300),  # stale
        ])
        rows = ew.extract(d, d, ew.parse_stations(["s@10:00:00+60"]), trim=0,
                          max_ap_age=60)
        self.assertEqual(rows[0]["a"]["fp"], {"aa:aa": -50})
        self.assertEqual(rows[0]["a"]["stale_dropped"], 1)

    def test_multiple_scans_unioned_best_rssi(self):
        d = self.data([
            wifiap("10:00:10.000", 1, "aa:aa", rssi=-65),
            wifiap("10:00:40.000", 2, "aa:aa", rssi=-55),   # better later reading
            wifiap("10:00:40.100", 2, "bb:bb", rssi=-60),   # only in scan 2
        ])
        rows = ew.extract(d, d, ew.parse_stations(["s@10:00:00+60"]), trim=0)
        self.assertEqual(rows[0]["a"]["fp"], {"aa:aa": -55, "bb:bb": -60})
        self.assertEqual(rows[0]["a"]["scan_n"], 2)

    def test_multiple_gps_fixes_aggregated(self):
        d = self.data([
            gpsfix("10:00:10.000", "40.100000", "-74.100000", 5),
            gpsfix("10:00:30.000", "40.100010", "-74.100000", 30),
            gpsfix("10:00:50.000", "40.100020", "-74.100000", 8),
        ])
        rows = ew.extract(d, d, ew.parse_stations(["s@10:00:00+60"]), trim=0)
        a = rows[0]["a"]
        self.assertEqual(a["fix_n"], 3)
        self.assertEqual(a["gps_med"], (40.100010, -74.100000))  # median, not last
        self.assertEqual(a["gps_worst_acc"], 30)

    def test_midnight_rollover_log(self):
        d = self.data([advert("23:59:59.000", -70), advert("00:00:01.000", -72)])
        rows = ew.extract(d, d, ew.parse_stations(["s@23:59:50+30"]), trim=0)
        self.assertEqual(rows[0]["a"]["high_n"], 2)  # both sides of midnight

    def test_clock_offset_shifts_log_times(self):
        # device clock 10 s behind host: offset +10 pulls the advert into window
        d = self.data([advert("09:59:55.000", -70)], offset=10.0)
        rows = ew.extract(d, d, ew.parse_stations(["s@10:00:00+60"]), trim=0)
        self.assertEqual(rows[0]["a"]["high_n"], 1)

    def test_gzip_log_readable(self):
        path = write_log([advert("10:00:10.000", -70)], gz=True)
        self.addCleanup(os.remove, path)
        d = ew.parse_log(path)
        self.assertEqual(len(d["adverts"]), 1)

    def test_manifest_content_hash_identity(self):
        a = write_log([advert("10:00:10.000", -70)])
        b = write_log([advert("10:00:11.000", -72)])
        self.addCleanup(os.remove, a)
        self.addCleanup(os.remove, b)
        m1 = ew.build_manifest(a, b, "s9-s9", freeze="tag1")
        self.assertEqual(m1["version"], "walk_manifest.v1")
        self.assertEqual(m1["pair_id"], "s9-s9")
        self.assertEqual(len(m1["walk_id"]), 16)
        # content-derived: same archives -> same id, regardless of arg order
        m2 = ew.build_manifest(b, a, "s9-s9")
        self.assertEqual(m1["walk_id"], m2["walk_id"])
        # different content -> different id
        c = write_log([advert("10:00:12.000", -80)])
        self.addCleanup(os.remove, c)
        self.assertNotEqual(m1["walk_id"], ew.build_manifest(a, c, "s9-s9")["walk_id"])

    def test_raw_observations_preserved(self):
        d = self.data([
            advert("10:00:10.000", -70),
            wifiap("10:00:20.000", 1, "aa:aa", rssi=-50, age=300),  # stale but raw-kept
            gpsfix("10:00:30.000", "40.1", "-74.1", 5),
        ])
        rows = ew.extract(d, d, ew.parse_stations(["s@10:00:00+60"]), trim=0)
        raw = rows[0]["a"]["raw"]
        self.assertEqual(len(raw["adverts_high"]), 1)
        self.assertEqual(len(raw["wifi_scans"][0]["aps"]), 1)  # stale AP still in raw
        self.assertEqual(len(raw["gps_fixes"]), 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
