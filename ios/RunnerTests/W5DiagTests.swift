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

    // A5 (was B3): the run secret in use is the PROVISIONED fleet secret, not a
    // per-process random. This test PROVISIONS a known secret and asserts the
    // handle equals the truncated HMAC-SHA256 computed with THAT secret — so it
    // exercises the injection path deterministically and NEVER skips (an
    // environment-conditional skip could hide a broken injection path as green).
    func testHandleUsesProvisionedRunSecret() {
      let hex = String(repeating: "b7", count: 32)  // 64 hex, known value
      W5Diag.provisionRunSecret(hex)
      let got = W5Diag.handle("peer", "tok-A")
      let want = Self.expectedHandle(domain: "peer", raw: "tok-A", secretHex: hex)
      XCTAssertEqual(got, want, "handle must use the provisioned fleet secret")
      // A different provisioned secret changes the handle — proving it is the
      // secret in use, not a coincidence.
      let hex2 = String(repeating: "3c", count: 32)
      W5Diag.provisionRunSecret(hex2)
      let got2 = W5Diag.handle("peer", "tok-A")
      let want2 = Self.expectedHandle(domain: "peer", raw: "tok-A", secretHex: hex2)
      XCTAssertEqual(got2, want2, "re-provision re-keys the handle")
      XCTAssertNotEqual(got, got2, "distinct secrets ⇒ distinct handles")
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
        W5Diag.destroySessionSecret(w5Quiescent: false)["rejected"] as? String,
        "w5-active", "must refuse while W5 is up")
      let ok = W5Diag.destroySessionSecret(w5Quiescent: true)
      XCTAssertEqual(ok["ok"] as? Bool, true)
      XCTAssertEqual(ok["secretDestroyed"] as? Bool, true)
    }

    // A1: destruction is gated by REAL controller quiescence, computed from live
    // W5 state (sessions/in-flight/links/leases/timers) — NOT the persisted
    // feature flag. A live committed lease ⇒ not quiescent ⇒ destroy REFUSED;
    // after the REAL dropPeer teardown ⇒ quiescent ⇒ destroy SUCCEEDS. This is
    // the predicate `destroyW5Secret` feeds from `BackgroundBeacon.isW5Quiescent`.
    func testDestroyGatedByRealControllerQuiescence() {
      let bb = BackgroundBeacon()
      withExtendedLifetime(bb) {
        bb.testEnableW5Links()
        XCTAssertTrue(bb.isW5Quiescent, "no links yet ⇒ quiescent")
        bb.w5Link.testSeedOutboundLink(
          peripheralID: UUID(), myCand: "cand-a", peerCand: "cand-b",
          alias: "aliasQ", linkId: "LQ")
        XCTAssertFalse(
          bb.isW5Quiescent,
          "a live committed lease ⇒ NOT quiescent (real state, not the flag)")
        XCTAssertEqual(
          W5Diag.destroySessionSecret(w5Quiescent: bb.isW5Quiescent)["rejected"]
            as? String,
          "w5-active", "destruction REFUSED while a real lease is live")
        // Tear the lease down through the REAL channel boundary Dart calls.
        let d = bb.dropPeerByToken("aliasQ")
        XCTAssertEqual(d["leaseEnded"] as? Bool, true, "real teardown ended lease")
        XCTAssertTrue(bb.isW5Quiescent, "after real teardown ⇒ quiescent")
        W5Diag.provisionRunSecret(String(repeating: "ab", count: 32))
        let ok = W5Diag.destroySessionSecret(w5Quiescent: bb.isW5Quiescent)
        XCTAssertEqual(ok["ok"] as? Bool, true, "destruction ALLOWED once quiescent")
        XCTAssertEqual(ok["secretDestroyed"] as? Bool, true)
      }
    }

    // A1/A2: concurrent reset + emit + destroy all serialize on the ONE shared
    // session lock — no torn evidence line, no crash — and the terminal state is
    // consistent: the secret is RETAINED across every concurrent resetCase
    // (owner ruling), and every emitted line is well-formed JSON.
    func testConcurrentResetAndEmitSerializeNoTornLine() {
      let sec = String(repeating: "9f", count: 32)  // 64 hex
      W5Diag.provisionRunSecret(sec)
      _ = W5Diag.resetCase()  // start from a clean evidence file
      let group = DispatchGroup()
      let q = DispatchQueue(label: "w5.concurrency", attributes: .concurrent)
      for i in 0..<12 {
        q.async(group: group) {
          if i % 4 == 0 {
            _ = W5Diag.resetCase()
          } else {
            W5Diag.emit(.beat, role: .app)
          }
        }
      }
      group.wait()
      // Secret survived every concurrent reset (retained, not rotated away).
      let want = Self.expectedHandle(domain: "peer", raw: "k", secretHex: sec)
      XCTAssertEqual(
        W5Diag.handle("peer", "k"), want, "secret retained across concurrent resets")
      // Any lines present are intact JSON — no interleaved/torn append.
      let docs = FileManager.default.urls(
        for: .documentDirectory, in: .userDomainMask)[0]
      let url = docs.appendingPathComponent("w5_events.jsonl")
      if let body = try? String(contentsOf: url, encoding: .utf8) {
        for l in body.split(separator: "\n", omittingEmptySubsequences: true) {
          XCTAssertNoThrow(
            try JSONSerialization.jsonObject(with: Data(l.utf8)),
            "no torn line under concurrent reset+emit: \(l)")
        }
      }
    }

    // A2: resetCase wipes EVERY family's current AND rotated artifact in one
    // serialized boundary — events, wake, AND RSSI, including each ".1" sibling —
    // and clears controls. A wipe that missed a rotation (or a family) would
    // leave a file behind; the inventory-based wipe must catch all six.
    func testResetCaseWipesEveryFamilyIncludingRotations() {
      let fm = FileManager.default
      let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
      let files = [
        "w5_events.jsonl", "w5_events.1.jsonl",
        "bb_wake_log.txt", "bb_wake_log.1.txt",
        "w5_rssi_log.jsonl", "w5_rssi_log.1.jsonl",
      ]
      for f in files {
        try? "seed\n".write(
          to: docs.appendingPathComponent(f), atomically: true, encoding: .utf8)
      }
      W5Diag.armFault(peerRaw: "p")
      W5Diag.armHelloDelay(2)
      let ack = W5Diag.resetCase()
      XCTAssertEqual(ack["ok"] as? Bool, true, "every wipe reported success")
      for f in files {
        XCTAssertFalse(
          fm.fileExists(atPath: docs.appendingPathComponent(f).path),
          "reset must remove \(f) (current + rotated, every family)")
      }
      XCTAssertFalse(W5Diag.isFaultArmed, "fault cleared in the same boundary")
      XCTAssertEqual(W5Diag.consumeHelloDelay(), 0, "delay cleared")
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

    // A4 alignment: the native provisioning floor MATCHES the frozen puller
    // contract (>= 64 hex / 256-bit). A 32-hex key — accepted under the old
    // 32-CHAR floor — must now be REJECTED, so a key can never provision on the
    // device yet be refused by the evidence puller.
    func testProvisionRequires64HexMatchingPullerContract() {
      W5Diag.provisionRunSecret(String(repeating: "ab", count: 32))  // 64 hex base
      let good = W5Diag.handle("peer", "z")
      let thirtyTwoHex = String(repeating: "cd", count: 16)  // 32 hex, 128-bit
      XCTAssertEqual(thirtyTwoHex.count, 32)
      XCTAssertEqual(
        W5Diag.provisionRunSecret(thirtyTwoHex)["ok"] as? Bool, false,
        "a 32-hex key is below the 64-hex puller floor → rejected")
      XCTAssertEqual(W5Diag.handle("peer", "z"), good, "state unchanged")
      XCTAssertEqual(
        W5Diag.provisionRunSecret(String(repeating: "9a", count: 32))["ok"]
          as? Bool, true, "a full 64-hex key is accepted")
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
      let w = W5EvidenceWriter(fileName: name, cap: 1_000_000, rotation: .dotOne, lock: NSRecursiveLock())
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
      let w = W5EvidenceWriter(fileName: name, cap: 1_000_000, rotation: .dotOne, lock: NSRecursiveLock())
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
      let w = W5EvidenceWriter(fileName: name, cap: 10, rotation: .dotOne, lock: NSRecursiveLock())
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
      let w = W5EvidenceWriter(fileName: name, cap: 1_000_000, rotation: .dotOne, lock: NSRecursiveLock())
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
      let w = W5EvidenceWriter(fileName: name, cap: 10_000_000, rotation: .dotOne, lock: NSRecursiveLock())
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

    // A4: PEEK sums dropped + typed op-failures across EVERY family WITHOUT
    // clearing (so a failed boot append can't erase loss before it is durably
    // recorded); ACK clears only after the boot event is written.
    func testPeekPriorLossSumsEveryFamilyAckClears() {
      let d = UserDefaults(suiteName: "io.inrange.diag")
      // Clear any residue from other tests so the sum is deterministic.
      for k in d?.dictionaryRepresentation().keys ?? [:].keys
      where k.hasPrefix(W5EvidenceWriter.opFailPrefix)
        || k.hasPrefix(W5EvidenceWriter.droppedPrefix) {
        d?.removeObject(forKey: k)
      }
      d?.set(3, forKey: "bb.evwrite.dropped.w5_events.jsonl")
      d?.set(2, forKey: "bb.evwrite.dropped.bb_wake_log.txt")
      d?.set(1, forKey: "bb.evwrite.dropped.w5_rssi_log.jsonl")
      // Typed op-failures (rotate/close/wipe) also count toward loss.
      d?.set(4, forKey: "bb.evwrite.opfail.w5_events.jsonl.rotate")
      d?.set(5, forKey: "bb.evwrite.opfail.w5_rssi_log.jsonl.close")
      XCTAssertEqual(W5EvidenceWriter.peekPriorLoss(), 15,
        "dropped(6) + typed op-failures(9) across all families")
      XCTAssertEqual(W5EvidenceWriter.peekPriorLoss(), 15,
        "PEEK does not clear — a second peek returns the same total")
      W5EvidenceWriter.ackPriorLoss()
      XCTAssertEqual(W5EvidenceWriter.peekPriorLoss(), 0, "ACK cleared every key")
    }

    private func opFail(_ file: String, _ op: String) -> Int {
      UserDefaults(suiteName: "io.inrange.diag")?
        .integer(forKey: "bb.evwrite.opfail.\(file).\(op)") ?? 0
    }

    // A4: EVERY writer file-op failure is TYPED and accounted. Using the diag-
    // only injection seam, force each op to fail and assert its own counter
    // (`bb.evwrite.opfail.<file>.<op>`) increments — so a soak's silent I/O
    // losses are attributable per operation, not merged into one bucket.
    func testInjectedFileOpFailuresAreTypedAndAccounted() throws {
      W5EvidenceWriter.resetInjectedFailures()
      let name = "ewtest_a.jsonl"
      try? FileManager.default.removeItem(at: url(name))
      try? FileManager.default.removeItem(at: url("ewtest_a.1.jsonl"))
      let d = UserDefaults(suiteName: "io.inrange.diag")
      for op in ["rotate", "rotate-unlink", "protect", "backup", "close", "wipe"] {
        d?.removeObject(forKey: "bb.evwrite.opfail.\(name).\(op)")
      }
      let w = W5EvidenceWriter(
        fileName: name, cap: 10, rotation: .dotOne, lock: NSRecursiveLock())

      // protect + backup: fail on the very first create's applyProtection.
      W5EvidenceWriter.injectedFailures["\(name).protect"] = 1
      W5EvidenceWriter.injectedFailures["\(name).backup"] = 1
      XCTAssertTrue(w.append("first\n"))  // append still SUCCEEDS…
      XCTAssertEqual(opFail(name, "protect"), 1, "protect failure typed")
      XCTAssertEqual(opFail(name, "backup"), 1, "backup failure typed")

      // close: force the post-write handle close to be accounted.
      W5EvidenceWriter.injectedFailures["\(name).close"] = 1
      _ = w.append("second\n")
      XCTAssertEqual(opFail(name, "close"), 1, "close failure typed")

      // rotate-unlink + rotate: grow past cap so a rotation is attempted, and
      // fail both the stale-.1 unlink and the move.
      try? "OLD\n".write(to: url("ewtest_a.1.jsonl"), atomically: true, encoding: .utf8)
      W5EvidenceWriter.injectedFailures["\(name).rotate-unlink"] = 1
      W5EvidenceWriter.injectedFailures["\(name).rotate"] = 1
      _ = w.append("AAAAAAAAAAAAAAAAAAAA\n")  // > cap 10 → rotate attempted
      XCTAssertEqual(opFail(name, "rotate-unlink"), 1, "rotate-unlink typed")
      XCTAssertEqual(opFail(name, "rotate"), 1, "rotate typed")

      // wipe: force a delete failure and prove wipeLocked reports it per-file.
      W5EvidenceWriter.injectedFailures["\(name).wipe"] = 1
      let wiped = w.wipeLocked()
      XCTAssertEqual(wiped[name], false, "wipe reports the failed file as false")
      XCTAssertEqual(opFail(name, "wipe"), 1, "wipe failure typed")

      W5EvidenceWriter.resetInjectedFailures()
    }

    // A4: the boot loss-record is ATOMIC w.r.t. acknowledgment — if the durable
    // boot append fails, prior loss counters are RETAINED (never acked), so a
    // failed boot can't erase the evidence that loss occurred.
    func testBootRecordDoesNotAckWhenAppendFails() throws {
      W5EvidenceWriter.resetInjectedFailures()
      let d = UserDefaults(suiteName: "io.inrange.diag")
      for k in d?.dictionaryRepresentation().keys ?? [:].keys
      where k.hasPrefix(W5EvidenceWriter.opFailPrefix)
        || k.hasPrefix(W5EvidenceWriter.droppedPrefix) {
        d?.removeObject(forKey: k)
      }
      d?.set(7, forKey: "bb.evwrite.dropped.w5_events.jsonl")
      XCTAssertEqual(W5EvidenceWriter.peekPriorLoss(), 7)
      // recordPriorLoss must NOT call ackPriorLoss when the append did not land.
      // Make the events file inaccessible so appendLocked drops (real failure).
      let events = FileManager.default.urls(
        for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("w5_events.jsonl")
      try? "x".data(using: .utf8)!.write(to: events)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o444], ofItemAtPath: events.path)
      W5Diag.recordPriorLoss()
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o644], ofItemAtPath: events.path)
      XCTAssertGreaterThanOrEqual(
        W5EvidenceWriter.peekPriorLoss(), 7,
        "a failed boot append must RETAIN prior loss (never ack it away)")
      try? FileManager.default.removeItem(at: events)
      W5EvidenceWriter.ackPriorLoss()
    }
  }
#endif
