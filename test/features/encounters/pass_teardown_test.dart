import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_range/features/beacon/background_beacon_channel.dart';
import 'package:in_range/features/encounters/local_encounter_store.dart';
import 'package:in_range/features/encounters/pass_teardown.dart';
import 'package:in_range/features/encounters/swipe_card.dart';

/// B1: the actual Dart pass→native teardown path — alias freshness, the
/// structured native result being awaited/propagated, and honest
/// stale-miss/unavailable reporting. Exercises `resolvePassTeardown`, the pure
/// core `_doPass` delegates to, with a recording fake for the native call.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SwipeCard serverCard() => SwipeCard.fromServer({
        'encounter_id': 12345, // a NON-radio id; must never reach dropPeer
        'range_type': 'feet_10',
        'encounter_time': DateTime.now().toIso8601String(),
      });

  SwipeCard localCard({required Duration seenAgo, String corr = 'aabbccddee'}) {
    final seen = DateTime.now().subtract(seenAgo);
    return SwipeCard.fromLocal(LocalEncounter(
      correlationId: corr,
      firstSeenAt: seen,
      lastSeenAt: seen,
      bestRssi: -60,
      rangeType: 'feet_10',
    ));
  }

  group('radioAliasStateAt', () {
    test('server card is always unavailable', () {
      expect(serverCard().radioAliasStateAt(), RadioAliasState.unavailable);
    });

    test('local card seen within TTL is fresh', () {
      expect(localCard(seenAgo: const Duration(minutes: 2)).radioAliasStateAt(),
          RadioAliasState.fresh);
    });

    test('local card seen beyond TTL is stale', () {
      expect(localCard(seenAgo: const Duration(minutes: 20)).radioAliasStateAt(),
          RadioAliasState.stale);
    });
  });

  group('resolvePassTeardown', () {
    test('server card → unavailable and native is NEVER called', () async {
      var called = false;
      final out = await resolvePassTeardown(serverCard(), (alias) async {
        called = true;
        return {'lookupHit': true};
      });
      expect(called, isFalse, reason: 'no alias → must not touch native');
      expect(out.isUnavailable, isTrue);
      expect(out.attempted, isFalse);
      expect(out.tore, isFalse);
      expect(out.summary, contains('unavailable(server-card)'));
    });

    test('fresh card with a live lease → hands the ALIAS (not id) and tears',
        () async {
      String? seenAlias;
      final card = localCard(seenAgo: const Duration(minutes: 1), corr: 'feedface');
      final out = await resolvePassTeardown(card, (alias) async {
        seenAlias = alias;
        return {
          'lookupHit': true,
          'leaseEnded': true,
          'rolesClosed': ['outbound', 'inbound'],
          'rawSessionsReaped': 1,
        };
      });
      expect(seenAlias, 'feedface', reason: 'radioAlias, never card.id');
      expect(out.requested, RadioAliasState.fresh);
      expect(out.tore, isTrue);
      expect(out.isStaleMiss, isFalse);
      expect(out.rolesClosed, containsAll(['outbound', 'inbound']));
      expect(out.summary, contains('teardown-ended'));
    });

    test('stale alias that misses natively → surfaced as a stale miss',
        () async {
      final card = localCard(seenAgo: const Duration(minutes: 30));
      final out = await resolvePassTeardown(card, (alias) async {
        return {'lookupHit': false, 'leaseEnded': false, 'rolesClosed': []};
      });
      expect(out.requested, RadioAliasState.stale);
      expect(out.isStaleMiss, isTrue);
      expect(out.tore, isFalse);
      expect(out.summary, contains('teardown-miss(stale)'));
    });

    test('native unavailable (null result) → not a false success', () async {
      final card = localCard(seenAgo: const Duration(minutes: 1));
      final out = await resolvePassTeardown(card, (alias) async => null);
      expect(out.attempted, isTrue);
      expect(out.nativeAvailable, isFalse);
      expect(out.tore, isFalse);
      expect(out.isStaleMiss, isFalse, reason: 'no native verdict → not a miss');
      expect(out.summary, contains('unavailable(native)'));
    });
  });

  // UI-channel coverage: the REAL platform-channel wrapper the pass path uses
  // (BackgroundBeaconChannel.dropPeer), not an injected fake. Proves the card's
  // radioAlias — never its id — crosses the boundary, and the native structured
  // dict is parsed into the outcome.
  group('resolvePassTeardown over the real platform channel', () {
    const channel = MethodChannel('io.inrange/background_beacon');
    final calls = <MethodCall>[];
    final bb = BackgroundBeaconChannel();
    Map<String, dynamic> reply = const {};

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return reply;
      });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('fresh card → channel dropPeer gets the ALIAS and the hit is parsed',
        () async {
      reply = {
        'lookupHit': true,
        'leaseEnded': true,
        'rolesClosed': ['outbound'],
        'rawSessionsReaped': 1,
      };
      final card = localCard(seenAgo: const Duration(minutes: 1), corr: 'c0ffee11');
      final out = await resolvePassTeardown(card, bb.dropPeer);
      expect(calls.single.method, 'dropPeer');
      expect(calls.single.arguments, 'c0ffee11',
          reason: 'radioAlias crosses the channel, never card.id');
      expect(out.tore, isTrue);
      expect(out.rolesClosed, ['outbound']);
    });

    test('server card → channel is NEVER called (teardown unavailable)',
        () async {
      final out = await resolvePassTeardown(serverCard(), bb.dropPeer);
      expect(calls, isEmpty);
      expect(out.isUnavailable, isTrue);
    });
  });
}
