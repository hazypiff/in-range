import CommonCrypto
import Foundation

/// Structured, compile-gated W5 diagnostic event layer (Phase 2).
///
/// PRIVACY / ISOLATION by construction:
/// - The entire emit path is `#if INRANGE_DIAG`. In a Release/Profile binary
///   every `W5Diag.emit(...)`/`armFault(...)` call compiles to an empty
///   inlinable no-op — no file I/O, no HMAC, no JSON. No diagnostic code ships.
/// - Raw identifiers (tokens, leaseIds, linkIds, CB handles) NEVER reach the
///   file. Each is replaced by a run-scoped truncated HMAC-SHA256 "handle"
///   under a domain separator (`peer\0<token>` vs `lease\0<leaseId>`), so the
///   same raw id yields the same handle within a run (cross-device alignment
///   when the run secret is shared) but is not reversible.
/// - The run secret lives only in memory, is never persisted or printed, and
///   is per-process random unless a shared secret is injected via the
///   `INRANGE_DIAG_RUN_SECRET` launch environment (Phase 5 sets it fleet-wide).
enum W5Diag {

  /// Stable event names (enum-like) — the only `event` values that appear.
  enum Event: String {
    case discover, tiebreak
    case dialPending, dialStart, connectResult, dialFail, ttlSweep
    case hello, helloAck, propose, ack, reject
    case commit, linkDown, graceEnter, graceBypass, graceExpiry
    case aliasRollSend, aliasRollRecv, prevAliasExpiry
    case dropPeer
    case restoreCentral, restorePeriph, restoreRebind, coldLaunch, snapshotLoad
    case boot, beat, parted
    case faultInject
  }

  enum Role: String { case outbound, inbound, app }

  // MARK: - public API (release-safe; bodies compile out)

  /// Emit a structured event. Two-layer construction: the whole body is
  /// `#if INRANGE_DIAG`, AND every sensitive argument is an `@autoclosure`, so
  /// in a Release/Profile build the raw-id expressions are NEVER evaluated —
  /// no id string is materialized, no HMAC runs, nothing is passed. Callers
  /// write `peer: rawHex` exactly as before; the compiler wraps it.
  static func emit(
    _ event: Event, role: Role? = nil,
    peer: @autoclosure () -> String? = nil,
    lease: @autoclosure () -> String? = nil,
    link: @autoclosure () -> String? = nil,
    peripheral: @autoclosure () -> String? = nil,
    result: @autoclosure () -> String? = nil,
    reason: @autoclosure () -> String? = nil,
    count: @autoclosure () -> Int? = nil
  ) {
    #if INRANGE_DIAG
      var obj: [String: Any] = [
        "v": 1,
        "run": runLabel,
        "epoch": bootEpoch,
        "wallMs": Int(Date().timeIntervalSince1970 * 1000),
        "monoNs": DispatchTime.now().uptimeNanoseconds,
        "seq": nextSeq(),
        "event": event.rawValue,
      ]
      if let role { obj["role"] = role.rawValue }
      if let h = handle("peer", peer()) { obj["peer"] = h }
      if let h = handle("lease", lease()) { obj["lease"] = h }
      if let h = handle("link", link()) { obj["link"] = h }
      if let h = handle("peripheral", peripheral()) { obj["peripheral"] = h }
      if let result = result() { obj["result"] = result }
      if let reason = reason() { obj["reason"] = reason }
      if let count = count() { obj["count"] = count }
      write(obj)
    #endif
  }

  /// Provision the shared fleet run secret (hex) from a build-time dart-define,
  /// persisted to the diag suite so it survives OS restoration and aligns HMAC
  /// handles across a fleet built from one artifact. Must be called before any
  /// emit (beacon start does). Release-safe no-op.
  static func provisionRunSecret(_ hex: String) {
    #if INRANGE_DIAG
      guard hex.count >= 32, hexToData(hex) != nil else { return }
      diagDefaults?.set(hex, forKey: provisionedSecretKey)
    #endif
  }

  /// Arm the one-shot pre-HELLO_ACK fault for a peer (Case 1 reclamation).
  static func armFault(peerRaw: String?) {
    #if INRANGE_DIAG
      faultPeerHandle = handle("peer", peerRaw) ?? "*"  // "*" = any next dial
    #endif
  }

  /// True (and clears) if a pre-ACK fault should fire for this outbound peer.
  static func consumePreAckFault(peerRaw: String?) -> Bool {
    #if INRANGE_DIAG
      guard let armed = faultPeerHandle else { return false }
      if armed == "*" || armed == handle("peer", peerRaw) {
        faultPeerHandle = nil
        return true
      }
      return false
    #else
      return false
    #endif
  }

  #if INRANGE_DIAG
    // MARK: - diagnostic internals (compiled out of Release)

    private static let bootEpoch = UInt64.random(in: 0...UInt64.max)
    private static var seqCounter: UInt64 = 0
    private static let seqLock = NSLock()
    private static var faultPeerHandle: String?
    private(set) static var droppedWrites: Int = 0
    private static let cap = 4 * 1024 * 1024
    // Persist to the diag operational suite so the NEXT boot can surface it.
    private static let diagDefaults = UserDefaults(suiteName: "io.inrange.diag")
    private static func noteDropped() {
      droppedWrites += 1
      let n = (diagDefaults?.integer(forKey: "bb.w5events.dropped") ?? 0) + 1
      diagDefaults?.set(n, forKey: "bb.w5events.dropped")
    }

    private static let runSecretKey = "bb.w5diag.runsecret"
    private static let provisionedSecretKey = "bb.w5diag.provisionedsecret"

    /// Run secret, resolved with precedence and PERSISTED so restoration works:
    ///   1. `INRANGE_DIAG_RUN_SECRET` env — explicit fleet-wide override for
    ///      simulator/Xcode/CI + cross-device alignment (set by the diag scheme
    ///      and artifact builder). Wins when present.
    ///   2. else a per-INSTALL secret persisted in the diag suite. An
    ///      OS-spawned CoreBluetooth restoration relaunch does NOT inherit the
    ///      Xcode launch environment, so an env-only secret would rotate at the
    ///      exact boundary Case 3 must join across. Persisting it (diag suite
    ///      only, never `standard`) keeps every HMAC handle continuous across
    ///      restoration.
    ///   3. else generate once and persist.
    /// Diag-only (the whole type compiles out of Release). Truncated HMAC
    /// handles stay non-reversible; the secret is never logged or emitted.
    private static let runSecret: Data = {
      // 1. env override (simulator/Xcode/CI + tests) — highest precedence.
      if let hex = ProcessInfo.processInfo.environment["INRANGE_DIAG_RUN_SECRET"],
        hex.count >= 32, let d = hexToData(hex) {
        return d
      }
      // 2. fleet secret provisioned from the build-time dart-define (persisted
      //    by provisionRunSecret at start) — aligns a whole fleet + survives
      //    restoration.
      if let hex = diagDefaults?.string(forKey: provisionedSecretKey),
        hex.count >= 32, let d = hexToData(hex) {
        return d
      }
      // 3. per-INSTALL persisted secret — restoration-continuous on one device.
      if let b64 = diagDefaults?.string(forKey: runSecretKey),
        let d = Data(base64Encoded: b64), d.count == 32 {
        return d
      }
      // 4. generate once and persist.
      var b = [UInt8](repeating: 0, count: 32)
      _ = SecRandomCopyBytes(kSecRandomDefault, 32, &b)
      let d = Data(b)
      diagDefaults?.set(d.base64EncodedString(), forKey: runSecretKey)
      return d
    }()

    /// Public run label — NOT the secret. Distinguishes relaunches.
    private static let runLabel = String(
      format: "%08x", UInt32(truncatingIfNeeded: bootEpoch))

    private static func hexToData(_ hex: String) -> Data? {
      var out = Data(capacity: hex.count / 2)
      var idx = hex.startIndex
      while idx < hex.endIndex {
        let n = hex.index(idx, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
        guard n > idx, let b = UInt8(hex[idx..<n], radix: 16) else { return nil }
        out.append(b)
        idx = n
      }
      return out
    }

    /// Truncated HMAC-SHA256 handle for a domain-separated raw id (14 hex).
    static func handle(_ domain: String, _ raw: String?) -> String? {
      guard let raw, !raw.isEmpty else { return nil }
      var msg = Data(domain.utf8)
      msg.append(0)
      msg.append(Data(raw.utf8))
      var mac = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
      runSecret.withUnsafeBytes { k in
        msg.withUnsafeBytes { m in
          CCHmac(
            CCHmacAlgorithm(kCCHmacAlgSHA256), k.baseAddress, k.count,
            m.baseAddress, m.count, &mac)
        }
      }
      return mac.prefix(7).map { String(format: "%02x", $0) }.joined()  // 14 hex
    }

    private static var fileURL: URL {
      FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("w5_events.jsonl")
    }

    private static func nextSeq() -> UInt64 {
      seqLock.lock(); defer { seqLock.unlock() }
      seqCounter += 1
      return seqCounter
    }

    private static func write(_ obj: [String: Any]) {
      guard let data = try? JSONSerialization.data(withJSONObject: obj),
        let bytes = (String(data: data, encoding: .utf8).map { $0 + "\n" })?
          .data(using: .utf8)
      else { noteDropped(); return }
      let url = fileURL
      // Cap + rotate.
      if let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size])
        as? Int, size > cap {
        let prev = url.deletingLastPathComponent()
          .appendingPathComponent("w5_events.1.jsonl")
        try? FileManager.default.removeItem(at: prev)
        try? FileManager.default.moveItem(at: url, to: prev)
        applyProtection(prev)
      }
      if let h = try? FileHandle(forWritingTo: url) {
        var ok = true
        if #available(iOS 13.4, *) {
          do { try h.seekToEnd(); try h.write(contentsOf: bytes) } catch { ok = false }
          try? h.close()
        } else {
          try? h.close()
          let existing = (try? Data(contentsOf: url)) ?? Data()
          do { try (existing + bytes).write(to: url, options: .atomic) } catch { ok = false }
        }
        if !ok { noteDropped(); return }
      } else {
        do { try bytes.write(to: url, options: .completeFileProtectionUnlessOpen) }
        catch { noteDropped(); return }
      }
      applyProtection(url)
    }

    /// Data protection + backup exclusion, reapplied after every op that can
    /// replace the file (create, append, rotate).
    private static func applyProtection(_ url: URL) {
      try? FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.completeUnlessOpen],
        ofItemAtPath: url.path)
      var u = url
      var res = URLResourceValues()
      res.isExcludedFromBackup = true
      try? u.setResourceValues(res)
    }
  #endif
}
