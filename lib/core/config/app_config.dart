import 'package:flutter_dotenv/flutter_dotenv.dart';

/// App-wide feature flags and product constants from `.env`.
///
/// Encounter reveal delay (Rahul 2026-07-08):
///   Production: people appear on Encounters tab after **4 hours** minimum.
///   Testing: set `ENCOUNTER_REVEAL_DELAY_HOURS=0` for instant reveal.
class AppConfig {
  AppConfig._();

  /// `--dart-define=KEY=value` wins (CI/release); then dotenv.
  static String _dartDefine(String key) => switch (key) {
        'SUPABASE_URL' => const String.fromEnvironment('SUPABASE_URL'),
        'SUPABASE_PUBLISHABLE_KEY' =>
          const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
        'SUPABASE_ANON_KEY' =>
          const String.fromEnvironment('SUPABASE_ANON_KEY'),
        'INRANGE_HMAC_SECRET' =>
          const String.fromEnvironment('INRANGE_HMAC_SECRET'),
        'INRANGE_USER_ID_SECRET' =>
          const String.fromEnvironment('INRANGE_USER_ID_SECRET'),
        'ENCOUNTER_REVEAL_DELAY_HOURS' =>
          const String.fromEnvironment('ENCOUNTER_REVEAL_DELAY_HOURS'),
        'INRANGE_ENABLE_FGS' =>
          const String.fromEnvironment('INRANGE_ENABLE_FGS'),
        'INRANGE_PREFER_SERVER' =>
          const String.fromEnvironment('INRANGE_PREFER_SERVER'),
        'AUTH_REDIRECT_URL' =>
          const String.fromEnvironment('AUTH_REDIRECT_URL'),
        'GOOGLE_WEB_CLIENT_ID' =>
          const String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
        'FCM_MOCK_TOKEN' => const String.fromEnvironment('FCM_MOCK_TOKEN'),
        _ => '',
      };

  static String _env(String key) {
    final defined = _dartDefine(key).trim();
    if (defined.isNotEmpty) return defined;
    return dotenv.maybeGet(key)?.trim() ?? '';
  }

  static String get supabaseUrl => _env('SUPABASE_URL');

  static String get supabaseAnonKey {
    final k = _env('SUPABASE_PUBLISHABLE_KEY');
    if (k.isNotEmpty) return k;
    return _env('SUPABASE_ANON_KEY');
  }

  // No hardcoded fallback — missing secret must not silently degrade to a
  // value embedded in the APK. BeaconService refuses to advertise when empty.
  static String get hmacSecret => _env('INRANGE_HMAC_SECRET');

  static String get userIdSecret => _env('INRANGE_USER_ID_SECRET');

  /// True when both crypto secrets are present. When false, the beacon cannot
  /// safely advertise (forged tokens would be trivial).
  static bool isUsableSecret(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.length < 32) return false;
    return !normalized.contains('replace-me') &&
        !normalized.contains('placeholder') &&
        !normalized.startsWith('your-') &&
        !normalized.startsWith('test-') &&
        !normalized.contains('example');
  }

  static bool get hasCryptoSecrets =>
      isUsableSecret(hmacSecret) && isUsableSecret(userIdSecret);

  /// Hours after first mutual BLE sighting before a person appears on
  /// the Encounters tab. 0 = instant (test mode). Production target is 4.
  static double get encounterRevealDelayHours {
    final parsed = double.tryParse(_env('ENCOUNTER_REVEAL_DELAY_HOURS')) ?? 4;
    return parsed.clamp(0, 168).toDouble();
  }

  static Duration get encounterRevealDelay {
    final h = encounterRevealDelayHours;
    if (h <= 0) return Duration.zero;
    return Duration(milliseconds: (h * 3600 * 1000).round());
  }

  static bool get isInstantEncounters => encounterRevealDelay == Duration.zero;

  /// Whether Supabase URL looks real (not the placeholder).
  static bool get hasRealSupabase {
    final url = supabaseUrl;
    final key = supabaseAnonKey;
    final uri = Uri.tryParse(url);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        key.length >= 20 &&
        !url.contains('YOUR-PROJECT-REF') &&
        !key.contains('YOUR-') &&
        !key.contains('YOUR_PUBLISHABLE') &&
        !key.toLowerCase().contains('placeholder');
  }

  /// Foreground service (second Flutter engine) — heavy on Galaxy S9.
  /// Off by default for dual-phone BLE tests; enable for background beacon later.
  static bool get enableForegroundService {
    final raw = (_env('INRANGE_ENABLE_FGS').isEmpty
            ? 'false'
            : _env('INRANGE_ENABLE_FGS'))
        .toLowerCase();
    return raw == 'true' || raw == '1' || raw == 'yes';
  }

  /// Prefer server feeds when online; always fall back to local SQLite/BLE.
  static bool get preferServerFeeds {
    final raw = (_env('INRANGE_PREFER_SERVER').isEmpty
            ? 'true'
            : _env('INRANGE_PREFER_SERVER'))
        .toLowerCase();
    return raw != 'false' && raw != '0' && raw != 'no';
  }

  /// Mock FCM token for offline testing of register_push_token path.
  static String? get mockFcmToken {
    final t = _env('FCM_MOCK_TOKEN');
    if (t.isEmpty || t.startsWith('YOUR')) return null;
    return t;
  }

  /// Deep link / OAuth redirect scheme (must match Android/iOS intent filters).
  static String get authRedirectUrl => _env('AUTH_REDIRECT_URL').isEmpty
      ? 'io.inrange.app://login-callback'
      : _env('AUTH_REDIRECT_URL');

  /// Google Web client ID (optional; for native Google Sign-In later).
  static String? get googleWebClientId {
    final id = _env('GOOGLE_WEB_CLIENT_ID');
    if (id.isEmpty || id.startsWith('YOUR')) return null;
    return id;
  }

  static String backendModeLabel() {
    if (hasRealSupabase) return 'Cloud connected';
    return 'Local / offline mode';
  }
}
