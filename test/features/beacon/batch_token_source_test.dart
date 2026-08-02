import 'package:flutter_test/flutter_test.dart';
import 'package:in_range/features/beacon/batch_token_source.dart';
import 'package:in_range/features/beacon/ephemeral_token_generator.dart';

// Mirrors the server (issue_token_batch): 15-min slots tiling a UTC day, each
// valid for window + 2 min grace.
List<BatchSlot> _dayBatch(DateTime dayUtc, int windowMinutes) {
  final slots = <BatchSlot>[];
  final n = 1440 ~/ windowMinutes;
  for (var g = 0; g < n; g++) {
    final vf = dayUtc.add(Duration(minutes: g * windowMinutes));
    slots.add(BatchSlot(
      token: g.toRadixString(16).padLeft(32, '0'),
      validFrom: vf,
      validUntil: vf.add(Duration(minutes: windowMinutes + 2)),
    ));
  }
  return slots;
}

final _hex32 = RegExp(r'^[0-9a-f]{32}$');
String _repeat(String value, int count) => List.filled(count, value).join();

void main() {
  final day = DateTime.utc(2026, 7, 16);

  test('returns the batch slot covering now', () async {
    var now = day.add(const Duration(minutes: 20)); // slot 1 (15..32 min)
    var fetches = 0;
    final src = BatchTokenSource(
      fetchBatch: (d, w) async {
        fetches++;
        return _dayBatch(d, w);
      },
      now: () => now,
    );
    final t = await src.nextToken();
    expect(t.token, _dayBatch(day, 15)[1].token);
    expect(t.expiresAt, day.add(const Duration(minutes: 32)));
    expect(fetches, 2, reason: 'today AND tomorrow are fetched together');
  });

  test('advancing across slots reuses the cached batch (no refetch)', () async {
    var now = day.add(const Duration(minutes: 5)); // slot 0
    var fetches = 0;
    final src = BatchTokenSource(
      fetchBatch: (d, w) async {
        fetches++;
        return _dayBatch(d, w);
      },
      now: () => now,
    );
    final a = await src.nextToken();
    now = day.add(const Duration(minutes: 40)); // slot 2
    final b = await src.nextToken();
    now = day.add(const Duration(minutes: 200)); // slot 13
    final c = await src.nextToken();
    expect(a.token, _dayBatch(day, 15)[0].token);
    expect(b.token, _dayBatch(day, 15)[2].token);
    expect(c.token, _dayBatch(day, 15)[13].token);
    expect(fetches, 2,
        reason: 'today + tomorrow are cached from one paired fetch');
  });

  test('tomorrow is preloaded; refetches only when now falls outside both days',
      () async {
    var now = day.add(const Duration(minutes: 20));
    final days = <DateTime>[];
    final src = BatchTokenSource(
      fetchBatch: (d, w) async {
        days.add(d);
        return _dayBatch(d, w);
      },
      now: () => now,
    );
    await src.nextToken();
    // Day+1 needs NO refetch — it was preloaded with today's batch, which is
    // exactly what keeps a dark session alive across midnight UTC.
    now = day.add(const Duration(days: 1, minutes: 20)); // next UTC day
    final t = await src.nextToken();
    expect(days, [day, day.add(const Duration(days: 1))]);
    expect(t.token, _dayBatch(day.add(const Duration(days: 1)), 15)[1].token);
    // Day+2 falls outside both cached days → a fresh paired fetch.
    now = day.add(const Duration(days: 2, minutes: 20));
    final t2 = await src.nextToken();
    expect(days, [
      day,
      day.add(const Duration(days: 1)),
      day.add(const Duration(days: 2)),
      day.add(const Duration(days: 3)),
    ]);
    expect(t2.token, _dayBatch(day.add(const Duration(days: 2)), 15)[1].token);
  });

  test('falls back to a random opaque token when the batch is empty', () async {
    final now = day.add(const Duration(minutes: 20));
    final src = BatchTokenSource(
      fetchBatch: (d, w) async => const <BatchSlot>[],
      now: () => now,
    );
    final t = await src.nextToken();
    expect(_hex32.hasMatch(t.token), isTrue);
    // window-aligned expiry
    expect(t.expiresAt.isAfter(now), isTrue);
    expect(t.expiresAt.difference(t.issuedAt).inMinutes <= 15, isTrue);
  });

  test('never throws when the fetch fails; yields a random token', () async {
    final now = day.add(const Duration(minutes: 20));
    final src = BatchTokenSource(
      fetchBatch: (d, w) async => throw StateError('network down'),
      now: () => now,
    );
    final t = await src.nextToken();
    expect(_hex32.hasMatch(t.token), isTrue);
  });

  test('drops malformed batch rows and falls back instead of throwing',
      () async {
    final now = day.add(const Duration(minutes: 20));
    final src = BatchTokenSource(
      fetchBatch: (d, w) async => [
        BatchSlot(
          token: 'short',
          validFrom: day,
          validUntil: day.add(const Duration(hours: 1)),
        ),
        BatchSlot(
          token: _repeat('a', 34),
          validFrom: day,
          validUntil: day.add(const Duration(hours: 1)),
        ),
      ],
      now: () => now,
    );

    final token = await src.nextToken();

    expect(_hex32.hasMatch(token.token), isTrue);
    expect(token.token, isNot(_repeat('a', 32)));
    expect(src.slots, isEmpty);
  });

  test('shouldRotate: true when null or within grace of expiry', () {
    var now = day.add(const Duration(minutes: 20));
    final src = BatchTokenSource(
      fetchBatch: (d, w) async => _dayBatch(d, w),
      now: () => now,
    );
    expect(src.shouldRotate(null), isTrue);
    final slot1 = _dayBatch(day, 15)[1]; // expires at 32 min
    final tok = EphemeralToken(
      token: slot1.token,
      epochSeconds: slot1.validFrom.millisecondsSinceEpoch ~/ 1000,
      issuedAt: slot1.validFrom,
      expiresAt: slot1.validUntil,
    );
    now = day.add(const Duration(minutes: 20));
    expect(src.shouldRotate(tok), isFalse); // 12 min left
    now = day.add(const Duration(minutes: 31, seconds: 30)); // <1 min left
    expect(src.shouldRotate(tok), isTrue);
  });
}
