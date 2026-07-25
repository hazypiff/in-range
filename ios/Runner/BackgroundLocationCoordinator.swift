import Flutter
import CoreLocation
import UIKit

/// Native iOS location session for the beacon's residency / candidate-pruning path.
///
/// This is intentionally NOT a distance-classification source. It keeps a coarse
/// location session alive while the beacon is on, buffers fixes in UserDefaults,
/// and bridges them to Dart when the app returns to foreground. The coordinates
/// are used for server-side radius gates and for refreshing the sighting cache;
/// they are never uploaded raw without the user's explicit encounter location.
///
/// The session is started/stopped by `LocationKeepalive` over the method channel
/// `io.inrange.app/location_coordinator`. If the native coordinator is not
/// registered (e.g. an older iOS build), Dart falls back to the existing
/// `geolocator` stream.
final class BackgroundLocationCoordinator: NSObject {
  static let shared = BackgroundLocationCoordinator()

  private static let channelName = "io.inrange.app/location_coordinator"
  private static let bufferKey = "io.inrange.location.buffer"
  private static let bufferCap = 100

  private var channel: FlutterMethodChannel?
  private var locationManager: CLLocationManager?
  private var isRunning = false

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
        self.start(call.arguments as? [String: Any] ?? [:], result: result)
      case "stop":
        self.stop(result: result)
      case "flush":
        result(self.drainBuffer())
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(appDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification,
      object: nil)
  }

  // MARK: - Lifecycle

  private func start(_ config: [String: Any], result: @escaping FlutterResult) {
    guard !isRunning else {
      result(true)
      return
    }
    guard CLLocationManager.locationServicesEnabled() else {
      result(false)
      return
    }

    let manager = CLLocationManager()
    manager.delegate = self
    // Coarsest accuracy that still sustains a session. We keep the fix, not the
    // precision: asking for meters here would only spend battery and collect
    // sensitive data we have no use for.
    manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    manager.distanceFilter = (config["distanceFilter"] as? NSNumber)?.doubleValue ?? 100
    manager.activityType = .other
    manager.pausesLocationUpdatesAutomatically = false
    manager.allowsBackgroundLocationUpdates = true
    manager.showsBackgroundLocationIndicator = true
    locationManager = manager
    isRunning = true

    let auth: CLAuthorizationStatus
    if #available(iOS 14.0, *) {
      auth = manager.authorizationStatus
    } else {
      auth = CLLocationManager.authorizationStatus()
    }
    switch auth {
    case .notDetermined:
      manager.requestAlwaysAuthorization()
    case .authorizedAlways, .authorizedWhenInUse:
      manager.startUpdatingLocation()
    default:
      isRunning = false
      self.locationManager = nil
      result(false)
      return
    }

    result(true)
  }

  private func stop(result: FlutterResult?) {
    locationManager?.stopUpdatingLocation()
    locationManager?.delegate = nil
    locationManager = nil
    isRunning = false
    result?(true)
  }

  @objc private func appDidBecomeActive() {
    guard let ch = channel else { return }
    let fixes = drainBuffer()
    guard !fixes.isEmpty else { return }
    ch.invokeMethod("onLocationFixes", arguments: fixes)
  }

  // MARK: - Ring buffer

  private func loadBuffer() -> [[String: Any]] {
    UserDefaults.standard.array(forKey: Self.bufferKey) as? [[String: Any]] ?? []
  }

  private func saveBuffer(_ buffer: [[String: Any]]) {
    UserDefaults.standard.set(buffer, forKey: Self.bufferKey)
  }

  private func appendFix(_ location: CLLocation) {
    var buffer = loadBuffer()
    let moving: Bool? = location.speed >= 0 ? location.speed > 0.5 : nil
    buffer.append([
      "lat": location.coordinate.latitude,
      "lon": location.coordinate.longitude,
      "acc": location.horizontalAccuracy,
      "ts": Int(location.timestamp.timeIntervalSince1970 * 1000),
      "moving": moving ?? false,
    ])
    if buffer.count > Self.bufferCap {
      buffer.removeFirst(buffer.count - Self.bufferCap)
    }
    saveBuffer(buffer)
  }

  private func drainBuffer() -> [[String: Any]] {
    let buffer = loadBuffer()
    UserDefaults.standard.removeObject(forKey: Self.bufferKey)
    return buffer
  }
}

// MARK: - CLLocationManagerDelegate

extension BackgroundLocationCoordinator: CLLocationManagerDelegate {
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
      manager.startUpdatingLocation()
    case .authorizedWhenInUse:
      // Updates may pause in deep background without Always, but this still
      // gives us foreground + transition fixes and keeps the indicator honest.
      manager.startUpdatingLocation()
    default:
      manager.stopUpdatingLocation()
    }
  }

  func locationManager(
    _ manager: CLLocationManager,
    didUpdateLocations locations: [CLLocation]
  ) {
    for location in locations {
      appendFix(location)
    }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    // CLLocationManager can emit a brief "location unavailable" error when the
    // app backgrounds; this is transient and must not tear the session down.
    debugPrint("BackgroundLocationCoordinator error: \(error)")
  }
}
