import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
// For WidgetsBinding only: the iOS BLE-state re-read needs an app-resume
// signal, and nothing in lib/ observed the lifecycle before this. No widgets
// are built here.
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:in_range/core/config/app_config.dart';
import 'package:in_range/core/network/supabase_client.dart';
import 'package:in_range/features/beacon/background_beacon_channel.dart';
import 'package:in_range/features/beacon/batch_token_source.dart';
import 'package:in_range/features/beacon/gatt_token_reader.dart';
import 'package:in_range/features/beacon/claim_manager.dart';
import 'package:in_range/features/beacon/ephemeral_token_generator.dart';
import 'package:in_range/features/beacon/location_keepalive.dart';
import 'package:in_range/features/beacon/proximity_observation.dart';
import 'package:in_range/features/beacon/range_estimator.dart';
import 'package:in_range/features/beacon/subtle_wake_service.dart';
import 'package:in_range/features/beacon/venue_anchor_service.dart';
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
    SharedPreferences? sharedPreferences,
  })  : _userId = userId,
        _correlationSalt = hmacSecret,
        _rotationWindow = rotationWindow,
        venueAnchors = VenueAnchorService(
          persistenceKey: () => 'inrange.venue_anchors.v1',
          readPersisted: (key) async => sharedPreferences?.getString(key),
          writePersisted: (key, value) async =>
              await sharedPreferences?.setString(key, value),
        ) {
    // Feed native/Dart location fixes into the sighting cache. The fix is used
    // for server radius gates and refreshes the cache without a fresh
    // Geolocator call per sighting. GPS is still not a proximity classifier.
    locationKeepalive.onFix = _onLocationFix;

    // Subtle-wake path (docs/SUBTLE_TRACKING_ARCHITECTURE.md): each wake turns
    // into a cache refresh + a bounded BLE burst; anchor edits propagate to
    // the native coordinator as region descriptors. The BSSID salt MUST be
    // the correlation salt so hints match the venue matcher's fingerprints.
    subtleWake
      ..onBurst = burst
      ..onFix = _onLocationFix
      ..onRefreshLocation = _ensureLocationCache
      ..cachedFix = _cachedLocationFix
      ..hashSalt = () => _correlationSalt;
    subtleWake.isBeaconOn = () => _isOn;
    subtleWake.onAnchorDerived = _onAnchorDerived;
    venueAnchors.onChanged =
        (descriptors) => unawaited(subtleWake.syncAnchors(descriptors));
  }

  // #6 step 2: opaque beacon tokens now come from the server
  // (issue_token_batch), not a client-side HMAC keyed by a secret shipped in the
  // app. `userIdSecret` is kept in the signature for API stability but is no
  // longer used for token derivation.
  late final BatchTokenSource _tokenSource = BatchTokenSource(
    fetchBatch: _fetchTokenBatch,
    rotationWindow: _rotationWindow,
  );

  /// iOS locked-phone carrier (W2/W4). Native sightings join the exact same
  /// ingest path as scan results; the native BLE-state callbacks keep
  /// `_advertisingUp` / `_receivePathDown` honest across background transitions.
  late final BackgroundBeaconChannel _bgBeacon = BackgroundBeaconChannel()
    ..onSighting = ((token, rssi, at) {
      if (!_isOn) return;
      _ingestForeignSample(token, rssi, AdvertPower.high, at: at);
    })
    // Still bound: native fires this verbatim alongside onBleState (additive
    // migration, nothing renamed) and it carries the same verdict, so the two
    // cannot disagree. Kept so a native build predating onBleState still keeps
    // discoverability honest.
    ..onAdvertisingState = ((advertising) {
      _applyAdvertisingVerdict(advertising, 'onAdvertisingState');
    })
    ..onBleState = _onNativeBleState
    ..onBufferedSightingsReady = (() {
      unawaited(_drainNativeBuffer());
    });
  final Duration _rotationWindow;
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

  /// Account-pause probe for the restore path (wired by the provider to the
  /// session controller). A paused account is "hidden from new encounters" —
  /// restoring its native beacon would advertise behind the paused UI, so
  /// restoreNativeSession stops native instead. Null = never paused (tests).
  bool Function()? isAccountPaused;

  /// Drains the calibration RSSI upload queue (see RssiUploader). Rides the
  /// existing 45 s sighting-flush timer rather than adding a second one, and
  /// fires once more on stop so a walk ships its tail without waiting for the
  /// next session. Failures are swallowed here: the queue is durable and the
  /// timer IS the retry, so a dead network must never disturb scanning.
  Future<void> Function()? onFlushUploads;

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

  /// False while the platform can't broadcast the token (iOS scan-only): the
  /// beacon scans + logs but peers can't discover this device. Drives the
  /// "scanning only" UI so we never claim false discoverability (reviewer #2).
  ///
  /// This is the ADVERTISE half only. Read [discoverable] for the verdict the
  /// UI is allowed to show — see [receivePathDown].
  bool _advertisingUp = true;

  /// Whether the "beacon is working" claim is honest right now.
  ///
  /// Advertising alone is not enough. Finding 1.3: iOS could be advertising
  /// perfectly while `CBCentralManager` was poweredOff/unauthorized, i.e. we
  /// were visible but stone deaf — and In Range needs BOTH directions before an
  /// encounter exists, so a live advertiser over a dead scanner produces exactly
  /// nothing while the UI says the beacon is up. Dart could not even observe
  /// that case before 2026-07-26 (the entire native surface was one peripheral-
  /// role bool), which is why it stayed shipped. Fail closed on either half.
  bool get discoverable => _advertisingUp && !_receivePathDown;

  /// The advertise half in isolation — for logs and for anything that needs to
  /// say WHICH side is down. "Can't be seen" and "can't see" have different
  /// remedies and different copy (background_beacon_channel.dart:44-45).
  bool get advertisingUp => _advertisingUp;

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

  /// Holds the process alive while the beacon is on (iOS). Scoped to the
  /// beacon session on both ends — see LocationKeepalive.
  final LocationKeepalive locationKeepalive = LocationKeepalive();

  /// Subtle-wake path: receives SLC/region/push wakes from the iOS native
  /// coordinator and turns each into a bounded BLE burst + venue hint upload.
  /// OFF unless INRANGE_SUBTLE_WAKE is set; no-op on Android.
  final SubtleWakeService subtleWake = SubtleWakeService();

  /// Local venue anchors (tier 3 wakes). Descriptors are pushed to native
  /// on every change and re-synced on each beacon-on. Persisted across
  /// sessions when a SharedPreferences instance is provided.
  final VenueAnchorService venueAnchors;

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

  /// iOS session restore (audit 2026-07-25, critical #1): after a process
  /// eviction the native carrier kept advertising/scanning off its persisted
  /// state, but a fresh Dart isolate starts with `_isOn = false` — restored
  /// sightings were rejected by the onSighting guard and the UI showed off
  /// over a live beacon. One canonical state: if native says the beacon is
  /// on, Dart re-runs the full session (fresh claim, timers, wake sources)
  /// and the UI follows; if Dart cannot run a session (signed out, missing
  /// secrets, or a PAUSED account — "hidden from new encounters" must not
  /// advertise) the native side is stopped so nothing advertises behind the
  /// user's back. Returns true when a session was restored. No-op off iOS
  /// and when the beacon is already on.
  Future<bool> restoreNativeSession() async {
    if (_isOn) return false;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return false;
    if (!await _bgBeacon.isNativeEnabled()) return false;
    if (_userId.trim().isEmpty ||
        !AppConfig.hasCryptoSecrets ||
        isAccountPaused?.call() == true) {
      debugPrint('Native beacon active but session not restorable — stopping');
      await _bgBeacon.stop();
      return false;
    }
    debugPrint('Restoring beacon session from native state');
    try {
      // Range is a fixed product constant (SelectedRangeController), so no
      // persisted choice is needed to resume.
      await turnOnBeacon(rangeType: 'feet_60');
      return true;
    } catch (e) {
      debugPrint('Native session restore failed: $e');
      return false;
    }
  }

  bool _nativeDrainInFlight = false;
  bool _nativeDrainPending = false;

  /// Pull-and-ack drain of the native background buffer: sightings are
  /// ingested with their original capture timestamps (migration 0053's
  /// late-evidence window covers them server-side) and only then acked, so
  /// a crash mid-drain re-delivers instead of losing them. Serialized: two
  /// concurrent drains would ack overlapping counts and delete sightings
  /// neither ingested (audit 2026-07-25 round 3); a drain requested while
  /// one runs is folded into a follow-up pass.
  Future<void> _drainNativeBuffer() async {
    if (!_isOn) return;
    // iOS-only: the buffer lives in BackgroundBeacon.swift. There is no Android
    // implementation of io.inrange/background_beacon, so on Android every call
    // threw MissingPluginException, got caught, and printed
    // "BackgroundBeacon drain failed: ..." on EVERY beacon start (observed on an
    // S9, 2026-07-26 bench). Harmless, but it put an alarming line in the walk
    // logs we are about to read closely — and a real drain failure would have
    // been indistinguishable from the routine one.
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    if (_nativeDrainInFlight) {
      _nativeDrainPending = true;
      return;
    }
    _nativeDrainInFlight = true;
    try {
      do {
        _nativeDrainPending = false;
        final items = await _bgBeacon.drainBufferedSightings();
        if (items.isEmpty || !_isOn) return;
        for (final s in items) {
          final token = s['token'], rssi = s['rssi'], ts = s['ts'];
          if (token is String && token.length == 32 && rssi is int) {
            final at = ts is int
                ? DateTime.fromMillisecondsSinceEpoch(ts)
                : DateTime.now();
            _ingestForeignSample(token, rssi, AdvertPower.high, at: at);
          }
        }
        await _bgBeacon.ackBufferedSightings(items.length);
      } while (_nativeDrainPending && _isOn);
    } finally {
      _nativeDrainInFlight = false;
    }
  }

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
      // Last, and only once the session is really up. OFF by default and a
      // no-op unless INRANGE_LOCATION_RESIDENCY is set: it keeps the process
      // from suspending so app-owned timers keep firing, which is NOT the same
      // as foreground BLE and is still unmeasured. See LocationKeepalive.
      // Never blocks the beacon — a denied grant costs latency, not function.
      unawaited(locationKeepalive.start());
      // Tier 2-4 wakes (SLC, region, silent push). Same contract as the
      // keepalive: gated, iOS-only, and never blocks the beacon.
      unawaited(subtleWake.start());
      unawaited(subtleWake.syncAnchors(venueAnchors.regionDescriptors()));
      // Pick up anything the native carrier buffered while this isolate was
      // dead (eviction restore) or suspended.
      unawaited(_drainNativeBuffer());
    } catch (e) {
      if (gen == _sessionGeneration) {
        _advertisingWanted = false;
        _scanningWanted = false;
        await locationKeepalive.stop();
        await subtleWake.stop();
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
      if (_tokenSource.shouldRotate(_currentToken)) {
        unawaited(_rotateToken(rangeType));
      }
    });

    _sightingFlushTimer?.cancel();
    _sightingFlushTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!_isOn) return;
      _flushSightings();
      _flushUploads();
    });
    _scanRestartTimer?.cancel();
    // MUST be < 10 min on Android 14+ (finding D7 of
    // docs/BLE_PRIOR_ART_REVIEW_2026-07-26.md).
    //
    // Path correction, 2026-07-26: the previous comment cited
    // `research/ble-radio-optimization.md` and a reviewer, finding nothing at
    // that path, concluded the 30-minute figure was unsourced and argued from
    // there. The file is `docs/research/ble-radio-optimization.md` and the
    // figure is sourced at :19-21 to a quoted academic paper ("the Android
    // operating system automatically switches from the SCAN_MODE_LOW_LATENCY to
    // the SCAN_MODE_OPPORTUNISTIC setting after 30 min of continuous
    // scanning"). It was never wrong — it describes Android ≤13. Cite the full
    // path; a one-character path error cost a reviewer an entire argument.
    //
    // AOSP demotes a long-running scan on a timeout that changed under us:
    // 30 min on Android 10–13, but **10 min on 14+**. The mechanism changed
    // too. On ≤13 an unfiltered client went OPPORTUNISTIC with its filters
    // removed; on 14+ a *filtered* client — which ours must be, since ≥8.1
    // suppresses unfiltered screen-off scans — is forced to
    // SCAN_MODE_FORCE_DOWNGRADED = LOW_POWER (ScanManager.java:1550-1578,
    // :123), and `mStats.setScanTimeout()` makes isForceDowngradedScanClient()
    // **sticky for the life of that scanner** (AppScanStats.java:801-810).
    // Sticky drags the screen-off path down with it: SCREEN_OFF_BALANCED 25%
    // → SCREEN_OFF 5% (ScanManager.java:698-731, duty cycles at :85-97).
    //
    // So at 25 min, on a 14+ handset, 15 of every 25 minutes ran at ⅕–⅒ the
    // duty cycle we were already paying for — invisible from Dart, because FBP
    // reports the demotion in no way at all (isScanning stays true, no event).
    // 8 min keeps it at `balanced` continuously with 2 min of slack for a
    // Doze-deferred timer, and stays far under the 30-min behaviour on the S9s.
    // The cost is one scan-quota charge per 8 min against a budget of 5 per
    // 30 s (D6) — a non-issue. Not backed off on failure: see
    // _requestScanRestart.
    //
    // Behind INRANGE_SCAN_RESTART_MINUTES (default 8 = this value) so one
    // handset can walk the old 25 tomorrow: e5d40e4 shipped this change AND
    // E1's PHY change together, which left the duty-cycle-collapse instrument
    // with nothing to compare against. See AppConfig.scanRestartMinutes.
    _scanRestartTimer = Timer.periodic(AppConfig.scanRestartInterval, (_) {
      if (_isOn) _requestScanRestart('cadence');
    });
    // Dual-power cycle: 20 s high / 10 s medium. Medium slots are the
    // physical feet_30 gate — medium-power packets die at mid-range while
    // high carries past 60 ft.
    _advTick = 0;
    _advPower = AdvertPower.high;
    _advPowerTimer?.cancel();
    // Power-cycle only on Android: iOS has no CBPeripheralManager TX-power
    // control (single high-power slot), and re-advertising it every 10 s would
    // just churn the iOS advertiser for no distance signal.
    if (_advertisingUp && defaultTargetPlatform != TargetPlatform.iOS) {
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
    }
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
        _requestScanRestart('watchdog');
      }
    });

    // E2/E8: the two state streams the app never listened to. Scoped to the
    // beacon session; cancelled in turnOffBeacon.
    _startStateListeners();

    // Walk-day instruments (W1–W9, docs/BLE_PRIOR_ART_REVIEW_2026-07-26.md).
    // Calibration builds ONLY — production never installs the timer, never
    // allocates the counters, and therefore behaves identically with and
    // without the instrumentation. 10 min per W2; each report carries the scan
    // sequence number so gap data can be attributed to a single scan window
    // even though the window (8 min) and the report (10 min) do not align.
    _calibReportTimer?.cancel();
    _calibReportTimer = null;
    if (AppConfig.calibScanMode) {
      _resetCalibWindow();
      _calibReportTimer = Timer.periodic(const Duration(minutes: 10), (_) {
        if (_isOn) _logCalibWindowReport();
      });
    }

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
        // Timeouts: startService waits on a handshake with the background
        // isolate; a wedged handshake held the ENTIRE beacon toggle hostage
        // with the radio already running (S22 2026-07-23 — UI showed off,
        // scan was live). The FGS is best-effort; the beacon must not be.
        final running =
            await service.isRunning().timeout(const Duration(seconds: 5));
        if (!running) {
          await service.startService().timeout(const Duration(seconds: 10));
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
    // A deferred scan restart must not fire into a stopped session. The
    // _scanStartLedger is deliberately NOT cleared — see _scanStartBudget.
    _scanRetryTimer?.cancel();
    _scanRetryTimer = null;
    _scanRetryDeadline = null;
    _scanErrorStreak = 0;
    _scanRunning = false;
    _locationRefreshTimer?.cancel();
    _locationRefreshTimer = null;
    // One last window report so a walk's tail ships instead of being lost with
    // the timer (same reasoning as the sighting/upload flush below).
    if (AppConfig.calibScanMode) _logCalibWindowReport();
    _calibReportTimer?.cancel();
    _calibReportTimer = null;
    _stopStateListeners();
    wifiScanner.stop();
    // Release residency the moment discoverability is off. Leaving this
    // running would keep the app alive — and keep the location indicator lit —
    // after the user explicitly opted out, which is the exact behavior that
    // gets an app pulled.
    await locationKeepalive.stop();
    // Same for wake sources: SLC/region monitoring must not keep waking the
    // app — and firing BLE bursts — after discoverability is off. The anchor
    // set itself stays client-side; the next session re-syncs it.
    await subtleWake.stop();
    _wifiFingerprint = null;
    // Estimator state must not leak across beacon sessions: after off/on, a
    // single fresh weak sample could otherwise classify Close By from the
    // prior session's samples (reviewer #17).
    rangeEstimator.clear();
    await _flushSightings();
    await _flushUploads();
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

  // ===== Scan restart pacing (C3 / D6 / E3) =============================
  //
  // Before this, every restart was free and instant. Three triggers called
  // `_restartScanning` — the cadence timer, the 15-min watchdog and the
  // scan-stream onError — and it caught, debugPrint'ed and gave up: no delay,
  // no counter, no retry if startScan itself threw.
  //
  // AOSP's scan quota is DEFAULT_SCAN_QUOTA_COUNT = 5 per
  // DEFAULT_SCAN_QUOTA_WINDOW_MILLIS = 30 s (AdapterService.java:6975-6976),
  // charged at scanner *registration*, and every startScan registers a fresh
  // scanner (BluetoothLeScanner.java:417) — so every restart is one charge.
  // Trip the quota and AOSP delivers *nothing at all*:
  // BluetoothLeScanner.java:429-433, verbatim
  //   // If scanning too frequently, don't report anything to the app.
  // No onScanFailed, no onScanResult. Combined with E3 (FBP's onScanFailed
  // desyncs Dart from native, so the next stopScan is a no-op and the next
  // startScan registers into a stack that still holds the old registration),
  // the old error path was `onScanFailed → restart → onScanFailed` bounded
  // only by the channel round-trip: the loop fed the throttle that kept it
  // broken, and the app went blind for up to a full watchdog period behind a
  // green "beacon is active" notification.

  /// 4, not AOSP's 5: one charge of headroom. The quota counter is fed on scan
  /// *stop* using the *start* timestamp (AppScanStats.java:355-363, :830-836),
  /// so a Dart-side ledger can only ever approximate it, and anything else in
  /// the process that registers a scanner spends from the same UID budget.
  static const int _scanStartBudget = 4;
  static const Duration _scanStartWindow = Duration(seconds: 30);

  /// Successful `startScan` times, oldest first. Deliberately NOT cleared by
  /// turnOffBeacon: the quota is per-UID and does not care about our session
  /// boundaries, so a user tapping the toggle four times must not look free.
  final List<DateTime> _scanStartLedger = <DateTime>[];

  /// onError backoff ladder: 2 s doubling to a 60 s ceiling, reset on the next
  /// delivered scan result of any kind (see _onScanResults). The *cadence*
  /// restart is deliberately never backed off — it is upkeep against AOSP's
  /// scan-mode demotion (D7), not failure recovery.
  static const Duration _scanErrorBackoffBase = Duration(seconds: 2);
  static const Duration _scanErrorBackoffMax = Duration(seconds: 60);
  int _scanErrorStreak = 0;
  Timer? _scanRetryTimer;

  /// When the pending [_scanRetryTimer] will fire. Kept so a later, LONGER
  /// request can extend the slot instead of being silently folded — a 3 s
  /// bucket defer must not swallow a 60 s error backoff, or the per-code
  /// ladder in [_scanBackoffFor] is never actually honoured.
  DateTime? _scanRetryDeadline;

  /// True between a successful `FlutterBluePlus.startScan` and the next
  /// error/stop (W8). This is the state the app was missing: `_lastForeignScanAt`
  /// is bumped only inside `_ingestForeignSample` — i.e. only when a real In
  /// Range peer decodes (C3) — so "the scanner is dead" and "the user is
  /// standing alone" had the identical signature. Not yet wired into the
  /// watchdog: that arm is on the walk-day freeze list.
  bool _scanRunning = false;
  bool get scanRunning => _scanRunning;

  /// Dispatched restarts that have not reached `FlutterBluePlus.startScan` yet.
  /// Counted against the budget: without it, two triggers firing in the same
  /// microtask both see an unspent ledger and both get through — which is the
  /// exact burst the bucket exists to stop.
  int _scanStartsInFlight = 0;

  /// How long until the token bucket can afford another scan start.
  Duration _scanStartCooldown() {
    final now = DateTime.now();
    _scanStartLedger.removeWhere((t) => now.difference(t) >= _scanStartWindow);
    if (_scanStartLedger.length + _scanStartsInFlight < _scanStartBudget) {
      return Duration.zero;
    }
    if (_scanStartLedger.isEmpty) {
      // Budget held entirely by starts still in flight. Come back once they
      // land and can price the real wait.
      return const Duration(seconds: 1);
    }
    // AOSP unblocks the same way — there is no fixed penalty, you unblock as
    // the oldest start in the window ages out (AppScanStats.java:830-836).
    // The 250 ms is slop against clock/scheduler skew at the boundary.
    final wait = _scanStartWindow - now.difference(_scanStartLedger.first);
    return wait.isNegative
        ? Duration.zero
        : wait + const Duration(milliseconds: 250);
  }

  /// Every scan restart trigger funnels through here: the 8-min cadence timer,
  /// the 15-min watchdog, the scan-stream onError, subtle-wake bursts and the
  /// adapter off→on listener (E2). A request the bucket cannot afford is
  /// DEFERRED, never dropped — dropping it is precisely what left the radio
  /// dead until the next watchdog tick.
  void _requestScanRestart(String reason, {Duration delay = Duration.zero}) {
    if (!_scanningWanted) return;
    final cooldown = _scanStartCooldown();
    final wait = delay > cooldown ? delay : cooldown;
    if (wait > Duration.zero) {
      _deferScanRestart(wait, reason);
      return;
    }
    unawaited(_restartScanning(reason));
  }

  /// Single-slot deferral. A pending retry absorbs every later request: a burst
  /// of ten stream errors inside a second must produce ONE restart, not ten —
  /// that burst is exactly what turns the quota into total silence (D6). A
  /// pending backoff therefore also outranks a cadence tick that lands on top
  /// of it; the backoff restart re-establishes scanning either way.
  void _deferScanRestart(Duration delay, String reason) {
    final deadline = DateTime.now().add(delay);
    if (_scanRetryTimer != null) {
      final pending = _scanRetryDeadline;
      if (pending != null && !deadline.isAfter(pending)) {
        debugPrint('Scan restart ($reason) folded into pending retry');
        return;
      }
      // The fold must take the LATER deadline: a pending short bucket defer
      // swallowing a longer error backoff re-arms a failing scan at bucket
      // speed instead of ladder speed.
      _scanRetryTimer!.cancel();
      debugPrint('Scan restart ($reason) extends pending retry to '
          '${delay.inMilliseconds}ms');
    } else {
      debugPrint('Scan restart ($reason) deferred ${delay.inMilliseconds}ms '
          '(bucket ${_scanStartLedger.length}/$_scanStartBudget per '
          '${_scanStartWindow.inSeconds}s, error streak $_scanErrorStreak)');
    }
    _scanRetryDeadline = deadline;
    _scanRetryTimer = Timer(delay, () {
      _scanRetryTimer = null;
      _scanRetryDeadline = null;
      // Re-price it: the deferral was granted against a ledger that another
      // trigger may have spent in the meantime. The ladder wait itself has
      // already elapsed on this timer, so zero extra delay here is correct.
      _requestScanRestart(reason);
    });
  }

  Future<void> _restartScanning([String reason = 'unspecified']) async {
    _scanStartsInFlight++;
    try {
      await _startScanning();
    } catch (e) {
      // Was: catch + debugPrint, full stop, nothing retrying — a transient
      // scan-start failure left the radio dead until the watchdog (C3). Now a
      // throw joins the same ladder a stream error does.
      _scanRunning = false;
      _scanErrorStreak++;
      debugPrint('BLE scan restart ($reason) failed: $e');
      _scheduleBackoffRetry(e, '$reason-failed');
    } finally {
      _scanStartsInFlight--;
    }
  }

  /// Shared tail of both failure paths (thrown startScan, stream onError).
  void _scheduleBackoffRetry(Object e, String reason) {
    if (!_scanningWanted) return;
    final delay = _scanBackoffFor(e);
    if (delay == null) {
      debugPrint('BLE scanning unsupported on this radio — not retrying');
      return;
    }
    _requestScanRestart(reason, delay: delay);
  }

  /// bitchat's per-code policy (C3, `BluetoothGattClientManager.kt:283-323`)
  /// mapped onto what FBP actually surfaces. Null = never retry.
  ///
  /// Where the codes live, verified rather than assumed: the scan-stream error
  /// is a `FlutterBluePlusException` whose `code` is the raw AOSP
  /// `ScanCallback.SCAN_FAILED_*` **int** (flutter_blue_plus.dart:364-368 ←
  /// FlutterBluePlusPlugin.java:2199-2213, :3042-3052). It is *not* a
  /// PlatformException — `startScan`'s own throw is
  /// `PlatformException(code: "startScan")` for every distinct cause
  /// (FlutterBluePlusPlugin.java:506, :529, :536, :543), one generic string
  /// with the detail only in the message. So the per-code policy has to hang
  /// off the int, and the string path falls through to the plain ladder.
  Duration? _scanBackoffFor(Object e) {
    final code = (e is FlutterBluePlusException &&
            e.platform == ErrorPlatform.android)
        ? e.code
        : null;
    // 2 s, 4 s, 8 s, 16 s, 32 s, then the 60 s ceiling. The shift is clamped so
    // a long-lived session cannot overflow it.
    final step = _clampBackoff(
        _scanErrorBackoffBase * (1 << (_scanErrorStreak - 1).clamp(0, 8)));
    switch (code) {
      case 4: // SCAN_FAILED_FEATURE_UNSUPPORTED — this radio will never scan.
        return null;
      case 5: // SCAN_FAILED_OUT_OF_HARDWARE_RESOURCES — 3× the current step,
        // bitchat's words: "so other scanners/connections can free up".
        return _clampBackoff(step * 3);
      case 6: // SCAN_FAILED_SCANNING_TOO_FREQUENTLY — flat 10 s. We are already
        // inside the quota window; climbing the ladder buys nothing, and the
        // window itself is only 30 s wide.
        return const Duration(seconds: 10);
      default:
        // 1 ALREADY_STARTED, 2 APPLICATION_REGISTRATION_FAILED ("common
        // transient stack fault. Previously had NO retry, which left discovery
        // dead until a manual BLE toggle" — bitchat's own postmortem),
        // 3 INTERNAL_ERROR, every iOS code, and PlatformExceptions.
        return step;
    }
  }

  Duration _clampBackoff(Duration d) =>
      d > _scanErrorBackoffMax ? _scanErrorBackoffMax : d;

  void _onScanStreamError(Object e) {
    // E3: FBP has already called `_stopScan(invokePlatform: false)` by the time
    // we get here, so Dart believes not-scanning while native still holds the
    // registration. Nothing to do about that from Dart — what we CAN do is stop
    // feeding the throttle.
    _scanRunning = false;
    _scanErrorStreak++;
    debugPrint('BLE scan stream error (streak $_scanErrorStreak): $e');
    if (AppConfig.calibScanMode) {
      _bumpCounter(_scanErrorCounts, _scanErrorLabel(e)); // W8
    }
    _scheduleBackoffRetry(e, 'stream-error');
  }

  static String _scanErrorLabel(Object e) {
    if (e is FlutterBluePlusException) return 'fbp:${e.code}:${e.description}';
    if (e is PlatformException) return 'platform:${e.code}';
    return e.runtimeType.toString();
  }

  /// Bounded BLE burst for the subtle-wake path
  /// (docs/SUBTLE_TRACKING_ARCHITECTURE.md): restarts the scan session so a
  /// fresh discovery window opens. Restarting the session is the only way
  /// repeated samples from one peer defeat duplicate coalescing (see
  /// LocationKeepalive). The bound is the platform's, not a timer's: a
  /// backgrounded app's wake window ends in seconds and iOS returns to the
  /// duty-cycled filtered carrier (BackgroundBeacon), so there is nothing to
  /// stop afterwards. Never throws and never starts a scan while off.
  Future<void> burst() async {
    if (!_isOn) return;
    debugPrint('BLE burst (subtle wake)');
    // A burst is a scan start like any other and spends from the same AOSP
    // quota (D6). If the bucket is dry the burst is deferred rather than
    // dropped — a wake that lands during a restart storm would otherwise be
    // the charge that silences the radio entirely.
    final cooldown = _scanStartCooldown();
    if (cooldown > Duration.zero) {
      _deferScanRestart(cooldown, 'subtle-wake burst');
      return;
    }
    await _restartScanning('subtle-wake burst');
  }

  Future<void> _stopBle() async {
    // Serialized behind any in-flight start; queued starts no-op via
    // _scanningWanted (already false by the time _stopBle is called on stop).
    try {
      await _serialScanOp(() async {
        await _scanSub?.cancel();
        _scanSub = null;
        _scanRunning = false;
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
    // iOS: the native carrier owns advertising + the filtered background
    // scan — stopping it also clears the persisted enabled flag so a BT
    // relaunch doesn't resurrect a beacon the user turned off.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      await _bgBeacon.stop();
    }
  }

  // --- BLE Implementation ---

  static const String _inRangeServiceUuid =
      '0000cafe-0000-1000-8000-00805f9b34fb';
  // (The 16-bit "cafe" short form of the marker now lives in the native
  // BackgroundBeacon module, which owns all iOS advertising.)
  static const int _inRangeManufacturerId = 0xFFFF;
  // W3: Apple's BLE company id — a backgrounded iPhone's overflow advert is
  // manufacturerData under this id with first payload byte 0x01.
  static const int _appleCompanyId = 0x004C;
  // The GATT characteristic the iOS native module serves the token from.
  static const String _inRangeTokenCharUuid =
      '0000ca7e-0000-1000-8000-00805f9b34fb';

  /// The advertised/claimed correlation id is now the raw 16 bytes of the
  /// server-issued opaque token (32 hex chars) — no HMAC. Peers hex these bytes
  /// back to the same token and report it; the server resolves it via the claim
  /// history the advertiser wrote. (#6 step 2)
  Uint8List _hexTo16Bytes(String hex) {
    final out = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  /// Fetches this user's server-issued opaque token batch for [dayUtc]. Returns
  /// [] in local mode or on failure, so the token source falls back to a random
  /// token and advertising never stalls.
  Future<List<BatchSlot>> _fetchTokenBatch(
      DateTime dayUtc, int windowMinutes) async {
    if (!AppConfig.hasRealSupabase) return const <BatchSlot>[];
    final dayStr = dayUtc.toIso8601String().split('T').first;
    // Timeout is load-bearing: with no/half-dead network this RPC HANGS
    // (S22 field incident 2026-07-23 — beacon button appeared dead, the
    // whole turnOnBeacon flow stuck here forever). A timeout throws, the
    // token source catches and falls back to a local random token, and BLE
    // comes up in local mode as designed.
    final rows = await InRangeSupabase.client.rpc('issue_token_batch', params: {
      'p_day': dayStr,
      'p_window_minutes': windowMinutes,
    }).timeout(const Duration(seconds: 8));
    if (rows is! List) return const <BatchSlot>[];
    final out = <BatchSlot>[];
    for (final r in rows) {
      if (r is Map &&
          r['token'] is String &&
          r['valid_from'] != null &&
          r['valid_until'] != null) {
        out.add(BatchSlot(
          token: r['token'] as String,
          validFrom: DateTime.parse('${r['valid_from']}').toUtc(),
          validUntil: DateTime.parse('${r['valid_until']}').toUtc(),
        ));
      }
    }
    return out;
  }

  Future<void> _startAdvertising() => _serialAdvOp(_startAdvertisingLocked);

  Future<void> _startAdvertisingLocked() async {
    // Beacon turned off while this op sat in the queue — do not resurrect.
    if (!_advertisingWanted) return;
    if (_currentToken == null || _currentCorrelationId == null) {
      throw StateError('No beacon token is available');
    }

    // iOS: the native BackgroundBeacon module owns advertising in BOTH
    // lifecycles now (W2/W4, docs/IOS_BACKGROUND_BLE_WIRING.md) — one
    // advertiser, no contention. Foreground it advertises the marker + the
    // rotating token as a second service UUID (today's path-b fast path,
    // kept); locked/backgrounded the advert degrades to the overflow area
    // and peers connect + read the token from the CA7E characteristic
    // instead, served per-read from the batch slots we pass here. Rotation
    // re-enters this method, so the module always holds the fresh batch.
    // Falls back to scan-only (fail-closed _advertisingUp) if the native
    // start reports no radio; the definitive verdict for BOTH roles arrives
    // via onBleState, which native pushes from `start`.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      final payload = BackgroundBeaconChannel.slotsPayload(
        _tokenSource.slots,
        currentToken: _currentToken!.token,
        currentFrom: _currentToken!.issuedAt,
        currentUntil: _currentToken!.expiresAt,
      );
      final ok = await _bgBeacon.start(payload);
      // Diag run secret first (before any W5 event can emit) so fleet HMAC
      // handles align and survive restoration. Gated on the compile-time diag
      // flag so the whole call — and the run-secret key literal — tree-shakes
      // out of production (B5). Awaited so provisioning lands before setW5Links
      // enables emits (B3 boot-before-provision ordering).
      if (AppConfig.kDiagBuild) {
        await _bgBeacon.setDiagRunSecret(AppConfig.diagRunSecret);
      }
      // W5 test gate: only establish persistent links when the build opts in.
      unawaited(_bgBeacon.setW5Links(AppConfig.w5LinksEnabled));
      // Crack #1: refresh the native wake-ping endpoint + JWT on every
      // (re)start — rotation re-enters here every ~15 min, keeping the
      // stored token fresh. Endpoint is null until the server half (issue
      // #4) ships, which keeps the native side silent.
      if (AppConfig.hasRealSupabase) {
        unawaited(_bgBeacon.setWakePing(
          url: AppConfig.wakePingUrl,
          auth: InRangeSupabase.client.auth.currentSession?.accessToken,
        ));
      }
      _applyAdvertisingVerdict(ok, 'native start');
      debugPrint(ok
          ? 'iOS native advertising armed (marker + GATT token carrier)'
          : 'iOS native advertising not ready → scan-only fallback');
      return;
    }
    _applyAdvertisingVerdict(true, 'android advertise start');

    final peripheral = FlutterBlePeripheral();
    // Legacy payload: mfg id + 16-byte corr + 1 flag byte (fits 31-byte AD).
    // Flag bit0 = medium-power slot. Field test 2026-07-13: Samsung's stack
    // does NOT update the TX Power Level AD when settings change, so the
    // slot marker must live in our own payload. Remaining flag bits are
    // reserved (future mesh relay bit). 16-byte adverts = legacy = high.
    final payload = Uint8List(17)
      ..setRange(0, 16, _currentCorrelationId!)
      ..[16] = _advPower == AdvertPower.medium ? 0x01 : 0x00;
    // W1 (IOS_BACKGROUND_BLE_WIRING.md): also advertise the fixed CAFE
    // discovery marker — a backgrounded iPhone can only scan with an exact
    // service-UUID filter, and mfgData alone can never match one. Android
    // encodes base-UUID-aliased UUIDs as 16-bit on air, so this costs 4
    // bytes: flags 3 + mfg AD 21 + svc AD 4 = 28 ≤ 31. Verify on-device
    // that BOTH fields still arrive (some stacks mis-handle mixed ADs).
    final advertiseData = AdvertiseData(
      manufacturerId: _inRangeManufacturerId,
      manufacturerData: payload,
      serviceUuids: const [_inRangeServiceUuid],
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
      if (AppConfig.calibScanMode) {
        // W6: every RSSI distribution is only interpretable against the
        // receiver that produced it. rangeEstimator's nearMedianDbm = −80 is
        // locked to one S9 walk (2026-07-17), so every other model is off by an
        // unknown constant and cross-device comparisons inherit the error
        // silently. Android's Bluetooth adapter name IS the device name
        // ("Galaxy S9"), which is the tag we can get without pulling in a
        // device_info dependency. The exact OS build (W10) matters just as much
        // — D7's demotion timeout is 30 min on ≤13 and 10 min on 14+ — but that
        // needs a platform channel this file does not own.
        _receiverTag = await FlutterBluePlus.adapterName;
        debugPrint('W6 receiver=$_receiverTag');
      }
    } catch (e) {
      debugPrint('BLE radio capability probe failed: $e');
    }
  }

  bool _capsLogged = false;
  String _receiverTag = 'unknown';

  // ===== Session state listeners (E2 / E8) ================================

  StreamSubscription<BluetoothAdapterState>? _adapterStateSub;
  BluetoothAdapterState? _lastAdapterState;
  StreamSubscription<PeripheralState>? _peripheralStateSub;
  PeripheralState? _lastPeripheralState;

  /// True once we know the advertiser is down while we still want it up, so a
  /// later "the radio is usable again" transition knows to re-advertise.
  bool _advertiserDown = false;

  /// Subscribes for the beacon session. Both streams re-emit their CURRENT
  /// state to a new listener — FBP via `newStreamWithInitialValue`
  /// (flutter_blue_plus.dart:204-206), flutter_ble_peripheral via
  /// `StateChangedHandler.onListen` publishing its cached state — so the first
  /// event of each is a baseline, not a transition, and must not be acted on.
  void _startStateListeners() {
    if (_adapterStateSub == null) {
      _lastAdapterState = null;
      _adapterStateSub = FlutterBluePlus.adapterState.listen(
        _onAdapterState,
        onError: (Object e) => debugPrint('adapterState stream error: $e'),
      );
    }
    // iOS: the native carrier is the only advertiser/scanner, and its state
    // arrives by push. A push can be dropped by a suspended engine, so the
    // session also watches for resume and re-reads.
    _startResumeWatch();
    // Android only: on iOS the native BackgroundBeacon carrier owns advertising
    // and reports through onAdvertisingState / onBleState, and
    // flutter_ble_peripheral is a dead dependency there (E9).
    if (_peripheralStateSub == null &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      _lastPeripheralState = null;
      _advertiserDown = false;
      final stream = FlutterBlePeripheral().onPeripheralStateChanged;
      if (stream != null) {
        _peripheralStateSub = stream.listen(
          _onPeripheralState,
          onError: (Object e) =>
              debugPrint('peripheralState stream error: $e'),
        );
      }
    }
  }

  void _stopStateListeners() {
    _adapterStateSub?.cancel();
    _adapterStateSub = null;
    _lastAdapterState = null;
    _peripheralStateSub?.cancel();
    _peripheralStateSub = null;
    _lastPeripheralState = null;
    _advertiserDown = false;
    _stopResumeWatch();
    // A "receive path is dead" verdict must not survive into the next session:
    // after off→on the native managers are re-created and the old verdict would
    // hold `discoverable` false over a perfectly healthy beacon. Same reasoning
    // as rangeEstimator.clear() in turnOffBeacon (reviewer #17).
    _receivePathConfirmTimer?.cancel();
    _receivePathConfirmTimer = null;
    _receivePathDown = false;
    _nativeBleState = null;
    _nativeBleStateUnknown = false;
  }

  // ===== iOS two-manager BLE state (finding 1.3) ==========================
  //
  // What this section is for: until 2026-07-26 the ENTIRE native BLE surface
  // Dart consumed was `onAdvertisingState(bool)`, which covered
  // CBPeripheralManager only and was raised `false` for radio-off,
  // permission-denied and a transient didStartAdvertising failure alike, while
  // `centralManagerDidUpdateState` reported nothing at all
  // (BackgroundBeacon.swift:477-485). Two consequences shipped:
  //
  //  1. The app could be advertising happily with a DEAD central manager — no
  //     scanning, no GATT reads, no sightings — and the UI would say
  //     discoverable. In Range needs both directions before an encounter
  //     exists, so that state produces nothing while claiming to work.
  //  2. Every reason for "not advertising" looked identical, so the app could
  //     not say "turn Bluetooth on" vs "grant Bluetooth in Settings" vs "we'll
  //     retry", and never did.
  //
  // e5d40e4 made native report both roles fully. This section is the consumer;
  // without it the native change delivers nothing user-visible.

  /// Last authoritative native BLE state, or null when we have never had one
  /// (non-iOS, pre-`onBleState` native build, or a failed read). Null means
  /// UNKNOWN — see [nativeBleStateUnknown]. It is never evidence of health.
  NativeBleState? _nativeBleState;
  NativeBleState? get nativeBleState => _nativeBleState;

  /// True when the last [readBleState] came back null while we expected an
  /// answer. Recorded rather than papered over: a channel that cannot answer is
  /// not the same as a radio that is fine, and the two were indistinguishable
  /// before.
  bool _nativeBleStateUnknown = false;
  bool get nativeBleStateUnknown => _nativeBleStateUnknown;

  /// Debounced verdict: the scan side is down while the beacon wants it up.
  /// Gates [discoverable] so the app cannot claim to be working when it cannot
  /// hear anybody.
  bool _receivePathDown = false;
  bool get receivePathDown => _receivePathDown;

  /// Why advertising is down, kept as the THREE distinguishable causes the old
  /// bool collapsed into one `false`. Null when advertising is up (or unknown).
  ///
  ///  * `radio:poweredOff` / `radio:unauthorized` / `radio:unsupported` — the
  ///    peripheral manager itself. `advertisingError` is deliberately null in
  ///    these cases on the native side (BackgroundBeacon.swift:488-490), so the
  ///    reason has to be read off [NativeBleState.peripheral].
  ///  * `startFailed:<message>` — a real `didStartAdvertising` error with the
  ///    radio up. Transient and retryable; NOT something to tell the user to fix.
  ///  * `notStarted` — radio fine, no error, nothing advertising yet.
  String? get advertisingDownReason {
    final s = _nativeBleState;
    if (s == null || s.advertising) return null;
    if (!s.peripheral.isUsable) return 'radio:${s.peripheral.name}';
    final err = s.advertisingError;
    return err == null ? 'notStarted' : 'startFailed:$err';
  }

  /// Fired whenever [discoverable] flips, so a UI holding a snapshot can
  /// repaint. Wired by BeaconController — without it the controller only
  /// sampled `discoverable` at toggle/restore, so a mid-session radio death
  /// updated this service and the badge stayed stale until the next toggle.
  /// That is the one case the don't-lie-about-discoverability rule exists for:
  /// nothing the user did caused it, so nothing the user does will repaint it.
  void Function(bool discoverable)? onDiscoverabilityChanged;

  void _applyAdvertisingVerdict(bool advertising, String source) {
    if (_advertisingUp == advertising) return;
    final before = discoverable;
    _advertisingUp = advertising;
    debugPrint('BLE advertise side ${advertising ? "UP" : "DOWN"} ($source)'
        '${advertising ? "" : " reason=${advertisingDownReason ?? "unknown"}"}');
    if (discoverable != before) _notifyDiscoverability();
  }

  void _setReceivePathDown(bool down, String why) {
    if (_receivePathDown == down) return;
    final before = discoverable;
    _receivePathDown = down;
    debugPrint(down
        ? 'BLE receive side DOWN ($why) — advertising=$_advertisingUp, '
            'discoverable now false'
        : 'BLE receive side recovered ($why)');
    if (discoverable != before) _notifyDiscoverability();
  }

  void _notifyDiscoverability() {
    try {
      onDiscoverabilityChanged?.call(discoverable);
    } catch (e) {
      debugPrint('onDiscoverabilityChanged callback error: $e');
    }
  }

  void _onNativeBleState(NativeBleState state) {
    _nativeBleState = state;
    _nativeBleStateUnknown = false;
    _applyAdvertisingVerdict(state.advertising, 'onBleState');
    _evaluateReceivePath(state, 'push');
  }

  /// A snapshot's `scanning: false` is only believable after a delay.
  ///
  /// `BackgroundBeacon.swift restartScanNow` (:342-353) calls `stopScan()` and
  /// restarts 0.3 s later on the main queue, so ANY snapshot taken inside that
  /// window reports a healthy scanner as idle. A pushed state can land there
  /// too, despite the channel's note that it cannot: `notifyAdvertisingState`
  /// pushes from `peripheralManagerDidStartAdvertising` (:486-493, :607), which
  /// is not synchronised with the central manager at all — so the very first
  /// push of a session routinely carries `scanning: false` before the scan has
  /// started. Raising an alarm on one sample would therefore mark every healthy
  /// session's startup as broken.
  ///
  /// 3 s = 10× the gap, and the confirm is a fresh independent read rather than
  /// a re-check of the same stale snapshot.
  static const Duration _receivePathConfirmDelay = Duration(seconds: 3);
  Timer? _receivePathConfirmTimer;

  void _evaluateReceivePath(NativeBleState state, String source) {
    // The radio-level half needs NO debounce: a central manager that is
    // poweredOff / unauthorized / unsupported cannot be a 0.3 s artefact of a
    // scan restart, and it is exactly the case that was previously invisible.
    if (!state.central.isUsable) {
      _receivePathConfirmTimer?.cancel();
      _receivePathConfirmTimer = null;
      _setReceivePathDown(true, 'central=${state.central.name} ($source)');
      return;
    }
    if (state.scanning || !state.enabled) {
      _receivePathConfirmTimer?.cancel();
      _receivePathConfirmTimer = null;
      _setReceivePathDown(
          false, state.scanning ? 'scanning ($source)' : 'native idle');
      return;
    }
    // Enabled, central usable, not scanning: could be the restart gap. Confirm
    // with a second read before believing it.
    if (_receivePathDown || _receivePathConfirmTimer != null) return;
    _receivePathConfirmTimer = Timer(_receivePathConfirmDelay, () {
      _receivePathConfirmTimer = null;
      unawaited(_confirmReceivePath());
    });
  }

  Future<void> _confirmReceivePath() async {
    if (!_isOn) return;
    final again = await _bgBeacon.readBleState();
    if (again == null) {
      // Unknown is not "fine": leave the existing verdict standing rather than
      // clearing it, and say so in the log.
      _nativeBleStateUnknown = true;
      debugPrint('BLE receive-path confirm unreadable — verdict unchanged '
          '(receivePathDown=$_receivePathDown)');
      return;
    }
    _nativeBleState = again;
    _nativeBleStateUnknown = false;
    _applyAdvertisingVerdict(again.advertising, 'confirm');
    if (!again.central.isUsable || (again.enabled && !again.scanning)) {
      // Cleared by the next native push (any manager transition, and every
      // token rotation, which re-enters _startAdvertisingLocked → native
      // `start` → notifyBleState) or by the next resume re-read. No poll is
      // added here on purpose: a self-clearing timer is scan-health *recovery*,
      // which is on the walk-day freeze list — this surface only reports.
      _setReceivePathDown(
          true,
          'idle in two reads ${_receivePathConfirmDelay.inSeconds}s apart, '
              'central=${again.central.name}');
    } else {
      _setReceivePathDown(false, 'scan-restart gap, not a failure');
    }
  }

  /// Authoritative re-read of the native BLE state. Public so the resume path,
  /// and any future caller, can force reconciliation.
  ///
  /// Needed because `onBleState` is a push and a push issued while the app is
  /// backgrounded is accepted then silently dropped by a suspended engine —
  /// exactly the hazard the native sighting BUFFER exists to work around
  /// (drainBufferedSightings + ack, audit 2026-07-25 round 3). State has no
  /// buffer, so it has to be pulled.
  ///
  /// A null answer is UNKNOWN and is never treated as healthy: nothing
  /// pessimistic is cleared on null.
  Future<NativeBleState?> refreshNativeBleState() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return null;
    final state = await _bgBeacon.readBleState();
    if (state == null) {
      _nativeBleStateUnknown = true;
      debugPrint('iOS BLE state unreadable → UNKNOWN (not healthy). '
          'Last known: ${_nativeBleState ?? "none"}; '
          'discoverable stays $discoverable');
      return null;
    }
    debugPrint('iOS BLE state re-read: $state');
    _nativeBleState = state;
    _nativeBleStateUnknown = false;
    _applyAdvertisingVerdict(state.advertising, 'resume re-read');
    _evaluateReceivePath(state, 'resume');
    return state;
  }

  /// One lifecycle observer, for one event. Registered here rather than in the
  /// provider because nothing in lib/ observed the lifecycle at all before this
  /// (no `WidgetsBindingObserver` anywhere), and the state that needs
  /// reconciling belongs to this service.
  _BeaconResumeObserver? _resumeObserver;

  void _startResumeWatch() {
    if (_resumeObserver != null) return;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    final binding = _maybeWidgetsBinding();
    if (binding == null) {
      debugPrint('No WidgetsBinding — iOS BLE resume re-read unavailable');
      return;
    }
    final obs = _BeaconResumeObserver(() {
      if (!_isOn) return;
      unawaited(refreshNativeBleState());
      // Drain on resume too, not only on the native push. `onBufferedSightingsReady`
      // is a push into a possibly-suspended engine — the identical hazard that
      // `readBleState()` exists to work around — and a dropped one leaves real
      // sightings sitting in UserDefaults until the next push happens to land.
      // On a walk with both phones locked for long stretches that is exactly the
      // data we came to collect, and the drain is idempotent (pull-and-ack: the
      // native side only discards what we acknowledge), so a redundant call costs
      // one empty channel round trip.
      unawaited(_drainNativeBuffer());
    });
    _resumeObserver = obs;
    binding.addObserver(obs);
  }

  void _stopResumeWatch() {
    final obs = _resumeObserver;
    if (obs == null) return;
    _resumeObserver = null;
    _maybeWidgetsBinding()?.removeObserver(obs);
  }

  /// `WidgetsBinding.instance` throws when no binding exists: a FlutterError
  /// from `BindingBase.checkInstance`'s assert in debug, a null-check TypeError
  /// in release/profile where that assert is stripped. Both are Objects, so one
  /// catch covers both. Bindings really are absent here — the
  /// flutter_background_service isolate (INRANGE_ENABLE_FGS) runs its own engine
  /// and `flutter test` bodies that do not call
  /// TestWidgetsFlutterBinding.ensureInitialized have none — and a beacon must
  /// never fail to start because an observability hook could not register.
  static WidgetsBinding? _maybeWidgetsBinding() {
    try {
      return WidgetsBinding.instance;
    } catch (_) {
      return null;
    }
  }

  /// E2 — the defect this exists for: a Bluetooth off→on toggle stops the FBP
  /// scan with **no error and no stream event**, through three layers.
  /// Android native FlutterBluePlusPlugin.java:2004-2015 calls
  /// `scanner.stopScan` on STATE_ON ("Bluetooth Restarted") and clears
  /// mIsScanning; Dart flutter_blue_plus.dart:485-487 calls
  /// `_stopScan(invokePlatform: false)` on any non-`on` state; and `_stopScan`
  /// (:424-436) cancels its internal subscription without ever closing or
  /// erroring `_scanResults`. Our listener therefore stays alive and receives
  /// nothing, forever (upstream #666, #849). Before this listener there was no
  /// persistent `adapterState.listen` anywhere in lib/ — only the one-shot
  /// prime inside _waitAdapterOn — so a routine BT toggle, or Samsung's stack
  /// restarting the adapter on its own, cost a full watchdog period of total
  /// blindness behind a green "beacon is active" notification.
  void _onAdapterState(BluetoothAdapterState state) {
    final prev = _lastAdapterState;
    _lastAdapterState = state;
    if (prev == null || prev == state) return; // baseline, or no transition
    debugPrint('BLE adapter ${prev.name} → ${state.name}');
    if (state != BluetoothAdapterState.on) {
      // The scan is gone whether or not anything told us. Say so.
      _scanRunning = false;
      return;
    }
    if (!_isOn || !_scanningWanted) return;
    // Through the token bucket, not straight to startScan: an adapter that
    // flaps must not machine-gun scanner registrations into AOSP's quota (D6),
    // which would trade one watchdog period of blindness for silence that no
    // callback ever ends.
    _requestScanRestart('adapter-on');
  }

  /// E8 — the Android twin of the iOS carrier's state reporting. Before this,
  /// the app had **no async advertising-health signal on Android at all**: a
  /// `start()` failure surfaces synchronously, but an advertiser that dies
  /// later (adapter restart, OEM reaping, ADVERTISE_FAILED_TOO_MANY_ADVERTISERS
  /// from another app) was invisible, and the user saw "active" while no peer
  /// could ever see them.
  ///
  /// `isAdvertising` is NOT used here and must not be: upstream #158,
  /// `stopPeripheral()` (FlutterBlePeripheralPlugin.kt:421-433) never publishes
  /// `PeripheralState.idle`, so the field it answers from is permanently stuck
  /// true. The redundant `stop()` before each `start()` in
  /// _startAdvertisingLocked works *because* of that bug — leave it alone.
  ///
  /// That same bug is what makes "uninitiated" decidable: since our own stop()
  /// publishes nothing, every event on this stream came from the adapter
  /// BroadcastReceiver (FlutterBlePeripheralPlugin.kt:57-81) or from an
  /// AdvertiseCallback outcome (PeripheralAdvertisingCallback.kt:11-46). None of
  /// them can be an echo of a stop we asked for.
  void _onPeripheralState(PeripheralState state) {
    final prev = _lastPeripheralState;
    _lastPeripheralState = state;
    if (prev == null || prev == state) return; // baseline, or no transition
    debugPrint('Advertiser ${prev.name} → ${state.name}');
    final wasAdvertising = prev == PeripheralState.advertising;
    switch (state) {
      case PeripheralState.advertising:
        _applyAdvertisingVerdict(true, 'peripheral advertising');
        _advertiserDown = false;
        return;
      case PeripheralState.poweredOff:
      case PeripheralState.unauthorized:
      case PeripheralState.unsupported:
        // Fail closed — the UI must never claim discoverability the radio
        // cannot deliver (reviewer #2). _startAdvertisingLocked sets
        // _advertisingUp = true optimistically on the Android path; this is the
        // correction.
        _applyAdvertisingVerdict(false, 'peripheral ${state.name}');
        // Don't retry into a radio that cannot advertise: peripheral.start()
        // would throw 'Bluetooth is off' and burn a log line. Remember instead,
        // and retry when the stream reports a usable state again — the adapter
        // coming back publishes `idle`, never `advertising`
        // (FlutterBlePeripheralPlugin.kt:66-79), so waiting for `advertising`
        // would wait forever.
        if (wasAdvertising) _advertiserDown = true;
        return;
      case PeripheralState.connected:
        // Should be unreachable: we advertise connectable: false and serve no
        // GATT server on Android. Not evidence about the advertiser either way.
        return;
      case PeripheralState.idle:
      case PeripheralState.unknown:
      case PeripheralState.shouldShowRequestPermissionRationale:
        break;
    }
    if (!(wasAdvertising || _advertiserDown)) return;
    if (!_isOn || !_advertisingWanted) return;
    debugPrint('Advertiser died uninitiated (${state.name}) — re-advertising');
    // Set before the attempt so a failed re-advertise is still remembered and
    // the next usable-state transition tries again. The ~30 s power-slot timer
    // is the existing backstop underneath this.
    _advertiserDown = true;
    unawaited(_startAdvertising().catchError((Object e) {
      debugPrint('Re-advertise after ${state.name} failed: $e');
    }));
  }

  /// Polls the BLE adapter until it reports `on`, up to [timeout]. Robust to
  /// the adapterState-stream race (see _startScanningLocked). Returns true as
  /// soon as it's on; false if the timeout elapses still-not-on.
  Future<bool> _waitAdapterOn(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    // Prime the plugin before polling. adapterStateNow is a passive cache
    // populated only by platform state-change events, and on iOS the native
    // CBCentralManager (whose creation triggers the first such event) is
    // created lazily on the first method-channel call — so on a cold process
    // with no prior FlutterBluePlus call the poll below would read `unknown`
    // until the deadline. The adapterState getter invokes getAdapterState,
    // which initializes the plugin and seeds the cache with the current
    // state; after that the event listener keeps it fresh and polling is
    // race-proof.
    try {
      await FlutterBluePlus.adapterState.first
          .timeout(deadline.difference(DateTime.now()));
    } catch (_) {
      // Priming failed or timed out — fall through; the poll decides.
    }
    while (true) {
      if (FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on) {
        return true;
      }
      if (DateTime.now().isAfter(deadline)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }

  Future<void> _startScanning() => _serialScanOp(_startScanningLocked);

  Future<void> _startScanningLocked() async {
    // Beacon turned off while this op waited in the queue — don't start a scan.
    if (!_scanningWanted) return;

    // iOS: CoreBluetooth starts in CBManagerStateUnknown and only reports
    // poweredOn asynchronously a beat after first use (and re-initialises
    // slowly after many beacon on/off cycles). Calling startScan before then
    // throws "bluetooth must be turned on (CBManagerStateUnknown)" even though
    // BT is on. We POLL adapterStateNow rather than await adapterState.firstWhere
    // — the stream only emits on CHANGES, so if BT flips to `on` between the
    // check and the subscription the event is missed and the wait spuriously
    // times out (root cause of the "press the toggle 2-3 times" lag,
    // 2026-07-17). Polling can't miss the transition. Android reports `on`
    // immediately → returns on the first poll.
    if (!await _waitAdapterOn(const Duration(seconds: 12))) {
      throw StateError(
          'Bluetooth is not ready (${FlutterBluePlus.adapterStateNow.name}). '
          'Turn Bluetooth on and try again.');
    }

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
      onError: _onScanStreamError,
    );
    _scanSub = sub;

    // Hardware msd filter (our manufacturer id) — required on Android, not an
    // optimization: Android ≥8.1 suppresses UNFILTERED scans while the
    // screen is off. Walk #1 (2026-07-13) proved it: 100% of scan
    // deliveries on both phones landed inside screen-awake windows.
    // The filter also confines results to In Range beacons.
    //
    // iOS: do NOT apply the msd filter. flutter_blue_plus filters MSD in
    // software on iOS, which would drop iPhone peers (they advertise service
    // UUIDs, no manufacturerData) — so iPhone↔iPhone would never see each
    // other. iOS foreground scanning has no screen-off suppression, so scan
    // unfiltered and match both carriers (mfg data + service UUID) in
    // _onScanResults.
    final calib = AppConfig.calibScanMode;
    final legacyOnly = AppConfig.scanLegacyPhyOnly;
    final isIOS =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(hours: 1),
        androidUsesFineLocation: true,
        continuousUpdates: true,
        // Android hardware filters are OR'd. Three matchers (issue #1 + W3):
        //  1. our mfg id             → Android peers (unchanged)
        //  2. CAFE service UUID      → foreground iPhones (token in advert)
        //  3. Apple mfg id, first payload byte 0x01 + mask → the Herald
        //     trick: matches BACKGROUNDED-iOS overflow adverts specifically;
        //     token then comes from a GATT read (W3). Keeps the scan
        //     hardware-filtered — Android ≥8.1 suppresses unfiltered
        //     screen-off scans (walk #1).
        withMsd: isIOS
            ? []
            : [
                MsdFilter(_inRangeManufacturerId),
                MsdFilter(_appleCompanyId, data: [0x01], mask: [0xFF]),
              ],
        withServices: isIOS ? [] : [Guid(_inRangeServiceUuid)],
        // E1: `androidLegacy` defaults to **false**
        // (flutter_blue_plus.dart:281), which makes
        // FlutterBluePlusPlugin.java:549-552 set
        // PHY_LE_ALL_SUPPORTED + setLegacy(false) — i.e. we were scanning both
        // PHYs. Every In Range peer advertises legacy 1M only: Android via
        // BluetoothLeAdvertiser.startAdvertising (17-byte legacy payload
        // above), iOS CBPeripheralManager is always legacy. So extended-PHY
        // scanning buys nothing and costs a share of the 1M duty cycle — and
        // per upstream #938 some Samsung phones run each PHY time slice as a
        // **4-second block**, so the cost lands as 4 s of total blindness at a
        // time (the attached log: adverts at 0:00:22.9, then nothing until
        // 0:00:26.9). That is missed peers in a crowd, worse time-to-detection,
        // and a silently corrupted RSSI sample distribution on the exact
        // hardware this app field-tests on. Legacy-only cannot reduce coverage
        // here, because there is nothing on the other PHYs to find.
        //
        // Behind INRANGE_SCAN_LEGACY_ONLY (default true = the fix). PHY
        // time-slicing is a receiver-side behaviour, so setting this false on
        // one handset and true on the other, in the same room, is a valid A/B:
        // the false leg's W9 advert-gap histogram should carry a ~4 s mode the
        // true leg's does not. Without the flag, tomorrow's walk can only show
        // that gaps are absent — which does not distinguish "the fix worked"
        // from "#938 never applied to a Galaxy S9".
        androidLegacy: legacyOnly,
        androidScanMode:
            calib ? AndroidScanMode.lowLatency : AndroidScanMode.balanced,
      );
      // Charged only on a start that actually reached the platform: AOSP bills
      // at scanner registration, and a startScan that threw never registered.
      _scanStartLedger.add(DateTime.now());
      _scanRunning = true;
      _scanSeq++;
      _scanStartedAt = DateTime.now();
    } catch (e) {
      // This op's own listener must not outlive a failed/aborted start.
      _scanRunning = false;
      if (AppConfig.calibScanMode) {
        // W8: the marker that tells tomorrow's walk apart from a walk with an
        // unknown-length hole in it. A scan-start failure previously left no
        // trace at all beyond a debugPrint on the way out.
        _bumpCounter(_scanErrorCounts, _scanErrorLabel(e));
        debugPrint('W8 scan-start FAILED seq=${_scanSeq + 1} '
            '${_scanErrorLabel(e)} '
            '${e is PlatformException ? e.message : e}');
      }
      await sub.cancel();
      if (identical(_scanSub, sub)) _scanSub = null;
      rethrow;
    }
    // Turned off during startScan → undo, don't leave a live hardware scan.
    if (!_scanningWanted) {
      await sub.cancel();
      if (identical(_scanSub, sub)) _scanSub = null;
      _scanRunning = false;
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
      return;
    }
    debugPrint('BLE scan started (filtered msd=0xFFFF, '
        '${legacyOnly ? "legacy-1M" : "all-PHY"}, '
        '${calib ? "lowLatency/calib" : "balanced"})');
    // A/B arm attribution. Deliberately NOT calibScanMode-gated: knowing which
    // arm produced a log matters in a normal build too, and the failure mode
    // this guards against is a walk log that cannot be assigned to a leg after
    // the fact — which is precisely how e5d40e4 lost the E1/D7 baseline in the
    // first place. One line per scan start (~8 min), so it is not noisy.
    debugPrint('BLE scan arm: INRANGE_SCAN_LEGACY_ONLY=$legacyOnly '
        'INRANGE_SCAN_RESTART_MINUTES=${AppConfig.scanRestartMinutes}');
    if (calib) {
      // W8: success marker + the gap since the last scan result **of any kind**,
      // In Range peer or not. That gap is the whole point — if the scanner dies
      // at minute 40 of a three-hour walk, the silence otherwise reads as
      // "nobody around" and contaminates every label derived from the segment.
      final last = _lastAnyScanResultAt;
      debugPrint('W8 scan-start ok seq=$_scanSeq receiver=$_receiverTag '
          'bucket=${_scanStartLedger.length}/$_scanStartBudget per '
          '${_scanStartWindow.inSeconds}s gapSinceAnyResult='
          '${last == null ? "none-yet" : "${DateTime.now().difference(last).inSeconds}s"}');
    }
  }

  // ===== Walk-day instruments (W1–W9) ====================================
  //
  // docs/BLE_PRIOR_ART_REVIEW_2026-07-26.md, "safe to add tonight" table. Each
  // of these converts a *claim* in that document into a *number* from the
  // 2026-07-27 walk. All of it is calibScanMode-gated: production installs no
  // timer, allocates no counter and takes no extra radio call, so a release
  // build behaves identically with and without this section. None of them
  // changes a policy decision — the fixes they justify (GATT semaphore,
  // outcome-aware backoff, stranger quarantine, keepalive jitter, all-zero
  // overflow rejection) are all on the freeze list until the data exists.

  /// Scan session counter, so a log line can be attributed to one scan window
  /// even though the window (8 min) and the report cadence (10 min) differ.
  int _scanSeq = 0;
  DateTime? _scanStartedAt;

  /// W8: last delivery of ANY kind from the scan stream.
  DateTime? _lastAnyScanResultAt;

  Timer? _calibReportTimer;
  DateTime? _calibWindowStart;

  /// W1: high-water mark of concurrent native GATT connects. This single number
  /// justifies or kills the bounded-semaphore work (1.1) — if the burst never
  /// exceeds 2 there is nothing to bound.
  int _gattInflightPeak = 0;

  /// W2: GATT outcome histogram. Buckets are `success` / `bad_length` /
  /// `no_service` / the native failure code (`connect_failed`, `timeout`,
  /// `read_failed`, `bt_off`, `no_permission`, `bad_args`, `channel_error`) /
  /// `failed` for a null return that carried no code. The native split reaches
  /// Dart via NativeGattTokenReader.readToken's `onFailure` — before 2026-07-26
  /// that wrapper collapsed all six codes into one bucket, which would have made
  /// tomorrow's histogram unable to answer the question it exists for.
  final Map<String, int> _gattOutcomeCounts = <String, int>{};

  /// W8: scan-failure histogram by FBP/platform code.
  final Map<String, int> _scanErrorCounts = <String, int>{};

  /// W3: distinct MACs by fate. Matched the Apple 0x01 hardware filter vs
  /// answered `no_service` vs actually served a token. Puts a number on "most
  /// of the room is strangers" (1.6), and the ratio of matched MACs to peers
  /// over a window is the observed MAC-rotation rate — which is what decides
  /// whether per-MAC quarantine is even viable.
  final Set<String> _w3MatchedMacs = <String>{};
  final Set<String> _w3NoServiceMacs = <String>{};
  final Set<String> _w3TokenMacs = <String>{};

  /// W4: gap between consecutive keepalive dispatches, 5 s bins. Herd
  /// synchronisation (1.8) shows up immediately as a bimodal distribution.
  /// MEASURE ONLY — the jitter fix is frozen until this says it is needed.
  final SplayTreeMap<int, int> _keepaliveGapHist = SplayTreeMap<int, int>();
  DateTime? _lastKeepaliveDispatchAt;

  /// W6: raw In Range RSSI distribution for this receiver, 5 dBm bins.
  final SplayTreeMap<int, int> _rssiHist = SplayTreeMap<int, int>();

  /// W9: per-peer inter-advert arrival gaps, 500 ms bins.
  final SplayTreeMap<int, int> _advertGapHist = SplayTreeMap<int, int>();

  static void _bumpCounter(Map<String, int> m, String key) {
    m[key] = (m[key] ?? 0) + 1;
  }

  static void _bumpBin(SplayTreeMap<int, int> m, int bin) {
    m[bin] = (m[bin] ?? 0) + 1;
  }

  /// 500 ms bins up to 6 s, then 1 s. Fine enough to separate E1's ~4 s Samsung
  /// dual-PHY block (upstream #938's log shows 22.9 s → 26.9 s) from ordinary
  /// advertising jitter, which is what makes the histogram readable as bimodal
  /// or not.
  static int _gapBin(int ms) {
    if (ms < 6000) return (ms ~/ 500) * 500;
    if (ms < 60000) return (ms ~/ 1000) * 1000;
    return 60000;
  }

  void _resetCalibWindow() {
    _calibWindowStart = DateTime.now();
    _gattInflightPeak = _gattInflight.length;
    _gattOutcomeCounts.clear();
    _scanErrorCounts.clear();
    _w3MatchedMacs.clear();
    _w3NoServiceMacs.clear();
    _w3TokenMacs.clear();
    _keepaliveGapHist.clear();
    _rssiHist.clear();
    _advertGapHist.clear();
  }

  /// One consolidated window report. Pure counter reads — no radio calls, no
  /// state changes, nothing that can fail.
  void _logCalibWindowReport() {
    final start = _calibWindowStart;
    final now = DateTime.now();
    final windowS = start == null ? 0 : now.difference(start).inSeconds;
    final scanAgeS = _scanStartedAt == null
        ? -1
        : now.difference(_scanStartedAt!).inSeconds;
    final lastAny = _lastAnyScanResultAt;
    debugPrint('=== calib window ${windowS}s receiver=$_receiverTag '
        'scanSeq=$_scanSeq scanAge=${scanAgeS}s scanRunning=$_scanRunning ===');
    // W8
    debugPrint('W8 lastAnyResult='
        '${lastAny == null ? "none" : "${now.difference(lastAny).inSeconds}s ago"} '
        'lastInRangePeer='
        '${_lastForeignScanAt == null ? "none" : "${now.difference(_lastForeignScanAt!).inSeconds}s ago"} '
        'startsInWindow=${_scanStartLedger.length}/$_scanStartBudget '
        'errorStreak=$_scanErrorStreak errors=$_scanErrorCounts');
    // W1
    debugPrint('W1 gattInflight now=${_gattInflight.length} '
        'peak=$_gattInflightPeak');
    // W2
    debugPrint('W2 gattOutcomes=$_gattOutcomeCounts');
    // W3
    debugPrint('W3 distinctMacs matchedAppleFilter=${_w3MatchedMacs.length} '
        'noService=${_w3NoServiceMacs.length} servedToken=${_w3TokenMacs.length}');
    // W4
    debugPrint('W4 keepaliveGapHist(sBin:count)=$_keepaliveGapHist');
    // W6
    debugPrint('W6 rssiHist(dBmBin:count)=$_rssiHist');
    // W9
    debugPrint('W9 advertGapHist(msBin:count)=$_advertGapHist');
    _resetCalibWindow();
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
    // A delivery of ANY kind is proof the scanner is alive — the question
    // `_lastForeignScanAt` structurally cannot answer, because it is bumped only
    // inside _ingestForeignSample, i.e. only when a real In Range peer decodes
    // (C3). Also the reset point for the onError backoff ladder: the ladder must
    // measure the current incident, not the whole session. A pending retry is
    // deliberately NOT cancelled here — after E3's desync the results reaching
    // us may be the tail of a subscription FBP has already abandoned, so one
    // restart is the cheap way back to a known-good state.
    _lastAnyScanResultAt = DateTime.now();
    _scanRunning = true;
    _scanErrorStreak = 0;
    if (!_isOn) return;
    for (final r in results) {
      final deviceId = r.device.remoteId.str;
      final prevTs = _lastAdvertTsByDevice[deviceId];
      if (prevTs != null && !r.timeStamp.isAfter(prevTs)) continue; // stale
      // W9: per-peer inter-advert gap. CAVEAT (E12): ScanResult.timeStamp is
      // DateTime.now() taken when the **Dart isolate** processed the message
      // (flutter_blue_plus.dart:733-736) — Android's radio
      // getTimestampNanos() is never forwarded — so it carries UI-isolate
      // scheduler jitter. Only gaps ≥1 s mean anything, and that is exactly
      // where both effects we are hunting live: E1's ~4 s Samsung dual-PHY
      // block and D7's mid-window scan-mode demotion.
      if (prevTs != null && AppConfig.calibScanMode) {
        final gapMs = r.timeStamp.difference(prevTs).inMilliseconds;
        _bumpBin(_advertGapHist, _gapBin(gapMs));
        if (gapMs >= 1000) {
          debugPrint('W9 gap dev=$deviceId ${gapMs}ms seq=$_scanSeq');
        }
      }
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

      // iOS foreground service-UUID carrier (path b): if the fixed discovery
      // marker is advertised, the OTHER 128-bit service UUID is the token.
      // Match the marker by value (robust to 16-bit vs 128-bit form); take the
      // 16-byte UUID that isn't the marker. This is how iPhones are discovered
      // (they can't send manufacturerData). No power flag on iOS → high.
      if (observedCorrelationId == null && adv.serviceUuids.isNotEmpty) {
        final marker = Guid(_inRangeServiceUuid);
        if (adv.serviceUuids.any((u) => u == marker)) {
          for (final u in adv.serviceUuids) {
            if (u != marker && u.bytes.length == 16) {
              observedCorrelationId = Uint8List.fromList(u.bytes);
              break;
            }
          }
        }
      }

      if (observedCorrelationId == null) {
        // W3: a backgrounded iPhone — Apple overflow advert matched by the
        // hardware filter, but the token is NOT on the air. Recover it with
        // a GATT read (cached per device so each rotation costs one
        // connect); RSSI always comes from this scan result, never the
        // connection. Android-only: on iOS the native module owns this.
        if (defaultTargetPlatform == TargetPlatform.android) {
          final apple = adv.manufacturerData[_appleCompanyId];
          if (apple != null && apple.isNotEmpty && apple[0] == 0x01) {
            if (AppConfig.calibScanMode) {
              _w3MatchedMacs.add(deviceId); // W3
              // W7: the WHOLE overflow payload, not just byte 0. Herald rejects
              // all-zero overflow adverts as provably-not-a-peer (A8) and we
              // have never looked past byte 0, so we cannot say what share of a
              // crowd that is — nor how much GATT budget it eats. The fix stays
              // frozen; this is only the measurement.
              debugPrint('W7 overflow dev=$deviceId rssi=${r.rssi} apple='
                  '${apple.map((b) => b.toRadixString(16).padLeft(2, "0")).join()}');
            }
            final cachedHex = _gattTokenByDevice[deviceId];
            final cachedAt = _gattTokenAt[deviceId];
            final cacheFresh = cachedHex != null &&
                cachedAt != null &&
                DateTime.now().difference(cachedAt) <
                    const Duration(minutes: 15);
            if (cacheFresh) {
              if (AppConfig.calibScanMode) {
                debugPrint(
                    'W3 overflow dev=$deviceId rssi=${r.rssi} → cached '
                    '${cachedHex.substring(0, 8)} (age ${DateTime.now().difference(cachedAt).inSeconds}s)');
              }
              _ingestForeignSample(cachedHex, r.rssi, AdvertPower.high);
            } else if (AppConfig.calibScanMode) {
              debugPrint('W3 overflow dev=$deviceId rssi=${r.rssi} → no cache');
            }
            // KEEPALIVE, not just token recovery: our GATT read is the only
            // thing that wakes a sleeping iPhone into scanning back (its
            // scan restarts piggyback on incoming reads — BackgroundBeacon
            // .swift). First dark bench (2026-07-23): a 15 min cache meant
            // no reads for 15 min, and the locked iPhone's return direction
            // died ~30 s after lock. So while a peer advertises in overflow
            // form (= it is asleep), re-read every ~75 s; reciprocity needs
            // BOTH witnesses.
            final lastRead = _gattTokenAt[deviceId];
            final needKeepalive = !cacheFresh ||
                lastRead == null ||
                DateTime.now().difference(lastRead) >
                    const Duration(seconds: 75);
            if (needKeepalive) {
              unawaited(_recoverTokenViaGatt(deviceId, r.rssi,
                  isKeepalive: cacheFresh));
            }
          }
        }
        continue;
      }

      final hexId = observedCorrelationId
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();

      // Which power slot sent this advert: flag byte in our payload
      // (Samsung's TX Power Level AD proved unreliable). Missing flag =
      // legacy advert = high — the safe direction: feet_30 can only
      // under-fire, never claim mid-range falsely.
      final power = mediumFlag ? AdvertPower.medium : AdvertPower.high;
      _ingestForeignSample(hexId, r.rssi, power);
    }
  }

  // W3 GATT token recovery state: token cache (one connect per rotation),
  // per-device attempt backoff (strangers' iPhones cost one failed
  // service-discovery, then silence), and an in-flight guard.
  final Map<String, String> _gattTokenByDevice = {};
  final Map<String, DateTime> _gattTokenAt = {};
  final Map<String, DateTime> _gattLastAttempt = {};
  final Set<String> _gattInflight = {};

  Future<void> _recoverTokenViaGatt(String deviceId, int rssi,
      {bool isKeepalive = false}) async {
    if (_gattInflight.contains(deviceId)) return;
    final last = _gattLastAttempt[deviceId];
    // The 5 min backoff protects against strangers' iPhones (one failed
    // service-discovery, then silence). Keepalive reads target devices that
    // already served our token — they get the short cadence instead.
    final floor =
        isKeepalive ? const Duration(seconds: 75) : const Duration(minutes: 5);
    if (last != null && DateTime.now().difference(last) < floor) {
      return;
    }
    debugPrint(
        'W3 GATT ${isKeepalive ? "keepalive" : "recover"} → connecting $deviceId');
    _gattLastAttempt[deviceId] = DateTime.now();
    if (_gattLastAttempt.length > 200) {
      final cutoff = DateTime.now().subtract(const Duration(minutes: 30));
      _gattLastAttempt.removeWhere((_, at) => at.isBefore(cutoff));
    }
    _gattInflight.add(deviceId);
    if (AppConfig.calibScanMode) {
      // W1: current + peak concurrent connects, logged at each dispatch. The
      // decision this settles: 1.1's bounded semaphore is worth writing only if
      // the burst is real and wide. Dispatch is fire-and-forget via `unawaited`
      // with no queue and no ordering, so in a mall leg this is the only place
      // the width is observable.
      if (_gattInflight.length > _gattInflightPeak) {
        _gattInflightPeak = _gattInflight.length;
      }
      // W4: gap between consecutive keepalive dispatches. Every peer's floor is
      // the same fixed 75 s measured from its own last read, so peers first seen
      // together stay locked together — herd synchronisation (1.8) would show
      // here as a bimodal distribution with a mode at ~0 s. MEASURE ONLY: adding
      // jitter now would de-correlate the baseline before we have measured it.
      if (isKeepalive) {
        final prevDispatch = _lastKeepaliveDispatchAt;
        if (prevDispatch != null) {
          final gapS = DateTime.now().difference(prevDispatch).inSeconds;
          _bumpBin(_keepaliveGapHist, (gapS ~/ 5) * 5);
        }
        _lastKeepaliveDispatchAt = DateTime.now();
      }
      debugPrint('W1 gattInflight=${_gattInflight.length} '
          'peak=$_gattInflightPeak dev=$deviceId '
          '${isKeepalive ? "keepalive" : "recover"}');
    }
    try {
      // Native BluetoothGatt round-trip (GattTokenReader.kt) — the app's one
      // connect path, kept plugin-free so it carries no flutter_blue_plus
      // license obligation (iOS connects natively in BackgroundBeacon.swift
      // for the same reason). Disconnect/close is the native side's job.
      var stranger = false;
      String? failureCode;
      final bytes = await NativeGattTokenReader.readToken(
        deviceId,
        serviceUuid: _inRangeServiceUuid,
        charUuid: _inRangeTokenCharUuid,
        timeout: const Duration(seconds: 10),
        onStranger: () {
          stranger = true;
          debugPrint('W3 GATT $deviceId: no In Range service (stranger)');
        },
        onFailure: (code) => failureCode = code,
      );
      // W2/W3: outcome histogram + distinct-MAC fates. This is READ-ONLY — the
      // backoff floors above are untouched, because outcome-aware backoff (1.7)
      // is frozen until this data says which outcomes actually dominate.
      //
      // The split is now real. Until 2026-07-26 every non-`no_service` failure
      // fell into one `failed` bucket, because the wrapper swallowed the native
      // code — so W2 could not tell "the room is full of unreachable strangers"
      // (connect_failed) from "our 10 s timeout is too tight" (timeout) from
      // "the radio is off" (bt_off), which are three different fixes. The codes
      // come straight from GattTokenReader.kt; `failed` now means only the one
      // case that carries no code at all — a null return with no exception.
      if (AppConfig.calibScanMode) {
        _bumpCounter(
          _gattOutcomeCounts,
          bytes == null
              ? (stranger ? 'no_service' : (failureCode ?? 'failed'))
              : (bytes.length == 16 ? 'success' : 'bad_length'),
        );
        if (stranger) _w3NoServiceMacs.add(deviceId);
        if (bytes != null && bytes.length == 16) _w3TokenMacs.add(deviceId);
      }
      if (bytes != null) {
        debugPrint('W3 GATT $deviceId: read ${bytes.length} bytes');
        if (bytes.length == 16 && _isOn) {
          final hex =
              bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
          _gattTokenByDevice[deviceId] = hex;
          _gattTokenAt[deviceId] = DateTime.now();
          if (_gattTokenByDevice.length > 64) {
            final cutoff =
                DateTime.now().subtract(const Duration(minutes: 15));
            _gattTokenAt.removeWhere((id, at) {
              final stale = at.isBefore(cutoff);
              if (stale) _gattTokenByDevice.remove(id);
              return stale;
            });
          }
          _ingestForeignSample(hex, rssi, AdvertPower.high);
        }
      }
    } finally {
      _gattInflight.remove(deviceId);
    }
  }

  /// W5 owner rule (2026-07-24): a pass/reject resolves the pair — its live
  /// session (if any) is torn down immediately. Returns the native structured
  /// teardown result (`lookupHit`/`rolesClosed`/`leaseEnded`/
  /// `rawSessionsReaped`) so the caller can report honestly whether a lease was
  /// actually torn down; null off-iOS (native unavailable).
  Future<Map<String, dynamic>?> dropPeer(String tokenHex) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      return _bgBeacon.dropPeer(tokenHex);
    }
    return null;
  }

  /// Diagnostic control path for Case-1 pending-dial reclamation: arm a
  /// one-shot pre-HELLO_ACK fault for the next outbound dial to [peerAlias]
  /// (null = any next dial). No-op off-iOS and in any release binary (the
  /// native fault is compiled out outside the diag flavor).
  Future<void> armW5Fault({String? peerAlias}) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      await _bgBeacon.armW5Fault(peerAlias: peerAlias);
    }
  }

  /// Clear any pending diagnostic fault (peer-scoped control cleanup).
  Future<void> disarmW5Fault() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      await _bgBeacon.disarmW5Fault();
    }
  }

  /// Record a pass teardown outcome (sanitized summary) in the native evidence
  /// layer. No-op off-iOS.
  Future<void> recordW5Teardown(String outcome) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      await _bgBeacon.recordW5Teardown(outcome);
    }
  }

  /// Reset the current diagnostic CASE — retains the fleet secret, rotates the
  /// public case epoch, wipes evidence, clears controls. Returns the native ack.
  Future<Map<String, dynamic>?> resetW5Case() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      return _bgBeacon.resetW5Case();
    }
    return null;
  }

  /// Destroy the persisted fleet secret (rejected natively while W5 active).
  Future<Map<String, dynamic>?> destroyW5Secret() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      return _bgBeacon.destroyW5Secret();
    }
    return null;
  }

  /// Single ingest point for a foreign token sample — scan results and the
  /// iOS native carrier's sightings (W4) both land here, so the self-sight
  /// guard, estimator, calibration log and sighting bookkeeping stay one
  /// code path.
  void _ingestForeignSample(String hexId, int rssi, AdvertPower power,
      {DateTime? at}) {
    // Filter ALL of our own tokens, not just the current one — a leaked
    // advertiser from a prior beacon session kept broadcasting the OLD
    // token after off→on, and we self-sighted it at a rock-constant RSSI
    // for an entire field test (2026-07-13 walk).
    if (_ownCorrHexes.contains(hexId)) return;

    rangeEstimator.addObservation(
      hexId,
      ProximityObservation(
        source: ProximitySource.advertRssi,
        rssi: rssi,
        localState: defaultTargetPlatform == TargetPlatform.iOS ? 'locked' : 'scan',
      ),
      power: power,
    );
    // Raw per-advert persistence + verbose peer logging is CALIBRATION only.
    // In production it would retain a place/peer fingerprint and print peer
    // ids to release logs / bug reports (reviewer #18).
    if (AppConfig.calibScanMode) {
      try {
        onAdvertSample?.call(hexId, rssi, power, at ?? DateTime.now());
      } catch (e) {
        debugPrint('onAdvertSample callback error: $e');
      }
      // One line per fresh foreign advert — the calibration ground truth. The
      // per-advert RSSI is already here, so W6 only adds the two things missing:
      // the receiver tag (logged once per process in _logRadioCapabilities) and
      // a 5 dBm-binned distribution per window, which is the shape Herald's
      // self-calibration finding (A9/B9) needs and which is not recoverable
      // after the walk.
      _bumpBin(_rssiHist, (rssi / 5).floor() * 5);
      debugPrint(
          'Advert corr=${hexId.substring(0, 8)} rssi=$rssi pw=${power == AdvertPower.medium ? "M" : "H"} rx=$_receiverTag');
    }

    _lastForeignScanAt = DateTime.now();
    _recordLocalSighting(hexId, rssi, at: at);
  }

  double? _cachedLat;
  double? _cachedLon;
  double? _cachedAccuracy;
  DateTime? _cachedLocAt;
  Timer? _locationRefreshTimer;

  final Map<String, DateTime> _lastSightingAt = {};
  static const _sightingMinInterval = Duration(seconds: 5);

  void _recordLocalSighting(String observedCorrelationIdHex, int rssi,
      {DateTime? at}) {
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
      // A locked iPhone's natively-buffered sighting flushes minutes after
      // capture; the server (0053) accepts and stores the TRUE capture time,
      // so pass it through instead of the flush time.
      observedAt: at ?? now,
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
    //
    // ...with one exception: a record with no coordinates can never be sent.
    // _ensureLocationCache() above is fire-and-forget (a Timer plus up to 6 s
    // in getCurrentPosition) and turnOnBeacon does not await it, so sightings
    // observed in the first seconds of a session are built with a null
    // observerLat/observerLon. _flushSightings skips those records (they fail
    // record_sighting's required lat/lon) but only REMOVES a record after a
    // successful send — so without this clause a strong early sighting sticks
    // in _pendingByCorr forever: never uploadable because it has no
    // coordinates, never replaced because no later sample beats its RSSI, and
    // holding one of the _maxPendingSightings slots until FIFO eviction.
    // The peer is simply never reported, which reads as "it didn't detect me"
    // at exactly the moment a user is watching. Found by audit 2026-07-25.
    //
    // Coherence (reviewer #12) is preserved: we swap in a whole later sample
    // rather than stitching coordinates onto an older one.
    final prevUnusable =
        prev != null && (prev.observerLat == null || prev.observerLon == null);
    final thisUsable = record.observerLat != null && record.observerLon != null;
    if (prev == null || rssi > prev.rssi || (prevUnusable && thisUsable)) {
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

  void _onLocationFix(LocationAssistFix fix) {
    if (!_isOn) return;
    _cachedLat = fix.lat;
    _cachedLon = fix.lon;
    _cachedAccuracy = fix.accuracyM;
    _cachedLocAt = fix.at;
  }

  /// The sighting cache as a fix, for subtle-wake venue hints that arrived
  /// without one of their own. Null until the first fix of the session.
  LocationAssistFix? _cachedLocationFix() {
    final lat = _cachedLat, lon = _cachedLon, at = _cachedLocAt;
    if (lat == null || lon == null || at == null) return null;
    return LocationAssistFix(
      lat: lat,
      lon: lon,
      accuracyM: _cachedAccuracy ?? -1,
      at: at,
    );
  }

  /// Derives a local venue anchor from a successfully uploaded hint cell.
  /// The anchor id is the geohash itself, so revisiting the same cell replaces
  /// rather than duplicates. Radius is clamped by VenueAnchorService to the
  /// monitorable band (100–2000 m).
  void _onAnchorDerived(double lat, double lon, String? hashedBssid) {
    if (!_isOn) return;
    final geohash = SubtleWakeService.geohashEncode(lat, lon);
    venueAnchors.upsert(
      VenueAnchor(
        id: geohash,
        lat: lat,
        lon: lon,
        radiusM: 3500,
        hashedBssid: hashedBssid,
      ),
    );
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

  /// Fire-and-forget drain of the calibration upload queue.
  ///
  /// Swallows everything on purpose. The rows are already durable in SQLite and
  /// the watermark only advances on server acknowledgement, so a failure here
  /// costs nothing but a delay — whereas letting it escape would take down the
  /// flush timer and, on the stop path, the BLE teardown that follows it.
  Future<void> _flushUploads() async {
    final flush = onFlushUploads;
    if (flush == null) return;
    try {
      await flush();
    } catch (e) {
      debugPrint('RSSI upload flush failed (will retry): $e');
    }
  }

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
        }).timeout(const Duration(seconds: 10));
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
    _currentToken = await _tokenSource.nextToken();
    _currentCorrelationId = _hexTo16Bytes(_currentToken!.token);
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

    // Pre-claim the whole issued batch (0060) so tokens the native carrier
    // serves while Dart is suspended or evicted still resolve server-side.
    // Self-throttled — fires at session start and day rollover, not per
    // rotation. Runs before the single claim so its 1-minute throttle never
    // trips on a fresh single-claim row.
    unawaited(_preclaimBatch());

    // Retries the SAME live token with bounded backoff; ClaimManager fires
    // onState (→ onClaimStateChanged) after every attempt.
    await _claimMgr.attempt(gen);
  }

  DateTime? _lastBatchPreclaim;

  /// One claim_token_batch RPC per 6 h (migration 0060): makes every slot
  /// the native iOS carrier can serve resolvable through token_claim_history
  /// while Dart is suspended. Failures are swallowed — the live per-rotation
  /// claim still covers the current slot; the pre-claim is the safety net.
  /// The backoff timestamp is set only on SUCCESS: a failed attempt must not
  /// suppress the retry due on the next rotation.
  Future<void> _preclaimBatch() async {
    final now = DateTime.now();
    final last = _lastBatchPreclaim;
    if (last != null && now.difference(last) < const Duration(hours: 6)) {
      return;
    }
    try {
      await InRangeSupabase.client.rpc('claim_token_batch', params: {
        'p_range': _mapUiRangeToDb(_claimRangeType ?? 'feet_60'),
      }).timeout(const Duration(seconds: 10));
      _lastBatchPreclaim = now;
      debugPrint('claim_token_batch OK');
    } catch (e) {
      debugPrint('claim_token_batch failed: $e');
    }
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
    // Timeout: a hanging claim (dead network) must fail the attempt so
    // ClaimManager's bounded retry + the "Local BLE only" fallback engage,
    // instead of wedging the whole beacon-on flow (S22 2026-07-23).
    await InRangeSupabase.client.rpc('claim_token', params: {
      'p_token': claimToken,
      'p_valid_until': until.toIso8601String(),
      'p_lat': _cachedLat,
      'p_lon': _cachedLon,
      'p_range': _mapUiRangeToDb(_claimRangeType ?? 'feet_60'),
      'p_accuracy': _cachedAccuracy,
    }).timeout(const Duration(seconds: 10));
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
      await InRangeSupabase.client
          .rpc('release_token')
          .timeout(const Duration(seconds: 8));
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

/// Minimal lifecycle observer: BeaconService needs exactly one event, and
/// `WidgetsBindingObserver`'s other twenty no-op overrides have no business in
/// a BLE service. Resume is when a dropped `onBleState` push has to be pulled
/// back — the engine was suspended, so the push never arrived.
class _BeaconResumeObserver extends WidgetsBindingObserver {
  _BeaconResumeObserver(this.onResumed);

  final void Function() onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResumed();
  }
}
