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

  /// Fresh foreign sighting from the native module (token hex, RSSI).
  void Function(String tokenHex, int rssi)? onSighting;

  /// Native advertising state — feeds the fail-closed `_discoverable` rule.
  void Function(bool advertising)? onAdvertisingState;

  Future<dynamic> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'onSighting':
        final args = call.arguments;
        if (args is Map) {
          final token = args['token'], rssi = args['rssi'];
          if (token is String && token.length == 32 && rssi is int) {
            onSighting?.call(token, rssi);
          }
        }
      case 'onAdvertisingState':
        final args = call.arguments;
        if (args is bool) onAdvertisingState?.call(args);
    }
    return null;
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
