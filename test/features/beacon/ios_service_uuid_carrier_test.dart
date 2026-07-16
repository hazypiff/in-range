import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';

/// iOS service-UUID token carrier (path b) — the advertiser encodes the 16-byte
/// correlation id as a 128-bit service UUID; the scanner recovers it. This test
/// guards the byte round-trip: if build/parse disagree, advertiser_hex !=
/// scanner_recovered_hex and no encounter ever confirms (hazypiff review 3d).
void main() {
  String hex(List<int> b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  test('16 corr bytes -> 128-bit UUID -> identical bytes (round trip)', () {
    // A non-trivial pattern (not all-equal) so byte-order bugs surface.
    final bytes =
        Uint8List.fromList(List.generate(16, (i) => (i * 37 + 11) & 0xFF));

    final uuidStr = Guid.fromBytes(bytes).str128; // advertiser side
    final recovered = Guid(uuidStr).bytes; // scanner side

    expect(recovered.length, 16);
    expect(recovered, equals(bytes));
    expect(hex(recovered), equals(hex(bytes)));
  });

  test('discovery marker equals its short form and is distinct from a token',
      () {
    final markerLong = Guid('0000cafe-0000-1000-8000-00805f9b34fb');
    final markerShort = Guid('cafe');
    final token = Guid.fromBytes(Uint8List.fromList(List.filled(16, 0xAB)));

    // Value equality across forms (how the scanner matches the marker).
    expect(markerShort == markerLong, isTrue);
    // A real token never collides with the marker.
    expect(token == markerLong, isFalse);
    expect(token.bytes.length, 16);
  });

  test('scanner logic: marker present -> pick the other 16-byte UUID as token',
      () {
    final marker = Guid('0000cafe-0000-1000-8000-00805f9b34fb');
    final tokenBytes =
        Uint8List.fromList(List.generate(16, (i) => (i * 91 + 7) & 0xFF));
    // What an iPhone advertises: [short marker, token-as-128bit].
    final advertised = <Guid>[Guid('cafe'), Guid.fromBytes(tokenBytes)];

    Uint8List? recovered;
    if (advertised.any((u) => u == marker)) {
      for (final u in advertised) {
        if (u != marker && u.bytes.length == 16) {
          recovered = Uint8List.fromList(u.bytes);
          break;
        }
      }
    }
    expect(recovered, isNotNull);
    expect(hex(recovered!), equals(hex(tokenBytes)));
  });
}
