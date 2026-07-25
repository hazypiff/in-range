import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_range/features/beacon/batch_token_source.dart';

/// Dart side of the iOS locked-phone BLE carrier (W4 of
/// docs/IOS_BACKGROUND_BLE_WIRING.md). Bridges to the native
/// `BackgroundBeacon.swift` module, which owns BOTH CoreBluetooth roles on
/// iOS: advertising (marker + GATT token service, survives lock/relaunch)
/// and the CAFE-filtered scan (+ connect-read for peers whose token isn't
/// on the air). Foreground advert ingest stays with the Dart unfiltered
/// scan; the native module only emits what that scan can't see.
class BackgroundBeaconChannel {
  BackgroundBeaconChannel() {
    _channel.setMethodCallHandler(_onCall);
  }

  static const _channel = MethodChannel('io.inrange/background_beacon');

  /// Foreign sighting from the native module (token hex, RSSI, capture
  /// time). Buffered background sightings flush on foregrounding with
  /// their ORIGINAL timestamps — honor them.
  void Function(String tokenHex, int rssi, DateTime at)? onSighting;

  /// Native advertising state — feeds the fail-closed `_discoverable` rule.
  void Function(bool advertising)? onAdvertisingState;

  /// Native reports a non-empty background buffer. The consumer MUST pull
  /// via [drainBufferedSightings] and confirm via [ackBufferedSightings] —
  /// native never deletes a buffered sighting before that ack (audit
  /// 2026-07-25: the old push-flush destroyed buffers before delivery was
  /// confirmed, losing sightings on cold launches).
  void Function()? onBufferedSightingsReady;

  Future<dynamic> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'onSighting':
        final args = call.arguments;
        if (args is Map) {
          final token = args['token'], rssi = args['rssi'], ts = args['ts'];
          if (token is String && token.length == 32 && rssi is int) {
            final at = ts is int
                ? DateTime.fromMillisecondsSinceEpoch(ts)
                : DateTime.now();
            onSighting?.call(token, rssi, at);
          }
        }
      case 'onAdvertisingState':
        final args = call.arguments;
        if (args is bool) onAdvertisingState?.call(args);
      case 'onBufferedSightingsReady':
        onBufferedSightingsReady?.call();
    }
    return null;
  }

  /// Whether the native carrier is enabled — i.e. it survived a process
  /// eviction and is advertising/scanning RIGHT NOW regardless of what this
  /// fresh Dart isolate believes. The session-restore path keys off this so
  /// native, Dart, and UI converge on one beacon state.
  Future<bool> isNativeEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isEnabled') ?? false;
    } catch (_) {
      return false; // no native module (Android, tests) — nothing to restore
    }
  }

  /// Reads the native background-sighting buffer WITHOUT clearing it. Pair
  /// with [ackBufferedSightings] once the sightings are ingested.
  Future<List<Map<String, Object>>> drainBufferedSightings() async {
    try {
      final list =
          await _channel.invokeMethod<List<dynamic>>('drainBufferedSightings');
      return [
        for (final e in list ?? const <dynamic>[])
          if (e is Map) Map<String, Object>.from(e),
      ];
    } catch (e) {
      debugPrint('BackgroundBeacon drain failed: $e');
      return const [];
    }
  }

  /// Confirms ingestion of the first [count] drained sightings; only then
  /// does native drop them (at-least-once delivery — a crash between drain
  /// and ack re-delivers, it never loses).
  Future<void> ackBufferedSightings(int count) async {
    try {
      await _channel.invokeMethod<void>('ackBufferedSightings', count);
    } catch (e) {
      debugPrint('BackgroundBeacon ack failed: $e');
    }
  }

  static List<Map<String, Object>> slotsPayload(
      List<BatchSlot> slots, {String? currentToken, DateTime? currentFrom,
      DateTime? currentUntil}) {
    final out = <Map<String, Object>>[
      for (final s in slots)
        {
          't': s.token,
          'f': s.validFrom.millisecondsSinceEpoch,
          'u': s.validUntil.millisecondsSinceEpoch,
        },
    ];
    // Random-fallback mode (local BLE, no server batch): the current token is
    // the only one that exists — hand it to the GATT read path as a slot.
    if (currentToken != null && currentFrom != null && currentUntil != null) {
      out.add({
        't': currentToken,
        'f': currentFrom.millisecondsSinceEpoch,
        'u': currentUntil.millisecondsSinceEpoch,
      });
    }
    return out;
  }

  /// Starts (or re-arms) native advertising + background scanning. Returns
  /// whether the peripheral manager was already powered on; the definitive
  /// advertising verdict arrives via [onAdvertisingState].
  Future<bool> start(List<Map<String, Object>> slots) async {
    try {
      final ok = await _channel.invokeMethod<bool>('start', slots);
      return ok ?? false;
    } catch (e) {
      debugPrint('BackgroundBeacon start failed: $e');
      return false;
    }
  }

  Future<void> updateBatch(List<Map<String, Object>> slots) async {
    try {
      await _channel.invokeMethod<void>('updateBatch', slots);
    } catch (e) {
      debugPrint('BackgroundBeacon updateBatch failed: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (e) {
      debugPrint('BackgroundBeacon stop failed: $e');
    }
  }
}
