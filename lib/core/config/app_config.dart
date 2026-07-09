import 'package:flutter_dotenv/flutter_dotenv.dart';

/// App-wide feature flags and product constants from `.env`.
///
/// Encounter reveal delay (Rahul 2026-07-08):
///   Production: people appear on Encounters tab after **4 hours** minimum.
///   Testing: set `ENCOUNTER_REVEAL_DELAY_HOURS=0` for instant reveal.
class AppConfig {
  AppConfig._();

  static String get supabaseUrl =>
      dotenv.maybeGet('SUPABASE_URL')?.trim() ?? '';

  static String get supabaseAnonKey =>
      dotenv.maybeGet('SUPABASE_PUBLISHABLE_KEY')?.trim() ??
      dotenv.maybeGet('SUPABASE_ANON_KEY')?.trim() ??
      '';

  // No hardcoded fallback — a missing secret must not silently degrade to a
  // value embedded in the APK. Returns empty string when unset; BeaconService
  // refuses to advertise when empty (safety, not silent fallback).
  static String get hmacSecret =>
      dotenv.maybeGet('INRANGE_HMAC_SECRET')?.trim() ?? '';

  static String get userIdSecret =>
      dotenv.maybeGet('INRANGE_USER_ID_SECRET')?.trim() ?? '';

  /// True when both crypto secrets are present. When false, the beacon cannot
  /// safely advertise (forged tokens would be trivial).
  static bool get hasCryptoSecrets =>
      hmacSecret.isNotEmpty && userIdSecret.isNotEmpty;

  /// Hours after first mutual BLE sighting before a person appears on
  /// the Encounters tab. 0 = instant (test mode). Production target is 4.
  static double get encounterRevealDelayHours {
    final raw = dotenv.maybeGet('ENCOUNTER_REVEAL_DELAY_HOURS') ?? '0';
    return double.tryParse(raw.trim()) ?? 0;
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
    return url.isNotEmpty &&
        key.isNotEmpty &&
        !url.contains('YOUR-PROJECT-REF') &&
        !key.contains('YOUR-') &&
        !key.contains('YOUR_PUBLISHABLE') &&
        url.startsWith('https://');
  }

  /// Foreground service (second Flutter engine) — heavy on Galaxy S9.
  /// Off by default for dual-phone BLE tests; enable for background beacon later.
  static bool get enableForegroundService {
    final raw =
        (dotenv.maybeGet('INRANGE_ENABLE_FGS') ?? 'false').toLowerCase();
    return raw == 'true' || raw == '1' || raw == 'yes';
  }

  /// Prefer server feeds when online; always fall back to local SQLite/BLE.
  static bool get preferServerFeeds {
    final raw =
        (dotenv.maybeGet('INRANGE_PREFER_SERVER') ?? 'true').toLowerCase();
    return raw != 'false' && raw != '0' && raw != 'no';
  }

  /// Mock FCM token for offline testing of register_push_token path.
  static String? get mockFcmToken {
    final t = dotenv.maybeGet('FCM_MOCK_TOKEN')?.trim();
    if (t == null || t.isEmpty || t.startsWith('YOUR')) return null;
    return t;
  }

  /// Deep link / OAuth redirect scheme (must match Android/iOS intent filters).
  static String get authRedirectUrl =>
      dotenv.maybeGet('AUTH_REDIRECT_URL')?.trim() ??
      'io.inrange.app://login-callback';

  /// Google Web client ID (optional; for native Google Sign-In later).
  static String? get googleWebClientId {
    final id = dotenv.maybeGet('GOOGLE_WEB_CLIENT_ID')?.trim();
    if (id == null || id.isEmpty || id.startsWith('YOUR')) return null;
    return id;
  }

  static String backendModeLabel() {
    if (hasRealSupabase) return 'Cloud connected';
    return 'Local / offline mode';
  }
}
