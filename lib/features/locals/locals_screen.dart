import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_range/core/config/app_config.dart';
import 'package:in_range/features/encounters/local_encounter_store.dart';
import 'package:in_range/features/locals/locals_service.dart';
import 'package:in_range/features/matches/match_store.dart';

/// Tab 3 — Locals (miles, GPS). Privacy-safe coarse distance labels.
class LocalsScreen extends ConsumerStatefulWidget {
  const LocalsScreen({super.key});

  @override
  ConsumerState<LocalsScreen> createState() => _LocalsScreenState();
}

class _LocalsScreenState extends ConsumerState<LocalsScreen> {
  String _range = 'miles_1';

  static const _ranges = <String, double>{
    'miles_1': 1,
    'miles_5': 5,
    'miles_10': 10,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = ref.read(localsControllerProvider.notifier);
      c.setRange(_range);
    });
  }

  /// Coarse distance band — never precise meters on UI.
  String _coarseDistanceLabel(double? meters) {
    if (meters == null) return 'Nearby area';
    final mi = meters / 1609.34;
    if (mi < 0.3) return 'Under ½ mi';
    if (mi < 1) return 'Under 1 mi';
    if (mi < 3) return 'About 1–3 mi';
    if (mi < 10) return 'About ${mi.round()} mi';
    if (mi < 50) return 'About ${(mi / 5).round() * 5} mi';
    return 'Farther out';
  }

  double? _fakeDistanceFromRssi(int rssi) {
    // Lab-only: map RSSI to a coarse mile estimate for dual-phone UI without server.
    // Strong BLE → small miles; weak → larger. Not real GPS distance.
    final clamped = rssi.clamp(-100, -30);
    final t = (-30 - clamped) / 70.0; // 0..1
    return 200 + t * 8000; // ~0.1–5 mi equivalent meters
  }

  @override
  Widget build(BuildContext context) {
    final gps = ref.watch(localsControllerProvider);
    final peers = ref.watch(localEncounterStoreProvider).values.toList()
      ..sort((a, b) => b.lastSeenAt.compareTo(a.lastSeenAt));
    final matchStore = ref.watch(matchStoreProvider.notifier);
    final maxMi = _ranges[_range] ?? 1;

    final filtered = peers.where((e) {
      final m = _fakeDistanceFromRssi(e.bestRssi);
      if (m == null) return true;
      return (m / 1609.34) <= maxMi * 1.2; // soft band
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Locals'),
        actions: [
          IconButton(
            tooltip: 'Refresh location',
            onPressed: () =>
                ref.read(localsControllerProvider.notifier).start(),
            icon: const Icon(Icons.my_location),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GpsCard(gps: gps),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Near you · miles (GPS) · indefinite until swiped',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Colors.grey.shade700,
                  ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: _ranges.entries.map((e) {
                final selected = e.key == _range;
                final label = e.value == e.value.roundToDouble()
                    ? '${e.value.toInt()} mi'
                    : '${e.value} mi';
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilterChip(
                    label: Text(label),
                    selected: selected,
                    onSelected: (_) {
                      setState(() => _range = e.key);
                      ref
                          .read(localsControllerProvider.notifier)
                          .setRange(e.key);
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          if (gps.usingServer)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                'Cloud feed · ${gps.serverPeers.length} nearby',
                style: TextStyle(fontSize: 12, color: Colors.green.shade800),
              ),
            )
          else if (AppConfig.hasRealSupabase)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                gps.lastSyncError != null
                    ? 'Cloud sync paused — showing local peers'
                    : 'Connecting cloud Locals…',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: _buildGrid(
              context,
              gps: gps,
              localPeers: filtered,
              matchStore: matchStore,
              maxMi: maxMi,
            ),
          ),
        ],
      ),
    );
  }
}

class _GpsCard extends StatelessWidget {
  const _GpsCard({required this.gps});
  final LocalsState gps;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  gps.broadcasting ? Icons.gps_fixed : Icons.gps_not_fixed,
                  color: gps.hasFix ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    gps.hasFix
                        ? 'Sharing coarse location · ${gps.neighborhood}'
                        : 'Acquiring GPS…',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            if (gps.hasFix) ...[
              const SizedBox(height: 6),
              Text(
                'Updated ${gps.updatedAt?.toLocal().toString().substring(0, 19) ?? "—"}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ],
            if (gps.error != null) ...[
              const SizedBox(height: 6),
              Text(gps.error!,
                  style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
            ],
            const SizedBox(height: 6),
            Text(
              gps.usingServer
                  ? 'Server miles correlation active · coarse bands only.'
                  : 'Distance shown as coarse bands only — never exact coordinates. '
                      '${AppConfig.hasRealSupabase ? "Local fallback until cloud syncs." : "Offline mode."}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

extension on _LocalsScreenState {
  Widget _buildGrid(
    BuildContext context, {
    required LocalsState gps,
    required List localPeers,
    required dynamic matchStore,
    required double maxMi,
  }) {
    final server = gps.serverPeers;
    final useServer = gps.usingServer && server.isNotEmpty;
    final count = useServer ? server.length : localPeers.length;

    if (count == 0) {
      return _EmptyLocals(
        rangeLabel: '${maxMi.toInt()} mi',
        hasFix: gps.hasFix,
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.92,
      ),
      itemCount: count,
      itemBuilder: (context, i) {
        if (useServer) {
          final row = server[i];
          final uid = row['user_id']?.toString() ?? 'peer-$i';
          final meters = (row['distance_m'] as num?)?.toDouble();
          final distLabel = _coarseDistanceLabel(meters);
          final hood = row['neighborhood']?.toString() ?? gps.neighborhood;
          final boosted = row['is_boosted'] == true;
          return _PeerCard(
            letter: '•',
            distLabel: distLabel,
            neighborhood: hood,
            badge: boosted ? 'Boosted' : null,
            dismissed: matchStore.isDismissed(uid),
            onTap: () async {
              try {
                // UUID → swipe_user RPC (creates/finds encounter then swipes).
                await ref.read(matchStoreProvider.notifier).like(
                      correlationId: uid,
                      displayName: 'Someone nearby',
                      neighborhood: hood,
                      otherUserId: uid,
                      range: _range,
                    );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Liked from Locals')),
                  );
                }
              } catch (e) {
                debugPrint('Locals like failed: $e');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Like failed.')),
                  );
                }
              }
            },
          );
        }

        final e = localPeers[i];
        final dismissed = matchStore.isDismissed(e.correlationId);
        final meters = _fakeDistanceFromRssi(e.bestRssi);
        final distLabel = _coarseDistanceLabel(meters);
        final letter =
            e.displayName.isNotEmpty ? e.displayName[0].toUpperCase() : '?';
        return _PeerCard(
          letter: letter,
          distLabel: distLabel,
          neighborhood: gps.neighborhood,
          dismissed: dismissed,
          onLongPress: () async {
            final ctrl = TextEditingController(text: e.alias ?? '');
            final alias = await showDialog<String>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Device alias'),
                content: TextField(
                  controller: ctrl,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Couch phone',
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, ctrl.text),
                    child: const Text('Save'),
                  ),
                ],
              ),
            );
            if (alias != null) {
              await ref
                  .read(localEncounterStoreProvider.notifier)
                  .setAlias(e.correlationId, alias);
            }
          },
          onTap: dismissed
              ? null
              : () async {
                  await ref.read(matchStoreProvider.notifier).like(
                        correlationId: e.correlationId,
                        displayName: e.displayName,
                        neighborhood: distLabel,
                      );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Liked from Locals')),
                    );
                  }
                },
        );
      },
    );
  }
}

class _PeerCard extends StatelessWidget {
  const _PeerCard({
    required this.letter,
    required this.distLabel,
    required this.neighborhood,
    this.badge,
    this.dismissed = false,
    this.onTap,
    this.onLongPress,
  });

  final String letter;
  final String distLabel;
  final String neighborhood;
  final String? badge;
  final bool dismissed;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    child: Text(letter, style: const TextStyle(fontSize: 22)),
                  ),
                  if (badge != null) ...[
                    const Spacer(),
                    Chip(
                      label: Text(badge!, style: const TextStyle(fontSize: 10)),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ],
              ),
              const Spacer(),
              const Text(
                'Someone nearby',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text(
                distLabel,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              Text(
                neighborhood,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
              if (dismissed)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Icon(Icons.check, size: 16, color: Colors.grey),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyLocals extends StatelessWidget {
  const _EmptyLocals({required this.rangeLabel, required this.hasFix});
  final String rangeLabel;
  final bool hasFix;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              'No locals in range yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              hasFix
                  ? 'Within $rangeLabel, people who share GPS pings appear here. '
                      '${AppConfig.hasRealSupabase ? "" : "Lab mode lists BLE-active peers with coarse distance bands."}'
                  : 'Enable location to broadcast a coarse miles ping.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
