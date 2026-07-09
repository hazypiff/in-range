import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:in_range/core/privacy/safety_store.dart';
import 'package:in_range/features/matches/match_profile_screen.dart';
import 'package:in_range/features/matches/match_store.dart';
import 'package:in_range/features/widgets/ad_banner.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class MessagesScreen extends ConsumerWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = ref.watch(matchStoreProvider);
    final blocked = ref.watch(safetyStoreProvider).blocked;
    final visible =
        matches.where((m) => !blocked.contains(m.correlationId)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
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
                            'Text + photos work now (local always; cloud when connected). '
                            'Voice notes & video calls: storage + send_message ready; '
                            'recording/WebRTC UI wires when platform keys are live.',
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
                          last,
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

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send({String? imagePath}) async {
    final t = _ctrl.text;
    _ctrl.clear();
    await ref.read(matchStoreProvider.notifier).sendMessage(
          correlationId: widget.correlationId,
          text: t,
          imagePath: imagePath,
        );
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
    final match = ref.watch(matchStoreProvider).firstWhere(
          (m) => m.correlationId == widget.correlationId,
          orElse: () => MatchRecord(
            correlationId: widget.correlationId,
            displayName: 'Chat',
            matchedAt: DateTime.now(),
          ),
        );

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
