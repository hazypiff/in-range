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


def write_ios_db(rows):
    """rows: [(at_ms, correlation_id, rssi, power)] -> temp sqlite path."""
    import sqlite3
    fd, path = tempfile.mkstemp(suffix=".db")
    os.close(fd)
    con = sqlite3.connect(path)
    con.execute("CREATE TABLE rssi_log (id INTEGER PRIMARY KEY AUTOINCREMENT, "
                "at_ms INTEGER NOT NULL, correlation_id TEXT NOT NULL, "
                "rssi INTEGER NOT NULL, power TEXT NOT NULL)")
    con.executemany("INSERT INTO rssi_log (at_ms, correlation_id, rssi, power) "
                    "VALUES (?,?,?,?)", rows)
    con.commit()
    con.close()
    return path


def at(date_str, hhmmss, ms=0):
    """Local wall-clock on `date_str` -> epoch ms, matching the extractor's
    host-local convention."""
    return int((ew.local_midnight_epoch(date_str) + ew.ts(hhmmss)) * 1000) + ms


class IosDbTest(unittest.TestCase):
    DATE = "2026-07-25"

    def test_epoch_maps_to_seconds_since_local_midnight(self):
        p = write_ios_db([(at(self.DATE, "10:00:30"), "abcdef0123", -70, "H")])
        self.addCleanup(os.remove, p)
        d = ew.parse_ios_db(p, date=self.DATE)
        self.assertEqual(len(d["adverts"]), 1)
        t, corr, rssi, pw = d["adverts"][0]
        self.assertAlmostEqual(t, ew.ts("10:00:30"), places=3)
        self.assertEqual((corr, rssi, pw), ("abcdef01", -70, "H"))

    def test_ble_only_no_wifi_or_gps(self):
        p = write_ios_db([(at(self.DATE, "10:00:30"), "aa", -70, "H")])
        self.addCleanup(os.remove, p)
        d = ew.parse_ios_db(p, date=self.DATE)
        self.assertEqual(d["wifi"], [])
        self.assertEqual(d["gps"], [])

    def test_venue_and_gps_are_none_not_zero(self):
        """A None feature is SKIPPED by train.py; a 0.0 would be a lie."""
        p = write_ios_db([(at(self.DATE, "10:00:30"), "aa", -70, "H")])
        self.addCleanup(os.remove, p)
        ios = ew.parse_ios_db(p, date=self.DATE)
        rows = ew.extract(ios, ios, ew.parse_stations(["10ft@10:00:00+60"]), trim=0)
        self.assertIsNone(rows[0]["venue"])
        self.assertIsNone(rows[0]["gps_delta_m"])

    def test_stale_rows_from_another_day_are_excluded(self):
        """rssi_log is append-only across sessions — an overnight soak must not
        drag the walk's anchor onto the wrong day."""
        p = write_ios_db(
            [(at("2026-07-24", "22:00:00", i), "aa", -95, "H") for i in range(50)]
            + [(at(self.DATE, "10:00:30", i), "aa", -70, "H") for i in range(5)])
        self.addCleanup(os.remove, p)
        d = ew.parse_ios_db(p, date=self.DATE)
        rows = ew.extract(d, d, ew.parse_stations(["10ft@10:00:00+60"]), trim=0)
        # Only the 5 walk-day samples land in the window; the 50 soak rows sit
        # ~12 h earlier and are excluded by the window, not by luck.
        self.assertEqual(rows[0]["a"]["high_n"], 5)
        self.assertEqual(rows[0]["a"]["high_med"], -70)

    def test_date_inference_beats_a_bigger_soak_on_another_day(self):
        """Regression: densest-day inference picked the SOAK, not the walk.

        A 90 s-per-station walk is easily out-numbered by an overnight soak, so
        row count is the wrong signal — every station then reports SILENT and
        the walk looks like a hardware failure. Score by in-window coverage.
        """
        stations = ew.parse_stations(["10ft@10:00:00+90"])
        walk = [(at(self.DATE, "10:00:%02d" % (i % 60), i), "aa", -60, "H")
                for i in range(60)]
        soak = [(at("2026-07-24", "22:00:00", i * 1000), "aa", -93, "H")
                for i in range(500)]
        p = write_ios_db(walk + soak)
        self.addCleanup(os.remove, p)
        self.assertEqual(len(soak), 500)          # soak really is the bigger day
        d = ew.parse_ios_db(p, stations=stations)
        self.assertEqual(d["ios"]["date"], self.DATE)
        rows = ew.extract(d, d, stations, trim=0)
        self.assertEqual(rows[0]["a"]["high_n"], 60)

    def test_date_inference_picks_densest_day_not_latest_row(self):
        p = write_ios_db(
            [(at(self.DATE, "10:00:30", i), "aa", -70, "H") for i in range(20)]
            + [(at("2026-07-26", "09:00:00", i), "aa", -50, "H") for i in range(3)])
        self.addCleanup(os.remove, p)
        self.assertEqual(ew.parse_ios_db(p)["ios"]["date"], self.DATE)

    def test_corr_prefix_filters_other_peers(self):
        p = write_ios_db([(at(self.DATE, "10:00:30"), "aaaaaaaa11", -70, "H"),
                          (at(self.DATE, "10:00:31"), "bbbbbbbb22", -60, "H")])
        self.addCleanup(os.remove, p)
        d = ew.parse_ios_db(p, date=self.DATE, corr_prefix="aaaaaaaa")
        self.assertEqual([a[2] for a in d["adverts"]], [-70])

    def test_power_medium_preserved(self):
        p = write_ios_db([(at(self.DATE, "10:00:30"), "aa", -70, "M")])
        self.addCleanup(os.remove, p)
        d = ew.parse_ios_db(p, date=self.DATE)
        self.assertEqual(d["adverts"][0][3], "M")

    def test_offset_shifts_times(self):
        p = write_ios_db([(at(self.DATE, "10:00:30"), "aa", -70, "H")])
        self.addCleanup(os.remove, p)
        d = ew.parse_ios_db(p, offset=2.5, date=self.DATE)
        self.assertAlmostEqual(d["adverts"][0][0], ew.ts("10:00:30") + 2.5, places=3)

    def test_digest_survives_rows_appended_after_the_walk(self):
        """The re-pull hazard: a growing .db must not mint a new walk_id, or
        one walk ingests twice and fakes the >=3-walk promotion gate."""
        walk = [(at(self.DATE, "10:00:30", i), "aa", -70, "H") for i in range(5)]
        stations = ew.parse_stations(["10ft@10:00:00+60"])

        p1 = write_ios_db(walk)
        self.addCleanup(os.remove, p1)
        d1 = ew.parse_ios_db(p1, date=self.DATE)
        r1 = ew.extract(d1, d1, stations, trim=0)

        # same walk, DB re-pulled later with a day of extra rows in it
        p2 = write_ios_db(
            walk + [(at(self.DATE, "18:00:00", i), "aa", -88, "H") for i in range(400)])
        self.addCleanup(os.remove, p2)
        d2 = ew.parse_ios_db(p2, date=self.DATE)
        r2 = ew.extract(d2, d2, stations, trim=0)

        self.assertEqual(ew.ios_digest(r1, "a"), ew.ios_digest(r2, "a"))

    def test_digest_changes_when_the_walk_data_changes(self):
        stations = ew.parse_stations(["10ft@10:00:00+60"])
        a = write_ios_db([(at(self.DATE, "10:00:30"), "aa", -70, "H")])
        b = write_ios_db([(at(self.DATE, "10:00:30"), "aa", -71, "H")])
        self.addCleanup(os.remove, a)
        self.addCleanup(os.remove, b)
        da = ew.parse_ios_db(a, date=self.DATE)
        db = ew.parse_ios_db(b, date=self.DATE)
        self.assertNotEqual(
            ew.ios_digest(ew.extract(da, da, stations, trim=0), "a"),
            ew.ios_digest(ew.extract(db, db, stations, trim=0), "a"))

    def test_empty_table_is_not_a_crash(self):
        p = write_ios_db([])
        self.addCleanup(os.remove, p)
        d = ew.parse_ios_db(p, date=self.DATE)
        self.assertEqual(d["adverts"], [])
        self.assertEqual(d["ios"]["n_total"], 0)

    def test_is_ios_db_detection(self):
        for p in ("in_range_local.db", "x.sqlite", "X.SQLITE3"):
            self.assertTrue(ew.is_ios_db(p), p)
        for p in ("walk.threadtime.log.gz", "walk.log"):
            self.assertFalse(ew.is_ios_db(p), p)




def fake_cloud(rows, *, drop=()):
    """Patch urlopen so cloud_rows() sees `rows` as PostgREST JSON.

    rows: [(device_seq, at_ms, correlation_id, rssi, power)]; `drop` removes
    those device_seqs to simulate samples the upload never delivered.
    """
    import contextlib
    import io as _io
    import json as _json
    import urllib.request

    payload = [{"device_seq": s, "at_ms": a, "correlation_id": c,
                "rssi": r, "power": p}
               for (s, a, c, r, p) in rows if s not in drop]

    @contextlib.contextmanager
    def _patch():
        real = urllib.request.urlopen
        served = {"n": 0}

        def fake(req, *a, **kw):
            # One page is enough; cloud_rows stops when a page is short.
            served["n"] += 1
            body = _json.dumps(payload if served["n"] == 1 else []).encode()
            return contextlib.closing(_io.BytesIO(body))
        urllib.request.urlopen = fake
        try:
            yield
        finally:
            urllib.request.urlopen = real
    return _patch()


class CloudExtractionTest(unittest.TestCase):
    DATE = "2026-07-25"

    def _rows(self):
        # 40 samples inside one station window, contiguous device_seq.
        return [(i + 1, at(self.DATE, "10:00:%02d" % (20 + i)), "abcdef0123",
                 -60, "H") for i in range(40)]

    def setUp(self):
        os.environ["SUPABASE_URL"] = "https://example.invalid"
        os.environ["SUPABASE_SERVICE_ROLE_KEY"] = "test-key"

    def test_cloud_and_usb_produce_the_same_walk_id(self):
        """The property the whole cloud path exists to be trusted on.

        The digest covers in-window SAMPLES, not the source, so the same walk
        pulled over USB and fetched from the server must agree exactly. If it
        ever does not, the upload dropped or reordered rows and the USB pull is
        the ground truth that proves it.
        """
        rows = self._rows()
        stations = ew.parse_stations(["10ft@10:00:00+90"])

        db = write_ios_db([(a, c, r, p) for (_s, a, c, r, p) in rows])
        self.addCleanup(os.remove, db)
        usb = ew.parse_ios_db(db, date=self.DATE, stations=stations)

        with fake_cloud(rows):
            cloud = ew.parse_ios_rows(
                ew.cloud_rows("cloud:dev-a"), date=self.DATE, stations=stations)

        self.assertEqual(usb["adverts"], cloud["adverts"])
        empty = {"adverts": [], "wifi": [], "gps": []}
        usb_rows = ew.extract(usb, empty, stations, 0, 60)
        cloud_rows_ = ew.extract(cloud, empty, stations, 0, 60)
        self.assertEqual(ew.ios_digest(usb_rows, "a"),
                         ew.ios_digest(cloud_rows_, "a"))

    def test_a_device_seq_gap_is_fatal(self):
        """A hole means dropped rows, and RSSI values alone cannot reveal it:
        'the peer went quiet' and 'the upload lost samples' look identical."""
        with fake_cloud(self._rows(), drop=(10, 11, 12)):
            with self.assertRaises(SystemExit) as cm:
                ew.cloud_rows("cloud:dev-a")
        self.assertIn("device_seq", str(cm.exception))

    def test_gaps_can_be_accepted_explicitly(self):
        with fake_cloud(self._rows(), drop=(10,)):
            got = ew.cloud_rows("cloud:dev-a", allow_gaps=True)
        self.assertEqual(len(got), 39)

    def test_empty_result_explains_the_usual_cause(self):
        with fake_cloud([]):
            with self.assertRaises(SystemExit) as cm:
                ew.cloud_rows("cloud:dev-a")
        self.assertIn("foreground", str(cm.exception))

    def test_missing_credentials_fail_loudly(self):
        os.environ.pop("SUPABASE_SERVICE_ROLE_KEY")
        os.environ.pop("SUPABASE_KEY", None)
        with self.assertRaises(SystemExit) as cm:
            ew.cloud_rows("cloud:dev-a")
        self.assertIn("SUPABASE", str(cm.exception))

    def test_cloud_spec_detection(self):
        self.assertTrue(ew.is_cloud("cloud:abc"))
        self.assertFalse(ew.is_cloud("walk.threadtime.log.gz"))
        self.assertFalse(ew.is_cloud("iphone.db"))

if __name__ == "__main__":
    unittest.main(verbosity=2)
