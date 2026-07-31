import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_range/features/beacon/w5_ownership.dart';

/// Two-peer acceptance tests for the #7 ownership oracle. candA < candB by
/// string order; the winning physical keeper is therefore always 'A->B' (its
/// central is A, the smaller candidate). leaseId == min == candA.
const candA = 'cand-a';
const candB = 'cand-b';
const aliasA = 'aliasA';
const aliasB = 'aliasB';
const leaseId = candA;

Iterable<List<int>> _perms(List<int> xs) sync* {
  if (xs.length <= 1) {
    yield List.of(xs);
    return;
  }
  for (var i = 0; i < xs.length; i++) {
    final rest = [...xs.sublist(0, i), ...xs.sublist(i + 1)];
    for (final p in _perms(rest)) {
      yield [xs[i], ...p];
    }
  }
}

/// Drives two endpoints and routes COMMIT messages between them.
class _Pair {
  final a = W5Ownership();
  final b = W5Ownership();

  void _route(List<W5Effect> fx, W5Ownership to, String fromAlias) {
    for (final (op, arg) in fx) {
      if (op == W5Op.commit) to.onCommitRecv(peerAlias: fromAlias, token: arg);
    }
  }

  void aControl(String h, W5Role role) => _route(
      a.onControl(
          handle: h,
          role: role,
          myCandidate: candA,
          peerCandidate: candB,
          peerAlias: aliasB),
      b,
      aliasA);

  void bControl(String h, W5Role role) => _route(
      b.onControl(
          handle: h,
          role: role,
          myCandidate: candB,
          peerCandidate: candA,
          peerAlias: aliasA),
      a,
      aliasB);

  /// Convergence-bound fallback fires on both endpoints.
  void finalize() {
    a.onConvergenceTimeout(leaseId: leaseId);
    b.onConvergenceTimeout(leaseId: leaseId);
  }
}

void main() {
  // Non-race: only A dials A->B. Both orderings converge, both agree on A->B.
  for (final perm in _perms([0, 1])) {
    test('two-peer non-race converges + agrees (order $perm)', () {
      final p = _Pair();
      final ops = <void Function()>[
        () => p.aControl('A->B', W5Role.outbound),
        () => p.bControl('A->B', W5Role.inbound),
      ];
      for (final i in perm) {
        ops[i]();
      }
      p.finalize();
      expect(p.a.committedKeeper(leaseId), 'A->B');
      expect(p.b.committedKeeper(leaseId), 'A->B');
      expect(p.a.committedKeeperCount, 1);
      expect(p.b.committedKeeperCount, 1);
    });
  }

  // Regression 1 — cross-device confirmation race. All 24 delivery orderings of
  // both role-reversed links must converge to the SAME physical keeper on BOTH
  // phones with exactly one committed keeper each.
  test('two-peer simultaneous open: all 24 orderings agree on one keeper', () {
    var count = 0;
    for (final perm in _perms([0, 1, 2, 3])) {
      final p = _Pair();
      final ops = <void Function()>[
        () => p.aControl('A->B', W5Role.outbound), // A dials B
        () => p.aControl('B->A', W5Role.inbound), // B dialed A (A's inbound)
        () => p.bControl('A->B', W5Role.inbound), // A dialed B (B's inbound)
        () => p.bControl('B->A', W5Role.outbound), // B dials A
      ];
      for (final i in perm) {
        ops[i]();
      }
      p.finalize();
      expect(p.a.committedKeeper(leaseId), 'A->B', reason: 'A perm $perm');
      expect(p.b.committedKeeper(leaseId), 'A->B', reason: 'B perm $perm');
      expect(p.a.committedKeeperCount, 1, reason: 'A perm $perm');
      expect(p.b.committedKeeperCount, 1, reason: 'B perm $perm');
      count++;
    }
    expect(count, 24);
  });

  // Regression 2 — a committed lease is never rekeyed by a replay carrying a
  // lower peer candidate.
  test('committed lease is stable under same-handle replay', () {
    final p = _Pair();
    p.aControl('A->B', W5Role.outbound);
    p.bControl('A->B', W5Role.inbound);
    p.finalize();
    expect(p.a.isCommitted(leaseId), isTrue);
    // Replay control on the keeper handle with a lower peer candidate.
    final fx = p.a.onControl(
        handle: 'A->B',
        role: W5Role.outbound,
        myCandidate: candA,
        peerCandidate: 'cand-0', // smaller than candA
        peerAlias: aliasB);
    expect(fx, [(W5Op.owns, 'A->B')]); // idempotent, NOT a rekey
    expect(p.a.committedKeeper(leaseId), 'A->B');
    expect(p.a.keeperOf('cand-0'), isNull); // never moved to cand-0
    expect(p.a.activeLeases, 1);
  });

  // Regression 3 — reconnect during grace can initiate through the real
  // discovery/dial path.
  test('reconnect during grace re-dials (does not stand down forever)', () {
    final p = _Pair();
    p.aControl('A->B', W5Role.outbound);
    p.bControl('A->B', W5Role.inbound);
    p.finalize();
    p.a.onLinkDown(handle: 'A->B'); // keeper lost → grace
    // Discovery during grace MUST dial, not stand down.
    final fx =
        p.a.onDiscovered(alias: aliasB, wouldDial: true, candidateId: candA);
    expect(fx, [(W5Op.dial, candA)]);
    // And a fresh handshake re-establishes.
    p.aControl('A->B2', W5Role.outbound);
    p.finalize();
    expect(p.a.committedKeeper(leaseId), 'A->B2');
  });

  // Loser links: a losing INBOUND is rejected (peer-central closes), a losing
  // OUTBOUND is closed by us.
  test('loser links produce role-correct close/reject effects', () {
    final a = W5Ownership();
    a.onControl(
        handle: 'A->B',
        role: W5Role.outbound,
        myCandidate: candA,
        peerCandidate: candB,
        peerAlias: aliasB);
    final fx = a.onControl(
        handle: 'B->A',
        role: W5Role.inbound, // loser (candB central) → rejectInbound
        myCandidate: candA,
        peerCandidate: candB,
        peerAlias: aliasB);
    expect(fx.contains((W5Op.rejectInbound, 'B->A')), isTrue);
    expect(a.keeperOf(leaseId), 'A->B');
  });

  // Inbound-only peer stands down after a token flip (the core #7 fix).
  test('inbound-only peer stands down (alias maps to the committed lease)', () {
    final b = W5Ownership();
    b.onControl(
        handle: 'A->B',
        role: W5Role.inbound,
        myCandidate: candB,
        peerCandidate: candA,
        peerAlias: aliasA);
    b.onConvergenceTimeout(leaseId: leaseId);
    expect(b.isCommitted(leaseId), isTrue);
    expect(b.onDiscovered(alias: aliasA, wouldDial: true, candidateId: candB),
        isEmpty);
  });

  // Multiple peers → one committed keeper each, never a global cap.
  test('two and three distinct peers each get one committed keeper', () {
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
      a.onConvergenceTimeout(leaseId: mine.compareTo(peer) <= 0 ? mine : peer);
    }
    expect(a.activeLeases, 3);
    expect(a.committedKeeperCount, 3);
  });

  // Alias rotation + bounded previous-alias expiry.
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
    expect(a.leaseForAlias(aliasB), leaseId); // previous kept
    a.onPrevAliasExpiry(leaseId: leaseId);
    expect(a.leaseForAlias(aliasB), isNull); // previous expired
    expect(a.leaseForAlias('aliasB2'), leaseId);
  });

  test('beacon off and teardown erase everything', () {
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

  group('degenerate inputs fail safely', () {
    test('unknown link-down / teardown / grace / commit are no-ops', () {
      final a = W5Ownership();
      expect(a.onLinkDown(handle: 'ghost'), isEmpty);
      expect(a.onTeardown(leaseId: 'ghost'), isEmpty);
      expect(a.onGraceExpiry(leaseId: 'ghost'), isEmpty);
      expect(a.onCommitRecv(peerAlias: 'ghost', token: 't'), isEmpty);
      a.onAliasRoll(leaseId: 'ghost', newAlias: 'z');
      a.onPrevAliasExpiry(leaseId: 'ghost');
    });
    test('dial that never handshakes is cleared', () {
      final a = W5Ownership();
      expect(a.onDiscovered(alias: aliasB, wouldDial: true, candidateId: candA),
          [(W5Op.dial, candA)]);
      expect(a.onDiscovered(alias: aliasB, wouldDial: true, candidateId: candA),
          isEmpty);
      expect(a.onDialFailed(candidateId: candA), [(W5Op.ended, candA)]);
      expect(a.onDiscovered(alias: aliasB, wouldDial: true, candidateId: candA),
          [(W5Op.dial, candA)]);
    });
  });

  // Property test: two peers, randomized delivery order of both links + their
  // commits, must ALWAYS converge to the same physical keeper with exactly one
  // committed keeper each (and never zero after convergence).
  test('property: two-peer randomized orderings agree + exactly one keeper',
      () {
    for (var seed = 0; seed < 300; seed++) {
      final rng = Random(seed);
      final p = _Pair();
      final ops = <void Function()>[
        () => p.aControl('A->B', W5Role.outbound),
        () => p.aControl('B->A', W5Role.inbound),
        () => p.bControl('A->B', W5Role.inbound),
        () => p.bControl('B->A', W5Role.outbound),
      ]..shuffle(rng);
      for (final o in ops) {
        o();
      }
      p.finalize();
      expect(p.a.committedKeeper(leaseId), 'A->B', reason: 'A seed $seed');
      expect(p.b.committedKeeper(leaseId), 'A->B', reason: 'B seed $seed');
      expect(p.a.committedKeeperCount, 1, reason: 'A seed $seed');
      expect(p.b.committedKeeperCount, 1, reason: 'B seed $seed');
    }
  });
}
