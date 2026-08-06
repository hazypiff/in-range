import BackgroundTasks
import CoreBluetooth
import Flutter
import UIKit

/// W2 of docs/IOS_BACKGROUND_BLE_WIRING.md — the locked-phone BLE carrier.
///
/// Peripheral side: advertises the fixed 0xCAFE discovery marker (+ the
/// rotating token as a second 128-bit service UUID for the foreground
/// fast path) and hosts a GATT service (CAFE) with one read-only
/// characteristic (CA7E) whose value is computed PER READ from the stored
/// token batch — background reads wake the app, so no timer ever fires.
///
/// Central side: filtered scan for CAFE (the only scan shape iOS delivers
/// in background). Token comes from the advert when present — as the second
/// service UUID from an iOS peer, or as manufacturer data from an Android peer
/// (finding B1, 2026-07-26: a filtered iOS scan still delivers manufacturer
/// data, and Android's 16-byte token is already in it, so that direction needs
/// no connect at all) — otherwise connect → read CA7E → disconnect, with a
/// per-peripheral token cache.
///
/// Survives relaunch: managers use CoreBluetooth state restoration, and the
/// batch + enabled flag persist in UserDefaults so a BT-relaunched process
/// can serve reads and buffer sightings before the Flutter engine attaches.
final class BackgroundBeacon: NSObject {
  static let shared = BackgroundBeacon()

  // 0000CAFE-…: app-wide discovery marker (beacon_service.dart).
  private static let serviceUUID = CBUUID(string: "CAFE")
  private static let tokenCharUUID = CBUUID(string: "CA7E")
  /// in-range's BLE company identifier, mirrored from beacon_service.dart's
  /// `_inRangeManufacturerId`. Android's advert carries the 16-byte
  /// correlation token under this id; CoreBluetooth hands the field back with
  /// the company id still on the front, little-endian. Finding B1.
  private static let inRangeCompanyID: UInt16 = 0xFFFF
  // W5 keepalive channel (contract proposed issue #3): central writes a
  // 1-byte heartbeat every ~8 s, peripheral notifies back — the Herald
  // ping-pong. Each incoming BLE event grants ~10 s of background
  // execution, inside which the next outgoing beat is sent: neither side
  // ever suspends while the session lives.
  private static let keepaliveCharUUID = CBUUID(string: "CA5E")
  // W5 encounter-lease control plane (#7/PR #9): versioned bidirectional
  // exchange — central writes .withResponse, peripheral notifies. Wired by
  // W5LinkController; inert unless INRANGE_W5_LINKS.
  static let controlCharUUID = CBUUID(string: "CA6E")

  // #8 release isolation: diagnostic builds live in their own persistence
  // universe — separate bundle id (build config), separate UserDefaults suite,
  // separate CoreBluetooth restoration identifiers — so nothing a diagnostic
  // build persists (token slots, flags, logs) can ever be restored by a
  // production build. INRANGE_DIAG is set ONLY by the diag build flavor.
  #if INRANGE_DIAG
    static let isDiagBuild = true
    static let restoreIDSuffix = ".diag"
  #else
    static let isDiagBuild = false
    static let restoreIDSuffix = ""
  #endif
  /// Referenced by tests to prove the production domain cannot see it.
  static let diagSuiteName = "io.inrange.diag"
  static let peripheralRestoreID = "io.inrange.beacon.peripheral" + restoreIDSuffix
  static let centralRestoreID = "io.inrange.beacon.central" + restoreIDSuffix

  /// The operational persistence domain. Diagnostic builds write to their own
  /// suite; production compiles to UserDefaults.standard with no code path
  /// that reads the diag suite.
  static func operationalDefaults() -> UserDefaults {
    #if INRANGE_DIAG
      return UserDefaults(suiteName: diagSuiteName) ?? .standard
    #else
      return UserDefaults.standard
    #endif
  }

  private static let keyEnabled = "bb.enabled"
  private static let keySlots = "bb.slots"
  private static let keyBuffer = "bb.buffer"
  private static let keyPingURL = "bb.pingUrl"
  private static let keyPingAuth = "bb.pingAuth"
  private static let bufferCap = 500
  private static let tokenCacheTTL: TimeInterval = 15 * 60
  private static let connectRetryFloor: TimeInterval = 5 * 60
  private static let scanRestartFloor: TimeInterval = 4

  var peripheralMgr: CBPeripheralManager?
  private var centralMgr: CBCentralManager?
  var channel: FlutterMethodChannel?
  private var serviceAdded = false
  /// Set by peripheralManager(_:willRestoreState:) — which fires BEFORE
  /// peripheralManagerDidUpdateState on a restoration relaunch — so the state
  /// callback does not clobber the restored service registration (audit
  /// 2026-07-25, critical #3).
  private var didRestorePeripheral = false

  // W5 live sessions: peripheral.identifier → session state. Session-scoped
  // by OWNER RULE (2026-07-24): hold while the encounter is live, drop on
  // part/reject — never a permanent ledger (matches token-rotation privacy).
  struct W5Session {
    let peripheral: CBPeripheral
    var tokenHex: String
    var lastEvent: Date
    var keepaliveChar: CBCharacteristic?
    var lastRssiAt: Date
    var lastBeatAt: Date
    var writeInFlight: Bool  // exactly one .withResponse write outstanding
    var notifyReady: Bool    // didUpdateNotificationStateFor confirmed
    var seq: Int             // beat sequence number (logging)
    var lastGattOp: String   // last GATT op attempted (logging)
  }
  private var w5: [UUID: W5Session] = [:]
  private var keepaliveNotifyChar: CBMutableCharacteristic?
  var controlNotifyChar: CBMutableCharacteristic?
  lazy var w5Link = W5LinkController(bb: self)
  /// Peripheral-side: a notify that updateValue refused (queue full) — retried
  /// only from peripheralManagerIsReady(toUpdateSubscribers:).
  private var pendingNotify = false
  /// W5 is a TEST-ONLY link layer until proven through the awake gates; gated
  /// by the INRANGE_W5_LINKS dart-define (persisted here by Dart). Off = pure
  /// token-read behavior, no persistent connections.
  var w5LinksEnabled: Bool {
    // H-DIAG-1/H-DIAG-4: diagnostic W5 must be gated by the COMPILE flag, not
    // a stale persisted bool that reads `true` before Dart attaches. In a
    // production binary this is a constant false — the whole W5/CA6E link
    // layer is inert regardless of what a prior diag install left in defaults.
    #if INRANGE_DIAG
      // Fail closed: W5 requires BOTH the opt-in flag AND a REAL fleet key
      // (injected or Dart-provisioned — never the generated per-install
      // fallback). So a stale persisted flag from a prior install cannot enable
      // W5 under a random/absent key even if the Dart key-ready gate could not
      // reach us (e.g. a swallowed setW5Links(false) on a flaky channel).
      return defaults.bool(forKey: Self.keyW5Links) && W5Diag.hasFleetKey
    #else
      return false
    #endif
  }

  /// REAL W5 quiescence (A1): not the persisted feature flag, but proof that no
  /// live W5 work exists — no sessions, no in-flight connects, and the
  /// controller holds no links/leases/timers. Deliberately does NOT short-circuit
  /// on `w5LinksEnabled`: disabling the flag does not tear down links/timers that
  /// were already live, so a stale session or a pending persist could survive a
  /// flag flip; quiescence must be judged from real state alone. (In a prod build
  /// the flag is compile-false and these collections are always empty, so this
  /// still returns true without any W5 work.)
  var isW5Quiescent: Bool {
    w5.isEmpty && inflight.isEmpty && w5Link.isQuiescent
  }

  // Callback-primed cadence: after a write CONFIRMS (didWriteValueFor), the
  // next beat is scheduled ~4 s out. Herald-shaped — not an instant loop.
  private static let w5Cadence: TimeInterval = 4
  private static let keyW5Links = "bb.w5links"
  // The diag HELLO delay is no longer an always-on constant — it is a ONE-SHOT,
  // explicitly-armed diagnostic control (W5Diag.armHelloDelay / consumeHelloDelay),
  // so it never slows an ordinary diag handshake.
  private static let keySchema = "bb.stateSchema"
  // Flavor+schema stamp: production and diag builds must not consume each
  // other's persisted operational state (issue #8). Bump on schema changes.
  #if INRANGE_DIAG
    private static let stateSchemaStamp = "diag.v1"
  #else
    private static let stateSchemaStamp = "prod.v1"
  #endif

  /// H-DIAG-3: on every launch, before any manager restoration, drop bb.*
  /// operational state whose stamp is missing or from a different flavor —
  /// stale diag tokens/flags/logs can never reactivate a release binary.
  /// Documented diagnostic-file location: the app container's Documents
  /// directory (USB-pullable via devicectl). Every diagnostic artifact lives
  /// here; a foreign-flavor boot wipes them all.
  static let diagnosticFileNames = [
    "bb_wake_log.txt", "bb_wake_log.1.txt",
    "w5_events.jsonl", "w5_events.1.jsonl",
    "w5_rssi_log.jsonl", "w5_rssi_log.1.jsonl",
  ]
  /// Returns `true` only if every diagnostic artifact was actually removed — the
  /// C5 foreign-flavor transition inspects this BEFORE deleting keys / advancing
  /// the stamp, so a partial wipe cannot strand old-key evidence under new keys.
  @discardableResult
  static func wipeDiagnosticFiles() -> Bool {
    #if INRANGE_DIAG
      // Wipe through the writer inventory so EVERY current + rotated artifact
      // (incl. w5_rssi_log.1.jsonl) is removed, typed, session-locked, and bumps
      // the wipe generation — no silent bypass of the writer abstraction (R3).
      return W5Diag.wipeAllEvidenceFiles()
    #else
      // Release ships no evidence machinery; defensively remove any stale files.
      let docs = FileManager.default.urls(
        for: .documentDirectory, in: .userDomainMask)[0]
      var allGone = true
      for name in diagnosticFileNames {
        let u = docs.appendingPathComponent(name)
        do { try FileManager.default.removeItem(at: u) }
        catch { if FileManager.default.fileExists(atPath: u.path) { allGone = false } }
      }
      return allGone
    #endif
  }

  /// The current build's operational flavor stamp (diag.v1 / prod.v1) — the
  /// value a persisted W5 snapshot must carry to be restorable in THIS flavor.
  static var operationalFlavor: String { stateSchemaStamp }

  private func reconcileStateStamp() {
    let stamp = defaults.string(forKey: Self.keySchema)
    if stamp == Self.stateSchemaStamp { return }
    if stamp == nil {
      // Legacy install predating the stamp: this is legitimate same-flavor
      // state (an existing production user upgrading). Adopt it — wiping here
      // would silently disable a real user's beacon (Codex H-DIAG-3).
      defaults.set(Self.stateSchemaStamp, forKey: Self.keySchema)
      logWake("state-stamp-adopted-legacy")
      return
    }
    // A DIFFERENT non-nil stamp = genuine cross-flavor collision: wipe ALL
    // foreign operational state — UserDefaults keys, the persisted W5 lease
    // snapshot, AND every diagnostic file — so nothing from another flavor
    // survives into this launch (Phase 3 complete foreign-flavor wipe).
    //
    // C5/B3-B4 — TRANSACTIONAL: wipe the evidence FILES first and inspect the
    // typed per-file result. Only if EVERY file was actually removed do we delete
    // the old-flavor keys (incl. the run secrets) and advance the stamp. On any
    // partial wipe we keep the old keys AND the old stamp, record a durable
    // failure, and return — so the stranded old-flavor evidence stays consistent
    // with its own keys, no new-key success marker is appended into it, and the
    // wipe is retried on the next launch (idempotent) instead of silently
    // producing mixed-flavor evidence.
    let wiped = Self.wipeDiagnosticFiles()
    if !wiped {
      logWake("state-stamp-wipe-FAILED-\(stamp!)")  // keys + stamp unchanged; retry next launch
      return
    }
    for key in ["bb.enabled", "bb.slots", "bb.buffer", "bb.pingUrl",
                "bb.pingAuth", Self.keyW5Links, "bb.w5rssi.off",
                "bb.w5.snapshot", "bb.w5events.dropped",
                // B4: per-family dropped counters + the persisted run secrets.
                "bb.evwrite.dropped.w5_events.jsonl",
                "bb.evwrite.dropped.bb_wake_log.txt",
                "bb.evwrite.dropped.w5_rssi_log.jsonl",
                "bb.w5diag.runsecret", "bb.w5diag.provisionedsecret",
                "bb.w5diag.destroyed", "bb.w5diag.lifetimeloss"] {
      defaults.removeObject(forKey: key)
    }
    defaults.set(Self.stateSchemaStamp, forKey: Self.keySchema)
    logWake("state-stamp-wiped-\(stamp!)")
  }

  // peripheral.identifier → (tokenHex, cachedAt)
  private var tokenCache: [UUID: (hex: String, at: Date)] = [:]
  // peripherals we're currently connected/connecting to, kept strongly.
  private var inflight: [UUID: CBPeripheral] = [:]
  private var inflightRSSI: [UUID: Int] = [:]
  private var lastConnectAttempt: [UUID: Date] = [:]
  private var lastScanRestart = Date.distantPast
  private var scanHeartbeat: Timer?

  /// Last verdict from peripheralManagerDidStartAdvertising, retained so the
  /// state snapshot can be rebuilt on demand: an invokeMethod issued while
  /// backgrounded is silently dropped by a suspended engine (same hazard as
  /// the sighting buffer), so Dart re-pulls the truth via `bleState`.
  /// Prior-art review 2026-07-26, finding 1.3.
  private var advertisingActive = false
  private var advertisingError: String?
  /// role → last state name written to bb_wake_log.txt, so W5 logs
  /// transitions rather than re-logging a steady state.
  private var lastLoggedManagerState: [String: String] = [:]

  // #8: MUST stay operationalDefaults() — diag builds persist in their own
  // suite; UserDefaults.standard here would silently break diag isolation.
  // Internal (not private): W5LinkController reads the same domain.
  var defaults: UserDefaults { Self.operationalDefaults() }

  // MARK: - Lifecycle

  /// Called from AppDelegate on EVERY launch. When iOS relaunched us for a
  /// bluetooth event (or the user had the beacon on before a jetsam), the
  /// persisted enabled flag brings both managers straight back up — no
  /// Flutter engine required to serve GATT reads or buffer sightings.
  func bootFromPersistence() {
    #if INRANGE_DIAG
      // C4/B3: arm the key-ready gate FIRST — before any restoration emit. Native
      // restoration runs here, before Dart; handled W5 events buffer until the
      // launch key is confirmed (Dart provision, or an authoritative env key),
      // then flush under the confirmed key. So a changed artifact (key A→B) never
      // writes a handled event under stale A, and no restoration marker is lost.
      W5Diag.beginLaunchKeyGate()
    #endif
    // Tell Dart a non-empty buffer is waiting whenever the app returns to
    // foreground — the engine is only trustworthy while active. Delivery is
    // pull-and-ack (see drainBuffer/ackBuffer): nothing is deleted here.
    NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification, object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.notifyBufferReady()
    }
    // Scheduled background wakes: the free-account path to both-iPhones-
    // asleep discovery. iOS grants opportunistic ~30 s windows (min 15 min
    // apart); each is a full scan burst while the screen stays dark. Two
    // sleeping iPhones sharing a venue eventually land overlapping windows.
    // (Silent push — paid account — is the deterministic upgrade.)
    // Must register BEFORE didFinishLaunching returns.
    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: Self.wakeTaskID, using: .main
    ) { [weak self] task in
      self?.handleWake(task: task)
    }
    NotificationCenter.default.addObserver(
      forName: UIApplication.didEnterBackgroundNotification, object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.scheduleWake()
    }
    reconcileStateStamp()  // H-DIAG-3: before any restoration
    logWake("boot enabled=\(defaults.bool(forKey: Self.keyEnabled))")
    // A4: PEEK the prior run's loss, durably RECORD it, then ACK — a failed boot
    // append can never erase prior loss before it is recorded.
    W5Diag.recordPriorLoss()
    W5Diag.emit(.boot, role: .app,
      result: defaults.bool(forKey: Self.keyEnabled) ? "enabled" : "disabled")
    // Cold-launch marker: whether a W5 snapshot is present to restore. Combined
    // with the presence/absence of preceding restore* events in the JSONL this
    // lets Case 3 tell a fresh cold launch from an OS restoration relaunch.
    W5Diag.emit(.coldLaunch, role: .app,
      result: defaults.object(forKey: "bb.w5.snapshot") != nil
        ? "snapshotPresent" : "fresh")
    if defaults.bool(forKey: Self.keyEnabled) {
      ensureManagers()
      scheduleWake()
    }
  }

  private static let wakeTaskID = "io.inrange.beacon.wake"

  private func scheduleWake() {
    guard enabled else { return }
    let req = BGAppRefreshTaskRequest(identifier: Self.wakeTaskID)
    req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
    do {
      try BGTaskScheduler.shared.submit(req)
    } catch {
      // Duplicate submissions and simulator denials land here — harmless.
    }
  }

  private func handleWake(task: BGTask) {
    scheduleWake()  // always chain the next window
    logWake("bgtask")
    guard enabled else {
      task.setTaskCompleted(success: true)
      return
    }
    sendWakePing()
    // One long scan session for the window; sessions must be long — short
    // ones die before iOS's coalesced deliveries arrive (2026-07-23 bench).
    restartScanNow()
    reconfigureAdvertising()  // re-assert the advert while we have cycles
    // Double-completion is a documented no-op for the OS but muddies crash
    // logs; complete exactly once from whichever fires first.
    var completed = false
    let completeOnce = {
      if !completed {
        completed = true
        task.setTaskCompleted(success: true)
      }
    }
    task.expirationHandler = { completeOnce() }
    DispatchQueue.main.asyncAfter(deadline: .now() + 20) { completeOnce() }
  }

  func attach(messenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(
      name: "io.inrange/background_beacon", binaryMessenger: messenger)
    channel = ch
    ch.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return result(FlutterMethodNotImplemented) }
      switch call.method {
      case "start":
        self.storeSlots(call.arguments)
        self.defaults.set(true, forKey: Self.keyEnabled)
        self.ensureManagers()
        self.reconfigureAdvertising()
        self.ensureScanning()
        self.notifyBufferReady()
        // Hand Dart a full snapshot immediately — the bool below only says
        // whether the peripheral manager happened to be up (finding 1.3).
        self.notifyBleState()
        result(self.peripheralMgr?.state == .poweredOn)
      case "updateBatch":
        self.storeSlots(call.arguments)
        self.reconfigureAdvertising()
        result(nil)
      case "stop":
        self.defaults.set(false, forKey: Self.keyEnabled)
        self.stopEverything()
        result(nil)
      case "isEnabled":
        // Dart's session-restore path keys off this: after an eviction the
        // native side is the ONLY component that knows the beacon is on.
        result(self.enabled)
      case "drainBufferedSightings":
        // Pull-and-ack: return the buffer WITHOUT clearing it; Dart acks via
        // ackBufferedSightings once the sightings are ingested. A crash
        // between drain and ack re-delivers — it never loses (audit
        // 2026-07-25, critical #6).
        let ud = self.defaults.array(forKey: Self.keyBuffer) as? [[String: Any]] ?? []
        // UD buffer first, then the W5 file log — ack splits in this order.
        result(ud + self.w5Link.drainFileSamples())
      case "ackBufferedSightings":
        let count = (call.arguments as? Int) ?? 0
        let udCount = (self.defaults.array(forKey: Self.keyBuffer) ?? []).count
        self.ackBuffer(min(count, udCount))
        self.w5Link.ackFileSamples(count - min(count, udCount))
        result(nil)
      case "bleState":
        // Pull path for finding 1.3: an onBleState push issued while the app
        // was backgrounded is accepted and silently dropped by a suspended
        // engine, so Dart re-reads the authoritative state on foregrounding —
        // same reasoning as the sighting buffer's pull-and-ack.
        result(self.bleStateSnapshot())
      case "dropPeer":
        // Owner rule: a resolved pair (pass/reject) drops its W5 session
        // immediately — no tracking anyone the user said no to.
        if let hex = call.arguments as? String {
          result(self.dropPeerByToken(hex))
        } else {
          result(["lookupHit": false, "rolesClosed": [String](),
                  "leaseEnded": false, "rawSessionsReaped": 0])
        }
      case "setWakePing":
        // Crack #1 client half (issue #4): {url, auth} for the coarse
        // co-presence ping fired on every background wake. Flag-gated:
        // no url stored → no pings. Server half is hazypiff's.
        if let args = call.arguments as? [String: Any] {
          self.defaults.set(args["url"] as? String, forKey: Self.keyPingURL)
          self.defaults.set(args["auth"] as? String, forKey: Self.keyPingAuth)
        }
        result(nil)
      case "setDiagRunSecret":
        // Diag-only: provision the shared fleet run secret (hex) so HMAC
        // handles align across a fleet and survive OS restoration. Returns the
        // structured provisioning ack (`ok`, `rotated`, `keyEpoch`) so Dart can
        // AWAIT it and fail closed — never enabling W5 on an unprovisioned key
        // (A3). No-op in a release binary (W5Diag compiles the body out).
        result(self.provisionDiagRunSecret((call.arguments as? String) ?? ""))
      // E-B2 (codex): the raw-alias "armW5Fault" channel case was REMOVED so a raw
      // peer token can never cross the channel. Fault arming is handle-based only
      // ("armW5FaultForPeer"); W5Diag.armFault(peerRaw:) is now called ONLY
      // internally, after native resolves an eligible handle→raw.
      case "disarmW5Fault":
        // Diag-only: clear any pending fault. No-op in a release binary.
        W5Diag.disarmFault()
        result(nil)
      case "armW5HelloDelay":
        // Diag-only: arm a one-shot HELLO delay (seconds) for the next dial.
        W5Diag.armHelloDelay((call.arguments as? Double) ?? 0)
        result(nil)
      case "listW5Peers":
        // E-B2: the installed selected-peer UI's eligible list — run-scoped
        // handles ONLY (raw aliases stay native). Empty in a release binary.
        result(self.diagListW5Peers())
      case "armW5FaultForPeer":
        // E-B2: arm a one-shot pre-ACK fault (+ optional delay) for a peer chosen
        // by its handle in the installed UI. Fails closed on nil/empty/ineligible.
        let a = call.arguments as? [String: Any]
        result(self.armW5FaultForPeer(
          handle: a?["handle"] as? String,
          delaySeconds: (a?["delaySeconds"] as? Double) ?? 0))
      case "w5DiagStatus":
        // E-B2: current armed handle / delay / eligible count for the UI.
        result(self.w5DiagStatus())
      case "recordW5Teardown":
        // Diag-only: record a pass's teardown OUTCOME (already sanitized — role
        // names + counts, no raw ids) in the structured evidence layer, so all
        // four outcomes (tore / unavailable / stale-miss / native-unavailable)
        // are operationally attributable, not just debugPrint'd.
        W5Diag.emit(.dropPeer, role: .app, result: call.arguments as? String,
          reason: "passOutcome")
        result(nil)
      case "resetW5Case":
        // Owner ruling: RETAIN the fleet secret, rotate the public case epoch,
        // wipe evidence, clear controls + sequence. Returns a structured ack.
        result(W5Diag.resetCase())
      case "destroyW5Secret":
        // Owner ruling: the ONLY secret-destroying op; rejected unless W5 is
        // genuinely QUIESCENT (live managers/sessions, not the persisted flag).
        result(W5Diag.destroySessionSecret(w5Quiescent: self.isW5Quiescent))
      case "setW5Links":
        // Gate for W5 persistent links (C2/A3). OFF is an ATOMIC EFFECTIVE-OFF
        // TRANSACTION, not a Boolean echo: it tears down every W5-specific live/
        // restored producer, then returns the STRUCTURED effective state. Dart
        // continues only when the ack proves BOTH `effectiveEnabled==false` AND
        // `quiescent==true` — a stored `false` flag alone never proves W5 stopped.
        let want = (call.arguments as? Bool) ?? false
        self.defaults.set(want, forKey: Self.keyW5Links)
        if !want { self.w5EffectiveOff() }
        result([
          "flag": self.defaults.bool(forKey: Self.keyW5Links),
          "effectiveEnabled": self.w5LinksEnabled,
          "quiescent": self.isW5Quiescent,
        ])
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private var enabled: Bool { defaults.bool(forKey: Self.keyEnabled) }

  private func ensureManagers() {
    if peripheralMgr == nil {
      peripheralMgr = CBPeripheralManager(
        delegate: self, queue: nil,
        options: [CBPeripheralManagerOptionRestoreIdentifierKey: Self.peripheralRestoreID])
    }
    if centralMgr == nil {
      centralMgr = CBCentralManager(
        delegate: self, queue: nil,
        options: [CBCentralManagerOptionRestoreIdentifierKey: Self.centralRestoreID])
    }
  }

  /// C2: a real W5 effective-OFF is an ATOMIC teardown, not a Boolean echo.
  /// Disabling the persisted flag alone leaves any already-live or OS-RESTORED
  /// W5 session/lease/link/timer running under a stale key. This reaps every
  /// W5-specific producer — the controller's leases/links/timers/ownership AND
  /// its persisted snapshot (via `beaconOff`), every W5 session, and any inflight
  /// W5 dial — so afterward `isW5Quiescent` is true and no restored old-key state
  /// survives. It deliberately leaves the shared beacon advertiser/scanner alone;
  /// W5 links are a strict subset of the beacon's lifecycle.
  /// The `setDiagRunSecret` production path (extracted so tests exercise the REAL
  /// flow, not a manual restore). Provisions the fleet key; a FAILED provision
  /// forces W5 OFF natively + reaps state (R5/C2); a SUCCESSFUL provision confirms
  /// the launch key and RE-DRIVES a boot restore that was deferred for want of a
  /// confirmed key (D1) — so a same-key relaunch actually restores its in-grace
  /// leases (the OS `willRestoreState` moment does not refire).
  @discardableResult
  func provisionDiagRunSecret(_ hex: String) -> [String: Any] {
    let provAck = W5Diag.provisionRunSecret(hex)
    if (provAck["ok"] as? Bool) != true {
      defaults.set(false, forKey: Self.keyW5Links)
      w5EffectiveOff()
    } else {
      w5Link.redriveRestoreIfDeferred()
    }
    return provAck
  }

  /// E-B2: the eligible peers for the installed selected-peer control, as
  /// run-scoped handles only (raw aliases are retained natively and never cross
  /// the channel). Empty in a release binary (no W5 links exist).
  func diagListW5Peers() -> [[String: Any]] {
    #if INRANGE_DIAG
      return w5Link.diagEligiblePeers.map { ["handle": $0.handle] }
    #else
      return []
    #endif
  }

  /// E-B2: arm a one-shot pre-ACK fault (+ optional one-shot delay) for the peer
  /// whose run-scoped HANDLE the UI selected. Fails closed on a nil/empty handle
  /// or one not currently eligible (wrong-peer / stale / wildcard). The raw alias
  /// is resolved natively so the installed UI never handles a raw token.
  func armW5FaultForPeer(handle: String?, delaySeconds: Double) -> [String: Any] {
    #if INRANGE_DIAG
      guard let h = handle, !h.isEmpty else {
        return ["ok": false, "rejected": "no-peer"]
      }
      guard let match = w5Link.diagEligiblePeers.first(where: { $0.handle == h })
      else {
        return ["ok": false, "rejected": "peer-not-eligible"]
      }
      var ack = W5Diag.armFault(peerRaw: match.raw)
      // The one-shot delay applies ONLY when the fault actually armed (E-B2:
      // "the delay applies exactly once and only when the selected fault is armed").
      if (ack["ok"] as? Bool) == true, delaySeconds > 0 {
        W5Diag.armHelloDelay(delaySeconds)
        ack["delaySeconds"] = delaySeconds
      } else {
        ack["delaySeconds"] = 0
      }
      return ack
    #else
      return ["ok": false]
    #endif
  }

  /// E-B2: current diagnostic control status for the installed UI.
  func w5DiagStatus() -> [String: Any] {
    #if INRANGE_DIAG
      return [
        "armed": W5Diag.isFaultArmed,
        "eligibleCount": w5Link.diagEligiblePeers.count,
      ]
    #else
      return ["armed": false, "eligibleCount": 0]
    #endif
  }

  func w5EffectiveOff() {
    w5Link.beaconOff()                        // leases/links/timers/ownership + snapshot
    for id in Array(w5.keys) { w5End(id) }    // end every live W5 session
    for (_, p) in inflight { centralMgr?.cancelPeripheralConnection(p) }
    inflight.removeAll()
    inflightRSSI.removeAll()
  }

  private func stopEverything() {
    w5Link.beaconOff()
    for id in Array(w5.keys) { w5End(id) }
    scanHeartbeat?.invalidate()
    scanHeartbeat = nil
    peripheralMgr?.stopAdvertising()
    peripheralMgr?.removeAllServices()
    serviceAdded = false
    centralMgr?.stopScan()
    for (_, p) in inflight { centralMgr?.cancelPeripheralConnection(p) }
    inflight.removeAll()
    inflightRSSI.removeAll()
    // Nothing is advertising or scanning after this; say so rather than
    // leaving the last verdict standing (finding 1.3). The legacy
    // onAdvertisingState bool is deliberately NOT re-fired here — its firing
    // pattern stays byte-for-byte what the Dart consumer already handles.
    advertisingActive = false
    advertisingError = nil
    notifyBleState()
    // Clear per-peer session/discovery state on stop. Without this a cached
    // peer token (15 min TTL) makes a re-enabled scanner emit sightings
    // WITHOUT reconnecting, so W5 never re-establishes — which confounded the
    // 2026-07-29 cold test. A beacon-off is a clean-slate boundary.
    tokenCache.removeAll()
    lastConnectAttempt.removeAll()
    pendingNotify = false
  }

  // MARK: - Token batch

  /// Slots arrive as [[t: hex32, f: epochMs, u: epochMs]] and persist so a
  /// relaunched process can answer reads without Dart.
  private func storeSlots(_ args: Any?) {
    guard let list = args as? [[String: Any]] else { return }
    let sane = list.filter {
      ($0["t"] as? String)?.count == 32 && $0["f"] is NSNumber && $0["u"] is NSNumber
    }
    if !sane.isEmpty { defaults.set(sane, forKey: Self.keySlots) }
  }

  /// The token for the slot covering NOW. Returns nil when nothing covers —
  /// the old fallback served the newest EXPIRED token ("stale beats
  /// nothing"), but every claim on an expired token is unresolvable
  /// server-side, so peers burned a connect + read for a token the server
  /// would reject. With today+tomorrow batches (0060 client side) an
  /// uncovered "now" only happens after >24 h without Dart, and the honest
  /// answer then is no token at all.
  func currentTokenHex() -> String? {
    guard let list = defaults.array(forKey: Self.keySlots) as? [[String: Any]] else {
      return nil
    }
    let nowMs = Date().timeIntervalSince1970 * 1000
    var covering: (hex: String, from: Double)?
    for s in list {
      guard let hex = s["t"] as? String,
            let f = (s["f"] as? NSNumber)?.doubleValue,
            let u = (s["u"] as? NSNumber)?.doubleValue else { continue }
      if f <= nowMs && nowMs < u && (covering == nil || f > covering!.from) {
        covering = (hex, f)
      }
    }
    return covering?.hex
  }

  static func hexToData(_ hex: String) -> Data? {
    guard hex.count == 32 else { return nil }
    var out = Data(capacity: 16)
    var idx = hex.startIndex
    for _ in 0..<16 {
      let next = hex.index(idx, offsetBy: 2)
      guard let b = UInt8(hex[idx..<next], radix: 16) else { return nil }
      out.append(b)
      idx = next
    }
    return out
  }

  // MARK: - Advertising (peripheral role)

  private func reconfigureAdvertising() {
    guard let pm = peripheralMgr, pm.state == .poweredOn, enabled else { return }
    if !serviceAdded {
      let char = CBMutableCharacteristic(
        type: Self.tokenCharUUID, properties: [.read], value: nil,
        permissions: [.readable])
      // .write (WITH response), not .writeWithoutResponse: Herald documents a
      // ~30 s iOS queue stall + supervision-timeout disconnect from unacked
      // writes (heraldprox.io/bluetooth/os), which matches the 2026-07-29
      // parted-7 failure. The ack is also the link-layer traffic that resets
      // the supervision timer.
      let keepalive = CBMutableCharacteristic(
        type: Self.keepaliveCharUUID,
        properties: [.notify, .write], value: nil,
        permissions: [.writeable])
      keepaliveNotifyChar = keepalive
      let control = CBMutableCharacteristic(
        type: Self.controlCharUUID,
        properties: [.notify, .write], value: nil,
        permissions: [.writeable])
      controlNotifyChar = control
      let service = CBMutableService(type: Self.serviceUUID, primary: true)
      service.characteristics = [char, keepalive, control]
      pm.add(service)
      serviceAdded = true
    }
    pm.stopAdvertising()
    // Marker + token-as-UUID: foreground peers keep today's no-connect fast
    // path; background iOS degrades this to the overflow area automatically
    // and peers fall back to the GATT read.
    var uuids: [CBUUID] = [Self.serviceUUID]
    if let hex = currentTokenHex(), let data = Self.hexToData(hex) {
      uuids.append(CBUUID(data: data))
      // Rotation: tell every established W5 link in-band (ALIAS_ROLL).
      if w5LinksEnabled { w5Link.advertisedTokenChanged(hex) }
    }
    pm.startAdvertising([CBAdvertisementDataServiceUUIDsKey: uuids])
  }

  // MARK: - Scanning (central role)

  private func ensureScanning() {
    guard let cm = centralMgr, cm.state == .poweredOn, enabled else { return }
    cm.scanForPeripherals(
      withServices: [Self.serviceUUID],
      options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    lastScanRestart = Date()
    startHeartbeat()
  }

  /// iOS reports each device ONCE per scan session (duplicates suppressed),
  /// so a scan must be restarted to re-surface present peers. Restarting
  /// only from discovery callbacks deadlocks (no discovery → no restart —
  /// first bench test, 2026-07-23); this heartbeat breaks the cycle. It
  /// fires while the app has execution time: always in foreground, and in
  /// background whenever a BT event (a peer's GATT read of our token, a
  /// delivery, a state change) wakes us.
  private func startHeartbeat() {
    guard scanHeartbeat == nil else { return }
    scanHeartbeat = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) {
      [weak self] _ in
      guard let self = self, self.enabled else { return }
      if self.inflight.isEmpty { self.restartScanNow() }
    }
  }

  private func restartScanNow() {
    guard let cm = centralMgr, cm.state == .poweredOn, enabled else { return }
    lastScanRestart = Date()
    // H-W5-3: piggyback the pending-dial TTL sweep on the scan cadence.
    if w5LinksEnabled { w5Link.sweepStalePendingDials(now: Date()) }
    cm.stopScan()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      guard let self = self, self.enabled,
            let c = self.centralMgr, c.state == .poweredOn else { return }
      c.scanForPeripherals(
        withServices: [Self.serviceUUID],
        options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }
  }

  /// Duplicates are coalesced (hard-off in background), so a discovered
  /// peripheral would otherwise be reported once per scan session. Restarting
  /// the scan re-surfaces present peers — the Herald-era pattern. Throttled.
  private func scheduleScanRestart() {
    let now = Date()
    guard now.timeIntervalSince(lastScanRestart) >= Self.scanRestartFloor else { return }
    restartScanNow()
  }

  /// An in-range Android's token, straight off the advert — finding B1
  /// (prior-art review 2026-07-26), the best impact-to-cost fix in that review.
  ///
  /// Until 2026-07-26 this module built its candidate list from
  /// `CBAdvertisementDataServiceUUIDsKey` + the overflow key ONLY. So an
  /// in-range Android was discovered by its CAFE marker, offered no 16-byte
  /// token service UUID, and fell through to `central.connect`. That connect
  /// can NEVER succeed: the Android advert is `connectable: false`
  /// (`beacon_service.dart:727`) and there is no Android GATT server at all
  /// (flutter_ble_peripheral 2.1.1 ships its server code commented out). The
  /// iPhone→Android direction was therefore not degraded but dead, and every
  /// attempt also burned that peer's 5-minute `connectRetryFloor` — forever.
  ///
  /// No GATT server is needed for this direction: the token is 16 bytes and is
  /// already on the air. Prior art that a *filtered* iOS scan still delivers
  /// Android manufacturer data — `opentrace-ios/.../CentralController.swift:100`
  /// scans `withServices:` and reads `CBAdvertisementDataManufacturerDataKey`
  /// from Android peers at `:165` in the same callback; DP-3T-prestandard makes
  /// the ordering explicit at `BluetoothDiscoveryService.swift:165`,
  /// *"// Only connect if we didn't got a EphId in the Advertisement"*.
  /// OpenTrace still had to connect because its tempID is a base64 JSON blob
  /// too big for an advert; in-range's 16 bytes are not.
  ///
  /// Layout mirrors `beacon_service.dart:703-705` exactly:
  /// `[company id, little-endian][16-byte correlation id][flag byte]`, flag
  /// bit0 = medium-power slot. The flag byte is OPTIONAL (16-byte adverts
  /// predate it, and `beacon_service.dart:968` still accepts both lengths) and
  /// is never part of the token — folding it in would corrupt every id. Any
  /// other length is rejected outright rather than read at a guessed offset.
  private static func androidAdvertToken(
    _ advertisementData: [String: Any]
  ) -> (hex: String, mediumPower: Bool)? {
    guard let raw = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
          raw.count >= 18
    else { return nil }
    let bytes = [UInt8](raw)
    // CoreBluetooth returns the whole AD field, company id included, and the
    // company id is little-endian on air.
    let company = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
    guard company == inRangeCompanyID else { return nil }
    let body = bytes.count - 2
    guard body == 16 || body == 17 else { return nil }
    let hex = bytes[2..<18].map { String(format: "%02x", $0) }.joined()
    let mediumPower = body == 17 && (bytes[18] & 0x01) != 0
    return (hex, mediumPower)
  }

  // MARK: - Sighting delivery

  /// `mediumPower` carries B1's Android flag bit0 (`beacon_service.dart:705`).
  /// It matters: "heard on medium" IS the physical feet_30 gate, so an Android
  /// sighting mislabelled as high-power would silently widen that tier. iOS
  /// peers have no power flag — high is the only slot they advertise in — so
  /// the default preserves every pre-existing call site exactly.
  private func emitSighting(tokenHex: String, rssi: Int, mediumPower: Bool = false) {
    let ts = Int(Date().timeIntervalSince1970 * 1000)
    let sighting: [String: Any] = [
      "token": tokenHex, "rssi": rssi, "ts": ts,
      "pwr": mediumPower ? "medium" : "high",
    ]
    // NEVER hand a background sighting to the Flutter engine: a suspended
    // engine's channel accepts the call and silently drops it (dark-bench
    // 2026-07-23 — native discoveries happened, Dart never saw them).
    // Background → persist natively; Dart pulls and acks when it is ready.
    if UIApplication.shared.applicationState == .active, let ch = channel {
      ch.invokeMethod("onSighting", arguments: sighting)
    } else {
      var buf = (defaults.array(forKey: Self.keyBuffer) as? [[String: Any]]) ?? []
      buf.append(sighting)
      if buf.count > Self.bufferCap { buf.removeFirst(buf.count - Self.bufferCap) }
      defaults.set(buf, forKey: Self.keyBuffer)
    }
  }

  /// Tells Dart the buffer is non-empty so it can pull (drain) and ack.
  /// Never delivers the sightings itself — a pushed batch whose delivery is
  /// not confirmed can be lost on a cold launch, which is exactly the bug
  /// pull-and-ack exists to close.
  private func notifyBufferReady() {
    guard let ch = channel,
          UIApplication.shared.applicationState == .active,
          let buf = defaults.array(forKey: Self.keyBuffer) as? [[String: Any]],
          !buf.isEmpty else { return }
    ch.invokeMethod("onBufferedSightingsReady", arguments: nil)
  }

  /// Drops the first [count] buffered sightings — called only after Dart
  /// confirms ingestion of that many drained entries.
  private func ackBuffer(_ count: Int) {
    guard count > 0,
          var buf = defaults.array(forKey: Self.keyBuffer) as? [[String: Any]],
          !buf.isEmpty else { return }
    buf.removeFirst(min(count, buf.count))
    if buf.isEmpty {
      defaults.removeObject(forKey: Self.keyBuffer)
    } else {
      defaults.set(buf, forKey: Self.keyBuffer)
    }
  }

  /// Direct native wake path for the subtle-wake tiers (audit 2026-07-25,
  /// critical #5): an SLC/region/silent-push wake nudges the BLE carrier
  /// immediately — a fresh scan session plus a re-asserted advert — instead
  /// of waiting for the async Dart burst to spin up. Cheap and idempotent.
  func nudge(reason: String) {
    guard enabled else { return }
    logWake(reason)
    restartScanNow()
    reconfigureAdvertising()
  }

  // MARK: - BLE state surface (finding 1.3, prior-art review 2026-07-26)

  /// Until 2026-07-26 the ENTIRE outbound state surface was this one bool. It
  /// was raised `false` both when the peripheral manager wasn't `poweredOn`
  /// and when `didStartAdvertising` errored, so Dart could not tell BT-off
  /// from permission-denied from a transient advertising failure — and it
  /// covered the peripheral role only, so the app could be simultaneously
  /// non-advertising AND non-scanning while the UI said "discoverable", which
  /// is precisely what the project's don't-lie-about-discoverability rule
  /// forbids. Kept firing verbatim (additive migration, never a rename) so the
  /// Dart consumer keeps working while `onBleState` rolls out.
  private func notifyAdvertisingState(_ ok: Bool, error: Error? = nil) {
    advertisingActive = ok
    // nil error on a `false` verdict means the reason is the manager state,
    // not a start failure — the peripheral field carries it.
    advertisingError = error?.localizedDescription
    channel?.invokeMethod("onAdvertisingState", arguments: ok)
    notifyBleState()
  }

  private static func stateName(_ s: CBManagerState) -> String {
    switch s {
    case .poweredOn: return "poweredOn"
    case .poweredOff: return "poweredOff"
    case .unauthorized: return "unauthorized"
    case .unsupported: return "unsupported"
    case .resetting: return "resetting"
    default: return "unknown"  // .unknown, plus anything a later iOS adds
    }
  }

  /// The two-manager snapshot. Both CoreBluetooth roles are reported
  /// SEPARATELY on purpose: Dart has to know *which* side is dead, because
  /// "can't be seen" and "can't see" have different user-facing copy and
  /// different remedies. Herald's worst-state-wins collapse into one verdict
  /// is done Dart-side, over these two values.
  private func bleStateSnapshot() -> [String: Any] {
    let periphState: CBManagerState = peripheralMgr?.state ?? .unknown
    let centralState: CBManagerState = centralMgr?.state ?? .unknown
    // Advertising requires BOTH a live manager and a successful
    // didStartAdvertising — the distinction the old single bool destroyed.
    let isAdvertising: Bool = advertisingActive && periphState == .poweredOn
    let isScanning: Bool = centralMgr?.isScanning ?? false
    var out: [String: Any] = [
      "peripheral": Self.stateName(periphState),
      "central": Self.stateName(centralState),
      "advertising": isAdvertising,
      "scanning": isScanning,
      "enabled": enabled,
    ]
    if let err = advertisingError { out["advertisingError"] = err }
    return out
  }

  private func notifyBleState() {
    channel?.invokeMethod("onBleState", arguments: bleStateSnapshot())
  }

  /// W5: append manager-state transitions to the existing bb_wake_log.txt so
  /// the USB-pull workflow shows whether the SCAN side ever died silently
  /// while advertising looked healthy — 2026-07-24's overnight soak produced
  /// zero samples and zero evidence of WHY. Change-only: manager states are
  /// rare events, and a re-logged steady state would bury the transitions.
  private func logManagerState(_ role: String, _ state: CBManagerState) {
    let name = Self.stateName(state)
    guard lastLoggedManagerState[role] != name else { return }
    lastLoggedManagerState[role] = name
    logWake("\(role)-state:\(name)")
  }

  /// Crack #1 (issue #4): coarse co-presence ping on every background wake.
  /// Deliberately carries NO location — the server sees the request's source
  /// IP + the caller's identity + timestamp, and matches co-presence from
  /// same-network/same-window overlap. Nothing new is collected client-side.
  /// Silent until Dart provides an endpoint (hazypiff's server half).
  private func sendWakePing() {
    guard let urlStr = defaults.string(forKey: Self.keyPingURL),
          let url = URL(string: urlStr),
          let auth = defaults.string(forKey: Self.keyPingAuth) else { return }
    var req = URLRequest(url: url, timeoutInterval: 10)
    req.httpMethod = "POST"
    req.setValue("Bearer \(auth)", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try? JSONSerialization.data(withJSONObject: [
      "ts": Int(Date().timeIntervalSince1970 * 1000),
      "kind": "bgtask",
    ])
    URLSession.shared.dataTask(with: req) { [weak self] _, resp, _ in
      let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
      self?.logWake("ping-\(code)")
    }.resume()
  }

  /// Soak-test observability (2026-07-24: overnight soak produced zero
  /// samples and zero evidence of WHY): append wake/read events to a file
  /// in Documents so a USB pull can show whether iOS granted windows at
  /// all, separately from whether scans saw anything during them.
  /// #8: diagnostic-only — compiled out of production entirely.
  func logWake(_ kind: String) {
    #if INRANGE_DIAG
      // B4: one serialized writer with absent-vs-inaccessible handling,
      // protection + backup exclusion after every op, and a bounded drop
      // counter — the wake log no longer risks replacing a locked file with a
      // single line.
      W5Diag.wakeWriter.append("\(Int(Date().timeIntervalSince1970 * 1000)) \(kind)\n")
    #endif
  }
}

// MARK: - CBPeripheralManagerDelegate

extension BackgroundBeacon: CBPeripheralManagerDelegate {
  func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    logManagerState("periph", peripheral.state)
    if peripheral.state == .poweredOn {
      if didRestorePeripheral {
        // Restoration relaunch: willRestoreState already recovered the
        // registered service (characteristics and subscriptions intact).
        // Resetting serviceAdded here would re-add it → .alreadyRegistered
        // and a briefly orphaned read characteristic.
        didRestorePeripheral = false
      } else {
        serviceAdded = false  // genuine fresh start / power cycle
      }
      reconfigureAdvertising()
      // reconfigureAdvertising is a no-op unless enabled, and when it does run
      // the definitive verdict arrives via didStartAdvertising — but Dart still
      // needs to learn the manager came up at all (finding 1.3).
      notifyBleState()
    } else {
      notifyAdvertisingState(false)
    }
  }

  func peripheralManager(
    _ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any]
  ) {
    // iOS relaunched us to service a GATT read or advert event. The restored
    // services are the SAME CBMutableService objects we registered, still
    // holding their characteristics — mark registration recovered and let
    // didUpdateState re-assert the advert without re-adding the service.
    didRestorePeripheral = true
    let _restSvc = (dict[CBPeripheralManagerRestoredStateServicesKey] as? [CBMutableService])?.count ?? 0
    logWake("w5-restored-periph n=\(_restSvc)")
    W5Diag.emit(.restorePeriph, role: .app, count: _restSvc)
    if let services = dict[CBPeripheralManagerRestoredStateServicesKey] as? [CBMutableService] {
      for svc in services where svc.uuid == Self.serviceUUID {
        if (svc.characteristics ?? []).contains(where: { $0.uuid == Self.tokenCharUUID }) {
          serviceAdded = true
        }
        // H-W5-2: re-bind BOTH notify characteristic references from the
        // restored service. They are created only inside the !serviceAdded
        // branch of reconfigureAdvertising, so without this they stay nil for
        // the process lifetime: the device keeps advertising and answering
        // reads (looks healthy) while every notifyControl/keepalive notify
        // silently drops — a HELLO gets .success and its HELLO_ACK vanishes,
        // stalling both endpoints. Restoration is the NORMAL launch path.
        for ch in (svc.characteristics ?? []) {
          if let mutable = ch as? CBMutableCharacteristic {
            if ch.uuid == Self.keepaliveCharUUID { keepaliveNotifyChar = mutable }
            if ch.uuid == Self.controlCharUUID { controlNotifyChar = mutable }
          }
        }
      }
    }
    // If either notify reference could not be recovered, force a clean
    // service rebuild: REMOVE the restored service first (Codex H-W5-2 — a
    // bare serviceAdded=false leaves the live service registered, so
    // reconfigureAdvertising adds a second one and binds the refs to an
    // unregistered replacement while the restored service stays mute). Clear
    // both refs so reconfigureAdvertising rebuilds from scratch.
    if serviceAdded && (keepaliveNotifyChar == nil || controlNotifyChar == nil) {
      logWake("w5-restored-periph notifyRebind=forced")
      W5Diag.emit(.restoreRebind, role: .app, result: "forced")
      peripheral.removeAllServices()
      keepaliveNotifyChar = nil
      controlNotifyChar = nil
      serviceAdded = false
    } else if serviceAdded {
      // Clean recovery: both notify refs re-bound from the restored service.
      // Case 3 must be able to tell this from the forced rebuild above.
      W5Diag.emit(.restoreRebind, role: .app, result: "recovered")
    }
    // W5 lease restoration: load persisted ownership so inbound subscriptions
    // that re-attach via didSubscribeTo are recognized instead of re-minted.
    if w5LinksEnabled { w5Link.restoreFromPersistence() }
  }

  func peripheralManagerDidStartAdvertising(
    _ peripheral: CBPeripheralManager, error: Error?
  ) {
    // The error text is the only thing that separates "advert rejected" from
    // "radio off" on the Dart side — carry it (finding 1.3).
    notifyAdvertisingState(error == nil, error: error)
  }

  // W5 ping-pong, peripheral half: an incoming heartbeat write IS our wake —
  // notify back SYNCHRONOUSLY, now, inside this window. A delayed beat dies
  // when iOS re-suspends us before the timer fires (the 2026-07-29 bug that
  // broke the cascade). The central's notify handler answers instantly in
  // turn, so the two synchronous responses sustain each other with no timer.
  func peripheralManager(
    _ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]
  ) {
    // Validate every request; respond EXACTLY ONCE (responding to the first
    // request in the array acks them all — CB semantics). A .withResponse
    // write that is never answered stalls the central's queue.
    guard let first = requests.first else { return }
    var ok = true
    for request in requests {
      let uuid = request.characteristic.uuid
      if uuid != Self.keepaliveCharUUID && uuid != Self.controlCharUUID { ok = false }
    }
    peripheral.respond(to: first, withResult: ok ? .success : .writeNotPermitted)
    guard ok else { return }
    // CA6E control writes → the ownership adapter; CA5E falls through to the
    // keepalive notify below (unchanged, the proven heartbeat).
    for request in requests where request.characteristic.uuid == Self.controlCharUUID {
      if w5LinksEnabled, let value = request.value {
        w5Link.controlWrite(request.central, value)
      }
    }
    guard requests.contains(where: { $0.characteristic.uuid == Self.keepaliveCharUUID })
    else { return }
    // Notify back so a SUSPENDED central still gets a wake (bidirectional).
    // Queue on refusal; retry only from peripheralManagerIsReady.
    if let ch = keepaliveNotifyChar {
      let sent = peripheralMgr?.updateValue(
        Data([0x01]), for: ch, onSubscribedCentrals: nil) ?? false
      pendingNotify = !sent
    }
  }

  func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
    w5Link.flushPendingControl()
    guard pendingNotify, let ch = keepaliveNotifyChar else { return }
    let sent = peripheral.updateValue(
      Data([0x01]), for: ch, onSubscribedCentrals: nil)
    pendingNotify = !sent
  }

  func peripheralManager(
    _ peripheral: CBPeripheralManager, central: CBCentral,
    didSubscribeTo characteristic: CBCharacteristic
  ) {
    if characteristic.uuid == Self.controlCharUUID {
      logWake("w5-subscribed ch=control")
      if w5LinksEnabled { w5Link.controlSubscribed(central) }
      return
    }
    guard characteristic.uuid == Self.keepaliveCharUUID,
          let ch = keepaliveNotifyChar else { return }
    logWake("w5-subscribed ch=keepalive")
    // First beat immediately; the central's writes drive the loop after.
    peripheralMgr?.updateValue(Data([0x01]), for: ch, onSubscribedCentrals: [central])
  }

  func peripheralManager(
    _ peripheral: CBPeripheralManager, central: CBCentral,
    didUnsubscribeFrom characteristic: CBCharacteristic
  ) {
    // The inbound physical link is gone (peer central left / powered off).
    if characteristic.uuid == Self.controlCharUUID, w5LinksEnabled {
      w5Link.inboundGone(central)
    }
  }

  func peripheralManager(
    _ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest
  ) {
    guard request.characteristic.uuid == Self.tokenCharUUID,
          let hex = currentTokenHex(), let data = Self.hexToData(hex) else {
      peripheral.respond(to: request, withResult: .attributeNotFound)
      return
    }
    guard request.offset <= data.count else {
      peripheral.respond(to: request, withResult: .invalidOffset)
      return
    }
    request.value = data.subdata(in: request.offset..<data.count)
    peripheral.respond(to: request, withResult: .success)
    logWake("gatt-read")
    // A peer reading our token = a peer in range + a moment of background
    // execution time. Background scan deliveries are coalesced for SECONDS,
    // so sessions must be long: a 2 s restart burst produced ZERO return
    // samples (2026-07-23 bench — every session died before its delivery
    // arrived), while one long session nets ~1 per wake. Best measured
    // shape: extend the wake (~30 s background task) and run two ~10 s
    // sessions inside it.
    var bgTask: UIBackgroundTaskIdentifier = .invalid
    bgTask = UIApplication.shared.beginBackgroundTask {
      UIApplication.shared.endBackgroundTask(bgTask)
      bgTask = .invalid
    }
    restartScanNow()
    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
      guard let self = self, self.enabled, self.inflight.isEmpty else { return }
      self.restartScanNow()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
      if bgTask != .invalid {
        UIApplication.shared.endBackgroundTask(bgTask)
        bgTask = .invalid
      }
    }
  }
}

// MARK: - CBCentralManagerDelegate

extension BackgroundBeacon: CBCentralManagerDelegate, CBPeripheralDelegate {
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    // Finding 1.3 + W5: this callback used to be handled entirely inside Swift
    // and report NOTHING to Dart, so a dead scanner was invisible — the app
    // could be non-advertising and non-scanning while the UI said discoverable.
    // Log first (the wake-log line survives a suspended Flutter engine; the
    // channel push does not), then push, with isScanning read after
    // ensureScanning so the snapshot is not one transition stale.
    logManagerState("central", central.state)
    if central.state == .poweredOn { ensureScanning() }
    notifyBleState()
  }

  func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
    // iOS relaunched us for a central event. Re-attach any restored
    // peripherals and resume the filtered scan so discoveries keep flowing
    // before Dart attaches. Apple requires resuming operations from their
    // preserved point: a restored CONNECTED peripheral picks its token read
    // back up (the whole reason we connected), and a CONNECTING one is kept
    // strongly so its didConnect/didFail has somewhere to land.
    var restoredPeripherals: [CBPeripheral] = []
    let restoredCount = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral])?.count ?? 0
    logWake("w5-restored-central n=\(restoredCount)")
    W5Diag.emit(.restoreCentral, role: .app, count: restoredCount)
    if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
      for p in peripherals {
        p.delegate = self
        switch p.state {
        case .connected:
          inflight[p.identifier] = p
          restoredPeripherals.append(p)
          resumeTokenRead(on: p)
        case .connecting:
          inflight[p.identifier] = p
          restoredPeripherals.append(p)
        default:
          break
        }
      }
    }
    // W5 lease restoration: rebuild ownership from persisted state and re-bind
    // restored outbound peripherals so a relaunch does not re-mint ids.
    if w5LinksEnabled { w5Link.restoreFromPersistence(restoredPeripherals: restoredPeripherals) }
    if enabled {
      ensureScanning()
    }
    // didUpdateState follows and restarts the filtered scan.
  }

  /// Continues a token read on a restored connection from whatever stage the
  /// peripheral already reached — discovery results survive restoration, so
  /// re-running them blindly would just add latency to a borrowed-time wake.
  private func resumeTokenRead(on p: CBPeripheral) {
    if let svc = p.services?.first(where: { $0.uuid == Self.serviceUUID }) {
      if let ch = svc.characteristics?.first(where: { $0.uuid == Self.tokenCharUUID }) {
        p.readValue(for: ch)
      } else {
        p.discoverCharacteristics(
          [Self.tokenCharUUID, Self.keepaliveCharUUID, Self.controlCharUUID], for: svc)
      }
    } else {
      p.discoverServices([Self.serviceUUID])
    }
  }

  func centralManager(
    _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any], rssi RSSI: NSNumber
  ) {
    let rssi = RSSI.intValue
    guard rssi < 0 else { return }  // 127 = invalid sentinel

    var advertised = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
    advertised +=
      (advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID]) ?? []

    // Foreground fast path: rotating token rides as the non-marker UUID.
    if let tokenUUID = advertised.first(where: { $0 != Self.serviceUUID && $0.data.count == 16 }) {
      let peerToken = tokenUUID.data.map { String(format: "%02x", $0) }.joined()
      // While the app is active the Dart unfiltered scan already ingests this
      // advert — emitting here too would double the sample rate.
      if UIApplication.shared.applicationState != .active {
        emitSighting(tokenHex: peerToken, rssi: rssi)
      }
      // W5 establishment: even though the token is already readable from the
      // air, OPEN a persistent connection now so proximity survives BOTH
      // phones sleeping later (an advert-only sighting dies the instant both
      // lock). Single-initiator tiebreak: the side whose current advertised
      // token sorts lower dials; the peer computes the mirror and stands
      // down — no double connect. Skip if a session/attempt already exists.
      let id = peripheral.identifier
      if w5LinksEnabled, w5[id] == nil, inflight[id] == nil,
         let myToken = currentTokenHex(), myToken < peerToken {
        // H-W5-5: an in-grace lease out-ranks the retry floor — the 120 s
        // reconnect window is the entire point of the lease.
        if w5Link.wantsGraceRecovery(alias: peerToken) {
          lastConnectAttempt.removeValue(forKey: id)
          W5Diag.emit(.graceBypass, role: .outbound, peer: peerToken, reason: "retryFloor")
        }
        let recent = lastConnectAttempt[id].map {
          Date().timeIntervalSince($0) < Self.connectRetryFloor } ?? false
        if !recent, w5Link.willDial(peerTokenHex: peerToken, peripheralID: id) {
          lastConnectAttempt[id] = Date()
          tokenCache[id] = (peerToken, Date())
          inflightRSSI[id] = rssi
          inflight[id] = peripheral
          peripheral.delegate = self
          W5Diag.emit(.dialStart, role: .outbound, peer: peerToken)
          centralMgr?.connect(peripheral, options: nil)
          DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self = self, self.w5[id] == nil,
                  let p = self.inflight[id] else { return }
            self.centralMgr?.cancelPeripheralConnection(p)  // read-only fallback timed out
            self.inflight.removeValue(forKey: id)
            self.inflightRSSI.removeValue(forKey: id)
          }
        }
      }
      scheduleScanRestart()
      return
    }

    // B1: an in-range ANDROID puts the token in manufacturer data, not in a
    // service UUID — so it never matched the branch above and always fell into
    // the connect path below, which cannot succeed against a non-connectable
    // peer with no GATT server. Read the advert instead, and return: these
    // peers must never be connected to, which also stops each one burning a
    // guaranteed-failing connect every 5 minutes.
    if let android = Self.androidAdvertToken(advertisementData) {
      // Same active-app rule as the service-UUID branch: on iOS the Dart scan
      // is UNFILTERED (`beacon_service.dart:914`) and already parses in-range
      // manufacturer data at `:965-971`, so emitting here too would double the
      // sample rate. The self-sight guard, estimator and buffering all stay on
      // the one shared path through emitSighting.
      if UIApplication.shared.applicationState != .active {
        emitSighting(
          tokenHex: android.hex, rssi: rssi, mediumPower: android.mediumPower)
      }
      scheduleScanRestart()
      return
    }

    // No token on the air (locked iOS peer): cached token, else connect + read.
    let id = peripheral.identifier
    if let cached = tokenCache[id], Date().timeIntervalSince(cached.at) < Self.tokenCacheTTL {
      emitSighting(tokenHex: cached.hex, rssi: rssi)
      // H-W5-5: a cached token mapping to an in-grace lease must NOT
      // suppress the reconnect dial (cache TTL 15 min >> grace 120 s).
      if w5LinksEnabled, w5Link.wantsGraceRecovery(alias: cached.hex) {
        lastConnectAttempt.removeValue(forKey: id)
        tokenCache.removeValue(forKey: id)  // fall through to the dial path
        W5Diag.emit(.graceBypass, role: .outbound, peer: cached.hex, reason: "tokenCache")
      } else {
        scheduleScanRestart()
        return
      }
    }
    if inflight[id] != nil { return }
    if let last = lastConnectAttempt[id],
       Date().timeIntervalSince(last) < Self.connectRetryFloor,
       tokenCache[id] == nil {
      return  // recent failed attempt (likely a stranger's iPhone) — back off
    }
    lastConnectAttempt[id] = Date()
    inflight[id] = peripheral
    inflightRSSI[id] = rssi
    peripheral.delegate = self
    // B2: attribute the NO-TOKEN dial (locked peer, connect-to-read) — the
    // advertised-token path already emits dialStart; this one did not, leaving
    // a dial with no structured record.
    W5Diag.emit(.dialStart, role: .outbound,
      peripheral: id.uuidString, reason: "tokenRead")
    central.connect(peripheral, options: nil)
    // Watchdog: never hold a connect slot longer than 10 s.
    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
      guard let self = self, let p = self.inflight[id] else { return }
      self.centralMgr?.cancelPeripheralConnection(p)
      self.inflight.removeValue(forKey: id)
      self.inflightRSSI.removeValue(forKey: id)
    }
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    logWake("w5-connect")
    W5Diag.emit(.connectResult, role: .outbound,
      peer: tokenCache[peripheral.identifier]?.hex,
      peripheral: peripheral.identifier.uuidString, result: "connected")
    peripheral.discoverServices([Self.serviceUUID])
  }

  func centralManager(
    _ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?
  ) {
    inflight.removeValue(forKey: peripheral.identifier)
    inflightRSSI.removeValue(forKey: peripheral.identifier)
    W5Diag.emit(.connectResult, role: .outbound,
      peer: tokenCache[peripheral.identifier]?.hex,
      peripheral: peripheral.identifier.uuidString, result: "failed")
    if w5LinksEnabled { w5Link.dialFailed(peripheral.identifier) }
    scheduleScanRestart()
  }

  func centralManager(
    _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
    error: Error?
  ) {
    inflight.removeValue(forKey: peripheral.identifier)
    inflightRSSI.removeValue(forKey: peripheral.identifier)
    if let s = w5.removeValue(forKey: peripheral.identifier) {
      // Full domain+code + last GATT op + seq: the diagnostic that tells us
      // whether the cascade starved (supervision timeout, code 6/7) or the
      // link physically dropped, and how far the beat sequence got.
      let e = error as NSError?
      let reason = e.map { "\($0.domain):\($0.code)" } ?? "clean"
      logWake("w5-parted-\(reason)-seq\(s.seq)-op:\(s.lastGattOp)")
      // B2: the physical CA5E session disconnect is a real transition — surface
      // it in the structured layer too (was wake-log only), with the beat count
      // reached so a starve vs a clean drop is distinguishable.
      W5Diag.emit(.parted, role: .outbound, peripheral: peripheral.identifier.uuidString,
        result: reason, count: Int(s.seq))
    }
    if w5LinksEnabled { w5Link.linkDown(peripheral.identifier) }
    scheduleScanRestart()
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard let svc = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
      centralMgr?.cancelPeripheralConnection(peripheral)
      return
    }
    peripheral.discoverCharacteristics(
      [Self.tokenCharUUID, Self.keepaliveCharUUID, Self.controlCharUUID], for: svc)
  }

  func peripheral(
    _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
    error: Error?
  ) {
    // Discover BOTH the token AND keepalive characteristics — W5 needs the
    // keepalive handle, which the committed version never requested.
    guard let ch = service.characteristics?.first(where: { $0.uuid == Self.tokenCharUUID })
    else {
      centralMgr?.cancelPeripheralConnection(peripheral)
      return
    }
    peripheral.readValue(for: ch)
  }

  func peripheral(
    _ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    let id = peripheral.identifier
    // W5 notify from the peer: a wake signal (bridges background gaps where
    // our cadence timer was suspended). Re-prime a beat if the cadence has
    // elapsed and no write is in flight — the single gated sender enforces
    // one-write-at-a-time. No synchronous unacked write here.
    if characteristic.uuid == Self.keepaliveCharUUID {
      guard w5[id] != nil else { return }
      w5[id]?.lastEvent = Date()
      w5MaybeReadRSSI(id)
      w5MaybeBeat(id)
      return
    }
    if characteristic.uuid == Self.controlCharUUID {
      guard w5LinksEnabled, let data = characteristic.value else { return }
      w5Link.controlNotify(peripheral, data)
      return
    }
    guard characteristic.uuid == Self.tokenCharUUID,
          let data = characteristic.value, data.count == 16 else {
      centralMgr?.cancelPeripheralConnection(peripheral)
      return
    }
    let hex = data.map { String(format: "%02x", $0) }.joined()
    tokenCache[id] = (hex, Date())
    if tokenCache.count > 64 {
      let cutoff = Date().addingTimeInterval(-Self.tokenCacheTTL)
      tokenCache = tokenCache.filter { $0.value.at > cutoff }
    }
    emitSighting(tokenHex: hex, rssi: inflightRSSI[id] ?? -85)
    // W5 (test-only, INRANGE_W5_LINKS): token read = session start. Subscribe
    // to the peer's keepalive; the first beat waits for
    // didUpdateNotificationStateFor. If W5 is gated off, disconnect after the
    // read (pure token-read behavior).
    guard w5LinksEnabled else {
      centralMgr?.cancelPeripheralConnection(peripheral)
      return
    }
    if w5[id] == nil {
      let ka = peripheral.services?
        .first(where: { $0.uuid == Self.serviceUUID })?.characteristics?
        .first(where: { $0.uuid == Self.keepaliveCharUUID })
      w5[id] = W5Session(
        peripheral: peripheral, tokenHex: hex, lastEvent: Date(),
        keepaliveChar: ka, lastRssiAt: .distantPast, lastBeatAt: .distantPast,
        writeInFlight: false, notifyReady: false, seq: 0, lastGattOp: "start")
      W5Diag.logWakeHandled("w5-start", token: hex)  // atomic derive+append (R5)
      inflight.removeValue(forKey: id)  // session owns the peripheral now
      if let ka = ka {
        // Subscribe first; the first beat fires from didUpdateNotificationState.
        peripheral.setNotifyValue(true, for: ka)
      }
      // Ownership (#7): register this link; peers without CA6E stay legacy.
      let cc = peripheral.services?
        .first(where: { $0.uuid == Self.serviceUUID })?.characteristics?
        .first(where: { $0.uuid == Self.controlCharUUID })
      w5Link.adoptTokenReadLink(peripheral, peerToken: hex, controlChar: cc)
      peripheral.readRSSI()
    } else {
      w5[id]?.tokenHex = hex  // rotation refresh on the open connection
    }
  }

  /// didUpdateNotificationStateFor: the subscription is confirmed — only now
  /// is it safe to send the first beat.
  func peripheral(
    _ peripheral: CBPeripheral,
    didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?
  ) {
    let id = peripheral.identifier
    if characteristic.uuid == Self.controlCharUUID {
      // CA6E subscription confirmed → the HELLO can go out (its HELLO_ACK
      // rides this notify channel).
      if w5LinksEnabled, error == nil, characteristic.isNotifying {
        w5Link.controlSubscribeConfirmed(peripheral)
      }
      return
    }
    guard characteristic.uuid == Self.keepaliveCharUUID, w5[id] != nil else { return }
    if let error = error {
      logWake("w5-notify-err-\((error as NSError).code)")
      return
    }
    w5[id]?.notifyReady = characteristic.isNotifying
    logWake("w5-notify-ready")
    w5MaybeBeat(id)
  }

  /// didWriteValueFor: the .withResponse write was acked. Clear the in-flight
  /// flag, sample RSSI (throttled, driven by this confirmed callback), and
  /// prime the next beat ~4 s out (callback-primed cadence).
  func peripheral(
    _ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    let id = peripheral.identifier
    guard characteristic.uuid == Self.keepaliveCharUUID, w5[id] != nil else { return }
    w5[id]?.writeInFlight = false
    if let error = error {
      w5[id]?.lastGattOp = "write-fail-\((error as NSError).code)"
      logWake("w5-write-err-\((error as NSError).code)")
      // Failed write: retry on the next wake/cadence rather than spinning.
      return
    }
    w5[id]?.lastGattOp = "write-ok"
    w5[id]?.lastEvent = Date()
    w5MaybeReadRSSI(id)
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.w5Cadence) { [weak self] in
      self?.w5MaybeBeat(id)
    }
  }

  /// The single gated beat sender: at most one .withResponse write outstanding,
  /// paced to the cadence. Callable from the notify wake, the cadence timer,
  /// and the notify-ready callback — all funnel through here.
  private func w5MaybeBeat(_ id: UUID) {
    guard w5LinksEnabled, var s = w5[id], s.peripheral.state == .connected,
          s.notifyReady, !s.writeInFlight, let ka = s.keepaliveChar else { return }
    guard Date().timeIntervalSince(s.lastBeatAt) >= Self.w5Cadence - 0.5 else { return }
    s.writeInFlight = true
    s.lastBeatAt = Date()
    s.seq += 1
    s.lastGattOp = "write-seq-\(s.seq)"
    w5[id] = s
    logWake("w5-beat-\(s.seq)")
    s.peripheral.writeValue(Data([0x01]), for: ka, type: .withResponse)
  }

  private func w5MaybeReadRSSI(_ id: UUID) {
    guard var s = w5[id], s.peripheral.state == .connected,
          Date().timeIntervalSince(s.lastRssiAt) >= 1.0 else { return }
    s.lastRssiAt = Date()
    w5[id] = s
    s.peripheral.readRSSI()
  }

  func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
    let id = peripheral.identifier
    guard error == nil, RSSI.intValue < 0, let s = w5[id] else { return }
    // Live-connection RSSI: the cleanest proximity stream iOS can give.
    // W5 samples go through the controller: live push when Dart is awake,
    // file-backed log otherwise (the 500-entry UserDefaults buffer truncated
    // the 07-29 overnight soak to its last ~35 min — soak results doc).
    w5Link.recordRssi(tokenHex: s.tokenHex, rssi: RSSI.intValue)
    w5[id]?.lastEvent = Date()
  }

  /// Session teardown — owner rule: drop on part (disconnect), drop on
  /// resolve (Dart's dropPeer), never linger past the encounter.
  func w5End(_ id: UUID) {
    let _endTok = w5[id]?.tokenHex
    if let s = w5.removeValue(forKey: id) {
      W5Diag.logWakeHandled("w5-end", token: _endTok)  // atomic derive+append (R5)
      centralMgr?.cancelPeripheralConnection(s.peripheral)
    }
  }

  /// Controller accessors: the session's peripheral (or an in-flight one),
  /// and a token refresh on ALIAS_ROLL so RSSI keeps flowing under the new
  /// alias after a peer rotation.
  func w5Peripheral(_ id: UUID) -> CBPeripheral? {
    w5[id]?.peripheral ?? inflight[id]
  }

  func w5UpdateSessionToken(_ id: UUID, _ hex: String) {
    if w5[id] != nil { w5[id]?.tokenHex = hex }
  }

  @discardableResult
  func dropPeerByToken(_ tokenHex: String) -> [String: Any] {
    // H-W5-6: erase the ownership lease AND disconnect inbound keepers, not
    // just the outbound session. Returns a STRUCTURED diagnostic (no raw ids):
    // ownership lookup hit/miss, roles closed, lease ended, and how many raw
    // CA5E/token sessions were reaped.
    var result: [String: Any] = [
      "lookupHit": false, "rolesClosed": [String](), "leaseEnded": false,
      "rawSessionsReaped": 0,
    ]
    if w5LinksEnabled {
      result = w5Link.dropPeer(alias: tokenHex).asDict
    }
    var reaped = 0
    for (id, session) in w5 where session.tokenHex == tokenHex {
      w5End(id)
      reaped += 1
    }
    result["rawSessionsReaped"] = reaped
    return result
  }

  #if DEBUG
    /// TEST-ONLY (compiled out of Release/diag app builds): flip the persisted
    /// W5-links gate so a test can drive dropPeerByToken through the real
    /// w5Link.dropPeer path (w5LinksEnabled reads this under INRANGE_DIAG).
    func testEnableW5Links() { defaults.set(true, forKey: Self.keyW5Links) }
    /// TEST-ONLY: drive the private foreign-flavor reconciliation directly (C5).
    func testReconcileStateStamp() { reconcileStateStamp() }
    static var testStateSchemaStamp: String { stateSchemaStamp }
    static var testSchemaKey: String { keySchema }
  #endif
}
