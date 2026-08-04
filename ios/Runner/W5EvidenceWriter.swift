import Foundation

/// B4: ONE serialized diagnostic file-append primitive for every evidence
/// family (W5 events JSONL, native wake log, W5 RSSI log). Diag-only — the whole
/// type compiles out of Release, so no evidence machinery ships.
///
/// Guarantees the panel required for locked-phone integrity:
/// - **absent vs inaccessible**: a missing file is CREATED; an existing file
///   that cannot be opened for writing (e.g. protected-while-locked) is treated
///   as inaccessible and the line is DROPPED — it is never replaced by a
///   single-line file (the Phase-3.3 defect).
/// - **protection + backup exclusion after EVERY op** (create, append, rotate).
/// - **serialized**: one lock per file, so concurrent BLE-queue + main-thread
///   emits cannot interleave a partial line or race the rotate.
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
    /// Returns false and accounts a drop on any failure.
    @discardableResult
    func append(_ text: String) -> Bool {
      guard let bytes = text.data(using: .utf8) else {
        noteDropped()
        return false
      }
      lock.lock()
      defer { lock.unlock() }
      let fm = FileManager.default

      // Rotate BEFORE writing when over cap (dotOne only).
      if rotation == .dotOne, fm.fileExists(atPath: url.path),
        let size = (try? fm.attributesOfItem(atPath: url.path)[.size]) as? Int,
        size > cap {
        rotateDotOne()
      }

      if !fm.fileExists(atPath: url.path) {
        // ABSENT → create fresh, protected, backup-excluded.
        do { try bytes.write(to: url, options: .completeFileProtectionUnlessOpen) }
        catch {
          noteDropped()
          return false
        }
        applyProtection(url)
        return true
      }

      // EXISTS → append. If it cannot be OPENED it is inaccessible, NOT absent:
      // drop the line, never overwrite an existing (possibly locked) log.
      guard let h = try? FileHandle(forWritingTo: url) else {
        noteDropped()
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
        noteDropped()
        return false
      }
      applyProtection(url)
      return true
    }

    private func rotateDotOne() {
      let name = url.lastPathComponent
      let ext = url.pathExtension
      let base = ext.isEmpty ? name : String(name.dropLast(ext.count + 1))
      let rotatedName = ext.isEmpty ? "\(base).1" : "\(base).1.\(ext)"
      let prev = url.deletingLastPathComponent().appendingPathComponent(rotatedName)
      try? FileManager.default.removeItem(at: prev)
      try? FileManager.default.moveItem(at: url, to: prev)
      applyProtection(prev)
    }

    /// Data protection + backup exclusion, reapplied after every op that can
    /// create or replace the file.
    private func applyProtection(_ u: URL) {
      try? FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.completeUnlessOpen],
        ofItemAtPath: u.path)
      var m = u
      var res = URLResourceValues()
      res.isExcludedFromBackup = true
      try? m.setResourceValues(res)
    }

    private func noteDropped() {
      dropped += 1
      let n = (Self.diagDefaults?.integer(forKey: droppedKey) ?? 0) + 1
      Self.diagDefaults?.set(n, forKey: droppedKey)
    }

    /// Account a drop that happened before append (e.g. JSON serialization
    /// failed), so no integrity loss is silent regardless of where it occurs.
    func noteExternalDrop() {
      lock.lock(); defer { lock.unlock() }
      noteDropped()
    }

    /// The persisted dropped-write keys for every family — summed + reset at
    /// boot so integrity loss is never silent.
    static let droppedKeys = [
      "bb.evwrite.dropped.w5_events.jsonl",
      "bb.evwrite.dropped.bb_wake_log.txt",
      "bb.evwrite.dropped.w5_rssi_log.jsonl",
    ]

    /// Sum the prior run's drops across ALL families, then reset them.
    static func drainPriorDropped() -> Int {
      var total = 0
      for k in droppedKeys {
        total += diagDefaults?.integer(forKey: k) ?? 0
        diagDefaults?.removeObject(forKey: k)
      }
      return total
    }
  }
#endif
