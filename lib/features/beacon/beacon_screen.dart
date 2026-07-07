import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_range/features/beacon/beacon_provider.dart';
import 'package:in_range/features/beacon/beacon_service.dart';
import 'package:in_range/features/encounters/encounters_provider.dart';

/// Minimal Beacon screen — toggle beacon on/off + see current token status.
/// Not the final UI; just enough to exercise the service end-to-end on device.
class BeaconScreen extends ConsumerWidget {
  const BeaconScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(beaconControllerProvider);
    final range = ref.watch(selectedRangeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('In Range — Beacon')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusCard(state: state),
            const SizedBox(height: 16),
            _RangeSelector(
              value: range,
              onChanged: (v) =>
                  ref.read(selectedRangeProvider.notifier).state = v,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: ref.read(beaconControllerProvider.notifier).toggle,
              icon: Icon(state.isOn ? Icons.stop : Icons.play_arrow),
              label: Text(state.isOn ? 'Turn Beacon Off' : 'Turn Beacon On'),
            ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            const Text('Recent Encounters',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Expanded(child: _EncountersList()),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.state});
  final BeaconState state;

  @override
  Widget build(BuildContext context) {
    final expiry = state.tokenExpiresAt;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  state.isOn ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: state.isOn ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 12),
                Text(state.isOn ? 'Beacon Active' : 'Beacon Off',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600)),
              ],
            ),
            if (state.isOn && expiry != null) ...[
              const SizedBox(height: 8),
              Text('Token expires: ${expiry.toLocal()}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ],
        ),
      ),
    );
  }
}

class _RangeSelector extends StatelessWidget {
  const _RangeSelector({required this.value, required this.onChanged});
  final String value;
  final void Function(String) onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'feet', label: Text('Feet (BLE)')),
        ButtonSegment(value: 'miles', label: Text('Miles (GPS)')),
      ],
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

class _EncountersList extends ConsumerWidget {
  const _EncountersList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myEncountersProvider);
    return async.when(
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(
              child: Text('No encounters yet — turn your beacon on.',
                  style: TextStyle(color: Colors.grey)));
        }
        return ListView(
          children: rows
              .map((r) => ListTile(
                    title: Text(r['display_name']?.toString() ?? 'Someone'),
                    subtitle: Text(r['neighborhood']?.toString() ?? ''),
                    trailing: Text(r['range_type']?.toString() ?? ''),
                  ))
              .toList(),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}
