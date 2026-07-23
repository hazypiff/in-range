package io.inrange.app

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// WiFi AP scanning for venue co-location (docs/PROXIMITY_ALGORITHM.md L1).
///
/// Own platform channel rather than a plugin: every pub WiFi-scan package is
/// still pinned to pre-Dart-3 SDKs, and all we need is the cached scan list.
///
/// We deliberately DO NOT call startScan(): Android 9+ throttles it hard
/// (4 calls / 2 min foreground, and it is a no-op when throttled), while
/// getScanResults() returns the system's latest cached results, which the
/// platform refreshes on its own schedule. Reading the cache is unthrottled,
/// costs no radio time, and is exactly what a 60s venue cadence needs.
class MainActivity : FlutterActivity() {
    private val channel = "io.inrange.app/wifi"
    private val gattChannel = "io.inrange.app/gatt"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scanResults" -> result.success(scanResults())
                    "requestScan" -> result.success(requestScan())
                    else -> result.notImplemented()
                }
            }
        // W3 GATT token recovery (GattTokenReader.kt) — native so the app's
        // one connect path carries no flutter_blue_plus license obligation.
        val gattReader = GattTokenReader(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, gattChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "readToken" -> gattReader.readToken(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    /// Latest cached scan results: [{bssid, ssid, rssi, freq, ageMs}]
    private fun scanResults(): List<Map<String, Any>> {
        return try {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val now = android.os.SystemClock.elapsedRealtime()
            wifi.scanResults.map { r ->
                val ageMs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR1) {
                    now - (r.timestamp / 1000) // ScanResult.timestamp is microseconds
                } else {
                    0L
                }
                mapOf(
                    "bssid" to (r.BSSID ?: ""),
                    "ssid" to (r.SSID ?: ""),
                    "rssi" to r.level,
                    "freq" to r.frequency,
                    "ageMs" to ageMs,
                )
            }
        } catch (e: SecurityException) {
            emptyList()
        } catch (e: Exception) {
            emptyList()
        }
    }

    /// Best-effort nudge for a fresh scan. Returns false when throttled or
    /// unavailable — callers must treat the cached list as the source of truth.
    private fun requestScan(): Boolean {
        return try {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            @Suppress("DEPRECATION")
            wifi.startScan()
        } catch (e: Exception) {
            false
        }
    }
}
