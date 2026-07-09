import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_range/features/matches/match_store.dart';

/// Extended encounter history (likes/passes) + "liked you" list.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(matchStoreProvider.notifier);
    // rebuild when matches change
    ref.watch(matchStoreProvider);
    final history = store.history;
    final likedYou = store.likedYou.toList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('History'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Your actions'),
              Tab(text: 'Liked you'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            history.isEmpty
                ? const Center(child: Text('No swipe history yet'))
                : ListView.separated(
                    itemCount: history.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final h = history[i];
                      return ListTile(
                        leading: Icon(
                          h.action == 'like'
                              ? Icons.favorite
                              : Icons.close,
                          color: h.action == 'like'
                              ? Colors.pink
                              : Colors.grey,
                        ),
                        title: Text(h.displayName),
                        subtitle: Text(
                          '${h.action} · ${h.neighborhood ?? ""} · '
                          '${h.at.toLocal().toString().substring(0, 16)}',
                        ),
                      );
                    },
                  ),
            likedYou.isEmpty
                ? const Center(
                    child: Text(
                      'No likes yet.\n(Local sim: appears when you match.)',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    itemCount: likedYou.length,
                    itemBuilder: (context, i) {
                      final id = likedYou[i];
                      final matches = ref
                          .read(matchStoreProvider)
                          .where((m) => m.correlationId == id);
                      final match = matches.isEmpty ? null : matches.first;
                      return ListTile(
                        leading: const Icon(Icons.favorite, color: Colors.pink),
                        title: Text(match?.displayName ?? 'Someone'),
                        subtitle: Text(
                          match?.neighborhood ??
                              (id.length >= 8 ? id.substring(0, 8) : id),
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}
