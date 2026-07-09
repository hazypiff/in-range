import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_range/core/privacy/safety_store.dart';
import 'package:in_range/features/chat/messages_screen.dart';
import 'package:in_range/features/matches/match_store.dart';

/// Full profile unlock after mutual match.
class MatchProfileScreen extends ConsumerWidget {
  const MatchProfileScreen({super.key, required this.correlationId});
  final String correlationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = ref.watch(matchStoreProvider);
    MatchRecord? match;
    for (final m in matches) {
      if (m.correlationId == correlationId) {
        match = m;
        break;
      }
    }
    if (match == null || match.isExpiredNoMessage) {
      return Scaffold(
        appBar: AppBar(title: const Text('Match')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.person_off_outlined, size: 56),
                const SizedBox(height: 12),
                const Text(
                  'This match is no longer available',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  'It may have expired after 24 hours with no messages.',
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

    return Scaffold(
      appBar: AppBar(
        title: Text(match.displayName),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'block') {
                await ref
                    .read(safetyStoreProvider.notifier)
                    .block(correlationId);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Blocked')),
                  );
                  Navigator.pop(context);
                }
              } else if (v == 'report') {
                await ref.read(safetyStoreProvider.notifier).report(
                      targetId: correlationId,
                      reason: 'User reported from profile',
                    );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Reported & blocked')),
                  );
                  Navigator.pop(context);
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'report', child: Text('Report')),
              PopupMenuItem(value: 'block', child: Text('Block')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (match.photoPaths.isNotEmpty)
            SizedBox(
              height: 220,
              child: PageView(
                children: [
                  for (final path in match.photoPaths)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: path.startsWith('http')
                            ? Image.network(path, fit: BoxFit.cover)
                            : (File(path).existsSync()
                                ? Image.file(File(path), fit: BoxFit.cover)
                                : const ColoredBox(
                                    color: Colors.black12,
                                    child: Center(
                                        child: Icon(Icons.broken_image)),
                                  )),
                      ),
                    ),
                ],
              ),
            )
          else
            CircleAvatar(
              radius: 48,
              child: Text(
                match.displayName.isNotEmpty
                    ? match.displayName[0].toUpperCase()
                    : '?',
                style: const TextStyle(fontSize: 36),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            match.displayName,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          if (match.age != null)
            Text('${match.age} · ${match.gender ?? ""}',
                style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.place_outlined, size: 18),
              const SizedBox(width: 4),
              Expanded(child: Text(match.neighborhood)),
            ],
          ),
          const SizedBox(height: 16),
          Text(match.bio ?? '', style: const TextStyle(height: 1.4)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: match.interests
                .map((i) => Chip(label: Text(i)))
                .toList(),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      ChatThreadScreen(correlationId: correlationId),
                ),
              );
            },
            icon: const Icon(Icons.chat_bubble),
            label: const Text('Open chat'),
          ),
        ],
      ),
    );
  }
}
