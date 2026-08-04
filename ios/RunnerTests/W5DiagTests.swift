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

#if INRANGE_DIAG
  /// B4: the ONE serialized evidence writer — absent-vs-inaccessible, protection
  /// + backup exclusion after every op, rotation, and bounded drop accounting.
  final class W5EvidenceWriterTests: XCTestCase {
    private let docs = FileManager.default.urls(
      for: .documentDirectory, in: .userDomainMask)[0]
    private func url(_ n: String) -> URL { docs.appendingPathComponent(n) }
    private let names = [
      "ewtest_a.jsonl", "ewtest_b.jsonl", "ewtest_b.1.jsonl", "ewtest_c.txt",
    ]

    override func tearDown() {
      for n in names {
        try? FileManager.default.setAttributes(
          [.posixPermissions: 0o644], ofItemAtPath: url(n).path)
        try? FileManager.default.removeItem(at: url(n))
      }
      super.tearDown()
    }

    func testAbsentFileIsCreatedAndProtectionAppliedWhenReported() throws {
      let name = "ewtest_a.jsonl"
      try? FileManager.default.removeItem(at: url(name))
      let w = W5EvidenceWriter(fileName: name, cap: 1_000_000, rotation: .dotOne)
      XCTAssertTrue(w.append("line1\n"))
      XCTAssertTrue(FileManager.default.fileExists(atPath: url(name).path))
      // Data protection + backup exclusion ARE applied on create, but the iOS
      // Simulator does not report either back (device-only features → nil).
      // Assert them WHEN the platform reports them; the device one-phone
      // preflight is where full enforcement is validated empirically.
      let attrs = try FileManager.default.attributesOfItem(atPath: url(name).path)
      if let prot = attrs[.protectionKey] as? FileProtectionType {
        XCTAssertEqual(prot, .completeUnlessOpen, "protection must be completeUnlessOpen")
      }
      let vals = try url(name).resourceValues(forKeys: [.isExcludedFromBackupKey])
      if let excluded = vals.isExcludedFromBackup {
        XCTAssertTrue(excluded, "must exclude from backup")
      }
      // Append grows the SAME file (never a fresh single-line replacement).
      XCTAssertTrue(w.append("line2\n"))
      XCTAssertEqual(
        try String(contentsOf: url(name), encoding: .utf8), "line1\nline2\n")
    }

    func testInaccessibleExistingFileIsDroppedNotOverwritten() throws {
      let name = "ewtest_c.txt"
      let path = url(name).path
      try "PRESERVE".data(using: .utf8)!.write(to: url(name))
      // Unwritable existing file → FileHandle(forWritingTo:) fails → the writer
      // must treat it as inaccessible (drop), NOT absent (overwrite).
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o444], ofItemAtPath: path)
      let w = W5EvidenceWriter(fileName: name, cap: 1_000_000, rotation: .dotOne)
      XCTAssertFalse(w.append("SHOULD-NOT-APPEAR\n"))
      XCTAssertGreaterThan(w.dropped, 0, "an inaccessible write must be counted")
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o644], ofItemAtPath: path)
      XCTAssertEqual(
        try String(contentsOf: url(name), encoding: .utf8), "PRESERVE",
        "existing content must NOT be replaced by a single line")
    }

    func testRotationMovesFullFileToDotOne() throws {
      let name = "ewtest_b.jsonl"
      try? FileManager.default.removeItem(at: url(name))
      try? FileManager.default.removeItem(at: url("ewtest_b.1.jsonl"))
      let w = W5EvidenceWriter(fileName: name, cap: 10, rotation: .dotOne)
      XCTAssertTrue(w.append("AAAAAAAAAAAA\n"))  // 13 bytes > cap
      XCTAssertTrue(w.append("B\n"))  // over cap → rotate first, then write fresh
      XCTAssertEqual(
        try String(contentsOf: url("ewtest_b.1.jsonl"), encoding: .utf8),
        "AAAAAAAAAAAA\n", "old file rotated to .1")
      XCTAssertEqual(
        try String(contentsOf: url(name), encoding: .utf8), "B\n",
        "new file holds only the newest line")
    }

    func testDrainPriorDroppedSumsAndResetsEveryFamily() {
      let d = UserDefaults(suiteName: "io.inrange.diag")
      d?.set(3, forKey: "bb.evwrite.dropped.w5_events.jsonl")
      d?.set(2, forKey: "bb.evwrite.dropped.bb_wake_log.txt")
      d?.set(1, forKey: "bb.evwrite.dropped.w5_rssi_log.jsonl")
      XCTAssertEqual(W5EvidenceWriter.drainPriorDropped(), 6)
      XCTAssertEqual(W5EvidenceWriter.drainPriorDropped(), 0, "reset after drain")
    }
  }
#endif
