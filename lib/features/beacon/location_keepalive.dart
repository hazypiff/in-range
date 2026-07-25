import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Keeps the app process RESIDENT while the beacon is on, so CoreBluetooth
/// keeps scanning with the screen locked instead of waking in ~15-30 minute
/// BGAppRefresh bursts.
///
/// This is the single largest iOS discoverability lever available without a
/// paid developer account, and the app already declared everything it needs
/// for it — `location` in UIBackgroundModes and the Always usage string were
/// in Info.plist all along, but nothing ever started a session, so the
/// entitlement sat unused and every fix was a one-shot poll on a Dart timer
/// that cannot fire while suspended.
///
/// **The location data is not the point — the session is.** iOS keeps an app
/// running while it holds an active location session, and a running app scans
/// continuously. So this deliberately asks for the WORST accuracy that still
/// sustains a session, and throws the fixes away. Coordinates are a by-product
/// we neither need nor keep; the beacon's own GPS path (`_ensureLocationCache`)
/// is unchanged and remains the only thing that records a position.
///
/// Scoped strictly to beacon-ON. That is both the honest design — the user
/// asked to be discoverable, and this is what discoverable costs — and the
/// version that survives App Review, because the permission is legible to the
/// person who turned it on.
///
/// iOS only. Android already scans in the background acceptably, and adding a
/// second foreground-service notification there would cost battery complaints
/// for no gain.
class LocationKeepalive {
  LocationKeepalive({
    Stream<Position> Function(LocationSettings)? openStream,
    TargetPlatform? platform,
  })  : _openStream = openStream ??
            ((s) => Geolocator.getPositionStream(locationSettings: s)),
        _platform = platform ?? defaultTargetPlatform;

  final Stream<Position> Function(LocationSettings) _openStream;
  final TargetPlatform _platform;

  StreamSubscription<Position>? _sub;

  bool get isRunning => _sub != null;

  /// True when a keepalive session is worth attempting on this platform.
  bool get isSupported => _platform == TargetPlatform.iOS;

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
    if (!isSupported || _sub != null) return;
    try {
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
