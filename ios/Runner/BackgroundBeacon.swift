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
  /// in-range's BLE company identifier, mirrored from
  /// `beacon_service.dart:608` (`_inRangeManufacturerId`). Android's advert
  /// carries the 16-byte correlation token under this id
  /// (`beacon_service.dart:713-714`); CoreBluetooth hands the field back with
  /// the company id still on the front, little-endian. Finding B1.
  private static let inRangeCompanyID: UInt16 = 0xFFFF
  private static let peripheralRestoreID = "io.inrange.beacon.peripheral"
  private static let centralRestoreID = "io.inrange.beacon.central"

  private static let keyEnabled = "bb.enabled"
  private static let keySlots = "bb.slots"
  private static let keyBuffer = "bb.buffer"
  private static let bufferCap = 500
  private static let tokenCacheTTL: TimeInterval = 15 * 60
  private static let connectRetryFloor: TimeInterval = 5 * 60
  private static let scanRestartFloor: TimeInterval = 4

  private var peripheralMgr: CBPeripheralManager?
  private var centralMgr: CBCentralManager?
  private var channel: FlutterMethodChannel?
  private var serviceAdded = false
  /// Set by peripheralManager(_:willRestoreState:) — which fires BEFORE
  /// peripheralManagerDidUpdateState on a restoration relaunch — so the state
  /// callback does not clobber the restored service registration (audit
  /// 2026-07-25, critical #3).
  private var didRestorePeripheral = false

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

  private var defaults: UserDefaults { UserDefaults.standard }

  // MARK: - Lifecycle

  /// Called from AppDelegate on EVERY launch. When iOS relaunched us for a
  /// bluetooth event (or the user had the beacon on before a jetsam), the
  /// persisted enabled flag brings both managers straight back up — no
  /// Flutter engine required to serve GATT reads or buffer sightings.
  func bootFromPersistence() {
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
        result(self.defaults.array(forKey: Self.keyBuffer) as? [[String: Any]] ?? [])
      case "ackBufferedSightings":
        let count = (call.arguments as? Int) ?? 0
        self.ackBuffer(count)
        result(nil)
      case "bleState":
        // Pull path for finding 1.3: an onBleState push issued while the app
        // was backgrounded is accepted and silently dropped by a suspended
        // engine, so Dart re-reads the authoritative state on foregrounding —
        // same reasoning as the sighting buffer's pull-and-ack.
        result(self.bleStateSnapshot())
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

  private func stopEverything() {
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
  private func currentTokenHex() -> String? {
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

  private static func hexToData(_ hex: String) -> Data? {
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
      let service = CBMutableService(type: Self.serviceUUID, primary: true)
      service.characteristics = [char]
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

  /// Soak-test observability (2026-07-24: overnight soak produced zero
  /// samples and zero evidence of WHY): append wake/read events to a file
  /// in Documents so a USB pull can show whether iOS granted windows at
  /// all, separately from whether scans saw anything during them.
  private func logWake(_ kind: String) {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let url = docs.appendingPathComponent("bb_wake_log.txt")
    let line = "\(Int(Date().timeIntervalSince1970 * 1000)) \(kind)\n"
    if let data = line.data(using: .utf8) {
      if let h = try? FileHandle(forWritingTo: url) {
        h.seekToEndOfFile()
        h.write(data)
        try? h.close()
      } else {
        try? data.write(to: url)
      }
    }
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
    if let services = dict[CBPeripheralManagerRestoredStateServicesKey] as? [CBMutableService] {
      for svc in services where svc.uuid == Self.serviceUUID {
        if (svc.characteristics ?? []).contains(where: { $0.uuid == Self.tokenCharUUID }) {
          serviceAdded = true
        }
      }
    }
  }

  func peripheralManagerDidStartAdvertising(
    _ peripheral: CBPeripheralManager, error: Error?
  ) {
    // The error text is the only thing that separates "advert rejected" from
    // "radio off" on the Dart side — carry it (finding 1.3).
    notifyAdvertisingState(error == nil, error: error)
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
    if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
      for p in peripherals {
        p.delegate = self
        switch p.state {
        case .connected:
          inflight[p.identifier] = p
          resumeTokenRead(on: p)
        case .connecting:
          inflight[p.identifier] = p
        default:
          break
        }
      }
    }
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
        p.discoverCharacteristics([Self.tokenCharUUID], for: svc)
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
      // While the app is active the Dart unfiltered scan already ingests this
      // advert — emitting here too would double the sample rate.
      if UIApplication.shared.applicationState != .active {
        emitSighting(tokenHex: tokenUUID.data.map { String(format: "%02x", $0) }.joined(),
                     rssi: rssi)
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
      scheduleScanRestart()
      return
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
    peripheral.discoverServices([Self.serviceUUID])
  }

  func centralManager(
    _ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?
  ) {
    inflight.removeValue(forKey: peripheral.identifier)
    inflightRSSI.removeValue(forKey: peripheral.identifier)
    scheduleScanRestart()
  }

  func centralManager(
    _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
    error: Error?
  ) {
    inflight.removeValue(forKey: peripheral.identifier)
    inflightRSSI.removeValue(forKey: peripheral.identifier)
    scheduleScanRestart()
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard let svc = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
      centralMgr?.cancelPeripheralConnection(peripheral)
      return
    }
    peripheral.discoverCharacteristics([Self.tokenCharUUID], for: svc)
  }

  func peripheral(
    _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
    error: Error?
  ) {
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
    defer { centralMgr?.cancelPeripheralConnection(peripheral) }
    guard characteristic.uuid == Self.tokenCharUUID,
          let data = characteristic.value, data.count == 16 else { return }
    let hex = data.map { String(format: "%02x", $0) }.joined()
    let id = peripheral.identifier
    tokenCache[id] = (hex, Date())
    if tokenCache.count > 64 {
      let cutoff = Date().addingTimeInterval(-Self.tokenCacheTTL)
      tokenCache = tokenCache.filter { $0.value.at > cutoff }
    }
    // RSSI for ranging comes from the SCAN RESULT, never the connection.
    emitSighting(tokenHex: hex, rssi: inflightRSSI[id] ?? -85)
  }
}
