// E-B2 installed proof surface (§4): a production-INVISIBLE, diag-only
// selected-peer control reachable through the installed app. It lists the
// currently eligible W5 peers as run-scoped HANDLES (the raw aliases never leave
// native), lets the operator select one and atomically arm a one-shot pre-ACK
// fault plus an optional one-shot delay, shows the native structured ack/status,
// and disarms/resets. Nil / empty / ineligible selections fail closed natively.
//
// This whole widget is only ever instantiated behind `AppConfig.kDiagBuild`
// (a const-false in release), so it — and its strings/symbols — tree-shake out of
// the production AOT bundle (verified by the E-B5 final-binary isolation gate).

import 'package:flutter/material.dart';

import 'background_beacon_channel.dart';

class W5DiagPanel extends StatefulWidget {
  const W5DiagPanel({super.key, BackgroundBeaconChannel? channel})
      : _channel = channel;

  final BackgroundBeaconChannel? _channel;

  @override
  State<W5DiagPanel> createState() => _W5DiagPanelState();
}

class _W5DiagPanelState extends State<W5DiagPanel> {
  late final BackgroundBeaconChannel _bb =
      widget._channel ?? BackgroundBeaconChannel();

  List<String> _peers = const [];
  String? _selected;
  double _delay = 0;
  String _status = 'idle';
  bool _armed = false;
  int _eligibleCount = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final peers = await _bb.listW5Peers();
    final status = await _bb.w5DiagStatus();
    if (!mounted) return;
    setState(() {
      _peers = peers
          .map((p) => p['handle'])
          .whereType<String>()
          .toList(growable: false);
      if (_selected != null && !_peers.contains(_selected)) _selected = null;
      _armed = status?['armed'] == true;
      _eligibleCount = (status?['eligibleCount'] as int?) ?? _peers.length;
    });
  }

  Future<void> _arm() async {
    final sel = _selected;
    if (sel == null) {
      setState(() => _status = 'no-peer-selected');
      return;
    }
    final ack =
        await _bb.armW5FaultForPeer(handle: sel, delaySeconds: _delay);
    if (!mounted) return;
    setState(() {
      if (ack == null) {
        _status = 'channel-error';
      } else if (ack['ok'] == true) {
        _armed = true;
        _status = 'armed ${ack['peer']} delay=${ack['delaySeconds']}';
      } else {
        _armed = false;
        _status = 'rejected:${ack['rejected']}';
      }
    });
  }

  Future<void> _disarm() async {
    await _bb.disarmW5Fault();
    if (!mounted) return;
    setState(() {
      _armed = false;
      _status = 'disarmed';
    });
  }

  Future<void> _reset() async {
    await _bb.resetW5Case();
    if (!mounted) return;
    setState(() {
      _armed = false;
      _selected = null;
      _delay = 0;
      _status = 'reset';
    });
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('w5DiagPanel'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('W5 diagnostics — eligible peers: $_eligibleCount',
            key: const Key('w5DiagEligible')),
        Text('status: $_status', key: const Key('w5DiagStatusText')),
        Text('armed: $_armed', key: const Key('w5DiagArmed')),
        for (final h in _peers)
          ListTile(
            key: Key('w5peer_$h'),
            dense: true,
            title: Text(h),
            trailing: _selected == h ? const Icon(Icons.check) : null,
            onTap: () => setState(() => _selected = h),
          ),
        Row(
          children: [
            const Text('delay(s):'),
            SizedBox(
              width: 64,
              child: TextField(
                key: const Key('w5DiagDelay'),
                keyboardType: TextInputType.number,
                onChanged: (v) => _delay = double.tryParse(v) ?? 0,
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          children: [
            ElevatedButton(
              key: const Key('w5DiagArm'),
              onPressed: _arm,
              child: const Text('Arm fault'),
            ),
            OutlinedButton(
              key: const Key('w5DiagDisarm'),
              onPressed: _disarm,
              child: const Text('Disarm'),
            ),
            OutlinedButton(
              key: const Key('w5DiagReset'),
              onPressed: _reset,
              child: const Text('Reset case'),
            ),
            OutlinedButton(
              key: const Key('w5DiagRefresh'),
              onPressed: _refresh,
              child: const Text('Refresh'),
            ),
          ],
        ),
      ],
    );
  }
}
