#!/bin/bash
# Start all persistent monitors in background (survives agent drops)

PROJECT_DIR="/home/hazypiff/in-range"
LOG_DIR="/tmp"

echo "Starting persistent monitors for In Range..."

# Download monitor (if not running)
if ! pgrep -f "flutter_download_monitor" > /dev/null; then
  nohup bash -c '
    while true; do
      echo "$(date +%T) | Tar: $(du -h ~/snap/flutter/common/latest_stable.tar.xz 2>/dev/null | cut -f1 || echo N/A) | Curls: $(ps aux | grep -c "[c]url.*flutter_linux")"
      sleep 20
    done
  ' > "$LOG_DIR/flutter_download_monitor.log" 2>&1 &
  echo "Started download monitor (PID $!)"
else
  echo "Download monitor already running"
fi

# Status updater (writes to a single status file every 30s)
if ! pgrep -f "inrange_status_updater" > /dev/null; then
  nohup bash -c '
    while true; do
      {
        echo "=== In Range Status - $(date) ==="
        echo "Flutter: $(/snap/bin/flutter --version 2>/dev/null | head -1 || echo "not ready")"
        echo "Tar: $(du -h ~/snap/flutter/common/latest_stable.tar.xz 2>/dev/null | cut -f1 || echo N/A)"
        echo "Curls: $(ps aux | grep -c "[c]url.*flutter_linux")"
        echo "pubspec.lock: $(ls -l '"$PROJECT_DIR"'/pubspec.lock 2>/dev/null && echo yes || echo no)"
        echo "Devices: $(adb devices 2>/dev/null | grep -c device)"
        echo ""
      } > "$LOG_DIR/inrange_live_status.txt"
      sleep 30
    done
  ' > /dev/null 2>&1 &
  echo "Started status updater (PID $!)"
else
  echo "Status updater already running"
fi

echo ""
echo "Logs:"
echo "  Download: tail -f $LOG_DIR/flutter_download_monitor.log"
echo "  Live status: cat $LOG_DIR/inrange_live_status.txt"
echo "  Pub get: tail -f $LOG_DIR/flutter_pub_get.log"
echo ""
echo "Interactive monitor: $PROJECT_DIR/scripts/monitor.sh"
echo "To stop all: pkill -f 'flutter_download_monitor|inrange_status_updater'"
