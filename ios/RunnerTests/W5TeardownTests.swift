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
