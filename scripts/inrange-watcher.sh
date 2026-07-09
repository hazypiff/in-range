#!/bin/bash
# Safe persistent watcher for In Range Flutter setup.
# Checks ONLY file sizes, processes, and logs — never calls flutter.
# Writes one-line status to /tmp/inrange_progress.txt every 30s.
# Survives agent drops (run with nohup or start-persistent-monitors.sh).
#
# Usage (background, survives drops):
#   nohup bash /home/hazypiff/in-range/scripts/inrange-watcher.sh > /tmp/inrange_watcher.log 2>&1 &
#
# To view live:
#   watch -n 5 cat /tmp/inrange_progress.txt
# or
#   tail -f /tmp/inrange_progress.txt

PROGRESS_FILE="/tmp/inrange_progress.txt"
ARIA_LOG="/tmp/aria_flutter_download.log"
TAR_PATH="$HOME/snap/flutter/common/latest_stable.tar.xz"
FLUTTER_DIR="$HOME/snap/flutter/common/flutter"
PROJECT_DIR="/home/hazypiff/in-range"

echo "InRange watcher started at $(date)" >> /tmp/inrange_watcher.log

while true; do
  ts=$(date '+%H:%M:%S')

  # Tar progress
  if [ -f "$TAR_PATH" ]; then
    size=$(du -h "$TAR_PATH" 2>/dev/null | cut -f1)
    aria_alive=$(pgrep -c '[a]ria2c' 2>/dev/null || echo 0)
    tar_line="tar:${size} aria:${aria_alive}"
  else
    tar_line="tar:done"
  fi

  # SDK extracted?
  if [ -d "$FLUTTER_DIR/bin" ] && [ -x "$FLUTTER_DIR/bin/flutter" ]; then
    sdk_line="sdk:ready"
  else
    sdk_line="sdk:downloading"
  fi

  # Project
  if [ -f "$PROJECT_DIR/pubspec.lock" ]; then
    proj_line="proj:ready"
  else
    proj_line="proj:waiting"
  fi

  # Devices (quick adb, no flutter)
  dev_count=$(adb devices 2>/dev/null | grep -c 'device$' || echo 0)
  dev_line="devs:${dev_count}"

  # Last aria status (if any)
  last_aria=$(tail -1 "$ARIA_LOG" 2>/dev/null | grep -o 'DL:[^ ]*' || echo "")

  status="$ts | $tar_line | $sdk_line | $proj_line | $dev_line | $last_aria"
  echo "$status" > "$PROGRESS_FILE"

  sleep 30
done
