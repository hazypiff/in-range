import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:in_range/core/config/app_config.dart';
import 'package:in_range/core/privacy/safety_store.dart';
import 'package:in_range/features/matches/match_profile_screen.dart';
import 'package:in_range/features/matches/match_store.dart';
import 'package:in_range/features/widgets/ad_banner.dart';
import 'package:in_range/shared/services/chat_sync_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});

  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(matchStoreProvider.notifier).syncFromCloud();
    });
  }

  @override
  Widget build(BuildContext context) {
    final matches = ref.watch(matchStoreProvider);
    final blocked = ref.watch(safetyStoreProvider).blocked;
    final visible = matches
        .where((m) =>
            !blocked.contains(m.correlationId) &&
            !blocked.contains(m.otherUserId ?? '') &&
            !m.isExpiredNoMessage)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          if (AppConfig.hasRealSupabase)
            IconButton(
              tooltip: 'Refresh from cloud',
              icon: const Icon(Icons.cloud_sync_outlined),
              onPressed: () =>
                  ref.read(matchStoreProvider.notifier).syncFromCloud(),
            ),
        ],
      ),
      body: Column(
        children: [
          const FreeAdBanner(),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.chat_bubble_outline,
                              size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          const Text(
                            'No messages yet',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'When you both like an encounter, chat appears here. '
                            '${AppConfig.hasRealSupabase ? "Cloud chat syncs via Supabase." : "Local mode until cloud keys are set."} '
                            'Voice/video: storage ready; recording UI when platform keys are live.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final m = visible[i];
                      final last =
                          m.messages.isNotEmpty ? m.messages.last.text : '';
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            m.displayName.isNotEmpty
                                ? m.displayName[0].toUpperCase()
                                : '?',
                          ),
                        ),
                        title: Text(m.displayName),
                        subtitle: Text(
                          last.isEmpty ? 'Say hi 👋' : last,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ChatThreadScreen(
                                  correlationId: m.correlationId),
                            ),
                          );
                        },
                        onLongPress: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => MatchProfileScreen(
                                  correlationId: m.correlationId),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class ChatThreadScreen extends ConsumerStatefulWidget {
  const ChatThreadScreen({super.key, required this.correlationId});
  final String correlationId;

  @override
  ConsumerState<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends ConsumerState<ChatThreadScreen> {
  final _ctrl = TextEditingController();
  final _chat = ChatSyncService();
  RealtimeChannel? _channel;
  bool _missing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final store = ref.read(matchStoreProvider.notifier);
    final match = store.findMatch(widget.correlationId);
    if (match == null) {
      if (mounted) setState(() => _missing = true);
      return;
    }
    await store.hydrateThread(widget.correlationId);
    final matchId = int.tryParse(widget.correlationId);
    if (matchId != null && AppConfig.hasRealSupabase) {
      _channel = _chat.subscribeMessages(
        matchId: matchId,
        onInsert: (msg) {
          if (msg.fromMe) return; // already optimistic
          ref.read(matchStoreProvider.notifier).appendRemoteMessage(
                widget.correlationId,
                msg,
              );
        },
      );
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    unawaited(_chat.unsubscribe(_channel));
    super.dispose();
  }

  Future<void> _send({String? imagePath}) async {
    final t = _ctrl.text;
    _ctrl.clear();
    try {
      await ref.read(matchStoreProvider.notifier).sendMessage(
            correlationId: widget.correlationId,
            text: t,
            imagePath: imagePath,
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Message not sent: $e',
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
      // Restore draft so user can retry
      if (t.isNotEmpty) _ctrl.text = t;
    }
  }

  Future<void> _pickPhoto() async {
    final x = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 80,
    );
    if (x == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final dest = p.join(
      dir.path,
      'chat_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await File(x.path).copy(dest);
    await _send(imagePath: dest);
  }

  @override
  Widget build(BuildContext context) {
    if (_missing) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chat')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.chat_bubble_outline, size: 56),
                const SizedBox(height: 12),
                const Text(
                  'This conversation is no longer available',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  'It may have expired (24h with no messages) or been removed.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final matches = ref.watch(matchStoreProvider);
    MatchRecord? found;
    for (final m in matches) {
      if (m.correlationId == widget.correlationId) {
        found = m;
        break;
      }
    }
    // If pruned while open (expiry timer), show empty state.
    if (found == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _missing = true);
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final match = found;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(match.displayName),
            Text(
              match.neighborhood,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Full profile',
            icon: const Icon(Icons.person_outline),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => MatchProfileScreen(
                      correlationId: widget.correlationId),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (AppConfig.hasRealSupabase && match.isServerMatch)
            Material(
              color: Colors.green.shade50,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.cloud_done, size: 16, color: Colors.green),
                    SizedBox(width: 8),
                    Text(
                      'Cloud chat · realtime when connected',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: match.messages.length,
              itemBuilder: (context, i) {
                final msg = match.messages[i];
                final align =
                    msg.fromMe ? Alignment.centerRight : Alignment.centerLeft;
                final bg = msg.fromMe
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Colors.grey.shade200;
                return Align(
                  alignment: align,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(10),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (msg.imagePath != null &&
                            !msg.imagePath!.startsWith('http') &&
                            File(msg.imagePath!).existsSync())
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(msg.imagePath!),
                              height: 160,
                              fit: BoxFit.cover,
                            ),
                          ),
                        if (msg.text.isNotEmpty) Text(msg.text),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _pickPhoto,
                    icon: const Icon(Icons.image_outlined),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      decoration: const InputDecoration(
                        hintText: 'Message…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filled(
                    onPressed: () => _send(),
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
