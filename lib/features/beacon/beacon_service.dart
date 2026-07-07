import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:in_range/core/network/supabase_client.dart';
import 'package:in_range/features/beacon/ephemeral_token_generator.dart';

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
  BeaconService({
    required String userIdSecret,
    required String hmacSecret,
    Duration rotationWindow = const Duration(minutes: 15),
  }) : _tokenGenerator = EphemeralTokenGenerator(
          userIdSecret: userIdSecret,
          hmacSecret: hmacSecret,
          rotationWindow: rotationWindow,
        );

  final EphemeralTokenGenerator _tokenGenerator;

  bool _isOn = false;
  bool get isOn => _isOn;

  EphemeralToken? _currentToken;
  EphemeralToken? get currentToken => _currentToken;

  Timer? _rotationTimer;
  Timer? _sightingFlushTimer;

  /// Observed tokens (from BLE scan) buffered for batch upload.
  final List<SightingRecord> _pendingSightings = [];

  /// Turns the beacon on for the given range ('feet' or 'miles').
  /// Throws if permissions or location are unavailable.
  Future<void> turnOnBeacon({required String rangeType}) async {
    if (_isOn) return;
    _isOn = true;

    await _refreshClaim(rangeType: rangeType);

    // Rotate the token shortly before each epoch boundary.
    // We poll every 60s because Timer granularity + doze can drift; cheap.
    _rotationTimer?.cancel();
    _rotationTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!_isOn) return;
      if (_tokenGenerator.shouldRotate(_currentToken)) {
        _refreshClaim(rangeType: rangeType);
      }
    });

    // Batch-flush sightings every 30s while beacon is ON.
    _sightingFlushTimer?.cancel();
    _sightingFlushTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_isOn) return;
      _flushSightings();
    });

    // TODO: start foreground service on Android
    // TODO: _startAdvertising(currentToken)
    // TODO: FlutterBluePlus.startScan(withServices: [InRangeServiceUuid])
  }

  Future<void> turnOffBeacon() async {
    _isOn = false;
    _rotationTimer?.cancel();
    _rotationTimer = null;
    _sightingFlushTimer?.cancel();
    _sightingFlushTimer = null;

    // Flush any remaining sightings before shutting down.
    await _flushSightings();

    // Stop advertising, scanning, services
    // await FlutterBluePlus.stopScan();
    // await _stopAdvertising();

    // Token naturally expires; server-side claim will time out.
    _currentToken = null;
  }

  /// Generates a fresh token and calls `claim_token` on the server.
  Future<void> _refreshClaim({required String rangeType}) async {
    final token = _tokenGenerator.generate();
    _currentToken = token;

    final position = await _coarsePosition();

    try {
      await InRangeSupabase.client.rpc('claim_token', params: {
        'p_token': token.token,
        'p_valid_until': token.expiresAt.toUtc().toIso8601String(),
        'p_lat': position?.latitude,
        'p_lon': position?.longitude,
        'p_range': rangeType,
      });
    } catch (e) {
      // Claim failed — keep the token locally so we can retry on the next
      // rotation tick. Server will reject sightings against unclaimed tokens.
      // TODO: surface to UI as 'degraded mode'.
      _currentToken = null;
      rethrow;
    }
  }

  /// Called by the BLE scan callback when another device's advertisement
  /// is observed. Buffers the sighting for batched upload.
  void observeSighting({
    required String observedToken,
    required int rssi,
    String? rangeType,
  }) {
    if (!_isOn) return;
    _pendingSightings.add(SightingRecord(
      observedToken: observedToken,
      rssi: rssi,
      observedAt: DateTime.now().toUtc(),
      observerLat: null, // populated at flush time from current position
      observerLon: null,
      rangeType: rangeType ?? 'feet',
    ));
  }

  Future<void> _flushSightings() async {
    if (_pendingSightings.isEmpty) return;
    final position = await _coarsePosition();
    final batch = List<SightingRecord>.from(_pendingSightings);
    _pendingSightings.clear();

    for (final s in batch) {
      try {
        await InRangeSupabase.client.rpc('record_sighting', params: {
          'p_observed_token': s.observedToken,
          'p_rssi': s.rssi,
          'p_observed_at': s.observedAt.toIso8601String(),
          'p_lat': position?.latitude,
          'p_lon': position?.longitude,
          'p_range': s.rangeType,
        });
      } catch (_) {
        // Re-queue on failure; bounded by beacon session lifetime.
        if (_pendingSightings.length < 500) {
          _pendingSightings.add(s);
        }
      }
    }
  }

  Future<Position?> _coarsePosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;
      // NOTE: permission must be requested upstream by the UI layer via
      // permission_handler before turning the beacon on.
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 5),
        ),
      );
    } catch (_) {
      return null;
    }
  }
}

/// A locally-buffered sighting awaiting upload.
class SightingRecord {
  const SightingRecord({
    required this.observedToken,
    required this.rssi,
    required this.observedAt,
    required this.observerLat,
    required this.observerLon,
    required this.rangeType,
  });

  final String observedToken;
  final int rssi;
  final DateTime observedAt;
  final double? observerLat;
  final double? observerLon;
  final String rangeType;
}
