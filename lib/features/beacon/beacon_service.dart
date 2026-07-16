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
import 'package:in_range/features/beacon/claim_manager.dart';
import 'package:in_range/features/beacon/ephemeral_token_generator.dart';
import 'package:in_range/features/beacon/range_estimator.dart';
import 'package:in_range/features/beacon/wifi_scanner.dart';

/// Called when we observe another In Range beacon (throttled).
typedef SightingCallback = void Function({
  required String correlationId,
  required int rssi,
  required String rangeType,
  required String estimatedBand,
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
    this.onAdvertSample,
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

  /// Every foreign advert, unthrottled (unlike [onSighting]'s 5 s gate).
  /// Calibration needs the full RSSI stream, not sighting summaries.
  void Function(String correlationId, int rssi, AdvertPower power, DateTime at)?
      onAdvertSample;

  /// Fired whenever the service turns itself off internally (e.g. a failed
  /// token rotation) so the UI never shows a green beacon over dead BLE.
  void Function()? onBeaconStopped;

  /// Fired after every claim attempt AND every rotation so the UI reflects the
  /// CURRENT token expiry and cloud-claim state — not the first token's stale
  /// values (reviewer #11). cloudSynced is null when there is no cloud (local
  /// mode); true/false otherwise.
  void Function(DateTime? expiresAt, bool? cloudSynced)? onClaimStateChanged;

  /// Retryable claim upload (see ClaimManager). Reports cloud-sync state after
  /// every attempt so the UI can't show the first token's stale values.
  late final ClaimManager _claimMgr = ClaimManager(upload: _uploadClaim)
    ..onState = (synced) {
      _cloudClaimed = synced;
      onClaimStateChanged?.call(_currentToken?.expiresAt, synced);
    };

  String? _claimRangeType;

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
  Timer? _advPowerTimer;
  StreamSubscription<List<ScanResult>>? _scanSub;

  /// Calibrated 10/30/60 ft classifier fed by every fresh foreign advert.
  final RangeEstimator rangeEstimator = RangeEstimator();

  /// WiFi venue layer: resolves BLE's core ambiguity (a weak signal is either
  /// "far" or "close but body-blocked" — only a second radio can tell).
  ///
  /// Calibration walks poll every 30s — the fastest Android's scan throttle
  /// allows (4 per 2 min) — so a 90-second stop yields ~3 fingerprints instead
  /// of one. Production stays at 60s: a venue changes on the scale of minutes,
  /// and WiFi shares the 2.4GHz antenna with the BLE scanner that matters more.
  final WifiScanner wifiScanner = WifiScanner(
    scanInterval: AppConfig.calibScanMode
        ? const Duration(seconds: 30)
        : const Duration(seconds: 60),
  );

  /// Our latest WiFi fingerprint, hashed for upload/comparison.
  Map<String, int>? _wifiFingerprint;
  Map<String, int>? get wifiFingerprint => _wifiFingerprint;

  /// Dual-power advertising: mostly high TX for range, periodic medium
  /// slots as the physical mid-distance gate (see RangeEstimator).
  AdvertPower _advPower = AdvertPower.high;
  int _advTick = 0;

  /// Serializes every advertising start/stop. Concurrent restarts (power
  /// timer vs token rotation vs turn-off) orphan Android advertisements —
  /// the plugin swaps its callback on each start and Android stops by
  /// callback identity, so an interleaved start can never be stopped again.
  Future<void> _advOpChain = Future.value();

  /// False the moment turnOffBeacon begins: queued advertising starts
  /// no-op instead of resurrecting a stale advertiser after stop.
  bool _advertisingWanted = false;

  /// Same guard for the scan path: the 25-min restart timer, 15-min watchdog,
  /// and stream onError all fire `_restartScanning`, which without
  /// serialization can overwrite `_scanSub` (leaking a listener) or start a
  /// fresh 1-hour hardware scan after teardown (reviewer #4).
  Future<void> _scanOpChain = Future.value();
  bool _scanningWanted = false;

  Future<T> _serialScanOp<T>(Future<T> Function() op) {
    final run = _scanOpChain.then((_) => op());
    _scanOpChain = run.then((_) {}, onError: (_) {});
    return run;
  }

  /// Bumped on every turn-on/off. In-flight async work (rotation, claims)
  /// compares its captured generation and aborts if the session changed.
  int _sessionGeneration = 0;

  Future<T> _serialAdvOp<T>(Future<T> Function() op) {
    final run = _advOpChain.then((_) => op());
    _advOpChain = run.then((_) {}, onError: (_) {});
    return run;
  }

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
    final gen = ++_sessionGeneration;
    _scanningWanted = true;
    _advertisingWanted = true;

    try {
      await _refreshClaim(rangeType: rangeType);
      // A turnOffBeacon (account pause / provider disposal) can land during any
      // of these awaits, bump the generation, and stop BLE. If so, abort before
      // we publish _isOn or install timers — otherwise startup resurrects a
      // stopped service (reviewer #3).
      if (gen != _sessionGeneration) throw StateError('beacon turned off');
      await _startAdvertising();
      if (gen != _sessionGeneration) throw StateError('beacon turned off');
      await _startScanning();
      if (gen != _sessionGeneration) throw StateError('beacon turned off');
      _isOn = true;
    } catch (e) {
      if (gen == _sessionGeneration) {
        _advertisingWanted = false;
        _scanningWanted = false;
        await _stopBle();
        _currentToken = null;
        _currentCorrelationId = null;
        _currentRangeType = null;
      }
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
    // MUST be < 30 min: Android silently downgrades SCAN_MODE_LOW_LATENCY to
    // SCAN_MODE_OPPORTUNISTIC after 30 minutes of continuous scanning, and an
    // opportunistic scanner only piggybacks on other apps' scans — it looks
    // exactly like a dead radio. At the old 55-minute restart we were demoted
    // for roughly half of every hour (research/ble-radio-optimization.md).
    _scanRestartTimer = Timer.periodic(const Duration(minutes: 25), (_) {
      if (_isOn) unawaited(_restartScanning());
    });
    // Dual-power cycle: 20 s high / 10 s medium. Medium slots are the
    // physical feet_30 gate — medium-power packets die at mid-range while
    // high carries past 60 ft.
    _advTick = 0;
    _advPower = AdvertPower.high;
    _advPowerTimer?.cancel();
    _advPowerTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_isOn) return;
      _advTick = (_advTick + 1) % 3;
      final next = _advTick == 2 ? AdvertPower.medium : AdvertPower.high;
      if (next != _advPower) {
        _advPower = next;
        unawaited(_startAdvertising().catchError((Object e) {
          debugPrint('Power-slot advertise restart failed: $e');
        }));
      }
    });
    // Zombie-scanner watchdog. Silence usually means the user is simply
    // alone — NOT a broken scanner — so this is a slow safety net, not a
    // health probe: one restart per 15 silent minutes at most (audit
    // 2026-07-13 #4; the aggressive 3-min version burned battery and
    // punched scan gaps for every solo user).
    _lastForeignScanAt = DateTime.now();
    _scanWatchdogTimer?.cancel();
    _scanWatchdogTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      if (!_isOn) return;
      final last = _lastForeignScanAt;
      if (last == null ||
          DateTime.now().difference(last) > const Duration(minutes: 15)) {
        debugPrint(
            'Scan watchdog: no foreign adverts ≥15min — precautionary scan restart');
        unawaited(_restartScanning());
      }
    });

    // WiFi venue layer — 60s cadence: a venue changes on the scale of minutes,
    // and WiFi shares the 2.4GHz antenna with the BLE scanner that matters more.
    wifiScanner.onFingerprint = (fp) {
      _wifiFingerprint =
          fp.hashed(_correlationSalt, excludedBssids: wifiScanner.excludedBssids);
    };
    wifiScanner.start();

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
    _sessionGeneration++;
    _advertisingWanted = false;
    _scanningWanted = false;
    _claimMgr.cancel();
    _rotationTimer?.cancel();
    _rotationTimer = null;
    _sightingFlushTimer?.cancel();
    _sightingFlushTimer = null;
    _scanRestartTimer?.cancel();
    _scanRestartTimer = null;
    _advPowerTimer?.cancel();
    _advPowerTimer = null;
    _scanWatchdogTimer?.cancel();
    _scanWatchdogTimer = null;
    _locationRefreshTimer?.cancel();
    _locationRefreshTimer = null;
    wifiScanner.stop();
    _wifiFingerprint = null;
    // Estimator state must not leak across beacon sessions: after off/on, a
    // single fresh weak sample could otherwise classify Close By from the
    // prior session's samples (reviewer #17).
    rangeEstimator.clear();
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

    try {
      onBeaconStopped?.call();
    } catch (e) {
      debugPrint('onBeaconStopped callback error: $e');
    }
  }

  Future<void> _rotateToken(String rangeType) async {
    final gen = _sessionGeneration;
    try {
      // Drain buffered sightings FIRST: the server keeps one claim per user,
      // so rows still referencing the outgoing token would fail after the
      // new claim replaces it (audit 2026-07-13 #3).
      await _flushSightings();
      if (!_isOn || gen != _sessionGeneration) return;
      await _refreshClaim(rangeType: rangeType);
      // A rotation that straddled turnOffBeacon must not resurrect the
      // claim or the advertiser.
      if (!_isOn || gen != _sessionGeneration) {
        await _releaseClaim();
        return;
      }
      await _startAdvertising();
    } catch (e) {
      debugPrint('Token rotation failed; stopping beacon: $e');
      if (gen == _sessionGeneration) await turnOffBeacon();
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
    // Serialized behind any in-flight start; queued starts no-op via
    // _scanningWanted (already false by the time _stopBle is called on stop).
    try {
      await _serialScanOp(() async {
        await _scanSub?.cancel();
        _scanSub = null;
        await FlutterBluePlus.stopScan();
      });
    } catch (e) {
      debugPrint('BLE scan stop failed: $e');
    }
    try {
      // Serialized: runs after any in-flight advertising start, and queued
      // starts behind it no-op via _advertisingWanted.
      await _serialAdvOp(() => FlutterBlePeripheral().stop());
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

  Future<void> _startAdvertising() => _serialAdvOp(_startAdvertisingLocked);

  Future<void> _startAdvertisingLocked() async {
    // Beacon turned off while this op sat in the queue — do not resurrect.
    if (!_advertisingWanted) return;
    if (_currentToken == null || _currentCorrelationId == null) {
      throw StateError('No beacon token is available');
    }

    // FAIL CLOSED on iOS: the pinned flutter_ble_peripheral Darwin bridge
    // forwards only serviceUuid/localName, never manufacturerData, so an
    // iPhone would advertise an EMPTY packet and no peer could recover the
    // 16-byte id — yet the call "succeeds" and the UI would say "findable"
    // (reviewer #2). Until an iOS-supported carrier (service UUID / iBeacon)
    // ships and is device-tested, refuse rather than lie about discoverability.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      throw StateError(
          'iOS beacon advertising is not yet supported — peers cannot discover '
          'this device. (Tracked: iOS token carrier not implemented.)');
    }

    final peripheral = FlutterBlePeripheral();
    // Legacy payload: mfg id + 16-byte corr + 1 flag byte (fits 31-byte AD).
    // Flag bit0 = medium-power slot. Field test 2026-07-13: Samsung's stack
    // does NOT update the TX Power Level AD when settings change, so the
    // slot marker must live in our own payload. Remaining flag bits are
    // reserved (future mesh relay bit). 16-byte adverts = legacy = high.
    final payload = Uint8List(17)
      ..setRange(0, 16, _currentCorrelationId!)
      ..[16] = _advPower == AdvertPower.medium ? 0x01 : 0x00;
    final advertiseData = AdvertiseData(
      manufacturerId: _inRangeManufacturerId,
      manufacturerData: payload,
      includeDeviceName: false,
    );

    // Balanced mode — lowLatency was aggressive on S9 dual-phone tests.
    // Power alternates high/medium (see _advPowerTimer): high carries past
    // 60 ft (walk #3); "heard on medium" is the physical feet_30 gate.
    final txPower = _advPower == AdvertPower.medium
        ? AdvertiseTxPower.advertiseTxPowerMedium
        : AdvertiseTxPower.advertiseTxPowerHigh;
    final settings = AdvertiseSettings(
      advertiseSet: false,
      connectable: false,
      timeout: 0,
      advertiseMode: AdvertiseMode.advertiseModeBalanced,
      txPowerLevel: txPower,
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
      debugPrint('Started BLE advertising (power=${_advPower.name})');
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
            txPowerLevel: txPower,
          ),
          advertiseSetParameters: AdvertiseSetParameters(
            connectable: false,
            legacyMode: true,
            scannable: true,
            txPowerLevel: _advPower == AdvertPower.medium
                ? txPowerMedium
                : txPowerHigh,
            interval: intervalHigh,
          ),
        );
        debugPrint(
            'Started BLE advertising (set+legacy fallback, power=${_advPower.name})');
      } catch (e2) {
        debugPrint('Advertising fallback also failed: $e2');
        throw StateError('Could not start BLE advertising');
      }
    }
  }

  /// One-shot radio capability probe. A phone marketed as "Bluetooth 5.0"
  /// (the S9 is) does NOT necessarily support the long-range Coded PHY —
  /// spec sheets conflate it with the 2M high-speed PHY, and the feature is
  /// gated by the Bluetooth controller, not the OS version. Coded PHY would
  /// buy ~12-20 dB of link budget (a large range/blocking win), so log what
  /// this device can actually do before designing around it.
  Future<void> _logRadioCapabilities() async {
    if (_capsLogged) return;
    _capsLogged = true;
    try {
      final phy = await FlutterBluePlus.getPhySupport();
      debugPrint(
          'BLE radio caps: le2M=${phy.le2M} leCoded=${phy.leCoded} (Coded PHY = long range)');
    } catch (e) {
      debugPrint('BLE radio capability probe failed: $e');
    }
  }

  bool _capsLogged = false;

  Future<void> _startScanning() => _serialScanOp(_startScanningLocked);

  Future<void> _startScanningLocked() async {
    // Beacon turned off while this op waited in the queue — don't start a scan.
    if (!_scanningWanted) return;
    await _logRadioCapabilities();
    final oldSub = _scanSub;
    _scanSub = null;
    await oldSub?.cancel();

    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      debugPrint('Pre-scan stop failed: $e');
    }

    // Re-check after the awaits: teardown may have run while we were stopping.
    if (!_scanningWanted) return;

    final sub = FlutterBluePlus.scanResults.listen(
      _onScanResults,
      onError: (e) {
        debugPrint('BLE scan stream error: $e');
        if (_scanningWanted) unawaited(_restartScanning());
      },
    );
    _scanSub = sub;

    // Hardware msd filter (our manufacturer id) — required, not an
    // optimization: Android ≥8.1 suppresses UNFILTERED scans while the
    // screen is off. Walk #1 (2026-07-13) proved it: 100% of scan
    // deliveries on both phones landed inside screen-awake windows.
    // The filter also confines results to In Range beacons, so the old
    // continuousDivisor flood guard is no longer needed.
    final calib = AppConfig.calibScanMode;
    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(hours: 1),
        androidUsesFineLocation: true,
        continuousUpdates: true,
        withMsd: [MsdFilter(_inRangeManufacturerId)],
        androidScanMode:
            calib ? AndroidScanMode.lowLatency : AndroidScanMode.balanced,
      );
    } catch (e) {
      // This op's own listener must not outlive a failed/aborted start.
      await sub.cancel();
      if (identical(_scanSub, sub)) _scanSub = null;
      rethrow;
    }
    // Turned off during startScan → undo, don't leave a live hardware scan.
    if (!_scanningWanted) {
      await sub.cancel();
      if (identical(_scanSub, sub)) _scanSub = null;
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
      return;
    }
    debugPrint(
        'BLE scan started (filtered msd=0xFFFF, ${calib ? "lowLatency/calib" : "balanced"})');
  }

  /// Every correlation id we've ever advertised this process — self-sighting guard.
  final Set<String> _ownCorrHexes = {};
  DateTime? _lastForeignScanAt;
  Timer? _scanWatchdogTimer;

  /// Last delivered timeStamp per device — the plugin re-emits its FULL
  /// accumulated list on every update, so old entries (with old RSSI)
  /// reappear on each callback. Walk #1: the app re-reported a frozen
  /// −81/−68 pair for 12 minutes this way. Process fresh results only.
  final Map<String, DateTime> _lastAdvertTsByDevice = {};

  void _onScanResults(List<ScanResult> results) {
    if (!_isOn) return;
    for (final r in results) {
      final deviceId = r.device.remoteId.str;
      final prevTs = _lastAdvertTsByDevice[deviceId];
      if (prevTs != null && !r.timeStamp.isAfter(prevTs)) continue; // stale
      _lastAdvertTsByDevice[deviceId] = r.timeStamp;
      if (_lastAdvertTsByDevice.length > 500) {
        final cutoff = DateTime.now().subtract(const Duration(minutes: 20));
        _lastAdvertTsByDevice.removeWhere((_, ts) => ts.isBefore(cutoff));
      }

      final adv = r.advertisementData;
      Uint8List? observedCorrelationId;
      bool mediumFlag = false;

      if (adv.manufacturerData.isNotEmpty) {
        final bytes = adv.manufacturerData[_inRangeManufacturerId];
        // 16 bytes = legacy corr-only advert (implies high power);
        // 17 bytes = corr + flag byte (bit0 = medium-power slot).
        if (bytes != null && (bytes.length == 16 || bytes.length == 17)) {
          observedCorrelationId = Uint8List.fromList(bytes.sublist(0, 16));
          mediumFlag = bytes.length == 17 && (bytes[16] & 0x01) != 0;
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

      // Which power slot sent this advert: flag byte in our payload
      // (Samsung's TX Power Level AD proved unreliable). Missing flag =
      // legacy advert = high — the safe direction: feet_30 can only
      // under-fire, never claim mid-range falsely.
      final power = mediumFlag ? AdvertPower.medium : AdvertPower.high;
      rangeEstimator.addSample(hexId, r.rssi, power);
      // Raw per-advert persistence + verbose peer logging is CALIBRATION only.
      // In production it would retain a place/peer fingerprint and print peer
      // ids to release logs / bug reports (reviewer #18).
      if (AppConfig.calibScanMode) {
        try {
          onAdvertSample?.call(hexId, r.rssi, power, DateTime.now());
        } catch (e) {
          debugPrint('onAdvertSample callback error: $e');
        }
        // One line per fresh foreign advert — the calibration ground truth.
        debugPrint(
            'Advert corr=${hexId.substring(0, 8)} rssi=${r.rssi} pw=${power == AdvertPower.medium ? "M" : "H"}');
      }

      _lastForeignScanAt = DateTime.now();
      _recordLocalSighting(hexId, r.rssi);
    }
  }

  double? _cachedLat;
  double? _cachedLon;
  double? _cachedAccuracy;
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
    // Uploaded sightings carry the ESTIMATED band, not the fixed beacon
    // range — the server derives encounter bands from it (migration 0022).
    final estimated = rangeEstimator.classify(observedCorrelationIdHex);
    final uploadRange = (range.startsWith('feet') && estimated != 'none')
        ? estimated
        : range;
    final record = SightingRecord(
      observedToken: observedCorrelationIdHex,
      rssi: rssi,
      observerLat: _cachedLat,
      observerLon: _cachedLon,
      observerAccuracyM: _cachedAccuracy,
      observedAt: now,
      rangeType: uploadRange,
    );

    // Keep one COHERENT best-evidence record per corr: RSSI, band, time,
    // location and accuracy all come from the SAME physical sample. Previously
    // the strongest RSSI was stitched onto the latest sample's time/coords/band
    // — an observation that never happened, which could pass the server RSSI
    // gate on old strength but store an unrelated location/band (reviewer #12).
    final prev = _pendingByCorr[observedCorrelationIdHex];
    if (prev == null && _pendingByCorr.length >= _maxPendingSightings) {
      _pendingByCorr.remove(_pendingByCorr.keys.first);
    }
    // Replace only when this sample is strictly stronger; otherwise keep the
    // existing coherent record untouched.
    if (prev == null || rssi > prev.rssi) {
      _pendingByCorr[observedCorrelationIdHex] = record;
    }

    final band = estimated;
    debugPrint(
        'Sighting observed rssi=$rssi band=$band (tracked=${_pendingByCorr.length})');

    // Local encounter store (instant or delayed reveal).
    try {
      onSighting?.call(
        correlationId: observedCorrelationIdHex,
        rssi: rssi,
        rangeType: range,
        estimatedBand: band,
      );
    } catch (e) {
      debugPrint('onSighting callback error: $e');
    }
  }

  /// Calibration ground truth for the GPS layer. Coordinates are logged only
  /// when INRANGE_CALIB_SCAN is set (our own test phones): comparing the two
  /// phones' fixes is the ONLY way to measure what the GPS veto is really
  /// doing, and accuracy alone cannot do it. Production logs accuracy only.
  void _logGpsFix(Position p, {String? tag}) {
    final suffix = tag == null ? '' : ' ($tag)';
    if (AppConfig.calibScanMode) {
      debugPrint('GpsFix lat=${p.latitude.toStringAsFixed(6)} '
          'lon=${p.longitude.toStringAsFixed(6)} '
          'acc=${p.accuracy.toStringAsFixed(1)}m$suffix');
    } else {
      debugPrint('GpsFix acc=${p.accuracy.toStringAsFixed(1)}m$suffix');
    }
  }

  void _ensureLocationCache() {
    // Calibration: refresh every 30s so a 90-second stop yields several fixes
    // to average. Production: 120s — GPS is a coarse veto, not a live signal.
    final maxAge = AppConfig.calibScanMode
        ? const Duration(seconds: 30)
        : const Duration(seconds: 120);
    final stale =
        _cachedLocAt == null || DateTime.now().difference(_cachedLocAt!) > maxAge;
    if (!stale) return;
    if (_locationRefreshTimer != null) return;
    _locationRefreshTimer = Timer(Duration.zero, () async {
      try {
        // Calibration takes a REAL fix every time. getLastKnownPosition can
        // keep re-serving a stale coarse fix (observed: one phone stuck at
        // 100 m while the other resolved to 15 m), which would make half the
        // GPS data worthless. Production still prefers the cached fix — it is
        // only feeding a coarse plausibility veto and battery matters more.
        Position? pos = AppConfig.calibScanMode
            ? null
            : await Geolocator.getLastKnownPosition();
        if (pos == null || !_isFreshPosition(pos)) {
          // Calibration walks request a real fix (sub-5 m outdoors) so we can
          // measure GPS's actual error against known distances. Production
          // stays on low accuracy — GPS is only a coarse plausibility veto,
          // and a high-accuracy fix is not worth the battery for that job.
          pos = await Geolocator.getCurrentPosition(
            locationSettings: LocationSettings(
              accuracy: AppConfig.calibScanMode
                  ? LocationAccuracy.high
                  : LocationAccuracy.low,
              timeLimit: const Duration(seconds: 6),
            ),
          );
        }
        _cachedLat = pos.latitude;
        _cachedLon = pos.longitude;
        _cachedAccuracy = pos.accuracy;
        _cachedLocAt = DateTime.now();
        // Android's accuracy figure is a 68%-confidence radius — ~1 fix in 3
        // is worse than it claims — and indoors it degrades to tens of metres.
        // Log it: it is the input to the server's correlation radius gate.
        //
        // Coordinates are logged ONLY in calibration mode, and only on our own
        // test phones: without them the two phones' fixes cannot be compared,
        // so the GPS layer could not be evaluated at all. Never in production.
        _logGpsFix(pos);
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
          // Sizes the server's GPS plausibility veto from real uncertainty
          // instead of a fixed guess (migration 0024).
          'p_accuracy': s.observerAccuracyM,
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

    // Reuse the cached fix only if it is still fresh. Without the age check a
    // user who travels >400 m without seeing a peer keeps claiming their
    // ORIGIN, and the server's 400 m veto then rejects the real encounter at
    // the new location (reviewer #7).
    final cacheAge = _cachedLocAt == null
        ? null
        : DateTime.now().difference(_cachedLocAt!);
    final cacheFresh = cacheAge != null &&
        cacheAge <= const Duration(minutes: 2);
    double? lat = cacheFresh ? _cachedLat : null;
    double? lon = cacheFresh ? _cachedLon : null;
    if (lat == null) {
      try {
        Position? position = AppConfig.calibScanMode
            ? null
            : await Geolocator.getLastKnownPosition();
        if (position == null || !_isFreshPosition(position)) {
          position = await Geolocator.getCurrentPosition(
            locationSettings: LocationSettings(
              accuracy: AppConfig.calibScanMode
                  ? LocationAccuracy.high
                  : LocationAccuracy.low,
              timeLimit: const Duration(seconds: 5),
            ),
          );
        }
        lat = position.latitude;
        lon = position.longitude;
        _cachedLat = lat;
        _cachedLon = lon;
        _cachedAccuracy = position.accuracy;
        _cachedLocAt = DateTime.now();
        _logGpsFix(position, tag: 'claim');
      } catch (e) {
        debugPrint('Geolocator failed at claim time: $e');
      }
    }

    // A new token supersedes any pending retry of the previous claim.
    final gen = _claimMgr.newSession();
    _claimRangeType = rangeType;
    _cachedLat = lat;
    _cachedLon = lon;

    // Publish the new token's expiry immediately, even before the claim RPC
    // resolves, so the UI countdown tracks the current token (reviewer #11).
    onClaimStateChanged?.call(
        _currentToken!.expiresAt, AppConfig.hasRealSupabase ? _cloudClaimed : null);

    if (!AppConfig.hasRealSupabase) {
      _cloudClaimed = false;
      debugPrint('claim_token skipped (no real Supabase — local BLE mode)');
      return;
    }

    // Retries the SAME live token with bounded backoff; ClaimManager fires
    // onState (→ onClaimStateChanged) after every attempt.
    await _claimMgr.attempt(gen);
  }

  /// One claim_token RPC for the current token/location. Throws on failure so
  /// ClaimManager retries; a location refresh is nudged for the next attempt.
  Future<void> _uploadClaim() async {
    if (_currentToken == null || _currentCorrelationId == null) {
      throw StateError('no token to claim');
    }
    _ensureLocationCache();
    final claimToken = _currentCorrelationId!
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    // Always send UTC — a local DateTime without offset is misread as UTC by
    // Postgres and expires claims hours early (broke feet correlation once).
    final until = _currentToken!.expiresAt.toUtc().add(const Duration(minutes: 2));
    await InRangeSupabase.client.rpc('claim_token', params: {
      'p_token': claimToken,
      'p_valid_until': until.toIso8601String(),
      'p_lat': _cachedLat,
      'p_lon': _cachedLon,
      'p_range': _mapUiRangeToDb(_claimRangeType ?? 'feet_60'),
      'p_accuracy': _cachedAccuracy,
    });
    debugPrint('claim_token OK until=${until.toIso8601String()}');
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
    this.observerAccuracyM,
  });

  final String observedToken;
  final int rssi;
  final DateTime observedAt;
  final double? observerLat;
  final double? observerLon;
  final String rangeType;

  /// Reported GPS accuracy (metres) — sizes the server's plausibility veto.
  final double? observerAccuracyM;
}
