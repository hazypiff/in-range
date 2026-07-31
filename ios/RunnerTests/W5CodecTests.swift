import XCTest

@testable import Runner

/// CA6E codec conformance — driven by the SAME vectors file as the Dart suite
/// (test/features/beacon/w5_codec_vectors.json, added to this test bundle as a
/// resource). The setHash anchor is independently computed (python hashlib),
/// so Dart and Swift are pinned to an external reference, not to each other.
final class W5CodecTests: XCTestCase {

  private var vectors: [String: Any] = [:]

  override func setUpWithError() throws {
    let url = try XCTUnwrap(
      Bundle(for: W5CodecTests.self).url(
        forResource: "w5_codec_vectors", withExtension: "json"),
      "w5_codec_vectors.json missing from test bundle resources")
    vectors = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
  }

  private func unhex(_ h: String) -> Data {
    var out = Data()
    var i = h.startIndex
    while i < h.endIndex {
      let j = h.index(i, offsetBy: 2)
      out.append(UInt8(h[i..<j], radix: 16)!)
      i = j
    }
    return out
  }

  private func hexOf(_ d: Data) -> String {
    d.map { String(format: "%02x", $0) }.joined()
  }

  private func buildMsg(_ type: String, _ f: [String: Any]) throws -> W5WireMsg {
    func d(_ k: String) -> Data { unhex(f[k] as! String) }
    func gen() -> UInt32 { UInt32(f["viewGen"] as! Int) }
    func contenders() -> [W5WireContender] {
      (f["contenders"] as! [[String: String]]).map {
        W5WireContender(central: unhex($0["central"]!), linkId: unhex($0["linkId"]!))
      }
    }
    switch type {
    case "hello":
      return .hello(
        linkId: d("linkId"), centralCandidate: d("centralCandidate"),
        currentAlias: d("currentAlias"), prevAlias: d("prevAlias"))
    case "helloAck":
      return .helloAck(
        linkId: d("linkId"), peripheralCandidate: d("peripheralCandidate"),
        peripheralAlias: d("peripheralAlias"))
    case "propose":
      return .propose(encounterId: d("encounterId"), viewGen: gen(), contenders: contenders())
    case "proposeAck":
      return .proposeAck(encounterId: d("encounterId"), viewGen: gen(), setHash: d("setHash"))
    case "reject":
      return .reject(encounterId: d("encounterId"), viewGen: gen(), linkId: d("linkId"))
    case "aliasRoll":
      return .aliasRoll(newAlias: d("newAlias"))
    case "bye":
      return .bye
    default:
      throw W5CodecError.contract("unknown vector type \(type)")
    }
  }

  func testConstantsAgreeWithVectors() {
    XCTAssertEqual(vectors["version"] as? Int, Int(kW5CodecVersion))
    XCTAssertEqual(vectors["maxContenders"] as? Int, kW5CodecMaxContenders)
    XCTAssertEqual(vectors["maxFrame"] as? Int, kW5MaxFrame)
  }

  func testPositiveVectorsRoundTrip() throws {
    for v in vectors["positives"] as! [[String: Any]] {
      let name = v["name"] as! String
      let msg = try buildMsg(v["type"] as! String, v["fields"] as! [String: Any])
      let frameHex = v["frame"] as! String
      let encoded = try w5Encode(msg)
      XCTAssertEqual(hexOf(encoded), frameHex, "encode: \(name)")
      if let expLen = v["expectFrameLen"] as? Int {
        XCTAssertEqual(encoded.count, expLen, "frame len: \(name)")
      }
      guard case .ok(let decoded) = w5Decode(unhex(frameHex)) else {
        return XCTFail("decode failed: \(name)")
      }
      XCTAssertEqual(decoded, msg, "decoded fields: \(name)")
      XCTAssertEqual(hexOf(try w5Encode(decoded)), frameHex, "re-encode: \(name)")
    }
  }

  func testNegativeVectors() {
    for v in vectors["negatives"] as! [[String: Any]] {
      let name = v["name"] as! String
      let result = w5Decode(unhex(v["frame"] as! String))
      switch v["expect"] as! String {
      case "legacy":
        guard case .legacyVersion = result else {
          return XCTFail("\(name): expected legacy fallback, got \(result)")
        }
      case "violation":
        guard case .violation = result else {
          return XCTFail("\(name): expected violation, got \(result)")
        }
      default:
        XCTFail("unknown expectation in \(name)")
      }
    }
  }

  func testSetHashMatchesIndependentAnchor() {
    let a = vectors["setHashAnchor"] as! [String: Any]
    let contenders = (a["contenders"] as! [[String: String]]).map {
      W5WireContender(central: unhex($0["central"]!), linkId: unhex($0["linkId"]!))
    }
    let got = w5SetHash(
      encounterId: unhex(a["encounterId"] as! String),
      viewGen: UInt32(a["viewGen"] as! Int),
      contenders: contenders)
    XCTAssertEqual(hexOf(got), a["expected"] as! String)
    // Order-invariance: the hash sorts canonically inside.
    let reversedHash = w5SetHash(
      encounterId: unhex(a["encounterId"] as! String),
      viewGen: UInt32(a["viewGen"] as! Int),
      contenders: contenders.reversed())
    XCTAssertEqual(hexOf(reversedHash), a["expected"] as! String)
  }

  func testEncoderRefusesOutOfContractInput() {
    let id = Data(repeating: 0, count: 16)
    XCTAssertThrowsError(try w5Encode(.propose(
      encounterId: Data(repeating: 0, count: 15), viewGen: 0, contenders: [])))
    let six = (0..<6).map {
      W5WireContender(
        central: Data(repeating: UInt8($0), count: 16),
        linkId: Data(repeating: UInt8($0 + 0x80), count: 16))
    }
    XCTAssertThrowsError(try w5Encode(.propose(
      encounterId: id, viewGen: 0, contenders: six)))
  }
}
