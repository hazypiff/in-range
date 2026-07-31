import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_range/features/beacon/w5_ownership.dart';

/// Two-peer tests for the #7 ownership oracle (v5.1: typed messages, per-view
/// generation, 2-phase ACK commit, linkId↔handle bijection, caps).
/// candA < candB. Local CB handles are observer-local — only wire linkIds are
/// compared across endpoints.
const candA = 'cand-a';
const candB = 'cand-b';
const aliasA = 'aliasA';
const aliasB = 'aliasB';
const leaseId = candA;

/// Two-endpoint message queue routing PROPOSE and ACK, with drops/reordering.
class _Sim {
  final a = W5Ownership();
  final b = W5Ownership();
  final List<(String to, String fromAlias, W5Effect msg)> q = [];

  void _collect(String from, List<W5Effect> fx) {
    final ep = from == 'A' ? a : b;
    final to = from == 'A' ? 'B' : 'A';
    final fromAlias = from == 'A' ? aliasA : aliasB;
    for (final f in fx) {
      if (f is W5Owns && !ep.isCommitted(leaseId)) {
        fail('owns before commit on $from (${f.handle})');
      }
      if (f is W5SendPropose || f is W5SendAck) q.add((to, fromAlias, f));
    }
  }

  void dial(String ep, String linkId) => (ep == 'A' ? a : b).onDiscovered(
      alias: ep == 'A' ? aliasB : aliasA,
      wouldDial: true,
      candidateId: ep == 'A' ? candA : candB,
      linkId: linkId);

  void linkUp(String ep, String handle, W5Role role, String linkId) => _collect(
      ep,
      (ep == 'A' ? a : b).onControl(
        handle: handle,
        role: role,
        myCandidate: ep == 'A' ? candA : candB,
        peerCandidate: ep == 'A' ? candB : candA,
        peerAlias: ep == 'A' ? aliasB : aliasA,
        linkId: linkId,
      ));

  void deliver(int i) {
    final (to, fromAlias, msg) = q.removeAt(i);
    final ep = to == 'A' ? a : b;
    if (msg is W5SendPropose) {
      _collect(
          to, ep.onProposeRecv(peerAlias: fromAlias, proposal: msg.proposal));
    } else if (msg is W5SendAck) {
      _collect(to, ep.onAckRecv(peerAlias: fromAlias, ack: msg.ack));
    }
  }

  void retry() {
    _collect('A', a.onRetryTimer(leaseId: leaseId));
    _collect('B', b.onRetryTimer(leaseId: leaseId));
  }

  void safety() {
    final la = a.committedLinkId(leaseId);
    final lb = b.committedLinkId(leaseId);
    if (la != null && lb != null && la != lb) {
      fail('SAFETY: two different committed linkIds A=$la B=$lb');
    }
  }

  void flush() {
    var guard = 0;
    while (
        (q.isNotEmpty || !(a.isCommitted(leaseId) && b.isCommitted(leaseId))) &&
            guard++ < 300) {
      while (q.isNotEmpty) {
        deliver(0);
        safety();
      }
      retry();
    }
  }
}

/// Drive one endpoint to commit against a peer whose contenders == [peerSet]:
/// deliver the peer's matching PROPOSE and its ACK of our current view.
void commitAgainst(
    W5Ownership a, String lease, List<String> peerSet, String peerAlias) {
  final mine = a.currentProposal(lease)!;
  a.onProposeRecv(
      peerAlias: peerAlias, proposal: W5Proposal(lease, 7, peerSet));
  a.onAckRecv(
      peerAlias: peerAlias, ack: W5Ack(lease, mine.viewGen, mine.viewHash));
}

void main() {
  // Headline property: safety on wire linkId + liveness under randomized
  // schedules with drops/reordering of PROPOSE and ACK.
  test('property: safety(linkId) + liveness (randomized schedules)', () {
    for (var seed = 0; seed < 500; seed++) {
      final rng = Random(seed);
      final s = _Sim();
      s.dial('A', 'Lab');
      s.dial('B', 'Lba');
      final linkUps = <void Function()>[
        () => s.linkUp('A', 'a1', W5Role.outbound, 'Lab'),
        () => s.linkUp('A', 'a2', W5Role.inbound, 'Lba'),
        () => s.linkUp('B', 'b1', W5Role.inbound, 'Lab'),
        () => s.linkUp('B', 'b2', W5Role.outbound, 'Lba'),
      ]..shuffle(rng);
      var li = 0, steps = 0;
      while ((li < linkUps.length || s.q.isNotEmpty) && steps++ < 400) {
        if (li < linkUps.length && (rng.nextInt(3) == 0 || s.q.isEmpty)) {
          linkUps[li++]();
        } else if (s.q.isNotEmpty) {
          if (rng.nextInt(4) == 0 && s.q.length > 1) {
            s.q.removeAt(rng.nextInt(s.q.length)); // drop
          } else {
            s.deliver(rng.nextInt(s.q.length)); // reorder
          }
        }
        s.safety();
      }
      s.flush();
      s.safety();
      expect(s.a.committedLinkId(leaseId), 'Lab', reason: 'A seed $seed');
      expect(s.b.committedLinkId(leaseId), 'Lab', reason: 'B seed $seed');
      expect(s.a.committedKeeper(leaseId), 'a1');
      expect(s.b.committedKeeper(leaseId), 'b1');
    }
  });

  // v5.1 core fix: the same winning linkId on a SECOND local handle must NOT
  // emit a second owns — the bijection is retained, newcomer closed.
  test('same linkId on a second handle does not re-own (bijection)', () {
    final a = W5Ownership();
    a.onControl(
        handle: 'p1',
        role: W5Role.outbound,
        myCandidate: candA,
        peerCandidate: candB,
        peerAlias: aliasB,
        linkId: 'L1');
    commitAgainst(a, leaseId, ['cand-a|L1'], aliasB);
    expect(a.committedKeeper(leaseId), 'p1');
    // Replay the winning linkId on a DIFFERENT handle → close, not a 2nd owns.
    final fx = a.onControl(
        handle: 'p2',
        role: W5Role.outbound,
        myCandidate: candA,
        peerCandidate: candB,
        peerAlias: aliasB,
        linkId: 'L1');
    expect(fx, [const W5CloseOutbound('p2')]);
    expect(a.committedKeeper(leaseId), 'p1'); // unchanged
  });

  // ... and a local handle must not silently map to a second live linkId.
  test('a handle bound to a second linkId is rejected', () {
    final a = W5Ownership();
    a.onControl(
        handle: 'p1',
        role: W5Role.outbound,
        myCandidate: candA,
        peerCandidate: candB,
        peerAlias: aliasB,
        linkId: 'L1');
    final fx = a.onControl(
        handle: 'p1', // same handle
        role: W5Role.outbound,
        myCandidate: candA,
        peerCandidate: candB,
        peerAlias: aliasB,
        linkId: 'L2'); // different linkId
    expect(fx, [const W5CloseOutbound('p1')]);
  });

  // Two same-direction duplicates agree on one wire linkId.
  test('two same-direction duplicates agree on one wire linkId', () {
    final s = _Sim();
    s.dial('A', 'L1');
    s.dial('A', 'L2');
    s.linkUp('A', 'a1', W5Role.outbound, 'L1');
    s.linkUp('A', 'a2', W5Role.outbound, 'L2');
    s.linkUp('B', 'b2', W5Role.inbound, 'L2');
    s.linkUp('B', 'b1', W5Role.inbound, 'L1');
    s.flush();
    expect(s.a.committedLinkId(leaseId), 'L1');
    expect(s.b.committedLinkId(leaseId), 'L1');
    expect(s.a.committedKeeper(leaseId), 'a1');
    expect(s.b.committedKeeper(leaseId), 'b1');
  });

  // 2-phase: a matching peer proposal WITHOUT an ACK of our view does not commit.
  test('no commit until the peer ACKs our current view', () {
    final a = W5Ownership();
    a.onControl(
        handle: 'p1',
        role: W5Role.outbound,
        myCandidate: candA,
        peerCandidate: candB,
        peerAlias: aliasB,
        linkId: 'L1');
    a.onProposeRecv(
        peerAlias: aliasB, proposal: W5Proposal(leaseId, 7, ['cand-a|L1']));
    expect(a.isCommitted(leaseId), isFalse); // matched, but no ACK yet
    final mine = a.currentProposal(leaseId)!;
    a.onAckRecv(
        peerAlias: aliasB, ack: W5Ack(leaseId, mine.viewGen, mine.viewHash));
    expect(a.committedLinkId(leaseId), 'L1'); // now committed
  });

  // Stale ACK from an older view generation is ignored.
  test('older-generation ACK does not commit', () {
    final a = W5Ownership();
    a.onControl(
        handle: 'p1',
        role: W5Role.outbound,
        myCandidate: candA,
        peerCandidate: candB,
        peerAlias: aliasB,
        linkId: 'L1');
    final gen1 = a.currentProposal(leaseId)!.viewGen;
    // A second link bumps the view generation.
    a.onControl(
        handle: 'p2',
        role: W5Role.inbound,
        myCandidate: candA,
        peerCandidate: candB,
        peerAlias: aliasB,
        linkId: 'L2');
    a.onProposeRecv(
        peerAlias: aliasB,
        proposal:
            W5Proposal(leaseId, 7, a.currentProposal(leaseId)!.contenders));
    // ACK references the OLD gen1 → must be ignored.
    a.onAckRecv(peerAlias: aliasB, ack: W5Ack(leaseId, gen1, 'cand-a|L1'));
    expect(a.isCommitted(leaseId), isFalse);
  });

  // Same-generation, different payload proposal does not commit.
  test('same-gen different-payload proposal does not commit', () {
    final a = W5Ownership();
    a.onControl(
        handle: 'p1',
        role: W5Role.outbound,
        myCandidate: candA,
        peerCandidate: candB,
        peerAlias: aliasB,
        linkId: 'L1');
    final mine = a.currentProposal(leaseId)!;
    a.onProposeRecv(
        peerAlias: aliasB,
        proposal: W5Proposal(leaseId, 7, ['cand-z|L9'])); // different payload
    a.onAckRecv(
        peerAlias: aliasB, ack: W5Ack(leaseId, mine.viewGen, mine.viewHash));
    expect(a.isCommitted(leaseId), isFalse);
  });

  // Over-cap proposal is rejected (no ACK, no commit).
  test('over-cap proposal is rejected', () {
    final a = W5Ownership();
    a.onControl(
        handle: 'p1',
        role: W5Role.outbound,
        myCandidate: candA,
        peerCandidate: candB,
        peerAlias: aliasB,
        linkId: 'L1');
    final huge = [for (var i = 0; i <= kMaxContenders; i++) 'c$i|l$i'];
    final fx = a.onProposeRecv(
        peerAlias: aliasB, proposal: W5Proposal(leaseId, 7, huge));
    expect(fx, isEmpty); // rejected, no ACK
  });

  // Asymmetric disconnect: a stale proposal cannot commit a replacement link.
  test('stale proposal does not commit a replacement link', () {
    final a = W5Ownership();
    a.onControl(
        handle: 'p1',
        role: W5Role.outbound,
        myCandidate: candA,
        peerCandidate: candB,
        peerAlias: aliasB,
        linkId: 'L1');
    commitAgainst(a, leaseId, ['cand-a|L1'], aliasB);
    expect(a.committedLinkId(leaseId), 'L1');
    a.onLinkDown(handle: 'p1');
    a.onControl(
        handle: 'p3',
        role: W5Role.outbound,
        myCandidate: candA,
        peerCandidate: candB,
        peerAlias: aliasB,
        linkId: 'L2');
    // Peer's stale proposal + ack name the OLD view → no commit of L2.
    a.onProposeRecv(
        peerAlias: aliasB, proposal: W5Proposal(leaseId, 7, ['cand-a|L1']));
    a.onAckRecv(peerAlias: aliasB, ack: W5Ack(leaseId, 1, 'cand-a|L1'));
    expect(a.isCommitted(leaseId), isFalse);
    // Once the peer catches up to L2, A commits L2.
    commitAgainst(a, leaseId, ['cand-a|L2'], aliasB);
    expect(a.committedLinkId(leaseId), 'L2');
  });

  // Restoration: replaying the committed link (same handle + linkId) is
  // idempotent — one keeper, no duplicate.
  test('restoration replay of the committed link is idempotent', () {
    final a = W5Ownership();
    a.onControl(
        handle: 'p1',
        role: W5Role.outbound,
        myCandidate: candA,
        peerCandidate: candB,
        peerAlias: aliasB,
        linkId: 'L1');
    commitAgainst(a, leaseId, ['cand-a|L1'], aliasB);
    final fx = a.onControl(
        handle: 'p1',
        role: W5Role.outbound,
        myCandidate: candA,
        peerCandidate: candB,
        peerAlias: aliasB,
        linkId: 'L1');
    expect(fx, [const W5Owns('p1')]);
    expect(a.committedKeeperCount, 1);
  });

  test('non-race converges + agrees', () {
    final s = _Sim();
    s.dial('A', 'Lab');
    s.linkUp('A', 'a1', W5Role.outbound, 'Lab');
    s.linkUp('B', 'b1', W5Role.inbound, 'Lab');
    s.flush();
    expect(s.a.committedLinkId(leaseId), 'Lab');
    expect(s.b.committedLinkId(leaseId), 'Lab');
  });

  test('timers never commit', () {
    final a = W5Ownership();
    a.onControl(
        handle: 'p1',
        role: W5Role.outbound,
        myCandidate: candA,
        peerCandidate: candB,
        peerAlias: aliasB,
        linkId: 'L1');
    for (var i = 0; i < 5; i++) {
      a.onRetryTimer(leaseId: leaseId);
    }
    expect(a.isCommitted(leaseId), isFalse);
  });

  test('loser inbound rejected at commit; winner outbound owned', () {
    final a = W5Ownership();
    a.onControl(
        handle: 'a1',
        role: W5Role.outbound,
        myCandidate: candA,
        peerCandidate: candB,
        peerAlias: aliasB,
        linkId: 'Lab');
    a.onControl(
        handle: 'a2',
        role: W5Role.inbound,
        myCandidate: candA,
        peerCandidate: candB,
        peerAlias: aliasB,
        linkId: 'Lba');
    final fx = <W5Effect>[];
    final mine = a.currentProposal(leaseId)!;
    fx.addAll(a.onProposeRecv(
        peerAlias: aliasB, proposal: W5Proposal(leaseId, 7, mine.contenders)));
    fx.addAll(a.onAckRecv(
        peerAlias: aliasB, ack: W5Ack(leaseId, mine.viewGen, mine.viewHash)));
    expect(fx.contains(const W5Owns('a1')), isTrue);
    expect(fx.contains(const W5RejectInbound('a2')), isTrue);
  });

  test('inbound-only peer stands down', () {
    final b = W5Ownership();
    b.onControl(
        handle: 'b1',
        role: W5Role.inbound,
        myCandidate: candB,
        peerCandidate: candA,
        peerAlias: aliasA,
        linkId: 'Lab');
    commitAgainst(b, leaseId, ['cand-a|Lab'], aliasA);
    expect(b.isCommitted(leaseId), isTrue);
    expect(
        b.onDiscovered(
            alias: aliasA, wouldDial: true, candidateId: candB, linkId: 'x'),
        isEmpty);
  });

  test('reconnect grace re-dials without wedging', () {
    final a = W5Ownership();
    a.onControl(
        handle: 'h1',
        role: W5Role.outbound,
        myCandidate: candA,
        peerCandidate: candB,
        peerAlias: 'pa',
        linkId: 'L1');
    commitAgainst(a, leaseId, ['cand-a|L1'], 'pa');
    a.onLinkDown(handle: 'h1');
    for (var i = 0; i < 2; i++) {
      expect(
          a.onDiscovered(
              alias: 'pa', wouldDial: true, candidateId: candA, linkId: 'r$i'),
          [W5Dial('r$i')]);
      a.onDialFailed(linkId: 'r$i');
    }
    a.onControl(
        handle: 'h2',
        role: W5Role.outbound,
        myCandidate: candA,
        peerCandidate: candB,
        peerAlias: 'pa',
        linkId: 'L2');
    commitAgainst(a, leaseId, ['cand-a|L2'], 'pa');
    expect(a.committedLinkId(leaseId), 'L2');
  });

  test('teardown and beacon off erase everything', () {
    final a = W5Ownership();
    a.onControl(
        handle: 'h',
        role: W5Role.outbound,
        myCandidate: candA,
        peerCandidate: candB,
        peerAlias: aliasB,
        linkId: 'L1');
    expect(a.onTeardown(leaseId: leaseId).last, const W5Ended(leaseId));
    expect(a.activeLeases, 0);
  });

  group('degenerate', () {
    test('unknown events are no-ops', () {
      final a = W5Ownership();
      expect(a.onLinkDown(handle: 'ghost'), isEmpty);
      expect(a.onTeardown(leaseId: 'ghost'), isEmpty);
      expect(a.onGraceExpiry(leaseId: 'ghost'), isEmpty);
      expect(a.onRetryTimer(leaseId: 'ghost'), isEmpty);
      expect(
          a.onProposeRecv(
              peerAlias: 'ghost', proposal: const W5Proposal('x', 0, [])),
          isEmpty);
      expect(a.onAckRecv(peerAlias: 'ghost', ack: const W5Ack('x', 0, '')),
          isEmpty);
    });
    test('provisional dial that never handshakes is erased', () {
      final a = W5Ownership();
      expect(
          a.onDiscovered(
              alias: aliasB, wouldDial: true, candidateId: candA, linkId: 'L1'),
          [const W5Dial('L1')]);
      expect(a.onDialFailed(linkId: 'L1'), [const W5Ended(candA)]);
      expect(a.activeLeases, 0);
    });
  });
}
