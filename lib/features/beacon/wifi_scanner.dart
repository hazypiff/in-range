import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
      // Best-effort nudge; ignored when throttled — the cache is the source of truth.
      unawaited(_requestScan());
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
              ))
          .where((a) => a.bssid.isNotEmpty)
          .toList();

      final fp = Fingerprint(aps, takenAt: DateTime.now());
      _latest = fp;

      final usable = fp.usable(excludedBssids);
      // Calibration ground truth: one line per scan, mirroring the BLE
      // 'Advert' lines so a walk can be reconstructed from logcat alone.
      //
      // Log EVERY AP, not just the ones above the -70 dBm gate: that gate is a
      // starting guess from the literature, and we only get one walk. Logging
      // the full fingerprint lets the threshold be re-tested offline instead of
      // baking today's guess into the data forever.
      final all = (aps.toList()..sort((a, b) => b.rssi.compareTo(a.rssi)))
          .take(16)
          .map((a) =>
              '${a.bssid.substring(a.bssid.length - 5)}:${a.rssi}:${a.is5GHz ? 5 : 2}')
          .join(',');
      debugPrint(
          'WifiScan aps=${aps.length} usable=${usable.length} fp=[$all]');

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
