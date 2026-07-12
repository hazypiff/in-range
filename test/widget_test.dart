// Widget smoke test: BeaconScreen renders with required Riverpod overrides.
//
// Regression for 559cff9 review: bare ProviderScope crashed on
// localDbProvider / sharedPreferencesProvider UnimplementedError.

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_range/core/session/app_session.dart';
import 'package:in_range/features/beacon/beacon_screen.dart';
import 'package:in_range/features/encounters/local_encounter_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    dotenv.testLoad(fileInput: '''
SUPABASE_URL=
SUPABASE_PUBLISHABLE_KEY=
INRANGE_USER_ID_SECRET=
INRANGE_HMAC_SECRET=
ENCOUNTER_REVEAL_DELAY_HOURS=4
''');
  });

  testWidgets('BeaconScreen renders status card + toggle button',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          // Empty store — no SQLite / BLE platform plugins in widget tests.
          localEncounterStoreProvider.overrideWith(
            (ref) => LocalEncounterStore.empty(),
          ),
        ],
        child: const MaterialApp(home: BeaconScreen()),
      ),
    );
    await tester.pump();

    // AppBar title is "Beacon" (product shell), not marketing tagline.
    expect(find.text('Beacon'), findsOneWidget);
    expect(find.textContaining('Beacon is OFF'), findsOneWidget);
    expect(find.byType(FilledButton), findsWidgets);
    expect(find.textContaining('Turn Beacon On'), findsOneWidget);
  });
}
