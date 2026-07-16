import 'dart:math';

import 'package:in_range/features/beacon/ephemeral_token_generator.dart';

/// One slot of a server-issued token batch (#6 step 2).
class BatchSlot {
  const BatchSlot({
    required this.token,
    required this.validFrom,
    required this.validUntil,
  });

  final String token; // opaque 32 hex chars (128-bit)
  final DateTime validFrom;
  final DateTime validUntil;
}

/// Fetches a day's opaque token batch. Returns [] when the cloud is unavailable
/// (local BLE mode) or the RPC fails — the caller then falls back to a random
/// token so advertising never stalls.
typedef BatchFetcher = Future<List<BatchSlot>> Function(
    DateTime dayUtc, int windowMinutes);

/// Server-issued opaque token source (#6 step 2).
///
/// Replaces the client-side [EphemeralTokenGenerator], whose HMAC was keyed by a
/// secret shipped in the app (so it was cosmetic — anyone with the binary could
/// forge it). Here the SERVER mints the opaque tokens (`issue_token_batch`); the
/// client fetches a day's batch once and advertises the slot covering "now". The
/// token value is unguessable and server-owned, which is what makes it
/// unforgeable and enables attested issuance / revocation later.
///
/// Fallback: when no batch is available (local mode or a transient fetch
/// failure) it yields a locally-generated random opaque token so BLE advertising
/// keeps working; those tokens simply won't correlate server-side until a real
/// batch loads. Never throws.
class BatchTokenSource {
  BatchTokenSource({
    required BatchFetcher fetchBatch,
    Duration rotationWindow = const Duration(minutes: 15),
    DateTime Function() now = DateTime.now,
    Random? random,
  })  : _fetch = fetchBatch,
        _window = rotationWindow,
        _now = now,
        _rand = random ?? Random.secure();

  final BatchFetcher _fetch;
  final Duration _window;
  final DateTime Function() _now;
  final Random _rand;

  final List<BatchSlot> _slots = <BatchSlot>[];

  /// Same rotation policy as before: rotate ~1 min before the current token
  /// expires (or immediately when there is none).
  bool shouldRotate(EphemeralToken? current,
      {Duration grace = const Duration(minutes: 1)}) {
    if (current == null) return true;
    return _now().isAfter(current.expiresAt.subtract(grace));
  }

  /// The opaque token for the slot covering "now", fetching/refreshing the batch
  /// as needed. Never throws — falls back to a random opaque token.
  Future<EphemeralToken> nextToken() async {
    final now = _now();
    BatchSlot? slot = _covering(now);
    if (slot == null) {
      await _ensureBatch(now);
      slot = _covering(now);
    }
    if (slot != null) {
      return EphemeralToken(
        token: slot.token,
        epochSeconds: slot.validFrom.millisecondsSinceEpoch ~/ 1000,
        issuedAt: now,
        expiresAt: slot.validUntil,
      );
    }
    return _randomToken(now);
  }

  /// The cached slot whose [validFrom, validUntil) contains [now]. Consecutive
  /// slots overlap by the server-side grace, so prefer the latest-starting one.
  BatchSlot? _covering(DateTime now) {
    BatchSlot? best;
    for (final s in _slots) {
      if (!now.isBefore(s.validFrom) && now.isBefore(s.validUntil)) {
        if (best == null || s.validFrom.isAfter(best.validFrom)) best = s;
      }
    }
    return best;
  }

  Future<void> _ensureBatch(DateTime now) async {
    final utc = now.toUtc();
    final dayUtc = DateTime.utc(utc.year, utc.month, utc.day);
    try {
      final slots = await _fetch(dayUtc, _window.inMinutes);
      if (slots.isNotEmpty) {
        _slots
          ..clear()
          ..addAll(slots);
      }
    } catch (_) {
      // Keep any prior batch; nextToken falls back to random if none covers now.
    }
  }

  EphemeralToken _randomToken(DateTime now) {
    final bytes = List<int>.generate(16, (_) => _rand.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final windowSecs = _window.inSeconds;
    final epoch =
        (now.millisecondsSinceEpoch ~/ 1000 ~/ windowSecs) * windowSecs;
    return EphemeralToken(
      token: hex,
      epochSeconds: epoch,
      issuedAt: now,
      expiresAt:
          DateTime.fromMillisecondsSinceEpoch((epoch + windowSecs) * 1000),
    );
  }
}
