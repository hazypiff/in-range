import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_range/core/config/app_config.dart';
import 'package:in_range/core/notifications/local_notify.dart';
import 'package:in_range/core/prefs/app_prefs.dart';
import 'package:in_range/core/privacy/safety_store.dart';
import 'package:in_range/features/encounters/encounters_provider.dart';
import 'package:in_range/features/encounters/local_encounter_store.dart';
import 'package:in_range/features/encounters/swipe_card.dart';
import 'package:in_range/features/matches/match_store.dart';
import 'package:in_range/features/widgets/ad_banner.dart';
import 'package:in_range/shared/services/photo_url_service.dart';

class SwipeFeed extends ConsumerStatefulWidget {
  const SwipeFeed({super.key});

  @override
  ConsumerState<SwipeFeed> createState() => _SwipeFeedState();
}

class _SwipeFeedState extends ConsumerState<SwipeFeed> {
  Timer? _tick;
  // Incremented every second to drive countdown text only — avoids rebuilding
  // the entire swipe stack via setState on every tick.
  final ValueNotifier<int> _tickNotifier = ValueNotifier(0);
  final _notifiedExpiring = <String>{};
  int _prevNew = 0;
  bool _actionInFlight = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _tickNotifier.value++;
      ref.read(matchStoreProvider.notifier).pruneExpired();
      _checkExpiring();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _tickNotifier.dispose();
    super.dispose();
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

  List<SwipeCard> _deck(WidgetRef ref) {
    final band = ref.watch(swipeBandFilterProvider);
    ref.watch(matchStoreProvider);
    final matchStore = ref.watch(matchStoreProvider.notifier);
    final safety = ref.watch(safetyStoreProvider);
    final server = ref.watch(myEncountersProvider).valueOrNull ?? const [];
    final local = ref.watch(localEncounterStoreProvider.notifier).visible;
    return buildHybridSwipeDeck(
      serverRows: server,
      localVisible: local,
      isDismissed: matchStore.isDismissed,
      blocked: safety.blocked,
    ).where((c) => c.matchesBandFilter(band)).toList();
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
    if (AppConfig.hasRealSupabase) return;
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

  Future<bool> _doPass(SwipeCard c) async {
    if (_actionInFlight) return false;
    setState(() => _actionInFlight = true);
    try {
      await ref.read(matchStoreProvider.notifier).pass(
            c.id,
            displayName: c.displayLabel,
            neighborhood: c.neighborhood,
            otherUserId: c.otherUserId,
            range: c.rangeType,
          );
      await _showUndo();
      return true;
    } catch (e) {
      debugPrint('Pass failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pass failed.')),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _actionInFlight = false);
    }
  }

  Future<bool> _doLike(SwipeCard c) async {
    if (_actionInFlight) return false;
    setState(() => _actionInFlight = true);
    try {
      await ref.read(matchStoreProvider.notifier).like(
            correlationId: c.id,
            displayName: c.displayLabel,
            neighborhood: c.neighborhood,
            photoPaths: c.photoUrls,
            otherUserId: c.otherUserId,
            range: c.rangeType,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Liked'),
            duration: Duration(seconds: 1),
          ),
        );
        await _showUndo();
      }
      return true;
    } catch (e) {
      debugPrint('Like failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Like failed.')),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _actionInFlight = false);
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
      await ref.read(localEncounterStoreProvider.notifier).setAlias(corr, name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final band = ref.watch(swipeBandFilterProvider);
    final pending = ref.watch(pendingRevealCountProvider);
    final newCount = ref.watch(newEncounterCountProvider);
    // Keep server encounters warm
    ref.watch(myEncountersProvider);

    if (newCount > _prevNew) {
      LocalNotify.instance.notifyNewEncounter('new');
    }
    _prevNew = newCount;

    final cards = _deck(ref);
    final serverCount = cards.where((c) => c.isServer).length;

    return Column(
      children: [
        const FreeAdBanner(),
        if (AppConfig.hasRealSupabase && serverCount > 0)
          Material(
            color: Colors.green.shade50,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.cloud_done, size: 16, color: Colors.green),
                  const SizedBox(width: 8),
                  Text(
                    'Cloud deck · $serverCount verified encounter${serverCount == 1 ? "" : "s"}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              for (final e in const [
                ('any', 'Any'),
                ('feet_10', 'Close By'),
                ('feet_30', 'Near By'),
                ('feet_60', 'In Range'),
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
                  key: ValueKey(cards.first.id),
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
                      return _doPass(e);
                    }
                    return _doLike(e);
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
                  onTap: _actionInFlight ? null : () => _doPass(cards.first),
                ),
                _RoundAction(
                  color: Colors.pink.shade50,
                  icon: Icons.favorite,
                  iconColor: Colors.pink.shade700,
                  onTap: _actionInFlight ? null : () => _doLike(cards.first),
                ),
                _RoundAction(
                  color: Colors.orange.shade50,
                  icon: Icons.flag_outlined,
                  iconColor: Colors.orange.shade800,
                  onTap: () async {
                    final e = cards.first;
                    final target = e.otherUserId ?? e.id;
                    await ref.read(safetyStoreProvider.notifier).report(
                          targetId: target,
                          reason: 'Reported from swipe feed',
                        );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Reported & blocked')),
                    );
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCard(SwipeCard e) {
    final letter = '?';
    final progress = e.expiryProgress;

    Widget photo;
    if (e.photoUrls.isNotEmpty) {
      final raw = e.photoUrls.first;
      if (File(raw).existsSync()) {
        photo = Image.file(File(raw), fit: BoxFit.cover);
      } else {
        // Private storage path — resolve signed URL
        photo = FutureBuilder<String?>(
          future: PhotoUrlService.resolve(raw),
          builder: (context, snap) {
            final u = snap.data;
            if (u == null || !u.startsWith('http')) {
              return _letterAvatar(letter);
            }
            return Image.network(
              u,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _letterAvatar(letter),
            );
          },
        );
      }
    } else {
      photo = _letterAvatar(letter);
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: GestureDetector(
          onLongPress: e.local != null
              ? () => _aliasDialog(e.id, e.local!.displayName)
              : null,
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
                Expanded(child: photo),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Someone nearby',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (e.isServer)
                            Chip(
                              label: const Text('Cloud',
                                  style: TextStyle(fontSize: 10)),
                              visualDensity: VisualDensity.compact,
                              backgroundColor: Colors.green.shade50,
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(e.neighborhood,
                          style: TextStyle(color: Colors.grey.shade800)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.timer_outlined,
                              size: 16, color: Colors.orange.shade800),
                          const SizedBox(width: 4),
                          ValueListenableBuilder<int>(
                            valueListenable: _tickNotifier,
                            builder: (context, _, __) {
                              final rem = e.timeRemaining;
                              return Text(
                                e.expiresAt == null
                                    ? 'Stays until you swipe'
                                    : 'Expires in ${_fmt(rem)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: rem.inHours < 2
                                      ? Colors.red.shade700
                                      : Colors.orange.shade900,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        e.isServer
                            ? 'Photo + neighborhood only · like calls server'
                            : 'Local BLE · swipe · long-press alias',
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
  final VoidCallback? onTap;

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
                      : 'No one in this band yet',
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
