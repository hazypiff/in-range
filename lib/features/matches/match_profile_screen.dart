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
    final match = ref.watch(matchStoreProvider).firstWhere(
          (m) => m.correlationId == correlationId,
          orElse: () => MatchRecord(
            correlationId: correlationId,
            displayName: 'Match',
            matchedAt: DateTime.now(),
          ),
        );

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
                        child: Image.file(File(path), fit: BoxFit.cover),
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
