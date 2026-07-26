package io.inrange.app

/// D5/D3 BLE advertisement-structure parser — deliberately pure Kotlin.
/// No Android imports, no I/O, no state, no policy. See the bottom of this
/// file for the worked fixture, and AdvertScanner.kt for how it is reached.
///
/// ── Why this exists (finding D5) ────────────────────────────────────────
/// flutter_blue_plus never hands Dart the raw advert. It hands it a
/// Map<companyId, bytes> built by its own getManufacturerSpecificData(
/// ScanRecord) — flutter_blue_plus_android-9.0.3/.../FlutterBluePlusPlugin
/// .java:1933-1970 — which walks the PDU and appends *every* 0xFF
/// manufacturer AD's data, company-id bytes included, into a single
/// ByteArrayOutputStream. :2685-2701 then reads rawMsd[0..1] as *the*
/// manufacturer id and everything after it as *the* payload, storing exactly
/// one map entry. The plugin's own comment calls this a bug fix; it merges
/// where AOSP overwrote, but it loses the attribution either way.
///
/// Two consequences for in-range:
///   1. The `apple[0] == 0x01` test in beacon_service.dart:1006-1007 is false
///      whenever any other Apple AD precedes the overflow AD in the PDU —
///      i.e. for iPhones emitting Continuity Nearby Info (0x10), which iOS
///      broadcasts continuously regardless of user activity. Those peers are
///      delivered by the radio and then discarded in Dart, so backgrounded-
///      iOS token recovery *and* the 75 s keepalive wake never fire for them.
///   2. If a non-Apple manufacturer AD comes first in the same PDU, the map
///      key is that other company id and manufacturerData[0x004C] is null.
/// emulateFlutterBluePlusMsd() below reproduces the plugin's exact behaviour
/// so a walk can *count* how many peers this costs instead of assuming.
///
/// ── Why offsets are half the job (finding D3) ───────────────────────────
/// AOSP's own ScanRecord collapses duplicate company ids differently across
/// versions, and a hardware ScanFilter's data/mask is compared byte-for-byte
/// against exactly that collapsed array (aosp/ScanFilter.java:576-596,
/// reached from :492-500):
///
///   Android 10-14  overwrite, last AD wins  (ScanRecord.java:289,
///                                            android14-release:602)
///   Android 15     concatenate in PDU order, flag-gated
///                  scanRecordManufacturerDataMerge() (:646-660)
///   Android 16+    concatenate in PDU order, ungated (:644-656)
///
/// So the byte offset of the overflow AD inside the Apple blob is *inverted*
/// across the 14→15 boundary. Every Apple TLV below therefore reports both
/// `blobOffset` (merge semantics) and `lastWinsOffset` (overwrite semantics);
/// Dart chooses by SDK level — AdvertScanner.platformInfo hands it the level
/// and the resulting semantics label. This applies to in-range's *existing*
/// filter MsdFilter(0x004C, data:[0x01], mask:[0xFF])
/// (beacon_service.dart:912) exactly as much as to any new one.
object AdvertParser {

    // ── Bluetooth Core assigned numbers ────────────────────────────────
    const val AD_TYPE_FLAGS = 0x01
    const val AD_TYPE_TX_POWER = 0x0A
    const val AD_TYPE_MANUFACTURER = 0xFF

    /// Apple Inc., little-endian on air as `4C 00`.
    const val COMPANY_APPLE = 0x004C

    // ── Apple Continuity message types ─────────────────────────────────
    // Authoritative enumeration: furiousMAC's Wireshark dissector,
    // continuity/dissector/4.4.0/packet-bthci_cmd.c:1305-1323 (finding D9).
    const val APPLE_OVERFLOW_AREA = 0x01   // 16-byte service-UUID bitmap
    const val APPLE_IBEACON = 0x02
    const val APPLE_AIRPRINT = 0x03
    const val APPLE_AIRDROP = 0x05
    const val APPLE_HOMEKIT = 0x06
    const val APPLE_AIRPODS = 0x07
    const val APPLE_MAGIC_SWITCH = 0x0B
    const val APPLE_HANDOFF = 0x0C
    const val APPLE_TETHERING_SOURCE = 0x0D
    const val APPLE_NEARBY_ACTION = 0x0F
    const val APPLE_NEARBY_INFO = 0x10
    const val APPLE_FIND_MY = 0x12

    /// The overflow area is `01` followed by 16 bitmap bytes with **no inner
    /// length byte** — proved by arithmetic on the cited capture below
    /// (AD length 0x14 = 20 = 1 type + 2 company + 1 + 16) and independently
    /// corroborated by finding D1's ScanFilter example, whose bitmap byte 4
    /// lands at data index 5, i.e. bitmap byte k at index k+1.
    const val OVERFLOW_BITMAP_LEN = 16

    /// Types whose payloads are published de-anonymisation primitives and are
    /// therefore never returned in the structured view (finding D9's explicit
    /// ⚠️): 0x0C Handoff carries a 2-byte sequence number that is *static*
    /// across MAC rotation and drifts only ~470/day
    /// (continuity/shmoocon2020/shmoo20.pdf lines 248-251, 390-394), and 0x0D
    /// carries a 24-hour-stable iCloud account id
    /// (continuity/dissector/FIELDS.md:105). Using either would turn in-range
    /// into a cross-app tracking tool. Their type byte, length and offsets are
    /// still reported — that is all any legitimate in-range use needs.
    /// (AdvertScanner's `includeRaw` returns the whole PDU and so bypasses
    /// this; it is a debug/calibration switch, documented as such there.)
    val TRACKING_SENSITIVE_APPLE_TYPES = setOf(APPLE_HANDOFF, APPLE_TETHERING_SOURCE)

    private val EMPTY = ByteArray(0)

    // ── Layer 1: the AD-structure walker ───────────────────────────────

    /// One `[length][type][payload…]` structure. `offset` is the index of
    /// payload[0] inside the raw record, which is what makes D3's arithmetic
    /// possible. `truncated` means the declared length overran the buffer and
    /// the payload here is short — the walk stops after such a structure.
    class AdStructure(
        val type: Int,
        val payload: ByteArray,
        val offset: Int,
        val truncated: Boolean,
    ) {
        override fun toString() =
            "AD(type=0x%02X len=%d off=%d%s)".format(type, payload.size, offset,
                if (truncated) " TRUNCATED" else "")
    }

    /// Walk `ScanResult.getScanRecord().getBytes()`.
    ///
    /// Hostile and merely-buggy adverts are both common, so nothing here
    /// assumes well-formed input. AOSP's own parseFromBytes() relies on
    /// catching the ArrayIndexOutOfBounds and throwing the *whole* record
    /// away; we bound-check and keep what parsed. Handled: the zero-length
    /// terminator (legacy records are zero-padded to 31 bytes), a length byte
    /// with no type byte after it, a length that overruns the buffer, and
    /// `length == 1` (type byte, empty payload). The index advances by at
    /// least 2 on every iteration, so this cannot loop.
    ///
    /// Multiple ADs of the same type are all returned, in PDU order. That is
    /// the entire point of this file.
    fun parseAdStructures(record: ByteArray?): List<AdStructure> {
        if (record == null || record.isEmpty()) return emptyList()
        val out = ArrayList<AdStructure>(8)
        var i = 0
        while (i < record.size) {
            val length = record[i].toInt() and 0xFF
            if (length == 0) break              // terminator / trailing padding
            if (i + 1 >= record.size) break     // length byte, no type byte
            val type = record[i + 1].toInt() and 0xFF
            val dataStart = i + 2               // <= record.size, checked above
            val declared = length - 1           // payload bytes claimed
            val available = record.size - dataStart
            val actual = if (declared > available) available else declared
            out.add(
                AdStructure(
                    type = type,
                    payload = if (actual > 0) record.copyOfRange(dataStart, dataStart + actual) else EMPTY,
                    offset = dataStart,
                    truncated = actual != declared,
                )
            )
            if (actual != declared) break        // nothing trustworthy follows
            i = dataStart + declared
        }
        return out
    }

    // ── Layer 2: per-company manufacturer data, never merged ───────────

    /// One 0xFF AD. `companyId` is little-endian per the Core spec.
    /// `recordOffset` is the index of data[0] in the raw record.
    class ManufacturerAd(
        val companyId: Int,
        val data: ByteArray,
        val recordOffset: Int,
        val truncated: Boolean,
    ) {
        override fun toString() =
            "Mfg(company=0x%04X len=%d off=%d)".format(companyId, data.size, recordOffset)
    }

    /// Every 0xFF AD, separately, in PDU order. Duplicate company ids are
    /// preserved as separate entries — that is what the plugin destroys.
    ///
    /// A 0xFF AD carrying fewer than 2 payload bytes has no complete company
    /// id and is dropped. (The plugin's guard is `fieldLen >= 2`, i.e. one
    /// payload byte, so it will happily synthesise a company id out of one
    /// byte plus whatever the next AD contributed.)
    fun manufacturerAds(ads: List<AdStructure>): List<ManufacturerAd> {
        val out = ArrayList<ManufacturerAd>(4)
        for (ad in ads) {
            if (ad.type != AD_TYPE_MANUFACTURER || ad.payload.size < 2) continue
            out.add(
                ManufacturerAd(
                    companyId = (ad.payload[0].toInt() and 0xFF) or
                        ((ad.payload[1].toInt() and 0xFF) shl 8),
                    data = ad.payload.copyOfRange(2, ad.payload.size),
                    recordOffset = ad.offset + 2,
                    truncated = ad.truncated,
                )
            )
        }
        return out
    }

    fun manufacturerAds(record: ByteArray?): List<ManufacturerAd> =
        manufacturerAds(parseAdStructures(record))

    /// The byte array AOSP's ScanRecord.getManufacturerSpecificData(companyId)
    /// would return, and therefore the array a hardware ScanFilter's
    /// data/mask is compared against. `merge = true` is Android 15+/16
    /// (concatenate in PDU order); `merge = false` is Android 10-14
    /// (overwrite, last AD wins). Null when the company id is absent.
    fun companyBlob(record: ByteArray?, companyId: Int, merge: Boolean): ByteArray? {
        val ads = manufacturerAds(record).filter { it.companyId == companyId }
        if (ads.isEmpty()) return null
        if (!merge) return ads.last().data
        var total = 0
        for (ad in ads) total += ad.data.size
        val out = ByteArray(total)
        var at = 0
        for (ad in ads) {
            ad.data.copyInto(out, at)
            at += ad.data.size
        }
        return out
    }

    /// What flutter_blue_plus would report for this advert: the single map
    /// entry it stores, or null when it stores none. Exists so a walk can put
    /// a number on D5 — compare `companyId` against 0x004C and `firstByte`
    /// against 0x01 and you have the count of peers the current Dart test
    /// silently drops. Faithful to FlutterBluePlusPlugin.java:1933-1970 +
    /// :2685-2701, including its `fieldLen >= 2` guard.
    fun emulateFlutterBluePlusMsd(record: ByteArray?): Map<String, Any?>? {
        if (record == null) return null
        // Only merged[0..2] and the total length are observable in the plugin's
        // output, so accumulate those in one pass instead of materialising the
        // whole glued blob on every advert.
        val head = IntArray(3) { -1 }
        var merged = 0
        var i = 0
        while (i < record.size) {
            val fieldLen = record[i].toInt() and 0xFF
            if (fieldLen <= 0) break
            if (i + fieldLen >= record.size) break      // the plugin's own bound check
            val dataType = record[i + 1].toInt() and 0xFF
            if (dataType == AD_TYPE_MANUFACTURER && fieldLen >= 2) {
                // plugin: output.write(bytes, n + 2, fieldLen - 1) — company-id
                // bytes included, which is the whole problem.
                val contributed = fieldLen - 1
                for (h in 0..2) {
                    val want = h - merged
                    if (want in 0 until contributed) head[h] = record[i + 2 + want].toInt() and 0xFF
                }
                merged += contributed
            }
            i += fieldLen + 1
        }
        if (merged < 2) return null
        return mapOf(
            "companyId" to (head[0] or (head[1] shl 8)),
            "payloadLen" to (merged - 2),
            "firstByte" to if (merged > 2) head[2] else null,
        )
    }

    // ── Layer 3: Apple Continuity sub-structures ───────────────────────

    /// One Apple TLV.
    ///
    /// `blobOffset` is the index of this TLV's **type byte** inside the
    /// concatenated Apple blob — i.e. the ScanFilter data/mask index to use on
    /// Android 15+/16. `payloadBlobOffset` is the index of value[0].
    /// `lastWinsOffset` is the same index under Android 10-14's overwrite
    /// semantics, and is null when this TLV is not in the last Apple AD, which
    /// means those Androids cannot filter on it at all.
    /// `declaredLength` is the inner length byte, or null for 0x01, which has
    /// none.
    class AppleAd(
        val type: Int,
        val value: ByteArray,
        val declaredLength: Int?,
        val blobOffset: Int,
        val payloadBlobOffset: Int,
        val lastWinsOffset: Int?,
        val adIndex: Int,
        val truncated: Boolean,
    ) {
        override fun toString() =
            "Apple(type=0x%02X len=%d blobOff=%d lastWinsOff=%s ad=%d)".format(
                type, value.size, blobOffset, lastWinsOffset?.toString() ?: "-", adIndex)
    }

    /// Every Apple TLV across every Apple AD in the PDU, in order, with both
    /// D3 offsets computed.
    fun appleAds(record: ByteArray?): List<AppleAd> {
        val appleBlobs = manufacturerAds(record).filter { it.companyId == COMPANY_APPLE }
        if (appleBlobs.isEmpty()) return emptyList()
        val lastIndex = appleBlobs.size - 1
        val out = ArrayList<AppleAd>(4)
        var blobBase = 0
        for ((adIndex, ad) in appleBlobs.withIndex()) {
            parseAppleTlvs(ad.data, adIndex, blobBase, adIndex == lastIndex, ad.truncated, out)
            blobBase += ad.data.size
        }
        return out
    }

    /// Apple payloads are a TLV sequence of `[type][length][value…]`, with the
    /// documented exception of 0x01, which is `[type][16 bytes]`.
    ///
    /// Stops on a type byte of 0x00 followed by nothing but zeros: 0x00 is not
    /// an assigned Apple type (packet-bthci_cmd.c:1305-1323) and only shows up
    /// as padding inside an over-declared AD. A non-zero tail after a 0x00 is
    /// parsed rather than swallowed, so a genuinely new type cannot be hidden
    /// by this shortcut.
    private fun parseAppleTlvs(
        blob: ByteArray,
        adIndex: Int,
        blobBase: Int,
        isLastAd: Boolean,
        adTruncated: Boolean,
        out: ArrayList<AppleAd>,
    ) {
        var i = 0
        while (i < blob.size) {
            val type = blob[i].toInt() and 0xFF
            if (type == 0x00 && isAllZero(blob, i)) break

            val headerLen: Int
            val declared: Int?
            val wanted: Int
            if (type == APPLE_OVERFLOW_AREA) {
                headerLen = 1
                declared = null
                wanted = OVERFLOW_BITMAP_LEN
            } else {
                if (i + 1 >= blob.size) {
                    // Type byte with no length byte: report it, then stop.
                    out.add(
                        AppleAd(type, EMPTY, null, blobBase + i, blobBase + i + 1,
                            if (isLastAd) i else null, adIndex, true)
                    )
                    return
                }
                headerLen = 2
                declared = blob[i + 1].toInt() and 0xFF
                wanted = declared
            }

            val valueStart = i + headerLen
            val available = blob.size - valueStart
            val actual = if (wanted > available) available else wanted
            out.add(
                AppleAd(
                    type = type,
                    value = if (actual > 0) blob.copyOfRange(valueStart, valueStart + actual) else EMPTY,
                    declaredLength = declared,
                    blobOffset = blobBase + i,
                    payloadBlobOffset = blobBase + valueStart,
                    lastWinsOffset = if (isLastAd) i else null,
                    adIndex = adIndex,
                    truncated = adTruncated || actual != wanted,
                )
            )
            if (actual != wanted) return
            i = valueStart + wanted             // headerLen >= 1, so i advances
        }
    }

    private fun isAllZero(bytes: ByteArray, from: Int): Boolean {
        for (k in from until bytes.size) if (bytes[k] != 0.toByte()) return false
        return true
    }

    fun isAllZero(bytes: ByteArray): Boolean = isAllZero(bytes, 0)

    // ── Layer 4: the overflow bitmap (instrument W7) ────────────────────

    /// The first type-0x01 Apple TLV, or null. "First" rather than "only"
    /// because nothing on air guarantees uniqueness.
    fun overflowAd(record: ByteArray?): AppleAd? =
        appleAds(record).firstOrNull { it.type == APPLE_OVERFLOW_AREA }

    /// Bit positions set in a 16-byte overflow bitmap.
    ///
    /// The bitmap is LSB-first within each byte: bit p lives in byte p/8 at
    /// mask 1 shl (p%8) — OverflowAreaBeaconRef/.../OverflowAreaUtils.swift
    /// :206-250, restated in AndroidOverflowAreaDetector/README.md. A stranger
    /// sets roughly one bit per advertised service UUID, so this list is
    /// normally 1-3 entries long.
    fun bitmapBits(bitmap: ByteArray?): List<Int> {
        if (bitmap == null) return emptyList()
        val out = ArrayList<Int>(4)
        for (i in bitmap.indices) {
            val b = bitmap[i].toInt() and 0xFF
            if (b == 0) continue
            for (p in 0..7) if ((b and (1 shl p)) != 0) out.add(i * 8 + p)
        }
        return out
    }

    /// Byte index and mask a ScanFilter needs for a given bit position,
    /// relative to the start of the 16-byte bitmap. Add the AppleAd's
    /// `payloadBlobOffset` to get the ScanFilter data/mask index.
    fun bitmapByteForBit(bit: Int): Int = bit / 8

    fun bitmapMaskForBit(bit: Int): Int = 1 shl (bit % 8)

    /// Low nibble of Nearby Info byte 0 — the action code, per
    /// packet-bthci_cmd.c:1325-1343: 0x03 locked phone, 0x0A locked + pushing
    /// to Watch, 0x0B active user, 0x0D driving, 0x0E call. Finding D9's
    /// wake-cost oracle: locked vs active predicts whether the 75 s keepalive
    /// GATT read will make that iPhone scan back at all. It is *not* a
    /// pre-filter — it cannot separate an in-range user from any other iPhone.
    fun nearbyInfoActionCode(record: ByteArray?): Int? {
        val ad = appleAds(record).firstOrNull { it.type == APPLE_NEARBY_INFO } ?: return null
        if (ad.value.isEmpty()) return null
        return ad.value[0].toInt() and 0x0F
    }

    // ── Layer 5: one channel-ready summary ─────────────────────────────

    /// Everything above in one pass, as plain types StandardMessageCodec can
    /// encode (Int, Boolean, String, List, Map, ByteArray). Dart decides what
    /// any of it means; nothing here is policy.
    ///
    /// `includeAppleValues = false` drops every Apple TLV value, which is the
    /// cheap shape for a crowded room — the type/offset/length skeleton is
    /// what D3 and W7 need, and the overflow bitmap is surfaced separately.
    fun summarize(record: ByteArray?, includeAppleValues: Boolean = true): Map<String, Any?> {
        val ads = parseAdStructures(record)
        val mfg = manufacturerAds(ads)
        val apple = appleAds(record)
        val overflow = apple.firstOrNull { it.type == APPLE_OVERFLOW_AREA }
        val bitmap = overflow?.value
        val nearbyInfo = apple.firstOrNull { it.type == APPLE_NEARBY_INFO }

        return mapOf(
            "recordLen" to (record?.size ?: 0),
            "adCount" to ads.size,
            "malformed" to (ads.any { it.truncated } || apple.any { it.truncated }),
            // PDU order, duplicates preserved — the D5 evidence in one field.
            "companyIds" to mfg.map { it.companyId },
            "manufacturer" to mfg.map {
                mapOf(
                    "companyId" to it.companyId,
                    "len" to it.data.size,
                    "recordOffset" to it.recordOffset,
                    "data" to it.data,
                )
            },
            "apple" to apple.map {
                val redact = it.type in TRACKING_SENSITIVE_APPLE_TYPES
                mapOf(
                    "type" to it.type,
                    "len" to it.value.size,
                    "declaredLength" to it.declaredLength,
                    "blobOffset" to it.blobOffset,
                    "payloadBlobOffset" to it.payloadBlobOffset,
                    "lastWinsOffset" to it.lastWinsOffset,
                    "adIndex" to it.adIndex,
                    "truncated" to it.truncated,
                    // Redacted per D9: see TRACKING_SENSITIVE_APPLE_TYPES.
                    "value" to if (includeAppleValues && !redact) it.value else null,
                )
            },
            "appleTypes" to apple.map { it.type },
            "isOverflow" to (overflow != null),
            // ScanFilter data/mask index of the 0x01 type byte under each
            // AOSP semantics (D3). Dart picks by SDK level.
            "overflowBlobOffset" to overflow?.blobOffset,
            "overflowLastWinsOffset" to overflow?.lastWinsOffset,
            "overflowBitmap" to bitmap,
            "overflowBitmapLen" to bitmap?.size,
            "overflowBits" to bitmapBits(bitmap),
            // A8: an all-zero bitmap is provably not an in-range peer.
            "overflowAllZero" to bitmap?.let { isAllZero(it) },
            "nearbyInfoByte0" to nearbyInfo?.value?.let {
                if (it.isEmpty()) null else it[0].toInt() and 0xFF
            },
            "nearbyInfoActionCode" to nearbyInfo?.value?.let {
                if (it.isEmpty()) null else it[0].toInt() and 0x0F
            },
            // What Dart is being told today, for side-by-side counting.
            "pluginWouldReport" to emulateFlutterBluePlusMsd(record),
        )
    }

    // ── Hex helpers (AdvertScanner.classify replays captured hex) ───────

    /// Lenient: ignores whitespace, `:` and `-`. Returns null on odd length or
    /// a non-hex digit, which the channel turns into `bad_args`.
    fun parseHex(hex: String?): ByteArray? {
        if (hex == null) return null
        val sb = StringBuilder(hex.length)
        for (c in hex) if (c != ' ' && c != ':' && c != '-' && c != '\n' && c != '\t') sb.append(c)
        if (sb.length % 2 != 0) return null
        val out = ByteArray(sb.length / 2)
        for (i in out.indices) {
            val hi = Character.digit(sb[i * 2], 16)
            val lo = Character.digit(sb[i * 2 + 1], 16)
            if (hi < 0 || lo < 0) return null
            out[i] = ((hi shl 4) or lo).toByte()
        }
        return out
    }

    fun toHex(bytes: ByteArray?): String {
        if (bytes == null) return ""
        val sb = StringBuilder(bytes.size * 2)
        for (b in bytes) {
            val v = b.toInt() and 0xFF
            sb.append(HEX[v ushr 4]).append(HEX[v and 0x0F])
        }
        return sb.toString()
    }

    private val HEX = "0123456789abcdef".toCharArray()

    // ── Worked fixture ─────────────────────────────────────────────────
    //
    // The capture in android-beacon-library/.../OverflowAreaBeaconTest.java:28
    // — a real modern iPhone — exercises multi-AD, same-company-id
    // duplication and offset computation in one packet:
    //
    //   02 01 1A                                    Flags
    //   02 0A 0C                                    TX Power
    //   0E FF 4C 00  0F 05 …                        Apple AD #0, 11 payload
    //   14 FF 4C 00  01 56 FE 87 49 …               Apple AD #1, 17 payload
    //
    // Walker output: 4 AD structures; two of type 0xFF, both company 0x004C.
    // Apple AD #0 payload starts at record offset 10 and is 11 bytes; Apple
    // AD #1 payload starts at record offset 25 and is 17 bytes (0x14 = 20 =
    // 1 type + 2 company + 1 + 16, which is the arithmetic proof that the
    // overflow area carries no inner length byte).
    //
    // Apple TLVs and their D3 offsets:
    //   type 0x0F  adIndex 0  blobOffset 0   lastWinsOffset null
    //   type 0x01  adIndex 1  blobOffset 11  lastWinsOffset 0
    //              payloadBlobOffset 12 (merge) / 1 (last-wins)
    //
    // Therefore, for this packet ordering:
    //   Android 10-14  the Apple blob *is* AD #1 → the 0x01 byte is at index
    //                  0, and in-range's live MsdFilter(0x004C, data:[0x01],
    //                  mask:[0xFF]) matches.
    //   Android 15/16  the blob is AD #0 ++ AD #1 → the 0x01 byte is at index
    //                  11, and that same filter MISSES this iPhone entirely.
    //
    // Cross-check on the bitmap layout: finding D1's filter for bit 36 is
    // data = 01 00 00 00 00 10 …, i.e. bitmap byte 4 at data index 5, so
    // bitmap byte k sits at index k+1 — exactly payloadBlobOffset -
    // blobOffset == 1. Two independently derived results agree.
}
