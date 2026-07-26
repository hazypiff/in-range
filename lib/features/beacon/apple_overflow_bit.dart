/// Apple BLE "overflow area" bit arithmetic — the piece needed to turn
/// in-range's catch-everything Apple scan filter into a filter for *our*
/// service UUID.
///
/// ## What the overflow area is
///
/// When an iOS app that advertises service UUIDs is backgrounded,
/// CoreBluetooth stops emitting those UUIDs as normal AD structures and moves
/// them into an undocumented Apple manufacturer AD: company id `0x004C`,
/// Apple AD type byte `0x01`, then a 16-byte (128-bit) bitmap in which each
/// advertised service UUID sets exactly one bit. Bit `p` lives in bitmap byte
/// `p ~/ 8` at mask `1 << (p % 8)` — LSB-first within each byte. Layout
/// confirmed against `OverflowAreaUtils.swift:206-250` (David G. Young,
/// Apache-2, 2020) and restated in his `AndroidOverflowAreaDetector/README.md`.
///
/// ## Why in-range wants this
///
/// The Android scan currently registers
/// `MsdFilter(0x004C, data: [0x01], mask: [0xFF])` — "any backgrounded
/// iPhone". Every match costs one speculative GATT connect to recover the
/// token, so a mall full of iPhones burns the connect budget on strangers. If
/// the bit for the CAFE marker UUID is known, the *hardware* filter can match
/// that one bit instead: a stranger sets ~1 bit per advertised UUID, so
/// P(collision) is ~0.8% at k=1 and ~2.3% at k=3 versus 100% today —
/// a 40-130x cut in wasted connects (BLE prior-art review 2026-07-26, D1).
///
/// ## PROVENANCE — READ THIS BEFORE SHIPPING IT
///
/// **This is not a documented Apple API and the closed form below is not a
/// published result.** Every prior project (Young's reference app, his Android
/// detector, android-beacon-library) ships a brute-forced 128-entry lookup
/// table and calls the mapping "some proprietary Apple hashing algorithm". The
/// CRC-8 parameterisation here was *derived* by an agent on 2026-07-26 by
/// fitting that table, and re-verified independently in this file's test.
///
/// Evidence for it:
///  - Reproduces all 128 published table rows exactly (test-locked).
///  - The published table is affine over GF(2) — `h(a^b) == h(a)^h(b)^h(0)`
///    held on all 8128 pairs with zero violations, which is the signature of
///    a CRC.
///  - Out-of-sample hit: Apple's Watch service UUID
///    `9aa4730f-b25c-4cc3-b821-c931559fc196` is full-entropy and appears
///    nowhere in the table, yet the formula returns 69 — the value
///    `OverflowAreaUtils.swift:13-16` independently attributes to it.
///
/// Evidence against / limits — a future reader must not skip these:
///  - **The table only constrains 7 of the 128 input bits.** Its rows are all
///    `00000000-0000-0000-0000-0000000000XX` for `XX` in `0x00..0x7F`, so it
///    pins the hash on a 7-dimensional subspace and says nothing about the
///    other 121 dimensions. Young's Swift table and his Android README table
///    are byte-identical but are the *same* experiment by the *same* author,
///    not two independent measurements. The Watch UUID is the only genuine
///    out-of-sample point in existence, and it is a single 7-bit observation.
///  - **One real capture disagrees.** `ios-overflow-area/README.md` (Young,
///    Apr 2020, iPhone 6, iOS 11) shows advert
///    `02011a14ff4c0001 00000000000000000000 08 0000000000` while
///    backgrounding service UUID `2F234454-CF6D-4A0F-ADF2-F4911BA9FFA6`.
///    That bitmap is byte 10 / mask `0x08` = bit **83**. This function returns
///    **84**. The gap is exactly the `^ 0x07` term (83 ^ 84 == 7), and 83 is
///    exactly `CRC8(uuid) & 0x7F` before the XOR — so it is *not* a plausible
///    `08`-for-`10` transcription slip as the review supposed. Either the XOR
///    constant is iOS-version-dependent (that capture is iOS 11; the table is
///    iOS 13/14) or one of the two observations is wrong. Unresolved. See
///    the recorded test case in `test/apple_overflow_bit_test.dart`.
///  - **Never confirmed on in-range hardware.** Do the 30-minute measurement
///    from review D2 first: background an in-range iPhone next to an Android
///    build logging raw `ScanRecord.getBytes()`, and read which bit is
///    actually set. Expect byte 4 / mask `0x10`.
///
/// Consequently **nothing in this library is wired into the live scan
/// filter.** It is a tested utility waiting on that measurement. Getting the
/// bit wrong does not degrade gracefully: a wrong bit means the hardware
/// filter silently stops matching backgrounded iPhones at all, and the
/// token-recovery path goes dark with no error anywhere.
library;

import 'dart:typed_data';

/// Bit 69 is Apple's own Watch service UUID
/// (`9aa4730f-b25c-4cc3-b821-c931559fc196`).
///
/// **Never advertise a UUID that hashes here.**
/// `OverflowAreaUtils.swift:13-16` warns that setting this bit makes nearby
/// iPhones pop "Apple Watch: Use your iPhone to set up this Apple Watch" when
/// the emitter is within a few centimetres. in-range's CAFE marker hashes to
/// 36, which is clear — but any future marker UUID must be checked against
/// this constant before it ships.
const int appleWatchPairingBit = 69;

/// The Apple manufacturer (company) id that carries the overflow AD.
const int appleCompanyId = 0x004C;

/// The Apple AD type byte that marks a payload as an overflow bitmap.
/// Other observed types are Continuity messages (`0x02` iBeacon, `0x0C`
/// Handoff, `0x10` Nearby Info, ...) and must not be confused with it.
const int appleOverflowAdType = 0x01;

/// Length of the overflow bitmap in bytes (128 bits).
const int overflowBitmapLength = 16;

/// The overflow bit position for a 128-bit BLE service [uuid].
///
/// Accepts the canonical dashed form, the 32-hex-digit undashed form, and
/// either case: `0000CAFE-0000-1000-8000-00805F9B34FB`,
/// `0000cafe00001000800000805f9b34fb`. Throws [FormatException] on anything
/// else — a silently-wrong bit would disable the scan filter with no
/// symptom, so malformed input must never fall through to a plausible number.
///
/// 16-bit and 32-bit short UUIDs must be expanded to their 128-bit form by
/// the caller (`CAFE` -> `0000CAFE-0000-1000-8000-00805F9B34FB`) because
/// that is what CoreBluetooth hashes; this function will not guess.
int appleOverflowBit(String uuid) => appleOverflowBitFromBytes(parseUuid(uuid));

/// The overflow bit position for a service UUID already in its canonical
/// **big-endian** 16-byte form (most significant byte first — the same order
/// the characters appear in the dashed string, *not* the little-endian order
/// BLE uses on the air).
///
/// `bit = (CRC8(bytes, poly=0x09, init=0x00) & 0x7F) ^ 0x07`
/// — width 8, polynomial x^8+x^3+1, MSB-first, non-reflected, no final
/// reflection. See the library doc comment for provenance and caveats.
int appleOverflowBitFromBytes(List<int> uuidBytes) {
  if (uuidBytes.length != 16) {
    throw FormatException(
        'service UUID must be 16 bytes, got ${uuidBytes.length}');
  }
  var reg = 0x00;
  for (final b in uuidBytes) {
    if (b < 0 || b > 0xFF) {
      throw FormatException('UUID byte out of range: $b');
    }
    reg ^= b;
    for (var i = 0; i < 8; i++) {
      reg = (reg & 0x80) != 0 ? ((reg << 1) ^ 0x09) & 0xFF : (reg << 1) & 0xFF;
    }
  }
  // The `^ 0x07` is the CRC's output XOR: the all-zeros UUID has CRC 0 yet
  // occupies bit 7 in every published table. It is also the single term the
  // 2020 iOS 11 capture contradicts (see library doc).
  return (reg & 0x7F) ^ 0x07;
}

/// Parse a 128-bit UUID string into its canonical big-endian 16 bytes.
///
/// Tolerates dashes anywhere (their placement is not validated — only that
/// exactly 32 hex digits remain) and either case. Throws [FormatException]
/// rather than returning a partial result.
Uint8List parseUuid(String uuid) {
  final hex = uuid.replaceAll('-', '');
  if (hex.length != 32) {
    throw FormatException(
        'expected a 128-bit UUID (32 hex digits), got ${hex.length}: "$uuid"');
  }
  // Hand-rolled nibble decode rather than int.parse: Dart's int.parse accepts
  // surrounding whitespace, so "…00805F9B34F " would have parsed its last byte
  // as 0x0F and returned a plausible, wrong bit (caught by this file's test
  // 2026-07-26). A wrong bit is the exact failure this library must not have.
  final out = Uint8List(16);
  for (var i = 0; i < 16; i++) {
    out[i] = (_nibble(hex.codeUnitAt(i * 2), uuid) << 4) |
        _nibble(hex.codeUnitAt(i * 2 + 1), uuid);
  }
  return out;
}

int _nibble(int codeUnit, String uuid) {
  if (codeUnit >= 0x30 && codeUnit <= 0x39) return codeUnit - 0x30; // 0-9
  if (codeUnit >= 0x41 && codeUnit <= 0x46) return codeUnit - 0x37; // A-F
  if (codeUnit >= 0x61 && codeUnit <= 0x66) return codeUnit - 0x57; // a-f
  throw FormatException('non-hex character in UUID: "$uuid"');
}

/// Which of the 16 bitmap bytes carries [bit].
int overflowBitmapByte(int bit) {
  _checkBit(bit);
  return bit ~/ 8;
}

/// The mask within [overflowBitmapByte] that carries [bit] — LSB-first, so
/// bit 36 is byte 4 mask `0x10`, not `0x08`.
int overflowBitmapMask(int bit) {
  _checkBit(bit);
  return 1 << (bit % 8);
}

void _checkBit(int bit) {
  if (bit < 0 || bit > 127) {
    throw RangeError.range(bit, 0, 127, 'bit', 'overflow bit position');
  }
}

/// A `(data, mask)` pair for an Android `ScanFilter` manufacturer-data filter
/// — `MsdFilter(appleCompanyId, data: filter.data, mask: filter.mask)` in
/// flutter_blue_plus, which passes both arrays through unchanged
/// (`FlutterBluePlusPlugin.java:593-606`), so no plugin change is needed.
class AppleOverflowFilter {
  const AppleOverflowFilter({
    required this.data,
    required this.mask,
    required this.bit,
    required this.payloadOffset,
  });

  /// Filter bytes, positionally aligned with the manufacturer-data payload
  /// (i.e. *after* the two company-id bytes).
  final List<int> data;

  /// Which payload bytes are compared. AOSP tests
  /// `(mask[i] & scanned[i]) == (mask[i] & data[i])` for every `i` and
  /// rejects any advert whose payload is shorter than `data`
  /// (`aosp/ScanFilter.java:576-596`), so length matters: this pair is
  /// exactly `payloadOffset + 17` bytes.
  final List<int> mask;

  /// The overflow bit this filter matches.
  final int bit;

  /// Where the Apple AD type byte sits inside the payload.
  final int payloadOffset;

  /// Space-separated uppercase hex, for logging next to a raw
  /// `ScanRecord.getBytes()` dump.
  String get dataHex => _hex(data);

  /// Space-separated uppercase hex of [mask].
  String get maskHex => _hex(mask);

  static String _hex(List<int> b) =>
      b.map((x) => x.toRadixString(16).toUpperCase().padLeft(2, '0')).join(' ');

  @override
  String toString() =>
      'AppleOverflowFilter(bit: $bit, payloadOffset: $payloadOffset, '
      'data: $dataHex, mask: $maskHex)';
}

/// Build the Android manufacturer-data filter that matches only overflow
/// adverts with [bit] set.
///
/// [payloadOffset] is the index of the Apple AD type byte (`0x01`) within the
/// manufacturer-data payload, and it **must** stay a parameter rather than a
/// baked-in 0. Modern iPhones commonly emit two Apple ADs in one PDU
/// (Continuity Nearby Info + overflow) and AOSP's handling of a duplicate
/// company id inverted across releases (review D3):
///
/// | Android | duplicate company id | overflow at offset 0 iff |
/// |---|---|---|
/// | 10-14 | last Apple AD wins (`ScanRecord-android14-release.java:602`) | overflow AD is LAST |
/// | 15 | concatenated, flag-gated (`SR-a15.java:646-660`) | overflow AD is FIRST |
/// | 16+ | concatenated, ungated (`aosp/ScanRecord.java:644-656`) | overflow AD is FIRST |
///
/// So the offset is version- *and* peer-dependent. The intended deployment is
/// one `MsdFilter` per observed offset — they are OR'd by the radio — with the
/// offsets taken from a real capture, not guessed. Offsets 0, 5 and 6 cover
/// the cases seen in the corpus.
AppleOverflowFilter appleOverflowFilterFor(int bit, {int payloadOffset = 0}) {
  _checkBit(bit);
  if (payloadOffset < 0) {
    throw RangeError.value(payloadOffset, 'payloadOffset', 'must be >= 0');
  }
  final len = payloadOffset + 1 + overflowBitmapLength;
  final data = List<int>.filled(len, 0);
  final mask = List<int>.filled(len, 0);
  // Byte 0 of the AD is the type discriminator: require it exactly, otherwise
  // a Continuity message whose payload happens to have the right byte set
  // would match.
  data[payloadOffset] = appleOverflowAdType;
  mask[payloadOffset] = 0xFF;
  final i = payloadOffset + 1 + overflowBitmapByte(bit);
  final m = overflowBitmapMask(bit);
  data[i] = m;
  mask[i] = m;
  // Every other byte stays 0/0: bitmap bits belonging to the peer's *other*
  // advertised UUIDs (including in-range's own token-derived UUID, which sets
  // a second bit that rotates every 15 min) must be ignored, not required to
  // be absent.
  return AppleOverflowFilter(
    data: data,
    mask: mask,
    bit: bit,
    payloadOffset: payloadOffset,
  );
}

/// The bit positions set in a 16-byte overflow [bitmap], ascending.
///
/// Used by walk instrument W7 and by the D2 on-device confirmation: log this
/// against a backgrounded in-range iPhone and check that 36 is present before
/// anyone lets the bit drive a production filter.
List<int> decodeOverflowBitmap(List<int> bitmap) {
  if (bitmap.length != overflowBitmapLength) {
    throw FormatException(
        'overflow bitmap must be $overflowBitmapLength bytes, '
        'got ${bitmap.length}');
  }
  final bits = <int>[];
  for (var byte = 0; byte < overflowBitmapLength; byte++) {
    final v = bitmap[byte];
    if (v < 0 || v > 0xFF) {
      throw FormatException('bitmap byte out of range: $v');
    }
    for (var b = 0; b < 8; b++) {
      if ((v >> b) & 1 != 0) bits.add(byte * 8 + b);
    }
  }
  return bits;
}

/// Encode [bits] as a 16-byte overflow bitmap — the inverse of
/// [decodeOverflowBitmap], for building fixtures and for asserting round-trips.
Uint8List encodeOverflowBitmap(Iterable<int> bits) {
  final out = Uint8List(overflowBitmapLength);
  for (final bit in bits) {
    _checkBit(bit);
    out[bit ~/ 8] |= 1 << (bit % 8);
  }
  return out;
}
