import XCTest

@testable import Runner

/// Ownership conformance — driven by the SHARED, hand-written vectors
/// (test/features/beacon/w5_ownership_vectors.json, bundled as a resource),
/// the same file the Dart suite consumes (round-7 fix #4). Pins semantics
/// across both oracles, independent of either implementation's output.
final class W5OwnershipVectorTests: XCTestCase {

  private func loadDoc() throws -> [String: Any] {
    let url = try XCTUnwrap(
      Bundle(for: W5OwnershipVectorTests.self).url(
        forResource: "w5_ownership_vectors", withExtension: "json"),
      "w5_ownership_vectors.json missing from test bundle resources")
    return try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
  }

  private func run(_ a: W5Ownership, _ step: [String: Any]) throws -> [W5Effect] {
    func str(_ k: String) -> String { step[k] as! String }
    switch str("event") {
    case "discovered":
      return a.onDiscovered(
        alias: str("alias"), wouldDial: step["wouldDial"] as! Bool,
        candidateId: str("candidateId"), linkId: str("linkId"))
    case "control":
      return a.onControl(
        handle: str("handle"),
        role: str("role") == "outbound" ? .outbound : .inbound,
        myCandidate: str("myCandidate"), peerCandidate: str("peerCandidate"),
        peerAlias: str("peerAlias"), linkId: str("linkId"),
        peerPrevAlias: step["peerPrevAlias"] as? String)
    case "proposeRecv":
      let contenders = (step["contenders"] as! [[String]]).map {
        W5Contender(central: $0[0], linkId: $0[1])
      }
      return a.onProposeRecv(
        peerAlias: str("peerAlias"),
        proposal: W5Proposal(
          encounterId: str("encounterId"), viewGen: step["viewGen"] as! Int,
          contenders: contenders))
    case "ackCurrent":
      let lease = try XCTUnwrap(a.leaseForAlias(str("peerAlias")))
      let cur = try XCTUnwrap(a.currentProposal(lease))
      return a.onAckRecv(
        peerAlias: str("peerAlias"),
        ack: W5Ack(
          encounterId: cur.encounterId, ackViewGen: cur.viewGen,
          viewHash: cur.viewHash))
    case "linkDown":
      return a.onLinkDown(handle: str("handle"))
    case "dialFailed":
      return a.onDialFailed(linkId: str("linkId"))
    case "aliasRoll":
      a.onAliasRoll(leaseId: str("leaseId"), newAlias: str("newAlias"))
      return []
    case "prevAliasExpiry":
      a.onPrevAliasExpiry(leaseId: str("leaseId"))
      return []
    case "retryTimer":
      return a.onRetryTimer(leaseId: str("leaseId"))
    case "beaconOff":
      return a.onBeaconOff()
    case "teardown":
      return a.onTeardown(leaseId: str("leaseId"))
    case "graceExpiry":
      return a.onGraceExpiry(leaseId: str("leaseId"))
    default:
      throw NSError(domain: "vector", code: 1)
    }
  }

  private func matchEffects(_ got: [W5Effect], _ expected: [[String: Any]], _ ctx: String) {
    XCTAssertEqual(got.count, expected.count, "\(ctx): effect count (got \(got))")
    guard got.count == expected.count else { return }
    for (i, e) in expected.enumerated() {
      let g = got[i]
      switch e["kind"] as! String {
      case "dial":
        XCTAssertEqual(g, .dial(linkId: e["linkId"] as! String), ctx)
      case "owns":
        XCTAssertEqual(g, .owns(handle: e["handle"] as! String), ctx)
      case "closeOutbound":
        XCTAssertEqual(g, .closeOutbound(handle: e["handle"] as! String), ctx)
      case "rejectInbound":
        XCTAssertEqual(g, .rejectInbound(handle: e["handle"] as! String), ctx)
      case "ended":
        XCTAssertEqual(g, .ended(leaseId: e["leaseId"] as! String), ctx)
      case "sendPropose":
        if case .sendPropose(_, let routes) = g {
          if let want = e["routes"] as? [String] {
            XCTAssertEqual(routes.map { $0.handle }, want, "\(ctx): propose routes")
          }
        } else { XCTFail("\(ctx): expected sendPropose, got \(g)") }
      case "sendAck":
        if case .sendAck(_, let route) = g {
          if let want = e["route"] as? String {
            XCTAssertEqual(route.handle, want, "\(ctx): ack route")
          }
        } else { XCTFail("\(ctx): expected sendAck, got \(g)") }
      default:
        XCTFail("\(ctx): unknown expected kind")
      }
    }
  }

  func testAllVectors() throws {
    let doc = try loadDoc()
    for v in doc["vectors"] as! [[String: Any]] {
      let name = v["name"] as! String
      let a = W5Ownership()
      for (i, step) in (v["steps"] as! [[String: Any]]).enumerated() {
        let fx = try run(a, step)
        if let expected = step["expectEffects"] as? [[String: Any]] {
          matchEffects(fx, expected, "\(name) step \(i)")
        }
      }
      let obs = v["finalObs"] as! [String: Any]
      if let n = obs["activeLeases"] as? Int {
        XCTAssertEqual(a.activeLeases, n, "\(name): activeLeases")
      }
      for (lease, link) in obs["committed"] as? [String: String] ?? [:] {
        XCTAssertEqual(a.committedLinkId(lease), link, "\(name): committed[\(lease)]")
      }
      for (alias, lease) in obs["leaseForAlias"] as? [String: String] ?? [:] {
        XCTAssertEqual(a.leaseForAlias(alias), lease, "\(name): leaseForAlias[\(alias)]")
      }
      for (lease, h) in obs["keeperOf"] as? [String: String] ?? [:] {
        XCTAssertEqual(a.keeperOf(lease), h, "\(name): keeperOf[\(lease)]")
      }
      for (lease, n) in obs["viewGenAtLeast"] as? [String: Int] ?? [:] {
        let gen = try XCTUnwrap(a.currentProposal(lease)).viewGen
        XCTAssertGreaterThanOrEqual(gen, n, "\(name): viewGen[\(lease)]")
      }
    }
  }
}
