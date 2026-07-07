import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:in_range/core/network/supabase_client.dart';

/// BeaconService
/// Responsible for:
/// - Managing beacon ON/OFF
/// - Generating/rotating ephemeral tokens (see docs/ephemeral-token-spec.md)
/// - Advertising (flutter_ble_peripheral)
/// - Scanning + collecting sightings (flutter_blue_plus)
/// - Uploading via RPCs: claim_token, record_sighting
///
/// IMPORTANT (2026 research):
/// - On Android this must run inside a Foreground Service with persistent notification.
/// - Background BLE/GPS is best-effort only. Design UI accordingly.
/// - Use adaptive scanning to save battery.
class BeaconService {
  bool _isOn = false;
  String? _currentToken;
  DateTime? _tokenExpiresAt;

  Future<void> turnOnBeacon({required String rangeType}) async {
    // TODO: request/check permissions (permission_handler)
    // TODO: start foreground service on Android

    _isOn = true;
    await _generateAndClaimNewToken(rangeType: rangeType);

    // Start BLE advertising + scanning
    // await _startAdvertising();
    // FlutterBluePlus.startScan(...);

    // Start periodic location + sighting upload loop
    // _startSightingLoop();
  }

  Future<void> turnOffBeacon() async {
    _isOn = false;
    // Stop advertising, scanning, services
    // Invalidate token on server if desired
  }

  Future<void> _generateAndClaimNewToken({required String rangeType}) async {
    // 1. Generate token per ephemeral-token-spec.md
    _currentToken = _generateEphemeralToken();
    _tokenExpiresAt = DateTime.now().add(const Duration(minutes: 15));

    // 2. Get coarse location
    final position = await Geolocator.getCurrentPosition();
    
    // 3. Call Supabase RPC
    await InRangeSupabase.client.rpc('claim_token', params: {
      'p_token': _currentToken,
      'p_valid_until': _tokenExpiresAt!.toIso8601String(),
      'p_lat': position.latitude,
      'p_lon': position.longitude,
      'p_range': rangeType,   // must match enum in DB
    });
  }

  String _generateEphemeralToken() {
    // TODO: implement real format from docs/ephemeral-token-spec.md
    // Use secure random + epoch + hmac
    return 'demo-${DateTime.now().millisecondsSinceEpoch}';
  }

  // TODO: implement recordSighting batch upload
  // TODO: integrate flutter_ble_peripheral for advertising
  // TODO: listen to scan results and call record_sighting RPC
}
