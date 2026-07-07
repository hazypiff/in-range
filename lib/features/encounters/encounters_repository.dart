import 'package:in_range/core/network/supabase_client.dart';

/// EncountersRepository
/// Talks to the server RPCs and tables created in 0001_init.sql
class EncountersRepository {
  final _client = InRangeSupabase.client;

  /// Returns active encounters for the current user (photo + neighborhood only pre-match)
  Future<List<Map<String, dynamic>>> getMyEncounters() async {
    final response = await _client.rpc('get_my_encounters', params: {
      'p_limit': 50,
      'p_offset': 0,
    });
    return List<Map<String, dynamic>>.from(response);
  }

  /// Record a swipe action (will be used to create matches when mutual)
  Future<void> recordAction({
    required int encounterId,
    required String action, // 'like' | 'pass'
  }) async {
    await _client.from('encounter_actions').insert({
      'encounter_id': encounterId,
      'action': action,
    });
  }

  // TODO: realtime subscription on encounters / matches
  // TODO: handle 24h expiry for feet-based encounters client-side + server
}
