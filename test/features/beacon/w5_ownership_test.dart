import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_range/features/beacon/w5_ownership.dart';

/// Two-peer tests for the #7 ownership oracle (v5, wire-linkId contenders).
/// candA < candB. Physical links carry a shared wire linkId; local handles are
/// observer-local and are NEVER compared across endpoints — only linkIds are.
const candA = 'cand-a';
const candB = 'cand-b';
const aliasA = 'aliasA';
const aliasB = 'aliasB';
const leaseId = candA; // = min(candA, candB)

/// Two-endpoint message-queue simulator with drops/reordering. Also asserts the
/// safety guard that `owns` is never emitted before that endpoint has committed.
class _Sim {
  final a = W5Ownership();
  final b = W5Ownership();
  final List<Map<String, String>> q = [];

  void _collect(String from, List<W5Effect> fx) {
    final ep = from == 'A' ? a : b;
    final to = from == 'A' ? 'B' : 'A';
    final fromAlias = from == 'A' ? aliasA : aliasB;
    for (final (op, arg) in fx) {
      if (op == W5Op.owns && !ep.isCommitted(leaseId)) {
        fail('owns before commit on $from (handle $arg)');
      }
      if (op == W5Op.propose) {
        q.add({'to': to, 'fromAlias': fromAlias, 'set': arg});
      }
    }
  }

  void dial(String ep, String linkId) {
    if (ep == 'A') {
      a.onDiscovered(
          alias: aliasB, wouldDial: true, candidateId: candA, linkId: linkId);
    } else {
      b.onDiscovered(
          alias: aliasA, wouldDial: true, candidateId: candB, linkId: linkId);
    }
  }

  void linkUp(String ep, String handle, W5Role role, String linkId) {
    final o = ep == 'A' ? a : b;
    _collect(
        ep,
        o.onControl(
          handle: handle,
          role: role,
          myCandidate: ep == 'A' ? candA : candB,
          peerCandidate: ep == 'A' ? candB : candA,
          peerAlias: ep == 'A' ? aliasB : aliasA,
          linkId: linkId,
        ));
  }

  void deliver(int i) {
    final m = q.removeAt(i);
    final o = m['to'] == 'A' ? a : b;
    _collect(m['to']!,
        o.onProposeRecv(peerAlias: m['fromAlias']!, setStr: m['set']!));
  }

  void retry() {
    _collect('A', a.onRetryTimer(leaseId: leaseId));
    _collect('B', b.onRetryTimer(leaseId: leaseId));
  }

  void safety() {
    // Safety is agreement on the WIRE linkId, never a local handle.
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
            guard++ < 200) {
      while (q.isNotEmpty) {
        deliver(0);
        safety();
      }
      retry();
    }
  }
}

void main() {
  // Headline property: randomized interleaving of link-ups AND proposals with
  // drops/reordering → never two different committed WIRE linkIds (safety), and
  // after eventual delivery both commit the SAME linkId (liveness). Also (via
  // the harness) no `owns` is ever emitted before commit.
  test('property: safety on wire linkId + liveness (randomized schedules)', () {
    for (var seed = 0; seed < 500; seed++) {
      final rng = Random(seed);
      final s = _Sim();
      s.dial('A', 'Lab'); // A dials A->B (wire linkId Lab)
      s.dial('B', 'Lba'); // B dials B->A (wire linkId Lba)
      final linkUps = <void Function()>[
        () => s.linkUp('A', 'a1', W5Role.outbound, 'Lab'),
        () => s.linkUp('A', 'a2', W5Role.inbound, 'Lba'),
        () => s.linkUp('B', 'b1', W5Role.inbound, 'Lab'),
        () => s.linkUp('B', 'b2', W5Role.outbound, 'Lba'),
      ]..shuffle(rng);
      var li = 0;
      var steps = 0;
      while ((li < linkUps.length || s.q.isNotEmpty) && steps++ < 300) {
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
      // Liveness: both committed, agree on the wire linkId (the smaller
      // contender candA|Lab), each mapping it to its OWN local handle.
      expect(s.a.committedLinkId(leaseId), 'Lab', reason: 'A seed $seed');
      expect(s.b.committedLinkId(leaseId), 'Lab', reason: 'B seed $seed');
      expect(s.a.committedKeeper(leaseId), 'a1'); // A's local handle for Lab
      expect(s.b.committedKeeper(leaseId), 'b1'); // B's local handle for Lab
    }
  });

  // NEW regression 1: two same-direction (A-central) links, delivered in
  // OPPOSITE local order on each phone. They must agree on the same wire linkId
  // (never on a local handle).
  test('two same-direction duplicates agree on one wire linkId', () {
    final s = _Sim();
    s.dial('A', 'L1');
    s.dial('A', 'L2'); // A opens TWO outbound connections
    // A learns them in order a1(L1), a2(L2); B in OPPOSITE order b2(L2), b1(L1).
    s.linkUp('A', 'a1', W5Role.outbound, 'L1');
    s.linkUp('A', 'a2', W5Role.outbound, 'L2');
    s.linkUp('B', 'b2', W5Role.inbound, 'L2');
    s.linkUp('B', 'b1', W5Role.inbound, 'L1');
    s.flush();
    // Winner is min(candA|L1, candA|L2) = L1 — agreed by BOTH.
    expect(s.a.committedLinkId(leaseId), 'L1');
    expect(s.b.committedLinkId(leaseId), 'L1');
    // Each maps L1 to its own local handle.
    expect(s.a.committedKeeper(leaseId), 'a1');
    expect(s.b.committedKeeper(leaseId), 'b1');
  });

  // NEW regression 2: asymmetric disconnect + stale proposal. A replaces link L1
  // with L2 while B still holds L1. B's stale proposal {candA|L1} must NOT commit
  // A's replacement L2.
  test('stale proposal does not commit a replacement link', () {
    final a = W5Ownership();
    // Establish + commit L1 (peer proposes the same single-contender set).
    a.onControl(
        handle: 'a1',
        role: W5Role.outbound,
        myCandidate: candA,
        peerCandidate: candB,
        peerAlias: aliasB,
        linkId: 'L1');
    a.onProposeRecv(peerAlias: aliasB, setStr: 'cand-a|L1');
    expect(a.committedLinkId(leaseId), 'L1');
    // L1 drops; A establishes replacement L2.
    a.onLinkDown(handle: 'a1');
    a.onControl(
        handle: 'a3',
        role: W5Role.outbound,
        myCandidate: candA,
        peerCandidate: candB,
        peerAlias: aliasB,
        linkId: 'L2');
    // B is unaware; its retransmitted OLD proposal names L1.
    a.onProposeRecv(peerAlias: aliasB, setStr: 'cand-a|L1');
    // A must NOT commit L2 on the stale L1 proposal.
    expect(a.isCommitted(leaseId), isFalse);
    // Only once B catches up to L2 does A commit L2.
    a.onProposeRecv(peerAlias: aliasB, setStr: 'cand-a|L2');
    expect(a.committedLinkId(leaseId), 'L2');
  });

  test('non-race converges + agrees on wire linkId', () {
    final s = _Sim();
    s.dial('A', 'Lab');
    s.linkUp('A', 'a1', W5Role.outbound, 'Lab');
    s.linkUp('B', 'b1', W5Role.inbound, 'Lab');
    s.flush();
    expect(s.a.committedLinkId(leaseId), 'Lab');
    expect(s.b.committedLinkId(leaseId), 'Lab');
  });

  test('no commit without peer agreement (timers never commit)', () {
    final a = W5Ownership();
    a.onControl(
        handle: 'a1',
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

  test('partial views do not commit', () {
    final a = W5Ownership();
    a.onControl(
        handle: 'a1',
        role: W5Role.outbound,
        myCandidate: candA,
        peerCandidate: candB,
        peerAlias: aliasB,
        linkId: 'L1');
    // Peer proposes a DIFFERENT contender set → no commit.
    a.onProposeRecv(peerAlias: aliasB, setStr: 'cand-b|L9');
    expect(a.isCommitted(leaseId), isFalse);
  });

  // R2 — committed lease never rekeyed by replay.
  test('committed lease stable under same-link replay', () {
    final s = _Sim();
    s.dial('A', 'Lab');
    s.linkUp('A', 'a1', W5Role.outbound, 'Lab');
    s.linkUp('B', 'b1', W5Role.inbound, 'Lab');
    s.flush();
    expect(s.a.isCommitted(leaseId), isTrue);
    final fx = s.a.onControl(
        handle: 'a1',
        role: W5Role.outbound,
        myCandidate: candA,
        peerCandidate: 'cand-0',
        peerAlias: aliasB,
        linkId: 'Lab');
    expect(fx, [(W5Op.owns, 'a1')]);
    expect(s.a.activeLeases, 1);
  });

  // R3 — reconnect grace re-dials on BOTH candidate orderings, no wedge.
  for (final localSmaller in [true, false]) {
    test(
        'reconnect grace re-dials without wedging (localSmaller=$localSmaller)',
        () {
      final mine = localSmaller ? 'c1' : 'c9';
      final peer = localSmaller ? 'c9' : 'c1';
      final lease = mine.compareTo(peer) <= 0 ? mine : peer;
      final a = W5Ownership();
      a.onControl(
          handle: 'h1',
          role: W5Role.outbound,
          myCandidate: mine,
          peerCandidate: peer,
          peerAlias: 'pa',
          linkId: 'L1');
      a.onProposeRecv(peerAlias: 'pa', setStr: '$mine|L1');
      expect(a.isCommitted(lease), isTrue);
      a.onLinkDown(handle: 'h1');
      for (var i = 0; i < 2; i++) {
        final dial = a.onDiscovered(
            alias: 'pa', wouldDial: true, candidateId: mine, linkId: 'L$i');
        expect(dial, [(W5Op.dial, 'L$i')]);
        a.onDialFailed(linkId: 'L$i');
      }
      a.onControl(
          handle: 'h2',
          role: W5Role.outbound,
          myCandidate: mine,
          peerCandidate: peer,
          peerAlias: 'pa',
          linkId: 'L2');
      a.onProposeRecv(peerAlias: 'pa', setStr: '$mine|L2');
      expect(a.committedLinkId(lease), 'L2');
    });
  }

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
    final fx =
        a.onProposeRecv(peerAlias: aliasB, setStr: 'cand-a|Lab,cand-b|Lba');
    expect(fx.contains((W5Op.owns, 'a1')), isTrue);
    expect(fx.contains((W5Op.rejectInbound, 'a2')), isTrue);
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
    b.onProposeRecv(peerAlias: aliasA, setStr: 'cand-a|Lab');
    expect(b.isCommitted(leaseId), isTrue);
    expect(
        b.onDiscovered(
            alias: aliasA, wouldDial: true, candidateId: candB, linkId: 'x'),
        isEmpty);
  });

  test('three peers each get one committed keeper', () {
    final a = W5Ownership();
    for (final (h, mine, peer, al, lid) in [
      ('hb', 'ca', 'zb', 'ab', 'lb'),
      ('hc', 'cc', 'zc', 'ac', 'lc'),
      ('hd', 'cd', 'zd', 'ad', 'ld'),
    ]) {
      a.onControl(
          handle: h,
          role: W5Role.outbound,
          myCandidate: mine,
          peerCandidate: peer,
          peerAlias: al,
          linkId: lid);
      a.onProposeRecv(peerAlias: al, setStr: '$mine|$lid');
    }
    expect(a.committedKeeperCount, 3);
  });

  test('alias rollover keeps current+previous, then expires previous', () {
    final a = W5Ownership();
    a.onControl(
        handle: 'h',
        role: W5Role.outbound,
        myCandidate: candA,
        peerCandidate: candB,
        peerAlias: aliasB,
        linkId: 'L1');
    a.onAliasRoll(leaseId: leaseId, newAlias: 'aliasB2');
    expect(a.leaseForAlias('aliasB2'), leaseId);
    expect(a.leaseForAlias(aliasB), leaseId);
    a.onPrevAliasExpiry(leaseId: leaseId);
    expect(a.leaseForAlias(aliasB), isNull);
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
    expect(a.onTeardown(leaseId: leaseId).last, (W5Op.ended, leaseId));
    expect(a.activeLeases, 0);
  });

  group('degenerate', () {
    test('unknown events are no-ops', () {
      final a = W5Ownership();
      expect(a.onLinkDown(handle: 'ghost'), isEmpty);
      expect(a.onTeardown(leaseId: 'ghost'), isEmpty);
      expect(a.onGraceExpiry(leaseId: 'ghost'), isEmpty);
      expect(a.onProposeRecv(peerAlias: 'ghost', setStr: 'x'), isEmpty);
      expect(a.onRetryTimer(leaseId: 'ghost'), isEmpty);
    });
    test('provisional dial that never handshakes is erased', () {
      final a = W5Ownership();
      expect(
          a.onDiscovered(
              alias: aliasB, wouldDial: true, candidateId: candA, linkId: 'L1'),
          [(W5Op.dial, 'L1')]);
      expect(a.onDialFailed(linkId: 'L1'), [(W5Op.ended, candA)]);
      expect(a.activeLeases, 0);
    });
  });
}
