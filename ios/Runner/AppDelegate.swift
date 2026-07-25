import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var apnsChannel: FlutterMethodChannel?
  private var pendingDeviceToken: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // W2 (IOS_BACKGROUND_BLE_WIRING.md): if iOS relaunched us for a bluetooth
    // event (launchOptions bluetoothCentrals/Peripherals) — or the beacon was
    // on when the process died — the persisted flag brings CoreBluetooth back
    // up immediately, before (and without) the Flutter engine.
    BackgroundBeacon.shared.bootFromPersistence()
    // Tier 2-3 (SUBTLE_TRACKING_ARCHITECTURE.md): an SLC/region relaunch
    // delivers its event only to a CLLocationManager recreated DURING launch
    // with monitoring restarted — rebuild from the persisted session before
    // the engine, and before super returns, exactly like the Bluetooth boot.
    SubtleWakeCoordinator.shared.bootFromPersistence()
    // Tier 4 (SUBTLE_TRACKING_ARCHITECTURE.md): APNs registration shows no
    // prompt — the permission alert belongs to UNUserNotificationCenter,
    // whose flow Dart owns. Fails harmlessly until the Mac build adds the
    // Push Notifications capability.
    application.registerForRemoteNotifications()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BackgroundBeacon") {
      BackgroundBeacon.shared.attach(messenger: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "WifiAssistPlugin") {
      WifiAssistPlugin.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BackgroundLocationCoordinator") {
      BackgroundLocationCoordinator.shared.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SubtleWakeCoordinator") {
      SubtleWakeCoordinator.shared.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AppDelegate") {
      let ch = FlutterMethodChannel(
        name: "io.inrange.app/apns", binaryMessenger: registrar.messenger())
      apnsChannel = ch
      ch.setMethodCallHandler { [weak self] call, result in
        switch call.method {
        case "getDeviceToken":
          // Pull path for a token that arrived before Dart attached a handler.
          result(self?.pendingDeviceToken)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
      if let token = pendingDeviceToken {
        ch.invokeMethod("onDeviceToken", arguments: token)
      }
    }
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    pendingDeviceToken = token
    apnsChannel?.invokeMethod("onDeviceToken", arguments: token)
    super.application(
      application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    // Expected in the simulator and until the capability is added in Xcode.
    debugPrint("APNs registration failed: \(error)")
    super.application(
      application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    // super is NOT called: FlutterAppDelegate completes the handler with
    // .noData via its lifecycle delegate (no linked plugin consumes remote
    // notifications), and completing twice is a runtime error.
    SubtleWakeCoordinator.shared.handleRemoteNotification(
      userInfo, completion: completionHandler)
  }
}
