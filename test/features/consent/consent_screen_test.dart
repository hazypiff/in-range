import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:in_range/features/consent/consent_screen.dart';

/// Pins the properties that make this screen legally usable as consent.
///
/// NJDPA excludes pre-ticked boxes and dark patterns from what counts as
/// consent, and the FTC's X-Mode/InMarket orders require location consent to be
/// unbundled and purpose-scoped. Those are UI invariants, so they are asserted
/// here rather than left to review.
///
/// With no cloud backend configured, ConsentService.current() returns an empty
/// map — which is exactly the first-run state these tests need.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    dotenv.testLoad(fileInput: '''
SUPABASE_URL=
SUPABASE_PUBLISHABLE_KEY=
INRANGE_USER_ID_SECRET=
INRANGE_HMAC_SECRET=
''');
  });

  Future<void> pump(WidgetTester tester, {bool manage = false}) async {
    // The consent list is a lazy ListView; in the default 800x600 test viewport
    // only the first few tiles are ever built. Give it a tall surface so every
    // purpose is realised and assertions about "all of them" are meaningful.
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: ConsentScreen(manage: manage)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('nothing is pre-checked', (tester) async {
    await pump(tester);

    final switches = tester.widgetList<SwitchListTile>(
      find.byType(SwitchListTile),
    );

    expect(switches, isNotEmpty, reason: 'no consent toggles rendered');
    for (final s in switches) {
      expect(
        s.value,
        isFalse,
        reason: 'a consent toggle was pre-checked; pre-ticked boxes are not '
            'consent under NJDPA and are a named dark pattern',
      );
    }
  });

  testWidgets('one toggle per purpose, and no bundled accept-all',
      (tester) async {
    await pump(tester);

    // Four OFFERED purposes -> four independent toggles. background_location
    // is deliberately not offered: no shipped feature collects it, and asking
    // consent for non-existent processing is over-collection by another name.
    expect(find.byType(SwitchListTile), findsNWidgets(4));

    for (final label in const ['accept all', 'agree to all', 'allow all']) {
      expect(
        find.textContaining(RegExp(label, caseSensitive: false)),
        findsNothing,
        reason: 'a bundled accept-all control defeats unbundled consent',
      );
    }
  });

  testWidgets('continue stays disabled until the required purposes are on',
      (tester) async {
    await pump(tester);

    final continueButton = find.widgetWithText(FilledButton, 'Continue');
    expect(continueButton, findsOneWidget);
    expect(
      tester.widget<FilledButton>(continueButton).onPressed,
      isNull,
      reason: 'Continue was enabled before any consent was given',
    );

    // Turn on the required ones, one by one — Continue must stay disabled
    // until the LAST of them is on.
    for (final title in const [
      'Who you are and who you want to meet',
      'Bluetooth proximity',
      'Precise location',
      'Profile photos',
    ]) {
      expect(
        tester.widget<FilledButton>(continueButton).onPressed,
        isNull,
        reason: 'Continue enabled before every required purpose was on',
      );
      await tester.tap(find.widgetWithText(SwitchListTile, title));
      await tester.pumpAndSettle();
    }

    expect(
      tester.widget<FilledButton>(continueButton).onPressed,
      isNotNull,
      reason: 'Continue stayed disabled with every required purpose on',
    );

    // Nothing was switched on implicitly along the way.
    final on = tester
        .widgetList<SwitchListTile>(find.byType(SwitchListTile))
        .where((s) => s.value)
        .length;
    expect(on, 4, reason: 'a purpose was switched on implicitly');
  });

  testWidgets('all three policy documents are surfaced', (tester) async {
    await pump(tester);

    // MHMDA requires the consumer-health-data policy to be a separate,
    // separately-linked document — not a section of the main policy.
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Health Data Privacy'), findsOneWidget);
    expect(find.text('Terms of Use'), findsOneWidget);
  });

  testWidgets(
      'manage mode has no save gate, so withdrawal is as easy as '
      'granting', (tester) async {
    await pump(tester, manage: true);

    expect(find.byType(SwitchListTile), findsNWidgets(4));
    expect(
      find.widgetWithText(FilledButton, 'Continue'),
      findsNothing,
      reason: 'withdrawal must not be gated behind a save button that '
          'granting did not require (GDPR Art. 7(3))',
    );
  });
}
