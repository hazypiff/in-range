import 'package:flutter_test/flutter_test.dart';
import 'package:in_range/features/beacon/apple_overflow_bit.dart';

/// David G. Young's brute-forced overflow table, indexed by bit position.
///
/// PROVENANCE. Machine-extracted 2026-07-26 from
/// `OverflowAreaBeaconRef/OverflowAreaBeaconRef/OverflowArea/OverflowAreaUtils.swift:17-146`
/// (github.com/davidgyoungtech/OverflowAreaBeaconRef, Apache-2, May 2020) with:
///
/// ```python
/// body = re.search(r'TableOfOverflowServiceUuidStringsByBitPosition\s*=\s*\[(.*?)\]',
///                  open(SWIFT).read(), re.S).group(1)
/// uuids = re.findall(r'"([0-9A-Fa-f\-]{36})"', body)      # 128 rows, in bit order
/// ```
///
/// Not hand-transcribed. Every row in the Swift source has the fixed prefix
/// `00000000-0000-0000-0000-0000000000` (verified during extraction: exactly
/// one distinct 34-character prefix), and the 128 low bytes are exactly
/// `0x00..0x7F` with no repeats — so storing the low bytes here is lossless.
/// [_tableUuid] rebuilds the full string.
///
/// The identical 128 rows appear in `AndroidOverflowAreaDetector/README.md`.
/// That is **not** an independent confirmation: same author, same rotating-UUID
/// experiment, same 7-bit input family. Treat the two as one measurement.
const List<int> _publishedTableLowBytes = [
  0x7C, 0x37, 0x6E, 0x25, 0x59, 0x12, 0x4B, 0x00, // bits 0-7
  0x36, 0x7D, 0x24, 0x6F, 0x13, 0x58, 0x01, 0x4A, // bits 8-15
  0x6C, 0x27, 0x7E, 0x35, 0x49, 0x02, 0x5B, 0x10, // bits 16-23
  0x26, 0x6D, 0x34, 0x7F, 0x03, 0x48, 0x11, 0x5A, // bits 24-31
  0x5D, 0x16, 0x4F, 0x04, 0x78, 0x33, 0x6A, 0x21, // bits 32-39
  0x17, 0x5C, 0x05, 0x4E, 0x32, 0x79, 0x20, 0x6B, // bits 40-47
  0x4D, 0x06, 0x5F, 0x14, 0x68, 0x23, 0x7A, 0x31, // bits 48-55
  0x07, 0x4C, 0x15, 0x5E, 0x22, 0x69, 0x30, 0x7B, // bits 56-63
  0x3E, 0x75, 0x2C, 0x67, 0x1B, 0x50, 0x09, 0x42, // bits 64-71
  0x74, 0x3F, 0x66, 0x2D, 0x51, 0x1A, 0x43, 0x08, // bits 72-79
  0x2E, 0x65, 0x3C, 0x77, 0x0B, 0x40, 0x19, 0x52, // bits 80-87
  0x64, 0x2F, 0x76, 0x3D, 0x41, 0x0A, 0x53, 0x18, // bits 88-95
  0x1F, 0x54, 0x0D, 0x46, 0x3A, 0x71, 0x28, 0x63, // bits 96-103
  0x55, 0x1E, 0x47, 0x0C, 0x70, 0x3B, 0x62, 0x29, // bits 104-111
  0x0F, 0x44, 0x1D, 0x56, 0x2A, 0x61, 0x38, 0x73, // bits 112-119
  0x45, 0x0E, 0x57, 0x1C, 0x60, 0x2B, 0x72, 0x39, // bits 120-127
];

String _tableUuid(int lowByte) =>
    '00000000-0000-0000-0000-0000000000'
    '${lowByte.toRadixString(16).toUpperCase().padLeft(2, '0')}';

/// in-range's marker service UUID — `beacon_service.dart:605`, advertised in
/// the background by `BackgroundBeacon.swift:25` as `CBUUID(string: "CAFE")`.
const String inRangeServiceUuid = '0000CAFE-0000-1000-8000-00805F9B34FB';

/// Apple's Watch service UUID, per `OverflowAreaUtils.swift:13-16`.
const String appleWatchServiceUuid = '9aa4730f-b25c-4cc3-b821-c931559fc196';

void main() {
  group('published 128-row table', () {
    test('extraction is a lossless cover of 0x00..0x7F', () {
      expect(_publishedTableLowBytes, hasLength(128));
      expect(_publishedTableLowBytes.toSet(), hasLength(128));
      expect(
        (_publishedTableLowBytes.toList()..sort()),
        List<int>.generate(128, (i) => i),
        reason: 'the Swift table rows must be exactly low bytes 0x00-0x7F',
      );
    });

    test('appleOverflowBit reproduces all 128 rows', () {
      final mismatches = <String>[];
      for (var bit = 0; bit < 128; bit++) {
        final uuid = _tableUuid(_publishedTableLowBytes[bit]);
        final got = appleOverflowBit(uuid);
        if (got != bit) mismatches.add('$uuid: want $bit got $got');
      }
      expect(mismatches, isEmpty);
    });

    test('the all-zeros UUID is bit 7 — this is the output-XOR term', () {
      // CRC8(16 zero bytes) == 0, so bit 7 is entirely due to `^ 0x07`.
      // Review D2 suggests this UUID as a hash-free marker precisely because
      // its bit is table-sourced rather than computed.
      expect(appleOverflowBit('00000000-0000-0000-0000-000000000000'), 7);
    });
  });

  group('out-of-sample evidence', () {
    test('Apple Watch UUID hashes to 69 — the only genuine out-of-sample point',
        () {
      // Full-entropy UUID, absent from the table, and Young had no algorithm
      // with which to compute it: he observed the pairing dialog and
      // attributed the bit. 1-in-128 by chance.
      expect(appleOverflowBit(appleWatchServiceUuid), 69);
      expect(appleOverflowBit(appleWatchServiceUuid), appleWatchPairingBit);
    });

    test(
        'RECORDED CONTRADICTION: 2020 iPhone 6 / iOS 11 capture says 83, '
        'formula says 84', () {
      // `ios-overflow-area/README.md` (Young, Apr 2020) backgrounded service
      // UUID 2F234454-... on an iPhone 6 running iOS 11 and captured:
      //   02 01 1a | 14 ff 4c 00 01 | 00*10 08 00*5
      // Parsed below: the bitmap's only set bit is 83.
      const captured = '02011a14ff4c0001'
          '00000000000000000000080000000000';
      final bytes = <int>[
        for (var i = 0; i < captured.length; i += 2)
          int.parse(captured.substring(i, i + 2), radix: 16),
      ];
      // Skip flags AD (3 bytes) + len/type/company/appletype (5 bytes).
      expect(bytes[3], 20, reason: 'manufacturer AD length');
      expect(bytes[4], 0xFF);
      expect(bytes[5] | (bytes[6] << 8), appleCompanyId);
      expect(bytes[7], appleOverflowAdType);
      final bitmap = bytes.sublist(8, 8 + overflowBitmapLength);
      expect(decodeOverflowBitmap(bitmap), [83],
          reason: 'the captured advert sets bit 83 and nothing else');

      const disputed = '2F234454-CF6D-4A0F-ADF2-F4911BA9FFA6';
      expect(appleOverflowBit(disputed), 84,
          reason: 'the formula disagrees with that capture by exactly ^0x07');

      // The gap is NOT the review's guessed `08`-for-`10` transcription slip:
      // 83 ^ 84 == 7, and 83 is exactly CRC8(uuid) & 0x7F *before* the output
      // XOR. So the capture is consistent with the same CRC minus the `^0x07`
      // term. Under no width-<=8 CRC parameterisation can the published table
      // and this capture both hold (see the uniqueness test below: zero
      // functions satisfy both). Either the XOR constant changed between
      // iOS 11 and iOS 13/14, or one observation is wrong. UNRESOLVED — do
      // not "fix" the formula to match either side without new hardware data.
      expect(83 ^ 84, 7);
    });
  });

  group("in-range's own marker UUID", () {
    test('CAFE hashes to bit 36 -> bitmap byte 4, mask 0x10', () {
      expect(appleOverflowBit(inRangeServiceUuid), 36);
      expect(overflowBitmapByte(36), 4);
      expect(overflowBitmapMask(36), 0x10);
    });

    test("filter bytes match review D1's worked example exactly", () {
      final f = appleOverflowFilterFor(appleOverflowBit(inRangeServiceUuid));
      expect(f.dataHex, '01 00 00 00 00 10 00 00 00 00 00 00 00 00 00 00 00');
      expect(f.maskHex, 'FF 00 00 00 00 10 00 00 00 00 00 00 00 00 00 00 00');
      expect(f.data, hasLength(17));
      expect(f.mask, hasLength(17));
      expect(f.bit, 36);
      expect(f.payloadOffset, 0);
    });

    test('CAFE is not the Apple Watch pairing bit', () {
      // Guard for any future marker-UUID change: bit 69 pops "Use your iPhone
      // to set up this Apple Watch" on nearby phones at a few centimetres.
      expect(appleOverflowBit(inRangeServiceUuid),
          isNot(equals(appleWatchPairingBit)));
    });
  });

  group('ScanFilter construction', () {
    test('non-zero payloadOffset shifts the whole pattern (review D3)', () {
      // Android 10-14 keep only the LAST Apple AD; 15+ concatenate and keep
      // the first at offset 0 — so the offset is version- and peer-dependent
      // and must never be hard-coded.
      final f = appleOverflowFilterFor(36, payloadOffset: 6);
      expect(f.data, hasLength(6 + 17));
      expect(f.mask, hasLength(6 + 17));
      expect(f.dataHex,
          '00 00 00 00 00 00 01 00 00 00 00 10 00 00 00 00 00 00 00 00 00 00 00');
      expect(f.maskHex,
          '00 00 00 00 00 00 FF 00 00 00 00 10 00 00 00 00 00 00 00 00 00 00 00');
    });

    test('mask only ever selects the type byte and the one bitmap bit', () {
      for (final bit in [0, 7, 8, 36, 69, 100, 127]) {
        final f = appleOverflowFilterFor(bit);
        final selected = <int>[
          for (var i = 0; i < f.mask.length; i++) if (f.mask[i] != 0) i,
        ];
        expect(selected, [0, 1 + bit ~/ 8],
            reason: 'bit $bit must not constrain any other payload byte');
        // AOSP requires (mask & scanned) == (mask & data), so data outside the
        // mask is irrelevant — but keep it zero so logs are readable.
        for (var i = 0; i < f.data.length; i++) {
          if (f.mask[i] == 0) expect(f.data[i], 0);
        }
      }
    });

    test('a real overflow payload matches its own filter under AOSP rules', () {
      // Emulates aosp/ScanFilter.java:576-596 matchesPartialData.
      bool matches(AppleOverflowFilter f, List<int> scanned) {
        if (scanned.length < f.data.length) return false;
        for (var i = 0; i < f.data.length; i++) {
          if ((f.mask[i] & scanned[i]) != (f.mask[i] & f.data[i])) return false;
        }
        return true;
      }

      // A peer advertising CAFE (36) plus a rotating token UUID (say bit 91).
      final payload = <int>[
        appleOverflowAdType,
        ...encodeOverflowBitmap([36, 91]),
      ];
      expect(matches(appleOverflowFilterFor(36), payload), isTrue,
          reason: 'extra bits from other advertised UUIDs must not block');
      expect(matches(appleOverflowFilterFor(37), payload), isFalse);
      // A Continuity Nearby Info AD (type 0x10) must be rejected by the type
      // byte even if its bytes happen to carry 0x10 at bitmap byte 4.
      final continuity = <int>[0x10, 0, 0, 0, 0, 0x10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
      expect(matches(appleOverflowFilterFor(36), continuity), isFalse);
      // Short payload: AOSP rejects rather than partially matching.
      expect(matches(appleOverflowFilterFor(36), [0x01, 0, 0, 0, 0, 0x10]),
          isFalse);
    });

    test('rejects out-of-range bits and negative offsets', () {
      expect(() => appleOverflowFilterFor(-1), throwsRangeError);
      expect(() => appleOverflowFilterFor(128), throwsRangeError);
      expect(() => appleOverflowFilterFor(36, payloadOffset: -1),
          throwsRangeError);
      expect(() => overflowBitmapByte(128), throwsRangeError);
      expect(() => overflowBitmapMask(-1), throwsRangeError);
    });
  });

  group('bitmap codec', () {
    test('LSB-first within each byte', () {
      // OverflowAreaUtils.swift:206-250 uses `1 << bitNumber`, so bit 0 is
      // 0x01 of byte 0 and bit 7 is 0x80 of byte 0.
      expect(decodeOverflowBitmap([0x01, ...List.filled(15, 0)]), [0]);
      expect(decodeOverflowBitmap([0x80, ...List.filled(15, 0)]), [7]);
      expect(
        decodeOverflowBitmap([...List.filled(15, 0), 0x80]),
        [127],
      );
      expect(encodeOverflowBitmap([36])[4], 0x10);
    });

    test('round-trips every single bit', () {
      for (var bit = 0; bit < 128; bit++) {
        expect(decodeOverflowBitmap(encodeOverflowBitmap([bit])), [bit]);
      }
    });

    test('round-trips multi-bit sets and returns ascending positions', () {
      const bits = [3, 7, 36, 69, 83, 84, 127];
      expect(decodeOverflowBitmap(encodeOverflowBitmap(bits)), bits);
      expect(decodeOverflowBitmap(encodeOverflowBitmap(bits.reversed)), bits);
    });

    test('empty bitmap decodes to nothing', () {
      expect(decodeOverflowBitmap(List.filled(16, 0)), isEmpty);
      expect(encodeOverflowBitmap(const []), List.filled(16, 0));
    });

    test('rejects wrong-length and out-of-range bitmaps', () {
      expect(() => decodeOverflowBitmap(List.filled(15, 0)),
          throwsA(isA<FormatException>()));
      expect(() => decodeOverflowBitmap(List.filled(17, 0)),
          throwsA(isA<FormatException>()));
      expect(() => decodeOverflowBitmap([0x100, ...List.filled(15, 0)]),
          throwsA(isA<FormatException>()));
      expect(() => encodeOverflowBitmap([128]), throwsRangeError);
    });
  });

  group('input handling', () {
    test('dashes and case are irrelevant', () {
      const forms = [
        '0000CAFE-0000-1000-8000-00805F9B34FB',
        '0000cafe-0000-1000-8000-00805f9b34fb',
        '0000CAFE00001000800000805F9B34FB',
        '0000cafe00001000800000805f9b34fb',
        '0000-CAFE-0000-1000-8000-0080-5F9B-34FB',
      ];
      for (final f in forms) {
        expect(appleOverflowBit(f), 36, reason: f);
      }
    });

    test('byte form agrees with string form', () {
      expect(appleOverflowBitFromBytes(parseUuid(inRangeServiceUuid)), 36);
      expect(
        appleOverflowBitFromBytes(const [
          0x9a, 0xa4, 0x73, 0x0f, 0xb2, 0x5c, 0x4c, 0xc3, //
          0xb8, 0x21, 0xc9, 0x31, 0x55, 0x9f, 0xc1, 0x96,
        ]),
        69,
      );
    });

    test('byte order is big-endian, not the little-endian on-air order', () {
      // Getting this backwards yields a plausible-looking wrong bit, which is
      // exactly the failure that would silently kill the scan filter.
      final be = parseUuid(inRangeServiceUuid);
      final le = be.reversed.toList();
      expect(appleOverflowBitFromBytes(le), isNot(36));
    });

    test('malformed input throws instead of returning a wrong bit', () {
      // 16- and 32-bit short forms are NOT auto-expanded: CoreBluetooth
      // hashes the 128-bit form, so guessing here would be a silent bug.
      for (final bad in [
        '',
        'CAFE',
        '0000CAFE',
        '0000CAFE-0000-1000-8000-00805F9B34F', // 31 digits
        '0000CAFE-0000-1000-8000-00805F9B34FBB', // 33 digits
        '0000CAFE-0000-1000-8000-00805F9B34FZ', // non-hex
        'not-a-uuid-at-all',
        '0000CAFE-0000-1000-8000-00805F9B34F ',
      ]) {
        expect(() => appleOverflowBit(bad), throwsA(isA<FormatException>()),
            reason: 'should reject "$bad"');
      }
      expect(() => appleOverflowBitFromBytes(List.filled(15, 0)),
          throwsA(isA<FormatException>()));
      expect(() => appleOverflowBitFromBytes(List.filled(17, 0)),
          throwsA(isA<FormatException>()));
      expect(() => appleOverflowBitFromBytes([0x100, ...List.filled(15, 0)]),
          throwsA(isA<FormatException>()));
    });

    test('every result is a legal bit position', () {
      for (var i = 0; i < 512; i++) {
        final bytes = List<int>.generate(16, (k) => (i * 31 + k * 17) & 0xFF);
        final bit = appleOverflowBitFromBytes(bytes);
        expect(bit, inInclusiveRange(0, 127));
      }
    });
  });

  // ===========================================================================
  // Independent re-derivation. These do not test the production code so much
  // as test the CLAIM the production code encodes, so that a future reader can
  // see the evidence rather than trusting the doc comment.
  // ===========================================================================
  group('derivation audit', () {
    // The 16 canonical big-endian bytes for a table row.
    List<int> rowBytes(int lowByte) => [...List.filled(15, 0), lowByte];

    test('the published table is affine over GF(2) — CRC signature', () {
      // h(a^b) == h(a)^h(b)^h(0) for all pairs. The table's UUID set is closed
      // under XOR (only the low 7 bits vary), so all 8128 pairs are checkable.
      final bitOf = <int, int>{
        for (var bit = 0; bit < 128; bit++) _publishedTableLowBytes[bit]: bit,
      };
      final h0 = bitOf[0x00]!;
      expect(h0, 7);
      var pairs = 0;
      final violations = <String>[];
      final lows = bitOf.keys.toList();
      for (var i = 0; i < lows.length; i++) {
        for (var j = i + 1; j < lows.length; j++) {
          final a = lows[i], b = lows[j];
          pairs++;
          final want = bitOf[a]! ^ bitOf[b]! ^ h0;
          final got = bitOf[a ^ b]!;
          if (got != want) violations.add('$a^$b: want $want got $got');
        }
      }
      expect(pairs, 8128);
      expect(violations, isEmpty);
      // CAVEAT worth stating in code: this only proves linearity across the 7
      // input dimensions the table varies. The other 121 UUID bits are
      // untested by the table entirely.
    });

    test('the width-<=8 CRC fit is unique — exactly one function', () {
      // Exhaustive over: width 7 and 8, all polynomials, input-byte
      // reflection, output reflection, big- vs little-endian message order,
      // and which 7 of the register's bits are taken.
      //
      // `init` is deliberately fixed at 0: for a fixed-length message the
      // init contributes a constant XOR to the output, so it is fully
      // redundant with the fitted output XOR. That redundancy is asserted in
      // the next test — which is also why "poly 0x09 / init 0x00 / xor 0x07"
      // is one NAMING of the unique function, not a unique parameter set.
      int crc(List<int> msg, int w, int poly, bool refIn, bool refOut,
          bool little, int shift) {
        final top = 1 << (w - 1);
        final mask = (1 << w) - 1;
        var reg = 0;
        final data = little ? msg.reversed.toList() : msg;
        for (var b in data) {
          if (refIn) {
            var r = 0;
            for (var k = 0; k < 8; k++) {
              if ((b >> k) & 1 != 0) r |= 1 << (7 - k);
            }
            b = r;
          }
          reg ^= w >= 8 ? (b << (w - 8)) & mask : b >> (8 - w);
          for (var k = 0; k < 8; k++) {
            reg = (reg & top) != 0
                ? ((reg << 1) ^ poly) & mask
                : (reg << 1) & mask;
          }
        }
        if (refOut) {
          var r = 0;
          for (var k = 0; k < w; k++) {
            if ((reg >> k) & 1 != 0) r |= 1 << (w - 1 - k);
          }
          reg = r;
        }
        return (reg >> shift) & 0x7F;
      }

      // Because the map is affine (previous test), fitting the 7 basis vectors
      // (low byte = 1,2,4,...,64) implies all 128 rows. Full 128-row
      // confirmation is still run on survivors.
      final bitOf = <int, int>{
        for (var bit = 0; bit < 128; bit++) _publishedTableLowBytes[bit]: bit,
      };
      final survivors = <String>[];
      for (final w in [7, 8]) {
        for (final little in [false, true]) {
          for (final refIn in [false, true]) {
            for (final refOut in [false, true]) {
              final shifts = w == 7 ? [0] : [0, 1];
              for (final shift in shifts) {
                for (var poly = 0; poly < (1 << w); poly++) {
                  var ok = true;
                  for (var k = 0; k < 7 && ok; k++) {
                    final e = rowBytes(1 << k);
                    if (crc(e, w, poly, refIn, refOut, little, shift) !=
                        (bitOf[1 << k]! ^ bitOf[0]!)) {
                      ok = false;
                    }
                  }
                  if (!ok) continue;
                  final xorOut = bitOf[0]!; // crc(zeros) == 0 with init 0
                  for (var bit = 0; bit < 128 && ok; bit++) {
                    final m = rowBytes(_publishedTableLowBytes[bit]);
                    if ((crc(m, w, poly, refIn, refOut, little, shift) ^
                            xorOut) !=
                        bit) {
                      ok = false;
                    }
                  }
                  if (!ok) continue;
                  survivors.add('w=$w poly=0x${poly.toRadixString(16)} '
                      'refIn=$refIn refOut=$refOut little=$little '
                      'shift=$shift xorOut=0x${xorOut.toRadixString(16)}');
                  // Cross-check: the survivor must also hit the out-of-sample
                  // Watch bit, and must NOT hit the disputed iOS 11 capture.
                  expect(
                    crc(parseUuid(appleWatchServiceUuid), w, poly, refIn,
                            refOut, little, shift) ^
                        xorOut,
                    69,
                  );
                  expect(
                    crc(parseUuid('2F234454-CF6D-4A0F-ADF2-F4911BA9FFA6'), w,
                            poly, refIn, refOut, little, shift) ^
                        xorOut,
                    84,
                    reason: 'no width-<=8 CRC reconciles the table with the '
                        'iOS 11 capture (bit 83)',
                  );
                }
              }
            }
          }
        }
      }
      expect(survivors, ['w=8 poly=0x9 refIn=false refOut=false little=false '
          'shift=0 xorOut=0x7']);
      // NOTE ON WHAT "UNIQUE" MEANS: unique *within the CRC family searched*.
      // The table constrains only 7 of 128 input dimensions, so uniqueness
      // here is a statement about a restricted hypothesis class, not proof
      // that Apple's hash is this CRC. On-device confirmation (review D2)
      // remains the gate.
      //
      // The same sweep run offline over widths 7..16 (too slow for a unit
      // test) found, 2026-07-26:
      //   widths 7..11 -> still exactly 1 distinct function fits the table
      //   widths 7..12 -> 2 distinct functions fit
      //   widths 7..16 -> 22 distinct functions fit, of which exactly 1 also
      //                   predicts the Apple Watch bit 69
      //   widths 7..16 -> ZERO functions fit the table AND the iOS 11
      //                   capture's bit 83
      // So the table alone is not quite sufficient once wide registers are
      // admitted; the Watch out-of-sample point is doing real selection work
      // (1-in-22), and no CRC in the family can reconcile the two captures.
    });

    test('init is redundant with the output XOR for fixed-length messages', () {
      // Justifies fixing init=0 above, and explains why the "init 0x00,
      // xor 0x07" naming is not itself evidence.
      int crcInit(List<int> msg, int init) {
        var reg = init;
        for (final b in msg) {
          reg ^= b;
          for (var k = 0; k < 8; k++) {
            reg = (reg & 0x80) != 0
                ? ((reg << 1) ^ 0x09) & 0xFF
                : (reg << 1) & 0xFF;
          }
        }
        return reg;
      }

      for (final init in [0x00, 0x01, 0x5A, 0xFF]) {
        final deltas = <int>{};
        for (var i = 0; i < 32; i++) {
          final m = List<int>.generate(16, (k) => (i * 37 + k * 11) & 0xFF);
          deltas.add(crcInit(m, init) ^ crcInit(m, 0));
        }
        expect(deltas, hasLength(1),
            reason: 'init $init must shift the output by a message-independent '
                'constant');
      }
    });
  });
}
