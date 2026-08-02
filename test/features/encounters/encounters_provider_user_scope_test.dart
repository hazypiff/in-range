import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_range/core/session/app_session.dart';
import 'package:in_range/features/encounters/encounters_provider.dart';
import 'package:in_range/features/encounters/encounters_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestSessionController extends SessionController {
  _TestSessionController(super.preferences);

  void setUser(String? userId) {
    state = userId == null
        ? AppSession.empty
        : AppSession.empty.copyWith(signedIn: true, userId: userId);
  }
}

class _CountingRepository extends EncountersRepository {
  int calls = 0;

  @override
  Future<List<Map<String, dynamic>>> getMyEncounters() async {
    calls++;
    return [
      {'fetch': calls}
    ];
  }
}

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

  test('server encounter cache is scoped to the active account', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = _CountingRepository();
    late _TestSessionController session;
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        sessionControllerProvider.overrideWith((ref) {
          session = _TestSessionController(preferences)..setUser('user-a');
          return session;
        }),
        encountersRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    expect(await container.read(myEncountersProvider.future), [
      {'fetch': 1}
    ]);

    session.setUser('user-b');
    expect(await container.read(myEncountersProvider.future), [
      {'fetch': 2}
    ]);

    session.setUser(null);
    expect(await container.read(myEncountersProvider.future), isEmpty);
    expect(repository.calls, 2, reason: 'signed-out sessions must not query');
  });
}
