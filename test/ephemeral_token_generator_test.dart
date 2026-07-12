import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_range/features/beacon/ephemeral_token_generator.dart';

void main() {
  const userSecret = '0123456789abcdef0123456789abcdef';
  const hmacSecret = 'abcdef0123456789abcdef0123456789';

  test('token has 36-byte payload and user-bound prefix', () {
    final now = DateTime.utc(2026, 7, 11, 12);
    EphemeralTokenGenerator generator(String userId) => EphemeralTokenGenerator(
          userIdSecret: userSecret,
          userId: userId,
          hmacSecret: hmacSecret,
          now: () => now,
        );

    final first = base64Url
        .decode(base64Url.normalize(generator('user-a').generate().token));
    final second = base64Url
        .decode(base64Url.normalize(generator('user-b').generate().token));
    expect(first, hasLength(36));
    expect(second, hasLength(36));
    expect(first.sublist(0, 8), isNot(equals(second.sublist(0, 8))));
  });

  test('rotation uses injected clock', () {
    var now = DateTime.utc(2026, 7, 11, 12);
    final generator = EphemeralTokenGenerator(
      userIdSecret: userSecret,
      userId: 'user-a',
      hmacSecret: hmacSecret,
      now: () => now,
    );
    final token = generator.generate();
    expect(generator.shouldRotate(token), isFalse);
    now = token.expiresAt.subtract(const Duration(seconds: 30));
    expect(generator.shouldRotate(token), isTrue);
  });
}
