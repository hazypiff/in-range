package io.inrange.app

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

/// D5/D3 raw-advert source + classifier channel (docs/BLE_PRIOR_ART_REVIEW_
/// 2026-07-26.md, findings D5 and D3). AdvertParser.kt is the mechanism; this
/// file is the plumbing. As in GattTokenReader.kt, Dart owns every policy
/// decision — which filters, which scan mode, when to start, what any byte
/// means — and native only does the radio work and the byte walking.
///
/// ── Why a native scan source, and not just a Dart-callable parser ────────
/// A parser Dart can call is worthless unless Dart can obtain the bytes, and
/// it cannot. flutter_blue_plus's AdvertisementData carries advName,
/// txPowerLevel, appearance, connectable, manufacturerData, serviceData and
/// serviceUuids and nothing else (flutter_blue_plus-2.3.10/lib/src/
/// flutter_blue_plus.dart:766-796); the Android plugin does compute
/// `bytesToHex(scanRecord.getBytes())` at FlutterBluePlusPlugin.java:2158 but
/// only to suppress duplicate adverts, and never serialises it. So there is no
/// route from the current scan path to raw bytes, and fixing D5 on the live
/// path requires a scan we own. That is the larger decision this file makes
/// possible and deliberately does not make: see "What this does NOT do".
///
/// ── Why an EventChannel and not a MethodChannel per advert ───────────────
/// A method-channel round trip per advert would be the wrong shape twice
/// over. First, cost: the scan runs with continuousUpdates, and a crowded room
/// produces adverts at tens to hundreds per second, each round trip costing
/// two platform-thread hops plus a StandardMessageCodec encode *and* decode.
/// Second, direction: the classification has to happen where the bytes are, so
/// there is nothing for Dart to send *in* — the traffic is one-way, native to
/// Dart, which is exactly an EventChannel. Control (start/stop/state) stays on
/// a MethodChannel in GattTokenReader.kt's style, because those are genuine
/// request/response calls and there are a handful of them per scan session,
/// not per advert.
///
/// Three further cost controls, all Dart-configured:
///   * `reportDelayMs` hands coalescing to the controller — the OS batches in
///     hardware and wakes the app once per window instead of once per advert.
///   * `minIntervalMsPerDevice` drops repeat adverts from the same MAC
///     natively, so the crowd never reaches the channel at all.
///   * `includeRaw` / `includeAppleValues` default off-ish, so the ordinary
///     event is a small skeleton of types, lengths and offsets.
///
/// ── What this does NOT do ────────────────────────────────────────────────
/// It does not start itself, and it does not touch the flutter_blue_plus scan.
/// Starting it is a second BluetoothLeScanner registration, which is a real
/// change to radio behaviour: per finding D6 the scan quota is charged at
/// scanner *registration* (aosp/ScanController.java:1113-1124, five per 30 s
/// with no callback on refusal), and per D7 an Android 14+ *filtered* client is
/// force-downgraded to LOW_POWER stickily for the life of the scanner. Running
/// two scanners concurrently therefore perturbs precisely what the 2026-07-27
/// walk is meant to measure, and the walk-day freeze list covers it. Whether
/// this becomes the app's only scan path — which would also retire
/// flutter_blue_plus from Android entirely and with it the Section 1.3
/// commercial-licence obligation of finding E5 — is a product decision, not
/// this file's.
class AdvertScanner(private val context: Context) : EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL = "io.inrange.app/advert"
        const val EVENT_CHANNEL = "io.inrange.app/advert_events"
    }

    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null

    private var scanner: BluetoothLeScanner? = null
    private var callback: ScanCallback? = null

    // Emission policy, set by startScan and read on the callback thread.
    @Volatile private var includeRaw = false
    @Volatile private var includeAppleValues = true
    @Volatile private var minIntervalMsPerDevice = 0

    /// Last emission per MAC, for minIntervalMsPerDevice. Bounded like the Dart
    /// token cache is: MAC randomisation makes this monotonically grow
    /// otherwise (7-15 min per Android peer, ~15 min per iPhone — finding
    /// D10), and a stale entry is worthless, so past the cap we drop the whole
    /// map rather than pay for an LRU.
    ///
    /// Unsynchronised on purpose: AOSP delivers ScanCallback on the main looper
    /// and MethodChannel handlers run on the platform thread, which is the same
    /// thread, so every access below is single-threaded. The @Volatile flags and
    /// the main.post() in emit() are the belt-and-braces for an OEM stack that
    /// disagrees — a wrong-thread EventSink call is a hard crash, a wrong-thread
    /// map read is just a stale timestamp.
    private val lastEmitAt = HashMap<String, Long>()
    private val lastEmitCap = 512

    // ── EventChannel.StreamHandler ─────────────────────────────────────

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    // ── MethodChannel: io.inrange.app/advert ───────────────────────────

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "platformInfo" -> result.success(platformInfo())
            "classify" -> classify(call, result)
            "startScan" -> startScan(call, result)
            "stopScan" -> stopScan(result)
            "isScanning" -> result.success(callback != null)
            else -> result.notImplemented()
        }
    }

    /// Everything Dart needs to choose D3's ScanFilter offsets, plus the device
    /// identity instrument W10 asks every log segment to be tagged with.
    ///
    /// `appleBlobSemantics` is how AOSP will collapse duplicate Apple ADs on
    /// *this* build: "last_wins" up to 14, "merge_flag_gated" on 15 (the
    /// concatenation is behind scanRecordManufacturerDataMerge(),
    /// ScanRecord.java:646-660, so it may be either), "merge" on 16+ where it
    /// is ungated (:644-656). On "merge_flag_gated" the safe move is to
    /// register a filter at both offsets — they are OR'd.
    private fun platformInfo(): Map<String, Any?> {
        val sdk = Build.VERSION.SDK_INT
        return mapOf(
            "sdkInt" to sdk,
            "release" to (Build.VERSION.RELEASE ?: ""),
            "buildId" to (Build.DISPLAY ?: ""),
            "manufacturer" to (Build.MANUFACTURER ?: ""),
            "model" to (Build.MODEL ?: ""),
            "appleBlobSemantics" to when {
                sdk >= 36 -> "merge"
                sdk == 35 -> "merge_flag_gated"
                else -> "last_wins"
            },
        )
    }

    /// Pure classification of bytes Dart already has — a captured PDU replayed
    /// as hex, or a record handed over from somewhere else. No radio, no
    /// permissions, safe to call from a test. This is the shape a Dart-side
    /// unit test uses to exercise AdvertParser without an Android SDK.
    ///
    /// Args: exactly one of `record` (ByteArray) or `hex` (String), plus
    /// optional `includeAppleValues` (Bool, default true).
    /// Errors: bad_args.
    private fun classify(call: MethodCall, result: MethodChannel.Result) {
        val record: ByteArray? = toBytes(call.argument<Any>("record"))
            ?: AdvertParser.parseHex(call.argument<String>("hex"))
        if (record == null) {
            result.error("bad_args", "record (bytes) or hex (even-length hex string) required", null)
            return
        }
        val values = call.argument<Boolean>("includeAppleValues") ?: true
        result.success(AdvertParser.summarize(record, includeAppleValues = values))
    }

    /// startScan(filters, scanMode, reportDelayMs, legacy, minIntervalMsPerDevice,
    ///           includeRaw, includeAppleValues) → true.
    ///
    /// `filters` is a list of maps, OR'd by the controller exactly like
    /// flutter_blue_plus's are. Each map takes either:
    ///   {companyId: Int, data?: ByteArray, mask?: ByteArray}   manufacturer
    ///   {serviceUuid: String, serviceMask?: String}            service UUID
    /// An empty list scans unfiltered — Dart's call, and Dart's problem:
    /// Android 8.1+ suppresses unfiltered screen-off scan results.
    ///
    /// Error codes, same taxonomy and same meanings as GattTokenReader:
    ///   bad_args         — malformed filter, mask length != data length, or a
    ///                      UUID that will not parse. Caller bug, not radio.
    ///   bt_off           — adapter absent/disabled, or no LE scanner
    ///   no_permission    — SecurityException (BLUETOOTH_SCAN / location)
    ///   already_scanning — a session is live; stopScan first
    ///   scan_failed      — startScan threw
    /// The event channel can also surface `parse_failed` — a single advert that
    /// blew up on the way to the sink, dropped rather than crashing the process.
    /// Runtime failures arrive on the event channel as a stream error with the
    /// same `scan_failed` code, because ScanCallback.onScanFailed is
    /// asynchronous and can fire long after this call returned. Subscribe to the
    /// event channel *before* calling this — adverts parsed while no sink is
    /// attached are dropped, not queued.
    private fun startScan(call: MethodCall, result: MethodChannel.Result) {
        if (callback != null) {
            result.error("already_scanning", "an advert scan session is already running", null)
            return
        }
        val adapter: BluetoothAdapter? =
            (context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
        if (adapter == null || !adapter.isEnabled) {
            result.error("bt_off", "Bluetooth adapter unavailable", null)
            return
        }
        val le = adapter.bluetoothLeScanner
        if (le == null) {
            result.error("bt_off", "no BluetoothLeScanner", null)
            return
        }

        val filters: List<ScanFilter>
        try {
            filters = buildFilters(call.argument<List<Map<String, Any?>>>("filters"))
        } catch (e: IllegalArgumentException) {
            result.error("bad_args", e.message, null)
            return
        }

        includeRaw = call.argument<Boolean>("includeRaw") ?: false
        includeAppleValues = call.argument<Boolean>("includeAppleValues") ?: true
        minIntervalMsPerDevice = call.argument<Int>("minIntervalMsPerDevice") ?: 0
        lastEmitAt.clear()

        val settings = buildSettings(
            mode = call.argument<String>("scanMode"),
            reportDelayMs = call.argument<Int>("reportDelayMs") ?: 0,
            legacy = call.argument<Boolean>("legacy") ?: true,
        )

        val cb = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, r: ScanResult?) {
                r?.let { emit(it) }
            }

            override fun onBatchScanResults(results: MutableList<ScanResult>?) {
                results?.forEach { emit(it) }
            }

            /// No notification exists for the quota refusal itself (finding D6:
            /// BluetoothLeScanner.java:501-503 maps it to sentinel scannerId
            /// -2 and drops it), so this fires only for the failures AOSP does
            /// report. Dart must not treat silence as health — that is W8.
            override fun onScanFailed(errorCode: Int) {
                val code = scanFailureName(errorCode)
                main.post { sink?.error("scan_failed", "$code ($errorCode)", null) }
            }
        }

        try {
            le.startScan(filters, settings, cb)
        } catch (e: SecurityException) {
            result.error("no_permission", e.message, null)
            return
        } catch (e: Exception) {
            result.error("scan_failed", e.message, null)
            return
        }
        scanner = le
        callback = cb
        result.success(true)
    }

    /// Idempotent: stopping a session that is not running is success, not an
    /// error, so Dart's teardown paths never have to guard.
    ///
    /// Local state is cleared before the stop is attempted and regardless of
    /// its outcome, so a throwing stopScan can never wedge this object into a
    /// permanent `already_scanning`. The trade is that a failed stop leaves the
    /// OS-side registration for the adapter/process cycle to reap — acceptable,
    /// because the only realistic throw here is a SecurityException from
    /// BLUETOOTH_SCAN being revoked at runtime, which unregisters us anyway.
    private fun stopScan(result: MethodChannel.Result) {
        val cb = callback
        val le = scanner
        callback = null
        scanner = null
        lastEmitAt.clear()
        if (cb == null || le == null) {
            result.success(true)
            return
        }
        try {
            le.stopScan(cb)
            result.success(true)
        } catch (e: SecurityException) {
            result.error("no_permission", e.message, null)
        } catch (e: Exception) {
            result.error("scan_failed", e.message, null)
        }
    }

    // ── Emission ───────────────────────────────────────────────────────

    /// One advert → one event. The parse happens here, on the callback thread,
    /// so nothing untyped and nothing large crosses the channel; delivery is
    /// posted to the platform thread because EventSink, like MethodChannel
    /// .Result, may only be touched there.
    private fun emit(r: ScanResult) {
        try {
            emitOrThrow(r)
        } catch (e: Exception) {
            // ScanCallback runs on the main looper: an escaping exception here
            // is an app crash, and a malformed advert from a stranger's device
            // is not a reason to take the process down. Drop the advert.
            main.post { sink?.error("parse_failed", e.message, null) }
        }
    }

    private fun emitOrThrow(r: ScanResult) {
        val record = r.scanRecord ?: return
        val bytes = record.bytes ?: return
        val mac = r.device?.address ?: return

        val nowMs = android.os.SystemClock.elapsedRealtime()
        if (minIntervalMsPerDevice > 0) {
            val last = lastEmitAt[mac]
            if (last != null && nowMs - last < minIntervalMsPerDevice) return
            if (lastEmitAt.size >= lastEmitCap) lastEmitAt.clear()
            lastEmitAt[mac] = nowMs
        }

        val out = HashMap<String, Any?>(24)
        out.putAll(AdvertParser.summarize(bytes, includeAppleValues = includeAppleValues))
        out["mac"] = mac
        out["rssi"] = r.rssi
        // Both stamps are boot-relative (SystemClock.elapsedRealtime domain),
        // NOT wall clock — ScanResult.timestampNanos is the radio's own stamp.
        // Handing over both in the same domain lets Dart compute a true
        // inter-advert gap without inheriting the Dart-isolate scheduler jitter
        // that caveats instrument W9.
        out["radioTimestampMs"] = r.timestampNanos / 1_000_000L
        out["receivedAtMs"] = nowMs
        out["txPower"] = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) r.txPower else null
        out["connectable"] = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) r.isConnectable else true
        out["advName"] = record.deviceName
        out["serviceUuids"] = record.serviceUuids?.map { it.uuid.toString() } ?: emptyList<String>()
        // Raw PDU is opt-in: it is the one field that carries the finding-D9
        // tracking-sensitive Apple payloads that summarize() redacts, and it is
        // the largest thing on the wire. Calibration/debug only.
        if (includeRaw) out["raw"] = bytes

        main.post { sink?.success(out) }
    }

    // ── Argument plumbing ──────────────────────────────────────────────

    /// @throws IllegalArgumentException with a message the caller can act on;
    /// startScan turns it into `bad_args`.
    private fun buildFilters(specs: List<Map<String, Any?>>?): List<ScanFilter> {
        if (specs == null || specs.isEmpty()) return emptyList()
        return specs.mapIndexed { i, spec ->
            val b = ScanFilter.Builder()
            val companyId = (spec["companyId"] as? Number)?.toInt()
            val serviceUuid = spec["serviceUuid"] as? String
            if (companyId == null && serviceUuid == null) {
                throw IllegalArgumentException("filter[$i] needs companyId or serviceUuid")
            }
            if (companyId != null) {
                val data = toBytes(spec["data"])
                val mask = toBytes(spec["mask"])
                if (mask != null && (data == null || mask.size != data.size)) {
                    // AOSP requires equal lengths and throws otherwise; fail
                    // here where we can say which filter was wrong.
                    throw IllegalArgumentException(
                        "filter[$i] mask length ${mask.size} != data length ${data?.size}"
                    )
                }
                if (data == null) b.setManufacturerData(companyId, null)
                else b.setManufacturerData(companyId, data, mask)
            }
            if (serviceUuid != null) {
                val uuid = try {
                    ParcelUuid(UUID.fromString(serviceUuid))
                } catch (e: IllegalArgumentException) {
                    throw IllegalArgumentException("filter[$i] serviceUuid not a UUID: $serviceUuid")
                }
                val serviceMask = (spec["serviceMask"] as? String)?.let {
                    try {
                        ParcelUuid(UUID.fromString(it))
                    } catch (e: IllegalArgumentException) {
                        throw IllegalArgumentException("filter[$i] serviceMask not a UUID: $it")
                    }
                }
                if (serviceMask == null) b.setServiceUuid(uuid) else b.setServiceUuid(uuid, serviceMask)
            }
            (spec["mac"] as? String)?.let {
                if (!BluetoothAdapter.checkBluetoothAddress(it)) {
                    throw IllegalArgumentException("filter[$i] mac not an address: $it")
                }
                b.setDeviceAddress(it)
            }
            b.build()
        }
    }

    /// StandardMessageCodec turns a Dart Uint8List into byte[] but a plain
    /// List<int> into a List of boxed Integers, and the difference is invisible
    /// at the Dart call site. Accept both rather than silently ignoring a
    /// filter's data/mask because the caller forgot Uint8List.fromList.
    private fun toBytes(value: Any?): ByteArray? = when (value) {
        null -> null
        is ByteArray -> value
        is List<*> -> ByteArray(value.size) { i -> ((value[i] as? Number)?.toInt() ?: 0).toByte() }
        else -> null
    }

    private fun buildSettings(mode: String?, reportDelayMs: Int, legacy: Boolean): ScanSettings {
        val b = ScanSettings.Builder()
        b.setScanMode(
            when (mode) {
                "opportunistic" -> ScanSettings.SCAN_MODE_OPPORTUNISTIC
                "low_power" -> ScanSettings.SCAN_MODE_LOW_POWER
                "low_latency" -> ScanSettings.SCAN_MODE_LOW_LATENCY
                else -> ScanSettings.SCAN_MODE_BALANCED
            }
        )
        b.setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
        if (reportDelayMs > 0) b.setReportDelay(reportDelayMs.toLong())
        // setLegacy is API 26+; AOSP's own default is already true, so older
        // builds are legacy-only regardless and the guard loses nothing.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) b.setLegacy(legacy)
        return b.build()
    }

    private fun scanFailureName(code: Int): String = when (code) {
        ScanCallback.SCAN_FAILED_ALREADY_STARTED -> "already_started"
        ScanCallback.SCAN_FAILED_APPLICATION_REGISTRATION_FAILED -> "registration_failed"
        ScanCallback.SCAN_FAILED_FEATURE_UNSUPPORTED -> "feature_unsupported"
        ScanCallback.SCAN_FAILED_INTERNAL_ERROR -> "internal_error"
        5 -> "out_of_hardware_resources"          // SCAN_FAILED_OUT_OF_HARDWARE_RESOURCES, API 33
        6 -> "scanning_too_frequently"            // SCAN_FAILED_SCANNING_TOO_FREQUENTLY, API 33
        else -> "unknown"
    }
}
