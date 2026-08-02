import 'package:flutter_test/flutter_test.dart';
import 'package:in_range/features/beacon/opaque_token.dart';

String _repeat(String value, int count) => List.filled(count, value).join();

void main() {
  group('opaqueTokenBytes', () {
    test('decodes exactly 16 bytes from canonical lowercase hex', () {
      final bytes = opaqueTokenBytes('000102030405060708090a0b0c0d0e0f');

      expect(bytes, List<int>.generate(16, (i) => i));
    });

    for (final invalid in <String>[
      _repeat('00', 15),
      _repeat('00', 17),
      '000102030405060708090a0b0c0d0e0G',
      '000102030405060708090A0B0C0D0E0F',
    ]) {
      test('rejects non-canonical token: ${invalid.length} chars', () {
        expect(() => opaqueTokenBytes(invalid), throwsFormatException);
        expect(isCanonicalOpaqueToken(invalid), isFalse);
      });
    }
  });
}
