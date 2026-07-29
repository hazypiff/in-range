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
/// in background). Token comes from the advert when present; otherwise
/// connect → read CA7E → disconnect, with a per-peripheral token cache.
///
/// Survives relaunch: managers use CoreBluetooth state restoration, and the
/// batch + enabled flag persist in UserDefaults so a BT-relaunched process
/// can serve reads and buffer sightings before the Flutter engine attaches.
final class BackgroundBeacon: NSObject {
  static let shared = BackgroundBeacon()

  // 0000CAFE-…: app-wide discovery marker (beacon_service.dart).
  private static let serviceUUID = CBUUID(string: "CAFE")
  private static let tokenCharUUID = CBUUID(string: "CA7E")
  // W5 keepalive channel (contract proposed issue #3): central writes a
  // 1-byte heartbeat every ~8 s, peripheral notifies back — the Herald
  // ping-pong. Each incoming BLE event grants ~10 s of background
  // execution, inside which the next outgoing beat is sent: neither side
  // ever suspends while the session lives.
  private static let keepaliveCharUUID = CBUUID(string: "CA5E")
  private static let keepaliveInterval: TimeInterval = 8
  private static let rssiInterval: TimeInterval = 10
  private static let peripheralRestoreID = "io.inrange.beacon.peripheral"
  private static let centralRestoreID = "io.inrange.beacon.central"

  private static let keyEnabled = "bb.enabled"
  private static let keySlots = "bb.slots"
  private static let keyBuffer = "bb.buffer"
  private static let keyPingURL = "bb.pingUrl"
  private static let keyPingAuth = "bb.pingAuth"
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

  // W5 live sessions: peripheral.identifier → session state. Session-scoped
  // by OWNER RULE (2026-07-24): hold while the encounter is live, drop on
  // part/reject — never a permanent ledger (matches token-rotation privacy).
  private struct W5Session {
    let peripheral: CBPeripheral
    var tokenHex: String
    var lastEvent: Date
    var keepaliveChar: CBCharacteristic?
  }
  private var w5: [UUID: W5Session] = [:]
  private var keepaliveNotifyChar: CBMutableCharacteristic?

  // peripheral.identifier → (tokenHex, cachedAt)
  private var tokenCache: [UUID: (hex: String, at: Date)] = [:]
  // peripherals we're currently connected/connecting to, kept strongly.
  private var inflight: [UUID: CBPeripheral] = [:]
  private var inflightRSSI: [UUID: Int] = [:]
  private var lastConnectAttempt: [UUID: Date] = [:]
  private var lastScanRestart = Date.distantPast
  private var scanHeartbeat: Timer?

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
      case "dropPeer":
        // Owner rule: a resolved pair (pass/reject) drops its W5 session
        // immediately — no tracking anyone the user said no to.
        if let hex = call.arguments as? String { self.dropPeerByToken(hex) }
        result(nil)
      case "setWakePing":
        // Crack #1 client half (issue #4): {url, auth} for the coarse
        // co-presence ping fired on every background wake. Flag-gated:
        // no url stored → no pings. Server half is hazypiff's.
        if let args = call.arguments as? [String: Any] {
          self.defaults.set(args["url"] as? String, forKey: Self.keyPingURL)
          self.defaults.set(args["auth"] as? String, forKey: Self.keyPingAuth)
        }
        result(nil)
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
      let keepalive = CBMutableCharacteristic(
        type: Self.keepaliveCharUUID,
        properties: [.notify, .writeWithoutResponse], value: nil,
        permissions: [.writeable])
      keepaliveNotifyChar = keepalive
      let service = CBMutableService(type: Self.serviceUUID, primary: true)
      service.characteristics = [char, keepalive]
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

  // MARK: - Sighting delivery

  private func emitSighting(tokenHex: String, rssi: Int) {
    let ts = Int(Date().timeIntervalSince1970 * 1000)
    // NEVER hand a background sighting to the Flutter engine: a suspended
    // engine's channel accepts the call and silently drops it (dark-bench
    // 2026-07-23 — native discoveries happened, Dart never saw them).
    // Background → persist natively; Dart pulls and acks when it is ready.
    if UIApplication.shared.applicationState == .active, let ch = channel {
      ch.invokeMethod(
        "onSighting", arguments: ["token": tokenHex, "rssi": rssi, "ts": ts])
    } else {
      var buf = (defaults.array(forKey: Self.keyBuffer) as? [[String: Any]]) ?? []
      buf.append(["token": tokenHex, "rssi": rssi, "ts": ts])
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

  private func notifyAdvertisingState(_ ok: Bool) {
    channel?.invokeMethod("onAdvertisingState", arguments: ok)
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
    notifyAdvertisingState(error == nil)
  }

  // W5 ping-pong, peripheral half: an incoming heartbeat write is our wake —
  // answer with a notify beat ~8 s later, inside the granted window. The
  // central's next write re-arms us; the loop sustains both sides asleep.
  func peripheralManager(
    _ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]
  ) {
    for request in requests where request.characteristic.uuid == Self.keepaliveCharUUID {
      logWake("w5-beat-in")
      DispatchQueue.main.asyncAfter(deadline: .now() + Self.keepaliveInterval) {
        [weak self] in
        guard let self = self, self.enabled, let ch = self.keepaliveNotifyChar else { return }
        self.peripheralMgr?.updateValue(
          Data([0x01]), for: ch, onSubscribedCentrals: nil)
      }
      // A live session proves a peer is right here — keep our own scan warm.
      scheduleScanRestart()
    }
  }

  func peripheralManager(
    _ peripheral: CBPeripheralManager, central: CBCentral,
    didSubscribeTo characteristic: CBCharacteristic
  ) {
    guard characteristic.uuid == Self.keepaliveCharUUID,
          let ch = keepaliveNotifyChar else { return }
    logWake("w5-subscribed")
    // First beat immediately; the central's writes drive the loop after.
    peripheralMgr?.updateValue(Data([0x01]), for: ch, onSubscribedCentrals: [central])
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
    if central.state == .poweredOn { ensureScanning() }
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

    // No token on the air (locked iOS peer, or W1 Android where mfg data is
    // out of reach of the filtered path): cached token, else connect + read.
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
    if w5.removeValue(forKey: peripheral.identifier) != nil {
      logWake("w5-parted")  // peer walked away — session over, back to scanning
    }
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
    let id = peripheral.identifier
    // W5 notify beat from the peer: answer with the next heartbeat write and
    // keep the RSSI loop alive.
    if characteristic.uuid == Self.keepaliveCharUUID {
      guard var s = w5[id] else { return }
      s.lastEvent = Date()
      w5[id] = s
      DispatchQueue.main.asyncAfter(deadline: .now() + Self.keepaliveInterval) {
        [weak self] in
        self?.w5Beat(id)
      }
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
    // W5: token read = session start. Hold the connection (session-scoped),
    // subscribe to the peer's keepalive, begin the RSSI loop. Continuous
    // proximity with both phones asleep — the Herald shape.
    if w5[id] == nil {
      w5[id] = W5Session(peripheral: peripheral, tokenHex: hex, lastEvent: Date(),
                         keepaliveChar: nil)
      logWake("w5-start")
      if let svc = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }),
         let ka = svc.characteristics?.first(where: { $0.uuid == Self.keepaliveCharUUID }) {
        w5[id]?.keepaliveChar = ka
        peripheral.setNotifyValue(true, for: ka)
      }
      inflight.removeValue(forKey: id)  // session owns the peripheral now
      w5Beat(id)
      w5ReadRSSI(id)
    } else {
      w5[id]?.tokenHex = hex  // rotation refresh on the open connection
    }
  }

  /// One heartbeat write; the peer's notify answer schedules the next.
  private func w5Beat(_ id: UUID) {
    guard enabled, let s = w5[id], s.peripheral.state == .connected,
          let ka = s.keepaliveChar else { return }
    s.peripheral.writeValue(Data([0x01]), for: ka, type: .withoutResponse)
  }

  private func w5ReadRSSI(_ id: UUID) {
    guard enabled, let s = w5[id], s.peripheral.state == .connected else { return }
    s.peripheral.readRSSI()
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.rssiInterval) { [weak self] in
      self?.w5ReadRSSI(id)
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
    let id = peripheral.identifier
    guard error == nil, RSSI.intValue < 0, let s = w5[id] else { return }
    // Live-connection RSSI: the cleanest proximity stream iOS can give.
    emitSighting(tokenHex: s.tokenHex, rssi: RSSI.intValue)
    w5[id]?.lastEvent = Date()
  }

  /// Session teardown — owner rule: drop on part (disconnect), drop on
  /// resolve (Dart's dropPeer), never linger past the encounter.
  private func w5End(_ id: UUID) {
    if let s = w5.removeValue(forKey: id) {
      logWake("w5-end")
      centralMgr?.cancelPeripheralConnection(s.peripheral)
    }
  }

  func dropPeerByToken(_ tokenHex: String) {
    for (id, s) in w5 where s.tokenHex == tokenHex { w5End(id) }
  }
}
