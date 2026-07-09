import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_range/core/navigation/home_tab.dart';
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
        if (isMiles) {
          // Keep GPS optional when turning off beacon; Locals tab owns continuous GPS.
        }
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
        await ref.read(beaconControllerProvider.notifier).toggle();
        // BLE still runs for hybrid discovery; miles is continuous GPS.
      } else {
        await ref.read(beaconControllerProvider.notifier).toggle();
      }

      final s = ref.read(beaconControllerProvider);
      if (!s.isOn && mounted) {
        setState(() {
          _lastError =
              'Beacon stayed off — check location permission + Bluetooth.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _lastError = e.toString());
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
                onTap: () =>
                    ref.read(homeTabIndexProvider.notifier).state = 1,
              ),
            ),
          const SizedBox(height: 12),
          Text('Range', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: range,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'feet_10', child: Text('10 ft (BLE · 24h)')),
              DropdownMenuItem(value: 'feet_20', child: Text('20 ft (BLE · 24h)')),
              DropdownMenuItem(value: 'feet_30', child: Text('30 ft (BLE · 24h)')),
              DropdownMenuItem(value: 'miles_1', child: Text('1 mi (GPS · keep)')),
              DropdownMenuItem(value: 'miles_5', child: Text('5 mi (GPS · keep)')),
              DropdownMenuItem(value: 'miles_10', child: Text('10 mi (GPS · keep)')),
              DropdownMenuItem(value: 'miles_25', child: Text('25 mi (GPS · keep)')),
              DropdownMenuItem(value: 'miles_50', child: Text('50 mi (GPS · keep)')),
              DropdownMenuItem(value: 'miles_100', child: Text('100 mi (GPS · keep)')),
              DropdownMenuItem(value: 'miles_200', child: Text('200 mi (GPS · keep)')),
            ],
            onChanged: (v) {
              if (v != null) {
                ref.read(selectedRangeProvider.notifier).set(v);
              }
            },
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
