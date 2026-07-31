package io.inrange.app

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/// JVM unit tests for AdvertParser (findings D5 and D3).
///
/// ── Why these exist as a checked-in test and not a scratch script ────────
/// The parser was first verified by transcribing its logic into Python and
/// asserting against it. That proves the transcription agrees with itself and
/// nothing else: it cannot fail when someone edits AdvertParser.kt, it dies
/// with the directory it lived in, and no reviewer can re-run it. AdvertParser
/// is now load-bearing — it exists because flutter_blue_plus merges every
/// manufacturer AD into one blob and labels the result with the *first*
/// company id, which is very likely breaking backgrounded-iPhone detection in
/// the shipped build right now — so the evidence has to live next to the code.
/// AdvertParser has no Android imports, so plain JUnit on the JVM is enough
/// (see app/build.gradle.kts).
///
/// Run: `./gradlew :app:testDebugUnitTest`. Not yet reached by
/// .github/workflows/ci.yml, which runs `flutter analyze` and `flutter test`
/// and never invokes Gradle.
///
/// ── What is actually being pinned ────────────────────────────────────────
/// Almost every assertion below is about a *number*, not a shape. The whole
/// point of the file is that a hardware ScanFilter's data/mask is compared
/// byte-for-byte against AOSP's collapsed manufacturer blob, so if an offset
/// is off by one the filter silently stops matching and the token-recovery
/// path goes dark with no error anywhere. Offsets are therefore asserted as
/// literal integers, and the same overflow AD is placed at five different blob
/// offsets (0, 3, 5, 10, 11) across five fixtures to prove the offset is the
/// *sum of preceding Apple AD payload lengths* rather than one of a small set
/// of magic values someone could hardcode and get away with.
///
/// ── Fixture provenance, stated plainly ───────────────────────────────────
/// * YOUNG_CAPTURE is a real capture, quoted byte-for-byte: Young's
///   ios-overflow-area README (iPhone 6, iOS 11), the same 24 bytes already
///   recorded in test/apple_overflow_bit_test.dart:102 and in
///   lib/features/beacon/apple_overflow_bit.dart:56. Its bitmap sets bit 83
///   and nothing else. It has exactly ONE Apple AD.
/// * BRIEF_COMPOSITE is the multi-AD packet AdvertParser.kt's header works
///   through (overflow type byte at blob offset 11). Two things about it that
///   the header does not say:
///     - It is **constructed**, not captured. The header attributes it to
///       android-beacon-library's OverflowAreaBeaconTest.java:28, but the only
///       bytes on record anywhere in this repo for that citation trail are
///       YOUNG_CAPTURE's single Apple AD, and the header's own `0f 05 …`
///       elides four bytes it does not give. Nothing in the corpus available
///       offline shows a real two-Apple-AD capture.
///     - It is 42 bytes, which is **above the 31-byte legacy AdvData cap**, so
///       no legacy ADV_IND can carry it and offset 11 is not an observed
///       on-air value. Pinned anyway, because it is the arithmetic the header
///       documents and the number a reader will check against.
/// * LEGACY_LEGAL is the same bug in a packet that can exist on legacy air:
///   31 bytes exactly, overflow type byte at blob offset 3. This is the shape
///   a real backgrounded iPhone can actually emit, and it breaks
///   `apple[0] == 0x01` just as thoroughly as the 42-byte composite.
/// Everything else is a deliberately synthesised structural probe and is
/// labelled as such.
class AdvertParserTest {

    // ── Fixture helpers ────────────────────────────────────────────────
    //
    // hex() is reimplemented here rather than delegating to
    // AdvertParser.parseHex: fixtures must not be built by the code under
    // test, or a parseHex bug corrupts every expectation in the file at once
    // and the suite goes quietly green. parseHex gets its own tests below.

    private fun hex(s: String): ByteArray {
        val clean = s.filter { it != ' ' && it != '\n' }
        require(clean.length % 2 == 0) { "fixture has odd hex length: $s" }
        return ByteArray(clean.length / 2) {
            clean.substring(it * 2, it * 2 + 2).toInt(16).toByte()
        }
    }

    private fun b(vararg v: Int): ByteArray = ByteArray(v.size) { v[it].toByte() }

    /// 16 bitmap bytes: the four the header quotes, then zeros. Bits set:
    /// 0x56 → 1,2,4,6 · 0xfe → 9..15 · 0x87 → 16,17,18,23 · 0x49 → 24,27,30.
    private val bitmapHex = "56fe8749" + "00".repeat(12)

    private val bitmapBitsExpected =
        listOf(1, 2, 4, 6, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 23, 24, 27, 30)

    /// The 21-byte overflow AD, reused by most fixtures.
    /// 0x14 = 20 = 1 type + 2 company + 1 Apple type + 16 bitmap.
    private val overflowAdHex = "14ff4c00" + "01" + bitmapHex

    /// F1. Flags · a 3-byte Apple Nearby Info AD · the overflow AD.
    /// 3 + 7 + 21 = 31 bytes = exactly the legacy AdvData cap, so this one is
    /// emittable by a real iPhone. Overflow type byte at blob offset 3.
    private val LEGACY_LEGAL = hex("02011a" + "06ff4c00" + "10010b" + overflowAdHex)

    /// F2. The composite AdvertParser.kt's header works through: Flags ·
    /// TX Power · an 11-byte Apple AD (Nearby Action 0x0F len 5, then Nearby
    /// Info 0x10 len 2) · the overflow AD. Overflow type byte at blob offset
    /// 11 under merge semantics, 0 under last-wins.
    ///
    /// The header's `0f 05 …` elides four bytes; the `10 02 0b 1c` tail below
    /// is synthesised to fill the documented 11-byte payload, which is what
    /// fixes the offset at 11.
    private val BRIEF_COMPOSITE = hex(
        "02011a" + "020a0c" +
            "0eff4c00" + "0f05a1a2a3a4a5" + "10020b1c" +
            overflowAdHex
    )

    /// F3. Three Apple ADs with payloads of 4, 6 and 17 bytes. Overflow type
    /// byte lands at 4 + 6 = 10 — a third value, which is the point.
    private val THREE_APPLE_ADS = hex(
        "02011a" +
            "07ff4c00" + "0f02aabb" +
            "09ff4c00" + "1004c1c2c3c4" +
            overflowAdHex
    )

    /// F4. The inversion of F2: the overflow AD comes *first*, so merge
    /// semantics put 0x01 at blob offset 0 and last-wins semantics drop the
    /// overflow AD out of the blob entirely.
    private val OVERFLOW_FIRST = hex("02011a" + overflowAdHex + "07ff4c00" + "0f02aabb")

    /// F5. Two Apple ADs where the overflow TLV is inside the *last* AD but
    /// not at its start, so lastWinsOffset is non-null and differs from both 0
    /// and blobOffset. Guards against a parser that conflates the two.
    private val OVERFLOW_MID_LAST_AD = hex(
        "02011a" +
            "05ff4c00" + "0f00" +
            "17ff4c00" + "10010b" + "01" + bitmapHex
    )

    /// F6. A non-Apple manufacturer AD (Nordic, 0x0059) ahead of the Apple
    /// overflow AD — D5's second consequence, where the plugin's single map
    /// entry is keyed 0x0059 and `manufacturerData[0x004C]` is null in Dart.
    private val NORDIC_FIRST = hex("02011a" + "05ff5900aabb" + overflowAdHex)

    /// F7. Real capture (Young, iPhone 6 / iOS 11). Bit 83, nothing else.
    private val YOUNG_CAPTURE = hex(
        "02011a" + "14ff4c00" + "01" + "00000000000000000000" + "08" + "0000000000"
    )

    /// F8. Handoff (0x0C) + Tethering Source (0x0D) — the two types
    /// TRACKING_SENSITIVE_APPLE_TYPES redacts out of summarize().
    private val TRACKING_SENSITIVE = hex("02011a" + "0bff4c00" + "0c02aabb" + "0d02ccdd")

    // ── The fixtures' own bookkeeping ──────────────────────────────────
    //
    // A fixture with a miscounted length byte would make every offset
    // assertion below vacuously "pass" against a differently-wrong parser, so
    // the sizes are asserted first.

    @Test
    fun fixtureSizes() {
        assertEquals("3 flags + 7 Apple + 21 overflow", 31, LEGACY_LEGAL.size)
        assertEquals("3 + 3 + 15 + 21", 42, BRIEF_COMPOSITE.size)
        assertEquals("3 + 8 + 10 + 21", 42, THREE_APPLE_ADS.size)
        assertEquals("3 + 21 + 8", 32, OVERFLOW_FIRST.size)
        assertEquals("3 + 6 + 24", 33, OVERFLOW_MID_LAST_AD.size)
        assertEquals("3 + 6 + 21", 30, NORDIC_FIRST.size)
        assertEquals(24, YOUNG_CAPTURE.size)
        assertEquals(21, hex(overflowAdHex).size)
    }

    /// The documented composite cannot occur in a legacy ADV_IND: legacy
    /// AdvData is capped at 31 bytes and this is 42. Recorded as an assertion
    /// rather than a comment so nobody later cites "offset 11" as an observed
    /// on-air value. LEGACY_LEGAL is the on-air-shaped version of the same
    /// bug, and it fits in 31 exactly.
    @Test
    fun briefCompositeExceedsTheLegacyAdvDataCap() {
        assertTrue("42 > 31", BRIEF_COMPOSITE.size > 31)
        assertEquals("legacy cap, to the byte", 31, LEGACY_LEGAL.size)
    }

    // ── D5/D3: the multi-AD fixture, both AOSP collapse semantics ──────

    @Test
    fun compositeWalksToFourAdStructures() {
        val ads = AdvertParser.parseAdStructures(BRIEF_COMPOSITE)
        assertEquals(4, ads.size)
        assertEquals(listOf(0x01, 0x0A, 0xFF, 0xFF), ads.map { it.type })
        // offset is the index of payload[0] in the raw record — the field that
        // makes D3's arithmetic possible at all.
        assertEquals(listOf(2, 5, 8, 23), ads.map { it.offset })
        assertEquals(listOf(1, 1, 13, 19), ads.map { it.payload.size })
        assertFalse(ads.any { it.truncated })
    }

    /// Duplicate company ids survive as separate entries. This is precisely
    /// what the plugin destroys and AOSP's ScanRecord collapses.
    @Test
    fun compositeKeepsBothAppleAdsSeparate() {
        val mfg = AdvertParser.manufacturerAds(BRIEF_COMPOSITE)
        assertEquals(2, mfg.size)
        assertEquals(listOf(AdvertParser.COMPANY_APPLE, AdvertParser.COMPANY_APPLE),
            mfg.map { it.companyId })
        assertEquals("Apple AD #0 data starts at record byte 10", 10, mfg[0].recordOffset)
        assertEquals(11, mfg[0].data.size)
        assertEquals("Apple AD #1 data starts at record byte 25", 25, mfg[1].recordOffset)
        assertEquals(17, mfg[1].data.size)
    }

    /// Android 15/16: concatenate in PDU order. The blob is AD#0 ++ AD#1, so
    /// byte 0 is Nearby Action's 0x0F and the overflow marker is at 11.
    @Test
    fun mergeSemanticsPutNearbyActionAtOffsetZero() {
        val blob = AdvertParser.companyBlob(BRIEF_COMPOSITE, AdvertParser.COMPANY_APPLE, merge = true)
        assertNotNull(blob)
        assertEquals(11 + 17, blob!!.size)
        assertEquals(0x0F, blob[0].toInt() and 0xFF)
        assertEquals(0x01, blob[11].toInt() and 0xFF)
    }

    /// Android 10-14: overwrite, last AD wins. The blob *is* AD#1, so 0x01 is
    /// at byte 0 — the offsets are inverted across the 14→15 boundary.
    @Test
    fun lastWinsSemanticsPutOverflowAtOffsetZero() {
        val blob = AdvertParser.companyBlob(BRIEF_COMPOSITE, AdvertParser.COMPANY_APPLE, merge = false)
        assertNotNull(blob)
        assertEquals(17, blob!!.size)
        assertEquals(0x01, blob[0].toInt() and 0xFF)
    }

    /// The two numbers the whole file is for.
    @Test
    fun compositeOverflowOffsetsAre11AndZero() {
        val ad = AdvertParser.overflowAd(BRIEF_COMPOSITE)
        assertNotNull(ad)
        assertEquals("merge (Android 15+): sum of preceding Apple payloads", 11, ad!!.blobOffset)
        assertEquals("last-wins (Android <=14)", 0, ad.lastWinsOffset)
        assertEquals(12, ad.payloadBlobOffset)
        assertEquals(1, ad.adIndex)
        assertFalse(ad.truncated)
    }

    /// The consequence for the filter that is live in the shipped build,
    /// MsdFilter(0x004C, data:[0x01], mask:[0xFF]) — beacon_service.dart:912.
    /// Same packet, same filter, opposite outcome by OS version.
    @Test
    fun theLiveMsdFilterMatchesOnAndroid14AndMissesOnAndroid15() {
        val lastWins =
            AdvertParser.companyBlob(BRIEF_COMPOSITE, AdvertParser.COMPANY_APPLE, merge = false)!!
        val merged =
            AdvertParser.companyBlob(BRIEF_COMPOSITE, AdvertParser.COMPANY_APPLE, merge = true)!!
        assertEquals("<=14: data[0]==0x01, filter matches", 0x01, lastWins[0].toInt() and 0xFF)
        assertTrue("15+: data[0]!=0x01, filter MISSES this iPhone", (merged[0].toInt() and 0xFF) != 0x01)
    }

    /// F4 inverts F2: put the overflow AD first and the verdicts swap. Under
    /// last-wins the overflow AD is not in the blob at all, so Android <=14
    /// cannot filter on it — which is what a null lastWinsOffset means.
    @Test
    fun overflowFirstInvertsBothVerdicts() {
        val ad = AdvertParser.overflowAd(OVERFLOW_FIRST)
        assertNotNull(ad)
        assertEquals(0, ad!!.blobOffset)
        assertNull("not in the last Apple AD → unfilterable on <=14", ad.lastWinsOffset)
        assertEquals(0, ad.adIndex)

        val merged = AdvertParser.companyBlob(OVERFLOW_FIRST, AdvertParser.COMPANY_APPLE, merge = true)!!
        val lastWins = AdvertParser.companyBlob(OVERFLOW_FIRST, AdvertParser.COMPANY_APPLE, merge = false)!!
        assertEquals("15+: filter matches", 0x01, merged[0].toInt() and 0xFF)
        assertEquals("<=14: blob is the trailing Apple AD, filter misses", 0x0F, lastWins[0].toInt() and 0xFF)
        assertEquals(4, lastWins.size)
    }

    // ── D3: the offset is a sum, not a magic number ────────────────────

    /// Three fixtures, three offsets, one rule: blobOffset == the sum of the
    /// payload lengths of every preceding Apple AD. A parser that hardcodes
    /// {0, 11} passes the composite test above and fails here.
    @Test
    fun overflowBlobOffsetIsTheSumOfPrecedingApplePayloads() {
        data class Case(val name: String, val record: ByteArray, val expected: Int)
        val cases = listOf(
            Case("LEGACY_LEGAL: one 3-byte Apple AD ahead of it", LEGACY_LEGAL, 3),
            Case("THREE_APPLE_ADS: 4 + 6", THREE_APPLE_ADS, 10),
            Case("BRIEF_COMPOSITE: 11", BRIEF_COMPOSITE, 11),
            Case("OVERFLOW_FIRST: nothing ahead of it", OVERFLOW_FIRST, 0),
            Case("OVERFLOW_MID_LAST_AD: 2 ahead of it, +3 inside its own AD", OVERFLOW_MID_LAST_AD, 5),
        )
        for (c in cases) {
            val apple = AdvertParser.manufacturerAds(c.record)
                .filter { it.companyId == AdvertParser.COMPANY_APPLE }
            val ad = AdvertParser.overflowAd(c.record)
            assertNotNull(c.name, ad)
            assertEquals(c.name, c.expected, ad!!.blobOffset)
            // Recompute the same number from the AD payload lengths, which is
            // the rule AdvertParser.kt states in prose. When the overflow TLV
            // is in the last Apple AD, lastWinsOffset *is* its offset within
            // that AD, so the two offsets and the AD sizes must be mutually
            // consistent: blobOffset == preceding payload bytes + in-AD offset.
            val precedingBytes = apple.take(ad.adIndex).sumOf { it.data.size }
            val inAd = ad.lastWinsOffset
            if (inAd != null) {
                assertEquals("${c.name}: sum(preceding) + in-AD offset",
                    precedingBytes + inAd, ad.blobOffset)
            } else {
                assertEquals("${c.name}: not the last Apple AD, so <=14 cannot filter at all",
                    0, precedingBytes)
            }
            assertEquals("${c.name}: payload sits one byte after the type byte",
                ad.blobOffset + 1, ad.payloadBlobOffset)
        }
        // All five distinct? Three distinct non-zero values is the claim.
        assertEquals(listOf(0, 3, 5, 10, 11),
            cases.map { AdvertParser.overflowAd(it.record)!!.blobOffset }.sorted())
    }

    @Test
    fun legacyLegalPacketOffsetsAreThreeAndZero() {
        val ad = AdvertParser.overflowAd(LEGACY_LEGAL)!!
        assertEquals(3, ad.blobOffset)
        assertEquals(4, ad.payloadBlobOffset)
        assertEquals("last Apple AD, and 0x01 is its first byte", 0, ad.lastWinsOffset)
        assertEquals(1, ad.adIndex)
        // The Nearby Info AD ahead of it is why apple[0] != 0x01 under merge.
        val merged = AdvertParser.companyBlob(LEGACY_LEGAL, AdvertParser.COMPANY_APPLE, merge = true)!!
        assertEquals(0x10, merged[0].toInt() and 0xFF)
        assertEquals(20, merged.size)
    }

    @Test
    fun threeAppleAdsOffsets() {
        val apple = AdvertParser.appleAds(THREE_APPLE_ADS)
        assertEquals(listOf(0x0F, 0x10, 0x01), apple.map { it.type })
        assertEquals(listOf(0, 4, 10), apple.map { it.blobOffset })
        assertEquals(listOf(0, 1, 2), apple.map { it.adIndex })
        assertEquals(listOf(null, null, 0), apple.map { it.lastWinsOffset })
        val merged = AdvertParser.companyBlob(THREE_APPLE_ADS, AdvertParser.COMPANY_APPLE, merge = true)!!
        assertEquals(4 + 6 + 17, merged.size)
        assertEquals(0x01, merged[10].toInt() and 0xFF)
    }

    /// lastWinsOffset is an offset *within the last Apple AD*, not a synonym
    /// for 0 and not a synonym for blobOffset. Here it is 3, blobOffset is 5.
    @Test
    fun lastWinsOffsetIsIndependentOfBlobOffset() {
        val ad = AdvertParser.overflowAd(OVERFLOW_MID_LAST_AD)!!
        assertEquals(5, ad.blobOffset)
        assertEquals(3, ad.lastWinsOffset)
        assertEquals(1, ad.adIndex)
        val lastWins =
            AdvertParser.companyBlob(OVERFLOW_MID_LAST_AD, AdvertParser.COMPANY_APPLE, merge = false)!!
        assertEquals(20, lastWins.size)
        assertEquals("<=14 must filter at index 3, not 0", 0x01, lastWins[3].toInt() and 0xFF)
    }

    @Test
    fun compositeAppleTlvsAreAllReturnedInOrder() {
        val apple = AdvertParser.appleAds(BRIEF_COMPOSITE)
        assertEquals(3, apple.size)

        assertEquals(AdvertParser.APPLE_NEARBY_ACTION, apple[0].type)
        assertEquals(5, apple[0].declaredLength)
        assertEquals(0, apple[0].blobOffset)
        assertEquals(2, apple[0].payloadBlobOffset)
        assertNull(apple[0].lastWinsOffset)
        assertArrayEquals(b(0xA1, 0xA2, 0xA3, 0xA4, 0xA5), apple[0].value)

        assertEquals(AdvertParser.APPLE_NEARBY_INFO, apple[1].type)
        assertEquals(2, apple[1].declaredLength)
        assertEquals(7, apple[1].blobOffset)
        assertEquals(0, apple[1].adIndex)
        assertArrayEquals(b(0x0B, 0x1C), apple[1].value)

        assertEquals(AdvertParser.APPLE_OVERFLOW_AREA, apple[2].type)
        assertEquals(11, apple[2].blobOffset)
    }

    // ── The overflow AD has no inner length byte ───────────────────────

    /// `[0x01][16 bytes]`, not `[type][len][value]`. A parser that assumed a
    /// length byte would read declaredLength = 0x56 from this fixture and try
    /// to consume 86 bytes, yielding a truncated 15-byte value. Assert the
    /// arithmetic that proves it instead: 0x14 = 20 = 1 + 2 + 1 + 16.
    @Test
    fun overflowAreaCarriesNoInnerLengthByte() {
        val ad = AdvertParser.overflowAd(BRIEF_COMPOSITE)!!
        assertNull("no inner length byte exists to report", ad.declaredLength)
        assertEquals(AdvertParser.OVERFLOW_BITMAP_LEN, ad.value.size)
        assertEquals(16, ad.value.size)
        assertFalse("a [type][len][value] reading would truncate here", ad.truncated)
        assertEquals("value starts one byte after the type byte, not two",
            1, ad.payloadBlobOffset - ad.blobOffset)

        // The declared AD length is the proof: 0x14 == 1 type + 2 company +
        // 1 Apple type + 16 bitmap. A length byte would make it 0x15.
        assertEquals(0x14, BRIEF_COMPOSITE[21].toInt() and 0xFF)
        assertEquals(0x14, 1 + 2 + 1 + AdvertParser.OVERFLOW_BITMAP_LEN)

        // What a wrong parser would have believed.
        assertEquals("the byte a length-assuming parser would take as a length",
            0x56, ad.value[0].toInt() and 0xFF)
    }

    /// Bitmap byte k sits at payload index k + 1 inside the Apple TLV, and
    /// therefore at company-blob index lastWinsOffset + 1 + k. Cross-checked
    /// against finding D1's published ScanFilter for bit 36,
    /// data = 01 00 00 00 00 10 …, i.e. bitmap byte 4 at data index 5.
    @Test
    fun bitmapByteKSitsAtPayloadIndexKPlusOne() {
        val ad = AdvertParser.overflowAd(YOUNG_CAPTURE)!!
        val blob = AdvertParser.companyBlob(YOUNG_CAPTURE, AdvertParser.COMPANY_APPLE, merge = false)!!
        assertEquals(0, ad.lastWinsOffset)
        for (k in 0 until AdvertParser.OVERFLOW_BITMAP_LEN) {
            assertEquals("bitmap byte $k", ad.value[k], blob[ad.lastWinsOffset!! + 1 + k])
        }
        // D1's worked example, reassembled from the helpers.
        assertEquals(4, AdvertParser.bitmapByteForBit(36))
        assertEquals(0x10, AdvertParser.bitmapMaskForBit(36))
        assertEquals("ScanFilter data index for bit 36 in this packet",
            5, ad.payloadBlobOffset + AdvertParser.bitmapByteForBit(36))
    }

    // ── D5 consequence 2: a non-Apple AD first hides Apple entirely ────

    /// With Nordic's 0x0059 AD ahead of the Apple one, the plugin stores a
    /// single map entry keyed 0x0059, so Dart's `manufacturerData[0x004C]`
    /// comes back **null** and the peer is dropped before any byte test runs.
    /// The native parser still sees both companies and still finds the
    /// overflow AD.
    @Test
    fun nonApplePriorAdMakesTheAppleMapEntryVanish() {
        val plugin = AdvertParser.emulateFlutterBluePlusMsd(NORDIC_FIRST)
        assertNotNull(plugin)
        assertEquals("the plugin keys the entry on the FIRST company id",
            0x0059, plugin!!["companyId"])
        assertTrue("manufacturerData[0x004C] is therefore null in Dart",
            plugin["companyId"] != AdvertParser.COMPANY_APPLE)

        val mfg = AdvertParser.manufacturerAds(NORDIC_FIRST)
        assertEquals(listOf(0x0059, AdvertParser.COMPANY_APPLE), mfg.map { it.companyId })
        assertArrayEquals(b(0xAA, 0xBB), mfg[0].data)
        assertEquals(17, mfg[1].data.size)

        val ad = AdvertParser.overflowAd(NORDIC_FIRST)
        assertNotNull("native still finds it", ad)
        assertEquals(0, ad!!.blobOffset)
        assertEquals(0, ad.lastWinsOffset)

        assertNull("a company that is not present", AdvertParser.companyBlob(NORDIC_FIRST, 0x0001, merge = true))
        assertEquals(2, AdvertParser.companyBlob(NORDIC_FIRST, 0x0059, merge = true)!!.size)
    }

    // ── emulateFlutterBluePlusMsd: what Dart is being told today ───────

    /// The three observable fields of the plugin's single map entry for the
    /// multi-AD packet. `firstByte == 0x0F` is the D5 bug in one number: the
    /// live Dart test is `apple[0] == 0x01`, so this peer is delivered by the
    /// radio and then discarded. Comparing these two fields across a walk is
    /// what turns "probably breaking detection" into a count.
    @Test
    fun pluginReportsAppleWithTheWrongFirstByteForTheComposite() {
        val plugin = AdvertParser.emulateFlutterBluePlusMsd(BRIEF_COMPOSITE)!!
        assertEquals(AdvertParser.COMPANY_APPLE, plugin["companyId"])
        assertEquals("13 + 19 glued, minus the 2 company bytes it strips",
            30, plugin["payloadLen"])
        assertEquals("apple[0] == 0x01 is FALSE for this iPhone", 0x0F, plugin["firstByte"])
    }

    @Test
    fun pluginReportsTheWrongFirstByteForTheLegacyLegalPacketToo() {
        val plugin = AdvertParser.emulateFlutterBluePlusMsd(LEGACY_LEGAL)!!
        assertEquals(AdvertParser.COMPANY_APPLE, plugin["companyId"])
        assertEquals(22, plugin["payloadLen"])
        assertEquals(0x10, plugin["firstByte"])
    }

    /// The single-Apple-AD case, where the plugin is right. Without this the
    /// suite would not distinguish "the plugin is broken" from "the plugin is
    /// broken *when there is more than one Apple AD*", which is the actual
    /// claim and the reason the bug survived to production.
    @Test
    fun pluginIsCorrectWhenThereIsExactlyOneAppleAd() {
        val plugin = AdvertParser.emulateFlutterBluePlusMsd(YOUNG_CAPTURE)!!
        assertEquals(AdvertParser.COMPANY_APPLE, plugin["companyId"])
        assertEquals(17, plugin["payloadLen"])
        assertEquals(0x01, plugin["firstByte"])
    }

    @Test
    fun pluginReportsNothingWhenThereIsNoManufacturerAd() {
        assertNull(AdvertParser.emulateFlutterBluePlusMsd(hex("02011a020a0c")))
        assertNull(AdvertParser.emulateFlutterBluePlusMsd(ByteArray(0)))
        assertNull(AdvertParser.emulateFlutterBluePlusMsd(null))
    }

    /// The plugin's guard is `fieldLen >= 2`, i.e. one payload byte, so two
    /// one-byte manufacturer ADs let it fabricate a company id that appears in
    /// neither of them: 0xAA from the first, 0xBB from the second → 0xBBAA.
    /// The native parser drops both, because neither carries a complete id.
    @Test
    fun pluginFabricatesACompanyIdFromTwoOneByteAds() {
        val record = hex("02011a" + "02ffaa" + "02ffbb")
        val plugin = AdvertParser.emulateFlutterBluePlusMsd(record)!!
        assertEquals("a company id present nowhere in the PDU", 0xBBAA, plugin["companyId"])
        assertEquals(0, plugin["payloadLen"])
        assertNull(plugin["firstByte"])

        assertTrue("native drops <2-byte manufacturer ADs",
            AdvertParser.manufacturerAds(record).isEmpty())
        assertEquals("but the AD structures are still all there",
            3, AdvertParser.parseAdStructures(record).size)
    }

    // ── Hostile and malformed input ────────────────────────────────────

    @Test
    fun nullAndEmptyRecords() {
        assertTrue(AdvertParser.parseAdStructures(null).isEmpty())
        assertTrue(AdvertParser.parseAdStructures(ByteArray(0)).isEmpty())
        assertTrue(AdvertParser.manufacturerAds(null).isEmpty())
        assertTrue(AdvertParser.appleAds(null).isEmpty())
        assertNull(AdvertParser.overflowAd(null))
        assertNull(AdvertParser.companyBlob(null, AdvertParser.COMPANY_APPLE, merge = true))
        assertNull(AdvertParser.nearbyInfoActionCode(null))
        assertEquals(0, AdvertParser.summarize(null)["recordLen"])
        assertEquals(0, AdvertParser.summarize(ByteArray(0))["adCount"])
    }

    @Test
    fun zeroLengthTerminatorStopsTheWalk() {
        val ads = AdvertParser.parseAdStructures(hex("02011a" + "000000"))
        assertEquals(1, ads.size)
        assertEquals(0x01, ads[0].type)
        assertFalse(ads[0].truncated)
    }

    /// Legacy AdvData is a fixed 31-byte field, so a shorter advert arrives
    /// zero-padded. That padding is normal and must not be reported as
    /// malformed — an OEM stack that hands over the full 31 bytes and one that
    /// trims must produce identical results.
    @Test
    fun thirtyOneByteZeroPaddedLegacyRecordIsNotCorruption() {
        val padded = ByteArray(31)
        YOUNG_CAPTURE.copyInto(padded)
        assertEquals(31, padded.size)

        val trimmed = AdvertParser.summarize(YOUNG_CAPTURE)
        val full = AdvertParser.summarize(padded)
        assertEquals(2, full["adCount"])
        assertEquals(false, full["malformed"])
        assertEquals(trimmed["appleTypes"], full["appleTypes"])
        assertEquals(trimmed["overflowBlobOffset"], full["overflowBlobOffset"])
        assertEquals(trimmed["overflowLastWinsOffset"], full["overflowLastWinsOffset"])
        assertEquals(trimmed["overflowBits"], full["overflowBits"])
        assertArrayEquals(
            AdvertParser.overflowAd(YOUNG_CAPTURE)!!.value,
            AdvertParser.overflowAd(padded)!!.value,
        )
        // The one field that legitimately differs.
        assertEquals(24, trimmed["recordLen"])
        assertEquals(31, full["recordLen"])
    }

    /// A declared length past the end of the buffer: keep what parsed, flag
    /// it, stop. AOSP's own parseFromBytes() catches the
    /// ArrayIndexOutOfBounds and throws the *whole* record away.
    @Test
    fun lengthOverrunningTheBufferIsTruncatedNotThrown() {
        val record = hex("02011a" + "05ff4c00")   // declares 4 payload bytes, has 2
        val ads = AdvertParser.parseAdStructures(record)
        assertEquals(2, ads.size)
        assertEquals(0xFF, ads[1].type)
        assertTrue(ads[1].truncated)
        assertArrayEquals(b(0x4C, 0x00), ads[1].payload)

        val mfg = AdvertParser.manufacturerAds(record)
        assertEquals(1, mfg.size)
        assertEquals(AdvertParser.COMPANY_APPLE, mfg[0].companyId)
        assertEquals("company id complete, no payload after it", 0, mfg[0].data.size)
        assertTrue(mfg[0].truncated)
        assertTrue(AdvertParser.appleAds(record).isEmpty())
        assertEquals(true, AdvertParser.summarize(record)["malformed"])
    }

    /// `length == 1` is a legal AD: type byte, zero payload. The walk must
    /// keep going past it — it advances 2, which is why the loop cannot spin.
    @Test
    fun lengthOneIsAnEmptyPayloadNotAnError() {
        val ads = AdvertParser.parseAdStructures(hex("0109" + "02011a"))
        assertEquals(2, ads.size)
        assertEquals(0x09, ads[0].type)
        assertEquals(0, ads[0].payload.size)
        assertEquals(2, ads[0].offset)
        assertFalse(ads[0].truncated)
        assertEquals(0x01, ads[1].type)
        assertEquals(4, ads[1].offset)
    }

    /// A length byte with nothing after it — the last byte of the buffer.
    /// Distinct from `length == 1`, which the brief for this work conflated.
    @Test
    fun trailingLoneLengthByteStopsTheWalk() {
        val ads = AdvertParser.parseAdStructures(hex("02011a" + "05"))
        assertEquals(1, ads.size)
        assertEquals(0x01, ads[0].type)
        assertFalse("nothing was half-read", ads[0].truncated)
    }

    @Test
    fun truncatedTrailingAppleTlv() {
        // Apple data = [0x0F, 0x05]: declares a 5-byte value, has none.
        val record = hex("02011a" + "05ff4c00" + "0f05")
        val apple = AdvertParser.appleAds(record)
        assertEquals(1, apple.size)
        assertEquals(AdvertParser.APPLE_NEARBY_ACTION, apple[0].type)
        assertEquals(5, apple[0].declaredLength)
        assertEquals(0, apple[0].value.size)
        assertTrue(apple[0].truncated)
        assertEquals(true, AdvertParser.summarize(record)["malformed"])
    }

    @Test
    fun appleTypeByteWithNoLengthByte() {
        // Apple data = [0x0F] and nothing else.
        val record = hex("02011a" + "04ff4c00" + "0f")
        val apple = AdvertParser.appleAds(record)
        assertEquals(1, apple.size)
        assertEquals(AdvertParser.APPLE_NEARBY_ACTION, apple[0].type)
        assertNull(apple[0].declaredLength)
        assertEquals(0, apple[0].value.size)
        assertTrue(apple[0].truncated)
        assertEquals(0, apple[0].blobOffset)
        assertEquals(1, apple[0].payloadBlobOffset)
    }

    @Test
    fun truncatedOverflowBitmap() {
        // 15 bitmap bytes where 16 are required. The AD itself is consistent;
        // only the Apple TLV inside it is short, which is a different failure
        // from lengthOverrunningTheBufferIsTruncatedNotThrown above.
        val record = hex("13ff4c00" + "01" + "00".repeat(15))
        assertEquals(20, record.size)
        val ads = AdvertParser.parseAdStructures(record)
        assertEquals(1, ads.size)
        assertFalse("the AD structure is well-formed", ads[0].truncated)

        val ad = AdvertParser.overflowAd(record)!!
        assertEquals(15, ad.value.size)
        assertTrue(ad.truncated)
        assertEquals(true, AdvertParser.summarize(record)["malformed"])
        assertEquals(15, AdvertParser.summarize(record)["overflowBitmapLen"])
    }

    /// A run of 0x00 at the tail of an over-declared Apple AD is padding, not
    /// a type-0x00 TLV. But a *non-zero* tail after a 0x00 is parsed rather
    /// than swallowed, so this shortcut cannot hide a future Apple type.
    @Test
    fun appleZeroPaddingStopsTheTlvWalkButANonZeroTailDoesNot() {
        val padded = hex("02011a" + "09ff4c00" + "0f02aabb" + "0000")
        val paddedTlvs = AdvertParser.appleAds(padded)
        assertEquals(1, paddedTlvs.size)
        assertEquals(AdvertParser.APPLE_NEARBY_ACTION, paddedTlvs[0].type)
        assertEquals(false, AdvertParser.summarize(padded)["malformed"])

        val tailed = hex("02011a" + "0aff4c00" + "0f02aabb" + "000177")
        val tailedTlvs = AdvertParser.appleAds(tailed)
        assertEquals(2, tailedTlvs.size)
        assertEquals(0x00, tailedTlvs[1].type)
        assertEquals(1, tailedTlvs[1].declaredLength)
        assertArrayEquals(b(0x77), tailedTlvs[1].value)
        assertEquals(4, tailedTlvs[1].blobOffset)
    }

    /// Every byte pattern up to 4 bytes long must parse without throwing.
    /// The walker is fed strangers' radios; an escaping exception on the
    /// ScanCallback thread is a process kill (AdvertScanner.emit catches, but
    /// that is the backstop, not the contract).
    @Test
    fun exhaustiveShortInputsNeverThrow() {
        var count = 0
        for (first in 0..255) {
            for (second in 0..255) {
                val r = b(first, second)
                AdvertParser.summarize(r)
                AdvertParser.emulateFlutterBluePlusMsd(r)
                count++
            }
        }
        assertEquals(65536, count)
        // 3- and 4-byte probes around the interesting length values, including
        // a declared length of 0xFF against a 4-byte buffer.
        for (len in intArrayOf(0, 1, 2, 3, 0xFE, 0xFF)) {
            for (type in intArrayOf(0x00, 0x01, 0xFF)) {
                AdvertParser.summarize(b(len, type, 0x4C, 0x00))
                AdvertParser.summarize(b(len, type, 0x4C))
                AdvertParser.emulateFlutterBluePlusMsd(b(len, type, 0x4C, 0x00))
            }
        }
    }

    // ── Bitmap helpers ────────────────────────────────────────────────

    /// LSB-first within each byte: bit p is byte p/8, mask 1 shl (p%8).
    /// Getting this endianness backwards is the failure mode that makes a
    /// hardware filter silently match nothing.
    @Test
    fun bitmapBitsAreLsbFirstWithinEachByte() {
        val bitmap = ByteArray(16)
        bitmap[0] = 0x01
        assertEquals(listOf(0), AdvertParser.bitmapBits(bitmap))
        bitmap[0] = 0x80.toByte()
        assertEquals(listOf(7), AdvertParser.bitmapBits(bitmap))
        bitmap[0] = 0
        bitmap[4] = 0x10                       // finding D1's bit 36
        assertEquals(listOf(36), AdvertParser.bitmapBits(bitmap))
        bitmap[4] = 0
        bitmap[10] = 0x08                      // Young's captured bit 83
        assertEquals(listOf(83), AdvertParser.bitmapBits(bitmap))
        bitmap[10] = 0
        bitmap[8] = 0x20                       // Apple Watch, bit 69
        assertEquals(listOf(69), AdvertParser.bitmapBits(bitmap))
    }

    @Test
    fun everyBitPositionRoundTrips() {
        for (bit in 0..127) {
            val bitmap = ByteArray(16)
            val idx = AdvertParser.bitmapByteForBit(bit)
            bitmap[idx] = (bitmap[idx].toInt() or AdvertParser.bitmapMaskForBit(bit)).toByte()
            assertEquals("bit $bit", listOf(bit), AdvertParser.bitmapBits(bitmap))
            assertTrue("bit $bit must land inside the 16-byte bitmap", idx in 0..15)
            assertTrue("bit $bit mask is a single bit",
                Integer.bitCount(AdvertParser.bitmapMaskForBit(bit)) == 1)
        }
        // No two positions collide on the same (byte, mask) pair — 128 bits,
        // 128 distinct slots.
        val slots = (0..127).map { AdvertParser.bitmapByteForBit(it) * 256 + AdvertParser.bitmapMaskForBit(it) }
        assertEquals(128, slots.toSet().size)
    }

    @Test
    fun multipleBitsComeBackAscending() {
        assertEquals(bitmapBitsExpected, AdvertParser.bitmapBits(hex(bitmapHex)))
        assertEquals(18, bitmapBitsExpected.size)
        assertEquals(listOf(83), AdvertParser.bitmapBits(AdvertParser.overflowAd(YOUNG_CAPTURE)!!.value))
    }

    /// A backgrounded iPhone advertising no service UUIDs sets no bits. That
    /// is decisive, not ambiguous: it is provably not one of our peers, so the
    /// GATT keepalive must not be spent on it.
    @Test
    fun allZeroBitmapIsAnAnswerNotAnAbsence() {
        val zeros = ByteArray(16)
        assertTrue(AdvertParser.bitmapBits(zeros).isEmpty())
        assertTrue(AdvertParser.isAllZero(zeros))
        assertTrue(AdvertParser.isAllZero(ByteArray(0)))
        assertFalse(AdvertParser.isAllZero(b(0, 0, 1)))
        assertTrue(AdvertParser.bitmapBits(null).isEmpty())

        val record = hex("14ff4c0001" + "00".repeat(16))
        val s = AdvertParser.summarize(record)
        assertEquals(true, s["isOverflow"])
        assertEquals("all-zero, and we know it", true, s["overflowAllZero"])
        assertEquals(emptyList<Int>(), s["overflowBits"])
        assertEquals(16, s["overflowBitmapLen"])

        // Contrast: no overflow AD at all is a *different* state, and null is
        // how it is reported. Dart must not collapse the two.
        val none = AdvertParser.summarize(hex("02011a"))
        assertEquals(false, none["isOverflow"])
        assertNull(none["overflowAllZero"])
        assertNull(none["overflowBlobOffset"])
    }

    // ── Nearby Info action code (W7's wake-cost oracle) ────────────────

    @Test
    fun nearbyInfoActionCodeIsTheLowNibbleOfByteZero() {
        assertEquals(0x0B, AdvertParser.nearbyInfoActionCode(BRIEF_COMPOSITE))
        assertEquals(0x0B, AdvertParser.nearbyInfoActionCode(LEGACY_LEGAL))
        assertEquals(0x0B, AdvertParser.summarize(BRIEF_COMPOSITE)["nearbyInfoActionCode"])
        assertEquals(0x0B, AdvertParser.summarize(BRIEF_COMPOSITE)["nearbyInfoByte0"])
        // High nibble is status, not action, and must not leak in: 0x53 → 3.
        assertEquals(0x03, AdvertParser.nearbyInfoActionCode(hex("06ff4c00" + "1001" + "53")))
        assertEquals(0x53, AdvertParser.summarize(hex("06ff4c00" + "1001" + "53"))["nearbyInfoByte0"])
        assertNull("no 0x10 TLV", AdvertParser.nearbyInfoActionCode(YOUNG_CAPTURE))
        assertNull("0x10 declaring a zero-length value",
            AdvertParser.nearbyInfoActionCode(hex("05ff4c00" + "1000")))
        assertNull("0x10 with no length byte at all",
            AdvertParser.nearbyInfoActionCode(hex("04ff4c00" + "10")))
    }

    // ── summarize(): the channel-ready view ───────────────────────────

    @Test
    fun summarizeCompositeCarriesTheWholeD5AndD3Story() {
        val s = AdvertParser.summarize(BRIEF_COMPOSITE)
        assertEquals(42, s["recordLen"])
        assertEquals(4, s["adCount"])
        assertEquals(false, s["malformed"])
        assertEquals("PDU order, duplicates preserved — the D5 evidence",
            listOf(0x004C, 0x004C), s["companyIds"])
        assertEquals(listOf(0x0F, 0x10, 0x01), s["appleTypes"])
        assertEquals(true, s["isOverflow"])
        assertEquals(11, s["overflowBlobOffset"])
        assertEquals(0, s["overflowLastWinsOffset"])
        assertEquals(16, s["overflowBitmapLen"])
        assertEquals(false, s["overflowAllZero"])
        assertEquals(bitmapBitsExpected, s["overflowBits"])
        assertArrayEquals(hex(bitmapHex), s["overflowBitmap"] as ByteArray)

        @Suppress("UNCHECKED_CAST")
        val mfg = s["manufacturer"] as List<Map<String, Any?>>
        assertEquals(2, mfg.size)
        assertEquals(10, mfg[0]["recordOffset"])
        assertEquals(25, mfg[1]["recordOffset"])

        @Suppress("UNCHECKED_CAST")
        val plugin = s["pluginWouldReport"] as Map<String, Any?>
        assertEquals(0x0F, plugin["firstByte"])
    }

    /// The finding-D9 redaction. Handoff (0x0C) carries a sequence number
    /// stable across MAC rotation; Tethering Source (0x0D) carries a 24-hour
    /// stable iCloud account id. Their type, length and offsets are reported —
    /// which is everything a legitimate in-range use needs — and their values
    /// are not.
    @Test
    fun summarizeRedactsTrackingSensitiveApplePayloads() {
        assertEquals(setOf(0x0C, 0x0D), AdvertParser.TRACKING_SENSITIVE_APPLE_TYPES)

        @Suppress("UNCHECKED_CAST")
        val apple = AdvertParser.summarize(TRACKING_SENSITIVE)["apple"] as List<Map<String, Any?>>
        assertEquals(2, apple.size)
        for ((i, entry) in apple.withIndex()) {
            assertNull("type ${entry["type"]} value must not cross the channel", entry["value"])
            assertEquals(2, entry["len"])
            assertEquals(2, entry["declaredLength"])
            assertEquals(i * 4, entry["blobOffset"])
        }
        assertEquals(listOf(0x0C, 0x0D), apple.map { it["type"] })

        // The redaction must hold for the WHOLE map, not just the `apple`
        // list: `manufacturer[].data` carries the same bytes one key over.
        // Walk every ByteArray anywhere in the summary and assert the
        // sensitive payloads appear nowhere.
        val summary = AdvertParser.summarize(TRACKING_SENSITIVE)
        for (bytes in byteArraysIn(summary)) {
            assertFalse(
                "Handoff payload leaked in a ByteArray on the channel",
                containsSubsequence(bytes, b(0xAA, 0xBB)))
            assertFalse(
                "Tethering Source payload leaked in a ByteArray on the channel",
                containsSubsequence(bytes, b(0xCC, 0xDD)))
        }
        // The skeleton survives redaction: type/length bytes intact, values
        // zeroed, size unchanged.
        @Suppress("UNCHECKED_CAST")
        val mfg = summary["manufacturer"] as List<Map<String, Any?>>
        assertArrayEquals(
            b(0x0C, 0x02, 0x00, 0x00, 0x0D, 0x02, 0x00, 0x00),
            mfg[0]["data"] as ByteArray)
        assertEquals(8, mfg[0]["len"])

        // The raw appleAds() layer does NOT redact — redaction is summarize's
        // job, because AdvertScanner.includeRaw deliberately bypasses it for
        // calibration. If that ever changes, this assertion is the tripwire.
        assertArrayEquals(b(0xAA, 0xBB), AdvertParser.appleAds(TRACKING_SENSITIVE)[0].value)
    }

    /// Redaction is surgical: a sensitive TLV sharing an Apple AD with a
    /// benign one loses only its own value bytes, and non-Apple manufacturer
    /// data is untouched.
    @Test
    fun manufacturerDataRedactionIsSurgical() {
        // Nordic AD (aa bb) + one Apple AD holding Handoff(de ad) then
        // Nearby Info(11 ee).
        val mixed = hex("02011a" + "05ff5900aabb" + "0bff4c00" + "0c02dead" + "100211ee")
        assertEquals("3 + 6 + 12", 21, mixed.size)

        val summary = AdvertParser.summarize(mixed)
        @Suppress("UNCHECKED_CAST")
        val mfg = summary["manufacturer"] as List<Map<String, Any?>>
        assertEquals(listOf(0x0059, 0x004C), mfg.map { it["companyId"] })
        // Non-Apple data intact.
        assertArrayEquals(b(0xAA, 0xBB), mfg[0]["data"] as ByteArray)
        // Apple data: Handoff value zeroed, Nearby Info value intact.
        assertArrayEquals(
            b(0x0C, 0x02, 0x00, 0x00, 0x10, 0x02, 0x11, 0xEE),
            mfg[1]["data"] as ByteArray)

        // And the `apple` list agrees with itself: 0x0C null, 0x10 present.
        @Suppress("UNCHECKED_CAST")
        val apple = summary["apple"] as List<Map<String, Any?>>
        assertNull(apple.first { it["type"] == 0x0C }["value"])
        assertArrayEquals(
            b(0x11, 0xEE),
            apple.first { it["type"] == 0x10 }["value"] as ByteArray)
    }

    /// Every ByteArray reachable in a channel map, recursively.
    private fun byteArraysIn(node: Any?): List<ByteArray> = when (node) {
        is ByteArray -> listOf(node)
        is Map<*, *> -> node.values.flatMap { byteArraysIn(it) }
        is List<*> -> node.flatMap { byteArraysIn(it) }
        else -> emptyList()
    }

    private fun containsSubsequence(hay: ByteArray, needle: ByteArray): Boolean {
        if (needle.isEmpty() || hay.size < needle.size) return false
        outer@ for (i in 0..hay.size - needle.size) {
            for (j in needle.indices) if (hay[i + j] != needle[j]) continue@outer
            return true
        }
        return false
    }

    @Test
    fun includeAppleValuesFalseDropsEveryValue() {
        @Suppress("UNCHECKED_CAST")
        val with = AdvertParser.summarize(BRIEF_COMPOSITE, includeAppleValues = true)["apple"]
            as List<Map<String, Any?>>
        @Suppress("UNCHECKED_CAST")
        val without = AdvertParser.summarize(BRIEF_COMPOSITE, includeAppleValues = false)["apple"]
            as List<Map<String, Any?>>
        assertEquals(3, with.size)
        assertEquals(3, without.size)
        assertTrue(with.all { it["value"] != null })
        assertTrue(without.all { it["value"] == null })
        // The skeleton D3 and W7 need survives either way.
        assertEquals(with.map { it["blobOffset"] }, without.map { it["blobOffset"] })
        assertEquals(with.map { it["len"] }, without.map { it["len"] })
        // The bitmap is surfaced separately and is NOT suppressed by this flag.
        assertNotNull(AdvertParser.summarize(BRIEF_COMPOSITE, includeAppleValues = false)["overflowBitmap"])
    }

    // ── Hex helpers (AdvertScanner.classify replays captured hex) ──────

    @Test
    fun parseHexIsLenientAboutSeparators() {
        val expected = b(0x02, 0x01, 0x1A)
        assertArrayEquals(expected, AdvertParser.parseHex("02011a"))
        assertArrayEquals(expected, AdvertParser.parseHex("02:01:1A"))
        assertArrayEquals(expected, AdvertParser.parseHex("02-01-1a"))
        assertArrayEquals(expected, AdvertParser.parseHex("02 01 1a"))
        assertArrayEquals(expected, AdvertParser.parseHex("02\n01\t1a"))
        assertArrayEquals(ByteArray(0), AdvertParser.parseHex(""))
    }

    @Test
    fun parseHexRejectsRatherThanGuesses() {
        assertNull("odd length", AdvertParser.parseHex("02011"))
        assertNull("not hex", AdvertParser.parseHex("02zz"))
        assertNull("one bad nibble in the middle", AdvertParser.parseHex("02 0g 1a"))
        assertNull("odd length after separators are stripped", AdvertParser.parseHex("02:01:1"))
        assertNull(AdvertParser.parseHex(null))
    }

    @Test
    fun toHexRoundTrips() {
        assertEquals("", AdvertParser.toHex(null))
        assertEquals("", AdvertParser.toHex(ByteArray(0)))
        assertEquals("00ff7f80", AdvertParser.toHex(b(0x00, 0xFF, 0x7F, 0x80)))
        assertArrayEquals(
            BRIEF_COMPOSITE,
            AdvertParser.parseHex(AdvertParser.toHex(BRIEF_COMPOSITE)),
        )
    }

    // ── Constants, so a renumbering is a test failure ──────────────────

    @Test
    fun assignedNumbers() {
        assertEquals(0x01, AdvertParser.AD_TYPE_FLAGS)
        assertEquals(0x0A, AdvertParser.AD_TYPE_TX_POWER)
        assertEquals(0xFF, AdvertParser.AD_TYPE_MANUFACTURER)
        assertEquals("Apple Inc., 4C 00 little-endian on air", 0x004C, AdvertParser.COMPANY_APPLE)
        assertEquals(0x01, AdvertParser.APPLE_OVERFLOW_AREA)
        assertEquals(0x0C, AdvertParser.APPLE_HANDOFF)
        assertEquals(0x0D, AdvertParser.APPLE_TETHERING_SOURCE)
        assertEquals(0x0F, AdvertParser.APPLE_NEARBY_ACTION)
        assertEquals(0x10, AdvertParser.APPLE_NEARBY_INFO)
        assertEquals(16, AdvertParser.OVERFLOW_BITMAP_LEN)
    }
}
