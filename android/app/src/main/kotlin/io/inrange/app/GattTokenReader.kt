package io.inrange.app

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

/// W3 GATT token recovery, native (docs/IOS_BACKGROUND_BLE_WIRING.md).
///
/// Own BluetoothGatt implementation rather than a plugin: flutter_blue_plus
/// gates connect() behind a commercial License declaration, and this — one
/// connect → discover → read of a 16-byte characteristic → disconnect — is
/// the app's only connect path on Android. iOS does the same natively in
/// BackgroundBeacon.swift, so going native here removes the license
/// obligation without losing any cross-platform surface.
///
/// One call = one BluetoothGatt object with its own callback; concurrent
/// reads of different devices are independent. The Dart side owns all
/// policy (per-device backoff, keepalive cadence, token cache, in-flight
/// guard) — this class only does the radio round-trip.
class GattTokenReader(private val context: Context) {

    /// readToken(mac, serviceUuid, charUuid, timeoutMs) → 16 token bytes.
    /// Error codes mirror what the Dart log distinguishes:
    ///   no_service    — connected, but the peer doesn't host our service
    ///                   (a stranger's backgrounded iPhone; back off long)
    ///   connect_failed / read_failed / timeout / bt_off / bad_args /
    ///   no_permission — transient or environmental; back off normally
    fun readToken(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        val mac = call.argument<String>("mac")
        val serviceUuid = call.argument<String>("serviceUuid")
        val charUuid = call.argument<String>("charUuid")
        val timeoutMs = call.argument<Int>("timeoutMs") ?: 10000
        if (mac == null || serviceUuid == null || charUuid == null ||
            !BluetoothAdapter.checkBluetoothAddress(mac)) {
            result.error("bad_args", "mac/serviceUuid/charUuid required", null)
            return
        }
        val adapter = (context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
        if (adapter == null || !adapter.isEnabled) {
            result.error("bt_off", "Bluetooth adapter unavailable", null)
            return
        }

        val svc = UUID.fromString(serviceUuid)
        val chr = UUID.fromString(charUuid)
        val main = Handler(Looper.getMainLooper())
        val done = AtomicBoolean(false)
        var gattRef: BluetoothGatt? = null

        // Every exit path funnels here exactly once: deliver on the platform
        // thread (MethodChannel requirement), then disconnect+close — close()
        // matters, leaked BluetoothGatt objects exhaust the client-if table
        // (BT stack cap ~32) and every later connect fails with status 133.
        fun finish(block: () -> Unit) {
            if (!done.compareAndSet(false, true)) return
            main.post {
                block()
                try {
                    gattRef?.disconnect()
                    gattRef?.close()
                } catch (_: Exception) {}
            }
        }

        val callback = object : BluetoothGattCallback() {
            override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
                if (newState == BluetoothProfile.STATE_CONNECTED && status == BluetoothGatt.GATT_SUCCESS) {
                    if (!gatt.discoverServices()) {
                        finish { result.error("connect_failed", "discoverServices refused", null) }
                    }
                } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                    finish { result.error("connect_failed", "disconnected status=$status", null) }
                }
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    finish { result.error("connect_failed", "discovery status=$status", null) }
                    return
                }
                val c = gatt.getService(svc)?.getCharacteristic(chr)
                if (c == null) {
                    finish { result.error("no_service", "peer has no token service", null) }
                    return
                }
                if (!gatt.readCharacteristic(c)) {
                    finish { result.error("read_failed", "readCharacteristic refused", null) }
                }
            }

            // API 33+ delivers the value in the new overload; older Androids
            // (the S9s) call the deprecated one. `done` makes overlap harmless.
            override fun onCharacteristicRead(
                gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic,
                value: ByteArray, status: Int
            ) {
                deliver(value, status)
            }

            @Deprecated("pre-33 path")
            override fun onCharacteristicRead(
                gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int
            ) {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                    @Suppress("DEPRECATION")
                    deliver(characteristic.value ?: ByteArray(0), status)
                }
            }

            private fun deliver(value: ByteArray, status: Int) {
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    finish { result.success(value) }
                } else {
                    finish { result.error("read_failed", "read status=$status", null) }
                }
            }
        }

        try {
            val device: BluetoothDevice = adapter.getRemoteDevice(mac)
            gattRef = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                device.connectGatt(context, false, callback, BluetoothDevice.TRANSPORT_LE)
            } else {
                device.connectGatt(context, false, callback)
            }
            if (gattRef == null) {
                finish { result.error("connect_failed", "connectGatt returned null", null) }
                return
            }
            main.postDelayed({
                finish { result.error("timeout", "no result in ${timeoutMs}ms", null) }
            }, timeoutMs.toLong())
        } catch (e: SecurityException) {
            finish { result.error("no_permission", e.message, null) }
        } catch (e: Exception) {
            finish { result.error("connect_failed", e.message, null) }
        }
    }
}
