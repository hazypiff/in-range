import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_range/core/config/app_config.dart';
import 'package:in_range/features/beacon/venue_matcher.dart';

/// Reads the platform's cached WiFi scan results for venue co-location.
///
/// Cadence: Android throttles explicit scans to 4 per 2 minutes, and a venue
/// changes on the scale of minutes, not seconds — so we poll the system's
/// cached results every 60s and only *nudge* a fresh scan opportunistically.
/// WiFi and BLE share one 2.4GHz antenna on phone combo chips, so a chatty
/// WiFi cadence would steal airtime from the BLE scanner that matters more.
class WifiScanner {
  WifiScanner({this.scanInterval = const Duration(seconds: 60)});

  static const MethodChannel _channel = MethodChannel('io.inrange.app/wifi');

  final Duration scanInterval;
  Timer? _timer;
  int _seq = 0;

  Fingerprint? _latest;
  Fingerprint? get latest => _latest;

  /// Our own tethering hotspot travels WITH the phones — it would manufacture
  /// a perfect venue match anywhere on earth. Excluded from every comparison.
  final Set<String> excludedBssids = <String>{};

  /// Emitted on every successful scan (calibration + fusion consumers).
  void Function(Fingerprint)? onFingerprint;

  void start() {
    stop();
    unawaited(_scanOnce());
    _timer = Timer.periodic(scanInterval, (_) => unawaited(_scanOnce()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _scanOnce() async {
    try {
      // Nudge a fresh scan, then give the radio time to finish it before
      // reading. Reading immediately returns the PREVIOUS scan — measured at
      // ~27s stale, i.e. potentially the room you were standing in before.
      // (The nudge is throttled to 4/2min by Android and may be ignored; the
      // cache remains the source of truth either way.)
      final requested = await _requestScan();
      if (requested) {
        await Future<void>.delayed(const Duration(seconds: 5));
      }
      final raw = await _channel.invokeListMethod<Map<dynamic, dynamic>>(
        'scanResults',
      );
      if (raw == null || raw.isEmpty) {
        debugPrint('WiFi scan: no results (permission or WiFi off?)');
        return;
      }
      final aps = raw
          .map((m) => ApSighting(
                bssid: (m['bssid'] as String?) ?? '',
                rssi: (m['rssi'] as int?) ?? -127,
                freq: (m['freq'] as int?) ?? 0,
                ageMs: (m['ageMs'] as int?) ?? 0,
              ))
          .where((a) => a.bssid.isNotEmpty)
          .toList();

      final fp = Fingerprint(aps, takenAt: DateTime.now());
      _latest = fp;

      final usable = fp.usable(excludedBssids);
      final fresh = aps.where((a) => !a.isStale).length;

      // Calibration ground truth: one line per scan, mirroring the BLE
      // 'Advert' lines so a walk can be reconstructed from logcat alone.
      //
      // Three things this line must NOT do, each learned the hard way:
      //  - It logs EVERY AP, not just those above the -70 dBm gate: that gate
      //    is a starting guess from the literature and we only get one walk,
      //    so the data has to let us re-test it offline.
      //  - It logs no truncated BSSID. A short suffix COLLIDES (a multi-BSSID
      //    access point broadcasts several BSSIDs differing in the high octets),
      //    which would silently merge distinct APs and corrupt every similarity
      //    score computed from this log.
      //  - It logs each entry's cache AGE. Android serves cached scan results,
      //    so a fingerprint can contain minutes-old APs — i.e. the room you
      //    just left. Without the age we could not tell.
      //
      // One line PER AP rather than one packed line: debugPrint word-wraps long
      // messages, which would shred a 40-AP fingerprint across log lines and
      // break every parser downstream. A header line ties the group together.
      _seq++;
      debugPrint('WifiScan seq=$_seq aps=${aps.length} fresh=$fresh '
          'usable=${usable.length}');
      // Raw BSSIDs are a place fingerprint — log them only in calibration
      // mode, never to production/release logs or bug reports (reviewer #18).
      if (AppConfig.calibScanMode) {
        for (final a in aps..sort((x, y) => y.rssi.compareTo(x.rssi))) {
          debugPrint('WifiAp seq=$_seq bssid=${a.bssid} rssi=${a.rssi} '
              'band=${a.is5GHz ? 5 : 2} age=${(a.ageMs / 1000).round()}');
        }
      }

      onFingerprint?.call(fp);
    } catch (e) {
      debugPrint('WiFi scan failed: $e');
    }
  }

  Future<bool> _requestScan() async {
    try {
      return await _channel.invokeMethod<bool>('requestScan') ?? false;
    } catch (_) {
      return false;
    }
  }
}
