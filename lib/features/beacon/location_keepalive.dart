import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:in_range/core/config/app_config.dart';

/// Holds a foreground-started location session while the beacon is on, so the
/// process is not suspended and app-owned timers keep firing with the screen
/// dark.
///
/// **OFF by default** (`AppConfig.locationResidency`). Unproven and governance-
/// blocked; see below. Do not enable it outside a bench.
///
/// ## What this does NOT do
///
/// It does not make Bluetooth foreground-like. Background scanning stays
/// duty-cycled and duplicate discoveries stay coalesced whether or not the
/// process is suspended — those rules key off app STATE, not liveness, and
/// Apple engineering has said directly that background-location does not
/// change background BLE scanning. An earlier version of this file claimed
/// residency makes CoreBluetooth "scan continuously". That was wrong.
///
/// ## The narrower thing that might be true
///
/// Duplicates are suppressed WITHIN a scan session, so restarting the session
/// is how repeated samples from one peer are obtained at all
/// (BackgroundBeacon.swift:296). Those restarts are timer-driven, and timers do
/// not fire while suspended. So the testable hypothesis is: residency raises
/// sample CADENCE by letting the restart machinery run — not that it unlocks a
/// better scan mode.
///
/// Even that is not obvious. The 2026-07-23 bench found short restart bursts
/// produced ZERO samples because background deliveries are coalesced for
/// seconds and every session died before its delivery arrived
/// (BackgroundBeacon.swift:395). Longer sessions won. So residency may help,
/// may do nothing, and could plausibly hurt if it encourages churn.
///
/// **Gate: a same-binary A/B with this flag off/on, measuring didDiscover,
/// GATT reads and connected-RSSI counts on locked hardware.** The unit tests
/// beside this file exercise a fake Dart stream and prove nothing about radios.
///
/// ## Two open problems
///
/// 1. **Governance.** This couples location to the beacon toggle, contradicting
///    "the beacon is a pure BLE switch" (owner decision 2026-07-21, issue #2,
///    recorded at beacon_screen.dart:26). Owner call, not an engineering one.
/// 2. **App Review.** Guideline 2.5.4 requires background modes serve their
///    stated purpose. Discarding every fix — which reads as a privacy virtue —
///    is evidence AGAINST us here: an app that never uses location has no
///    business holding the location background mode. The defensible version
///    feeds a genuinely location-dependent feature (coarse presence matching),
///    which would also make the session honestly location-purposed rather than
///    a BLE keepalive wearing a location costume.
///
/// iOS only. Android already scans in the background acceptably, and a second
/// foreground-service notification there would cost battery for no gain.
class LocationKeepalive {
  LocationKeepalive({
    Stream<Position> Function(LocationSettings)? openStream,
    TargetPlatform? platform,
    bool Function()? enabled,
  })  : _openStream = openStream ??
            ((s) => Geolocator.getPositionStream(locationSettings: s)),
        _platform = platform ?? defaultTargetPlatform,
        _enabled = enabled ?? (() => AppConfig.locationResidency);

  final Stream<Position> Function(LocationSettings) _openStream;
  final TargetPlatform _platform;
  final bool Function() _enabled;

  StreamSubscription<Position>? _sub;

  bool get isRunning => _sub != null;

  /// True when a session is both permitted by the flag and useful on this
  /// platform. The flag is checked at every start, not cached, so a bench can
  /// flip it between runs of the same binary.
  bool get isSupported => _platform == TargetPlatform.iOS && _enabled();

  /// Settings tuned for residency rather than precision.
  ///
  /// `pauseLocationUpdatesAutomatically: false` is the load-bearing one. iOS
  /// pauses a location session when it decides the device has been stationary,
  /// and a paused session stops holding the process up — which would surrender
  /// residency at exactly the moment it matters most. Someone sitting still in
  /// a cafe is the canonical In Range encounter, not an idle device.
  static LocationSettings settingsForResidency() => AppleSettings(
        // Coarsest tier that still sustains a session. We discard the fixes;
        // asking for precision here would only spend battery and collect
        // sensitive data we have no use for.
        accuracy: LocationAccuracy.lowest,
        activityType: ActivityType.other,
        // Callbacks cost power; the SESSION is what keeps us alive, not their
        // cadence. A wide filter means we stay resident while staying quiet.
        distanceFilter: 100,
        pauseLocationUpdatesAutomatically: false,
        // Honest, and required for background updates under when-in-use: the
        // user can see at a glance that In Range is live.
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );

  /// Starts the session. Safe to call twice. Never throws: losing residency
  /// degrades detection latency, but a beacon that refuses to start because
  /// location was denied would be a worse product than a foreground-only one.
  Future<void> start() async {
    if (_sub != null) return;
    try {
      // Inside the try: isSupported reads config, and config can throw when
      // dotenv has not been loaded. start() promises never to throw.
      if (!isSupported) return;
      _sub = _openStream(settingsForResidency()).listen(
        // Deliberately empty. See the class doc: the session is the product,
        // the coordinates are not. Do not start recording these without a
        // consent decision — that is a different feature.
        (_) {},
        onError: (Object e) {
          debugPrint('Location keepalive ended: $e');
          unawaited(stop());
        },
        cancelOnError: true,
      );
      debugPrint('Location keepalive started (residency mode)');
    } catch (e) {
      _sub = null;
      debugPrint('Location keepalive failed to start: $e');
    }
  }

  /// Stops the session. Must run on every beacon-off path, or the app keeps
  /// itself alive — and keeps showing the location indicator — after the user
  /// turned discoverability off.
  Future<void> stop() async {
    final sub = _sub;
    _sub = null;
    if (sub == null) return;
    try {
      await sub.cancel();
      debugPrint('Location keepalive stopped');
    } catch (e) {
      debugPrint('Location keepalive stop failed: $e');
    }
  }
}
