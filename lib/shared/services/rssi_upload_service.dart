import 'package:flutter/foundation.dart';
import 'package:in_range/core/config/app_config.dart';
import 'package:in_range/core/network/supabase_client.dart';

/// Supabase adapter for [RssiUploader] — the only part of the upload path that
/// touches the network. Kept separate so the uploader's watermark logic stays
/// unit-testable without the platform stack.
class RssiUploadService {
  /// Why an upload cannot be attempted right now, or null when it can.
  ///
  /// Returns a REASON rather than a bool because every failure mode here is
  /// silent by nature: the app runs, the walk completes, and nothing is
  /// uploaded. This project has already lost a walk to exactly that shape of
  /// bug (INRANGE_CALIB_SCAN defaulting false), so the gate explains itself.
  static String? get blockedReason {
    // The consent boundary. rssi_samples is a raw co-location log; shipping it
    // for a user who did not opt into calibration is a different product.
    if (!AppConfig.calibScanMode) return 'INRANGE_CALIB_SCAN is false';
    if (!AppConfig.hasRealSupabase) return 'no real Supabase config';
    final client = InRangeSupabase.clientOrNull;
    if (client == null) return 'Supabase client unavailable';
    // Guest mode mints a local v4 UUID that is NOT an auth.users id. Uploading
    // under it fails the foreign key on every row, forever, silently — so the
    // auth session, not AppSession.userId, is what gates this.
    if (client.auth.currentUser?.id == null) return 'not signed in to Supabase';
    return null;
  }

  static bool get canUpload => blockedReason == null;

  static String get _platform =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  /// Uploads one batch of raw `rssi_log` rows. Returns the number of rows the
  /// server actually inserted — 0 means the whole batch was a replay, which is
  /// a normal outcome after a retry, not an error.
  ///
  /// Throws on any failure. The caller must NOT advance the watermark when this
  /// throws, or the rows are lost.
  static Future<int> send(
      String deviceId, List<Map<String, Object?>> samples) async {
    final client = InRangeSupabase.clientOrNull;
    if (client == null) {
      throw StateError('rssi upload attempted without a Supabase client');
    }
    final result = await client.rpc(
      'record_rssi_batch',
      params: {
        'p_device_id': deviceId,
        'p_platform': _platform,
        // device_seq IS the local rowid: it is what makes a replay idempotent
        // server-side and what lets the extractor spot a dropped row.
        'p_samples': [
          for (final r in samples)
            {
              'device_seq': r['id'],
              'at_ms': r['at_ms'],
              'correlation_id': r['correlation_id'],
              'rssi': r['rssi'],
              'power': r['power'],
            },
        ],
      },
    ).timeout(const Duration(seconds: 20));
    return (result as num?)?.toInt() ?? 0;
  }
}
