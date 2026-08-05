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
          "runEpoch": runEpoch,
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
          eventWriter.droppedLocked("encode")
          return
        }
        _ = eventWriter.appendLocked(s + "\n")
      }
    #endif
  }

  /// Provision the shared fleet run secret (hex). Validated: >= 64 hex chars
  /// (a full 256-bit key), EVEN length, valid hex — a short/odd/non-hex value
  /// MUST NOT mutate state. The >= 64 floor MATCHES the frozen puller/artifact
  /// contract (`hw_matrix_pull.sh` validates >= 64 hex before contact), so a key
  /// that provisions here is one the evidence chain will accept end to end.
  /// Persisted (survives OS restoration). If a DIFFERENT key arrives while an
  /// evidence epoch is active, this atomically rotates to a VISIBLY NEW key
  /// epoch and wipes the current evidence (never continues the same JSONL under
  /// two secrets). Returns a structured acknowledgment. Release-safe no-op.
  @discardableResult
  static func provisionRunSecret(_ hex: String) -> [String: Any] {
    #if INRANGE_DIAG
      guard hex.count >= 64, hex.count % 2 == 0, let d = hexToData(hex) else {
        return ["ok": false, "rejected": "invalid-hex"]
      }
      // ONE writer-serialized transaction: compare-vs-persisted, replace the
      // secret, and (if changed) rotate the key epoch + wipe — so no event can
      // ever be written with the new key into the old file/epoch, and a nil
      // in-memory cache after relaunch cannot hide a persisted key change.
      return eventWriter.withLock {
        let prior = persistedSecretLocked()
        let changed = prior != nil && prior != d
        if changed {
          // Wipe the OLD-key evidence BEFORE committing the new key. If the wipe
          // fails, an old-key artifact is stranded; rotating anyway would append
          // NEW-key events into it → mixed-key evidence. So DO NOT rotate: keep
          // the old key, fail closed, and surface the failure so the operator
          // can resolve the stranded artifact and retry.
          let r = resetCaseLocked(reason: "keyRotate")
          if (r["ok"] as? Bool) != true {
            return [
              "ok": false, "rejected": "rotate-wipe-failed",
              "wiped": r["wiped"] ?? [:],
            ]
          }
          runSecretLock.lock()
          diagDefaults?.set(hex, forKey: provisionedSecretKey)
          _cachedRunSecret = d
          runSecretLock.unlock()
          diagDefaults?.set(keyEpoch + 1, forKey: keyEpochKey)
        } else {
          // First provision or an unchanged key — no old-key evidence to wipe.
          runSecretLock.lock()
          diagDefaults?.set(hex, forKey: provisionedSecretKey)
          _cachedRunSecret = d
          runSecretLock.unlock()
        }
        return ["ok": true, "keyEpoch": keyEpoch, "rotated": changed]
      }
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
  /// - `destroySessionSecret(w5Quiescent:)` — the ONLY operation that destroys
  ///   the secret; rejected unless W5 is genuinely quiescent (no live sessions,
  ///   in-flight connects, links, leases, or timers — not a persisted flag).
  ///
  /// `runLabel`/`bootEpoch` are public per-process; `keyEpoch` (public) marks a
  /// key change; `caseEpoch` (public) marks a case reset. None is the secret.
  @discardableResult
  static func resetCase(reason: String = "reset") -> [String: Any] {
    #if INRANGE_DIAG
      // Serialize with any in-flight append/rotate on the events writer.
      return eventWriter.withLock { resetCaseLocked(reason: reason) }
    #else
      return ["ok": false]
    #endif
  }

  #if INRANGE_DIAG
    /// The case-reset body. The CALLER MUST hold the session lock, so wipe across
    /// EVERY evidence writer, control clearing, sequence + run-state reset, and
    /// epoch rotation are one transaction that cannot race an append/trim.
    /// Returns a structured, TYPED result (per-file wipe outcomes) — a wipe
    /// failure is visible, not hidden behind a bare "ok".
    @discardableResult
    static func resetCaseLocked(reason: String) -> [String: Any] {
      // Wipe every family's current + rotated artifacts under the shared lock.
      var wiped: [String: Bool] = [:]
      for w in [eventWriter, wakeWriter, rssiWriter] {
        for (name, ok) in w.wipeLocked() { wiped[name] = ok }
      }
      let allWiped = !wiped.values.contains(false)
      // TRANSACTIONAL on the wipe. If ANY artifact could not be wiped, the reset
      // FAILS CLOSED: do NOT rotate the case/run epoch, clear controls, reset the
      // sequence, remove the RSSI offset, or ack loss. Advancing the epoch while
      // a stranded old-epoch file survives would let later records land in it
      // under a new epoch (mixed-epoch evidence). The typed wipe-failure counters
      // are RETAINED so the failure surfaces at the next boot; ok:false is
      // returned with the per-file map. State is left as-was (minus whatever
      // partial wipe already succeeded, which only removes evidence — never
      // rotates identity).
      if !allWiped {
        return [
          "ok": false, "caseEpoch": caseEpoch, "runEpoch": runEpoch,
          "keyEpoch": keyEpoch, "secretRetained": true, "reason": reason,
          "wiped": wiped,
        ]
      }
      diagDefaults?.removeObject(forKey: "bb.w5rssi.off")  // RSSI drain offset
      faultPeerHandle = nil
      helloDelayPending = nil
      seqCounter = 0
      W5EvidenceWriter.ackPriorLoss()
      let newCase = caseEpoch + 1
      diagDefaults?.set(newCase, forKey: caseEpochKey)
      diagDefaults?.set(runEpoch + 1, forKey: runEpochKey)  // reset run state
      // SECRET RETAINED (owner ruling).
      return [
        "ok": true, "caseEpoch": newCase, "runEpoch": runEpoch,
        "keyEpoch": keyEpoch, "secretRetained": true, "reason": reason,
        "wiped": wiped,
      ]
    }
  #endif

  /// Destroy the persisted fleet secret. REJECTED unless W5 is genuinely
  /// QUIESCENT (managers/sessions/timers stopped — not merely the persisted
  /// feature flag). Routes through the SAME session boundary as reset (wipes
  /// evidence, clears controls, resets sequence/run) so it cannot produce a
  /// one-file/two-key result. Bumps the key epoch. Structured ack.
  @discardableResult
  static func destroySessionSecret(w5Quiescent: Bool) -> [String: Any] {
    #if INRANGE_DIAG
      return eventWriter.withLock {
        if !w5Quiescent { return ["ok": false, "rejected": "w5-active"] }
        let r = resetCaseLocked(reason: "destroy")  // wipe/clear/reset atomically
        // If the evidence could not be FULLY wiped, do NOT destroy the secret or
        // advance the key epoch: a stranded old-key artifact plus a destroyed
        // secret would later (on W5 restart under a fresh key) accrue mixed-key
        // evidence. Keep the secret, fail closed, and surface the stranded files
        // so the operator can resolve them and retry — the secret + evidence stay
        // mutually consistent (old key) in the meantime.
        let fullyWiped = (r["ok"] as? Bool) ?? false
        if !fullyWiped {
          return [
            "ok": false, "rejected": "wipe-failed", "wiped": r["wiped"] ?? [:],
          ]
        }
        runSecretLock.lock()
        diagDefaults?.removeObject(forKey: runSecretKey)
        diagDefaults?.removeObject(forKey: provisionedSecretKey)
        _cachedRunSecret = nil
        runSecretLock.unlock()
        diagDefaults?.set(keyEpoch + 1, forKey: keyEpochKey)
        return [
          "ok": true, "secretDestroyed": true, "keyEpoch": keyEpoch,
          "caseEpoch": caseEpoch, "wiped": r["wiped"] ?? [:],
        ]
      }
    #else
      return ["ok": false]
    #endif
  }

  /// Arm the one-shot pre-HELLO_ACK fault for a peer (Case 1 reclamation).
  /// A specific peer token scopes the fault to that peer; nil arms the next
  /// dial to anyone (use only when the target alias is not yet known).
  /// Arm the one-shot pre-HELLO_ACK fault for a SPECIFIC peer (Case 1). All
  /// control state (fault/delay) is mutated UNDER the events-writer boundary, so
  /// a `resetCase` clears controls atomically w.r.t. arm/consume; the handle is
  /// derived inside the lock (consistent eventWriter→runSecret order). The emit
  /// happens after the lock is released (emit takes the lock itself).
  @discardableResult
  static func armFault(peerRaw: String?) -> [String: Any] {
    #if INRANGE_DIAG
      // NO WILDCARD: a nil/empty/unresolvable target fails closed.
      let armed: String? = eventWriter.withLock {
        guard let h = handle("peer", peerRaw) else { return nil }
        faultPeerHandle = h
        return h
      }
      guard let armed else {
        emit(.faultInject, role: .app, reason: "arm-rejected")
        return ["ok": false, "rejected": "no-peer"]
      }
      // Observable lifecycle: armed → fired (preAckDrop) → [disarmed].
      emit(.faultInject, role: .outbound, peer: peerRaw, reason: "armed")
      return ["ok": true, "armed": true, "peer": armed]
    #else
      return ["ok": false]
    #endif
  }

  /// Disarm any pending fault (peer-scoped control cleanup between cases).
  static func disarmFault() {
    #if INRANGE_DIAG
      let was = eventWriter.withLock {
        let w = faultPeerHandle != nil
        faultPeerHandle = nil
        return w
      }
      if was { emit(.faultInject, role: .app, reason: "disarmed") }
    #endif
  }

  /// Whether a fault is currently armed (diagnostics/tests). False in Release.
  static var isFaultArmed: Bool {
    #if INRANGE_DIAG
      return eventWriter.withLock { faultPeerHandle != nil }
    #else
      return false
    #endif
  }

  /// Arm a ONE-SHOT diagnostic HELLO delay (seconds) for the next outbound
  /// HELLO — ONLY when explicitly armed, once. Under the writer boundary.
  static func armHelloDelay(_ seconds: Double) {
    #if INRANGE_DIAG
      eventWriter.withLock { helloDelayPending = seconds > 0 ? seconds : nil }
    #endif
  }

  /// The one-shot HELLO delay to apply now, then cleared (0 = none/not armed).
  static func consumeHelloDelay() -> Double {
    #if INRANGE_DIAG
      return eventWriter.withLock {
        let d = helloDelayPending ?? 0
        helloDelayPending = nil
        return d
      }
    #else
      return 0
    #endif
  }

  /// True (and clears) if a pre-ACK fault should fire for this outbound peer.
  static func consumePreAckFault(peerRaw: String?) -> Bool {
    #if INRANGE_DIAG
      return eventWriter.withLock {
        guard let armed = faultPeerHandle else { return false }
        // Peer-scoped, exactly-once: fires only for the armed peer, never a
        // wildcard, and clears on consumption. Handle derived inside the
        // boundary (eventWriter→runSecret order).
        if armed == handle("peer", peerRaw) {
          faultPeerHandle = nil
          return true
        }
        return false
      }
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
    // ONE session boundary (recursive) shared by every evidence writer AND the
    // controls/secret ops below — so append/rotate/wipe/control/provision/
    // destroy across all families are serialized, and a control mutation can
    // emit its ack event within the same transaction (A1/A2).
    static let sessionLock = NSRecursiveLock()
    static let eventWriter = W5EvidenceWriter(
      fileName: "w5_events.jsonl", cap: 4 * 1024 * 1024, rotation: .dotOne,
      lock: sessionLock)
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

    private static func validHex(_ hex: String?) -> Data? {
      // >= 64 hex (256-bit) — the same floor as provisionRunSecret and the
      // frozen puller contract, so an injected/persisted secret that resolves
      // here is one the whole evidence chain accepts.
      guard let hex, hex.count >= 64, hex.count % 2 == 0 else { return nil }
      return hexToData(hex)
    }

    /// True iff a REAL fleet key is in place — an injected env secret OR a
    /// Dart-provisioned one — NOT the generated per-install fallback. W5 link
    /// enablement is gated on this so a stale persisted `w5LinksEnabled` flag can
    /// never enable W5 activity under a random/absent key even if the Dart
    /// key-ready gate could not reach native (fail closed at the native level).
    static var hasFleetKey: Bool {
      if validHex(ProcessInfo.processInfo.environment["INRANGE_DIAG_RUN_SECRET"])
        != nil {
        return true
      }
      return validHex(diagDefaults?.string(forKey: provisionedSecretKey)) != nil
    }

    /// The PERSISTED/injected secret WITHOUT generating a fallback — used to
    /// decide whether a newly-provisioned key actually differs from a prior one
    /// (a nil in-memory cache must not hide a persisted key). nil = none yet.
    private static func persistedSecretLocked() -> Data? {
      if let d = validHex(ProcessInfo.processInfo.environment["INRANGE_DIAG_RUN_SECRET"]) {
        return d
      }
      if let d = validHex(diagDefaults?.string(forKey: provisionedSecretKey)) {
        return d
      }
      if let b64 = diagDefaults?.string(forKey: runSecretKey),
        let d = Data(base64Encoded: b64), d.count == 32 {
        return d
      }
      return nil
    }

    private static func resolveRunSecret() -> Data {
      if let d = persistedSecretLocked() { return d }
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

  /// A4 retained-until-ack boot accounting: PEEK the prior run's total loss,
  /// durably record it as a boot event, and ACK (clear) the counters ONLY if
  /// that record actually appended — so a failed boot append can never erase
  /// prior loss. All under the session boundary. Release-safe no-op.
  static func recordPriorLoss() {
    #if INRANGE_DIAG
      eventWriter.withLock {
        // Snapshot the per-key loss BEFORE the append records it. Ack only these
        // exact amounts on success — a new failure the append itself generates
        // (e.g. an applyProtection failure on THIS write) is retained, not erased.
        let recorded = W5EvidenceWriter.peekPriorLossDetailed()
        let loss = recorded.values.reduce(0, +)
        let obj: [String: Any] = [
          "v": 1, "run": runLabel, "epoch": bootEpoch,
          "keyEpoch": keyEpoch, "caseEpoch": caseEpoch, "runEpoch": runEpoch,
          "wallMs": Int(Date().timeIntervalSince1970 * 1000),
          "monoNs": DispatchTime.now().uptimeNanoseconds,
          "seq": nextSeqLocked(), "event": Event.boot.rawValue,
          "role": Role.app.rawValue, "reason": "priorLoss", "count": loss,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: obj),
          let s = String(data: data, encoding: .utf8),
          eventWriter.appendLocked(s + "\n") {
          W5EvidenceWriter.ackPriorLoss(recorded)  // ack ONLY the recorded amounts
        }
      }
    #endif
  }

  /// Shared writers for the non-W5Diag families — all on the SAME session lock.
  #if INRANGE_DIAG
    static let wakeWriter = W5EvidenceWriter(
      fileName: "bb_wake_log.txt", cap: 2 * 1024 * 1024, rotation: .dotOne,
      lock: sessionLock)
    static let rssiWriter = W5EvidenceWriter(
      fileName: "w5_rssi_log.jsonl", cap: 4 * 1024 * 1024, rotation: .external,
      lock: sessionLock)

    /// Public, RESETTABLE run epoch — `resetCase` rotates it (bootEpoch/runLabel
    /// are immutable process identity; this carries the reset run-state).
    static let runEpochKey = "bb.w5diag.runepoch"
    static var runEpoch: Int { diagDefaults?.integer(forKey: runEpochKey) ?? 0 }
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
