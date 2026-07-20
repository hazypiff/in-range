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
      // `restricted` = Bluetooth blocked by MDM / Screen Time / parental
      // controls (distinct from user denial). It would pass a
      // !isPermanentlyDenied check and then fail cryptically inside
      // CoreBluetooth, so reject it explicitly (P2, hazypiff review
      // 2026-07-16). Plain `denied` can be a transient pre-CBManager state on
      // iOS, so keep letting that through — CoreBluetooth surfaces any real
      // block — but a hard user/MDM refusal is rejected here.
      if (bt.isPermanentlyDenied || bt.isRestricted) {
        return false;
      }
      return true;
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
  ///
  /// [onDisclosure] MUST present Google Play's prominent disclosure and
  /// resolve true only on an affirmative tap. Play policy requires an in-app
  /// disclosure — shown *before* the OS prompt, not buried in the privacy
  /// policy or ToS — naming the data, saying it is collected in the
  /// background, and explaining why. Requesting ACCESS_BACKGROUND_LOCATION
  /// without it is a documented rejection cause.
  ///
  /// When [onDisclosure] is null or returns false we simply never ask, and the
  /// beacon stays foreground-only. Fail-closed: no disclosure, no request.
  static Future<bool> requestBackgroundLocation({
    Future<bool> Function()? onDisclosure,
  }) async {
    // Already granted (e.g. returning user) — nothing to disclose or ask.
    if (await Permission.locationAlways.isGranted) {
      return true;
    }
    if (onDisclosure == null) {
      debugPrint('PERM background location skipped: no disclosure provided');
      return false;
    }
    if (!await onDisclosure()) {
      debugPrint('PERM background location declined at disclosure');
      return false;
    }
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
  ///
  /// [onBackgroundDisclosure] is forwarded to [requestBackgroundLocation];
  /// without it the background step is skipped entirely (foreground-only
  /// beacon), which is the safe default rather than a silent policy breach.
  static Future<PermissionResult> requestAllForBeacon({
    Future<bool> Function()? onBackgroundDisclosure,
  }) async {
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
    final bg = await requestBackgroundLocation(
      onDisclosure: onBackgroundDisclosure,
    );
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

/// Google Play prominent disclosure for background location.
///
/// Must run BEFORE the OS permission prompt. Play requires the disclosure to
/// name the data type, state that collection continues when the app is closed
/// or not in use, explain what it enables, and be dismissible only by an
/// affirmative user action. Declining is a first-class outcome — the beacon
/// still works in the foreground — so neither button is styled as a dead end.
///
/// Returns true only on an explicit "Allow" tap; a back-gesture dismissal
/// resolves false.
Future<bool> showBackgroundLocationDisclosure(BuildContext context) async {
  final accepted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Background location'),
      content: const SingleChildScrollView(
        child: Text(
          'In Range collects location data to detect when you and another '
          'member are physically near each other, so an encounter can be '
          'recorded.\n\n'
          'To keep detecting encounters while the app is closed or not in '
          'use, In Range needs "Allow all the time" location access.\n\n'
          'Your precise location is used only to match encounters and is '
          'deleted from our servers after 24 hours. It is never sold or '
          'shared with advertisers.\n\n'
          'You can decline and In Range will only detect encounters while '
          'the app is open. You can change this at any time in Settings.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Allow'),
        ),
      ],
    ),
  );
  return accepted ?? false;
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
