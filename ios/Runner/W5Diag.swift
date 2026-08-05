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
/// - The run secret is resolved once per process and PERSISTED in the diag-only
///   UserDefaults suite so it survives OS restoration (see the full lifecycle
///   contract on `resetDiagSession`). It is never printed and never emitted;
///   only truncated, non-reversible handles derived from it appear in the log.
///   Precedence: fleet dart-define/env → persisted (per-install) → generated.
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
      // Evaluate the raw-id autoclosures OUTSIDE the lock (cheap strings), then
      // derive EVERY handle from ONE atomic {secret, keyEpoch, caseEpoch}
      // snapshot INSIDE the serialized boundary — so a key/epoch cannot change
      // between fields or silently inside one file epoch (Wave A).
      let rPeer = peer(), rLease = lease(), rLink = link(), rPeriph = peripheral()
      let rResult = result(), rReason = reason(), rCount = count()
      let rRole = role
      eventWriter.withLock {
        let snap = sessionSnapshotLocked()
        var obj: [String: Any] = [
          "v": 1,
          "run": runLabel,
          "epoch": bootEpoch,
          "keyEpoch": snap.keyEpoch,
          "caseEpoch": snap.caseEpoch,
          "wallMs": Int(Date().timeIntervalSince1970 * 1000),
          "monoNs": DispatchTime.now().uptimeNanoseconds,
          "seq": nextSeqLocked(),
          "event": event.rawValue,
        ]
        if let rRole { obj["role"] = rRole.rawValue }
        if let h = handle(with: snap.secret, "peer", rPeer) { obj["peer"] = h }
        if let h = handle(with: snap.secret, "lease", rLease) { obj["lease"] = h }
        if let h = handle(with: snap.secret, "link", rLink) { obj["link"] = h }
        if let h = handle(with: snap.secret, "peripheral", rPeriph) {
          obj["peripheral"] = h
        }
        if let rResult { obj["result"] = rResult }
        if let rReason { obj["reason"] = rReason }
        if let rCount { obj["count"] = rCount }
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
          let s = String(data: data, encoding: .utf8)
        else {
          eventWriter.droppedLocked()
          return
        }
        _ = eventWriter.appendLocked(s + "\n")
      }
    #endif
  }

  /// Provision the shared fleet run secret (hex). Validated: >= 32 chars, EVEN
  /// length, valid hex — a short/odd/non-hex value MUST NOT mutate state.
  /// Persisted (survives OS restoration). If a DIFFERENT key arrives while an
  /// evidence epoch is active, this atomically rotates to a VISIBLY NEW key
  /// epoch and wipes the current evidence (never continues the same JSONL under
  /// two secrets). Returns a structured acknowledgment. Release-safe no-op.
  @discardableResult
  static func provisionRunSecret(_ hex: String) -> [String: Any] {
    #if INRANGE_DIAG
      guard hex.count >= 32, hex.count % 2 == 0, let d = hexToData(hex) else {
        return ["ok": false, "rejected": "invalid-hex"]
      }
      runSecretLock.lock()
      let changed = _cachedRunSecret != nil && _cachedRunSecret != d
      diagDefaults?.set(hex, forKey: provisionedSecretKey)
      _cachedRunSecret = d
      runSecretLock.unlock()
      if changed {
        // Key changed mid-session → new key epoch + fresh evidence epoch.
        _ = resetCase(reason: "keyRotate")
        diagDefaults?.set(keyEpoch + 1, forKey: keyEpochKey)
      }
      return ["ok": true, "keyEpoch": keyEpoch, "rotated": changed]
    #else
      return ["ok": false]
    #endif
  }

  /// DIAGNOSTIC-SESSION LIFECYCLE CONTRACT (diag-only), owner-ratified 2026-08-05:
  /// the shared fleet secret PERSISTS across relaunch/restoration AND case
  /// resets. Two distinct operations:
  /// - `resetCase()` — RETAINS the fleet secret, rotates only the PUBLIC case
  ///   epoch, waits for in-flight writes, wipes every current + rotated
  ///   artifact, clears fault/delay, and resets sequence/run state. Between
  ///   matrix cases.
  /// - `destroySessionSecret(w5Active:)` — the ONLY operation that destroys the
  ///   secret; rejected while W5 is active (must be stopped first).
  ///
  /// `runLabel`/`bootEpoch` are public per-process; `keyEpoch` (public) marks a
  /// key change; `caseEpoch` (public) marks a case reset. None is the secret.
  @discardableResult
  static func resetCase(reason: String = "reset") -> [String: Any] {
    #if INRANGE_DIAG
      // Serialize with any in-flight append/rotate on the events writer.
      return eventWriter.withLock {
        BackgroundBeacon.wipeDiagnosticFiles()  // current + rotated artifacts
        diagDefaults?.removeObject(forKey: "bb.w5rssi.off")  // RSSI drain offset
        faultPeerHandle = nil
        helloDelayPending = nil
        seqCounter = 0
        for k in W5EvidenceWriter.droppedKeys + W5EvidenceWriter.opFailKeys {
          diagDefaults?.removeObject(forKey: k)
        }
        let newCase = caseEpoch + 1
        diagDefaults?.set(newCase, forKey: caseEpochKey)
        // SECRET RETAINED (owner ruling).
        return [
          "ok": true, "caseEpoch": newCase, "keyEpoch": keyEpoch,
          "secretRetained": true, "reason": reason,
        ]
      }
    #else
      return ["ok": false]
    #endif
  }

  /// Destroy the persisted fleet secret. REJECTED while W5 is active — the
  /// owner ruling makes destruction a separate stopped-W5 operation, distinct
  /// from `resetCase`. Bumps the key epoch. Structured ack.
  @discardableResult
  static func destroySessionSecret(w5Active: Bool) -> [String: Any] {
    #if INRANGE_DIAG
      if w5Active { return ["ok": false, "rejected": "w5-active"] }
      runSecretLock.lock()
      diagDefaults?.removeObject(forKey: runSecretKey)
      diagDefaults?.removeObject(forKey: provisionedSecretKey)
      _cachedRunSecret = nil
      runSecretLock.unlock()
      diagDefaults?.set(keyEpoch + 1, forKey: keyEpochKey)
      return ["ok": true, "secretDestroyed": true, "keyEpoch": keyEpoch]
    #else
      return ["ok": false]
    #endif
  }

  /// Arm the one-shot pre-HELLO_ACK fault for a peer (Case 1 reclamation).
  /// A specific peer token scopes the fault to that peer; nil arms the next
  /// dial to anyone (use only when the target alias is not yet known).
  @discardableResult
  static func armFault(peerRaw: String?) -> [String: Any] {
    #if INRANGE_DIAG
      // NO WILDCARD (work order): a nil/empty/unresolvable target fails closed.
      guard let h = handle("peer", peerRaw) else {
        emit(.faultInject, role: .app, reason: "arm-rejected")
        return ["ok": false, "rejected": "no-peer"]
      }
      faultPeerHandle = h
      // Observable lifecycle: armed → fired (preAckDrop) → [disarmed].
      emit(.faultInject, role: .outbound, peer: peerRaw, reason: "armed")
      return ["ok": true, "armed": true, "peer": h]
    #else
      return ["ok": false]
    #endif
  }

  /// Disarm any pending fault (peer-scoped control cleanup between cases, so an
  /// armed-but-never-consumed fault can't fire on a later unrelated dial).
  static func disarmFault() {
    #if INRANGE_DIAG
      let was = faultPeerHandle != nil
      faultPeerHandle = nil
      if was { emit(.faultInject, role: .app, reason: "disarmed") }
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

  /// Arm a ONE-SHOT diagnostic HELLO delay (seconds) for the next outbound
  /// HELLO — widens the connect↔HELLO_ACK window for Case 1 deterministically,
  /// but ONLY when explicitly armed (not on every diag dial) and only once.
  static func armHelloDelay(_ seconds: Double) {
    #if INRANGE_DIAG
      helloDelayPending = seconds > 0 ? seconds : nil
    #endif
  }

  /// The one-shot HELLO delay to apply now, then cleared (0 = none/not armed).
  static func consumeHelloDelay() -> Double {
    #if INRANGE_DIAG
      defer { helloDelayPending = nil }
      return helloDelayPending ?? 0
    #else
      return 0
    #endif
  }

  /// True (and clears) if a pre-ACK fault should fire for this outbound peer.
  static func consumePreAckFault(peerRaw: String?) -> Bool {
    #if INRANGE_DIAG
      guard let armed = faultPeerHandle else { return false }
      // Peer-scoped, exactly-once: fires only for the armed peer, never a
      // wildcard, and clears on consumption.
      if armed == handle("peer", peerRaw) {
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
    private static var faultPeerHandle: String?
    private static var helloDelayPending: Double?
    // B4: the events JSONL now shares the one serialized evidence writer with
    // the wake + RSSI logs (absent-vs-inaccessible, protection/backup after
    // every op, per-family bounded drop counter).
    static let eventWriter = W5EvidenceWriter(
      fileName: "w5_events.jsonl", cap: 4 * 1024 * 1024, rotation: .dotOne)
    static var droppedWrites: Int { eventWriter.dropped }
    private static let diagDefaults = UserDefaults(suiteName: "io.inrange.diag")

    private static let runSecretKey = "bb.w5diag.runsecret"
    private static let provisionedSecretKey = "bb.w5diag.provisionedsecret"

    private static let runSecretLock = NSLock()
    private static var _cachedRunSecret: Data?

    /// Run secret (see the lifecycle contract on `resetDiagSession`). Resolved
    /// lazily, cached in-process, and — unlike a resolve-once `let` —
    /// RE-RESOLVABLE: `provisionRunSecret` updates the cache so a fleet key that
    /// arrives after an early boot emit still governs later handles (boot events
    /// carry no handles, so nothing keyed leaks before provisioning); and
    /// `resetDiagSession` clears the cache so the next handle re-resolves.
    /// Precedence: env → provisioned → per-install persisted → generate+persist.
    /// Diag-only. Truncated HMAC handles stay non-reversible; the secret is
    /// never logged or emitted.
    static var runSecret: Data {
      runSecretLock.lock()
      defer { runSecretLock.unlock() }
      if let c = _cachedRunSecret { return c }
      let d = resolveRunSecret()
      _cachedRunSecret = d
      return d
    }

    private static func resolveRunSecret() -> Data {
      if let hex = ProcessInfo.processInfo.environment["INRANGE_DIAG_RUN_SECRET"],
        hex.count >= 32, let d = hexToData(hex) {
        return d
      }
      if let hex = diagDefaults?.string(forKey: provisionedSecretKey),
        hex.count >= 32, let d = hexToData(hex) {
        return d
      }
      if let b64 = diagDefaults?.string(forKey: runSecretKey),
        let d = Data(base64Encoded: b64), d.count == 32 {
        return d
      }
      var b = [UInt8](repeating: 0, count: 32)
      _ = SecRandomCopyBytes(kSecRandomDefault, 32, &b)
      let d = Data(b)
      diagDefaults?.set(d.base64EncodedString(), forKey: runSecretKey)
      return d
    }

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

    /// Truncated HMAC-SHA256 handle for a domain-separated raw id (14 hex),
    /// keyed by the CURRENT run secret.
    static func handle(_ domain: String, _ raw: String?) -> String? {
      handle(with: runSecret, domain, raw)
    }

    /// Handle keyed by a SPECIFIC secret — so one emit derives every field from
    /// one atomic snapshot (a key cannot change mid-event).
    static func handle(with secret: Data, _ domain: String, _ raw: String?)
      -> String?
    {
      guard let raw, !raw.isEmpty else { return nil }
      var msg = Data(domain.utf8)
      msg.append(0)
      msg.append(Data(raw.utf8))
      var mac = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
      secret.withUnsafeBytes { k in
        msg.withUnsafeBytes { m in
          CCHmac(
            CCHmacAlgorithm(kCCHmacAlgSHA256), k.baseAddress, k.count,
            m.baseAddress, m.count, &mac)
        }
      }
      return mac.prefix(7).map { String(format: "%02x", $0) }.joined()  // 14 hex
    }

    // Public epochs (non-secret) persisted so restoration keeps the same case.
    static let caseEpochKey = "bb.w5diag.caseepoch"
    static let keyEpochKey = "bb.w5diag.keyepoch"
    static var caseEpoch: Int { diagDefaults?.integer(forKey: caseEpochKey) ?? 0 }
    static var keyEpoch: Int { diagDefaults?.integer(forKey: keyEpochKey) ?? 0 }

    /// One immutable {secret, keyEpoch, caseEpoch} snapshot — read INSIDE the
    /// events-writer lock so a whole event derives from a single, consistent
    /// session state.
    static func sessionSnapshotLocked()
      -> (secret: Data, keyEpoch: Int, caseEpoch: Int)
    {
      (runSecret, keyEpoch, caseEpoch)
    }

    /// Next monotonic sequence. The CALLER MUST hold the events writer's lock
    /// (emit calls this inside `eventWriter.withLock`), so seq-assign + append
    /// are atomic and no separate seq lock is needed.
    private static func nextSeqLocked() -> UInt64 {
      seqCounter += 1
      return seqCounter
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
