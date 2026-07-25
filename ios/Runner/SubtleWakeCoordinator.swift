import Flutter
import CoreLocation
import UIKit

/// Tiers 2–4 of docs/SUBTLE_TRACKING_ARCHITECTURE.md — the low-power wake net.
///
/// Owns one CLLocationManager for significant-location-change (SLC) monitoring
/// and CLCircularRegion monitoring of venue anchors. Neither is a distance
/// classifier: every event is forwarded to Dart as a wake hint over the method
/// channel `io.inrange.app/subtle_wake`, and Dart decides whether to spend a
/// BLE burst. Silent pushes (tier 4) arrive via AppDelegate and take the same
/// path — they carry no user data, only a wake hint and a nonce.
///
/// SLC and region wakes require Location Always authorization, and this class
/// NEVER requests it: Dart's PermissionService owns the disclosure-gated
/// request flow. start() returns false until Always has been granted.
final class SubtleWakeCoordinator: NSObject {
  static let shared = SubtleWakeCoordinator()

  private static let channelName = "io.inrange.app/subtle_wake"
  private static let bufferKey = "io.inrange.subtlewake.buffer"
  private static let bufferCap = 50
  /// Hard iOS cap on simultaneously monitored regions per app.
  private static let maxRegions = 20
  /// Persisted session state so an SLC/region RELAUNCH can rebuild monitoring
  /// during didFinishLaunching — Apple delivers the relaunching event only to
  /// a manager recreated at launch (audit 2026-07-25, critical #5).
  private static let keyWantsToRun = "io.inrange.subtlewake.wants"
  private static let keyRegions = "io.inrange.subtlewake.regions"

  private var channel: FlutterMethodChannel?
  private var locationManager: CLLocationManager?
  private var isRunning = false
  /// True after Dart calls start(), even if it returned false because Location
  /// Always was not yet granted. Lets applyAuthorizationStatus re-arm when the
  /// user upgrades to Always mid-session. Persisted: a relaunched process
  /// must know whether to rebuild monitoring before Dart ever attaches.
  private var wantsToRun = false {
    didSet { UserDefaults.standard.set(wantsToRun, forKey: Self.keyWantsToRun) }
  }
  /// Latest anchor set from Dart (id/lat/lon/radius/onEnter/onExit dicts),
  /// kept so start() and authorization upgrades can re-arm regions without a
  /// Dart round-trip. Regions are built lazily in applyRegions so the radius
  /// can be clamped against maximumRegionMonitoringDistance. Persisted for
  /// the same relaunch path as wantsToRun.
  private var desiredRegions: [[String: Any]] = [] {
    didSet { UserDefaults.standard.set(desiredRegions, forKey: Self.keyRegions) }
  }
  /// Retained when start() finds Location Always missing (audit 2026-07-25,
  /// critical #4): with no live manager + delegate, the authorization-change
  /// callback can NEVER fire and the wantsToRun re-arm is dead code. This
  /// manager observes only — it never requests authorization.
  private var pendingAuthManager: CLLocationManager?

  private override init() {
    super.init()
  }

  func register(with registrar: FlutterPluginRegistrar) {
    let ch = FlutterMethodChannel(
      name: Self.channelName, binaryMessenger: registrar.messenger())
    channel = ch
    ch.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return result(nil) }
      switch call.method {
      case "start":
        self.start(result: result)
      case "stop":
        self.stop(result: result)
      case "updateRegions":
        self.updateRegions(call.arguments as? [String: Any] ?? [:], result: result)
      case "drainBufferedWakes":
        // Pull-and-ack: return the buffer WITHOUT clearing it; Dart acks via
        // ackBufferedWakes after handling each wake.
        result(UserDefaults.standard.array(forKey: Self.bufferKey) as? [[String: Any]] ?? [])
      case "ackBufferedWakes":
        self.ackBuffer((call.arguments as? Int) ?? 0)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(appDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification,
      object: nil)
    // Buffered wakes (fired before the engine attached) are NOT pushed here:
    // delivery is pull-and-ack — Dart drains when its handler is ready and
    // acks after handling (audit 2026-07-25, critical #6).
    notifyBufferReady()
  }

  // MARK: - Relaunch boot

  /// Called from AppDelegate on EVERY launch, before the Flutter engine
  /// matters. An SLC/region relaunch delivers its event only to a
  /// CLLocationManager created during didFinishLaunching with monitoring
  /// re-started — so when the persisted session says we were running, rebuild
  /// exactly that. The wake event lands on the delegate below and is
  /// buffered until Dart drains it.
  func bootFromPersistence() {
    let defaults = UserDefaults.standard
    let persistedRegions =
      defaults.array(forKey: Self.keyRegions) as? [[String: Any]] ?? []
    if desiredRegions.isEmpty { desiredRegions = persistedRegions }
    guard defaults.bool(forKey: Self.keyWantsToRun), !isRunning else { return }

    let auth: CLAuthorizationStatus
    if #available(iOS 14.0, *) {
      auth = CLLocationManager().authorizationStatus
    } else {
      auth = CLLocationManager.authorizationStatus()
    }
    guard auth == .authorizedAlways else { return }

    let manager = CLLocationManager()
    manager.delegate = self
    locationManager = manager
    wantsToRun = true
    isRunning = true
    manager.startMonitoringSignificantLocationChanges()
    manager.startMonitoringVisits()
    applyRegions(to: manager)
  }

  // MARK: - Lifecycle

  private func start(result: @escaping FlutterResult) {
    wantsToRun = true
    guard !isRunning else {
      result(true)
      return
    }

    let manager = CLLocationManager()
    manager.delegate = self

    let auth: CLAuthorizationStatus
    if #available(iOS 14.0, *) {
      auth = manager.authorizationStatus
    } else {
      auth = CLLocationManager.authorizationStatus()
    }

    switch auth {
    case .authorizedAlways:
      // SLC and region events are delivered in the background without
      // allowsBackgroundLocationUpdates — that flag is for the continuous
      // session owned by BackgroundLocationCoordinator.
      pendingAuthManager = nil  // observed upgrade landed (or was never needed)
      locationManager = manager
      isRunning = true
      manager.startMonitoringSignificantLocationChanges()
      manager.startMonitoringVisits()
      applyRegions(to: manager)
      result(true)
    case .notDetermined, .authorizedWhenInUse, .denied, .restricted:
      // Do NOT request authorization natively. Without Always there are no
      // background wakes, so report unavailable and let Dart's permission
      // flow (or a fallback) handle it. wantsToRun stays true so an auth
      // upgrade re-arms without another Dart call — and that REQUIRES this
      // manager to stay alive with its delegate attached: authorization
      // callbacks only fire on live managers (audit 2026-07-25, critical #4).
      // This manager observes only; it never requests.
      pendingAuthManager = manager
      result(false)
    @unknown default:
      pendingAuthManager = manager
      result(false)
    }
  }

  private func stop(result: FlutterResult?) {
    wantsToRun = false
    pendingAuthManager = nil
    if let manager = locationManager {
      manager.stopMonitoringSignificantLocationChanges()
      manager.stopMonitoringVisits()
      for region in manager.monitoredRegions {
        manager.stopMonitoring(for: region)
      }
      manager.delegate = nil
    }
    locationManager = nil
    isRunning = false
    result?(true)
  }

  /// Replaces the venue-anchor set. Stored even when not running so a later
  /// start() arms it; entries past the 20-region iOS cap are dropped.
  private func updateRegions(_ args: [String: Any], result: FlutterResult) {
    let raw = args["regions"] as? [[String: Any]] ?? []
    desiredRegions = Array(raw.prefix(Self.maxRegions))
    if let manager = locationManager, isRunning {
      applyRegions(to: manager)
    }
    result(true)
  }

  private func applyRegions(to manager: CLLocationManager) {
    let wantedIds = Set(desiredRegions.compactMap { $0["id"] as? String })
    for region in manager.monitoredRegions where !wantedIds.contains(region.identifier) {
      manager.stopMonitoring(for: region)
    }
    let monitoredById = Dictionary(
      uniqueKeysWithValues: manager.monitoredRegions.compactMap {
        $0 as? CLCircularRegion
      }.map { ($0.identifier, $0) })
    for entry in desiredRegions {
      guard let id = entry["id"] as? String, !id.isEmpty,
            let lat = (entry["lat"] as? NSNumber)?.doubleValue,
            let lon = (entry["lon"] as? NSNumber)?.doubleValue,
            let radius = (entry["radius"] as? NSNumber)?.doubleValue
      else { continue }
      let center = CLLocationCoordinate2D(latitude: lat, longitude: lon)
      guard CLLocationCoordinate2DIsValid(center), radius > 0 else { continue }
      let clampedRadius = min(radius, manager.maximumRegionMonitoringDistance)

      // M1: an existing region with the same id but different geometry must be
      // replaced, not skipped — otherwise the stale fence keeps firing.
      if let existing = monitoredById[id] {
        let sameCenter = abs(existing.center.latitude - lat) < 0.0001 &&
                         abs(existing.center.longitude - lon) < 0.0001
        let sameRadius = abs(existing.radius - clampedRadius) < 1
        if sameCenter && sameRadius { continue }
        manager.stopMonitoring(for: existing)
      }

      let region = CLCircularRegion(
        center: center,
        radius: clampedRadius,
        identifier: id)
      region.notifyOnEntry = (entry["onEnter"] as? Bool) ?? true
      region.notifyOnExit = (entry["onExit"] as? Bool) ?? true
      // An anchor added while already inside the venue fires no entry event;
      // the next SLC fix or exit covers it, so requestState is skipped.
      manager.startMonitoring(for: region)
    }
  }

  // MARK: - Silent push (tier 4)

  /// Called from AppDelegate for every remote notification. Only plist-safe
  /// custom keys are forwarded; the `aps` dictionary never reaches Dart.
  ///
  /// The completion handler is HELD (~20 s) instead of answered immediately:
  /// the handler's return ends the background execution window, so completing
  /// at once strangled the very BLE burst the push was sent to buy (audit
  /// 2026-07-25, critical #5). The native carrier is also nudged directly —
  /// the async Dart burst is the second half of the wake, not a prerequisite.
  func handleRemoteNotification(
    _ userInfo: [AnyHashable: Any],
    completion: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    // Only silent pushes (content-available) are wake hints. Anything else
    // (none today) is not ours to spend a window on.
    let aps = userInfo["aps"] as? [String: Any]
    guard (aps?["content-available"] as? Int) == 1 else {
      completion(.noData)
      return
    }
    BackgroundBeacon.shared.nudge(reason: "push")
    var event: [String: Any] = [
      "kind": "silentPush",
      "ts": Int(Date().timeIntervalSince1970 * 1000),
    ]
    for (key, value) in userInfo {
      guard let key = key as? String, key != "aps" else { continue }
      switch value {
      case let v as String:
        event[key] = v
      case let v as NSNumber:
        event[key] = v
      default:
        continue
      }
    }
    emitWake(event)
    DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
      completion(.newData)
    }
  }

  // MARK: - Wake delivery

  private func emitWake(_ event: [String: Any]) {
    guard let ch = channel else {
      appendBuffer(event)
      return
    }
    if UIApplication.shared.applicationState == .active {
      ch.invokeMethod("onWake", arguments: event)
    } else {
      // A suspended engine silently drops channel calls (bench note in
      // BackgroundBeacon.emitSighting), so persist first; Dart pulls and acks
      // when ready. The live call still reaches an engine that iOS resumed
      // for this wake; wake hints are idempotent, so the duplicate that the
      // drain may deliver later is harmless.
      appendBuffer(event)
      ch.invokeMethod("onWake", arguments: event)
    }
  }

  private func appendBuffer(_ event: [String: Any]) {
    var buffer =
      UserDefaults.standard.array(forKey: Self.bufferKey) as? [[String: Any]] ?? []
    buffer.append(event)
    if buffer.count > Self.bufferCap {
      buffer.removeFirst(buffer.count - Self.bufferCap)
    }
    UserDefaults.standard.set(buffer, forKey: Self.bufferKey)
  }

  @objc private func appDidBecomeActive() {
    notifyBufferReady()
  }

  /// Tells Dart a non-empty buffer is waiting; Dart then pulls
  /// (drainBufferedWakes) and confirms (ackBufferedWakes). The buffer is
  /// never cleared here — an unconfirmed push-flush is exactly how wakes
  /// were lost on cold launches.
  private func notifyBufferReady() {
    guard let ch = channel,
          UIApplication.shared.applicationState == .active,
          let buffer =
            UserDefaults.standard.array(forKey: Self.bufferKey) as? [[String: Any]],
          !buffer.isEmpty else { return }
    ch.invokeMethod("onWakeBuffered", arguments: nil)
  }

  /// Drops the first [count] buffered wakes — only after Dart confirms it
  /// handled that many drained entries.
  private func ackBuffer(_ count: Int) {
    guard count > 0,
          var buffer =
            UserDefaults.standard.array(forKey: Self.bufferKey) as? [[String: Any]],
          !buffer.isEmpty else { return }
    buffer.removeFirst(min(count, buffer.count))
    if buffer.isEmpty {
      UserDefaults.standard.removeObject(forKey: Self.bufferKey)
    } else {
      UserDefaults.standard.set(buffer, forKey: Self.bufferKey)
    }
  }
}

// MARK: - CLLocationManagerDelegate

extension SubtleWakeCoordinator: CLLocationManagerDelegate {
  func locationManager(
    _ manager: CLLocationManager,
    didChangeAuthorization status: CLAuthorizationStatus
  ) {
    applyAuthorizationStatus(status, manager: manager)
  }

  @available(iOS 14.0, *)
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    applyAuthorizationStatus(manager.authorizationStatus, manager: manager)
  }

  private func applyAuthorizationStatus(
    _ status: CLAuthorizationStatus, manager: CLLocationManager
  ) {
    switch status {
    case .authorizedAlways:
      if isRunning {
        manager.startMonitoringSignificantLocationChanges()
        applyRegions(to: manager)
      } else if wantsToRun {
        // Dart asked to start earlier but Always was missing; the user just
        // granted it. Re-arm without waiting for the next beacon toggle.
        start { _ in }
      }
    default:
      guard isRunning else { return }
      // Anything below Always means no background wakes. Tear down so a
      // later start() — after Dart's permission flow — can re-arm cleanly.
      manager.stopMonitoringSignificantLocationChanges()
      manager.stopMonitoringVisits()
      for region in manager.monitoredRegions {
        manager.stopMonitoring(for: region)
      }
      locationManager = nil
      isRunning = false
      // Keep THIS manager alive (delegate attached) as the authorization
      // observer: without a live manager the upgrade back to Always can
      // never fire the wantsToRun re-arm above — the same dead-observer
      // shape as critical #4.
      pendingAuthManager = manager
    }
  }

  func locationManager(
    _ manager: CLLocationManager,
    didUpdateLocations locations: [CLLocation]
  ) {
    // SLC fixes only — this manager never runs a continuous session.
    guard let location = locations.last else { return }
    // Wake the BLE carrier NOW, natively: the Dart burst that follows is the
    // second half of this wake, not a prerequisite for it (audit critical #5).
    BackgroundBeacon.shared.nudge(reason: "slc")
    emitWake([
      "kind": "slc",
      "lat": location.coordinate.latitude,
      "lon": location.coordinate.longitude,
      "acc": location.horizontalAccuracy,
      "ts": Int(location.timestamp.timeIntervalSince1970 * 1000),
    ])
  }

  func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
    guard region is CLCircularRegion else { return }
    BackgroundBeacon.shared.nudge(reason: "regionEnter")
    emitWake([
      "kind": "regionEnter",
      "id": region.identifier,
      "ts": Int(Date().timeIntervalSince1970 * 1000),
    ])
  }

  func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
    guard region is CLCircularRegion else { return }
    BackgroundBeacon.shared.nudge(reason: "regionExit")
    emitWake([
      "kind": "regionExit",
      "id": region.identifier,
      "ts": Int(Date().timeIntervalSince1970 * 1000),
    ])
  }

  func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
    // CLVisit fires on ARRIVAL with no motion requirement — the exact case
    // SLC misses: two phones that both arrive and then sit stationary at the
    // same venue. iOS delivers visits in the background like SLC.
    BackgroundBeacon.shared.nudge(reason: "visit")
    let arrivalKnown = visit.arrivalDate.timeIntervalSince1970 > 0
    emitWake([
      "kind": "visit",
      "lat": visit.coordinate.latitude,
      "lon": visit.coordinate.longitude,
      "acc": visit.horizontalAccuracy,
      "ts": Int((arrivalKnown ? visit.arrivalDate : Date()).timeIntervalSince1970 * 1000),
    ])
  }

  func locationManager(
    _ manager: CLLocationManager,
    monitoringDidFailFor region: CLRegion?,
    withError error: Error
  ) {
    // A single anchor failing (radius too large, region limit) must not tear
    // down SLC or the other regions.
    debugPrint("SubtleWakeCoordinator region \(region?.identifier ?? "?") failed: \(error)")
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    // Transient "location unavailable" errors are expected in background;
    // SLC monitoring persists across them.
    debugPrint("SubtleWakeCoordinator error: \(error)")
  }
}
