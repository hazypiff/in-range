import Foundation

/// B4: ONE serialized diagnostic file-append primitive for every evidence
/// family (W5 events JSONL, native wake log, W5 RSSI log). Diag-only — the whole
/// type compiles out of Release, so no evidence machinery ships.
///
/// Every writer shares ONE session lock (injected), so append/rotate/wipe across
/// ALL families — and the W5Diag controls/secret ops that also take it — are one
/// serialized session boundary. The lock is recursive so a control mutation can
/// emit its acknowledgment event within the same transaction.
///
/// Guarantees:
/// - **locked-state writes SUCCEED**: `completeUntilFirstUserAuthentication`.
/// - **absent vs inaccessible**: a missing file is CREATED; an existing file
///   that cannot be opened is DROPPED, never replaced by a single line.
/// - **protection + backup exclusion after EVERY op**, verified where reported.
/// - **typed, retained-until-ack failure accounting**: every drop AND every
///   file-op failure is counted per (file, operation) and only cleared after a
///   durable boot acknowledgment (peek → record → ack).
#if INRANGE_DIAG
  final class W5EvidenceWriter {
    enum Rotation {
      case dotOne  // move full file to "<name>.1.<ext>" (events, wake)
      case external  // caller trims after append (RSSI drain offsets)
    }

    let url: URL
    private let cap: Int
    private let rotation: Rotation
    private let fileName: String
    private let droppedKeyBase: String
    private let lock: NSRecursiveLock
    private static let diagDefaults = UserDefaults(suiteName: "io.inrange.diag")
    static let opFailPrefix = "bb.evwrite.opfail."
    static let droppedPrefix = "bb.evwrite.dropped."

    private(set) var dropped = 0

    // TEST-ONLY (diag build) deterministic file-op fault injection. Keyed by
    // "<fileName>.<op>"; each entry forces that op to fail `count` more times so
    // a test can assert the TYPED failure counter increments for every op
    // (rotate / rotate-unlink / protect / backup / close / wipe) without relying
    // on fragile real-FS permission tricks. The whole type compiles out of
    // Release, so this seam is never present in a production binary.
    static var injectedFailures: [String: Int] = [:]
    static func resetInjectedFailures() { injectedFailures = [:] }
    private func consumeInjected(_ op: String) -> Bool {
      let k = "\(fileName).\(op)"
      guard let n = Self.injectedFailures[k], n > 0 else { return false }
      Self.injectedFailures[k] = n - 1
      return true
    }

    init(fileName: String, cap: Int, rotation: Rotation, lock: NSRecursiveLock) {
      self.fileName = fileName
      self.url = FileManager.default.urls(
        for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(fileName)
      self.cap = cap
      self.rotation = rotation
      self.droppedKeyBase = "\(Self.droppedPrefix)\(fileName)"
      self.lock = lock
    }

    /// The rotated (".1") sibling URL — part of this family's inventory.
    var rotatedURL: URL {
      let ext = url.pathExtension
      let base = ext.isEmpty ? fileName : String(fileName.dropLast(ext.count + 1))
      let name = ext.isEmpty ? "\(base).1" : "\(base).1.\(ext)"
      return url.deletingLastPathComponent().appendingPathComponent(name)
    }

    /// Every artifact this family owns (current + rotated) — the authoritative
    /// inventory used by wipe/reset so no rotation is missed.
    var inventory: [URL] { [url, rotatedURL] }

    @discardableResult
    func append(_ text: String) -> Bool {
      lock.lock()
      defer { lock.unlock() }
      return appendLocked(text)
    }

    /// Core append; the CALLER MUST hold the shared lock (via `append`/`withLock`
    /// or the session boundary), so seq-assign + append is one atomic section.
    @discardableResult
    func appendLocked(_ text: String) -> Bool {
      guard let bytes = text.data(using: .utf8) else {
        droppedLocked("encode")
        return false
      }
      let fm = FileManager.default

      // The over-cap check runs THROUGH the typed/injectable stat op — a stat
      // failure here is accounted (`bb.evwrite.opfail.<file>.stat`) exactly like
      // the RSSI path, never silently treated as "not over cap" (A2, codex
      // re-review). Absent → nil (nothing to rotate); unstattable → nil + typed.
      if rotation == .dotOne, let size = statSizeLocked(), size > cap {
        _ = rotateDotOne()  // accounted on failure; append proceeds either way
      }

      if !fm.fileExists(atPath: url.path) {
        do { try bytes.write(to: url, options: .completeFileProtectionUntilFirstUserAuthentication) }
        catch {
          droppedLocked("create")
          return false
        }
        applyProtection(url)
        return true
      }

      guard let h = try? FileHandle(forWritingTo: url) else {
        droppedLocked("open")  // inaccessible existing file — never overwrite
        return false
      }
      var ok = true
      if #available(iOS 13.4, *) {
        do {
          try h.seekToEnd()
          try h.write(contentsOf: bytes)
        } catch { ok = false }
        // A close failure leaves durability UNCERTAIN (buffered bytes may not
        // have flushed), so it must NOT report success — otherwise a caller like
        // recordPriorLoss would ack prior loss against a possibly non-durable
        // record. Treat it as a failed append (ok=false) AND type it.
        if consumeInjected("close") {
          try? h.close()  // still release the fd; only the typed failure is faked
          noteOpFailure("close")
          ok = false
        } else {
          do { try h.close() } catch { noteOpFailure("close"); ok = false }
        }
      } else {
        try? h.close()
        if let existing = try? Data(contentsOf: url) {
          do { try (existing + bytes).write(to: url, options: .atomic) }
          catch { ok = false }
        } else {
          ok = false
        }
      }
      if !ok {
        droppedLocked("write")
        return false
      }
      applyProtection(url)
      return true
    }

    @discardableResult
    private func rotateDotOne() -> Bool {
      let prev = rotatedURL
      if FileManager.default.fileExists(atPath: prev.path) {
        if consumeInjected("rotate-unlink") {
          noteOpFailure("rotate-unlink")
        } else {
          do { try FileManager.default.removeItem(at: prev) }
          catch { noteOpFailure("rotate-unlink") }
        }
      }
      if consumeInjected("rotate") {
        noteOpFailure("rotate")
        return false
      }
      do { try FileManager.default.moveItem(at: url, to: prev) }
      catch {
        noteOpFailure("rotate")
        return false
      }
      applyProtection(prev)
      return true
    }

    private func applyProtection(_ u: URL) {
      if consumeInjected("protect") {
        noteOpFailure("protect")
      } else {
        do {
          try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: u.path)
        } catch { noteOpFailure("protect") }
      }
      if consumeInjected("backup") {
        noteOpFailure("backup")
      } else {
        var m = u
        var res = URLResourceValues()
        res.isExcludedFromBackup = true
        do { try m.setResourceValues(res) } catch { noteOpFailure("backup") }
        // Read-back-verify. A read that FAILS (nil — attribute unreadable) is as
        // much a verify failure as reading back `false`: in neither case can we
        // confirm the exclusion took, so both must be TYPED, not silently
        // accepted (A2, codex re-review — the old `if let …, == false` swallowed
        // an unreadable attribute). The injection seam models an unreadable read.
        let excluded: Bool? = consumeInjected("backup-verify")
          ? nil
          : (try? u.resourceValues(forKeys: [.isExcludedFromBackupKey])
              .isExcludedFromBackup) ?? nil
        if excluded != true { noteOpFailure("backup-verify") }
      }
    }

    /// GLOBAL wipe generation — incremented on EVERY wipe ATTEMPT of ANY family
    /// (success or partial failure), so a consumer holding a pre-wipe read (an
    /// RSSI drain) can detect that its data is stale and discard a late ack even
    /// when the wipe did not change caseEpoch (a partial-failed reset). R3.
    static var wipeGeneration = 0

    /// Delete every artifact this family owns; returns a TYPED per-file result so
    /// a wipe cannot silently fail and still report success (A2). Caller holds
    /// the session lock.
    @discardableResult
    func wipeLocked() -> [String: Bool] {
      Self.wipeGeneration += 1  // a wipe was ATTEMPTED — invalidate pending reads
      var out: [String: Bool] = [:]
      for u in inventory where FileManager.default.fileExists(atPath: u.path) {
        if consumeInjected("wipe") {
          out[u.lastPathComponent] = false
          noteOpFailure("wipe")
          continue
        }
        do {
          try FileManager.default.removeItem(at: u)
          out[u.lastPathComponent] = true
        } catch {
          out[u.lastPathComponent] = false
          noteOpFailure("wipe")
        }
      }
      return out
    }

    // MARK: - R3: mandatory RSSI file ops behind the writer (typed + injectable)
    //
    // The RSSI trim/drain/ack path performs stat/read/replace/delete on the
    // current file. These run here — under the shared session lock, with typed
    // failure accounting and the same injection seam — so no mandatory B4 file
    // operation bypasses the writer abstraction. Callers hold the session lock.

    /// Byte size of the current file, or nil if absent/unstattable (typed).
    func statSizeLocked() -> Int? {
      if consumeInjected("stat") { noteOpFailure("stat"); return nil }
      guard FileManager.default.fileExists(atPath: url.path) else { return nil }
      guard let n = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size])
        as? Int else {
        noteOpFailure("stat"); return nil
      }
      return n
    }

    /// Full contents of the current file, or nil if absent/unreadable (typed).
    func readLocked() -> Data? {
      if consumeInjected("read") { noteOpFailure("read"); return nil }
      guard FileManager.default.fileExists(atPath: url.path) else { return nil }
      guard let d = try? Data(contentsOf: url) else { noteOpFailure("read"); return nil }
      return d
    }

    /// Atomically REPLACE the current file with `data`, then reapply protection +
    /// backup exclusion and READ-BACK-VERIFY them (the trim path previously wrote
    /// with no re-protection). Typed on failure. Returns success.
    @discardableResult
    func replaceLocked(_ data: Data) -> Bool {
      if consumeInjected("replace") { noteOpFailure("replace"); return false }
      do {
        try data.write(to: url, options: [.atomic,
          .completeFileProtectionUntilFirstUserAuthentication])
      } catch { noteOpFailure("replace"); return false }
      applyProtection(url)  // reapply + verify protection/backup (typed within)
      // Read-back-verify the protection class actually took. An UNREADABLE
      // attribute (nil) cannot confirm the class, so it is a verify failure too,
      // not a silent pass (A2, codex re-review — the old `if let …, != x` swallowed
      // an unreadable read). The injection seam models an unreadable read.
      let prot: FileProtectionType? = consumeInjected("replace-verify")
        ? nil
        : (try? FileManager.default.attributesOfItem(atPath: url.path)[.protectionKey])
            as? FileProtectionType
      if prot != .completeUntilFirstUserAuthentication { noteOpFailure("replace-verify") }
      return true
    }

    /// Delete the CURRENT file (not rotations) — the ack reclaim path. Typed.
    @discardableResult
    func deleteCurrentLocked() -> Bool {
      guard FileManager.default.fileExists(atPath: url.path) else { return true }
      if consumeInjected("delete") { noteOpFailure("delete"); return false }
      do { try FileManager.default.removeItem(at: url); return true }
      catch { noteOpFailure("delete"); return false }
    }

    /// Run `body` under the shared session lock. Recursive, so nested control +
    /// emit transactions are one critical section.
    func withLock<T>(_ body: () -> T) -> T {
      lock.lock()
      defer { lock.unlock() }
      return body()
    }

    /// Account a LOST LINE, TYPED by the operation that lost it
    /// (`bb.evwrite.dropped.<file>.<op>`) — so a soak's line losses are
    /// attributable to encode/create/open/write, not merged into one bucket.
    /// The CALLER MUST hold the lock. `dropped` (in-memory) is the total.
    func droppedLocked(_ op: String = "write") {
      dropped += 1
      let k = "\(droppedKeyBase).\(op)"
      let n = (Self.diagDefaults?.integer(forKey: k) ?? 0) + 1
      Self.diagDefaults?.set(n, forKey: k)
    }

    /// A pre-append drop (takes the lock).
    func noteExternalDrop() {
      lock.lock(); defer { lock.unlock() }
      droppedLocked("external")
    }

    /// Typed-by-operation failure counter: `bb.evwrite.opfail.<file>.<op>`.
    private func noteOpFailure(_ op: String) {
      let k = "\(Self.opFailPrefix)\(fileName).\(op)"
      let n = (Self.diagDefaults?.integer(forKey: k) ?? 0) + 1
      Self.diagDefaults?.set(n, forKey: k)
    }

    // MARK: - retained-until-ack loss accounting (A4)

    /// PEEK the prior run's total loss (dropped + typed op-failures) across ALL
    /// families WITHOUT clearing — so a failed boot append cannot erase loss
    /// before it is durably recorded. Enumerates by prefix so rotated files and
    /// every operation kind are included.
    static func peekPriorLoss() -> Int {
      peekPriorLossDetailed().values.reduce(0, +)
    }

    /// PEEK the prior loss as a per-key SNAPSHOT (key → count) WITHOUT clearing.
    /// The snapshot is what a durable boot record then acks — so ONLY the exact
    /// amounts recorded are cleared, and any NEW failure generated DURING the
    /// boot append (e.g. an applyProtection failure on the record write itself)
    /// is retained for the next boot rather than silently erased (A4).
    static func peekPriorLossDetailed() -> [String: Int] {
      guard let all = diagDefaults?.dictionaryRepresentation() else { return [:] }
      var out: [String: Int] = [:]
      for (k, v) in all
      where k.hasPrefix(opFailPrefix) || k.hasPrefix(droppedPrefix) {
        out[k] = (v as? Int) ?? 0
      }
      return out
    }

    /// ACK the loss counters — call ONLY after the boot event that recorded them
    /// has been durably appended. Blanket form (clears everything) for a case
    /// reset that fully wiped; use `ackPriorLoss(_:)` after a boot record so new
    /// failures during the append survive.
    static func ackPriorLoss() {
      ackPriorLoss(peekPriorLossDetailed())
    }

    /// ACK exactly the RECORDED amounts: decrement each snapshotted key by the
    /// count that was durably recorded, retaining any increment that happened
    /// after the snapshot (removing the key only when it drops to zero).
    static func ackPriorLoss(_ recorded: [String: Int]) {
      for (k, recordedCount) in recorded {
        let cur = diagDefaults?.integer(forKey: k) ?? 0
        let remaining = cur - recordedCount
        if remaining > 0 {
          diagDefaults?.set(remaining, forKey: k)
        } else {
          diagDefaults?.removeObject(forKey: k)
        }
      }
    }
  }
#endif
