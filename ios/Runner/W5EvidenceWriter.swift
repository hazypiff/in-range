import Foundation

/// B4: ONE serialized diagnostic file-append primitive for every evidence
/// family (W5 events JSONL, native wake log, W5 RSSI log). Diag-only — the whole
/// type compiles out of Release, so no evidence machinery ships.
///
/// Guarantees the panel required for locked-phone integrity:
/// - **locked-state writes SUCCEED**: files use
///   `completeUntilFirstUserAuthentication` — accessible after the first unlock
///   post-boot and stay accessible when the phone re-locks (the standard class
///   for background daemons). The whole point of this evidence is to be written
///   while the phone is locked in a pocket during a soak; `completeUnlessOpen`
///   (an earlier mistake) made per-append open/close fail under lock and drop
///   every locked write.
/// - **absent vs inaccessible**: a missing file is CREATED; an existing file
///   that cannot be opened for writing is treated as inaccessible and the line
///   is DROPPED — it is never replaced by a single-line file (Phase-3.3 defect).
/// - **protection + backup exclusion after EVERY op** (create, append, rotate).
/// - **serialized**: one lock per file. `append` takes it internally; callers
///   with related file work (RSSI trim/drain/ack) run under `withLock` so
///   cross-thread (BLE queue vs channel/main) access cannot race the rotate or
///   the drain offset.
/// - **bounded failure accounting**: every drop increments a per-file counter
///   persisted to the diag suite, surfaced at the next boot.
#if INRANGE_DIAG
  final class W5EvidenceWriter {
    enum Rotation {
      case dotOne  // move full file to "<name>.1.<ext>" (events, wake)
      case external  // caller trims after append (RSSI drain offsets)
    }

    private let url: URL
    private let cap: Int
    private let rotation: Rotation
    private let droppedKey: String
    private let lock = NSLock()
    private static let diagDefaults = UserDefaults(suiteName: "io.inrange.diag")

    private(set) var dropped = 0

    init(fileName: String, cap: Int, rotation: Rotation) {
      self.url = FileManager.default.urls(
        for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(fileName)
      self.cap = cap
      self.rotation = rotation
      self.droppedKey = "bb.evwrite.dropped.\(fileName)"
    }

    /// Append one already-formatted line (caller includes any trailing newline).
    /// Returns false and accounts a drop on any failure. Takes the lock.
    @discardableResult
    func append(_ text: String) -> Bool {
      lock.lock()
      defer { lock.unlock() }
      return appendLocked(text)
    }

    /// Core append; the CALLER MUST hold the lock (via `append` or `withLock`).
    /// This lets the events writer make seq-assignment + append ONE atomic
    /// critical section, so a line's `seq` always matches its file order even
    /// under concurrent emits (B4).
    @discardableResult
    func appendLocked(_ text: String) -> Bool {
      guard let bytes = text.data(using: .utf8) else {
        droppedLocked()
        return false
      }
      let fm = FileManager.default

      // Rotate BEFORE writing when over cap (dotOne only). If the rotation
      // MOVE fails, the op-failure is already accounted; we still append (the
      // file stays slightly over cap for one more line) rather than drop
      // evidence — preservation over a strict cap bound. The Bool is consumed so
      // the outcome is explicit, not silently ignored.
      if rotation == .dotOne, fm.fileExists(atPath: url.path),
        let size = (try? fm.attributesOfItem(atPath: url.path)[.size]) as? Int,
        size > cap {
        if !rotateDotOne() {
          // accounted in rotateDotOne(); fall through and append anyway.
        }
      }

      if !fm.fileExists(atPath: url.path) {
        // ABSENT → create fresh, protected (locked-state-writable), excluded.
        do { try bytes.write(to: url, options: .completeFileProtectionUntilFirstUserAuthentication) }
        catch {
          droppedLocked()
          return false
        }
        applyProtection(url)
        return true
      }

      // EXISTS → append. If it cannot be OPENED it is inaccessible, NOT absent:
      // drop the line, never overwrite an existing (possibly locked) log.
      guard let h = try? FileHandle(forWritingTo: url) else {
        droppedLocked()
        return false
      }
      var ok = true
      if #available(iOS 13.4, *) {
        do {
          try h.seekToEnd()
          try h.write(contentsOf: bytes)
        } catch { ok = false }
        try? h.close()
      } else {
        // iOS 13.0–13.3: no non-trapping FileHandle write. We already proved
        // the file exists AND is openable, so a read-append-write replaces a
        // known-accessible file (not the absent/inaccessible ambiguity).
        try? h.close()
        if let existing = try? Data(contentsOf: url) {
          do { try (existing + bytes).write(to: url, options: .atomic) }
          catch { ok = false }
        } else {
          ok = false
        }
      }
      if !ok {
        droppedLocked()
        return false
      }
      applyProtection(url)
      return true
    }

    /// Rotate; returns false (and accounts an op-failure) if the move failed —
    /// so a failed rotation is never silently followed by an append to the
    /// over-cap file with no record.
    @discardableResult
    private func rotateDotOne() -> Bool {
      let name = url.lastPathComponent
      let ext = url.pathExtension
      let base = ext.isEmpty ? name : String(name.dropLast(ext.count + 1))
      let rotatedName = ext.isEmpty ? "\(base).1" : "\(base).1.\(ext)"
      let prev = url.deletingLastPathComponent().appendingPathComponent(rotatedName)
      try? FileManager.default.removeItem(at: prev)
      do {
        try FileManager.default.moveItem(at: url, to: prev)
      } catch {
        noteOpFailure("rotate")
        return false
      }
      applyProtection(prev)
      return true
    }

    /// Data protection + backup exclusion, reapplied after every op that can
    /// create or replace the file. Accounts a failure and VERIFIES the
    /// backup-exclusion read-back (the one attribute the platform reports), so a
    /// silent attribute loss on replacement is not invisible.
    private func applyProtection(_ u: URL) {
      do {
        try FileManager.default.setAttributes(
          [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
          ofItemAtPath: u.path)
      } catch { noteOpFailure("protect") }
      var m = u
      var res = URLResourceValues()
      res.isExcludedFromBackup = true
      do { try m.setResourceValues(res) } catch { noteOpFailure("backup") }
      // Verify the backup-exclusion took (device reports it; simulator returns
      // nil, in which case we cannot verify and do not falsely fail).
      if let excluded = try? u.resourceValues(forKeys: [.isExcludedFromBackupKey])
        .isExcludedFromBackup, excluded == false {
        noteOpFailure("backup-verify")
      }
    }

    private func noteOpFailure(_ kind: String) {
      let k = "bb.evwrite.opfail.\(url.lastPathComponent)"
      let n = (Self.diagDefaults?.integer(forKey: k) ?? 0) + 1
      Self.diagDefaults?.set(n, forKey: k)
    }

    /// Run `body` holding this writer's lock — for related file work (RSSI
    /// trim/drain/ack) that must serialize with `append` across threads. Must
    /// NOT call `append` from inside (the lock is non-reentrant).
    func withLock<T>(_ body: () -> T) -> T {
      lock.lock()
      defer { lock.unlock() }
      return body()
    }

    /// Account a drop; the CALLER MUST hold the lock (append/withLock).
    func droppedLocked() {
      dropped += 1
      let n = (Self.diagDefaults?.integer(forKey: droppedKey) ?? 0) + 1
      Self.diagDefaults?.set(n, forKey: droppedKey)
    }

    /// Account a drop that happened before append (e.g. JSON serialization
    /// failed), so no integrity loss is silent regardless of where it occurs.
    func noteExternalDrop() {
      lock.lock(); defer { lock.unlock() }
      droppedLocked()
    }

    /// The persisted dropped-write keys for every family — summed + reset at
    /// boot so integrity loss is never silent.
    static let droppedKeys = [
      "bb.evwrite.dropped.w5_events.jsonl",
      "bb.evwrite.dropped.bb_wake_log.txt",
      "bb.evwrite.dropped.w5_rssi_log.jsonl",
    ]

    /// Per-file op-failure keys (rotate/protect/backup) — bounded accounting for
    /// the file operations that can fail silently.
    static let opFailKeys = [
      "bb.evwrite.opfail.w5_events.jsonl",
      "bb.evwrite.opfail.bb_wake_log.txt",
      "bb.evwrite.opfail.w5_rssi_log.jsonl",
      "bb.evwrite.opfail.w5_events.1.jsonl",
      "bb.evwrite.opfail.bb_wake_log.1.txt",
    ]

    /// Sum the prior run's dropped writes + op-failures across ALL families,
    /// then reset them — no integrity loss (write OR file-op) is silent.
    static func drainPriorDropped() -> Int {
      var total = 0
      for k in droppedKeys + opFailKeys {
        total += diagDefaults?.integer(forKey: k) ?? 0
        diagDefaults?.removeObject(forKey: k)
      }
      return total
    }
  }
#endif
