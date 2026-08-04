import CommonCrypto
import XCTest

@testable import Runner

/// Flavor-aware tests for the structured diagnostic layer (Phase 2/4). The
/// public API (`emit`, `armFault`, `consumePreAckFault`) exists in BOTH
/// flavors; its BEHAVIOR differs by `INRANGE_DIAG`. This suite runs under the
/// Runner scheme (no INRANGE_DIAG) AND the diag scheme (INRANGE_DIAG) and
/// asserts the correct behavior for each.
final class W5DiagTests: XCTestCase {

  func testFaultArmConsumeIsFlavorCorrect() {
    #if INRANGE_DIAG
      // Armed for a specific peer → the next matching consume fires once.
      W5Diag.armFault(peerRaw: "peer-token-1")
      XCTAssertTrue(W5Diag.consumePreAckFault(peerRaw: "peer-token-1"))
      XCTAssertFalse(W5Diag.consumePreAckFault(peerRaw: "peer-token-1"),
        "one-shot: must not fire twice")
      // Wildcard arm fires for any next dial, once.
      W5Diag.armFault(peerRaw: nil)
      XCTAssertTrue(W5Diag.consumePreAckFault(peerRaw: "anyone"))
      XCTAssertFalse(W5Diag.consumePreAckFault(peerRaw: "anyone"))
    #else
      // Production: arming and consuming are no-ops; never fires.
      W5Diag.armFault(peerRaw: "peer-token-1")
      XCTAssertFalse(W5Diag.consumePreAckFault(peerRaw: "peer-token-1"),
        "release build must never inject a fault")
    #endif
  }

  #if INRANGE_DIAG
    /// Independent re-implementation of W5Diag.handle's truncated HMAC-SHA256
    /// (domain\0raw, 14 hex) to prove the injected secret is the one in use.
    static func expectedHandle(domain: String, raw: String, secretHex: String)
      -> String
    {
      var key = [UInt8]()
      var i = secretHex.startIndex
      while i < secretHex.endIndex {
        let n = secretHex.index(i, offsetBy: 2, limitedBy: secretHex.endIndex)
          ?? secretHex.endIndex
        key.append(UInt8(secretHex[i..<n], radix: 16) ?? 0)
        i = n
      }
      var msg = Data(domain.utf8)
      msg.append(0)
      msg.append(Data(raw.utf8))
      var mac = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
      key.withUnsafeBytes { k in
        msg.withUnsafeBytes { m in
          CCHmac(
            CCHmacAlgorithm(kCCHmacAlgSHA256), k.baseAddress, k.count,
            m.baseAddress, m.count, &mac)
        }
      }
      return mac.prefix(7).map { String(format: "%02x", $0) }.joined()
    }

    // B3: the run secret in use under the diag scheme is the INJECTED env
    // secret (fleet alignment), not a per-process random. The diag scheme sets
    // INRANGE_DIAG_RUN_SECRET; handles must equal the truncated HMAC-SHA256
    // computed with THAT secret — proving the injection path is wired.
    func testHandleUsesInjectedRunSecret() throws {
      guard let hex = ProcessInfo.processInfo.environment["INRANGE_DIAG_RUN_SECRET"],
        hex.count >= 32
      else {
        throw XCTSkip("diag scheme did not inject INRANGE_DIAG_RUN_SECRET")
      }
      let got = W5Diag.handle("peer", "tok-A")
      let want = Self.expectedHandle(domain: "peer", raw: "tok-A", secretHex: hex)
      XCTAssertEqual(got, want, "handle must use the injected fleet secret")
    }

    // B3: provisioning API persists a valid fleet secret to the diag suite and
    // rejects malformed input (so a bad dart-define can't wipe alignment).
    func testProvisionRunSecretPersistsAndValidates() {
      let suite = UserDefaults(suiteName: "io.inrange.diag")
      let key = "bb.w5diag.provisionedsecret"
      suite?.removeObject(forKey: key)
      W5Diag.provisionRunSecret("zz")  // too short / non-hex → ignored
      XCTAssertNil(suite?.string(forKey: key))
      let valid = String(repeating: "a1", count: 32)  // 64 hex
      W5Diag.provisionRunSecret(valid)
      XCTAssertEqual(suite?.string(forKey: key), valid)
      suite?.removeObject(forKey: key)
    }

    func testHandleDeterminismAndDomainSeparation() {
      let a = W5Diag.handle("peer", "tok-A")
      let b = W5Diag.handle("peer", "tok-A")
      XCTAssertEqual(a, b, "same domain+raw → same handle within a run")
      XCTAssertEqual(a?.count, 14, "truncated HMAC = 14 hex")
      // Domain separation: same raw under different domains → different handle.
      XCTAssertNotEqual(
        W5Diag.handle("peer", "x"), W5Diag.handle("lease", "x"),
        "domain-separated: peer\\0x != lease\\0x")
      // Different raw → different handle.
      XCTAssertNotEqual(W5Diag.handle("peer", "tok-A"), W5Diag.handle("peer", "tok-B"))
      // Empty/nil raw → no handle (never emit a handle for absent id).
      XCTAssertNil(W5Diag.handle("peer", nil))
      XCTAssertNil(W5Diag.handle("peer", ""))
      // Handle is not the raw value (irreversibility smoke: not a prefix).
      XCTAssertFalse("tok-A".hasPrefix(a ?? "tok-A"))
    }
  #endif
}
