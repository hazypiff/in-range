import 'package:flutter_test/flutter_test.dart';
import 'package:in_range/features/encounters/swipe_card.dart';

void main() {
  Map<String, dynamic> serverRow({
    int? sessions,
    int? days,
    String? firstSeen,
  }) =>
      {
        'encounter_id': 42,
        'other_user_id': 'u1',
        'neighborhood': 'Near you',
        'range_type': 'feet_10',
        'encounter_time': '2026-07-15T20:00:00Z',
        if (sessions != null) 'session_count': sessions,
        if (days != null) 'distinct_day_count': days,
        if (firstSeen != null) 'first_seen_at': firstSeen,
      };

  group('SwipeCard recurrence', () {
    test('first meeting is not recurring, no label', () {
      final c = SwipeCard.fromServer(serverRow(sessions: 1, days: 1));
      expect(c.isRecurring, isFalse);
      expect(c.recurrenceLabel, isNull);
    });

    test('multiple crossings same day', () {
      final c = SwipeCard.fromServer(serverRow(sessions: 3, days: 1));
      expect(c.isRecurring, isTrue);
      expect(c.recurrenceLabel, 'Crossed paths 3 times');
    });

    test('multiple crossings across days', () {
      final c = SwipeCard.fromServer(serverRow(sessions: 5, days: 3));
      expect(c.recurrenceLabel, 'Crossed paths 5 times · 3 days');
    });

    test('missing counters default to a single first meeting', () {
      final c = SwipeCard.fromServer(serverRow());
      expect(c.sessionCount, 1);
      expect(c.distinctDayCount, 1);
      expect(c.isRecurring, isFalse);
    });

    test('parses first_seen_at when present', () {
      final c = SwipeCard.fromServer(
          serverRow(sessions: 2, days: 1, firstSeen: '2026-07-10T18:30:00Z'));
      expect(c.firstSeenAt, DateTime.utc(2026, 7, 10, 18, 30));
    });
  });
}
