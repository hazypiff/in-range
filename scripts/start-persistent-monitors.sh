#!/bin/bash
# Starts background monitors that survive agent/session drops.
# Run this once: bash scripts/start-persistent-monitors.sh

LOG_DIR="/tmp"
PROJECT="/home/hazypiff/in-range"

echo "Starting persistent In Range monitors..."

# 1. Download progress logger (every 20s) — tracks aria2c, does NOT touch flutter
if ! pgrep -f "inrange-download-monitor" > /dev/null 2>&1; then
  nohup bash -c '
    while true; do
      SIZE=$(du -h ~/snap/flutter/common/latest_stable.tar.xz 2>/dev/null | cut -f1 || echo "N/A")
      ARIA=$(pgrep -c "[a]ria2c" 2>/dev/null || echo 0)
      SDK_READY=$([ -d "$HOME/snap/flutter/common/flutter" ] && echo "yes" || echo "no")
      echo "$(date +%H:%M:%S) | Tar: $SIZE | aria2c alive: $ARIA | SDK extracted: $SDK_READY" >> "$LOG_DIR/flutter_download_monitor.log"
      sleep 20
    done
  ' > /dev/null 2>&1 &
  disown
  echo "  ✓ Download monitor started"
else
  echo "  • Download monitor already running"
fi

# 2. Live status file (updated every 30s) — does NOT call flutter --version
if ! pgrep -f "inrange-live-status" > /dev/null 2>&1; then
  nohup bash -c '
    while true; do
      {
        echo "=== In Range Status ==="
        echo "Updated: $(date)"
        echo ""
        echo "Flutter SDK:"
        if [ -d "$HOME/snap/flutter/common/flutter" ]; then
          echo "  Extracted: yes"
        else
          echo "  Extracted: no (still downloading or not extracted)"
        fi
        echo ""
        echo "Download:"
        du -h ~/snap/flutter/common/latest_stable.tar.xz 2>/dev/null || echo "  N/A"
        echo "aria2c alive: $(pgrep -c "[a]ria2c" 2>/dev/null || echo 0)"
        echo ""
        echo "Project:"
        ls -l "$PROJECT/pubspec.lock" 2>/dev/null && echo "pubspec.lock: yes" || echo "pubspec.lock: no"
        echo ""
        echo "Devices:"
        adb devices 2>/dev/null | grep device | wc -l
      } > "$LOG_DIR/inrange_live_status.txt" 2>/dev/null
      sleep 30
    done
  ' > /dev/null 2>&1 &
  disown
  echo "  ✓ Live status updater started"
else
  echo "  • Live status updater already running"
fi

echo ""
echo "Quick commands (work even if agent drops):"
echo "  cat $LOG_DIR/inrange_live_status.txt"
echo "  tail -f $LOG_DIR/flutter_pub_get.log"
echo "  tail -f $LOG_DIR/flutter_download_monitor.log"
echo "  bash $PROJECT/scripts/monitor.sh"
echo "  bash $PROJECT/scripts/status.sh"
