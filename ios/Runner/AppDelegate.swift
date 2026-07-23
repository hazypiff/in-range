import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // W2 (IOS_BACKGROUND_BLE_WIRING.md): if iOS relaunched us for a bluetooth
    // event (launchOptions bluetoothCentrals/Peripherals) — or the beacon was
    // on when the process died — the persisted flag brings CoreBluetooth back
    // up immediately, before (and without) the Flutter engine.
    BackgroundBeacon.shared.bootFromPersistence()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BackgroundBeacon") {
      BackgroundBeacon.shared.attach(messenger: registrar.messenger())
    }
  }
}
