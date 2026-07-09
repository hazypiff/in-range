import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:in_range/core/config/app_config.dart';
import 'package:in_range/core/notifications/local_notify.dart';
import 'package:in_range/core/session/app_session.dart';
import 'package:in_range/shared/services/chat_sync_service.dart';
import 'package:in_range/shared/services/encounters_api.dart';

class MatchRecord {
  MatchRecord({
    required this.correlationId,
    required this.displayName,
    required this.matchedAt,
    this.neighborhood = 'Nearby',
    this.bio,
    this.age,
    this.gender,
    this.interests = const [],
    this.photoPaths = const [],
    List<ChatMessage>? messages,
    this.otherUserId,
    this.isServerMatch = false,
  }) : messages = messages ?? [];

  /// Local BLE corr-id or server match id (numeric string when cloud).
  final String correlationId;
  final String displayName;
  final DateTime matchedAt;
  final String neighborhood;
  final String? bio;
  final int? age;
  final String? gender;
  final List<String> interests;
  final List<String> photoPaths;
  final List<ChatMessage> messages;
  final String? otherUserId;
  final bool isServerMatch;

  /// Parsed server match id when [correlationId] is numeric.
  int? get serverMatchId => int.tryParse(correlationId);

  static const noMessageExpiry = Duration(hours: 24);

  bool get hasUserMessage => messages.any((m) => m.fromMe);

  bool get isExpiredNoMessage {
    if (hasUserMessage) return false;
    // Normalize both sides to UTC so timezone offset doesn't bias the
    // comparison (matchedAt is parsed from ISO and may be stored as UTC).
    return DateTime.now().toUtc().isAfter(matchedAt.toUtc().add(noMessageExpiry));
  }

  MatchRecord copyWith({
    String? displayName,
    String? neighborhood,
    String? bio,
    int? age,
    String? gender,
    List<String>? interests,
    List<String>? photoPaths,
    List<ChatMessage>? messages,
    String? otherUserId,
    bool? isServerMatch,
  }) {
    return MatchRecord(
      correlationId: correlationId,
      displayName: displayName ?? this.displayName,
      matchedAt: matchedAt,
      neighborhood: neighborhood ?? this.neighborhood,
      bio: bio ?? this.bio,
      age: age ?? this.age,
      gender: gender ?? this.gender,
      interests: interests ?? this.interests,
      photoPaths: photoPaths ?? this.photoPaths,
      messages: messages ?? this.messages,
      otherUserId: otherUserId ?? this.otherUserId,
      isServerMatch: isServerMatch ?? this.isServerMatch,
    );
  }

  Map<String, dynamic> toJson() => {
        'correlationId': correlationId,
        'displayName': displayName,
        'matchedAt': matchedAt.toIso8601String(),
        'neighborhood': neighborhood,
        'bio': bio,
        'age': age,
        'gender': gender,
        'interests': interests,
        'photoPaths': photoPaths,
        'messages': messages.map((m) => m.toJson()).toList(),
        'otherUserId': otherUserId,
        'isServerMatch': isServerMatch,
      };

  factory MatchRecord.fromJson(Map<String, dynamic> j) => MatchRecord(
        correlationId: j['correlationId'] as String,
        displayName: j['displayName'] as String? ?? 'Someone',
        matchedAt: DateTime.tryParse(j['matchedAt'] as String? ?? '') ??
            DateTime.now(),
        neighborhood: j['neighborhood'] as String? ?? 'Nearby',
        bio: j['bio'] as String?,
        age: j['age'] as int?,
        gender: j['gender'] as String?,
        interests: (j['interests'] as List?)?.cast<String>() ?? const [],
        photoPaths: (j['photoPaths'] as List?)?.cast<String>() ?? const [],
        messages: (j['messages'] as List? ?? [])
            .map((e) =>
                ChatMessage.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        otherUserId: j['otherUserId'] as String?,
        isServerMatch: j['isServerMatch'] as bool? ?? false,
      );
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.fromMe,
    required this.text,
    required this.at,
    this.imagePath,
  });

  final String id;
  final bool fromMe;
  final String text;
  final DateTime at;
  final String? imagePath;

  Map<String, dynamic> toJson() => {
        'id': id,
        'fromMe': fromMe,
        'text': text,
        'at': at.toIso8601String(),
        'imagePath': imagePath,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String,
        fromMe: j['fromMe'] as bool? ?? false,
        text: j['text'] as String? ?? '',
        at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
        imagePath: j['imagePath'] as String?,
      );
}

class UndoAction {
  UndoAction({
    required this.kind,
    required this.correlationId,
    required this.displayName,
    required this.neighborhood,
    required this.at,
    this.createdMatch = false,
  });

  final String kind;
  final String correlationId;
  final String displayName;
  final String neighborhood;
  final DateTime at;
  final bool createdMatch;

  static const window = Duration(seconds: 5);
  bool get isValid => DateTime.now().difference(at) <= window;
}

class HistoryEntry {
  HistoryEntry({
    required this.correlationId,
    required this.action,
    required this.at,
    required this.displayName,
    this.neighborhood,
  });
  final String correlationId;
  final String action; // like | pass
  final DateTime at;
  final String displayName;
  final String? neighborhood;

  Map<String, dynamic> toJson() => {
        'correlationId': correlationId,
        'action': action,
        'at': at.toIso8601String(),
        'displayName': displayName,
        'neighborhood': neighborhood,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        correlationId: j['correlationId'] as String,
        action: j['action'] as String,
        at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
        displayName: j['displayName'] as String? ?? 'Someone',
        neighborhood: j['neighborhood'] as String?,
      );
}

class MatchStore extends StateNotifier<List<MatchRecord>> {
  MatchStore(this._prefs) : super(const []) {
    _load();
  }

  final SharedPreferences _prefs;
  // Demo/offline convenience: immediately create a local match on like. Must
  // stay OFF when real Supabase is configured — a real match requires a mutual
  // server swipe (handled above via EncountersApi.swipe → res['matched']).
  static bool get autoMatchOnLike => !AppConfig.hasRealSupabase;

  UndoAction? lastUndo;
  List<HistoryEntry> history = [];
  /// Local "liked you" sim: when we match, they "liked" us.
  Set<String> likedYou = {};

  Set<String> get likes => (_prefs.getStringList('liked_corrs') ?? []).toSet();
  Set<String> get passes =>
      (_prefs.getStringList('passed_corrs') ?? []).toSet();

  void _load() {
    try {
      final raw = _prefs.getString('matches_json');
      if (raw != null && raw.isNotEmpty) {
        state = (jsonDecode(raw) as List)
            .map((e) =>
                MatchRecord.fromJson(Map<String, dynamic>.from(e as Map)))
            .where((m) => !m.isExpiredNoMessage)
            .toList();
      }
      final h = _prefs.getString('history_json');
      if (h != null && h.isNotEmpty) {
        history = (jsonDecode(h) as List)
            .map((e) =>
                HistoryEntry.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
      likedYou = (_prefs.getStringList('liked_you') ?? []).toSet();
    } catch (e) {
      debugPrint('Match load failed: $e');
    }
  }

  Future<void> _persist() async {
    await _prefs.setString(
      'matches_json',
      jsonEncode(state.map((m) => m.toJson()).toList()),
    );
    await _prefs.setString(
      'history_json',
      jsonEncode(history.map((h) => h.toJson()).toList()),
    );
    await _prefs.setStringList('liked_you', likedYou.toList());
  }

  Future<void> pruneExpired() async {
    final before = state.length;
    state = state.where((m) => !m.isExpiredNoMessage).toList();
    if (state.length != before) await _persist();
  }

  Future<void> like({
    required String correlationId,
    required String displayName,
    String neighborhood = 'Nearby',
    String? bio,
    int? age,
    String? gender,
    List<String>? interests,
    List<String>? photoPaths,
  }) async {
    // Server swipe when correlationId is a numeric encounter id
    if (AppConfig.hasRealSupabase) {
      final encId = int.tryParse(correlationId);
      if (encId != null) {
        try {
          final res = await EncountersApi().swipe(
            encounterId: encId,
            action: 'like',
          );
          if (res != null && res['matched'] == true) {
            final matchId = res['match_id']?.toString() ?? correlationId;
            await _upsertMatch(
              correlationId: matchId,
              displayName: displayName,
              neighborhood: neighborhood,
              bio: bio,
              age: age,
              gender: gender,
              interests: interests ?? const [],
              photoPaths: photoPaths ?? const [],
              otherUserId: res['other_user_id']?.toString(),
              isServerMatch: true,
            );
            await LocalNotify.instance.notifyMatch(displayName);
            await _persistHistoryLike(correlationId, displayName, neighborhood);
            return;
          }
          // Liked but not mutual yet — still record local history
          await _persistHistoryLike(correlationId, displayName, neighborhood);
          final likedOnly = likes..add(correlationId);
          await _prefs.setStringList('liked_corrs', likedOnly.toList());
          return;
        } catch (e) {
          debugPrint('Server like failed, local fallback: $e');
        }
      }
    }

    final alreadyMatch =
        state.any((m) => m.correlationId == correlationId);
    final liked = likes..add(correlationId);
    await _prefs.setStringList('liked_corrs', liked.toList());
    final p = passes..remove(correlationId);
    await _prefs.setStringList('passed_corrs', p.toList());

    history = [
      HistoryEntry(
        correlationId: correlationId,
        action: 'like',
        at: DateTime.now(),
        displayName: displayName,
        neighborhood: neighborhood,
      ),
      ...history,
    ].take(200).toList();

    var created = false;
    if (autoMatchOnLike && !alreadyMatch) {
      likedYou = {...likedYou, correlationId};
      await _upsertMatch(
        correlationId: correlationId,
        displayName: displayName,
        neighborhood: neighborhood,
        bio: bio,
        age: age,
        gender: gender,
        interests: interests ?? const [],
        photoPaths: photoPaths ?? const [],
      );
      created = true;
      await LocalNotify.instance.notifyMatch(displayName);
    }

    lastUndo = UndoAction(
      kind: 'like',
      correlationId: correlationId,
      displayName: displayName,
      neighborhood: neighborhood,
      at: DateTime.now(),
      createdMatch: created,
    );
    await _persist();
    state = [...state];
  }

  Future<void> _persistHistoryLike(
    String correlationId,
    String displayName,
    String neighborhood,
  ) async {
    history = [
      HistoryEntry(
        correlationId: correlationId,
        action: 'like',
        at: DateTime.now(),
        displayName: displayName,
        neighborhood: neighborhood,
      ),
      ...history,
    ].take(200).toList();
    await _persist();
  }

  Future<void> pass(
    String correlationId, {
    String displayName = 'Someone',
    String neighborhood = 'Nearby',
  }) async {
    if (AppConfig.hasRealSupabase) {
      final encId = int.tryParse(correlationId);
      if (encId != null) {
        try {
          await EncountersApi().swipe(encounterId: encId, action: 'pass');
        } catch (e) {
          debugPrint('Server pass failed, local fallback: $e');
        }
      }
    }
    final p = passes..add(correlationId);
    await _prefs.setStringList('passed_corrs', p.toList());
    history = [
      HistoryEntry(
        correlationId: correlationId,
        action: 'pass',
        at: DateTime.now(),
        displayName: displayName,
        neighborhood: neighborhood,
      ),
      ...history,
    ].take(200).toList();
    lastUndo = UndoAction(
      kind: 'pass',
      correlationId: correlationId,
      displayName: displayName,
      neighborhood: neighborhood,
      at: DateTime.now(),
    );
    await _persist();
    state = [...state];
  }

  Future<bool> undoLast() async {
    final u = lastUndo;
    if (u == null || !u.isValid) return false;
    if (u.kind == 'like') {
      final liked = likes..remove(u.correlationId);
      await _prefs.setStringList('liked_corrs', liked.toList());
      if (u.createdMatch) {
        state =
            state.where((m) => m.correlationId != u.correlationId).toList();
        likedYou = {...likedYou}..remove(u.correlationId);
      }
    } else {
      final p = passes..remove(u.correlationId);
      await _prefs.setStringList('passed_corrs', p.toList());
    }
    lastUndo = null;
    await _persist();
    state = [...state];
    return true;
  }

  Future<void> _upsertMatch({
    required String correlationId,
    required String displayName,
    required String neighborhood,
    String? bio,
    int? age,
    String? gender,
    List<String> interests = const [],
    List<String> photoPaths = const [],
    String? otherUserId,
    bool isServerMatch = false,
  }) async {
    if (state.any((m) => m.correlationId == correlationId)) return;
    final m = MatchRecord(
      correlationId: correlationId,
      displayName: displayName,
      matchedAt: DateTime.now(),
      neighborhood: neighborhood,
      bio: bio ?? 'I love coffee shops and spontaneous walks.',
      age: age ?? 28,
      gender: gender ?? 'prefer-not-to-say',
      interests: interests.isEmpty ? const ['Music', 'Travel'] : interests,
      photoPaths: photoPaths,
      // No canned opener — a real match starts with zero messages until a
      // user sends one.
      messages: const [],
      otherUserId: otherUserId,
      isServerMatch: isServerMatch || int.tryParse(correlationId) != null,
    );
    state = [m, ...state];
    await _persist();
  }

  /// Pull server matches (get_my_matches) and merge into local state.
  Future<void> syncFromCloud() async {
    if (!AppConfig.hasRealSupabase) return;
    try {
      final remote = await ChatSyncService().fetchMatches();
      if (remote.isEmpty) return;
      final byId = {for (final m in state) m.correlationId: m};
      for (final r in remote) {
        final existing = byId[r.correlationId];
        if (existing == null) {
          byId[r.correlationId] = r;
        } else {
          // Keep richer local message history if longer; else take remote meta.
          byId[r.correlationId] = existing.copyWith(
            displayName: r.displayName,
            neighborhood: r.neighborhood,
            bio: r.bio ?? existing.bio,
            age: r.age ?? existing.age,
            gender: r.gender ?? existing.gender,
            interests: r.interests.isNotEmpty ? r.interests : existing.interests,
            photoPaths:
                r.photoPaths.isNotEmpty ? r.photoPaths : existing.photoPaths,
            otherUserId: r.otherUserId ?? existing.otherUserId,
            isServerMatch: true,
            messages: existing.messages.length >= r.messages.length
                ? existing.messages
                : r.messages,
          );
        }
      }
      state = byId.values.toList()
        ..sort((a, b) => b.matchedAt.compareTo(a.matchedAt));
      await _persist();
    } catch (e) {
      debugPrint('syncFromCloud matches failed: $e');
    }
  }

  /// Load full message history for a server match id.
  Future<void> hydrateThread(String correlationId) async {
    final matchId = int.tryParse(correlationId);
    if (matchId == null || !AppConfig.hasRealSupabase) return;
    try {
      final msgs = await ChatSyncService().fetchMessages(matchId);
      if (msgs.isEmpty) return;
      state = [
        for (final m in state)
          if (m.correlationId == correlationId)
            m.copyWith(messages: msgs, isServerMatch: true)
          else
            m,
      ];
      await _persist();
      await ChatSyncService().markRead(matchId);
    } catch (e) {
      debugPrint('hydrateThread failed: $e');
    }
  }

  /// Append an incoming realtime message (dedupe by id).
  Future<void> appendRemoteMessage(
    String correlationId,
    ChatMessage msg,
  ) async {
    state = [
      for (final m in state)
        if (m.correlationId == correlationId)
          m.copyWith(
            messages: m.messages.any((x) => x.id == msg.id)
                ? m.messages
                : [...m.messages, msg],
          )
        else
          m,
    ];
    await _persist();
  }

  Future<void> sendMessage({
    required String correlationId,
    required String text,
    String? imagePath,
  }) async {
    final t = text.trim();
    if (t.isEmpty && imagePath == null) return;

    final localId = DateTime.now().microsecondsSinceEpoch.toString();
    final localMsg = ChatMessage(
      id: localId,
      fromMe: true,
      text: t.isEmpty ? '📷 Photo' : t,
      at: DateTime.now(),
      imagePath: imagePath,
    );

    // Optimistic local append
    state = [
      for (final m in state)
        if (m.correlationId == correlationId)
          m.copyWith(messages: [...m.messages, localMsg])
        else
          m,
    ];
    await _persist();

    // Cloud path: server match ids are numeric
    final matchId = int.tryParse(correlationId);
    if (AppConfig.hasRealSupabase && matchId != null && t.isNotEmpty) {
      try {
        final serverId = await EncountersApi().sendMessage(
          matchId: matchId,
          content: t,
        );
        if (serverId != null) {
          // Replace optimistic id with server id when possible
          state = [
            for (final m in state)
              if (m.correlationId == correlationId)
                m.copyWith(
                  messages: [
                    for (final msg in m.messages)
                      if (msg.id == localId)
                        ChatMessage(
                          id: '$serverId',
                          fromMe: true,
                          text: msg.text,
                          at: msg.at,
                          imagePath: msg.imagePath,
                        )
                      else
                        msg,
                  ],
                  isServerMatch: true,
                )
              else
                m,
          ];
          await _persist();
        }
      } catch (e) {
        debugPrint('send_message RPC failed (local kept): $e');
      }
    }
  }

  /// Safe lookup — null when match was pruned (expired / deleted).
  MatchRecord? findMatch(String correlationId) {
    for (final m in state) {
      if (m.correlationId == correlationId) return m;
    }
    return null;
  }

  bool isDismissed(String correlationId) =>
      likes.contains(correlationId) || passes.contains(correlationId);

  Future<void> clearAll() async {
    await _prefs.remove('liked_corrs');
    await _prefs.remove('passed_corrs');
    await _prefs.remove('matches_json');
    await _prefs.remove('history_json');
    await _prefs.remove('liked_you');
    lastUndo = null;
    history = [];
    likedYou = {};
    state = const [];
  }
}

final matchStoreProvider =
    StateNotifierProvider<MatchStore, List<MatchRecord>>((ref) {
  return MatchStore(ref.watch(sharedPreferencesProvider));
});
