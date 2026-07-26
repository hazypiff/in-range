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
  ///
  /// [onFailure] receives the native failure code for every OTHER failure, so a
  /// caller can bucket outcomes instead of guessing. Until 2026-07-26 this
  /// wrapper collapsed every non-`no_service` PlatformException into `null` +
  /// a debugPrint, so W2's outcome histogram could only ever report `failed`
  /// while GattTokenReader.kt was already distinguishing six causes
  /// (`bad_args` :46, `bt_off` :51, `connect_failed` :80/:83/:89/:138/:147,
  /// `read_failed` :98/:125, `timeout` :142, `no_permission` :145). "Which
  /// outcome dominates" is exactly the question outcome-aware backoff (finding
  /// 1.7) is frozen pending, and the codes were only in logcat.
  ///
  /// The return contract is UNCHANGED — still null on every failure — so this is
  /// additive: an existing caller that passes neither callback behaves as before.
  static Future<Uint8List?> readToken(
    String mac, {
    required String serviceUuid,
    required String charUuid,
    Duration timeout = const Duration(seconds: 10),
    void Function()? onStranger,
    void Function(String code)? onFailure,
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
        // Native code verbatim — do NOT remap. The point is that the caller
        // sees the same six buckets the Kotlin side already separates.
        onFailure?.call(e.code);
        debugPrint('W3 native GATT read failed ($mac): ${e.code} ${e.message}');
      }
      return null;
    } catch (e) {
      // MissingPluginException (no native module — iOS, tests) and channel
      // marshalling errors land here. Distinct bucket: attributing these to a
      // radio failure would make the histogram lie about the radio.
      onFailure?.call('channel_error');
      debugPrint('W3 native GATT read failed ($mac): $e');
      return null;
    }
  }
}
