import 'package:flutter_test/flutter_test.dart';
import 'package:in_range/features/encounters/swipe_card.dart';

/// H-W5-6 identifier-domain contract (Phase 1): the dismissal `id` and the
/// radio `radioAlias` are SEPARATE domains. A server `encounter_id` must never
/// be usable as a radio alias for native `dropPeer`.
void main() {
  test('server card: id is encounter_id, radioAlias is NULL (teardown unavail)',
      () {
    final c = SwipeCard.fromServer({
      'encounter_id': 12345,
      'range_type': 'feet_10',
      'neighborhood': 'Downtown',
      'other_user_id': 'user-abc',
    });
    expect(c.isServer, isTrue);
    expect(c.id, '12345'); // dismissal key = encounter_id string
    expect(c.radioAlias, isNull,
        reason: 'server feed rows carry no radio token → no alias');
  });

  test('local-style card: radioAlias carries the token, distinct from any id',
      () {
    const token = '0123456789abcdef0123456789abcdef';
    final c = SwipeCard(
      id: token, // local dismissal key == correlation token
      radioAlias: token, // and the SAME token is the valid radio alias
      displayLabel: 'x',
      neighborhood: 'y',
      rangeType: 'feet_10',
      isServer: false,
    );
    expect(c.radioAlias, token);
    expect(c.radioAlias!.length, 32); // a real 16-byte token hex
  });

  test('server encounter_id is never a 32-hex radio token by construction', () {
    final c = SwipeCard.fromServer({'encounter_id': 999});
    // The alias-keyed native dropPeer must not receive this. The UI guards on
    // radioAlias != null; here it is null, so dropPeer is never called.
    expect(c.radioAlias, isNull);
    // And the dismissal id is decidedly not a token hex.
    expect(c.id.length, isNot(32));
  });
}
