import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_range/features/beacon/w5_ownership.dart';

/// Two-peer tests for the #7 ownership oracle (v5.2: peer-gen tracking, endpoint-
/// global bijection, local cap, injective contenders, effect routing). candA <
/// candB. Local CB handles are observer-local — only wire linkIds are compared.
const candA = 'cand-a';
const candB = 'cand-b';
const aliasA = 'aliasA';
const aliasB = 'aliasB';
const leaseId = candA;

W5Contender ct(String central, String link) => W5Contender(central, link);

/// Two-endpoint message queue routing PROPOSE + ACK (routes ignored for
/// delivery; source identity is exercised by the direct-call violation tests).
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

void commitAgainst(
    W5Ownership a, String lease, List<W5Contender> peerSet, String peerAlias) {
  final mine = a.currentProposal(lease)!;
  a.onProposeRecv(
      peerAlias: peerAlias, proposal: W5Proposal(lease, 7, peerSet));
  a.onAckRecv(
      peerAlias: peerAlias, ack: W5Ack(lease, mine.viewGen, mine.viewHash));
}

void main() {
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
            s.q.removeAt(rng.nextInt(s.q.length));
          } else {
            s.deliver(rng.nextInt(s.q.length));
          }
        }
        s.safety();
      }
      s.flush();
      s.safety();
      expect(s.a.committedLinkId(leaseId), 'Lab', reason: 'A seed $seed');
      expect(s.b.committedLinkId(leaseId), 'Lab', reason: 'B seed $seed');
    }
  });

  W5Ownership established(String linkId) {
    final a = W5Ownership();
    a.onControl(
        handle: 'p1',
        role: W5Role.outbound,
        myCandidate: candA,
        peerCandidate: candB,
        peerAlias: aliasB,
        linkId: linkId);
    return a;
  }

  // v5.2 #1 — older peer generation is NOT accepted/ACKed.
  test('older peer generation is rejected (no ACK, no state change)', () {
    final a = established('L1');
    a.onProposeRecv(
        peerAlias: aliasB,
        proposal: W5Proposal(leaseId, 8, [ct('cand-a', 'L1')]));
    final fx = a.onProposeRecv(
        peerAlias: aliasB,
        proposal: W5Proposal(leaseId, 7, [ct('cand-a', 'L1')]));
    expect(fx, isEmpty); // gen 7 < accepted gen 8 → dropped, no ACK
  });

  // v5.2 #2 — same-gen conflicting payload does NOT poison the accepted view.
  test('same-gen conflicting payload is failed closed, not overwritten', () {
    final a = established('L1');
    // Accept a valid matching proposal at gen 8.
    a.onProposeRecv(
        peerAlias: aliasB,
        proposal: W5Proposal(leaseId, 8, [ct('cand-a', 'L1')]));
    // Conflicting payload at the SAME gen 8, tagged with a source link.
    final fx = a.onProposeRecv(
        peerAlias: aliasB,
        proposal: W5Proposal(leaseId, 8, [ct('cand-z', 'L9')]),
        sourceHandle: 'p1',
        sourceRole: W5Role.outbound);
    expect(
        fx, [const W5CloseOutbound('p1')]); // fail closed, not silent overwrite
    // The valid view survived → the peer's ACK still commits.
    final mine = a.currentProposal(leaseId)!;
    a.onAckRecv(
        peerAlias: aliasB, ack: W5Ack(leaseId, mine.viewGen, mine.viewHash));
    expect(a.committedLinkId(leaseId), 'L1');
  });

  // v5.2 #3 — endpoint-global bijection: a live handle cannot be rebound into a
  // second encounter.
  test('a live handle is not rebound into a second encounter', () {
    final a = established('L1');
    commitAgainst(a, leaseId, [ct('cand-a', 'L1')], aliasB);
    // Deliver control for a DIFFERENT encounter (different alias/candidate) on
    // the same still-live handle p1.
    final fx = a.onControl(
        handle: 'p1',
        role: W5Role.outbound,
        myCandidate: 'cand-x',
        peerCandidate: 'cand-y',
        peerAlias: 'otherAlias',
        linkId: 'L9');
    expect(fx, [const W5CloseOutbound('p1')]); // fail closed
    expect(a.activeLeases, 1); // no second encounter created
    expect(a.committedKeeper(leaseId), 'p1'); // original binding intact
  });

  // v5.2 #3b — a live linkId cannot be replayed into a second encounter.
  test('a live linkId is not accepted in a second encounter', () {
    final a = established('L1');
    final fx = a.onControl(
        handle: 'p9',
        role: W5Role.outbound,
        myCandidate: 'cand-x',
        peerCandidate: 'cand-y',
        peerAlias: 'otherAlias',
        linkId: 'L1'); // linkId already live in encounter candA
    expect(fx, [const W5CloseOutbound('p9')]);
    expect(a.activeLeases, 1);
  });

  // v5.2 #4 — local contenders cannot exceed the cap.
  test('local contenders are capped', () {
    final a = W5Ownership();
    // Fill to the cap with distinct outbound links.
    for (var i = 0; i < kMaxContenders; i++) {
      a.onControl(
          handle: 'h$i',
          role: W5Role.inbound,
          myCandidate: candA,
          peerCandidate: candB,
          peerAlias: aliasB,
          linkId: 'L$i');
    }
    // One more must be refused.
    final fx = a.onControl(
        handle: 'hx',
        role: W5Role.inbound,
        myCandidate: candA,
        peerCandidate: candB,
        peerAlias: aliasB,
        linkId: 'Lx');
    expect(fx, [const W5RejectInbound('hx')]);
    expect(a.currentProposal(leaseId)!.contenders.length, kMaxContenders);
  });

  // v5.2 #5 — out-of-range (negative / > u32) proposal generation is rejected.
  test('out-of-u32-range proposal generation is rejected', () {
    final a = established('L1');
    expect(
        a.onProposeRecv(
            peerAlias: aliasB,
            proposal: W5Proposal(leaseId, -1, [ct('cand-a', 'L1')]),
            sourceHandle: 'p1',
            sourceRole: W5Role.outbound),
        [const W5CloseOutbound('p1')]);
    expect(
        a.onProposeRecv(
            peerAlias: aliasB,
            proposal: W5Proposal(leaseId, kU32Max + 1, [ct('cand-a', 'L1')]),
            sourceHandle: 'p1',
            sourceRole: W5Role.outbound),
        [const W5CloseOutbound('p1')]);
    // Injective encoding: these two DIFFERENT contender sets are not equal.
    expect(
        W5Proposal(leaseId, 1, [ct('aa|bb', 'cc')]) ==
            W5Proposal(leaseId, 1, [ct('aa', 'bb|cc')]),
        isFalse);
  });

  // v5.2 #6 — a proposal carrying too many contenders (over cap) fails the
  // source link closed.
  test('over-cap proposal fails the source link closed', () {
    final a = established('L1');
    final huge = [for (var i = 0; i <= kMaxContenders; i++) ct('c$i', 'l$i')];
    final fx = a.onProposeRecv(
        peerAlias: aliasB,
        proposal: W5Proposal(leaseId, 7, huge),
        sourceHandle: 'p1',
        sourceRole: W5Role.outbound);
    expect(fx, [const W5CloseOutbound('p1')]);
  });

  // Bijection within-encounter (v5.1 regressions retained).
  test('same linkId on a second handle does not re-own', () {
    final a = established('L1');
    commitAgainst(a, leaseId, [ct('cand-a', 'L1')], aliasB);
    final fx = a.onControl(
        handle: 'p2',
        role: W5Role.outbound,
        myCandidate: candA,
        peerCandidate: candB,
        peerAlias: aliasB,
        linkId: 'L1');
    expect(fx, [const W5CloseOutbound('p2')]);
    expect(a.committedKeeper(leaseId), 'p1');
  });

  // Two-phase + wire linkId agreement.
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
  });

  test('no commit until the peer ACKs our current view', () {
    final a = established('L1');
    a.onProposeRecv(
        peerAlias: aliasB,
        proposal: W5Proposal(leaseId, 7, [ct('cand-a', 'L1')]));
    expect(a.isCommitted(leaseId), isFalse);
    final mine = a.currentProposal(leaseId)!;
    a.onAckRecv(
        peerAlias: aliasB, ack: W5Ack(leaseId, mine.viewGen, mine.viewHash));
    expect(a.committedLinkId(leaseId), 'L1');
  });

  test('stale proposal does not commit a replacement link', () {
    final a = established('L1');
    // Commit L1 (peer view gen 10).
    final m1 = a.currentProposal(leaseId)!;
    a.onProposeRecv(
        peerAlias: aliasB,
        proposal: W5Proposal(leaseId, 10, [ct('cand-a', 'L1')]));
    a.onAckRecv(
        peerAlias: aliasB, ack: W5Ack(leaseId, m1.viewGen, m1.viewHash));
    expect(a.committedLinkId(leaseId), 'L1');
    // L1 drops; A establishes replacement L2.
    a.onLinkDown(handle: 'p1');
    a.onControl(
        handle: 'p3',
        role: W5Role.outbound,
        myCandidate: candA,
        peerCandidate: candB,
        peerAlias: aliasB,
        linkId: 'L2');
    // B (unaware) retransmits its old committed-view proposal (gen 10, L1) →
    // idempotent, and a stale ACK → neither commits the L2 replacement.
    a.onProposeRecv(
        peerAlias: aliasB,
        proposal: W5Proposal(leaseId, 10, [ct('cand-a', 'L1')]));
    a.onAckRecv(peerAlias: aliasB, ack: W5Ack(leaseId, 5, 'stale'));
    expect(a.isCommitted(leaseId), isFalse);
    // B catches up to L2 at a newer generation → A commits L2.
    final m2 = a.currentProposal(leaseId)!;
    a.onProposeRecv(
        peerAlias: aliasB,
        proposal: W5Proposal(leaseId, 11, [ct('cand-a', 'L2')]));
    a.onAckRecv(
        peerAlias: aliasB, ack: W5Ack(leaseId, m2.viewGen, m2.viewHash));
    expect(a.committedLinkId(leaseId), 'L2');
  });

  test('restoration replay of the committed link is idempotent', () {
    final a = established('L1');
    commitAgainst(a, leaseId, [ct('cand-a', 'L1')], aliasB);
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

  // Two independent peers → one keeper each (endpoint-global, no cross-binding).
  test('two independent peers each get one committed keeper', () {
    final a = W5Ownership();
    a.onControl(
        handle: 'hb',
        role: W5Role.outbound,
        myCandidate: 'ca',
        peerCandidate: 'zb',
        peerAlias: 'ab',
        linkId: 'lb');
    commitAgainst(a, 'ca', [ct('ca', 'lb')], 'ab');
    a.onControl(
        handle: 'hc',
        role: W5Role.outbound,
        myCandidate: 'cc',
        peerCandidate: 'zc',
        peerAlias: 'ac',
        linkId: 'lc');
    commitAgainst(a, 'cc', [ct('cc', 'lc')], 'ac');
    expect(a.committedKeeperCount, 2);
  });

  test('alias rollover keeps current+previous, then expires previous', () {
    final a = established('L1');
    a.onAliasRoll(leaseId: leaseId, newAlias: 'aliasB2');
    expect(a.leaseForAlias('aliasB2'), leaseId);
    expect(a.leaseForAlias(aliasB), leaseId);
    a.onPrevAliasExpiry(leaseId: leaseId);
    expect(a.leaseForAlias(aliasB), isNull);
  });

  test('teardown and beacon off erase everything', () {
    final a = established('L1');
    expect(a.onTeardown(leaseId: leaseId).last, const W5Ended(leaseId));
    expect(a.activeLeases, 0);
  });

  group('degenerate', () {
    test('unknown events are no-ops', () {
      final a = W5Ownership();
      expect(a.onLinkDown(handle: 'ghost'), isEmpty);
      expect(a.onTeardown(leaseId: 'ghost'), isEmpty);
      expect(a.onRetryTimer(leaseId: 'ghost'), isEmpty);
      expect(
          a.onProposeRecv(
              peerAlias: 'ghost', proposal: const W5Proposal('x', 0, [])),
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
