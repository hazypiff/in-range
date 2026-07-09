import 'package:flutter/foundation.dart';
import 'package:in_range/core/config/app_config.dart';
import 'package:in_range/shared/services/encounters_api.dart';

/// Hybrid encounters repository: server when live, empty list when offline
/// (local BLE store is merged by the feed/provider layer).
class EncountersRepository {
  EncountersRepository({EncountersApi? api}) : _api = api ?? EncountersApi();

  final EncountersApi _api;

  /// Active encounters for the current user (photo + neighborhood pre-match).
  Future<List<Map<String, dynamic>>> getMyEncounters() async {
    if (!AppConfig.hasRealSupabase || !AppConfig.preferServerFeeds) {
      return [];
    }
    try {
      final rows = await _api.getMyEncounters();
      return rows.map((r) {
        final m = Map<String, dynamic>.from(r);
        m['is_local'] = false;
        m['is_server'] = true;
        return m;
      }).toList();
    } catch (e) {
      debugPrint('getMyEncounters failed: $e');
      return [];
    }
  }

  /// Record a swipe; returns match payload when mutual.
  Future<Map<String, dynamic>?> recordAction({
    required int encounterId,
    required String action,
  }) async {
    if (!AppConfig.hasRealSupabase) return null;
    try {
      return await _api.swipe(encounterId: encounterId, action: action);
    } catch (e) {
      debugPrint('recordAction failed: $e');
      rethrow;
    }
  }
}
