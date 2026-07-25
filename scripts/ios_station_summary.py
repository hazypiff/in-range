#!/usr/bin/env python3
"""Summarize exact wall-clock windows in an iPhone calibration RSSI database.

The default protocol is a 90-second station:

  pocket: physical +0..45 s, measured +10..45 s
  hand:   physical +45..90 s, measured +55..90 s

The first 10 seconds of each half are trimmed, exactly as extract_walk.py
--trim 10 will treat two 45-second station records. Crucially, the split is
anchored to the operator's recorded start rather than the first database row.
"""

import argparse
import re
import sqlite3

import extract_walk as ew


DEFAULT_WINDOWS = (("pocket", 0, 45), ("hand", 45, 45))
WINDOW_RE = re.compile(r"^(?P<label>[^:]+):(?P<offset>\d+):(?P<duration>\d+)$")


def parse_windows(specs):
    if not specs:
        return list(DEFAULT_WINDOWS)
    windows = []
    for spec in specs:
        match = WINDOW_RE.match(spec)
        if not match:
            raise SystemExit(
                f"bad --window {spec!r}; want LABEL:OFFSET_SECONDS:DURATION_SECONDS"
            )
        duration = int(match.group("duration"))
        if duration <= 0:
            raise SystemExit(f"bad --window {spec!r}; duration must be positive")
        windows.append(
            (match.group("label"), int(match.group("offset")), duration)
        )
    return windows


def station_start_ms(date, start):
    """Use the same local-midnight conversion as final extraction."""
    return round((ew.local_midnight_epoch(date) + ew.ts(start)) * 1000)


def load_rows(path, lo_ms, hi_ms, corr_prefix=None):
    sql = (
        "SELECT at_ms, rssi, power, correlation_id FROM rssi_log "
        "WHERE rssi < 0 AND at_ms >= ? AND at_ms < ?"
    )
    params = [lo_ms, hi_ms]
    if corr_prefix:
        sql += " AND correlation_id LIKE ?"
        params.append(f"{corr_prefix}%")
    sql += " ORDER BY at_ms"
    with sqlite3.connect(path) as con:
        return con.execute(sql, params).fetchall()


def summarize(rows, start_ms, windows, trim_s):
    summaries = []
    for label, offset_s, duration_s in windows:
        if trim_s >= duration_s:
            raise SystemExit(
                f"--trim {trim_s} leaves no samples in {label!r} "
                f"({duration_s} second window)"
            )
        physical_lo = start_ms + offset_s * 1000
        measured_lo = physical_lo + trim_s * 1000
        hi = physical_lo + duration_s * 1000
        usable = [row for row in rows if measured_lo <= row[0] < hi]
        high = [int(row[1]) for row in usable
                if str(row[2]).upper().startswith("H")]
        med_n = sum(1 for row in usable
                    if str(row[2]).upper().startswith("M"))
        summary = {
            "label": label,
            "offset_s": offset_s,
            "duration_s": duration_s,
            "trim_s": trim_s,
            "high_n": len(high),
            "med_n": med_n,
            "rate": len(high) / (duration_s - trim_s),
            "thin": 0 < len(high) < ew.MIN_HIGH_N,
        }
        if high:
            p25, median, p75 = ew.quart(high)
            summary.update(p25=p25, median=median, p75=p75)
        summaries.append(summary)
    return summaries


def format_summary(summary):
    lo = summary["offset_s"] + summary["trim_s"]
    hi = summary["offset_s"] + summary["duration_s"]
    interval = f"+{lo}..+{hi}s"
    if summary["high_n"] == 0:
        measurement = "SILENT"
    else:
        measurement = (
            f"median {summary['median']:.0f} dBm  "
            f"IQR {summary['p25']:.0f}..{summary['p75']:.0f}  "
            f"n={summary['high_n']}"
        )
    quality = "  THIN!" if summary["thin"] else ""
    return (
        f"  {summary['label']:<10} {interval:<11} {measurement}"
        f"  med_n={summary['med_n']}  rate={summary['rate']:.2f}/s{quality}"
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("db", help="pulled Documents/in_range_local.db")
    parser.add_argument("--date", required=True,
                        help="local station date, YYYY-MM-DD")
    parser.add_argument("--start", required=True,
                        help="operator-recorded Beacon-on time, HH:MM:SS")
    parser.add_argument(
        "--window", action="append",
        help="window LABEL:OFFSET_SECONDS:DURATION_SECONDS; repeat as needed",
    )
    parser.add_argument(
        "--trim", type=int, default=10,
        help="seconds dropped from the beginning of each window (default: 10)",
    )
    parser.add_argument("--corr-prefix",
                        help="optional peer correlation-id prefix")
    args = parser.parse_args()

    if args.trim < 0:
        parser.error("--trim cannot be negative")
    windows = parse_windows(args.window)
    start_ms = station_start_ms(args.date, args.start)
    end_ms = start_ms + max(offset + duration
                            for _, offset, duration in windows) * 1000
    rows = load_rows(args.db, start_ms, end_ms, args.corr_prefix)
    summaries = summarize(rows, start_ms, windows, args.trim)

    print(
        f"station: {args.date} {args.start} local | "
        f"{len(rows)} valid RSSI row(s) in physical window"
    )
    for summary in summaries:
        print(format_summary(summary))

    thin = [summary for summary in summaries if summary["thin"]]
    if thin:
        labels = ", ".join(
            f"{summary['label']} n={summary['high_n']}" for summary in thin
        )
        print(
            f"WARNING: {labels}; below {ew.MIN_HIGH_N} high-power samples. "
            "That median is not trainable; repeat this distance once while "
            "the geometry is still set."
        )
    if any(summary["high_n"] == 0 for summary in summaries):
        print(
            "NOTE: SILENT has no median to corrupt training. Repeat once if "
            "silence is unexpected at this distance; at the far ceiling it "
            "is a valid observation."
        )


if __name__ == "__main__":
    main()
