import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Opportunistic connected-BSSID sampling for iOS venue corroboration.
///
/// iOS has no API to scan nearby Wi-Fi access points, but on a device with the
/// Access WiFi Information entitlement and precise location authorization it
/// can read the currently-associated BSSID/SSID. This is not a fingerprint and
/// it does not wake the app; it is sampled only when another callback (BLE,
/// location, or foreground) already provides runtime.
///
/// The raw BSSID is hashed with the same rotating salt as the Android venue
/// matcher before it is ever uploaded or compared.
class WifiAssist {
  static const MethodChannel _channel =
      MethodChannel('io.inrange.app/wifi_assist');

  /// Returns the current connected BSSID/SSID, or null if unavailable.
  ///
  /// Expected reasons for null:
  /// - not on iOS
  /// - Access WiFi Information entitlement not enabled
  /// - precise location authorization not granted
  /// - not currently associated to a Wi-Fi network
  /// - channel not yet implemented on this platform
  static Future<WifiBssidResult?> currentBSSID() async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('currentBSSID');
      if (raw == null) return null;
      final bssid = raw['bssid'] as String?;
      final ssid = raw['ssid'] as String?;
      if (bssid == null || bssid.isEmpty) return null;
      return WifiBssidResult(bssid: bssid, ssid: ssid ?? '');
    } on MissingPluginException {
      // Android branch or an iOS build predating the native handler.
      return null;
    } catch (e) {
      debugPrint('WifiAssist currentBSSID failed: $e');
      return null;
    }
  }
}

class WifiBssidResult {
  const WifiBssidResult({required this.bssid, required this.ssid});

  /// Raw BSSID — hash before it leaves the device.
  final String bssid;

  /// SSID of the current network.
  final String ssid;
}
