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
      W5Diag.disarmFault()
      // Armed for a specific peer → the next matching consume fires once.
      W5Diag.armFault(peerRaw: "peer-token-1")
      XCTAssertTrue(W5Diag.isFaultArmed)
      XCTAssertTrue(W5Diag.consumePreAckFault(peerRaw: "peer-token-1"))
      XCTAssertFalse(W5Diag.consumePreAckFault(peerRaw: "peer-token-1"),
        "one-shot: must not fire twice")
      XCTAssertFalse(W5Diag.isFaultArmed, "consumed → disarmed")
      // Peer-scoped: armed for peer-1 must NOT fire for a different peer.
      W5Diag.armFault(peerRaw: "peer-token-1")
      XCTAssertFalse(W5Diag.consumePreAckFault(peerRaw: "peer-token-2"),
        "peer-scoped: must not fire for another peer")
      XCTAssertTrue(W5Diag.isFaultArmed, "still armed for its target")
      // Disarm clears a pending fault so it can't fire later.
      W5Diag.disarmFault()
      XCTAssertFalse(W5Diag.isFaultArmed)
      XCTAssertFalse(W5Diag.consumePreAckFault(peerRaw: "peer-token-1"),
        "disarmed → never fires")
      // NO WILDCARD: a nil/empty target is REJECTED (fail closed), never armed.
      XCTAssertEqual(W5Diag.armFault(peerRaw: nil)["ok"] as? Bool, false)
      XCTAssertFalse(W5Diag.isFaultArmed, "nil target must not arm anything")
      XCTAssertFalse(W5Diag.consumePreAckFault(peerRaw: "anyone"),
        "no wildcard — an unrelated dial must not fire")
    #else
      // Production: arming and consuming are no-ops; never fires.
      W5Diag.armFault(peerRaw: "peer-token-1")
      XCTAssertFalse(W5Diag.isFaultArmed)
      XCTAssertFalse(W5Diag.consumePreAckFault(peerRaw: "peer-token-1"),
        "release build must never inject a fault")
      W5Diag.disarmFault()  // no-op, must compile + not crash
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

    // B4: seq is assigned in the SAME critical section as the append, so a
    // line's seq always matches its file order (monotonic, no interleave).
    func testEventSeqMatchesFileOrder() throws {
      let docs = FileManager.default.urls(
        for: .documentDirectory, in: .userDomainMask)[0]
      let url = docs.appendingPathComponent("w5_events.jsonl")
      try? FileManager.default.removeItem(at: url)
      try? FileManager.default.removeItem(
        at: docs.appendingPathComponent("w5_events.1.jsonl"))
      for _ in 0..<6 { W5Diag.emit(.beat, role: .app) }
      let lines = try String(contentsOf: url, encoding: .utf8)
        .split(separator: "\n", omittingEmptySubsequences: true)
      XCTAssertEqual(lines.count, 6)
      var seqs: [Int] = []
      for l in lines {
        let obj = try JSONSerialization.jsonObject(with: Data(l.utf8))
          as! [String: Any]
        seqs.append((obj["seq"] as? NSNumber)?.intValue ?? -1)
      }
      XCTAssertEqual(seqs, seqs.sorted(), "seq monotonic in file order")
      for i in 1..<seqs.count {
        XCTAssertGreaterThan(seqs[i], seqs[i - 1], "strictly increasing")
      }
    }

    // B3 owner ruling: resetCase RETAINS the fleet secret and rotates the
    // PUBLIC case epoch. The handle is unchanged across reset (same secret);
    // caseEpoch increments; controls + counters clear.
    func testResetCaseRetainsSecretRotatesEpochClearsControls() {
      let sec = String(repeating: "cd", count: 32)  // 64 hex
      W5Diag.provisionRunSecret(sec)
      let want = Self.expectedHandle(domain: "peer", raw: "z", secretHex: sec)
      XCTAssertEqual(W5Diag.handle("peer", "z"), want, "provision sets the key")
      W5Diag.armFault(peerRaw: "p")
      W5Diag.armHelloDelay(3)
      let before = W5Diag.caseEpoch
      let ack = W5Diag.resetCase()
      XCTAssertEqual(ack["ok"] as? Bool, true)
      XCTAssertEqual(ack["secretRetained"] as? Bool, true)
      XCTAssertEqual(W5Diag.handle("peer", "z"), want,
        "secret RETAINED across resetCase (owner ruling)")
      XCTAssertEqual(W5Diag.caseEpoch, before + 1, "case epoch rotated")
      XCTAssertFalse(W5Diag.isFaultArmed, "controls cleared")
      XCTAssertEqual(W5Diag.consumeHelloDelay(), 0, "delay cleared")
    }

    // B3 owner ruling: destroySessionSecret is REJECTED while W5 is active, and
    // succeeds while stopped (the only secret-clearing op).
    func testDestroySecretRejectedWhileW5ActiveAllowedWhenStopped() {
      W5Diag.provisionRunSecret(String(repeating: "ab", count: 32))
      XCTAssertEqual(
        W5Diag.destroySessionSecret(w5Active: true)["rejected"] as? String,
        "w5-active", "must refuse while W5 is up")
      let ok = W5Diag.destroySessionSecret(w5Active: false)
      XCTAssertEqual(ok["ok"] as? Bool, true)
      XCTAssertEqual(ok["secretDestroyed"] as? Bool, true)
    }

    // B3: a short/odd/non-hex secret must NOT mutate state.
    func testInvalidSecretDoesNotMutateState() {
      W5Diag.provisionRunSecret(String(repeating: "cd", count: 32))
      let good = W5Diag.handle("peer", "z")
      XCTAssertEqual(W5Diag.provisionRunSecret("zz")["ok"] as? Bool, false)
      XCTAssertEqual(W5Diag.provisionRunSecret("abc")["ok"] as? Bool, false)  // odd
      XCTAssertEqual(W5Diag.provisionRunSecret("ab")["ok"] as? Bool, false)  // short
      XCTAssertEqual(W5Diag.handle("peer", "z"), good, "state unchanged")
    }

    // B3: provisioning a DIFFERENT key mid-session rotates the key epoch.
    func testKeyChangeRotatesKeyEpoch() {
      W5Diag.provisionRunSecret(String(repeating: "cd", count: 32))
      let e0 = W5Diag.keyEpoch
      let r = W5Diag.provisionRunSecret(String(repeating: "ef", count: 32))
      XCTAssertEqual(r["rotated"] as? Bool, true)
      XCTAssertEqual(W5Diag.keyEpoch, e0 + 1, "different key → new key epoch")
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
      "ewtest_conc.jsonl",
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
        // completeUntilFirstUserAuthentication: writable while the phone is
        // locked (after first unlock) — required for background soak evidence.
        XCTAssertEqual(prot, .completeUntilFirstUserAuthentication,
          "protection must allow locked-state writes")
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

    func testManyAppendsPreserveOrderAndEveryLine() throws {
      let name = "ewtest_a.jsonl"
      try? FileManager.default.removeItem(at: url(name))
      let w = W5EvidenceWriter(fileName: name, cap: 1_000_000, rotation: .dotOne)
      for i in 0..<200 { XCTAssertTrue(w.append("line\(i)\n")) }
      let lines = try String(contentsOf: url(name), encoding: .utf8)
        .split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
      XCTAssertEqual(lines.count, 200, "every appended line present")
      XCTAssertEqual(lines.first, "line0")
      XCTAssertEqual(lines.last, "line199", "chronological order preserved")
    }

    // B4: truly concurrent appends from many threads are serialized by the
    // writer lock — every line lands exactly once, none torn or lost.
    func testConcurrentAppendsAreSerializedAndComplete() {
      let name = "ewtest_conc.jsonl"
      try? FileManager.default.removeItem(at: url(name))
      let w = W5EvidenceWriter(fileName: name, cap: 10_000_000, rotation: .dotOne)
      let group = DispatchGroup()
      let q = DispatchQueue(label: "ewtest.conc", attributes: .concurrent)
      let threads = 16, per = 40
      for t in 0..<threads {
        q.async(group: group) {
          for i in 0..<per { _ = w.append("t\(t)-\(i)\n") }
        }
      }
      group.wait()
      let lines = (try? String(contentsOf: url(name), encoding: .utf8))?
        .split(separator: "\n", omittingEmptySubsequences: true) ?? []
      XCTAssertEqual(lines.count, threads * per,
        "every concurrent append present; none lost")
      for l in lines {
        XCTAssertTrue(l.hasPrefix("t") && l.contains("-"), "no torn line: \(l)")
      }
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
