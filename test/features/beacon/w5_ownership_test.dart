import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_range/features/beacon/w5_ownership.dart';

/// Acceptance tests for the #7 encounter-lease ownership oracle (corrected per
/// PR #9 review). candA < candB by string order throughout. Scenarios 11-14
/// (diagnostic isolation) are build-level (#8), not this unit surface.
void main() {
  const candA = 'cand-a';
  const candB = 'cand-b';
  const aliasA = 'aliasA';
  const aliasB = 'aliasB';
  // Lease id at establishment == min(candidate) == candA (see per-test asserts).

  // Decisive case: the initial dialer is chosen by TOKEN order, which can be
  // opposite to candidate order. leaseId is min(candidate) regardless of dialer.
  test('dialer chosen by token order; lease anchored to min(candidate)', () {
    // A dials B (token order) even though B holds the smaller candidate.
    final a = W5Ownership();
    // Here A's own candidate is the LARGER one (candB), peer's is smaller.
    final dial = a.onDiscovered(
        alias: aliasB, wouldDial: true, candidateId: candB);
    expect(dial, [(W5Op.dial, candB)]);
    final up = a.onControl(
        handle: 'A->B', role: W5Role.outbound,
        myCandidate: candB, peerCandidate: candA, peerAlias: aliasB);
    expect(up, [(W5Op.owns, 'A->B')]);
    // Lease is anchored to the smaller candidate (candA), not the dialer's.
    expect(a.keeperOf(candA), 'A->B');
    expect(a.confirmedKeeperCount, 1);
  });

  // Scenario 2 (core fix): inbound-only peer does not dial after a token flip.
  test('inbound-only peer stands down after ordering reverses', () {
    final b = W5Ownership();
    // B receives an inbound link from A (A dialed B).
    b.onControl(
        handle: 'A->B', role: W5Role.inbound,
        myCandidate: candB, peerCandidate: candA, peerAlias: aliasA);
    expect(b.confirmedKeeperCount, 1);
    b.onConfirmed(handle: 'A->B');
    // A token flip would make B "want" to dial — but aliasA maps to the lease.
    final fx = b.onDiscovered(alias: aliasA, wouldDial: true, candidateId: candB);
    expect(fx, isEmpty);
    expect(b.confirmedKeeperCount, 1);
  });

  // Discovery before any peer control data is known → dial (not stand down).
  test('discovery of an unknown peer dials', () {
    final a = W5Ownership();
    expect(a.onDiscovered(alias: 'newpeer', wouldDial: true, candidateId: candA),
        [(W5Op.dial, candA)]);
  });

  // Simultaneous open: both role-reversed links converge to ONE keeper on each
  // phone (the smaller link-candidate wins), regardless of event order.
  for (final order in ['out-first', 'in-first']) {
    test('simultaneous open converges to one keeper ($order)', () {
      // A side: keeps its outbound A->B (candA is smaller).
      final a = W5Ownership();
      void aOut() => a.onControl(
          handle: 'A->B', role: W5Role.outbound,
          myCandidate: candA, peerCandidate: candB, peerAlias: aliasB);
      void aIn() => a.onControl(
          handle: 'B->A', role: W5Role.inbound,
          myCandidate: candA, peerCandidate: candB, peerAlias: aliasB);
      if (order == 'out-first') {
        aOut();
        aIn();
      } else {
        aIn();
        aOut();
      }
      expect(a.confirmedKeeperCount, 1);
      expect(a.keeperOf(candA), 'A->B'); // the smaller-candidate link kept

      // B side keeps the SAME physical link (A->B, inbound on B).
      final b = W5Ownership();
      void bOut() => b.onControl(
          handle: 'B->A', role: W5Role.outbound,
          myCandidate: candB, peerCandidate: candA, peerAlias: aliasA);
      void bIn() => b.onControl(
          handle: 'A->B', role: W5Role.inbound,
          myCandidate: candB, peerCandidate: candA, peerAlias: aliasA);
      if (order == 'out-first') {
        bOut();
        bIn();
      } else {
        bIn();
        bOut();
      }
      expect(b.confirmedKeeperCount, 1);
      expect(b.keeperOf(candA), 'A->B');
    });
  }

  // A healthy keeper survives token rotations and lower-valued duplicate
  // candidates (sticky).
  test('confirmed keeper is not displaced by rotation or a smaller candidate',
      () {
    final a = W5Ownership();
    a.onControl(
        handle: 'A->B', role: W5Role.outbound,
        myCandidate: candA, peerCandidate: candB, peerAlias: aliasB);
    a.onConfirmed(handle: 'A->B');
    // Peer rotates its token in-band.
    a.onAliasRoll(leaseId: candA, newAlias: 'aliasB2');
    // A later inbound link arrives with a SMALLER candidate — must be closed,
    // never adopted, because the keeper is confirmed.
    final fx = a.onControl(
        handle: 'late', role: W5Role.inbound,
        myCandidate: candA, peerCandidate: 'cand-0', peerAlias: 'aliasB2');
    expect(fx, [(W5Op.close, 'late')]);
    expect(a.keeperOf(candA), 'A->B');
    expect(a.confirmedKeeperCount, 1);
    // A discovery under EITHER the new or previous alias maps to the lease.
    expect(a.leaseForAlias('aliasB2'), candA);
    expect(a.leaseForAlias(aliasB), candA); // previous kept during grace
  });

  // Identifier churn on either role → no second keeper (alias maps to lease).
  test('identifier churn does not create a second keeper', () {
    final a = W5Ownership();
    a.onControl(
        handle: 'h1', role: W5Role.outbound,
        myCandidate: candA, peerCandidate: candB, peerAlias: aliasB);
    a.onConfirmed(handle: 'h1');
    // The peer reappears under a churned CB handle but the SAME alias.
    expect(a.onDiscovered(alias: aliasB, wouldDial: true, candidateId: 'x'),
        isEmpty);
    expect(a.confirmedKeeperCount, 1);
  });

  // Disconnect/reconnect inside grace resumes; after grace erases.
  test('reconnect within grace resumes; after grace the encounter ends', () {
    final a = W5Ownership();
    a.onControl(
        handle: 'h1', role: W5Role.outbound,
        myCandidate: candA, peerCandidate: candB, peerAlias: aliasB);
    a.onConfirmed(handle: 'h1');
    a.onLinkDown(handle: 'h1');
    // still in grace → an expiry check before reconnect would end it, but a
    // reconnect first re-owns the SAME lease.
    a.onControl(
        handle: 'h2', role: W5Role.outbound,
        myCandidate: candA, peerCandidate: candB, peerAlias: aliasB);
    expect(a.keeperOf(candA), 'h2');
    // A late grace-expiry now no-ops (keeper present).
    expect(a.onGraceExpiry(leaseId: candA), isEmpty);

    // Now drop and let grace expire.
    a.onLinkDown(handle: 'h2');
    expect(a.onGraceExpiry(leaseId: candA), [(W5Op.ended, candA)]);
    expect(a.activeLeases, 0);
  });

  // Multiple peers → one keeper each, never a global cap.
  test('two and three distinct peers get independent keepers', () {
    final a = W5Ownership();
    a.onControl(
        handle: 'hb', role: W5Role.outbound,
        myCandidate: 'ca', peerCandidate: 'zb', peerAlias: 'ab');
    a.onControl(
        handle: 'hc', role: W5Role.outbound,
        myCandidate: 'cc', peerCandidate: 'zc', peerAlias: 'ac');
    a.onControl(
        handle: 'hd', role: W5Role.outbound,
        myCandidate: 'cd', peerCandidate: 'zd', peerAlias: 'ad');
    expect(a.activeLeases, 3);
    expect(a.confirmedKeeperCount, 3);
  });

  // Beacon OFF and explicit teardown erase leases/aliases.
  test('beacon off tears every encounter down', () {
    final a = W5Ownership();
    a.onControl(
        handle: 'hb', role: W5Role.outbound,
        myCandidate: 'ca', peerCandidate: 'zb', peerAlias: 'ab');
    a.onControl(
        handle: 'hc', role: W5Role.outbound,
        myCandidate: 'cc', peerCandidate: 'zc', peerAlias: 'ac');
    final off = a.onBeaconOff();
    expect(off.where((e) => e.$1 == W5Op.ended).length, 2);
    expect(a.activeLeases, 0);
    expect(a.leaseForAlias('ab'), isNull);
  });

  test('teardown closes keeper and erases identity', () {
    final a = W5Ownership();
    a.onControl(
        handle: 'h1', role: W5Role.outbound,
        myCandidate: candA, peerCandidate: candB, peerAlias: aliasB);
    expect(a.onTeardown(leaseId: candA), [(W5Op.close, 'h1'), (W5Op.ended, candA)]);
    expect(a.activeLeases, 0);
  });

  // Hostile/degenerate inputs fail safe.
  group('degenerate inputs fail safely', () {
    test('unknown link-down / teardown / grace are no-ops', () {
      final a = W5Ownership();
      expect(a.onLinkDown(handle: 'ghost'), isEmpty);
      expect(a.onTeardown(leaseId: 'ghost'), isEmpty);
      expect(a.onGraceExpiry(leaseId: 'ghost'), isEmpty);
      a.onAliasRoll(leaseId: 'ghost', newAlias: 'z'); // no throw
    });
    test('dial that never handshakes is cleared', () {
      final a = W5Ownership();
      expect(a.onDiscovered(alias: aliasB, wouldDial: true, candidateId: candA),
          [(W5Op.dial, candA)]);
      expect(a.onDiscovered(alias: aliasB, wouldDial: true, candidateId: candA),
          isEmpty); // engaged, no double-dial
      expect(a.onDialFailed(candidateId: candA), [(W5Op.ended, candA)]);
      expect(a.onDiscovered(alias: aliasB, wouldDial: true, candidateId: candA),
          [(W5Op.dial, candA)]); // dialable again
    });
  });

  // Property test: randomized event orderings for ONE encounter must never
  // yield more than one confirmed keeper, and must not throw.
  test('property: randomized orderings keep ≤1 keeper per encounter', () {
    for (var seed = 0; seed < 200; seed++) {
      final rng = Random(seed);
      final a = W5Ownership();
      // Two role-reversed links for one encounter, plus noise events.
      final events = <void Function()>[
        () => a.onControl(
            handle: 'A->B', role: W5Role.outbound,
            myCandidate: candA, peerCandidate: candB, peerAlias: aliasB),
        () => a.onControl(
            handle: 'B->A', role: W5Role.inbound,
            myCandidate: candA, peerCandidate: candB, peerAlias: aliasB),
        () => a.onControl(
            handle: 'dup', role: W5Role.inbound,
            myCandidate: candA, peerCandidate: 'cand-0', peerAlias: aliasB),
        () => a.onConfirmed(handle: 'A->B'),
        () => a.onConfirmed(handle: 'B->A'),
        () => a.onAliasRoll(leaseId: candA, newAlias: 'rot'),
        () => a.onLinkDown(handle: 'dup'),
      ]..shuffle(rng);
      for (final e in events) {
        e();
      }
      // Invariant: at most one confirmed keeper for the single encounter.
      expect(a.confirmedKeeperCount, lessThanOrEqualTo(1),
          reason: 'seed $seed violated the one-keeper invariant');
    }
  });
}
