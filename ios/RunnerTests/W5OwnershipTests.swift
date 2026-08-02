import XCTest

@testable import Runner

/// Native mirror of test/features/beacon/w5_ownership_test.dart (v5.2 cases:
/// peer-gen tracking, endpoint-global bijection, local cap, injective
/// contenders, effect routing, saturation). candA < candB. Local CB handles are
/// observer-local — only wire linkIds are compared across endpoints.
private let candA = "cand-a"
private let candB = "cand-b"
private let aliasA = "aliasA"
private let aliasB = "aliasB"
private let leaseId = candA

private func ct(_ central: String, _ link: String) -> W5Contender {
  W5Contender(central: central, linkId: link)
}

/// Deterministic RNG so the randomized property schedules are reproducible.
private struct SplitMix64: RandomNumberGenerator {
  var state: UInt64
  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}

/// Two-endpoint message queue routing PROPOSE + ACK (routes ignored for
/// delivery; source identity is exercised by the direct-call violation tests).
private final class Sim {
  let a = W5Ownership()
  let b = W5Ownership()
  var q: [(to: String, fromAlias: String, msg: W5Effect)] = []

  func collect(_ from: String, _ fx: [W5Effect]) {
    let ep = from == "A" ? a : b
    let to = from == "A" ? "B" : "A"
    let fromAlias = from == "A" ? aliasA : aliasB
    for f in fx {
      if case .owns(let handle) = f, !ep.isCommitted(leaseId) {
        XCTFail("owns before commit on \(from) (\(handle))")
      }
      switch f {
      case .sendPropose, .sendAck: q.append((to, fromAlias, f))
      default: break
      }
    }
  }

  func dial(_ ep: String, _ linkId: String) {
    _ = (ep == "A" ? a : b).onDiscovered(
      alias: ep == "A" ? aliasB : aliasA,
      wouldDial: true,
      candidateId: ep == "A" ? candA : candB,
      linkId: linkId)
  }

  func linkUp(_ ep: String, _ handle: String, _ role: W5Role, _ linkId: String) {
    collect(
      ep,
      (ep == "A" ? a : b).onControl(
        handle: handle,
        role: role,
        myCandidate: ep == "A" ? candA : candB,
        peerCandidate: ep == "A" ? candB : candA,
        peerAlias: ep == "A" ? aliasB : aliasA,
        linkId: linkId))
  }

  func deliver(_ i: Int) {
    let (to, fromAlias, msg) = q.remove(at: i)
    let ep = to == "A" ? a : b
    switch msg {
    case .sendPropose(let proposal, _):
      collect(to, ep.onProposeRecv(peerAlias: fromAlias, proposal: proposal))
    case .sendAck(let ack, _):
      collect(to, ep.onAckRecv(peerAlias: fromAlias, ack: ack))
    default: break
    }
  }

  func retry() {
    collect("A", a.onRetryTimer(leaseId: leaseId))
    collect("B", b.onRetryTimer(leaseId: leaseId))
  }

  func safety() {
    let la = a.committedLinkId(leaseId)
    let lb = b.committedLinkId(leaseId)
    if let la, let lb, la != lb {
      XCTFail("SAFETY: two different committed linkIds A=\(la) B=\(lb)")
    }
  }

  func flush() {
    var guardCount = 0
    while (!q.isEmpty || !(a.isCommitted(leaseId) && b.isCommitted(leaseId)))
      && guardCount < 300 {
      guardCount += 1
      while !q.isEmpty {
        deliver(0)
        safety()
      }
      retry()
    }
  }
}

private func commitAgainst(
  _ a: W5Ownership, _ lease: String, _ peerSet: [W5Contender],
  _ peerAlias: String
) {
  let mine = a.currentProposal(lease)!
  _ = a.onProposeRecv(
    peerAlias: peerAlias,
    proposal: W5Proposal(encounterId: lease, viewGen: 7, contenders: peerSet))
  _ = a.onAckRecv(
    peerAlias: peerAlias,
    ack: W5Ack(encounterId: lease, ackViewGen: mine.viewGen, viewHash: mine.viewHash))
}

private func established(_ linkId: String) -> W5Ownership {
  let a = W5Ownership()
  _ = a.onControl(
    handle: "p1", role: .outbound, myCandidate: candA, peerCandidate: candB,
    peerAlias: aliasB, linkId: linkId)
  return a
}

final class W5OwnershipTests: XCTestCase {

  func testPropertySafetyAndLivenessRandomizedSchedules() {
    for seed in 0..<500 {
      var rng = SplitMix64(state: UInt64(seed &+ 1))
      let s = Sim()
      s.dial("A", "Lab")
      s.dial("B", "Lba")
      var linkUps: [() -> Void] = [
        { s.linkUp("A", "a1", .outbound, "Lab") },
        { s.linkUp("A", "a2", .inbound, "Lba") },
        { s.linkUp("B", "b1", .inbound, "Lab") },
        { s.linkUp("B", "b2", .outbound, "Lba") },
      ]
      linkUps.shuffle(using: &rng)
      var li = 0
      var steps = 0
      while (li < linkUps.count || !s.q.isEmpty) && steps < 400 {
        steps += 1
        if li < linkUps.count && (Int.random(in: 0..<3, using: &rng) == 0 || s.q.isEmpty) {
          linkUps[li]()
          li += 1
        } else if !s.q.isEmpty {
          if Int.random(in: 0..<4, using: &rng) == 0 && s.q.count > 1 {
            s.q.remove(at: Int.random(in: 0..<s.q.count, using: &rng))
          } else {
            s.deliver(Int.random(in: 0..<s.q.count, using: &rng))
          }
        }
        s.safety()
      }
      s.flush()
      s.safety()
      XCTAssertEqual(s.a.committedLinkId(leaseId), "Lab", "A seed \(seed)")
      XCTAssertEqual(s.b.committedLinkId(leaseId), "Lab", "B seed \(seed)")
    }
  }

  // v5.2 #1 — older peer generation is NOT accepted/ACKed.
  func testOlderPeerGenerationIsRejected() {
    let a = established("L1")
    _ = a.onProposeRecv(
      peerAlias: aliasB,
      proposal: W5Proposal(encounterId: leaseId, viewGen: 8, contenders: [ct("cand-a", "L1")]))
    let fx = a.onProposeRecv(
      peerAlias: aliasB,
      proposal: W5Proposal(encounterId: leaseId, viewGen: 7, contenders: [ct("cand-a", "L1")]))
    XCTAssertEqual(fx, []) // gen 7 < accepted gen 8 → dropped, no ACK
  }

  // v5.2 #2 — same-gen conflicting payload does NOT poison the accepted view.
  func testSameGenConflictingPayloadFailsClosed() {
    let a = established("L1")
    _ = a.onProposeRecv(
      peerAlias: aliasB,
      proposal: W5Proposal(encounterId: leaseId, viewGen: 8, contenders: [ct("cand-a", "L1")]))
    let fx = a.onProposeRecv(
      peerAlias: aliasB,
      proposal: W5Proposal(encounterId: leaseId, viewGen: 8, contenders: [ct("cand-z", "L9")]),
      sourceHandle: "p1",
      sourceRole: .outbound)
    XCTAssertEqual(fx, [.closeOutbound(handle: "p1")]) // fail closed
    // The valid view survived → the peer's ACK still commits.
    let mine = a.currentProposal(leaseId)!
    _ = a.onAckRecv(
      peerAlias: aliasB,
      ack: W5Ack(encounterId: leaseId, ackViewGen: mine.viewGen, viewHash: mine.viewHash))
    XCTAssertEqual(a.committedLinkId(leaseId), "L1")
  }

  // v5.2 #3 — endpoint-global bijection: a live handle cannot be rebound into a
  // second encounter.
  func testLiveHandleIsNotReboundIntoSecondEncounter() {
    let a = established("L1")
    commitAgainst(a, leaseId, [ct("cand-a", "L1")], aliasB)
    let fx = a.onControl(
      handle: "p1", role: .outbound, myCandidate: "cand-x",
      peerCandidate: "cand-y", peerAlias: "otherAlias", linkId: "L9")
    XCTAssertEqual(fx, [.closeOutbound(handle: "p1")]) // fail closed
    XCTAssertEqual(a.activeLeases, 1) // no second encounter created
    XCTAssertEqual(a.committedKeeper(leaseId), "p1") // original binding intact
  }

  // v5.2 #3b — a live linkId cannot be replayed into a second encounter.
  func testLiveLinkIdIsNotAcceptedInSecondEncounter() {
    let a = established("L1")
    let fx = a.onControl(
      handle: "p9", role: .outbound, myCandidate: "cand-x",
      peerCandidate: "cand-y", peerAlias: "otherAlias", linkId: "L1")
    XCTAssertEqual(fx, [.closeOutbound(handle: "p9")])
    XCTAssertEqual(a.activeLeases, 1)
  }

  // v5.2 #4 — local contenders cannot exceed the cap.
  func testLocalContendersAreCapped() {
    let a = W5Ownership()
    for i in 0..<kW5MaxContenders {
      _ = a.onControl(
        handle: "h\(i)", role: .inbound, myCandidate: candA,
        peerCandidate: candB, peerAlias: aliasB, linkId: "L\(i)")
    }
    let fx = a.onControl(
      handle: "hx", role: .inbound, myCandidate: candA, peerCandidate: candB,
      peerAlias: aliasB, linkId: "Lx")
    XCTAssertEqual(fx, [.rejectInbound(handle: "hx")])
    XCTAssertEqual(a.currentProposal(leaseId)!.contenders.count, kW5MaxContenders)
  }

  // v5.2 #5 — out-of-range (negative / > u32) proposal generation is rejected.
  func testOutOfU32RangeProposalGenerationIsRejected() {
    let a = established("L1")
    XCTAssertEqual(
      a.onProposeRecv(
        peerAlias: aliasB,
        proposal: W5Proposal(encounterId: leaseId, viewGen: -1, contenders: [ct("cand-a", "L1")]),
        sourceHandle: "p1",
        sourceRole: .outbound),
      [.closeOutbound(handle: "p1")])
    XCTAssertEqual(
      a.onProposeRecv(
        peerAlias: aliasB,
        proposal: W5Proposal(
          encounterId: leaseId, viewGen: kW5U32Max + 1, contenders: [ct("cand-a", "L1")]),
        sourceHandle: "p1",
        sourceRole: .outbound),
      [.closeOutbound(handle: "p1")])
    // Injective encoding: these two DIFFERENT contender sets are not equal.
    XCTAssertNotEqual(
      W5Proposal(encounterId: leaseId, viewGen: 1, contenders: [ct("aa|bb", "cc")]),
      W5Proposal(encounterId: leaseId, viewGen: 1, contenders: [ct("aa", "bb|cc")]))
  }

  // v5.2 #6 — a proposal carrying too many contenders (over cap) fails the
  // source link closed.
  func testOverCapProposalFailsSourceLinkClosed() {
    let a = established("L1")
    let huge = (0...kW5MaxContenders).map { ct("c\($0)", "l\($0)") }
    let fx = a.onProposeRecv(
      peerAlias: aliasB,
      proposal: W5Proposal(encounterId: leaseId, viewGen: 7, contenders: huge),
      sourceHandle: "p1",
      sourceRole: .outbound)
    XCTAssertEqual(fx, [.closeOutbound(handle: "p1")])
  }

  // Bijection within-encounter (v5.1 regressions retained).
  func testSameLinkIdOnSecondHandleDoesNotReOwn() {
    let a = established("L1")
    commitAgainst(a, leaseId, [ct("cand-a", "L1")], aliasB)
    let fx = a.onControl(
      handle: "p2", role: .outbound, myCandidate: candA, peerCandidate: candB,
      peerAlias: aliasB, linkId: "L1")
    XCTAssertEqual(fx, [.closeOutbound(handle: "p2")])
    XCTAssertEqual(a.committedKeeper(leaseId), "p1")
  }

  // Two-phase + wire linkId agreement.
  func testTwoSameDirectionDuplicatesAgreeOnOneWireLinkId() {
    let s = Sim()
    s.dial("A", "L1")
    s.dial("A", "L2")
    s.linkUp("A", "a1", .outbound, "L1")
    s.linkUp("A", "a2", .outbound, "L2")
    s.linkUp("B", "b2", .inbound, "L2")
    s.linkUp("B", "b1", .inbound, "L1")
    s.flush()
    XCTAssertEqual(s.a.committedLinkId(leaseId), "L1")
    XCTAssertEqual(s.b.committedLinkId(leaseId), "L1")
  }

  func testNoCommitUntilPeerAcksOurCurrentView() {
    let a = established("L1")
    _ = a.onProposeRecv(
      peerAlias: aliasB,
      proposal: W5Proposal(encounterId: leaseId, viewGen: 7, contenders: [ct("cand-a", "L1")]))
    XCTAssertFalse(a.isCommitted(leaseId))
    let mine = a.currentProposal(leaseId)!
    _ = a.onAckRecv(
      peerAlias: aliasB,
      ack: W5Ack(encounterId: leaseId, ackViewGen: mine.viewGen, viewHash: mine.viewHash))
    XCTAssertEqual(a.committedLinkId(leaseId), "L1")
  }

  func testStaleProposalDoesNotCommitReplacementLink() {
    let a = established("L1")
    // Commit L1 (peer view gen 10).
    let m1 = a.currentProposal(leaseId)!
    _ = a.onProposeRecv(
      peerAlias: aliasB,
      proposal: W5Proposal(encounterId: leaseId, viewGen: 10, contenders: [ct("cand-a", "L1")]))
    _ = a.onAckRecv(
      peerAlias: aliasB,
      ack: W5Ack(encounterId: leaseId, ackViewGen: m1.viewGen, viewHash: m1.viewHash))
    XCTAssertEqual(a.committedLinkId(leaseId), "L1")
    // L1 drops; A establishes replacement L2.
    _ = a.onLinkDown(handle: "p1")
    _ = a.onControl(
      handle: "p3", role: .outbound, myCandidate: candA, peerCandidate: candB,
      peerAlias: aliasB, linkId: "L2")
    // B (unaware) retransmits its old committed-view proposal (gen 10, L1) →
    // idempotent, and a stale ACK → neither commits the L2 replacement.
    _ = a.onProposeRecv(
      peerAlias: aliasB,
      proposal: W5Proposal(encounterId: leaseId, viewGen: 10, contenders: [ct("cand-a", "L1")]))
    _ = a.onAckRecv(
      peerAlias: aliasB, ack: W5Ack(encounterId: leaseId, ackViewGen: 5, viewHash: "stale"))
    XCTAssertFalse(a.isCommitted(leaseId))
    // B catches up to L2 at a newer generation → A commits L2.
    let m2 = a.currentProposal(leaseId)!
    _ = a.onProposeRecv(
      peerAlias: aliasB,
      proposal: W5Proposal(encounterId: leaseId, viewGen: 11, contenders: [ct("cand-a", "L2")]))
    _ = a.onAckRecv(
      peerAlias: aliasB,
      ack: W5Ack(encounterId: leaseId, ackViewGen: m2.viewGen, viewHash: m2.viewHash))
    XCTAssertEqual(a.committedLinkId(leaseId), "L2")
  }

  func testRestorationReplayOfPendingLinkIsIdempotent() {
    let a = established("L1")
    // iOS may re-deliver the restored link's control exchange before Dart
    // attaches: same handle+linkId replay mid-negotiation must not duplicate
    // the contender or wedge the later commit.
    _ = a.onControl(
      handle: "p1", role: .outbound, myCandidate: candA, peerCandidate: candB,
      peerAlias: aliasB, linkId: "L1")
    XCTAssertEqual(a.currentProposal(leaseId)!.contenders, [ct("cand-a", "L1")])
    XCTAssertFalse(a.isCommitted(leaseId))
    commitAgainst(a, leaseId, [ct("cand-a", "L1")], aliasB)
    XCTAssertEqual(a.committedLinkId(leaseId), "L1")
  }

  func testRestorationReplayOfCommittedLinkIsIdempotent() {
    let a = established("L1")
    commitAgainst(a, leaseId, [ct("cand-a", "L1")], aliasB)
    let fx = a.onControl(
      handle: "p1", role: .outbound, myCandidate: candA, peerCandidate: candB,
      peerAlias: aliasB, linkId: "L1")
    XCTAssertEqual(fx, [.owns(handle: "p1")])
    XCTAssertEqual(a.committedKeeperCount, 1)
  }

  // Two independent peers → one keeper each (endpoint-global, no cross-binding).
  func testTwoIndependentPeersEachGetOneCommittedKeeper() {
    let a = W5Ownership()
    _ = a.onControl(
      handle: "hb", role: .outbound, myCandidate: "ca", peerCandidate: "zb",
      peerAlias: "ab", linkId: "lb")
    commitAgainst(a, "ca", [ct("ca", "lb")], "ab")
    _ = a.onControl(
      handle: "hc", role: .outbound, myCandidate: "cc", peerCandidate: "zc",
      peerAlias: "ac", linkId: "lc")
    commitAgainst(a, "cc", [ct("cc", "lc")], "ac")
    XCTAssertEqual(a.committedKeeperCount, 2)
  }

  // Three independent peers → one keeper each (no global one-session cap).
  func testThreeIndependentPeersEachGetOneCommittedKeeper() {
    let a = W5Ownership()
    for (mine, peer, alias, link, handle) in [
      ("ca", "zb", "ab", "lb", "hb"),
      ("cc", "zc", "ac", "lc", "hc"),
      ("ce", "zd", "ad", "ld", "hd"),
    ] {
      _ = a.onControl(
        handle: handle, role: .outbound, myCandidate: mine, peerCandidate: peer,
        peerAlias: alias, linkId: link)
      commitAgainst(a, mine, [ct(mine, link)], alias)
    }
    XCTAssertEqual(a.committedKeeperCount, 3)
    XCTAssertEqual(a.activeLeases, 3)
  }

  // Local view generation saturation → teardown (no wrap), from ANY bumping
  // event, per the documented u32 rule.
  func testViewGenSaturationTearsDownInsteadOfWrapping() {
    let a = established("L1")
    a.debugSetViewGen(leaseId, kW5U32Max)
    // Overflow via a new inbound link.
    let fx = a.onControl(
      handle: "p2", role: .inbound, myCandidate: candA, peerCandidate: candB,
      peerAlias: aliasB, linkId: "L2")
    // R7 contract: W5Ended is preceded by a close for EVERY live link.
    XCTAssertEqual(
      fx,
      [
        .closeOutbound(handle: "p1"), .rejectInbound(handle: "p2"),
        .ended(leaseId: leaseId),
      ])
    XCTAssertEqual(a.activeLeases, 0)
    // Overflow via link-down (a non-onControl bump site).
    let b = established("L1")
    b.debugSetViewGen(leaseId, kW5U32Max)
    XCTAssertEqual(b.onLinkDown(handle: "p1"), [.ended(leaseId: leaseId)])
    XCTAssertEqual(b.activeLeases, 0)
  }

  // R7 probe 4 — rotation during grace with the ALIAS_ROLL lost.
  func testR7RotationDuringGraceRediscoveryRejoinsPrevAliasResolves() {
    let a = W5Ownership()
    _ = a.onControl(
      handle: "p1", role: .outbound, myCandidate: candA, peerCandidate: candB,
      peerAlias: aliasB, linkId: "L1")
    commitAgainst(a, leaseId, [ct("cand-a", "L1")], aliasB)
    _ = a.onLinkDown(handle: "p1")
    let genInGrace = a.currentProposal(leaseId)!.viewGen
    XCTAssertGreaterThan(genInGrace, 0)
    let fx = a.onDiscovered(
      alias: "aliasB2", wouldDial: true, candidateId: candA, linkId: "L3")
    XCTAssertEqual(fx, [.dial(linkId: "L3")])
    XCTAssertEqual(a.activeLeases, 1)  // no replacement encounter
    XCTAssertGreaterThan(a.currentProposal(leaseId)!.viewGen, genInGrace)
    _ = a.onControl(
      handle: "p3", role: .outbound, myCandidate: candA, peerCandidate: candB,
      peerAlias: "aliasB2", linkId: "L3", peerPrevAlias: aliasB)
    XCTAssertEqual(a.activeLeases, 1)
    XCTAssertEqual(a.leaseForAlias("aliasB2"), leaseId)
    let m = a.currentProposal(leaseId)!
    _ = a.onProposeRecv(
      peerAlias: "aliasB2",
      proposal: W5Proposal(encounterId: leaseId, viewGen: 11, contenders: [ct("cand-a", "L3")]))
    _ = a.onAckRecv(
      peerAlias: "aliasB2",
      ack: W5Ack(encounterId: leaseId, ackViewGen: m.viewGen, viewHash: m.viewHash))
    XCTAssertEqual(a.committedLinkId(leaseId), "L3")
  }

  // R7 fix #2 — rekey onto an occupied lease key fails closed.
  func testR7RekeyOntoOccupiedLeaseKeyFailsClosed() {
    let a = W5Ownership()
    _ = a.onControl(
      handle: "h1", role: .outbound, myCandidate: "cand-a", peerCandidate: "cand-z",
      peerAlias: "aliasZ", linkId: "L1")
    _ = a.onDiscovered(
      alias: "aliasY", wouldDial: true, candidateId: "cand-y", linkId: "L2")
    let fx = a.onControl(
      handle: "h2", role: .outbound, myCandidate: "cand-y", peerCandidate: "cand-a",
      peerAlias: "aliasY", linkId: "L2")
    XCTAssertEqual(fx, [.closeOutbound(handle: "h2")])
    XCTAssertEqual(a.activeLeases, 2)
    XCTAssertEqual(a.keeperOf("cand-a"), "h1")
  }

  // R7 contract — every erase-ender closes ALL live links before Ended.
  func testR7TeardownAndBeaconOffCloseEveryLiveLinkBeforeEnded() {
    let a = established("L1")
    _ = a.onControl(
      handle: "p2", role: .inbound, myCandidate: candA, peerCandidate: candB,
      peerAlias: aliasB, linkId: "L2")
    XCTAssertEqual(
      a.onTeardown(leaseId: leaseId),
      [
        .closeOutbound(handle: "p1"), .rejectInbound(handle: "p2"),
        .ended(leaseId: leaseId),
      ])
    let b = established("L1")
    _ = b.onControl(
      handle: "p2", role: .inbound, myCandidate: candA, peerCandidate: candB,
      peerAlias: aliasB, linkId: "L2")
    XCTAssertEqual(
      b.onBeaconOff(),
      [
        .closeOutbound(handle: "p1"), .rejectInbound(handle: "p2"),
        .ended(leaseId: leaseId),
      ])
  }

  // H-W5-5 — the grace observation the discovery bypass keys on.
  func testHW55IsInGraceTracksReconnectWindow() {
    let a = established("L1")
    XCTAssertFalse(a.isInGrace(leaseId))
    _ = a.onLinkDown(handle: "p1")
    XCTAssertTrue(a.isInGrace(leaseId))
    _ = a.onControl(
      handle: "p3", role: .outbound, myCandidate: candA, peerCandidate: candB,
      peerAlias: aliasB, linkId: "L3")
    XCTAssertFalse(a.isInGrace(leaseId))
    _ = a.onLinkDown(handle: "p3")
    _ = a.onGraceExpiry(leaseId: leaseId)
    XCTAssertFalse(a.isInGrace(leaseId))
    XCTAssertEqual(a.activeLeases, 0)
  }

  // H-W5-1 — a committed encounter reached only via realId (unknown rotated
  // alias, no prevAlias, lease keyed by the PEER's candidate) must hit the
  // sticky-keeper branch: intruder rejected, keeper unmoved.
  func testHW51RealIdResolvedCommittedEncounterKeepsStickyKeeper() {
    let a = W5Ownership()
    _ = a.onControl(
      handle: "p1", role: .outbound, myCandidate: "cand-b", peerCandidate: "cand-a",
      peerAlias: aliasB, linkId: "L5")
    commitAgainst(a, "cand-a", [ct("cand-b", "L5")], aliasB)
    XCTAssertEqual(a.committedKeeper("cand-a"), "p1")
    let fx = a.onControl(
      handle: "p2", role: .inbound, myCandidate: "cand-b", peerCandidate: "cand-a",
      peerAlias: "alias-rotated-unknown", linkId: "L0")
    XCTAssertEqual(fx, [.rejectInbound(handle: "p2")])
    XCTAssertEqual(a.committedKeeper("cand-a"), "p1")
    XCTAssertEqual(a.committedLinkId("cand-a"), "L5")
  }

  // H-W5-1 persistence: the stored winner survives a snapshot round-trip.
  func testHW51CommittedWinnerSurvivesSnapshotRestore() {
    let a = W5Ownership()
    _ = a.onControl(
      handle: "p1", role: .outbound, myCandidate: candA, peerCandidate: candB,
      peerAlias: aliasB, linkId: "L1")
    commitAgainst(a, leaseId, [ct("cand-a", "L1")], aliasB)
    let data = a.snapshot()
    let b = W5Ownership()
    _ = b.restore(
      from: data, reconnectGrace: 120, aliasTTL: 900,
      now: Date().timeIntervalSince1970)
    XCTAssertEqual(b.committedKeeper(leaseId), "p1")
    XCTAssertEqual(b.committedLinkId(leaseId), "L1")
  }

  func testAliasRolloverKeepsCurrentPlusPreviousThenExpires() {
    let a = established("L1")
    a.onAliasRoll(leaseId: leaseId, newAlias: "aliasB2")
    XCTAssertEqual(a.leaseForAlias("aliasB2"), leaseId)
    XCTAssertEqual(a.leaseForAlias(aliasB), leaseId)
    a.onPrevAliasExpiry(leaseId: leaseId)
    XCTAssertNil(a.leaseForAlias(aliasB))
  }

  func testTeardownAndBeaconOffEraseEverything() {
    let a = established("L1")
    XCTAssertEqual(a.onTeardown(leaseId: leaseId).last, .ended(leaseId: leaseId))
    XCTAssertEqual(a.activeLeases, 0)
    let b = established("L1")
    XCTAssertEqual(b.onBeaconOff().last, .ended(leaseId: leaseId))
    XCTAssertEqual(b.activeLeases, 0)
    XCTAssertNil(b.leaseForAlias(aliasB))
  }

  // Degenerate inputs.
  func testUnknownEventsAreNoOps() {
    let a = W5Ownership()
    XCTAssertEqual(a.onLinkDown(handle: "ghost"), [])
    XCTAssertEqual(a.onTeardown(leaseId: "ghost"), [])
    XCTAssertEqual(a.onRetryTimer(leaseId: "ghost"), [])
    XCTAssertEqual(
      a.onProposeRecv(
        peerAlias: "ghost",
        proposal: W5Proposal(encounterId: "x", viewGen: 0, contenders: [])),
      [])
  }

  func testProvisionalDialThatNeverHandshakesIsErased() {
    let a = W5Ownership()
    XCTAssertEqual(
      a.onDiscovered(alias: aliasB, wouldDial: true, candidateId: candA, linkId: "L1"),
      [.dial(linkId: "L1")])
    XCTAssertEqual(a.onDialFailed(linkId: "L1"), [.ended(leaseId: candA)])
    XCTAssertEqual(a.activeLeases, 0)
  }

  // MARK: - persistence / restoration

  func testSnapshotRestoreRoundTripPreservesObservations() {
    let a = established("L1")
    commitAgainst(a, leaseId, [ct("cand-a", "L1")], aliasB)
    let snap = a.snapshot()
    let b = W5Ownership()
    XCTAssertTrue(b.restore(from: snap, reconnectGrace: 120, aliasTTL: 900))
    XCTAssertEqual(b.activeLeases, a.activeLeases)
    XCTAssertEqual(b.committedLinkId(leaseId), a.committedLinkId(leaseId))
    XCTAssertEqual(b.committedKeeper(leaseId), a.committedKeeper(leaseId))
    XCTAssertEqual(b.keeperOf(leaseId), a.keeperOf(leaseId))
    XCTAssertEqual(b.leaseForAlias(aliasB), a.leaseForAlias(aliasB))
    XCTAssertEqual(b.currentProposal(leaseId)?.viewGen, a.currentProposal(leaseId)?.viewGen)
  }

  func testRestoreReplayedControlIsIdempotent() {
    let a = established("L1")
    commitAgainst(a, leaseId, [ct("cand-a", "L1")], aliasB)
    let snap = a.snapshot()
    let b = W5Ownership()
    XCTAssertTrue(b.restore(from: snap, reconnectGrace: 120, aliasTTL: 900))
    let fx = b.onControl(
      handle: "p1", role: .outbound, myCandidate: candA, peerCandidate: candB,
      peerAlias: aliasB, linkId: "L1")
    XCTAssertEqual(fx, [.owns(handle: "p1")])
    XCTAssertEqual(b.committedKeeperCount, 1)
  }

  func testStaleGraceSnapshotIsExpiredOnRestore() {
    let a = established("L1")
    _ = a.onLinkDown(handle: "p1") // enters grace
    let snap = a.snapshot()
    let b = W5Ownership()
    let restored = b.restore(
      from: snap, reconnectGrace: 120, aliasTTL: 900,
      now: Date().timeIntervalSince1970 + 121)
    XCTAssertFalse(restored)
    XCTAssertEqual(b.activeLeases, 0)
  }

  func testStaleActiveSnapshotIsExpiredOnRestore() {
    let a = established("L1")
    let snap = a.snapshot()
    let b = W5Ownership()
    let restored = b.restore(
      from: snap, reconnectGrace: 120, aliasTTL: 900,
      now: Date().timeIntervalSince1970 + 901)
    XCTAssertFalse(restored)
    XCTAssertEqual(b.activeLeases, 0)
  }

  func testRestoreNeverRemintsIds() {
    let a = W5Ownership()
    _ = a.onControl(
      handle: "p1", role: .outbound, myCandidate: candA, peerCandidate: candB,
      peerAlias: aliasB, linkId: "L1")
    commitAgainst(a, leaseId, [ct("cand-a", "L1")], aliasB)
    let snap = a.snapshot()
    // The raw snapshot must carry the exact linkId and candidate; restore
    // returns them verbatim — no fresh mint for a live/grace encounter.
    let b = W5Ownership()
    XCTAssertTrue(b.restore(from: snap, reconnectGrace: 120, aliasTTL: 900))
    let contenders = b.currentProposal(leaseId)!.contenders
    XCTAssertEqual(contenders, [ct("cand-a", "L1")])
    // Replaying the same control must not mint a replacement linkId or candidate.
    let fx = b.onControl(
      handle: "p1", role: .outbound, myCandidate: candA, peerCandidate: candB,
      peerAlias: aliasB, linkId: "L1")
    XCTAssertEqual(fx, [.owns(handle: "p1")])
    XCTAssertEqual(b.currentProposal(leaseId)!.contenders, [ct("cand-a", "L1")])
  }
}
