import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Requests runtime permissions needed for BLE advertising + scanning.
///
/// Permission pyramid (API level dependent):
///   - Android 10 (API 29): locationWhenInUse → locationAlways
///   - Android 12+ (API 31): BLUETOOTH_SCAN / BLUETOOTH_ADVERTISE / BLUETOOTH_CONNECT
///                            are "nearby devices" permissions; location is not required
///                            for BLE on API 31+ but we still ask for coarse location
///                            (approximate) so the miles feed can work.
///
/// We request the superset and degrade gracefully — whatever the OS grants
/// determines which features are available.
class PermissionService {
  /// Returns true if the caller has enough to run BLE in the foreground.
  static Future<bool> requestForegroundBle() async {
    // Location is prerequisite for BLE on API 29. On API 31+ it is not
    // required for scanning but needed for GPS (miles feed). Request it first.
    final foreground = await Permission.locationWhenInUse.request();
    if (!foreground.isGranted) {
      return false;
    }

    // Android 12+ BLE "nearby devices" permissions (no-op below API 31).
    // These are required for BLE scanning on modern Android.
    await Future.wait([
      Permission.bluetoothScan.request(),
      Permission.bluetoothAdvertise.request(),
      Permission.bluetoothConnect.request(),
    ]);

    return true;
  }

  /// Returns true if background location is also granted.
  /// Must be called after requestForegroundBle() succeeds.
  static Future<bool> requestBackgroundLocation() async {
    final bg = await Permission.locationAlways.request();
    return bg.isGranted;
  }

  /// Full flow: foreground → background. Returns a PermissionResult.
  static Future<PermissionResult> requestAllForBeacon() async {
    final fg = await requestForegroundBle();
    if (!fg) {
      return PermissionResult(
        foregroundLocation: false,
        backgroundLocation: false,
        canUseBeacon: false,
        denialReason: 'Location permission is required for BLE proximity. '
            'Please grant location access in Settings to use In Range.',
      );
    }
    final bg = await requestBackgroundLocation();
    return PermissionResult(
      foregroundLocation: true,
      backgroundLocation: bg,
      // Foreground-only beacon is still useful — background is best-effort.
      canUseBeacon: true,
      denialReason: bg
          ? null
          : 'Background location denied. Beacon will only run while the app '
              'is in the foreground. To enable background scanning, grant '
              '"Allow all the time" in Settings.',
    );
  }
}

class PermissionResult {
  const PermissionResult({
    required this.foregroundLocation,
    required this.backgroundLocation,
    required this.canUseBeacon,
    this.denialReason,
  });

  final bool foregroundLocation;
  final bool backgroundLocation;
  final bool canUseBeacon;
  final String? denialReason;
}

/// Shows a rationale dialog before opening app settings, if the user denied.
Future<void> showPermissionRationale(
  BuildContext context,
  String reason,
) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Permissions needed'),
      content: Text(reason),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            openAppSettings();
          },
          child: const Text('Open Settings'),
        ),
      ],
    ),
  );
}
