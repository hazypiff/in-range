#!/bin/bash
# One-shot status check - completely safe, no long-running commands.

PROJECT="/home/hazypiff/in-range"

echo "=== In Range Status - $(date '+%Y-%m-%d %H:%M:%S') ==="
echo ""

echo "Flutter SDK:"
# DO NOT call `flutter --version` — it triggers a fresh 1.4GB download and
# interrupts any in-progress aria2c download. Just check whether the SDK
# extracted dir exists.
if [ -d "$HOME/snap/flutter/common/flutter" ]; then
  echo "  SDK extracted: ✅ $HOME/snap/flutter/common/flutter"
else
  echo "  SDK extracted: ❌ (still downloading or not yet extracted)"
fi

echo ""
echo "Download:"
du -h ~/snap/flutter/common/latest_stable.tar.xz 2>/dev/null || echo "  tar not visible"
echo "  curl processes: $(ps aux | grep -c '[c]url.*flutter_linux' 2>/dev/null || echo 0)"

echo ""
echo "Project:"
[ -f "$PROJECT/pubspec.lock" ] && echo "  pubspec.lock: ✅ present" || echo "  pubspec.lock: ❌ missing"
if [ -d "$PROJECT/android/app/src/main" ]; then
  echo "  android ready: ✅ $(ls $PROJECT/android/app/src/main/ 2>/dev/null | tr '\n' ' ')"
else
  echo "  android ready: ❌"
fi

echo ""
echo "Devices:"
adb devices -l 2>/dev/null | grep -E 'device |List of devices' | head -5 || echo "  (adb not showing devices or not installed)"

echo ""
echo "Useful logs:"
echo "  cat /tmp/inrange_live_status.txt"
echo "  tail -f /tmp/flutter_pub_get.log"
