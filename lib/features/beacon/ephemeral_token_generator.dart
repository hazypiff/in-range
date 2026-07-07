import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// EphemeralTokenGenerator
///
/// Implements the v1 token format from docs/ephemeral-token-spec.md:
///
///   <user_hash_8bytes>|<epoch_4bytes>|<random_16bytes>|<hmac_8bytes>
///
/// - user_hash: first 8 bytes of HMAC-SHA256(user_id_secret, "inrange-token-v1")
///   (never the raw user UUID).
/// - epoch: Unix seconds rounded down to the rotation window (default 15 min).
/// - random: 16 bytes from Random.secure().
/// - hmac: truncated HMAC-SHA256(global_secret, payload) — anti-forgery.
///
/// The token is base64url-encoded for transport. It rotates every epoch; on
/// rotation the client must call `claim_token` again on the server.
class EphemeralTokenGenerator {
  EphemeralTokenGenerator({
    required String userIdSecret,
    required String hmacSecret,
    Duration rotationWindow = const Duration(minutes: 15),
    DateTime Function() now = DateTime.now,
  })  : _userIdSecret = userIdSecret,
        _hmacSecret = hmacSecret,
        _rotationWindow = rotationWindow,
        _now = now;

  final String _userIdSecret;
  final String _hmacSecret;
  final Duration _rotationWindow;
  final DateTime Function() _now;

  static const String _tokenVersion = 'inrange-token-v1';

  /// Generates a fresh ephemeral token for the current rotation window.
  /// Returns the token string plus the epoch it is valid for and its
  /// computed expiry (end of the rotation window + a small grace period).
  EphemeralToken generate() {
    final now = _now();
    final windowSeconds = _rotationWindow.inSeconds;
    final epochSeconds =
        (now.millisecondsSinceEpoch ~/ 1000 ~/ windowSeconds) * windowSeconds;
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      (epochSeconds + windowSeconds) * 1000,
    );

    final userHash = _userHash();
    final randomBytes = _secureRandomBytes(16);
    final epochBytes = _int32BigEndian(epochSeconds);

    final payload = BytesBuilder()
      ..add(userHash)
      ..add(epochBytes)
      ..add(randomBytes);
    final payloadBytes = payload.toBytes();

    final sig = _hmacTruncated(payloadBytes, length: 8);
    final tokenBytes = BytesBuilder()
      ..add(payloadBytes)
      ..add(sig);
    final token = base64Url.encode(tokenBytes.toBytes()).replaceAll('=', '');

    return EphemeralToken(
      token: token,
      epochSeconds: epochSeconds,
      issuedAt: now,
      expiresAt: expiresAt,
    );
  }

  /// Returns true if the previously issued token has expired (or is within
  /// the refresh margin) and should be rotated.
  bool shouldRotate(EphemeralToken? current, {Duration grace = const Duration(minutes: 1)}) {
    if (current == null) return true;
    return DateTime.now().isAfter(current.expiresAt.subtract(grace));
  }

  List<int> _userHash() {
    final h = Hmac(sha256, utf8.encode(_userIdSecret));
    final digest = h.convert(utf8.encode(_tokenVersion));
    return digest.bytes.sublist(0, 8);
  }

  List<int> _hmacTruncated(List<int> payload, {required int length}) {
    final h = Hmac(sha256, utf8.encode(_hmacSecret));
    final digest = h.convert(payload);
    return digest.bytes.sublist(0, length);
  }

  static List<int> _secureRandomBytes(int length) {
    final r = Random.secure();
    return List<int>.generate(length, (_) => r.nextInt(256));
  }

  static List<int> _int32BigEndian(int value) {
    final data = ByteData(4)..setInt32(0, value, Endian.big);
    return data.buffer.asUint8List().toList();
  }
}

/// A generated ephemeral token with its metadata.
class EphemeralToken {
  const EphemeralToken({
    required this.token,
    required this.epochSeconds,
    required this.issuedAt,
    required this.expiresAt,
  });

  final String token;
  final int epochSeconds;
  final DateTime issuedAt;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
