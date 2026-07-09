# In Range - Immediate Next Steps (2026-07-08)

**Status:** ✅ DONE — APK built (48MB), installed + launched on Galaxy S9 (324c305855433498). App process running. See HANDOFF.md.

## Built & Installed
```bash
flutter build apk --release   # (or --debug)
adb -s 324c305855433498 install -r build/app/outputs/flutter-apk/app-release.apk
adb -s 324c305855433498 shell am start -n com.example.in_range/.MainActivity
bash scripts/install-and-run.sh
```

## Test on device (do this now)
1. Open "In Range" on the S9.
2. Grant Location "while using the app" then "Allow all the time".
3. Pick range e.g. feet_10, tap "Turn Beacon On".
4. Watch persistent notification.
5. Use 2+ phones: both ON → should see encounters (BLE RSSI or GPS).
6. Monitor:
   adb -s 324c305855433498 logcat | grep -E 'Beacon|flutter|Encounter'
   tail -f /tmp/device_logcat.txt

Next: real Supabase keys in .env + migrations push, photo UI, full features. LLM can restart after stable test.

## Run this sequence now
```bash
export PATH="/snap/bin:$PATH"
cd /home/hazypiff/in-range

# 1. Ensure deps (safe even if lock exists)
flutter pub get

# 2. Code generation
dart run build_runner build --delete-conflicting-outputs

# 3. Verify
flutter devices

# 4. Launch on first S9 (test beacon)
flutter run -d 324c305855433498
```

Or use the convenience script:
```bash
bash /home/hazypiff/in-range/scripts/GO.sh
```

## Monitoring (works even if agent drops)
```bash
# Quick
bash scripts/status.sh

# Live
bash scripts/monitor.sh

# Raw
cat /tmp/inrange_live_status.txt
tail -f /tmp/flutter_pub_get.log

# Restart updaters
bash scripts/start-persistent-monitors.sh
```

## If you need to re-wait for SDK (rare now)
```bash
nohup bash scripts/go-when-ready.sh > /tmp/go.log 2>&1 &
tail -f /tmp/go.log
```

## Key files
- scripts/GO.sh, status.sh, monitor.sh
- android/app/src/main/AndroidManifest.xml (custom permissions)
- lib/features/beacon/ (service + UI)
- supabase/migrations/ (0001 + 0002)
- HANDOFF.md (full history)

Once the app runs on the phone, toggle the beacon and test with multiple S9s for real encounters.
