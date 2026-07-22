import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:in_range/app_root.dart';
import 'package:in_range/core/session/app_session.dart';
import 'package:in_range/features/consent/consent_gate.dart';
import 'package:in_range/features/consent/consent_screen.dart';
import 'package:in_range/features/profile/profile_setup_screen.dart';

/// Regressions from the 2026-07-22 device audit: the consent gate must sit
/// BEFORE profile setup, and must re-arm when the signed-in account changes
/// within one process.

class _TestSession extends SessionController {
  _TestSession(super.prefs);
  void put(AppSession s) => state = s;
}

AppSession _session({required String? uid, bool profileComplete = false}) =>
    AppSession(
      onboardingComplete: true,
      signedIn: uid != null,
      profileComplete: profileComplete,
      paused: false,
      userId: uid,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    dotenv.testLoad(fileInput: '''
SUPABASE_URL=
SUPABASE_PUBLISHABLE_KEY=
INRANGE_USER_ID_SECRET=
INRANGE_HMAC_SECRET=
''');
  });

  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Widget app({required bool consentRequired, required AppSession session}) =>
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          sessionControllerProvider
              .overrideWith((ref) => _TestSession(prefs)..put(session)),
          consentRequiredProvider.overrideWith((ref) async => consentRequired),
        ],
        child: const MaterialApp(home: AppRoot()),
      );

  testWidgets('consent gate sits BEFORE profile setup', (tester) async {
    await tester.pumpWidget(
      app(consentRequired: true, session: _session(uid: 'user-a')),
    );
    await tester.pumpAndSettle();
    // Photos / orientation / DOB must not be collectable before consent.
    expect(find.byType(ConsentScreen), findsOneWidget);
    expect(find.byType(ProfileSetupScreen), findsNothing);
  });

  testWidgets('satisfied consent falls through to profile setup',
      (tester) async {
    await tester.pumpWidget(
      app(consentRequired: false, session: _session(uid: 'user-a')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ConsentScreen), findsNothing);
    expect(find.byType(ProfileSetupScreen), findsOneWidget);
  });

  test('consentRequiredProvider re-evaluates when the account changes', () async {
    // The original bug: one cached result per process, so switching to an
    // account with zero consents sailed past the gate until an app restart.
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      sessionControllerProvider
          .overrideWith((ref) => _TestSession(prefs)..put(_session(uid: 'a'))),
    ]);
    addTearDown(container.dispose);

    final events = <AsyncValue<bool>>[];
    container.listen(consentRequiredProvider, (_, next) => events.add(next),
        fireImmediately: true);
    await container.read(consentRequiredProvider.future);
    final before = events.length;

    (container.read(sessionControllerProvider.notifier) as _TestSession)
        .put(_session(uid: 'b'));
    await container.read(consentRequiredProvider.future);

    expect(events.length, greaterThan(before),
        reason: 'uid change must invalidate the cached consent decision');
  });
}
