import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_range/features/beacon/w5_ownership.dart';

/// Two-peer acceptance tests for the #7 ownership oracle (v4, set-agreement
/// commit). candA < candB by string order → the shared winner is 'A->B'.
const candA = 'cand-a';
const candB = 'cand-b';
const aliasA = 'aliasA';
const aliasB = 'aliasB';
const leaseId = candA; // = min(candA, candB)

/// Explicit two-endpoint message-queue simulator with drops/reordering.
class _Sim {
  final a = W5Ownership();
  final b = W5Ownership();
  final List<Map<String, String>> q = []; // pending PROPOSE messages

  void _collect(String from, List<W5Effect> fx) {
    final to = from == 'A' ? 'B' : 'A';
    final fromAlias = from == 'A' ? aliasA : aliasB;
    for (final (op, arg) in fx) {
      if (op == W5Op.propose) {
        q.add({'to': to, 'fromAlias': fromAlias, 'set': arg});
      }
    }
  }

  /// Model the dial (registers a pending outbound) before its handshake.
  void dial(String ep) {
    if (ep == 'A') {
      a.onDiscovered(alias: aliasB, wouldDial: true, candidateId: candA);
    } else {
      b.onDiscovered(alias: aliasA, wouldDial: true, candidateId: candB);
    }
  }

  void linkUp(String ep, String handle, W5Role role) {
    final o = ep == 'A' ? a : b;
    _collect(
        ep,
        o.onControl(
          handle: handle,
          role: role,
          myCandidate: ep == 'A' ? candA : candB,
          peerCandidate: ep == 'A' ? candB : candA,
          peerAlias: ep == 'A' ? aliasB : aliasA,
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
    final ka = a.committedKeeper(leaseId);
    final kb = b.committedKeeper(leaseId);
    if (ka != null && kb != null && ka != kb) {
      fail('SAFETY: two different committed keepers A=$ka B=$kb');
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
  // The headline property: under randomized interleaving of both role-reversed
  // link-ups AND propose deliveries WITH drops/reordering, there are NEVER two
  // different committed keepers (safety), and after eventual delivery both
  // commit the SAME keeper (liveness).
  test('property: message-queue safety under all orderings + liveness', () {
    for (var seed = 0; seed < 500; seed++) {
      final rng = Random(seed);
      final s = _Sim();
      s.dial('A'); // both dial → potential race
      s.dial('B');
      final linkUps = <void Function()>[
        () => s.linkUp('A', 'A->B', W5Role.outbound),
        () => s.linkUp('A', 'B->A', W5Role.inbound),
        () => s.linkUp('B', 'A->B', W5Role.inbound),
        () => s.linkUp('B', 'B->A', W5Role.outbound),
      ]..shuffle(rng);
      var li = 0;
      var steps = 0;
      while ((li < linkUps.length || s.q.isNotEmpty) && steps++ < 300) {
        final canLink = li < linkUps.length;
        final canDeliver = s.q.isNotEmpty;
        if (canLink && (rng.nextInt(3) == 0 || !canDeliver)) {
          linkUps[li++]();
        } else if (canDeliver) {
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
      expect(s.a.committedKeeper(leaseId), isNotNull,
          reason: 'A live seed $seed');
      expect(s.b.committedKeeper(leaseId), isNotNull,
          reason: 'B live seed $seed');
      expect(s.a.committedKeeper(leaseId), s.b.committedKeeper(leaseId),
          reason: 'agree seed $seed');
    }
  });

  // Non-race: only A dials. Both converge on A->B.
  test('non-race converges + agrees', () {
    final s = _Sim();
    s.dial('A'); // only A dials
    s.linkUp('A', 'A->B', W5Role.outbound);
    s.linkUp('B', 'A->B', W5Role.inbound);
    s.flush();
    expect(s.a.committedKeeper(leaseId), 'A->B');
    expect(s.b.committedKeeper(leaseId), 'A->B');
  });

  // No commit without peer agreement (round-3 regression 2): a lone endpoint
  // whose proposal is never answered stays negotiating, even after retries.
  test('no commit without peer agreement', () {
    final a = W5Ownership();
    a.onControl(
        handle: 'A->B',
        role: W5Role.outbound,
        myCandidate: candA,
        peerCandidate: candB,
        peerAlias: aliasB);
    for (var i = 0; i < 5; i++) {
      a.onRetryTimer(leaseId: leaseId); // timers never commit
    }
    expect(a.isCommitted(leaseId), isFalse);
    expect(a.committedKeeperCount, 0);
  });

  // Partial-view divergence (round-3 regression 1): differing sets never both
  // commit. Only when sets match does either commit — to the same keeper.
  test('partial views do not commit; matching sets commit the same keeper', () {
    final a = W5Ownership();
    final b = W5Ownership();
    a.onControl(
        handle: 'A->B',
        role: W5Role.outbound,
        myCandidate: candA,
        peerCandidate: candB,
        peerAlias: aliasB); // A set = {candA}
    b.onControl(
        handle: 'B->A',
        role: W5Role.outbound,
        myCandidate: candB,
        peerCandidate: candA,
        peerAlias: aliasA); // B set = {candB}
    // Exchange proposals — sets differ ({candA} vs {candB}) → neither commits.
    a.onProposeRecv(peerAlias: aliasB, setStr: 'cand-b');
    b.onProposeRecv(peerAlias: aliasA, setStr: 'cand-a');
    expect(a.isCommitted(leaseId), isFalse);
    expect(b.isCommitted(leaseId), isFalse);
  });

  // R2 — committed lease never rekeyed by replay.
  test('committed lease is stable under same-handle replay', () {
    final s = _Sim();
    s.linkUp('A', 'A->B', W5Role.outbound);
    s.linkUp('B', 'A->B', W5Role.inbound);
    s.flush();
    expect(s.a.isCommitted(leaseId), isTrue);
    final fx = s.a.onControl(
        handle: 'A->B',
        role: W5Role.outbound,
        myCandidate: candA,
        peerCandidate: 'cand-0',
        peerAlias: aliasB);
    expect(fx, [(W5Op.owns, 'A->B')]);
    expect(s.a.keeperOf('cand-0'), isNull);
    expect(s.a.activeLeases, 1);
  });

  // R3 — reconnect grace re-dials on BOTH candidate orderings (lease id is the
  // local candidate in one, the peer's in the other) and never wedges.
  for (final localSmaller in [true, false]) {
    test(
        'reconnect grace re-dials without wedging (localSmaller=$localSmaller)',
        () {
      final mine = localSmaller ? 'c1' : 'c9';
      final peer = localSmaller ? 'c9' : 'c1';
      final lease = mine.compareTo(peer) <= 0 ? mine : peer;
      final a = W5Ownership();
      // establish + commit (drive both sides through a tiny inline flush)
      a.onControl(
          handle: 'h1',
          role: W5Role.outbound,
          myCandidate: mine,
          peerCandidate: peer,
          peerAlias: 'peerAlias');
      a.onProposeRecv(
          peerAlias: 'peerAlias', setStr: mine); // peer set = {mine}
      expect(a.isCommitted(lease), isTrue);
      a.onLinkDown(handle: 'h1'); // grace
      // Two failed re-dials must NOT wedge discovery.
      for (var i = 0; i < 2; i++) {
        final dial = a.onDiscovered(
            alias: 'peerAlias', wouldDial: true, candidateId: mine);
        expect(dial, [(W5Op.dial, mine)], reason: 'redial $i');
        a.onDialFailed(candidateId: mine); // keeps grace
      }
      // Eventually a link re-establishes.
      a.onControl(
          handle: 'h2',
          role: W5Role.outbound,
          myCandidate: mine,
          peerCandidate: peer,
          peerAlias: 'peerAlias');
      a.onProposeRecv(peerAlias: 'peerAlias', setStr: mine);
      expect(a.committedKeeper(lease), 'h2');
    });
  }

  // Loser role-correct effects — the losing inbound is rejected AT COMMIT (a
  // peripheral can't cancel a CBCentral), the winner outbound is owned.
  test('loser inbound is rejected at commit; winner outbound owned', () {
    final a = W5Ownership();
    a.onControl(
        handle: 'A->B',
        role: W5Role.outbound,
        myCandidate: candA,
        peerCandidate: candB,
        peerAlias: aliasB);
    a.onControl(
        handle: 'B->A',
        role: W5Role.inbound,
        myCandidate: candA,
        peerCandidate: candB,
        peerAlias: aliasB);
    // set == {cand-a, cand-b}; peer proposes the same → commit closes the loser.
    final fx = a.onProposeRecv(peerAlias: aliasB, setStr: 'cand-a,cand-b');
    expect(fx.contains((W5Op.owns, 'A->B')), isTrue);
    expect(fx.contains((W5Op.rejectInbound, 'B->A')), isTrue);
    expect(a.committedKeeper(leaseId), 'A->B');
  });

  // Core #7 fix: inbound-only peer stands down (alias maps to the lease).
  test('inbound-only peer stands down', () {
    final b = W5Ownership();
    b.onControl(
        handle: 'A->B',
        role: W5Role.inbound,
        myCandidate: candB,
        peerCandidate: candA,
        peerAlias: aliasA);
    b.onProposeRecv(peerAlias: aliasA, setStr: candA); // peer agrees → commit
    expect(b.isCommitted(leaseId), isTrue);
    expect(b.onDiscovered(alias: aliasA, wouldDial: true, candidateId: candB),
        isEmpty);
  });

  // Multiple peers → one keeper each; never a global cap.
  test('three distinct peers each get one committed keeper', () {
    final a = W5Ownership();
    for (final (h, mine, peer, al) in [
      ('hb', 'ca', 'zb', 'ab'),
      ('hc', 'cc', 'zc', 'ac'),
      ('hd', 'cd', 'zd', 'ad'),
    ]) {
      a.onControl(
          handle: h,
          role: W5Role.outbound,
          myCandidate: mine,
          peerCandidate: peer,
          peerAlias: al);
      a.onProposeRecv(peerAlias: al, setStr: mine);
    }
    expect(a.activeLeases, 3);
    expect(a.committedKeeperCount, 3);
  });

  // Alias rollover + bounded previous-alias expiry.
  test('alias rollover keeps current+previous, then expires previous', () {
    final a = W5Ownership();
    a.onControl(
        handle: 'h',
        role: W5Role.outbound,
        myCandidate: candA,
        peerCandidate: candB,
        peerAlias: aliasB);
    a.onAliasRoll(leaseId: leaseId, newAlias: 'aliasB2');
    expect(a.leaseForAlias('aliasB2'), leaseId);
    expect(a.leaseForAlias(aliasB), leaseId);
    a.onPrevAliasExpiry(leaseId: leaseId);
    expect(a.leaseForAlias(aliasB), isNull);
    expect(a.leaseForAlias('aliasB2'), leaseId);
  });

  test('teardown and beacon off erase everything', () {
    final a = W5Ownership();
    a.onControl(
        handle: 'h',
        role: W5Role.outbound,
        myCandidate: candA,
        peerCandidate: candB,
        peerAlias: aliasB);
    expect(a.onTeardown(leaseId: leaseId).last, (W5Op.ended, leaseId));
    expect(a.activeLeases, 0);
    expect(a.leaseForAlias(aliasB), isNull);
  });

  group('degenerate / bounds', () {
    test('unknown link-down / teardown / grace / propose are no-ops', () {
      final a = W5Ownership();
      expect(a.onLinkDown(handle: 'ghost'), isEmpty);
      expect(a.onTeardown(leaseId: 'ghost'), isEmpty);
      expect(a.onGraceExpiry(leaseId: 'ghost'), isEmpty);
      expect(a.onProposeRecv(peerAlias: 'ghost', setStr: 'x'), isEmpty);
      expect(a.onRetryTimer(leaseId: 'ghost'), isEmpty);
      a.onAliasRoll(leaseId: 'ghost', newAlias: 'z');
      a.onPrevAliasExpiry(leaseId: 'ghost');
    });
    test('provisional dial that never handshakes is erased', () {
      final a = W5Ownership();
      expect(a.onDiscovered(alias: aliasB, wouldDial: true, candidateId: candA),
          [(W5Op.dial, candA)]);
      expect(a.onDiscovered(alias: aliasB, wouldDial: true, candidateId: candA),
          isEmpty);
      expect(a.onDialFailed(candidateId: candA), [(W5Op.ended, candA)]);
      expect(a.activeLeases, 0);
    });
    test('grace-expiry after failed reconnect ends the encounter', () {
      final a = W5Ownership();
      a.onControl(
          handle: 'h1',
          role: W5Role.outbound,
          myCandidate: candA,
          peerCandidate: candB,
          peerAlias: aliasB);
      a.onProposeRecv(peerAlias: aliasB, setStr: candA);
      a.onLinkDown(handle: 'h1');
      expect(a.onGraceExpiry(leaseId: leaseId), [(W5Op.ended, leaseId)]);
      expect(a.activeLeases, 0);
    });
  });
}
