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
    case restoreCentral, restorePeriph, restoreRebind, coldLaunch
    case boot, beat, parted
    case faultInject
  }

  enum Role: String { case outbound, inbound, app }

  // MARK: - public API (release-safe; bodies compile out)

  /// Emit a structured event. Raw ids are HMAC-handled internally; in Release
  /// the whole body is compiled out and args are unused.
  static func emit(
    _ event: Event, role: Role? = nil, peer: String? = nil, lease: String? = nil,
    link: String? = nil, peripheral: String? = nil, result: String? = nil,
    reason: String? = nil, count: Int? = nil
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
      if let h = handle("peer", peer) { obj["peer"] = h }
      if let h = handle("lease", lease) { obj["lease"] = h }
      if let h = handle("link", link) { obj["link"] = h }
      if let h = handle("peripheral", peripheral) { obj["peripheral"] = h }
      if let result { obj["result"] = result }
      if let reason { obj["reason"] = reason }
      if let count { obj["count"] = count }
      write(obj)
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

    /// In-memory only. Injected shared secret if present, else per-process
    /// random. Never persisted, never logged.
    private static let runSecret: Data = {
      if let hex = ProcessInfo.processInfo.environment["INRANGE_DIAG_RUN_SECRET"],
        hex.count >= 32, let d = hexToData(hex) {
        return d
      }
      var b = [UInt8](repeating: 0, count: 32)
      _ = SecRandomCopyBytes(kSecRandomDefault, 32, &b)
      return Data(b)
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
      else { droppedWrites += 1; return }
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
        if !ok { droppedWrites += 1; return }
      } else {
        do { try bytes.write(to: url, options: .completeFileProtectionUnlessOpen) }
        catch { droppedWrites += 1; return }
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
