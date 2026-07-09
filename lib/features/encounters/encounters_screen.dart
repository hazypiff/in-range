import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_range/core/config/app_config.dart';
import 'package:in_range/features/encounters/encounters_provider.dart';
import 'package:in_range/features/encounters/local_encounter_store.dart';
import 'package:in_range/features/encounters/swipe_feed.dart';

/// Tab 2 — feet run-ins swipe feed (photo + neighborhood only).
class EncountersScreen extends ConsumerStatefulWidget {
  const EncountersScreen({super.key});

  @override
  ConsumerState<EncountersScreen> createState() => _EncountersScreenState();
}

class _EncountersScreenState extends ConsumerState<EncountersScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    if (!AppConfig.isInstantEncounters) {
      _tick = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keep server provider warm for when Supabase is real.
    ref.watch(myEncountersProvider);
    final pending = ref.watch(pendingRevealCountProvider);
    final delayHours = AppConfig.encounterRevealDelayHours;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Encounters'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(myEncountersProvider);
              setState(() {});
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          _DelayBanner(
            delayHours: delayHours,
            pendingCount: pending,
          ),
          const Expanded(child: SwipeFeed()),
        ],
      ),
    );
  }
}

class _DelayBanner extends StatelessWidget {
  const _DelayBanner({
    required this.delayHours,
    required this.pendingCount,
  });

  final double delayHours;
  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    final isTest = delayHours <= 0;
    return Material(
      color: isTest
          ? Colors.orange.shade50
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              isTest ? Icons.science_outlined : Icons.schedule,
              size: 18,
              color: isTest ? Colors.orange.shade800 : Colors.grey.shade700,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isTest
                    ? 'Test mode: encounters reveal instantly · swipe photo + hood only'
                    : 'Reveal after ${delayHours % 1 == 0 ? delayHours.toInt() : delayHours}h'
                        '${pendingCount > 0 ? ' · $pendingCount waiting' : ''}',
                style: TextStyle(
                  fontSize: 12,
                  color:
                      isTest ? Colors.orange.shade900 : Colors.grey.shade800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
