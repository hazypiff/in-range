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

  private var channel: FlutterMethodChannel?
  private var locationManager: CLLocationManager?
  private var isRunning = false
  /// Latest anchor set from Dart (id/lat/lon/radius/onEnter/onExit dicts),
  /// kept so start() and authorization upgrades can re-arm regions without a
  /// Dart round-trip. Regions are built lazily in applyRegions so the radius
  /// can be clamped against maximumRegionMonitoringDistance.
  private var desiredRegions: [[String: Any]] = []

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
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(appDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification,
      object: nil)
    // Deliver any wakes buffered before the engine attached (e.g. an SLC or
    // region relaunch, where delegate callbacks can beat engine startup).
    flushBuffered()
  }

  // MARK: - Lifecycle

  private func start(result: FlutterResult) {
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
      locationManager = manager
      isRunning = true
      manager.startMonitoringSignificantLocationChanges()
      applyRegions(to: manager)
      result(true)
    case .notDetermined, .authorizedWhenInUse, .denied, .restricted:
      // Do NOT request authorization natively. Without Always there are no
      // background wakes, so report unavailable and let Dart's permission
      // flow (or a fallback) handle it.
      manager.delegate = nil
      result(false)
    @unknown default:
      manager.delegate = nil
      result(false)
    }
  }

  private func stop(result: FlutterResult?) {
    if let manager = locationManager {
      manager.stopMonitoringSignificantLocationChanges()
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
    let monitoredIds = Set(manager.monitoredRegions.map { $0.identifier })
    for entry in desiredRegions {
      guard let id = entry["id"] as? String, !id.isEmpty,
            !monitoredIds.contains(id),
            let lat = (entry["lat"] as? NSNumber)?.doubleValue,
            let lon = (entry["lon"] as? NSNumber)?.doubleValue,
            let radius = (entry["radius"] as? NSNumber)?.doubleValue
      else { continue }
      let center = CLLocationCoordinate2D(latitude: lat, longitude: lon)
      guard CLLocationCoordinate2DIsValid(center), radius > 0 else { continue }
      let region = CLCircularRegion(
        center: center,
        radius: min(radius, manager.maximumRegionMonitoringDistance),
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
  func handleRemoteNotification(
    _ userInfo: [AnyHashable: Any],
    completion: @escaping (UIBackgroundFetchResult) -> Void
  ) {
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
    completion(.newData)
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
      // BackgroundBeacon.emitSighting), so persist first and flush on
      // foreground. The live call still reaches an engine that iOS resumed
      // for this wake; wake hints are idempotent, so the duplicate that may
      // flush later is harmless.
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
    flushBuffered()
  }

  private func flushBuffered() {
    guard let ch = channel,
          let buffer =
            UserDefaults.standard.array(forKey: Self.bufferKey) as? [[String: Any]],
          !buffer.isEmpty else { return }
    UserDefaults.standard.removeObject(forKey: Self.bufferKey)
    for event in buffer {
      ch.invokeMethod("onWake", arguments: event)
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
    guard isRunning else { return }
    switch status {
    case .authorizedAlways:
      manager.startMonitoringSignificantLocationChanges()
      applyRegions(to: manager)
    default:
      // Anything below Always means no background wakes. Tear down so a
      // later start() — after Dart's permission flow — can re-arm cleanly.
      manager.stopMonitoringSignificantLocationChanges()
      for region in manager.monitoredRegions {
        manager.stopMonitoring(for: region)
      }
      manager.delegate = nil
      locationManager = nil
      isRunning = false
    }
  }

  func locationManager(
    _ manager: CLLocationManager,
    didUpdateLocations locations: [CLLocation]
  ) {
    // SLC fixes only — this manager never runs a continuous session.
    guard let location = locations.last else { return }
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
    emitWake([
      "kind": "regionEnter",
      "id": region.identifier,
      "ts": Int(Date().timeIntervalSince1970 * 1000),
    ])
  }

  func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
    guard region is CLCircularRegion else { return }
    emitWake([
      "kind": "regionExit",
      "id": region.identifier,
      "ts": Int(Date().timeIntervalSince1970 * 1000),
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
