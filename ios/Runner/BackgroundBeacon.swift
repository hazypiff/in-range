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
    if defaults.bool(forKey: Self.keyEnabled) {
      ensureManagers()
    }
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
        self.flushBuffered()
        result(self.peripheralMgr?.state == .poweredOn)
      case "updateBatch":
        self.storeSlots(call.arguments)
        self.reconfigureAdvertising()
        result(nil)
      case "stop":
        self.defaults.set(false, forKey: Self.keyEnabled)
        self.stopEverything()
        result(nil)
      case "flushBufferedSightings":
        self.flushBuffered()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    flushBuffered()
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

  /// The token for the slot covering NOW; falls back to the newest slot that
  /// has started (serving a slightly-stale token beats serving nothing).
  private func currentTokenHex() -> String? {
    guard let list = defaults.array(forKey: Self.keySlots) as? [[String: Any]] else {
      return nil
    }
    let nowMs = Date().timeIntervalSince1970 * 1000
    var covering: (hex: String, from: Double)?
    var started: (hex: String, from: Double)?
    for s in list {
      guard let hex = s["t"] as? String,
            let f = (s["f"] as? NSNumber)?.doubleValue,
            let u = (s["u"] as? NSNumber)?.doubleValue else { continue }
      if f <= nowMs && nowMs < u && (covering == nil || f > covering!.from) {
        covering = (hex, f)
      }
      if f <= nowMs && (started == nil || f > started!.from) {
        started = (hex, f)
      }
    }
    return covering?.hex ?? started?.hex
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

  // MARK: - Sighting delivery

  private func emitSighting(tokenHex: String, rssi: Int) {
    let ts = Int(Date().timeIntervalSince1970 * 1000)
    if let ch = channel {
      ch.invokeMethod(
        "onSighting", arguments: ["token": tokenHex, "rssi": rssi, "ts": ts])
    } else {
      var buf = (defaults.array(forKey: Self.keyBuffer) as? [[String: Any]]) ?? []
      buf.append(["token": tokenHex, "rssi": rssi, "ts": ts])
      if buf.count > Self.bufferCap { buf.removeFirst(buf.count - Self.bufferCap) }
      defaults.set(buf, forKey: Self.keyBuffer)
    }
  }

  private func flushBuffered() {
    guard let ch = channel,
          let buf = defaults.array(forKey: Self.keyBuffer) as? [[String: Any]],
          !buf.isEmpty else { return }
    defaults.removeObject(forKey: Self.keyBuffer)
    for s in buf { ch.invokeMethod("onSighting", arguments: s) }
  }

  private func notifyAdvertisingState(_ ok: Bool) {
    channel?.invokeMethod("onAdvertisingState", arguments: ok)
  }
}

// MARK: - CBPeripheralManagerDelegate

extension BackgroundBeacon: CBPeripheralManagerDelegate {
  func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    if peripheral.state == .poweredOn {
      serviceAdded = false  // services don't survive a power cycle
      reconfigureAdvertising()
    } else {
      notifyAdvertisingState(false)
    }
  }

  func peripheralManager(
    _ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any]
  ) {
    // Restored services re-attach automatically; didUpdateState re-advertises.
  }

  func peripheralManagerDidStartAdvertising(
    _ peripheral: CBPeripheralManager, error: Error?
  ) {
    notifyAdvertisingState(error == nil)
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
    // A peer reading our token = a peer in range + a moment of background
    // execution time. Spend it re-arming our own scan so discovery flows
    // both ways even when we're locked.
    scheduleScanRestart()
  }
}

// MARK: - CBCentralManagerDelegate

extension BackgroundBeacon: CBCentralManagerDelegate, CBPeripheralDelegate {
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    if central.state == .poweredOn { ensureScanning() }
  }

  func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
    // didUpdateState follows and restarts the filtered scan.
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
