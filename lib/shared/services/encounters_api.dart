import 'package:flutter/foundation.dart';
import 'package:in_range/core/config/app_config.dart';
import 'package:in_range/core/network/supabase_client.dart';

/// Server-side encounters / locals / swipe / match API.
/// All methods no-op or return empty when cloud is offline.
class EncountersApi {
  bool get cloudReady =>
      AppConfig.hasRealSupabase &&
      InRangeSupabase.clientOrNull?.auth.currentUser != null;

  Future<List<Map<String, dynamic>>> getMyEncounters() async {
    if (!cloudReady) return [];
    try {
      final response = await InRangeSupabase.client.rpc(
        'get_my_encounters',
        params: {
          'p_limit': 50,
          'p_offset': 0,
          'p_min_age_hours': AppConfig.encounterRevealDelayHours,
        },
      );
      return List<Map<String, dynamic>>.from(response as List? ?? []);
    } catch (e) {
      debugPrint('getMyEncounters: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getLocalsFeed({
    required double lat,
    required double lon,
    String range = 'miles_10',
  }) async {
    if (!cloudReady) return [];
    try {
      final response = await InRangeSupabase.client.rpc(
        'get_locals_feed',
        params: {
          'p_lat': lat,
          'p_lon': lon,
          'p_range': range,
          'p_limit': 50,
        },
      );
      return List<Map<String, dynamic>>.from(response as List? ?? []);
    } catch (e) {
      debugPrint('getLocalsFeed: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> swipe({
    required int encounterId,
    required String action,
  }) async {
    if (!cloudReady) return null;
    try {
      final response = await InRangeSupabase.client.rpc(
        'swipe_encounter',
        params: {
          'p_encounter_id': encounterId,
          'p_action': action,
        },
      );
      if (response is Map<String, dynamic>) return response;
      if (response is Map) return Map<String, dynamic>.from(response);
      return null;
    } catch (e) {
      debugPrint('swipe_encounter: $e');
      rethrow;
    }
  }

  Future<int?> recordLocationPing({
    required double lat,
    required double lon,
    String range = 'miles_10',
    String? neighborhood,
  }) async {
    if (!cloudReady) return null;
    try {
      final id = await InRangeSupabase.client.rpc(
        'record_location_ping',
        params: {
          'p_lat': lat,
          'p_lon': lon,
          'p_range': range,
          'p_neighborhood': neighborhood,
        },
      );
      return id is int ? id : int.tryParse('$id');
    } catch (e) {
      debugPrint('record_location_ping: $e');
      return null;
    }
  }

  Future<void> claimToken({
    required String token,
    required DateTime validUntil,
    double? lat,
    double? lon,
    String range = 'feet_10',
  }) async {
    if (!cloudReady) return;
    try {
      await InRangeSupabase.client.rpc('claim_token', params: {
        'p_token': token,
        'p_valid_until': validUntil.toUtc().toIso8601String(),
        'p_lat': lat,
        'p_lon': lon,
        'p_range': range,
      });
    } catch (e) {
      debugPrint('claim_token: $e');
    }
  }

  Future<void> recordSighting({
    required String observedToken,
    int? rssi,
    DateTime? observedAt,
    double? lat,
    double? lon,
    String? range,
  }) async {
    if (!cloudReady) return;
    try {
      await InRangeSupabase.client.rpc('record_sighting', params: {
        'p_observed_token': observedToken,
        'p_rssi': rssi,
        'p_observed_at':
            (observedAt ?? DateTime.now()).toUtc().toIso8601String(),
        'p_lat': lat,
        'p_lon': lon,
        'p_range': range,
      });
    } catch (e) {
      debugPrint('record_sighting: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getMyMatches() async {
    if (!cloudReady) return [];
    try {
      final response = await InRangeSupabase.client.rpc(
        'get_my_matches',
        params: {'p_limit': 50, 'p_offset': 0},
      );
      return List<Map<String, dynamic>>.from(response as List? ?? []);
    } catch (e) {
      debugPrint('get_my_matches: $e');
      return [];
    }
  }

  Future<int?> sendMessage({
    required int matchId,
    required String content,
    String messageType = 'text',
    Map<String, dynamic>? metadata,
  }) async {
    if (!cloudReady) return null;
    try {
      final id = await InRangeSupabase.client.rpc('send_message', params: {
        'p_match_id': matchId,
        'p_content': content,
        'p_message_type': messageType,
        'p_metadata': metadata,
      });
      return id is int ? id : int.tryParse('$id');
    } catch (e) {
      debugPrint('send_message: $e');
      return null;
    }
  }

  Future<void> blockUser(String userId) async {
    if (!cloudReady) return;
    await InRangeSupabase.client.rpc('block_user', params: {
      'p_blocked_id': userId,
    });
  }

  Future<void> reportUser({
    required String userId,
    required String reason,
    String? details,
    int? matchId,
  }) async {
    if (!cloudReady) return;
    await InRangeSupabase.client.rpc('report_user', params: {
      'p_reported_id': userId,
      'p_reason': reason,
      'p_details': details,
      'p_match_id': matchId,
    });
  }
}
