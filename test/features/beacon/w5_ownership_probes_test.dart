import 'package:flutter_test/flutter_test.dart';
import 'package:in_range/features/beacon/w5_ownership.dart';

/// H-ORCH-1 remediation: the round-7/8 adversarial probe suites (16 + 10
/// probes) were run from /tmp and cited as sign-off evidence but never
/// committed — this file RECONSTRUCTS, from the PR #9 round-7/8 review
/// records, every probe class not already pinned by the committed suites
/// (w5_ownership_test.dart, zz vectors). These guard the alias-stomp wedge
/// family — the worst correctness bug found in this subsystem — against
/// silent regression. Do not delete without replacing coverage.
const candA = 'cand-a';
const candB = 'cand-b';
const aliasB = 'aliasB';
const leaseId = candA;

W5Contender ct(String c, String l) => W5Contender(c, l);

W5Ownership established(String linkId, {String handle = 'p1'}) {
  final a = W5Ownership();
  a.onControl(
      handle: handle,
      role: W5Role.outbound,
      myCandidate: candA,
      peerCandidate: candB,
      peerAlias: aliasB,
      linkId: linkId);
  return a;
}

void commit(
    W5Ownership a, String lease, List<W5Contender> peerSet, String peerAlias,
    {int gen = 7}) {
  final mine = a.currentProposal(lease)!;
  a.onProposeRecv(
      peerAlias: peerAlias, proposal: W5Proposal(lease, gen, peerSet));
  a.onAckRecv(
      peerAlias: peerAlias, ack: W5Ack(lease, mine.viewGen, mine.viewHash));
}

void main() {
  // H-W5-1 — a committed encounter reached only via realId (unknown rotated
  // alias, no prevAlias, lease keyed by the PEER's candidate) must still hit
  // the sticky-keeper branch: intruder rejected, keeper unmoved. Before the
  // hoist this returned [W5SendPropose] and moved the keeper p1→p2, L5→L0.
  test('probe: realId-resolved committed encounter keeps its sticky keeper',
      () {
    final a = W5Ownership();
    // peerCandidate 'cand-a' < myCandidate 'cand-b' → leaseId = peer's cand.
    a.onControl(
        handle: 'p1',
        role: W5Role.outbound,
        myCandidate: 'cand-b',
        peerCandidate: 'cand-a',
        peerAlias: aliasB,
        linkId: 'L5');
    commit(a, 'cand-a', [ct('cand-b', 'L5')], aliasB);
    expect(a.committedKeeper('cand-a'), 'p1');
    // Intruder link under a NEVER-SEEN alias (rotation, ALIAS_ROLL lost, no
    // prevAlias): resolution falls through _locate to _enc[realId].
    final fx = a.onControl(
        handle: 'p2',
        role: W5Role.inbound,
        myCandidate: 'cand-b',
        peerCandidate: 'cand-a',
        peerAlias: 'alias-rotated-unknown',
        linkId: 'L0');
    expect(fx, [const W5RejectInbound('p2')],
        reason: 'sticky branch must fire via realId resolution');
    expect(a.committedKeeper('cand-a'), 'p1',
        reason: 'committed keeper never moves without an effect');
    expect(a.committedLinkId('cand-a'), 'L5');
  });

  // H-W5-5 — the grace observation the recovery bypass keys on: true only
  // between keeper loss and re-establishment/expiry.
  test('probe: isInGrace tracks the reconnect window exactly', () {
    final a = established('L1');
    expect(a.isInGrace(leaseId), isFalse);
    a.onLinkDown(handle: 'p1');
    expect(a.isInGrace(leaseId), isTrue);
    // Re-establishment clears grace...
    a.onControl(
        handle: 'p3',
        role: W5Role.outbound,
        myCandidate: candA,
        peerCandidate: candB,
        peerAlias: aliasB,
        linkId: 'L3');
    expect(a.isInGrace(leaseId), isFalse);
    // ...and expiry erases: no lease, no grace.
    a.onLinkDown(handle: 'p3');
    a.onGraceExpiry(leaseId: leaseId);
    expect(a.isInGrace(leaseId), isFalse);
    expect(a.activeLeases, 0);
  });

  // H-W5-3 — a pending dial that never establishes must be reclaimable:
  // onDialFailed clears it so the encounter erases and rediscovery re-dials
  // (the leak was the ADAPTER routing an unestablished disconnect to
  // onLinkDown, which no-ops; the oracle contract this relies on is here).
  test('probe: unestablished pending dial is reclaimed via onDialFailed', () {
    final a = W5Ownership();
    expect(
        a.onDiscovered(
            alias: aliasB, wouldDial: true, candidateId: candA, linkId: 'L1'),
        [const W5Dial('L1')]);
    // Never established (no onControl). Dial-fail clears the pending dial and
    // erases the link-less encounter.
    expect(a.onDialFailed(linkId: 'L1'), [const W5Ended(candA)]);
    expect(a.activeLeases, 0);
    // Rediscovery re-dials — no permanent wedge.
    expect(
        a.onDiscovered(
            alias: aliasB, wouldDial: true, candidateId: candA, linkId: 'L2'),
        [const W5Dial('L2')]);
  });

  // R7 probe 1 — proposals are encounterId-bound: a same-generation proposal
  // for a DIFFERENT encounter never collides into this one's gen space.
  test('probe: foreign-encounter proposal is inert at any generation', () {
    final a = established('L1');
    a.onProposeRecv(
        peerAlias: aliasB, proposal: W5Proposal(leaseId, 8, [ct(candA, 'L1')]));
    final fx = a.onProposeRecv(
        peerAlias: aliasB,
        proposal: W5Proposal('other-enc', 8, [ct('cand-z', 'L9')]));
    expect(fx, isEmpty); // wrong encounter → dropped, no state change
    final mine = a.currentProposal(leaseId)!;
    a.onAckRecv(
        peerAlias: aliasB, ack: W5Ack(leaseId, mine.viewGen, mine.viewHash));
    expect(a.committedLinkId(leaseId), 'L1'); // accepted view intact
  });

  // R7 probe 2 — saturation from a non-onControl bump site WITH a commit
  // pending: teardown still wins over the half-done agreement.
  test('probe: saturation with commit pending tears down cleanly', () {
    final a = established('L1');
    a.onProposeRecv(
        peerAlias: aliasB, proposal: W5Proposal(leaseId, 7, [ct(candA, 'L1')]));
    // Peer proposal accepted, ACK not yet arrived — commit pending.
    a.debugSetViewGen(leaseId, kU32Max);
    final fx = a.onLinkDown(handle: 'p1'); // non-onControl bump site
    expect(fx.last, const W5Ended(leaseId));
    expect(a.activeLeases, 0);
    // A late ACK for the dead encounter is inert.
    expect(
        a.onAckRecv(peerAlias: aliasB, ack: W5Ack(leaseId, 2, 'x')), isEmpty);
  });

  // R7 probe 5 — handle AND linkId become reusable after teardown erases the
  // encounter (the global bijection releases them; only LIVE reuse fails).
  test('probe: handle/linkId reuse after teardown is legal', () {
    final a = established('L1');
    commit(a, leaseId, [ct(candA, 'L1')], aliasB);
    a.onTeardown(leaseId: leaseId);
    expect(a.activeLeases, 0);
    // Same handle p1 AND same linkId L1 in a brand-new encounter: allowed.
    final fx = a.onControl(
        handle: 'p1',
        role: W5Role.outbound,
        myCandidate: 'cand-x',
        peerCandidate: 'cand-y',
        peerAlias: 'aliasY',
        linkId: 'L1');
    expect(fx.whereType<W5CloseOutbound>(), isEmpty,
        reason: 'released ids must not fail closed');
    expect(a.activeLeases, 1);
    expect(a.keeperOf('cand-x'), 'p1');
  });

  // R7 probe 6 — dial-fail recovery on BOTH candidate orderings: after a
  // failed dial the encounter erases (no links) and a rediscovery re-dials.
  test('probe: dial-fail recovery, both candidate orderings', () {
    for (final mine in ['cand-a', 'cand-z']) {
      // 'cand-a' < aliasB peer candidate; 'cand-z' > — both orderings.
      final a = W5Ownership();
      expect(
          a.onDiscovered(
              alias: aliasB, wouldDial: true, candidateId: mine, linkId: 'L1'),
          [const W5Dial('L1')],
          reason: 'ordering $mine: first dial');
      expect(a.onDialFailed(linkId: 'L1'), [W5Ended(mine)],
          reason: 'ordering $mine: erase on dial-fail with no links');
      expect(
          a.onDiscovered(
              alias: aliasB, wouldDial: true, candidateId: mine, linkId: 'L2'),
          [const W5Dial('L2')],
          reason: 'ordering $mine: recovery re-dial never wedges');
    }
  });

  // R7 probe 7 — the local cap SELF-EXCLUDES a relanding pending dial: the
  // link whose HELLO arrives is the pending dial itself, not a newcomer.
  test('probe: own pending dial self-excludes from the cap', () {
    final a = W5Ownership();
    a.onDiscovered(
        alias: aliasB, wouldDial: true, candidateId: candA, linkId: 'L0');
    // Fill remaining cap with inbound links (pending L0 counts too: 1+4=5).
    for (var i = 1; i <= kMaxContenders - 1; i++) {
      a.onControl(
          handle: 'h$i',
          role: W5Role.inbound,
          myCandidate: candA,
          peerCandidate: candB,
          peerAlias: aliasB,
          linkId: 'L$i');
    }
    expect(a.currentProposal(leaseId)!.contenders.length, kMaxContenders);
    // The pending dial's own HELLO lands: must be ACCEPTED (it replaces its
    // pending slot, it does not exceed the cap).
    final fx = a.onControl(
        handle: 'h0',
        role: W5Role.outbound,
        myCandidate: candA,
        peerCandidate: candB,
        peerAlias: aliasB,
        linkId: 'L0');
    expect(fx.whereType<W5CloseOutbound>(), isEmpty,
        reason: 'own pending dial must not be refused as over-cap');
    expect(a.currentProposal(leaseId)!.contenders.length, kMaxContenders);
  });

  // R7 probe 8 — PROPOSE route-set exactness under churn: the broadcast
  // routes are exactly the live links, updated as links come and go.
  test('probe: propose route set tracks live links exactly', () {
    final a = established('L1');
    var fx = a.onControl(
        handle: 'p2',
        role: W5Role.inbound,
        myCandidate: candA,
        peerCandidate: candB,
        peerAlias: aliasB,
        linkId: 'L2');
    var send = fx.whereType<W5SendPropose>().single;
    expect({for (final r in send.routes) r.handle}, {'p1', 'p2'});
    expect(
        send.routes.firstWhere((r) => r.handle == 'p1').role, W5Role.outbound);
    expect(
        send.routes.firstWhere((r) => r.handle == 'p2').role, W5Role.inbound);
    // p1 dies → the next propose routes ONLY over p2.
    a.onLinkDown(handle: 'p1');
    fx = a.onRetryTimer(leaseId: leaseId);
    send = fx.whereType<W5SendPropose>().single;
    expect({for (final r in send.routes) r.handle}, {'p2'});
  });

  // R8 probe — two-generations-back prevAlias is REJECTED: alias continuity
  // is exactly one generation (privacy bound from the ratification).
  test('probe: prevAlias two generations back does not resolve', () {
    final a = established('L1');
    // Roll twice: aliasB → aliasB2 → aliasB3. aliasB is now two back.
    a.onAliasRoll(leaseId: leaseId, newAlias: 'aliasB2');
    a.onAliasRoll(leaseId: leaseId, newAlias: 'aliasB3');
    expect(a.leaseForAlias(aliasB), isNull, reason: 'two-back alias expired');
    a.onLinkDown(handle: 'p1'); // grace
    // Rediscovery under a NEW alias claiming the two-back alias as prev:
    // must NOT resolve into the lease (fresh candidates → new encounter).
    a.onControl(
        handle: 'p9',
        role: W5Role.outbound,
        myCandidate: 'cand-x',
        peerCandidate: 'cand-y',
        peerAlias: 'aliasB4',
        linkId: 'L9',
        peerPrevAlias: aliasB);
    expect(a.leaseForAlias('aliasB4'), isNot(leaseId),
        reason: 'stale prevAlias must not rejoin the old lease');
    expect(a.activeLeases, 2); // old lease still in grace, new one separate
  });

  // R8 probe — the W5Ended close contract on the EMPTY-link erase paths:
  // graceExpiry and dial-fail erase carry no links, so Ended arrives alone —
  // pinned so the contract stays "closes for every live link", not "always
  // at least one close".
  test('probe: empty-link erase paths emit bare Ended by contract', () {
    final a = established('L1');
    a.onLinkDown(handle: 'p1'); // grace; zero live links
    expect(a.onGraceExpiry(leaseId: leaseId), [const W5Ended(leaseId)]);
    final b = W5Ownership();
    b.onDiscovered(
        alias: aliasB, wouldDial: true, candidateId: candA, linkId: 'L1');
    expect(b.onDialFailed(linkId: 'L1'), [const W5Ended(candA)]);
  });

  // R8 probe — changed-candidate rejoin commits at a CONTINUED generation
  // (vector 2's flow, asserted at the effect level end-to-end).
  test('probe: fresh-candidate prevAlias rejoin re-commits, gen continuous',
      () {
    final a = established('L1');
    commit(a, leaseId, [ct(candA, 'L1')], aliasB, gen: 5);
    a.onLinkDown(handle: 'p1');
    final genInGrace = a.currentProposal(leaseId)!.viewGen;
    a.onControl(
        handle: 'p3',
        role: W5Role.outbound,
        myCandidate: 'cand-x',
        peerCandidate: candB,
        peerAlias: 'aliasB2',
        linkId: 'L3',
        peerPrevAlias: aliasB);
    final lease = a.leaseForAlias('aliasB2')!;
    final cur = a.currentProposal(lease)!;
    expect(cur.viewGen, greaterThan(genInGrace),
        reason: 'generation never resets across the rejoin');
    a.onProposeRecv(
        peerAlias: 'aliasB2',
        proposal: W5Proposal(lease, 9, [ct('cand-x', 'L3')]));
    a.onAckRecv(
        peerAlias: 'aliasB2', ack: W5Ack(lease, cur.viewGen, cur.viewHash));
    expect(a.committedLinkId(lease), 'L3');
    expect(a.activeLeases, 1);
  });
}
