import 'package:flutter_test/flutter_test.dart';
import 'package:in_range/features/beacon/w5_ownership.dart';

/// Acceptance tests for the #7 encounter-lease ownership state machine.
/// Scenario numbers map to the authorized brief's acceptance list. Scenarios
/// 11–14 are build/isolation-level (#8 compile-time diagnostic isolation) and
/// are covered outside this unit surface — noted at the bottom.
void main() {
  // Two stable encounter nonces. 'aaaa' < 'bbbb', so the 'aaaa' side is the
  // rotation-invariant initiator for the whole encounter.
  const nonceA = 'aaaa';
  const nonceB = 'bbbb';
  final lease = W5Lease.id(nonceA, nonceB);

  group('W5Lease', () {
    test('lease id is order-independent (both sides derive the same id)', () {
      expect(W5Lease.id(nonceA, nonceB), W5Lease.id(nonceB, nonceA));
    });
    test('initiator is deterministic and complementary', () {
      expect(W5Lease.iAmInitiator(nonceA, nonceB), isTrue);
      expect(W5Lease.iAmInitiator(nonceB, nonceA), isFalse);
    });
  });

  // Scenario 1: token ordering reverses while linked → exactly one link.
  test('1. rotation/tiebreak flip does not create a second link', () {
    final a = W5Ownership(); // initiator side
    a.onDiscovered(leaseId: lease, iAmInitiator: true);
    a.onLinkUp(
        leaseId: lease, handle: 'A->B', role: W5Role.outbound,
        iAmInitiator: true);
    expect(a.linkCount(lease), 1);
    // A later re-discovers the SAME encounter with a FLIPPED initiator flag
    // (what a rotating token would do). The existing encounter blocks a dial.
    final fx = a.onDiscovered(leaseId: lease, iAmInitiator: false);
    expect(fx, isEmpty);
    expect(a.linkCount(lease), 1);
  });

  // Scenario 2 (the core fix): inbound-only ownership blocks reverse
  // duplication. This is exactly the proven leak: B held only an inbound link,
  // its ownership map was empty, a token flip made it dial.
  test('2. inbound-only peer does NOT dial after ordering reverses', () {
    final b = W5Ownership(); // non-initiator side
    // B receives the inbound subscription (A dialed B).
    final up = b.onLinkUp(
        leaseId: lease, handle: 'A->B', role: W5Role.inbound,
        iAmInitiator: false);
    expect(up, [(W5Op.owns, 'A->B')]);
    expect(b.ownedHandle(lease), 'A->B');
    // Ordering reverses; B would now be "initiator" under a rotating token —
    // but the encounter already exists, so B stands down (no dial). Pre-fix
    // this returned a dial and produced the duplicate.
    final fx = b.onDiscovered(leaseId: lease, iAmInitiator: true);
    expect(fx, isEmpty);
    expect(b.linkCount(lease), 1);
  });

  // Scenario 3: identifier churn during a valid lease → no duplicate dial.
  test('3. peripheral-identifier churn does not cause a re-dial', () {
    final a = W5Ownership();
    a.onDiscovered(leaseId: lease, iAmInitiator: true);
    a.onLinkUp(
        leaseId: lease, handle: 'h1', role: W5Role.outbound,
        iAmInitiator: true);
    // The peer's advertising address churned → a discovery under a NEW handle,
    // but the encounter nonce (hence leaseId) is unchanged → stand down.
    final fx = a.onDiscovered(leaseId: lease, iAmInitiator: true);
    expect(fx, isEmpty);
    expect(a.linkCount(lease), 1);
  });

  // Scenario 4: simultaneous inbound/outbound race → deterministic convergence.
  test('4. simultaneous open converges to one link on each side', () {
    // Initiator A: owns its outbound; also receives an inbound (B raced a dial)
    // → closes the inbound, keeps outbound.
    final a = W5Ownership();
    a.onLinkUp(
        leaseId: lease, handle: 'A->B', role: W5Role.outbound,
        iAmInitiator: true);
    final aInbound = a.onLinkUp(
        leaseId: lease, handle: 'B->A', role: W5Role.inbound,
        iAmInitiator: true);
    expect(aInbound, [(W5Op.close, 'B->A')]);
    expect(a.ownedHandle(lease), 'A->B');
    expect(a.linkCount(lease), 1);

    // Non-initiator B: owns the inbound (A->B); its own raced outbound (B->A)
    // is closed. Both sides therefore keep the A->B connection — converged.
    final b = W5Ownership();
    b.onLinkUp(
        leaseId: lease, handle: 'B->A', role: W5Role.outbound,
        iAmInitiator: false); // non-keeper, held transiently
    final bKeeper = b.onLinkUp(
        leaseId: lease, handle: 'A->B', role: W5Role.inbound,
        iAmInitiator: false);
    expect(bKeeper, [(W5Op.owns, 'A->B'), (W5Op.close, 'B->A')]);
    expect(b.ownedHandle(lease), 'A->B');
    expect(b.linkCount(lease), 1);
  });

  // Scenario 5: multiple peers → one link per distinct peer, never a global cap.
  test('5. distinct peers get independent links (no global cap)', () {
    final a = W5Ownership();
    final leaseC = W5Lease.id(nonceA, 'cccc');
    a.onLinkUp(
        leaseId: lease, handle: 'A->B', role: W5Role.outbound,
        iAmInitiator: true);
    a.onLinkUp(
        leaseId: leaseC, handle: 'A->C', role: W5Role.outbound,
        iAmInitiator: true);
    expect(a.activeEncounters, 2);
    expect(a.linkCount(lease), 1);
    expect(a.linkCount(leaseC), 1);
  });

  // Scenario 6: restoration rebuilds ownership without duplication.
  test('6. re-registering the same handle/lease stays single', () {
    final a = W5Ownership();
    a.onLinkUp(
        leaseId: lease, handle: 'A->B', role: W5Role.outbound,
        iAmInitiator: true);
    // Restoration replays the same link.
    final again = a.onLinkUp(
        leaseId: lease, handle: 'A->B', role: W5Role.outbound,
        iAmInitiator: true);
    expect(again, [(W5Op.owns, 'A->B')]);
    expect(a.linkCount(lease), 1);
  });

  // Scenario 7: disconnect/reconnect retains or re-establishes correctly.
  test('7. keeper disconnect ends encounter; reconnect re-owns', () {
    final a = W5Ownership();
    a.onLinkUp(
        leaseId: lease, handle: 'A->B', role: W5Role.outbound,
        iAmInitiator: true);
    final down = a.onLinkDown(handle: 'A->B');
    expect(down, [(W5Op.ended, lease)]);
    expect(a.activeEncounters, 0);
    // Reconnect.
    final re = a.onLinkUp(
        leaseId: lease, handle: 'A->B2', role: W5Role.outbound,
        iAmInitiator: true);
    expect(re, [(W5Op.owns, 'A->B2')]);
    expect(a.linkCount(lease), 1);
  });

  // Scenario 8: lease expiry / dropPeer erase encounter identity.
  test('8. teardown closes the link and erases the encounter', () {
    final a = W5Ownership();
    a.onLinkUp(
        leaseId: lease, handle: 'A->B', role: W5Role.outbound,
        iAmInitiator: true);
    final td = a.onTeardown(leaseId: lease);
    expect(td, [(W5Op.close, 'A->B'), (W5Op.ended, lease)]);
    expect(a.activeEncounters, 0);
    expect(a.ownedHandle(lease), isNull);
  });

  // Scenario 9: beacon OFF clears ownership safely.
  test('9. beacon off tears every encounter down', () {
    final a = W5Ownership();
    final leaseC = W5Lease.id(nonceA, 'cccc');
    a.onLinkUp(
        leaseId: lease, handle: 'A->B', role: W5Role.outbound,
        iAmInitiator: true);
    a.onLinkUp(
        leaseId: leaseC, handle: 'A->C', role: W5Role.outbound,
        iAmInitiator: true);
    final off = a.onBeaconOff();
    expect(off.where((e) => e.$1 == W5Op.ended).length, 2);
    expect(a.activeEncounters, 0);
  });

  // Scenario 10: malformed / stale / replayed / conflicting messages fail safe.
  group('10. hostile/degenerate inputs fail safely', () {
    test('unknown link-down is a no-op', () {
      expect(W5Ownership().onLinkDown(handle: 'ghost'), isEmpty);
    });
    test('teardown of unknown lease is a no-op', () {
      expect(W5Ownership().onTeardown(leaseId: 'ghost'), isEmpty);
    });
    test('dial that never links up is cleared (does not wedge future dials)',
        () {
      final a = W5Ownership();
      expect(a.onDiscovered(leaseId: lease, iAmInitiator: true),
          [(W5Op.dial, '')]);
      // Still negotiating → a repeat discover does not double-dial.
      expect(a.onDiscovered(leaseId: lease, iAmInitiator: true), isEmpty);
      // Watchdog fires → clears the negotiating encounter.
      expect(a.onDialFailed(leaseId: lease), [(W5Op.ended, lease)]);
      // Now a fresh dial is allowed again.
      expect(a.onDiscovered(leaseId: lease, iAmInitiator: true),
          [(W5Op.dial, '')]);
    });
    test('a conflicting duplicate keeper-role link is closed, never adopted',
        () {
      final a = W5Ownership();
      a.onLinkUp(
          leaseId: lease, handle: 'first', role: W5Role.outbound,
          iAmInitiator: true);
      final dup = a.onLinkUp(
          leaseId: lease, handle: 'second', role: W5Role.outbound,
          iAmInitiator: true);
      expect(dup, [(W5Op.close, 'second')]);
      expect(a.ownedHandle(lease), 'first'); // oldest healthy kept
    });
  });

  // Scenarios 11–14 (diagnostic settings cannot affect production; in-place
  // upgrade retains legitimate restoration; diagnostic run/session id reset;
  // diagnostic logging bounded/compiled-out) are BUILD/ISOLATION-level, verified
  // by the #8 compile-time isolation + Phase-1 harness fixes, not by this unit
  // surface. Tracked in issue #8.
}
