import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:in_range/core/config/app_config.dart';
import 'package:in_range/core/network/supabase_client.dart';
import 'package:in_range/features/beacon/ephemeral_token_generator.dart';

/// Called when we observe another In Range beacon (throttled).
typedef SightingCallback = void Function({
  required String correlationId,
  required int rssi,
  required String rangeType,
});

/// BeaconService — BLE advertise + scan + optional server upload.
///
/// Stability notes (Galaxy S9 Android 10 dual-phone tests):
/// - Unfiltered continuous scan + dual Flutter engines (FGS) was ballooning
///   memory (~160MB Unknown) and flooding the main isolate → LMK/jank.
/// - We throttle sightings, use balanced scan/advertise, skip FGS unless
///   `INRANGE_ENABLE_FGS=true`, and skip network when Supabase is placeholder.
class BeaconService {
  BeaconService({
    required String userIdSecret,
    required String userId,
    required String hmacSecret,
    Duration rotationWindow = const Duration(minutes: 15),
    this.onSighting,
  })  : _tokenGenerator = EphemeralTokenGenerator(
          userIdSecret: userIdSecret,
          userId: userId,
          hmacSecret: hmacSecret,
          rotationWindow: rotationWindow,
        ),
        _userId = userId,
        _correlationSalt = hmacSecret;

  final EphemeralTokenGenerator _tokenGenerator;
  final String _userId;
  final String _correlationSalt;

  /// Optional hook for local encounter store / UI.
  SightingCallback? onSighting;

  bool _isOn = false;
  bool get isOn => _isOn;
  bool _cloudClaimed = false;
  bool get cloudClaimed => _cloudClaimed;

  EphemeralToken? _currentToken;
  EphemeralToken? get currentToken => _currentToken;

  Uint8List? _currentCorrelationId;
  Uint8List? get currentCorrelationId => _currentCorrelationId;

  Timer? _rotationTimer;
  Timer? _sightingFlushTimer;
  Timer? _scanRestartTimer;
  StreamSubscription<List<ScanResult>>? _scanSub;

  /// One buffered row per corr id (keeps best RSSI).
  final Map<String, SightingRecord> _pendingByCorr = {};
  static const int _maxPendingSightings = 500;

  Future<void> turnOnBeacon({required String rangeType}) async {
    if (_isOn) return;
    if (!AppConfig.hasCryptoSecrets) {
      debugPrint(
        'Beacon refused: INRANGE_HMAC_SECRET / INRANGE_USER_ID_SECRET missing. '
        'Set these in .env — no hardcoded fallback is shipped.',
      );
      throw StateError('Missing crypto secrets; cannot start beacon.');
    }
    if (_userId.trim().isEmpty) {
      throw StateError('Sign in before starting the beacon.');
    }
    _currentRangeType = rangeType;

    try {
      await _refreshClaim(rangeType: rangeType);
      await _startAdvertising();
      await _startScanning();
      _isOn = true;
    } catch (e) {
      await _stopBle();
      _currentToken = null;
      _currentCorrelationId = null;
      _currentRangeType = null;
      rethrow;
    }

    _rotationTimer?.cancel();
    _rotationTimer = Timer.periodic(const Duration(seconds: 90), (_) {
      if (!_isOn) return;
      if (_tokenGenerator.shouldRotate(_currentToken)) {
        unawaited(_rotateToken(rangeType));
      }
    });

    _sightingFlushTimer?.cancel();
    _sightingFlushTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!_isOn) return;
      _flushSightings();
    });
    _scanRestartTimer?.cancel();
    _scanRestartTimer = Timer.periodic(const Duration(minutes: 55), (_) {
      if (_isOn) unawaited(_restartScanning());
    });
    // Zombie-scanner watchdog: field test 2026-07-13 — a beacon reported ON
    // but yielded zero scan results for the whole walk. If the scanner goes
    // silent, restart it (also flushes the stack's stale-advert cache).
    _lastForeignScanAt = DateTime.now();
    _scanWatchdogTimer?.cancel();
    _scanWatchdogTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (!_isOn) return;
      final last = _lastForeignScanAt;
      if (last == null ||
          DateTime.now().difference(last) > const Duration(minutes: 3)) {
        debugPrint('Scan watchdog: no foreign adverts ≥3min — restarting scan');
        unawaited(_restartScanning());
      }
    });

    if (AppConfig.enableForegroundService) {
      try {
        final service = FlutterBackgroundService();
        final running = await service.isRunning();
        if (!running) {
          await service.startService();
        }
        service.invoke('setAsForeground');
        service.invoke(
          'setBeaconActive',
          {'active': true, 'range': rangeType},
        );
      } catch (e) {
        debugPrint('Foreground service start skipped or failed: $e');
      }
    } else {
      debugPrint(
          'FGS disabled (INRANGE_ENABLE_FGS=false) — foreground BLE only');
    }
  }

  Future<void> turnOffBeacon() async {
    _isOn = false;
    _rotationTimer?.cancel();
    _rotationTimer = null;
    _sightingFlushTimer?.cancel();
    _sightingFlushTimer = null;
    _scanRestartTimer?.cancel();
    _scanRestartTimer = null;
    _scanWatchdogTimer?.cancel();
    _scanWatchdogTimer = null;
    _locationRefreshTimer?.cancel();
    _locationRefreshTimer = null;
    await _flushSightings();
    await _releaseClaim();
    await _stopBle();

    if (AppConfig.enableForegroundService) {
      try {
        final service = FlutterBackgroundService();
        service.invoke('setBeaconActive', {'active': false});
        service.invoke('stopService');
      } catch (e) {
        debugPrint('Foreground service stop failed: $e');
      }
    }

    _lastSightingAt.clear();
    _pendingByCorr.clear();
    _currentToken = null;
    _currentCorrelationId = null;
    _currentRangeType = null;
    _cloudClaimed = false;
  }

  Future<void> _rotateToken(String rangeType) async {
    try {
      await _refreshClaim(rangeType: rangeType);
      if (_isOn) await _startAdvertising();
    } catch (e) {
      debugPrint('Token rotation failed; stopping beacon: $e');
      await turnOffBeacon();
    }
  }

  Future<void> _restartScanning() async {
    try {
      await _startScanning();
    } catch (e) {
      debugPrint('BLE scan restart failed: $e');
    }
  }

  Future<void> _stopBle() async {
    await _scanSub?.cancel();
    _scanSub = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      debugPrint('BLE scan stop failed: $e');
    }
    try {
      await FlutterBlePeripheral().stop();
    } catch (e) {
      debugPrint('BLE advertising stop failed: $e');
    }
  }

  // --- BLE Implementation ---

  static const String _inRangeServiceUuid =
      '0000cafe-0000-1000-8000-00805f9b34fb';
  static const int _inRangeManufacturerId = 0xFFFF;

  Uint8List _deriveCorrelationId(String token) {
    final hmac = Hmac(sha256, utf8.encode(_correlationSalt));
    final digest = hmac.convert(utf8.encode(token));
    return Uint8List.fromList(digest.bytes.sublist(0, 16));
  }

  Future<void> _startAdvertising() async {
    if (_currentToken == null || _currentCorrelationId == null) {
      throw StateError('No beacon token is available');
    }

    final peripheral = FlutterBlePeripheral();
    // Legacy payload only: mfg id + 16-byte corr (fits 31-byte AD).
    final advertiseData = AdvertiseData(
      manufacturerId: _inRangeManufacturerId,
      manufacturerData: _currentCorrelationId!,
      includeDeviceName: false,
    );

    // Balanced mode — lowLatency was aggressive on S9 dual-phone tests.
    final settings = AdvertiseSettings(
      advertiseSet: false,
      connectable: false,
      timeout: 0,
      advertiseMode: AdvertiseMode.advertiseModeBalanced,
      txPowerLevel: AdvertiseTxPower.advertiseTxPowerMedium,
    );

    final supported = await peripheral.isSupported;
    if (!supported) {
      throw StateError('BLE advertising is not supported on this device');
    }
    final btOn = await peripheral.isBluetoothOn;
    if (!btOn) {
      throw StateError('Bluetooth is off');
    }
    try {
      try {
        if (await peripheral.isAdvertising) {
          await peripheral.stop();
        }
      } catch (e) {
        debugPrint('Existing advertisement stop failed: $e');
      }

      await peripheral.start(
        advertiseData: advertiseData,
        advertiseSettings: settings,
      );
      debugPrint('Started BLE advertising');
    } catch (e) {
      debugPrint('Advertising start failed: $e');
      try {
        await peripheral.start(
          advertiseData: advertiseData,
          advertiseSettings: AdvertiseSettings(
            advertiseSet: true,
            connectable: false,
            timeout: 0,
            advertiseMode: AdvertiseMode.advertiseModeBalanced,
            txPowerLevel: AdvertiseTxPower.advertiseTxPowerMedium,
          ),
          advertiseSetParameters: AdvertiseSetParameters(
            connectable: false,
            legacyMode: true,
            scannable: true,
            txPowerLevel: txPowerHigh,
            interval: intervalHigh,
          ),
        );
        debugPrint('Started BLE advertising (set+legacy fallback)');
      } catch (e2) {
        debugPrint('Advertising fallback also failed: $e2');
        throw StateError('Could not start BLE advertising');
      }
    }
  }

  Future<void> _startScanning() async {
    await _scanSub?.cancel();
    _scanSub = null;

    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      debugPrint('Pre-scan stop failed: $e');
    }

    _scanSub = FlutterBluePlus.scanResults.listen(
      _onScanResults,
      onError: (e) {
        debugPrint('BLE scan stream error: $e');
        if (_isOn) unawaited(_restartScanning());
      },
    );

    // Balanced + continuousDivisor cuts main-isolate flood on S9.
    await FlutterBluePlus.startScan(
      timeout: const Duration(hours: 1),
      androidUsesFineLocation: true,
      continuousUpdates: true,
      continuousDivisor: 5,
      androidScanMode: AndroidScanMode.balanced,
    );
    debugPrint('BLE scan started (balanced, divisor=5)');
  }

  /// Every correlation id we've ever advertised this process — self-sighting guard.
  final Set<String> _ownCorrHexes = {};
  DateTime? _lastForeignScanAt;
  Timer? _scanWatchdogTimer;

  void _onScanResults(List<ScanResult> results) {
    if (!_isOn) return;
    for (final r in results) {
      final adv = r.advertisementData;
      Uint8List? observedCorrelationId;

      if (adv.manufacturerData.isNotEmpty) {
        final bytes = adv.manufacturerData[_inRangeManufacturerId];
        if (bytes != null && bytes.length == 16) {
          observedCorrelationId = Uint8List.fromList(bytes);
        }
      }

      if (observedCorrelationId == null && adv.serviceData.isNotEmpty) {
        final Guid inRangeGuid = Guid(_inRangeServiceUuid);
        final bytes = adv.serviceData[inRangeGuid];
        if (bytes != null && bytes.length == 16) {
          observedCorrelationId = Uint8List.fromList(bytes);
        }
      }

      if (observedCorrelationId == null) continue;

      final hexId = observedCorrelationId
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();

      // Filter ALL of our own tokens, not just the current one — a leaked
      // advertiser from a prior beacon session kept broadcasting the OLD
      // token after off→on, and we self-sighted it at a rock-constant RSSI
      // for an entire field test (2026-07-13 walk).
      if (_ownCorrHexes.contains(hexId)) continue;

      _lastForeignScanAt = DateTime.now();
      _recordLocalSighting(hexId, r.rssi);
    }
  }

  double? _cachedLat;
  double? _cachedLon;
  DateTime? _cachedLocAt;
  Timer? _locationRefreshTimer;

  final Map<String, DateTime> _lastSightingAt = {};
  static const _sightingMinInterval = Duration(seconds: 5);

  void _recordLocalSighting(String observedCorrelationIdHex, int rssi) {
    final now = DateTime.now();
    final last = _lastSightingAt[observedCorrelationIdHex];
    if (last != null && now.difference(last) < _sightingMinInterval) {
      return;
    }
    _lastSightingAt[observedCorrelationIdHex] = now;
    if (_lastSightingAt.length > 1000) {
      _lastSightingAt.removeWhere(
        (_, at) => now.difference(at) > const Duration(minutes: 10),
      );
      while (_lastSightingAt.length > 1000) {
        _lastSightingAt.remove(_lastSightingAt.keys.first);
      }
    }

    _ensureLocationCache();

    final range = _currentRangeType ?? 'feet_10';
    final record = SightingRecord(
      observedToken: observedCorrelationIdHex,
      rssi: rssi,
      observerLat: _cachedLat,
      observerLon: _cachedLon,
      observedAt: now,
      rangeType: range,
    );

    // Keep one pending row per corr (best RSSI).
    final prev = _pendingByCorr[observedCorrelationIdHex];
    if (prev == null && _pendingByCorr.length >= _maxPendingSightings) {
      _pendingByCorr.remove(_pendingByCorr.keys.first);
    }
    _pendingByCorr[observedCorrelationIdHex] = SightingRecord(
      observedToken: record.observedToken,
      rssi: prev == null ? rssi : (rssi > prev.rssi ? rssi : prev.rssi),
      observerLat: record.observerLat,
      observerLon: record.observerLon,
      observedAt: record.observedAt,
      rangeType: record.rangeType,
    );

    debugPrint(
        'Sighting observed rssi=$rssi (tracked=${_pendingByCorr.length})');

    // Local encounter store (instant or delayed reveal).
    try {
      onSighting?.call(
        correlationId: observedCorrelationIdHex,
        rssi: rssi,
        rangeType: range,
      );
    } catch (e) {
      debugPrint('onSighting callback error: $e');
    }
  }

  void _ensureLocationCache() {
    final stale = _cachedLocAt == null ||
        DateTime.now().difference(_cachedLocAt!) > const Duration(seconds: 120);
    if (!stale) return;
    if (_locationRefreshTimer != null) return;
    _locationRefreshTimer = Timer(Duration.zero, () async {
      try {
        Position? pos = await Geolocator.getLastKnownPosition();
        if (pos == null || !_isFreshPosition(pos)) {
          pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low,
              timeLimit: Duration(seconds: 6),
            ),
          );
        }
        _cachedLat = pos.latitude;
        _cachedLon = pos.longitude;
        _cachedLocAt = DateTime.now();
      } catch (e) {
        debugPrint('Location cache refresh failed: $e');
      } finally {
        _locationRefreshTimer = null;
      }
    });
  }

  String? _currentRangeType;

  Future<void> _flushSightings() async {
    if (_pendingByCorr.isEmpty) return;
    if (!AppConfig.hasRealSupabase) {
      // Keep local rows; no network thrash against placeholder host.
      return;
    }

    final toSend = List<SightingRecord>.from(_pendingByCorr.values);

    for (final s in toSend) {
      if (s.observerLat == null || s.observerLon == null) continue;
      try {
        // Named args match migration signatures (lat/lon required before optionals).
        await InRangeSupabase.client.rpc('record_sighting', params: {
          'p_observed_token':
              s.observedToken, // correlation-id hex (matches claim)
          'p_lat': s.observerLat,
          'p_lon': s.observerLon,
          'p_rssi': s.rssi,
          'p_observed_at': s.observedAt.toUtc().toIso8601String(),
          'p_range': _mapUiRangeToDb(s.rangeType),
        });
        debugPrint('record_sighting OK rssi=${s.rssi}');
        if (identical(_pendingByCorr[s.observedToken], s)) {
          _pendingByCorr.remove(s.observedToken);
        }
      } catch (e) {
        debugPrint('Sighting upload failed: $e');
        // Retain for a later bounded retry; the queue is capped above.
      }
    }
  }

  Future<void> _refreshClaim({required String rangeType}) async {
    _currentToken = _tokenGenerator.generate();
    _currentCorrelationId = _deriveCorrelationId(_currentToken!.token);
    // Remember every token we advertise so the scanner never self-sights a
    // stale one (leaked advertiser after off→on). Bounded to stay tiny.
    _ownCorrHexes.add(_currentCorrelationId!
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join());
    if (_ownCorrHexes.length > 16) {
      _ownCorrHexes.remove(_ownCorrHexes.first);
    }

    double? lat = _cachedLat;
    double? lon = _cachedLon;
    if (lat == null) {
      try {
        Position? position = await Geolocator.getLastKnownPosition();
        if (position == null || !_isFreshPosition(position)) {
          position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low,
              timeLimit: Duration(seconds: 5),
            ),
          );
        }
        lat = position.latitude;
        lon = position.longitude;
        _cachedLat = lat;
        _cachedLon = lon;
        _cachedLocAt = DateTime.now();
      } catch (e) {
        debugPrint('Geolocator failed at claim time: $e');
      }
    }

    if (!AppConfig.hasRealSupabase) {
      _cloudClaimed = false;
      debugPrint('claim_token skipped (no real Supabase — local BLE mode)');
      return;
    }

    final dbRange = _mapUiRangeToDb(rangeType);
    // Peers only observe the 16-byte correlation id over BLE — claim THAT
    // hex string so record_sighting / correlate_encounter can match.
    final claimToken = _currentCorrelationId!
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    try {
      // Always send UTC — local DateTime without offset is misread as UTC by Postgres
      // and expires claims hours early (broke feet correlation after first flush).
      final validUntil = _currentToken!.expiresAt.toUtc();
      // Two-minute transport grace, bounded by the server's 21-minute maximum.
      final until = validUntil.add(const Duration(minutes: 2));
      await InRangeSupabase.client.rpc('claim_token', params: {
        'p_token': claimToken,
        'p_valid_until': until.toIso8601String(),
        'p_lat': lat,
        'p_lon': lon,
        'p_range': dbRange,
      });
      _cloudClaimed = true;
      debugPrint(
        'claim_token OK range=$dbRange until=${until.toIso8601String()}',
      );
    } catch (e) {
      _cloudClaimed = false;
      debugPrint('claim_token RPC failed (continuing local BLE): $e');
    }
  }

  bool _isFreshPosition(Position position) {
    final age = DateTime.now().difference(position.timestamp).abs();
    return age <= const Duration(minutes: 2);
  }

  Future<void> _releaseClaim() async {
    _cloudClaimed = false;
    if (!AppConfig.hasRealSupabase) return;
    try {
      await InRangeSupabase.client.rpc('release_token');
    } catch (e) {
      debugPrint('release_token failed: $e');
    }
  }

  String _mapUiRangeToDb(String uiRange) {
    if (uiRange == 'feet') return 'feet_10';
    if (uiRange == 'miles') return 'miles_10';
    return uiRange;
  }
}

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
