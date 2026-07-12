#!/bin/bash
# Post-build: install release APK to the primary S9 and launch.
# Run after APK is ready.
set -e
DEVICE="324c305855433498"
APK="build/app/outputs/flutter-apk/app-release.apk"

export PATH="/snap/bin:$PATH"

if [ ! -f "$APK" ]; then
  echo "APK not found at $APK. Build first."
  exit 1
fi

echo "=== Installing to $DEVICE ==="
adb -s "$DEVICE" install -r "$APK"

echo "=== Launching ==="
adb -s "$DEVICE" shell am start -n io.inrange.app/.MainActivity

echo "=== Device ready. Use logcat to monitor ==="
echo "adb -s $DEVICE logcat | grep -E 'flutter|Beacon|In Range|Encounter|BLE'"
echo ""
echo "On phone: open app, grant Location (while using + all the time for bg), toggle beacon."
