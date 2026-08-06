// E-B1 widget proof: a REAL SwipeFeed pass, driven through the actual widget,
// routes the card's evidence-backed radio ALIAS (never its dismissal id) to the
// real BeaconService.dropPeer platform seam — and a server card's encounter_id
// never reaches that seam. This exercises the installed pass path end to end:
// SwipeFeed._doPass → reportPassTeardown → BeaconService.dropPeer → the
// io.inrange/background_beacon channel. No test-only shortcut around the widget.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_range/core/session/app_session.dart';
import 'package:in_range/features/encounters/encounters_provider.dart';
import 'package:in_range/features/encounters/local_encounter_store.dart';
import 'package:in_range/features/encounters/swipe_feed.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A local store seeded with fixed encounters (no SQLite / BLE plugins).
class _SeededLocalStore extends LocalEncounterStore {
  _SeededLocalStore(List<LocalEncounter> seed) : super.empty() {
    state = {for (final e in seed) e.correlationId: e};
  }
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Reveal delay 0 so a just-seen encounter is immediately visible; empty
    // Supabase ⇒ hasRealSupabase false ⇒ local BLE cards drive the deck.
    dotenv.testLoad(fileInput: '''
SUPABASE_URL=
SUPABASE_PUBLISHABLE_KEY=
INRANGE_USER_ID_SECRET=
INRANGE_HMAC_SECRET=
ENCOUNTER_REVEAL_DELAY_HOURS=0
''');
  });

  const channel = MethodChannel('io.inrange/background_beacon');
  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'dropPeer') {
        // A committed hit: lease torn, a raw session reaped, one role closed.
        return <String, dynamic>{
          'lookupHit': true,
          'leaseEnded': true,
          'rawSessionsReaped': 1,
          'rolesClosed': <String>['outbound'],
        };
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> pumpFeed(WidgetTester tester, List<LocalEncounter> seed) async {
    // dropPeer is gated to iOS (BeaconService.dropPeer) — the installed target.
    // Reset happens in each test's finally, before the framework's invariant check.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          localEncounterStoreProvider.overrideWith((ref) => _SeededLocalStore(seed)),
          // No Supabase in a widget test — an empty server deck.
          myEncountersProvider.overrideWith((ref) async => const []),
          // Suppress the new-encounter local notification (the plugin isn't
          // registered in a widget test); the deck itself is unaffected.
          newEncounterCountProvider.overrideWithValue(0),
        ],
        child: const MaterialApp(home: Scaffold(body: SwipeFeed())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  MethodCall? dropCall(List<MethodCall> cs) {
    for (final c in cs) {
      if (c.method == 'dropPeer') return c;
    }
    return null;
  }

  testWidgets('pass on a fresh local card sends the radio ALIAS to native dropPeer',
      (tester) async {
    final fresh = LocalEncounter(
      correlationId: 'feedface',        // becomes the card's radioAlias
      firstSeenAt: DateTime.now(),      // reveal delay 0 ⇒ visible now
      lastSeenAt: DateTime.now(),       // fresh ⇒ alias within TTL
      bestRssi: -50,
      rangeType: 'feet_10',
    );
    try {
      await pumpFeed(tester, [fresh]);

      // The pass control is the grey close button (SwipeFeed._doPass).
      expect(find.byIcon(Icons.close), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final drop = dropCall(calls);
      expect(drop, isNotNull, reason: 'the real widget pass reached native dropPeer');
      expect(drop!.arguments, 'feedface',
          reason: 'the evidence-backed radioAlias crosses — never the card id');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('pass on a STALE local card is a miss — native dropPeer is still '
      'called with the alias but no lease-tear is reported', (tester) async {
    // A stale alias (seen > 15 min ago) is still ATTEMPTED (freshness is judged
    // natively), but the native miss is surfaced, never fabricated as a tear.
    final stale = LocalEncounter(
      correlationId: 'stale00',
      firstSeenAt: DateTime.now().subtract(const Duration(minutes: 30)),
      lastSeenAt: DateTime.now().subtract(const Duration(minutes: 30)),
      bestRssi: -50,
      rangeType: 'feet_10',
    );
    // Native reports NO hit for this alias.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'dropPeer') {
        return <String, dynamic>{
          'lookupHit': false,
          'leaseEnded': false,
          'rawSessionsReaped': 0,
          'rolesClosed': <String>[],
        };
      }
      return null;
    });
    try {
      await pumpFeed(tester, [stale]);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final drop = dropCall(calls);
      expect(drop, isNotNull, reason: 'a stale alias is still attempted natively');
      expect(drop!.arguments, 'stale00',
          reason: 'the alias crosses; the native miss (not a fabricated tear) is trusted');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
