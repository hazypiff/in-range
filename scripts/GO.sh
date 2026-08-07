#!/bin/bash
# One-command "GO" script for when the SDK download finishes.
# Run this (or put it in nohup) once the aria2c log shows "Download Results" + OK.

set -e

PROJECT="$HOME/in-range"
TAR="$HOME/snap/flutter/common/latest_stable.tar.xz"

echo "=== Waiting for clean Flutter SDK ==="
while ! /snap/bin/flutter --version >/dev/null 2>&1; do
  echo "Still initializing... ($(date +%H:%M))"
  sleep 15
done
/snap/bin/flutter --version | head -1
echo ""

echo "=== Verifying tar (if still present) ==="
if [ -f "$TAR" ]; then
  xz -t "$TAR" && echo "Tar integrity OK" || { echo "Tar corrupt!"; exit 1; }
fi

echo ""
echo "=== Running the build sequence ==="
cd "$PROJECT"

echo "flutter pub get"
flutter pub get

echo ""
echo "dart run build_runner build"
dart run build_runner build --delete-conflicting-outputs

echo ""
echo "flutter devices"
flutter devices

echo ""
echo "=== Ready to launch on the first S9 ==="
if [ "$#" -lt 1 ]; then
  echo "No device serial supplied; build preparation is complete."
  echo "Launch with: $0 <device-serial>"
  exit 0
fi
echo "Launching on the explicitly selected device."
flutter run -d "$1"
