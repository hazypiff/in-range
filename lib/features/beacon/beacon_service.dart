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
    required String hmacSecret,
    Duration rotationWindow = const Duration(minutes: 15),
    this.onSighting,
  })  : _tokenGenerator = EphemeralTokenGenerator(
          userIdSecret: userIdSecret,
          hmacSecret: hmacSecret,
          rotationWindow: rotationWindow,
        ),
        _correlationSalt = hmacSecret;

  final EphemeralTokenGenerator _tokenGenerator;
  final String _correlationSalt;

  /// Optional hook for local encounter store / UI.
  SightingCallback? onSighting;

  bool _isOn = false;
  bool get isOn => _isOn;

  EphemeralToken? _currentToken;
  EphemeralToken? get currentToken => _currentToken;

  Uint8List? _currentCorrelationId;
  Uint8List? get currentCorrelationId => _currentCorrelationId;

  Timer? _rotationTimer;
  Timer? _sightingFlushTimer;
  StreamSubscription<List<ScanResult>>? _scanSub;

  final List<SightingRecord> _pendingSightings = [];
  /// One buffered row per corr id (keeps best RSSI).
  final Map<String, SightingRecord> _pendingByCorr = {};

  Future<void> turnOnBeacon({required String rangeType}) async {
    if (_isOn) return;
    if (!AppConfig.hasCryptoSecrets) {
      debugPrint(
        'Beacon refused: INRANGE_HMAC_SECRET / INRANGE_USER_ID_SECRET missing. '
        'Set these in .env — no hardcoded fallback is shipped.',
      );
      throw StateError('Missing crypto secrets; cannot start beacon.');
    }
    _isOn = true;
    _currentRangeType = rangeType;

    await _refreshClaim(rangeType: rangeType);

    _rotationTimer?.cancel();
    _rotationTimer = Timer.periodic(const Duration(seconds: 90), (_) {
      if (!_isOn) return;
      if (_tokenGenerator.shouldRotate(_currentToken)) {
        _refreshClaim(rangeType: rangeType).then((_) {
          if (_isOn) _startAdvertising();
        });
      }
    });

    _sightingFlushTimer?.cancel();
    _sightingFlushTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!_isOn) return;
      _flushSightings();
    });

    await _startAdvertising();
    await _startScanning();

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
      debugPrint('FGS disabled (INRANGE_ENABLE_FGS=false) — foreground BLE only');
    }
  }

  Future<void> turnOffBeacon() async {
    _isOn = false;
    _rotationTimer?.cancel();
    _rotationTimer = null;
    _sightingFlushTimer?.cancel();
    _sightingFlushTimer = null;
    _locationRefreshTimer?.cancel();
    _locationRefreshTimer = null;
    _lastSightingAt.clear();
    _pendingByCorr.clear();

    await _scanSub?.cancel();
    _scanSub = null;

    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    try {
      final peripheral = FlutterBlePeripheral();
      await peripheral.stop();
    } catch (_) {}

    if (AppConfig.enableForegroundService) {
      try {
        final service = FlutterBackgroundService();
        service.invoke('setBeaconActive', {'active': false});
        service.invoke('stopService');
      } catch (_) {}
    }

    _pendingSightings.clear();
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
    if (_currentToken == null || _currentCorrelationId == null) return;

    final peripheral = FlutterBlePeripheral();
    final hexId = _currentCorrelationId!
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

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

    try {
      final supported = await peripheral.isSupported;
      if (!supported) {
        debugPrint('BLE peripheral advertising not supported on this device');
        return;
      }
      final btOn = await peripheral.isBluetoothOn;
      if (!btOn) {
        debugPrint('Bluetooth is off — cannot advertise');
        return;
      }
      try {
        if (await peripheral.isAdvertising) {
          await peripheral.stop();
        }
      } catch (_) {}

      await peripheral.start(
        advertiseData: advertiseData,
        advertiseSettings: settings,
      );
      debugPrint('Started BLE advertising correlationId (hex=$hexId)');
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
        debugPrint('Started BLE advertising (set+legacy fallback) hex=$hexId');
      } catch (e2) {
        debugPrint('Advertising fallback also failed: $e2');
      }
    }
  }

  Future<void> _startScanning() async {
    await _scanSub?.cancel();
    _scanSub = null;

    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    _scanSub = FlutterBluePlus.scanResults.listen(
      _onScanResults,
      onError: (e) => debugPrint('BLE scan stream error: $e'),
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

      final selfHex = _currentCorrelationId
          ?.map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      if (selfHex != null && hexId == selfHex) continue;

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
    if (prev == null || rssi > prev.rssi) {
      _pendingByCorr[observedCorrelationIdHex] = record;
    }

    debugPrint(
      'Sighting rssi=$rssi corr=$observedCorrelationIdHex '
      '(tracked=${_pendingByCorr.length})',
    );

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
        pos ??= await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 6),
          ),
        );
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
    _pendingByCorr.clear();

    for (final s in toSend) {
      try {
        // Named args match migration signatures (lat/lon required before optionals).
        await InRangeSupabase.client.rpc('record_sighting', params: {
          'p_observed_token': s.observedToken, // correlation-id hex (matches claim)
          'p_lat': s.observerLat ?? 0.0,
          'p_lon': s.observerLon ?? 0.0,
          'p_rssi': s.rssi,
          'p_observed_at': s.observedAt.toUtc().toIso8601String(),
          'p_range': _mapUiRangeToDb(s.rangeType),
        });
        debugPrint(
          'record_sighting OK corr=${s.observedToken.substring(0, 8)}… rssi=${s.rssi}',
        );
      } catch (e) {
        debugPrint('Sighting upload failed: $e');
        // Drop on failure — local store already has the encounter.
      }
    }
  }

  Future<void> _refreshClaim({required String rangeType}) async {
    _currentToken = _tokenGenerator.generate();
    _currentCorrelationId = _deriveCorrelationId(_currentToken!.token);

    double? lat = _cachedLat;
    double? lon = _cachedLon;
    if (lat == null) {
      try {
        final position = await Geolocator.getLastKnownPosition() ??
            await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.low,
                timeLimit: Duration(seconds: 5),
              ),
            );
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
      // Floor: at least 20 minutes from now so flush windows always hit active claims.
      final minUntil = DateTime.now().toUtc().add(const Duration(minutes: 20));
      final until =
          validUntil.isAfter(minUntil) ? validUntil : minUntil;
      await InRangeSupabase.client.rpc('claim_token', params: {
        'p_token': claimToken,
        'p_valid_until': until.toIso8601String(),
        'p_lat': lat,
        'p_lon': lon,
        'p_range': dbRange,
      });
      debugPrint(
        'claim_token OK corr=${claimToken.substring(0, 8)}… '
        'range=$dbRange until=${until.toIso8601String()}',
      );
    } catch (e) {
      debugPrint('claim_token RPC failed (continuing local BLE): $e');
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
