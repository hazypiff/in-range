import Flutter
import NetworkExtension

/// Opportunistic connected-BSSID sampling for iOS venue corroboration.
///
/// Requires the Access WiFi Information entitlement and precise location
/// authorization. Without either, fetchCurrent returns nil and this plugin
/// silently reports no network. It does not wake the app; it is only called
/// from Dart when another callback already provides runtime.
struct WifiAssistPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "io.inrange.app/wifi_assist",
      binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "currentBSSID":
        if #available(iOS 14.0, *) {
          NEHotspotNetwork.fetchCurrent { network in
            // FlutterResult must be invoked on the platform (main) thread.
            DispatchQueue.main.async {
              guard let net = network else {
                result(nil)
                return
              }
              result([
                "bssid": net.bssid,
                "ssid": net.ssid,
              ])
            }
          }
        } else {
          // NEHotspotNetwork.fetchCurrent requires iOS 14+.
          result(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
