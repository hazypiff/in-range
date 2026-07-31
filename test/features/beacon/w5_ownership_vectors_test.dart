import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_range/features/beacon/w5_ownership.dart';

/// Ownership conformance — driven by the SHARED, hand-written vectors
/// (w5_ownership_vectors.json), the same file the Swift suite consumes
/// (round-7 fix #4). Pins semantics across both oracles, independent of
/// either implementation's output.
void main() {
  final doc = jsonDecode(File('test/features/beacon/w5_ownership_vectors.json')
      .readAsStringSync()) as Map<String, dynamic>;

  List<W5Effect> run(W5Ownership a, Map<String, dynamic> step) {
    switch (step['event'] as String) {
      case 'discovered':
        return a.onDiscovered(
            alias: step['alias'],
            wouldDial: step['wouldDial'] as bool,
            candidateId: step['candidateId'],
            linkId: step['linkId']);
      case 'control':
        return a.onControl(
            handle: step['handle'],
            role: step['role'] == 'outbound' ? W5Role.outbound : W5Role.inbound,
            myCandidate: step['myCandidate'],
            peerCandidate: step['peerCandidate'],
            peerAlias: step['peerAlias'],
            linkId: step['linkId'],
            peerPrevAlias: step['peerPrevAlias'] as String?);
      case 'proposeRecv':
        return a.onProposeRecv(
            peerAlias: step['peerAlias'],
            proposal: W5Proposal(step['encounterId'], step['viewGen'] as int, [
              for (final c in step['contenders'] as List)
                W5Contender(c[0] as String, c[1] as String),
            ]));
      case 'ackCurrent':
        final lease = a.leaseForAlias(step['peerAlias'] as String)!;
        final cur = a.currentProposal(lease)!;
        return a.onAckRecv(
            peerAlias: step['peerAlias'],
            ack: W5Ack(cur.encounterId, cur.viewGen, cur.viewHash));
      case 'linkDown':
        return a.onLinkDown(handle: step['handle']);
      case 'teardown':
        return a.onTeardown(leaseId: step['leaseId']);
      case 'graceExpiry':
        return a.onGraceExpiry(leaseId: step['leaseId']);
      default:
        throw StateError('unknown event ${step['event']}');
    }
  }

  void matchEffects(List<W5Effect> got, List expected, String ctx) {
    expect(got.length, expected.length,
        reason: '$ctx: effect count (got $got)');
    for (var i = 0; i < expected.length; i++) {
      final e = expected[i] as Map<String, dynamic>;
      final g = got[i];
      final kind = e['kind'] as String;
      switch (kind) {
        case 'dial':
          expect(g, W5Dial(e['linkId']), reason: ctx);
        case 'owns':
          expect(g, W5Owns(e['handle']), reason: ctx);
        case 'closeOutbound':
          expect(g, W5CloseOutbound(e['handle']), reason: ctx);
        case 'rejectInbound':
          expect(g, W5RejectInbound(e['handle']), reason: ctx);
        case 'ended':
          expect(g, W5Ended(e['leaseId']), reason: ctx);
        case 'sendPropose':
          expect(g, isA<W5SendPropose>(), reason: ctx);
        case 'sendAck':
          expect(g, isA<W5SendAck>(), reason: ctx);
        default:
          fail('$ctx: unknown expected kind $kind');
      }
    }
  }

  for (final v in doc['vectors'] as List) {
    test('vector: ${v['name']}', () {
      final a = W5Ownership();
      final steps = v['steps'] as List;
      for (var i = 0; i < steps.length; i++) {
        final step = steps[i] as Map<String, dynamic>;
        final fx = run(a, step);
        if (step['expectEffects'] != null) {
          matchEffects(fx, step['expectEffects'] as List, 'step $i');
        }
      }
      final obs = v['finalObs'] as Map<String, dynamic>;
      if (obs['activeLeases'] != null) {
        expect(a.activeLeases, obs['activeLeases'], reason: 'activeLeases');
      }
      (obs['committed'] as Map<String, dynamic>? ?? {}).forEach((lease, link) {
        expect(a.committedLinkId(lease), link, reason: 'committed[$lease]');
      });
      (obs['leaseForAlias'] as Map<String, dynamic>? ?? {})
          .forEach((alias, lease) {
        expect(a.leaseForAlias(alias), lease, reason: 'leaseForAlias[$alias]');
      });
      (obs['keeperOf'] as Map<String, dynamic>? ?? {}).forEach((lease, h) {
        expect(a.keeperOf(lease), h, reason: 'keeperOf[$lease]');
      });
      (obs['viewGenAtLeast'] as Map<String, dynamic>? ?? {})
          .forEach((lease, n) {
        expect(
            a.currentProposal(lease)!.viewGen, greaterThanOrEqualTo(n as int),
            reason: 'viewGen[$lease]');
      });
    });
  }
}
