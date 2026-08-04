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

  /// Run-secret LIFECYCLE CONTRACT (diag-only):
  /// - **Creation**: lazily on first use, resolved env → provisioned(build
  ///   dart-define) → per-install persisted → generate. Persisted only in the
  ///   `io.inrange.diag` suite, never `standard`.
  /// - **Stability**: fixed for the life of the process, and persisted so an OS
  ///   restoration relaunch reuses it (HMAC handles stay joinable — Case 3).
  ///   Never auto-rotated (that would break restoration continuity).
  /// - **Bounded lifetime**: the secret belongs to ONE diagnostic session, not
  ///   forever. `resetDiagSession()` clears it (and the dropped counters); a
  ///   foreign-flavor boot wipes it too. The NEXT launch then mints a fresh
  ///   secret, so separate matrix cases are not cross-correlatable.
  /// - **runLabel vs secret**: `runLabel` (bootEpoch-derived) is a PUBLIC,
  ///   per-process label that distinguishes relaunches in the log; the secret
  ///   is private and keys the handles. They are independent by design.
  ///
  /// Clears the persisted run/provisioned secret + per-family dropped counters.
  /// In-process `runSecret` is already resolved (a `let`), so this takes effect
  /// on the NEXT launch — call it between matrix cases (before relaunch) to
  /// start a fresh, isolated diagnostic session. Release-safe no-op.
  static func resetDiagSession() {
    #if INRANGE_DIAG
      diagDefaults?.removeObject(forKey: runSecretKey)
      diagDefaults?.removeObject(forKey: provisionedSecretKey)
      for k in W5EvidenceWriter.droppedKeys { diagDefaults?.removeObject(forKey: k) }
    #endif
  }

  /// Arm the one-shot pre-HELLO_ACK fault for a peer (Case 1 reclamation).
  /// A specific peer token scopes the fault to that peer; nil arms the next
  /// dial to anyone (use only when the target alias is not yet known).
  static func armFault(peerRaw: String?) {
    #if INRANGE_DIAG
      faultPeerHandle = handle("peer", peerRaw) ?? "*"  // "*" = any next dial
    #endif
  }

  /// Disarm any pending fault (peer-scoped control cleanup between cases, so an
  /// armed-but-never-consumed fault can't fire on a later unrelated dial).
  static func disarmFault() {
    #if INRANGE_DIAG
      faultPeerHandle = nil
    #endif
  }

  /// Whether a fault is currently armed (diagnostics/tests). False in Release.
  static var isFaultArmed: Bool {
    #if INRANGE_DIAG
      return faultPeerHandle != nil
    #else
      return false
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
    // B4: the events JSONL now shares the one serialized evidence writer with
    // the wake + RSSI logs (absent-vs-inaccessible, protection/backup after
    // every op, per-family bounded drop counter).
    static let eventWriter = W5EvidenceWriter(
      fileName: "w5_events.jsonl", cap: 4 * 1024 * 1024, rotation: .dotOne)
    static var droppedWrites: Int { eventWriter.dropped }
    private static let diagDefaults = UserDefaults(suiteName: "io.inrange.diag")

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

    private static func nextSeq() -> UInt64 {
      seqLock.lock(); defer { seqLock.unlock() }
      seqCounter += 1
      return seqCounter
    }

    private static func write(_ obj: [String: Any]) {
      guard let data = try? JSONSerialization.data(withJSONObject: obj),
        let s = String(data: data, encoding: .utf8)
      else {
        eventWriter.noteExternalDrop()
        return
      }
      eventWriter.append(s + "\n")  // absent/inaccessible/protection handled here
    }
  #endif

  /// Sum + reset the PRIOR run's dropped-write count across every evidence
  /// family (events, wake, RSSI). Release-safe (0 when no diag machinery ships).
  static func drainPriorDroppedWrites() -> Int {
    #if INRANGE_DIAG
      return W5EvidenceWriter.drainPriorDropped()
    #else
      return 0
    #endif
  }

  /// Shared writers for the non-W5Diag families, so all three go through the
  /// one primitive. Diag-only.
  #if INRANGE_DIAG
    static let wakeWriter = W5EvidenceWriter(
      fileName: "bb_wake_log.txt", cap: 2 * 1024 * 1024, rotation: .dotOne)
    static let rssiWriter = W5EvidenceWriter(
      fileName: "w5_rssi_log.jsonl", cap: 4 * 1024 * 1024, rotation: .external)
  #endif

  /// Release-safe truncated handle for a raw id — for text logs (wake log) that
  /// must NOT carry raw token fragments. Returns "-" in a Release build and for
  /// nil/empty ids, so call sites need no `#if`.
  static func shortHandle(_ raw: String?) -> String {
    #if INRANGE_DIAG
      return handle("peer", raw) ?? "-"
    #else
      return "-"
    #endif
  }
}
