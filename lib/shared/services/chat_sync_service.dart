import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_range/core/network/supabase_client.dart';
import 'package:in_range/shared/services/media_hash_service.dart';
import 'package:in_range/features/matches/match_store.dart';
import 'package:in_range/shared/services/encounters_api.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class SentChatMedia {
  const SentChatMedia({required this.messageId, required this.storagePath});
  final int messageId;
  final String storagePath;
}

/// Cloud chat: hydrate matches, send/read messages, realtime subscribe.
class ChatSyncService {
  ChatSyncService({EncountersApi? api}) : _api = api ?? EncountersApi();

  final EncountersApi _api;

  bool get cloudReady => _api.cloudReady;

  /// Map get_my_matches rows → local MatchRecord list.
  Future<List<MatchRecord>> fetchMatches() async {
    if (!cloudReady) return [];
    final rows = await _api.getMyMatches();
    return rows.map((r) {
      final matchId = r['match_id']?.toString() ??
          r['id']?.toString() ??
          DateTime.now().microsecondsSinceEpoch.toString();
      final photos =
          (r['photo_urls'] as List?)?.map((e) => e.toString()).toList() ??
              const <String>[];
      final interests =
          (r['interests'] as List?)?.map((e) => e.toString()).toList() ??
              const <String>[];
      final last = r['last_message']?.toString();
      final lastAt = DateTime.tryParse(r['last_message_at']?.toString() ?? '');
      final msgs = <ChatMessage>[];
      if (last != null && last.isNotEmpty) {
        msgs.add(
          ChatMessage(
            id: 'preview-$matchId',
            fromMe: false,
            text: last,
            at: lastAt ?? DateTime.now(),
          ),
        );
      }
      return MatchRecord(
        correlationId: matchId,
        displayName: r['display_name']?.toString() ?? 'Match',
        matchedAt: DateTime.tryParse(r['matched_at']?.toString() ?? '') ??
            DateTime.now(),
        neighborhood: r['neighborhood']?.toString() ?? 'Nearby',
        bio: r['bio']?.toString(),
        age: r['age'] is int ? r['age'] as int : int.tryParse('${r['age']}'),
        gender: r['gender']?.toString(),
        interests: interests,
        photoPaths: photos,
        messages: msgs,
        otherUserId: r['other_user_id']?.toString(),
        isServerMatch: true,
      );
    }).toList();
  }

  Future<List<ChatMessage>> fetchMessages(int matchId) async {
    if (!cloudReady) return [];
    try {
      final me = InRangeSupabase.client.auth.currentUser?.id;
      final rows = await InRangeSupabase.client
          .from('messages')
          .select()
          .eq('match_id', matchId)
          .order('created_at', ascending: true);
      return (rows as List).map((raw) {
        final r = Map<String, dynamic>.from(raw as Map);
        final sender = r['sender_id']?.toString();
        final meta = r['metadata'];
        String? imagePath;
        if (meta is Map && meta['storage_path'] != null) {
          imagePath = meta['storage_path']?.toString();
        }
        return ChatMessage(
          id: r['id']?.toString() ??
              DateTime.now().microsecondsSinceEpoch.toString(),
          fromMe: sender != null && sender == me,
          text: r['content']?.toString() ?? '',
          at: DateTime.tryParse(r['created_at']?.toString() ?? '') ??
              DateTime.now(),
          imagePath: imagePath,
        );
      }).toList();
    } catch (e) {
      debugPrint('fetchMessages: $e');
      rethrow;
    }
  }

  Future<int?> sendText({
    required int matchId,
    required String content,
  }) =>
      _api.sendMessage(matchId: matchId, content: content);

  Future<SentChatMedia> sendPhoto({
    required int matchId,
    required String localPath,
    String caption = '',
  }) async {
    if (!cloudReady) throw StateError('Cloud chat is unavailable');
    final client = InRangeSupabase.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) throw StateError('Sign in before sending media');
    final storagePath = '$matchId/$uid/${const Uuid().v4()}.jpg';
    await client.storage.from('chat_media').upload(
          storagePath,
          File(localPath),
          fileOptions: const FileOptions(
            upsert: false,
            contentType: 'image/jpeg',
          ),
        );
    // TAKE IT DOWN: record the digest so a removal reaches identical copies.
    // Fire-and-forget: hashing must never sit on the message-send path.
    // record() already swallows its own errors; unawaited keeps a slow
    // hash-insert round-trip from delaying the send.
    unawaited(MediaHashService.record(
      bucketId: 'chat_media',
      objectName: storagePath,
      file: File(localPath),
    ));
    try {
      final id = await _api.sendMessage(
        matchId: matchId,
        content: caption,
        messageType: 'photo',
        metadata: {'storage_path': storagePath},
      );
      return SentChatMedia(messageId: id, storagePath: storagePath);
    } catch (_) {
      await client.storage.from('chat_media').remove([storagePath]);
      rethrow;
    }
  }

  Future<String?> resolveMedia(String storagePath) async {
    if (!cloudReady || storagePath.isEmpty) return null;
    try {
      return await InRangeSupabase.client.storage
          .from('chat_media')
          .createSignedUrl(storagePath, 900);
    } catch (e) {
      debugPrint('resolve chat media failed: $e');
      return null;
    }
  }

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

  /// Subscribe to new messages for a match. Caller must [unsubscribe].
  RealtimeChannel? subscribeMessages({
    required int matchId,
    required void Function(ChatMessage msg) onInsert,
  }) {
    if (!cloudReady) return null;
    final client = InRangeSupabase.client;
    final me = client.auth.currentUser?.id;
    final channel = client.channel('match-msgs-$matchId');
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
            final r = payload.newRecord;
            final sender = r['sender_id']?.toString();
            final metadata = r['metadata'];
            final imagePath =
                metadata is Map ? metadata['storage_path']?.toString() : null;
            onInsert(
              ChatMessage(
                id: r['id']?.toString() ??
                    DateTime.now().microsecondsSinceEpoch.toString(),
                fromMe: sender != null && sender == me,
                text: r['content']?.toString() ?? '',
                at: DateTime.tryParse(r['created_at']?.toString() ?? '') ??
                    DateTime.now(),
                imagePath: imagePath,
              ),
            );
          },
        )
        .subscribe();
    return channel;
  }

  Future<void> unsubscribe(RealtimeChannel? channel) async {
    if (channel == null) return;
    try {
      await InRangeSupabase.client.removeChannel(channel);
    } catch (e) {
      debugPrint('unsubscribe: $e');
    }
  }
}
