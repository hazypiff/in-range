import 'dart:io' show Platform;

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
    debugPrint('PERM locationWhenInUse: $foreground');
    if (!foreground.isGranted) {
      return false;
    }

    // iOS has NO scan/advertise/connect permissions — those are Android 12+
    // (BLUETOOTH_SCAN/ADVERTISE/CONNECT) only. On iOS permission_handler
    // returns `denied` for them permanently, so requiring them here bricked
    // the beacon on every iPhone build (2026-07-16 incident). iOS gates BLE
    // through the single `Permission.bluetooth` + the Info.plist usage
    // strings; the OS prompts on first CBCentral/PeripheralManager use.
    if (Platform.isIOS) {
      final bt = await Permission.bluetooth.request();
      debugPrint('PERM iOS bluetooth: $bt');
      // isPermanentlyDenied only if the user explicitly refused; otherwise
      // (granted / not-yet-determined) let the beacon proceed and let the
      // CoreBluetooth manager surface any real block.
      return !bt.isPermanentlyDenied;
    }

    // Android 12+ BLE "nearby devices" permissions. On API 31+ the app CANNOT
    // scan or advertise without scan+advertise, so a denial here is a hard
    // failure — not something to swallow and then fail cryptically inside the
    // BLE plugin (reviewer #21). Below API 31 these resolve granted (no-op),
    // so requiring them does not break Android 10/11.
    final results = await Future.wait([
      Permission.bluetoothScan.request(),
      Permission.bluetoothAdvertise.request(),
      Permission.bluetoothConnect.request(),
    ]);
    final scan = results[0];
    final advertise = results[1];
    debugPrint(
        'PERM btScan: $scan btAdvertise: $advertise btConnect: ${results[2]}');
    // Nearby-devices grants are a single OS-level toggle, so scan and advertise
    // move together; require both. (connect isn't needed for advertise+scan.)
    if (!scan.isGranted || !advertise.isGranted) {
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

  /// Compact status line of every permission the beacon gate checks —
  /// shown in the UI when the beacon refuses, so field debugging never
  /// depends on a tethered debug session.
  static Future<String> diagnose() async {
    final entries = <String, Permission>{
      'loc': Permission.locationWhenInUse,
      'locAlways': Permission.locationAlways,
      'btScan': Permission.bluetoothScan,
      'btAdv': Permission.bluetoothAdvertise,
      'btConn': Permission.bluetoothConnect,
      'bt': Permission.bluetooth,
    };
    final parts = <String>[];
    for (final e in entries.entries) {
      try {
        final s = await e.value.status;
        parts.add('${e.key}=${s.name}');
      } catch (err) {
        parts.add('${e.key}=err');
      }
    }
    return parts.join(' ');
  }

  /// Full flow: foreground → background. Returns a PermissionResult.
  static Future<PermissionResult> requestAllForBeacon() async {
    final fg = await requestForegroundBle();
    if (!fg) {
      // Distinguish which grant is missing so the rationale is accurate.
      final loc = await Permission.locationWhenInUse.isGranted;
      return PermissionResult(
        foregroundLocation: loc,
        backgroundLocation: false,
        canUseBeacon: false,
        denialReason: loc
            ? 'Nearby devices (Bluetooth) permission is required to find people '
                'around you. Grant it in Settings to use In Range.'
            : 'Location permission is required for BLE proximity. '
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
