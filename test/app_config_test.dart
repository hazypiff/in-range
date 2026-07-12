import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_range/core/config/app_config.dart';

void main() {
  test('dart defines take precedence over dotenv when requested', () {
    dotenv.testLoad(fileInput: '''
SUPABASE_URL=https://dotenv.example.test
SUPABASE_PUBLISHABLE_KEY=dotenv-publishable-key-1234567890
INRANGE_HMAC_SECRET=dotenv-hmac-secret-0123456789abcdef
INRANGE_USER_ID_SECRET=dotenv-user-secret-0123456789abcdef
ENCOUNTER_REVEAL_DELAY_HOURS=7
''');

    const expectDefines = bool.fromEnvironment('EXPECT_DART_DEFINE');
    if (expectDefines) {
      expect(AppConfig.supabaseUrl, 'https://define.example.test');
      expect(AppConfig.encounterRevealDelayHours, 5);
    } else {
      expect(AppConfig.supabaseUrl, 'https://dotenv.example.test');
      expect(AppConfig.encounterRevealDelayHours, 7);
    }
  });

  test('blank config fails closed with a four-hour reveal default', () {
    dotenv.testLoad(fileInput: '');
    expect(AppConfig.hasRealSupabase, isFalse);
    expect(AppConfig.hasCryptoSecrets, isFalse);
    const expectDefines = bool.fromEnvironment('EXPECT_DART_DEFINE');
    expect(AppConfig.encounterRevealDelayHours, expectDefines ? 5 : 4);
  });

  test('weak and placeholder crypto secrets are rejected', () {
    expect(AppConfig.isUsableSecret('short'), isFalse);
    expect(
      AppConfig.isUsableSecret('replace-me-012345678901234567890123456789'),
      isFalse,
    );
    expect(
      AppConfig.isUsableSecret('79fbc82a9f6048618bd49ccd8a9aedf1'),
      isTrue,
    );
  });
}
