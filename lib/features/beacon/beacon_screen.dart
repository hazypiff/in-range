import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_range/core/navigation/home_tab.dart';
import 'package:in_range/core/permissions/permission_service.dart';
import 'package:in_range/core/privacy/safety_store.dart';
import 'package:in_range/features/beacon/beacon_provider.dart';
import 'package:in_range/features/encounters/local_encounter_store.dart';
import 'package:in_range/features/locals/locals_service.dart';
import 'package:in_range/features/widgets/ad_banner.dart';

class BeaconScreen extends ConsumerStatefulWidget {
  const BeaconScreen({super.key});

  @override
  ConsumerState<BeaconScreen> createState() => _BeaconScreenState();
}

class _BeaconScreenState extends ConsumerState<BeaconScreen> {
  String? _lastError;

  Future<void> _doToggle() async {
    setState(() => _lastError = null);
    final safety = ref.read(safetyStoreProvider);
    final range = ref.read(selectedRangeProvider);
    final isMiles = range.startsWith('miles');

    try {
      final beacon = ref.read(beaconControllerProvider);
      if (beacon.isOn) {
        await ref.read(beaconControllerProvider.notifier).toggle();
        if (isMiles) await ref.read(localsControllerProvider.notifier).stop();
        return;
      }

      if (safety.incognito) {
        setState(() {
          _lastError =
              'Incognito is on — turn it off in Settings to be findable.';
        });
        return;
      }

      if (isMiles) {
        // Miles mode: GPS logging while beacon ON (product outline).
        await ref.read(localsControllerProvider.notifier).start();
        try {
          await ref.read(beaconControllerProvider.notifier).toggle();
        } catch (_) {
          await ref.read(localsControllerProvider.notifier).stop();
          rethrow;
        }
        // BLE still runs for hybrid discovery; miles is continuous GPS.
      } else {
        await ref.read(beaconControllerProvider.notifier).toggle();
      }

      final s = ref.read(beaconControllerProvider);
      if (!s.isOn && mounted) {
        // Name the exact denied permission on-screen — field debugging must
        // not depend on a tethered debug session (2026-07-16 iOS incident).
        final diag = await PermissionService.diagnose();
        if (mounted) {
          setState(() {
            _lastError = 'Beacon stayed off — $diag';
          });
        }
      }
    } catch (e) {
      debugPrint('Beacon toggle failed: $e');
      if (mounted) {
        // Surface the real reason. Config/crypto/sign-in failures are
        // StateErrors and are NOT permission problems — don't mislabel them.
        setState(() {
          // Surface the raw exception so field debugging doesn't need a
          // tethered session (2026-07-16). Type + message pins the throw site.
          _lastError = e is StateError
              ? 'Beacon could not start: ${e.message}'
              : 'Beacon error [${e.runtimeType}]: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(beaconControllerProvider);
    final range = ref.watch(selectedRangeProvider);
    final newCount = ref.watch(newEncounterCountProvider);
    final pending = ref.watch(pendingRevealCountProvider);
    final safety = ref.watch(safetyStoreProvider);
    final isMiles = range.startsWith('miles');

    return Scaffold(
      appBar: AppBar(title: const Text('Beacon')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const FreeAdBanner(),
          const SizedBox(height: 8),
          _StatusCard(
            state: state,
            incognito: safety.incognito,
            boost: safety.boostActive,
          ),
          if (state.isOn && !state.discoverable) ...[
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              child: const ListTile(
                leading: Icon(Icons.wifi_find_outlined),
                title: Text('Scanning only — not discoverable'),
                subtitle: Text(
                  'This device finds and logs nearby beacons, but could not '
                  'start advertising, so others can\'t discover it right now.',
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (newCount > 0 || pending > 0)
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: ListTile(
                leading: Badge(
                  label: Text('$newCount'),
                  isLabelVisible: newCount > 0,
                  child: const Icon(Icons.notifications_active_outlined),
                ),
                title: Text(
                  newCount > 0
                      ? 'You have $newCount new encounter${newCount == 1 ? "" : "s"}'
                      : '$pending run-in${pending == 1 ? "" : "s"} waiting to reveal',
                ),
                subtitle: const Text('Tap to open Encounters'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => ref.read(homeTabIndexProvider.notifier).state = 1,
              ),
            ),
          const SizedBox(height: 12),
          Text('Range', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          // Fixed range (no user picker for now): beacon runs wide and the
          // RangeEstimator tags every encounter 10/30/60 ft automatically.
          InputDecorator(
            decoration: const InputDecoration(border: OutlineInputBorder()),
            child: Text(
              'Up to ~60 ft (BLE · 24h) — encounters tagged Close By / Near By / In Range',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isMiles
                ? 'Miles: continuous GPS while Beacon ON · indefinite until swiped'
                : 'Feet: continuous BLE while both beacons ON · 24h to swipe',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _doToggle,
            icon: Icon(state.isOn ? Icons.stop : Icons.play_arrow),
            label: Text(state.isOn ? 'Turn Beacon Off' : 'Turn Beacon On'),
          ),
          if (_lastError != null) ...[
            const SizedBox(height: 12),
            Text(_lastError!,
                style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
          ],
          const SizedBox(height: 20),
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Beacon ON = findable. Incognito (Settings) stops advertising. '
                'Feet uses Bluetooth; Miles keeps location logging on. '
                'Background mode is best-effort on Android 10.',
                style: TextStyle(fontSize: 13, height: 1.35),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.state,
    required this.incognito,
    required this.boost,
  });
  final BeaconState state;
  final bool incognito;
  final bool boost;

  @override
  Widget build(BuildContext context) {
    final expiry = state.tokenExpiresAt;
    final title = incognito
        ? 'Incognito — not findable'
        : state.isOn
            ? 'Beacon is ON — finding people near you'
            : 'Beacon is OFF';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  state.isOn && !incognito
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: state.isOn && !incognito ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            if (state.isOn && expiry != null) ...[
              const SizedBox(height: 8),
              Text(
                'Token expires: ${expiry.toLocal()}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            if (state.isOn && state.cloudSynced == false) ...[
              const SizedBox(height: 6),
              Text(
                'Local BLE only — the cloud claim did not sync.',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
              ),
            ],
            if (boost) ...[
              const SizedBox(height: 6),
              Text('Boost active (local sim)',
                  style: TextStyle(
                      fontSize: 12, color: Colors.deepPurple.shade700)),
            ],
          ],
        ),
      ),
    );
  }
}
