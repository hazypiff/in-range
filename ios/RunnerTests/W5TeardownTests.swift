import XCTest

@testable import Runner

/// H-W5-6 Phase 1 — the teardown matrix. Tests the alias→lease resolution
/// (the miss guard that stops a server encounter_id from acting as an alias)
/// plus the structured result derivation from onTeardown effects. The
/// controller's `dropPeer(alias:)` is a thin wrapper: `leaseForAlias` +
/// `W5TeardownResult.from(hit:effects:)` over `onTeardown`, exercised here.
private let candA = "cand-a"
private let candB = "cand-b"
private let aliasB = "aliasB"

private func ct(_ c: String, _ l: String) -> W5Contender {
  W5Contender(central: c, linkId: l)
}

private func commit(
  _ a: W5Ownership, _ lease: String, _ set: [W5Contender], _ alias: String
) {
  let mine = a.currentProposal(lease)!
  _ = a.onProposeRecv(
    peerAlias: alias, proposal: W5Proposal(encounterId: lease, viewGen: 7, contenders: set))
  _ = a.onAckRecv(
    peerAlias: alias, ack: W5Ack(encounterId: lease, ackViewGen: mine.viewGen, viewHash: mine.viewHash))
}

/// Resolve + tear down exactly as W5LinkController.dropPeer does.
private func teardown(_ a: W5Ownership, alias: String) -> W5TeardownResult {
  guard let lease = a.leaseForAlias(alias) else {
    return W5TeardownResult.from(hit: false, effects: [])
  }
  return W5TeardownResult.from(hit: true, effects: a.onTeardown(leaseId: lease))
}

final class W5TeardownTests: XCTestCase {

  // MISS: an unknown alias (e.g. a server encounter_id mislabeled as an alias)
  // resolves to nothing → lookupHit false, nothing closed, nothing ended.
  func testServerIdOrUnknownAliasIsAMiss() {
    let a = W5Ownership()
    _ = a.onControl(
      handle: "p1", role: .outbound, myCandidate: candA, peerCandidate: candB,
      peerAlias: aliasB, linkId: "L1")
    commit(a, candA, [ct("cand-a", "L1")], aliasB)
    // "12345" is an encounter_id, never a radio alias.
    let r = teardown(a, alias: "12345")
    XCTAssertFalse(r.lookupHit)
    XCTAssertTrue(r.rolesClosed.isEmpty)
    XCTAssertFalse(r.leaseEnded)
    // And the real lease is untouched.
    XCTAssertEqual(a.committedKeeper(candA), "p1")
  }

  // LOCAL HIT (outbound keeper): alias resolves, outbound link closed, ended.
  func testLocalHitOutboundKeeper() {
    let a = W5Ownership()
    _ = a.onControl(
      handle: "p1", role: .outbound, myCandidate: candA, peerCandidate: candB,
      peerAlias: aliasB, linkId: "L1")
    commit(a, candA, [ct("cand-a", "L1")], aliasB)
    let r = teardown(a, alias: aliasB)
    XCTAssertTrue(r.lookupHit)
    XCTAssertEqual(r.rolesClosed, ["outbound"])
    XCTAssertTrue(r.leaseEnded)
    XCTAssertEqual(a.activeLeases, 0)
  }

  // INBOUND-ONLY: a single inbound keeper is rejected on teardown.
  func testInboundOnly() {
    let a = W5Ownership()
    _ = a.onControl(
      handle: "in1", role: .inbound, myCandidate: candA, peerCandidate: candB,
      peerAlias: aliasB, linkId: "L1")
    commit(a, candA, [ct("cand-b", "L1")], aliasB)
    let r = teardown(a, alias: aliasB)
    XCTAssertTrue(r.lookupHit)
    XCTAssertEqual(r.rolesClosed, ["inbound"])
    XCTAssertTrue(r.leaseEnded)
  }

  // TWO-ROLE: both an outbound and an inbound link close, role-correct + ended.
  func testTwoRoleTeardown() {
    let a = W5Ownership()
    _ = a.onControl(
      handle: "p1", role: .outbound, myCandidate: candA, peerCandidate: candB,
      peerAlias: aliasB, linkId: "L1")
    _ = a.onControl(
      handle: "p2", role: .inbound, myCandidate: candA, peerCandidate: candB,
      peerAlias: aliasB, linkId: "L2")
    let r = teardown(a, alias: aliasB)
    XCTAssertTrue(r.lookupHit)
    XCTAssertEqual(Set(r.rolesClosed), ["outbound", "inbound"])
    XCTAssertEqual(r.rolesClosed.count, 2)
    XCTAssertTrue(r.leaseEnded)
    XCTAssertEqual(a.activeLeases, 0)
  }

  // STALE ALIAS: an alias that WAS live but whose lease already ended → miss.
  func testStaleAliasAfterTeardownIsAMiss() {
    let a = W5Ownership()
    _ = a.onControl(
      handle: "p1", role: .outbound, myCandidate: candA, peerCandidate: candB,
      peerAlias: aliasB, linkId: "L1")
    commit(a, candA, [ct("cand-a", "L1")], aliasB)
    _ = teardown(a, alias: aliasB)  // first teardown ends it
    let r = teardown(a, alias: aliasB)  // second: alias no longer maps
    XCTAssertFalse(r.lookupHit)
    XCTAssertFalse(r.leaseEnded)
  }

  // REAL CONTROLLER ENTRY (B1): drive the actual W5LinkController.dropPeer, not
  // a reconstruction. An unknown/rotated/stale alias on a controller with no
  // live lease must miss through the real method — nothing torn down.
  func testControllerDropPeerRealEntryMissesUnknownAlias() {
    // Hold a STRONG ref: W5LinkController.bb is `unowned`, so a temporary
    // BackgroundBeacon() would be freed right after init and any bb access
    // would crash (unowned-read-after-free).
    let bb = BackgroundBeacon()
    let ctl = W5LinkController(bb: bb)
    withExtendedLifetime(bb) {
      let r = ctl.dropPeer(alias: "12345")  // encounter_id-shaped, never an alias
      XCTAssertFalse(r.lookupHit)
      XCTAssertTrue(r.rolesClosed.isEmpty)
      XCTAssertFalse(r.leaseEnded)
      // Idempotent: a second real call is still a clean miss.
      let r2 = ctl.dropPeer(alias: "aabbccddeeff00112233445566778899")
      XCTAssertFalse(r2.lookupHit)
    }
  }

  // REAL CONTROLLER HIT (B1): a genuinely live, established lease seeded into
  // the controller is torn down through the REAL dropPeer path — hit, role
  // closed, lease ended, ownership emptied — and a repeat is then a clean miss.
  func testControllerDropPeerRealHitTearsDownLiveLease() {
    // Strong ref (see above): the seed's apply()/requestPersist dereferences the
    // unowned bb, so a temporary would crash.
    let bb = BackgroundBeacon()
    let ctl = W5LinkController(bb: bb)
    withExtendedLifetime(bb) {
      ctl.testSeedOutboundLink(
        peripheralID: UUID(), myCand: "cand-a", peerCand: "cand-b",
        alias: "aliasB", linkId: "L1")
      XCTAssertEqual(ctl.testActiveLeaseCount, 1, "seed established a live lease")
      XCTAssertTrue(ctl.testIsCommitted(alias: "aliasB"),
        "seed COMMITTED the lease (propose+ack), not merely established")
      let r = ctl.dropPeer(alias: "aliasB")
      XCTAssertTrue(r.lookupHit, "a genuinely committed lease is a HIT")
      XCTAssertTrue(r.leaseEnded)
      XCTAssertEqual(r.rolesClosed, ["outbound"])
      XCTAssertEqual(ctl.testActiveLeaseCount, 0, "lease erased")
      XCTAssertFalse(ctl.dropPeer(alias: "aliasB").lookupHit, "repeat is a miss")
    }
  }

  // REAL CHANNEL COMMITTED HIT (B1): a genuinely committed lease torn down
  // through BackgroundBeacon.dropPeerByToken — the exact boundary Dart invokes —
  // not just the controller. Diag-only: the w5Link gate is compile-false
  // otherwise.
  #if INRANGE_DIAG
    func testChannelDropPeerByTokenCommittedHit() {
      let bb = BackgroundBeacon()
      withExtendedLifetime(bb) {
        // W5 is enable-able only with a real fleet key provisioned (native
        // fail-closed gate), so the seed exercises the REAL w5Link path.
        W5Diag.provisionRunSecret(String(repeating: "ab", count: 32))
        bb.testEnableW5Links()
        bb.w5Link.testSeedOutboundLink(
          peripheralID: UUID(), myCand: "cand-a", peerCand: "cand-b",
          alias: "aliasZ", linkId: "L9")
        XCTAssertTrue(bb.w5Link.testIsCommitted(alias: "aliasZ"))
        let d = bb.dropPeerByToken("aliasZ")
        XCTAssertEqual(d["lookupHit"] as? Bool, true, "committed lease → hit")
        XCTAssertEqual(d["leaseEnded"] as? Bool, true)
        XCTAssertEqual(d["rolesClosed"] as? [String], ["outbound"])
        // No raw CA5E session was seeded (needs a CBPeripheral), so 0 reaped;
        // the reap loop itself is exercised by the field soak.
        XCTAssertEqual(d["rawSessionsReaped"] as? Int, 0)
        // A server-id-shaped token remains inert through the same real boundary.
        let miss = bb.dropPeerByToken("0badc0de5758583300000000deadbeef")
        XCTAssertEqual(miss["lookupHit"] as? Bool, false)
      }
    }
  #endif

  // REAL CHANNEL ENTRY (B1): the platform-channel handler itself. A server
  // encounter_id fed through dropPeerByToken tears down nothing and reaps no
  // raw sessions — the H-W5-6 guarantee at the real boundary Dart calls.
  func testChannelDropPeerByTokenServerIdIsInert() {
    let dict = BackgroundBeacon().dropPeerByToken("0badc0de5758583300000000deadbeef")
    XCTAssertEqual(dict["lookupHit"] as? Bool, false)
    XCTAssertEqual(dict["leaseEnded"] as? Bool, false)
    XCTAssertEqual(dict["rawSessionsReaped"] as? Int, 0)
    XCTAssertEqual((dict["rolesClosed"] as? [String])?.isEmpty, true)
    // No raw identifier ever appears in the structured result.
    XCTAssertNil(dict["alias"])
    XCTAssertNil(dict["token"])
  }

  // Result → dict shape (channel contract, no raw ids).
  func testResultDictShape() {
    let r = W5TeardownResult.from(
      hit: true, effects: [.closeOutbound(handle: "p1"), .ended(leaseId: "x")])
    let d = r.asDict
    XCTAssertEqual(d["lookupHit"] as? Bool, true)
    XCTAssertEqual(d["rolesClosed"] as? [String], ["outbound"])
    XCTAssertEqual(d["leaseEnded"] as? Bool, true)
    XCTAssertNil(d["handle"])  // never leaks raw identifiers
  }
}
