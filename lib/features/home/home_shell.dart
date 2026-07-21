import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_range/core/navigation/home_tab.dart';
import 'package:in_range/features/beacon/beacon_screen.dart';
import 'package:in_range/features/beacon/beacon_provider.dart';
import 'package:in_range/features/chat/messages_screen.dart';
import 'package:in_range/features/encounters/encounters_screen.dart';
import 'package:in_range/features/encounters/local_encounter_store.dart';
import 'package:in_range/features/locals/locals_screen.dart';
import 'package:in_range/features/locals/locals_service.dart';
import 'package:in_range/features/matches/match_store.dart';
import 'package:in_range/features/settings/settings_screen.dart';
import 'package:in_range/features/widgets/offline_banner.dart';

/// Root shell with animated badges for new encounters + matches.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  int _prevEncounters = 0;

  static const _pages = <Widget>[
    BeaconScreen(),
    EncountersScreen(),
    LocalsScreen(),
    MessagesScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(homeTabIndexProvider);
    final newEncounters = ref.watch(newEncounterCountProvider);
    final matchCount = ref.watch(matchStoreProvider).length;

    if (newEncounters > _prevEncounters) {
      _pulse.forward(from: 0);
    }
    _prevEncounters = newEncounters;

    Widget encIcon(IconData icon) {
      final child = Icon(icon);
      if (newEncounters <= 0) return child;
      return ScaleTransition(
        scale: Tween(begin: 1.0, end: 1.25).animate(
          CurvedAnimation(parent: _pulse, curve: Curves.elasticOut),
        ),
        child: Badge(
          label: Text('$newEncounters'),
          child: child,
        ),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: IndexedStack(
              index: index,
              children: [
                // IndexedStack keeps hidden tabs alive, which keeps their
                // animation tickers firing offstage — mute them so only the
                // visible tab animates (battery matters while beacon is ON).
                for (var i = 0; i < _pages.length; i++)
                  TickerMode(enabled: i == index, child: _pages[i]),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: index == 0
          ? FloatingActionButton.small(
              tooltip: 'Settings',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SettingsScreen(),
                  ),
                );
              },
              child: const Icon(Icons.settings_outlined),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) async {
          final previous = ref.read(homeTabIndexProvider);
          ref.read(homeTabIndexProvider.notifier).state = i;
          if (i == 2) {
            await ref.read(localsControllerProvider.notifier).start();
          } else if (previous == 2) {
            final beaconOn = ref.read(beaconControllerProvider).isOn;
            final miles = ref.read(selectedRangeProvider).startsWith('miles');
            if (!beaconOn || !miles) {
              await ref.read(localsControllerProvider.notifier).stop();
            }
          }
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.radar_outlined),
            selectedIcon: Icon(Icons.radar),
            label: 'Beacon',
          ),
          NavigationDestination(
            icon: encIcon(Icons.people_outline),
            selectedIcon: encIcon(Icons.people),
            label: 'Encounters',
          ),
          const NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Locals',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: matchCount > 0,
              label: Text('$matchCount'),
              child: const Icon(Icons.chat_bubble_outline),
            ),
            selectedIcon: Badge(
              isLabelVisible: matchCount > 0,
              label: Text('$matchCount'),
              child: const Icon(Icons.chat_bubble),
            ),
            label: 'Matches',
          ),
        ],
      ),
    );
  }
}
