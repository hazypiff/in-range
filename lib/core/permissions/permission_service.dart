import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Requests the runtime permissions needed for BLE advertising + scanning
/// on Android 10 (API 29):
///   1. locationWhenInUse (runtime, required for BLE scan on API 29)
///   2. locationAlways (runtime, required for background BLE)
///
/// On Android 10, BLUETOOTH / BLUETOOTH_ADMIN are normal permissions
/// (granted at install) so we do not request them at runtime.
/// BLUETOOTH_SCAN / BLUETOOTH_ADVERTISE / BLUETOOTH_CONNECT are Android 12+
/// only — they do not exist on API 29.
///
/// IMPORTANT: per permission_handler docs, on Android 10+ the user MUST grant
/// locationWhenInUse before locationAlways can be requested. We follow that
/// sequence here. If the user denies the second prompt, background BLE is
/// unavailable and we degrade gracefully (foreground-only).
class PermissionService {
  /// Returns true if all permissions needed for foreground BLE are granted.
  static Future<bool> requestForegroundBle() async {
    // Step 1: foreground location (prerequisite for background on API 29+)
    final foreground = await Permission.locationWhenInUse.request();
    if (!foreground.isGranted) {
      return false;
    }
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
