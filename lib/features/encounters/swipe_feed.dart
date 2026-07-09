import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_range/core/config/app_config.dart';
import 'package:in_range/core/notifications/local_notify.dart';
import 'package:in_range/core/prefs/app_prefs.dart';
import 'package:in_range/core/privacy/safety_store.dart';
import 'package:in_range/core/session/app_session.dart';
import 'package:in_range/features/encounters/local_encounter_store.dart';
import 'package:in_range/features/matches/match_store.dart';
import 'package:in_range/features/widgets/ad_banner.dart';

class SwipeFeed extends ConsumerStatefulWidget {
  const SwipeFeed({super.key});

  @override
  ConsumerState<SwipeFeed> createState() => _SwipeFeedState();
}

class _SwipeFeedState extends ConsumerState<SwipeFeed> {
  Timer? _tick;
  final _notifiedExpiring = <String>{};
  int _prevNew = 0;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      ref.read(matchStoreProvider.notifier).pruneExpired();
      _checkExpiring();
    });
  }

  void _checkExpiring() {
    final store = ref.read(localEncounterStoreProvider.notifier);
    for (final e in store.visible) {
      if (e.expiresAt == null) continue;
      if (e.timeRemaining.inHours < 2 &&
          e.timeRemaining.inMinutes > 0 &&
          !_notifiedExpiring.contains(e.correlationId)) {
        _notifiedExpiring.add(e.correlationId);
        LocalNotify.instance.notifyExpiringSoon(e.displayName);
      }
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  Future<void> _showUndo() async {
    final store = ref.read(matchStoreProvider.notifier);
    final u = store.lastUndo;
    if (u == null || !u.isValid || !mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: UndoAction.window,
        content: Text(u.kind == 'like' ? 'Liked — undo?' : 'Passed — undo?'),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () => store.undoLast(),
        ),
      ),
    );
  }

  Future<void> _doPass(LocalEncounter e) async {
    await ref.read(matchStoreProvider.notifier).pass(
          e.correlationId,
          displayName: e.displayName,
          neighborhood: e.neighborhoodLabel,
        );
    await _showUndo();
  }

  Future<void> _doLike(LocalEncounter e) async {
    final me = ref.read(sessionControllerProvider);
    await ref.read(matchStoreProvider.notifier).like(
          correlationId: e.correlationId,
          displayName: e.displayName,
          neighborhood: e.neighborhoodLabel,
          // Local unlock profile uses placeholder peer data.
          bio: 'We crossed paths near ${e.neighborhoodLabel}.',
          age: 27,
          gender: 'prefer-not-to-say',
          interests: const ['Coffee', 'Music'],
          photoPaths: me.photoPaths,
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('It\'s a match 🔥'),
          duration: Duration(seconds: 1),
        ),
      );
      await _showUndo();
    }
  }

  Future<void> _aliasDialog(String corr, String current) async {
    final ctrl = TextEditingController(
      text: current.startsWith('Nearby ') ? '' : current,
    );
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Device alias'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'e.g. Desk S9'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (name != null) {
      await ref
          .read(localEncounterStoreProvider.notifier)
          .setAlias(corr, name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final band = ref.watch(swipeBandFilterProvider);
    final pending = ref.watch(pendingRevealCountProvider);
    final matchStore = ref.watch(matchStoreProvider.notifier);
    final store = ref.watch(localEncounterStoreProvider.notifier);
    final safety = ref.watch(safetyStoreProvider);
    final newCount = ref.watch(newEncounterCountProvider);

    if (newCount > _prevNew) {
      LocalNotify.instance.notifyNewEncounter('new');
    }
    _prevNew = newCount;

    final cards = store.visible.where((e) {
      if (matchStore.isDismissed(e.correlationId)) return false;
      if (safety.blocked.contains(e.correlationId)) return false;
      if (!e.matchesBandFilter(band)) return false;
      return true;
    }).toList();

    return Column(
      children: [
        const FreeAdBanner(),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              for (final e in const [
                ('any', 'Any'),
                ('feet_10', '10 ft'),
                ('feet_20', '20 ft'),
                ('feet_30', '30 ft'),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilterChip(
                    label: Text(e.$2),
                    selected: band == e.$1,
                    onSelected: (_) =>
                        ref.read(swipeBandFilterProvider.notifier).set(e.$1),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text('${cards.length} to review',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
              const Spacer(),
              if (pending > 0)
                Text('$pending waiting reveal',
                    style:
                        TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            ],
          ),
        ),
        Expanded(
          child: cards.isEmpty
              ? _Empty(
                  pending: pending,
                  delayHours: AppConfig.encounterRevealDelayHours,
                  band: band,
                )
              : Dismissible(
                  key: ValueKey(cards.first.correlationId),
                  background: Container(
                    color: Colors.red.shade100,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: 32),
                    child: const Icon(Icons.close, size: 40),
                  ),
                  secondaryBackground: Container(
                    color: Colors.pink.shade100,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 32),
                    child: const Icon(Icons.favorite, size: 40),
                  ),
                  confirmDismiss: (dir) async {
                    final e = cards.first;
                    if (dir == DismissDirection.startToEnd) {
                      await _doPass(e);
                    } else {
                      await _doLike(e);
                    }
                    return true;
                  },
                  child: _buildCard(cards.first),
                ),
        ),
        if (cards.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _RoundAction(
                  color: Colors.grey.shade200,
                  icon: Icons.close,
                  iconColor: Colors.grey.shade800,
                  onTap: () => _doPass(cards.first),
                ),
                _RoundAction(
                  color: Colors.pink.shade50,
                  icon: Icons.favorite,
                  iconColor: Colors.pink.shade700,
                  onTap: () => _doLike(cards.first),
                ),
                _RoundAction(
                  color: Colors.orange.shade50,
                  icon: Icons.flag_outlined,
                  iconColor: Colors.orange.shade800,
                  onTap: () async {
                    final e = cards.first;
                    await ref.read(safetyStoreProvider.notifier).report(
                          targetId: e.correlationId,
                          reason: 'Reported from swipe feed',
                        );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Reported & blocked')),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCard(LocalEncounter e) {
    final me = ref.watch(sessionControllerProvider);
    final letter =
        e.displayName.isNotEmpty ? e.displayName[0].toUpperCase() : '?';
    final remaining = e.timeRemaining;
    final progress = e.expiresAt == null
        ? 0.0
        : remaining.inMilliseconds /
            LocalEncounter.feetLifespan.inMilliseconds;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: GestureDetector(
          onLongPress: () => _aliasDialog(e.correlationId, e.displayName),
          child: Card(
            elevation: 4,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: Colors.grey.shade200,
                ),
                Expanded(
                  child: me.photoPaths.isNotEmpty
                      ? Image.file(
                          File(me.photoPaths.first),
                          fit: BoxFit.cover,
                          // Peer photo unknown locally — show own as placeholder art
                          // until server profiles exist.
                          color: Colors.black26,
                          colorBlendMode: BlendMode.darken,
                          errorBuilder: (_, __, ___) => _letterAvatar(letter),
                        )
                      : _letterAvatar(letter),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Someone nearby',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(e.neighborhoodLabel,
                          style: TextStyle(color: Colors.grey.shade800)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.timer_outlined,
                              size: 16, color: Colors.orange.shade800),
                          const SizedBox(width: 4),
                          Text(
                            e.expiresAt == null
                                ? 'Stays until you swipe'
                                : 'Expires in ${_fmt(remaining)}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: remaining.inHours < 2
                                  ? Colors.red.shade700
                                  : Colors.orange.shade900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Swipe ← pass · → like · long-press alias · photo+area only',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _letterAvatar(String letter) {
    return Container(
      color: Theme.of(context)
          .colorScheme
          .primaryContainer
          .withValues(alpha: 0.55),
      child: Center(
        child: CircleAvatar(
          radius: 64,
          child: Text(letter, style: const TextStyle(fontSize: 48)),
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.color,
    required this.icon,
    required this.iconColor,
    required this.onTap,
  });
  final Color color;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Icon(icon, size: 28, color: iconColor),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.pending,
    required this.delayHours,
    required this.band,
  });
  final int pending;
  final double delayHours;
  final String band;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 72, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              pending > 0
                  ? 'Run-in logged — not revealed yet'
                  : band == 'any'
                      ? 'No one to swipe'
                      : 'No one in $band band',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              pending > 0
                  ? 'They appear after ${delayHours <= 0 ? "instant test reveal" : "${delayHours}h"}.'
                  : 'Turn Beacon on near someone else.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
