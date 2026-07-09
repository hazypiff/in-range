#!/bin/bash
# In Range - Live Monitor
# Run this anytime: bash scripts/monitor.sh
# It survives agent drops because it just reads files.

PROJECT="/home/hazypiff/in-range"
LOG_DIR="/tmp"

while true; do
  clear
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║           IN RANGE - LIVE PROJECT MONITOR                  ║"
  echo "╚════════════════════════════════════════════════════════════╝"
  echo "Time: $(date)"
  echo ""

  echo "▶ Flutter SDK"
  # DO NOT call `flutter --version` — it triggers a fresh 1.4GB download and
  # interrupts any in-progress aria2c download. Just check for the extracted SDK dir.
  if [ -d "$HOME/snap/flutter/common/flutter" ]; then
    echo "  SDK extracted: ✅ $HOME/snap/flutter/common/flutter"
  else
    echo "  SDK extracted: ❌ (still downloading or not yet extracted)"
  fi
  echo ""

  echo "▶ SDK Download"
  TAR="$HOME/snap/flutter/common/latest_stable.tar.xz"
  if [ -f "$TAR" ]; then
    echo "  Tar size: $(du -h "$TAR" | cut -f1)"
  else
    echo "  Tar not found"
  fi
  echo "  aria2c alive: $(pgrep -c '[a]ria2c' 2>/dev/null || echo 0)"
  echo ""

  echo "▶ Project State"
  if [ -f "$PROJECT/pubspec.lock" ]; then
    echo "  pubspec.lock: ✅ EXISTS"
  else
    echo "  pubspec.lock: ❌ MISSING"
  fi

  if [ -d "$PROJECT/android/app/src/main" ]; then
    echo "  Android: ✅ $(ls "$PROJECT/android/app/src/main/" | tr '\n' ' ')"
  else
    echo "  Android: ❌ incomplete"
  fi
  echo ""

  echo "▶ Devices"
  adb devices -l 2>/dev/null | grep -E 'device |List of' | head -6 || echo "  No devices or adb not ready"
  echo ""

  echo "▶ Background Logs (last lines)"
  echo "  --- pub get ---"
  tail -3 "$LOG_DIR/flutter_pub_get.log" 2>/dev/null || echo "  (no log)"
  echo ""
  echo "  --- download monitor ---"
  tail -2 "$LOG_DIR/flutter_download_monitor.log" 2>/dev/null || echo "  (no log)"
  echo ""

  echo "Press Ctrl+C to exit • Refreshes every 10s"
  sleep 10
done
