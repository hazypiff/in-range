import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dart side of the native W3 GATT token read (GattTokenReader.kt).
///
/// The app's only BLE connect path — native BluetoothGatt instead of
/// flutter_blue_plus.connect(), which is license-gated for commercial use.
/// All policy (backoff, cache, keepalive cadence) stays in BeaconService;
/// this is just the radio round-trip.
class NativeGattTokenReader {
  static const _channel = MethodChannel('io.inrange.app/gatt');

  /// Reads the 16-byte token characteristic from [mac]. Returns the bytes,
  /// or null on any failure. [onStranger] fires when the peer is connectable
  /// but hosts no In Range service (a stranger's backgrounded iPhone) — the
  /// caller uses it to log/back off differently from transient failures.
  static Future<Uint8List?> readToken(
    String mac, {
    required String serviceUuid,
    required String charUuid,
    Duration timeout = const Duration(seconds: 10),
    void Function()? onStranger,
  }) async {
    try {
      final bytes = await _channel.invokeMethod<Uint8List>('readToken', {
        'mac': mac,
        'serviceUuid': serviceUuid,
        'charUuid': charUuid,
        'timeoutMs': timeout.inMilliseconds,
      });
      return bytes;
    } on PlatformException catch (e) {
      if (e.code == 'no_service') {
        onStranger?.call();
      } else {
        debugPrint('W3 native GATT read failed ($mac): ${e.code} ${e.message}');
      }
      return null;
    } catch (e) {
      debugPrint('W3 native GATT read failed ($mac): $e');
      return null;
    }
  }
}
