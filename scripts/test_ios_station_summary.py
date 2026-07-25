#!/usr/bin/env python3
"""Tests for ios_station_summary.py."""

import os
import sqlite3
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ios_station_summary as station  # noqa: E402


def make_db(rows):
    handle, path = tempfile.mkstemp(suffix=".db")
    os.close(handle)
    with sqlite3.connect(path) as con:
        con.execute(
            "CREATE TABLE rssi_log ("
            "id INTEGER PRIMARY KEY AUTOINCREMENT, "
            "at_ms INTEGER NOT NULL, correlation_id TEXT NOT NULL, "
            "rssi INTEGER NOT NULL, power TEXT NOT NULL)"
        )
        con.executemany(
            "INSERT INTO rssi_log "
            "(at_ms, correlation_id, rssi, power) VALUES (?, ?, ?, ?)",
            rows,
        )
    return path


class StationSummaryTest(unittest.TestCase):
    def setUp(self):
        self.start = station.station_start_ms("2026-07-25", "10:00:00")

    def row(self, offset_s, rssi=-70, power="H", corr="peer-a"):
        return (self.start + offset_s * 1000, corr, rssi, power)

    def test_absolute_split_does_not_follow_first_callback(self):
        # The first callback arrives during the hand half. A first-row anchor
        # would incorrectly call it pocket; the operator clock cannot.
        rows = [
            (self.start + 56_000, -80, "H", "peer-a"),
        ]
        got = station.summarize(
            rows, self.start, list(station.DEFAULT_WINDOWS), trim_s=10
        )
        self.assertEqual(got[0]["high_n"], 0)
        self.assertEqual(got[1]["high_n"], 1)
        self.assertTrue(got[1]["thin"])

    def test_each_half_gets_its_own_ten_second_trim(self):
        rows = [
            (self.start + 2_000, -50, "H", "peer-a"),   # pocket trim
            (self.start + 12_000, -70, "H", "peer-a"),
            (self.start + 44_000, -72, "H", "peer-a"),
            (self.start + 46_000, -55, "H", "peer-a"),  # hand trim
            (self.start + 56_000, -80, "H", "peer-a"),
            (self.start + 89_000, -82, "H", "peer-a"),
        ]
        got = station.summarize(
            rows, self.start, list(station.DEFAULT_WINDOWS), trim_s=10
        )
        self.assertEqual([part["high_n"] for part in got], [2, 2])
        self.assertEqual(got[0]["median"], -71)
        self.assertEqual(got[1]["median"], -81)

    def test_single_sample_quartiles_do_not_crash(self):
        rows = [(self.start + 20_000, -77, "H", "peer-a")]
        got = station.summarize(
            rows, self.start, list(station.DEFAULT_WINDOWS), trim_s=10
        )
        self.assertEqual(
            (got[0]["p25"], got[0]["median"], got[0]["p75"]),
            (-77, -77, -77),
        )

    def test_database_query_uses_exact_window_and_optional_peer(self):
        path = make_db([
            self.row(-1),
            self.row(12, corr="wanted-123"),
            self.row(13, corr="other-456"),
            self.row(91),
        ])
        self.addCleanup(os.unlink, path)
        rows = station.load_rows(
            path, self.start, self.start + 90_000, corr_prefix="wanted"
        )
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0][3], "wanted-123")

    def test_custom_smoke_window(self):
        self.assertEqual(
            station.parse_windows(["smoke:0:60"]), [("smoke", 0, 60)]
        )

    def test_cli_reports_the_recorded_station(self):
        path = make_db([
            self.row(20, rssi=-71),
            self.row(60, rssi=-81),
        ])
        self.addCleanup(os.unlink, path)
        script = os.path.join(
            os.path.dirname(os.path.abspath(__file__)),
            "ios_station_summary.py",
        )
        result = subprocess.run(
            [
                sys.executable, script, path,
                "--date", "2026-07-25", "--start", "10:00:00",
            ],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("pocket", result.stdout)
        self.assertIn("hand", result.stdout)
        self.assertEqual(result.stdout.count("n=1"), 4)  # row + warning per half


if __name__ == "__main__":
    unittest.main(verbosity=2)
