import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:in_range/core/config/app_config.dart';

/// One location fix from the native coordinator or the Dart geolocator stream.
class LocationAssistFix {
  const LocationAssistFix({
    required this.lat,
    required this.lon,
    required this.accuracyM,
    required this.at,
    this.isMoving,
  });

  final double lat;
  final double lon;
  final double accuracyM;
  final DateTime at;

  /// True when the device appears to be moving; null if the source does not
  /// report speed. This is a coarse hint, not a classification feature.
  final bool? isMoving;
}

/// Holds a foreground-started location session while the beacon is on, so the
/// process is not suspended and app-owned timers keep firing with the screen
/// dark.
///
/// **OFF by default** (`AppConfig.locationResidency`). Unproven and governance-
/// blocked; see below. Do not enable it outside a bench.
///
/// iOS now prefers a native coordinator (`BackgroundLocationCoordinator.swift`)
/// that buffers fixes in UserDefaults and bridges them on foreground. If that
/// coordinator is missing (older build, simulator without plugin registration),
/// this class falls back to the Dart `geolocator` stream. Either way the beacon
/// keeps working.
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
///   stated purpose. Discarding every fix — which reads as a privacy virtue —
///   is evidence AGAINST us here: an app that never uses location has no
///   business holding the location background mode. The defensible version
///   feeds a genuinely location-dependent feature (coarse presence matching),
///   which would also make the session honestly location-purposed rather than
///   a BLE keepalive wearing a location costume.
///
/// iOS only. Android already scans in the background acceptably, and a second
/// foreground-service notification there would cost battery for no gain.
class LocationKeepalive {
  LocationKeepalive({
    Stream<Position> Function(LocationSettings)? openStream,
    TargetPlatform? platform,
    bool Function()? enabled,
    MethodChannel? coordinatorChannel,
  })  : _openStream = openStream ??
            ((s) => Geolocator.getPositionStream(locationSettings: s)),
        _platform = platform ?? defaultTargetPlatform,
        _enabled = enabled ?? (() => AppConfig.locationResidency),
        _channel = coordinatorChannel ??
            const MethodChannel('io.inrange.app/location_coordinator') {
    // try/catch, NOT BindingBase.debugBindingType(). That returns null in
    // release AND profile builds — its backing field is assigned inside an
    // assert block (flutter/foundation/binding.dart:293), which the compiler
    // strips. Gating on it silently disabled this entire native path in every
    // build produced by build-install-ios.sh --release, while `flutter test`
    // (asserts on) reported it working.
    try {
      _channel.setMethodCallHandler(_handleNativeCall);
    } catch (e) {
      // No binding (plain unit test). The native path is unavailable; the
      // Dart-stream fallback in start() covers it.
      debugPrint('Location coordinator handler not registered: ${_shortError(e)}');
    }
  }

  final Stream<Position> Function(LocationSettings) _openStream;
  final TargetPlatform _platform;
  final bool Function() _enabled;
  final MethodChannel _channel;

  StreamSubscription<Position>? _sub;
  bool _nativeRunning = false;

  bool get isRunning => _sub != null || _nativeRunning;

  /// True when a session is both permitted by the flag and useful on this
  /// platform. The flag is checked at every start, not cached, so a bench can
  /// flip it between runs of the same binary.
  bool get isSupported => _platform == TargetPlatform.iOS && _enabled();

  /// Consumer hook for every fresh or buffered location fix. Called for both
  /// the native coordinator path and the Dart-stream fallback.
  void Function(LocationAssistFix)? onFix;

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
    if (isRunning) return;
    try {
      // isSupported reads config, and config can throw when dotenv has not
      // been loaded. If we cannot even read the flag, degrade silently.
      if (!isSupported) return;
    } catch (e) {
      debugPrint('Location keepalive flag read failed: $e');
      return;
    }

    try {
      // Prefer the native coordinator. It buffers fixes while the app is
      // suspended and bridges them on foreground.
      //
      // Attempted UNCONDITIONALLY — a missing binding or missing plugin throws
      // and is caught below. The previous BindingBase.debugBindingType() guard
      // looked like a test-only skip but is compiled away in release, so it
      // skipped the native path on real devices instead.
      final ok = await _channel.invokeMethod<bool>('start', {
        'accuracy': 'lowest',
        'distanceFilter': 100,
        'pauseAutomatically': false,
        'background': true,
      });
      if (ok == true) {
        _nativeRunning = true;
        debugPrint('Location coordinator started (native)');
        await _pullBufferedFixes();
        return;
      }
    } on MissingPluginException {
      // Native coordinator not available on this build; fall through to the
      // Dart geolocator stream.
    } catch (e) {
      debugPrint('Location coordinator native start failed: ${_shortError(e)}');
      // Fall through to Dart stream so a partial native failure doesn't kill
      // the beacon.
    }

    _startDartStream();
  }

  void _startDartStream() {
    try {
      _sub = _openStream(settingsForResidency()).listen(
        (pos) => _emitFix(_positionToFix(pos)),
        onError: (Object e) {
          debugPrint('Location keepalive ended: $e');
          unawaited(stop());
        },
        cancelOnError: true,
      );
      debugPrint('Location keepalive started (Dart stream)');
    } catch (e) {
      _sub = null;
      debugPrint('Location keepalive failed to start: $e');
    }
  }

  /// Stops the session. Must run on every beacon-off path, or the app keeps
  /// itself alive — and keeps showing the location indicator — after the user
  /// turned discoverability off.
  Future<void> stop() async {
    if (_nativeRunning) {
      _nativeRunning = false;
      try {
        await _channel.invokeMethod('stop');
      } catch (e) {
        debugPrint('Location coordinator stop failed: $e');
      }
    }

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

  Future<void> _pullBufferedFixes() async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('flush');
      if (raw == null || raw.isEmpty) return;
      for (final m in raw) {
        if (m is Map) {
          _emitFix(_mapToFix(m.cast<String, dynamic>()));
        }
      }
    } catch (e) {
      debugPrint('Location coordinator flush failed: $e');
    }
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onLocationFixes':
        final list = call.arguments as List<dynamic>? ?? [];
        for (final raw in list) {
          if (raw is Map) {
            _emitFix(_mapToFix(raw.cast<String, dynamic>()));
          }
        }
        return null;
    }
    return null;
  }

  LocationAssistFix _positionToFix(Position p) => LocationAssistFix(
        lat: p.latitude,
        lon: p.longitude,
        accuracyM: p.accuracy,
        at: p.timestamp,
        isMoving: null,
      );

  LocationAssistFix _mapToFix(Map<String, dynamic> m) => LocationAssistFix(
        lat: (m['lat'] as num).toDouble(),
        lon: (m['lon'] as num).toDouble(),
        accuracyM: (m['acc'] as num).toDouble(),
        at: DateTime.fromMillisecondsSinceEpoch(m['ts'] as int),
        isMoving: m['moving'] as bool?,
      );

  String _shortError(Object e) {
    // Keep logs short in unit-test contexts where the binding isn't initialized.
    // The runtime type is enough to diagnose the failure mode in production.
    return e.runtimeType.toString();
  }

  void _emitFix(LocationAssistFix fix) {
    onFix?.call(fix);
    // calibScanMode touches dotenv, which is not loaded in every unit-test
    // context. Treat an unreadable flag as "off" rather than crashing the fix.
    var logFix = false;
    try {
      logFix = AppConfig.calibScanMode;
    } catch (_) {}
    if (logFix) {
      debugPrint(
        'LocationAssist lat=${fix.lat.toStringAsFixed(6)} '
        'lon=${fix.lon.toStringAsFixed(6)} '
        'acc=${fix.accuracyM.toStringAsFixed(1)} '
        'moving=${fix.isMoving}',
      );
    }
  }
}
