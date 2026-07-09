// Basic widget smoke test for the In Range app.
//
// This test verifies that the BeaconScreen renders without throwing,
// including the beacon status card, range dropdown, and toggle button.

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_range/features/beacon/beacon_screen.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Load .env if present; otherwise stub minimal values.
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      dotenv.testLoad(fileInput: '''
SUPABASE_URL=https://test.supabase.co
SUPABASE_PUBLISHABLE_KEY=test-key
INRANGE_USER_ID_SECRET=test-secret
INRANGE_HMAC_SECRET=test-hmac
''');
    }
  });

  testWidgets('BeaconScreen renders status card + toggle button',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: BeaconScreen())),
    );
    await tester.pump();

    // The beacon status card should render with the In Range title.
    expect(find.text('In Range'), findsOneWidget);
    // The toggle button should be present.
    expect(find.byType(FilledButton), findsOneWidget);
  });
}
