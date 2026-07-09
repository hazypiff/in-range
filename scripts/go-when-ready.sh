#!/bin/bash
# One-line / script to run the post-SDK sequence when Flutter is ready.
# Safe to run in background: nohup bash scripts/go-when-ready.sh > /tmp/inrange_go.log 2>&1 &

PROJECT="/home/hazypiff/in-range"
LOG="/tmp/inrange_go.log"

echo "[$(date)] Waiting for Flutter SDK to be ready..." | tee -a "$LOG"

# Wait for flutter to respond cleanly (max ~30 min)
for i in {1..180}; do
  if /snap/bin/flutter --version >/dev/null 2>&1; then
    VERSION=$(/snap/bin/flutter --version 2>/dev/null | head -1)
    echo "[$(date)] Flutter ready: $VERSION" | tee -a "$LOG"
    break
  fi
  if (( i % 10 == 0 )); then
    echo "[$(date)] Still waiting... ($i/180)" | tee -a "$LOG"
  fi
  sleep 10
done

if ! /snap/bin/flutter --version >/dev/null 2>&1; then
  echo "[$(date)] ERROR: Flutter never became ready. Exiting." | tee -a "$LOG"
  exit 1
fi

echo "[$(date)] Running post-download sequence..." | tee -a "$LOG"

cd "$PROJECT" || exit 1

echo "[$(date)] flutter pub get" | tee -a "$LOG"
flutter pub get 2>&1 | tee -a "$LOG"

echo "[$(date)] dart run build_runner build" | tee -a "$LOG"
dart run build_runner build --delete-conflicting-outputs 2>&1 | tee -a "$LOG"

echo "[$(date)] flutter devices" | tee -a "$LOG"
flutter devices 2>&1 | tee -a "$LOG"

echo "[$(date)] Launching on first device..." | tee -a "$LOG"
# Use the first available device
DEVICE=$(flutter devices 2>/dev/null | grep -o '^[a-zA-Z0-9_]*' | head -1)
if [ -n "$DEVICE" ]; then
  flutter run -d "$DEVICE" 2>&1 | tee -a "$LOG"
else
  echo "No device found. Run manually: flutter run -d <id>" | tee -a "$LOG"
fi

echo "[$(date)] Done." | tee -a "$LOG"
