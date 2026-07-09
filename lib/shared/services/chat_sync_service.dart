import 'package:flutter/foundation.dart';
import 'package:in_range/core/config/app_config.dart';
import 'package:in_range/core/network/supabase_client.dart';
import 'package:in_range/shared/services/encounters_api.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Cloud chat: list matches, send/read messages, realtime subscribe.
class ChatSyncService {
  final _api = EncountersApi();

  bool get cloudReady =>
      AppConfig.hasRealSupabase &&
      InRangeSupabase.clientOrNull?.auth.currentUser != null;

  Future<List<Map<String, dynamic>>> fetchMatches() => _api.getMyMatches();

  Future<List<Map<String, dynamic>>> fetchMessages(int matchId) async {
    if (!cloudReady) return [];
    try {
      final rows = await InRangeSupabase.client
          .from('messages')
          .select()
          .eq('match_id', matchId)
          .order('created_at', ascending: true);
      return List<Map<String, dynamic>>.from(rows as List);
    } catch (e) {
      debugPrint('fetchMessages: $e');
      return [];
    }
  }

  Future<int?> sendText({
    required int matchId,
    required String content,
  }) =>
      _api.sendMessage(matchId: matchId, content: content);

  Future<void> markRead(int matchId) async {
    if (!cloudReady) return;
    try {
      await InRangeSupabase.client.rpc(
        'mark_messages_read',
        params: {'p_match_id': matchId},
      );
    } catch (e) {
      debugPrint('mark_messages_read: $e');
    }
  }

  /// Realtime channel for a match's messages. Caller must unsubscribe.
  RealtimeChannel? subscribeMessages({
    required int matchId,
    required void Function(Map<String, dynamic> row) onInsert,
  }) {
    if (!cloudReady) return null;
    final client = InRangeSupabase.client;
    final channel = client.channel('match-$matchId');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'match_id',
            value: matchId,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            onInsert(Map<String, dynamic>.from(row));
          },
        )
        .subscribe();
    return channel;
  }

  Future<void> uploadChatMediaAndSend({
    required int matchId,
    required String localPath,
    required String messageType, // photo | voice | video
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (!cloudReady) return;
    final uid = InRangeSupabase.client.auth.currentUser!.id;
    final path = '$matchId/$uid/$fileName';
    await InRangeSupabase.client.storage.from('chat_media').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    await _api.sendMessage(
      matchId: matchId,
      content: path,
      messageType: messageType,
      metadata: {'storage_path': path, 'bucket': 'chat_media'},
    );
  }
}
