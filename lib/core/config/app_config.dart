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
        'INRANGE_CALIB_SCAN' =>
          const String.fromEnvironment('INRANGE_CALIB_SCAN'),
        'INRANGE_SCAN_LEGACY_ONLY' =>
          const String.fromEnvironment('INRANGE_SCAN_LEGACY_ONLY'),
        'INRANGE_SCAN_RESTART_MINUTES' =>
          const String.fromEnvironment('INRANGE_SCAN_RESTART_MINUTES'),
        'INRANGE_SUBTLE_WAKE' =>
          const String.fromEnvironment('INRANGE_SUBTLE_WAKE'),
        'INRANGE_LOCATION_RESIDENCY' =>
          const String.fromEnvironment('INRANGE_LOCATION_RESIDENCY'),
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

  /// iOS subtle-wake tiers (SLC, venue regions, silent push): the low-power
  /// wake net that turns co-location hints into bounded BLE bursts while the
  /// phone is dark. Off by default.
  ///
  /// Must be read here — NOT via dotenv directly. Release builds load only
  /// `.env.example` (both flags false) into dotenv; the real values arrive by
  /// `--dart-define`, which this getter honors first. A direct dotenv read is
  /// silently false in every release build (audit 2026-07-25 round 3).
  static bool get subtleWake {
    final raw = (_env('INRANGE_SUBTLE_WAKE').isEmpty
            ? 'false'
            : _env('INRANGE_SUBTLE_WAKE'))
        .toLowerCase();
    return raw == 'true' || raw == '1' || raw == 'yes';
  }

  /// iOS location residency: hold a foreground-started location session while
  /// the beacon is on, so the process is not suspended and app-owned timers
  /// (scan restarts, flushes, advert cycling) keep firing with the screen dark.
  ///
  /// OFF by default, and it must stay that way until measured. Two open items:
  ///
  ///  1. It does NOT give foreground BLE semantics. Background scanning stays
  ///     duty-cycled and duplicate discoveries stay coalesced regardless of
  ///     suspension state. The hypothesis worth benching is narrower — that
  ///     restarting scan sessions is what defeats coalescing, and those
  ///     restarts are timer-driven, so residency raises sample cadence. Prove
  ///     it with a same-binary A/B on didDiscover / GATT / connected-RSSI
  ///     counts, not Dart heartbeats. See docs/IOS_LOCATION_RESIDENCY_REVIEW.
  ///  2. It couples location to the beacon toggle, which contradicts the
  ///     "beacon is a pure BLE switch" owner decision (beacon_screen.dart:26).
  ///     That is an owner call, not an engineering one.
  static bool get locationResidency {
    final raw = (_env('INRANGE_LOCATION_RESIDENCY').isEmpty
            ? 'false'
            : _env('INRANGE_LOCATION_RESIDENCY'))
        .toLowerCase();
    return raw == 'true' || raw == '1' || raw == 'yes';
  }

  /// Calibration scan mode: low-latency scanning for dense per-advert RSSI
  /// during range walks. Battery-heavy — leave off outside field tests.
  static bool get calibScanMode {
    final raw = (_env('INRANGE_CALIB_SCAN').isEmpty
            ? 'false'
            : _env('INRANGE_CALIB_SCAN'))
        .toLowerCase();
    return raw == 'true' || raw == '1' || raw == 'yes';
  }

  // ===== BLE scan A/B arms (2026-07-27 walk) =============================
  //
  // Both of these shipped as fixed constants in e5d40e4 (findings E1 and D7 of
  // the 2026-07-26 prior-art review), and both were originally recommended
  // MEASURE-FIRST. Shipping them together destroyed the baseline for the two
  // walk instruments that existed to prove the effects are real on THIS
  // hardware: W9's advert-gap histogram (E1's ~4 s Samsung dual-PHY blind
  // block) and the mid-window duty-cycle collapse (D7). With both already
  // fixed, tomorrow's histogram can only show the gaps are *absent* — which is
  // equally consistent with "the fix works" and with "the effect never existed
  // on a Galaxy S9". A flag per arm recovers the comparison: flip ONE handset
  // to the old values and walk the two side by side.
  //
  // Defaults are the NEW (fixed) values, so a plain build and a release build
  // behave exactly as e5d40e4 shipped. Resolved values are logged unconditioned
  // on INRANGE_CALIB_SCAN at every scan start (beacon_service.dart) — arm
  // attribution has to work in a normal build too, or a log cannot be assigned
  // to a leg after the fact.

  /// Scan the legacy 1M PHY only (finding E1). Default **true** = the fix.
  ///
  /// `false` restores flutter_blue_plus's own default (flutter_blue_plus.dart:281
  /// → FlutterBluePlusPlugin.java:549-552 sets PHY_LE_ALL_SUPPORTED +
  /// setLegacy(false)), i.e. the pre-2026-07-26 both-PHY scan whose cost
  /// upstream #938 reports as 4-second time slices of total blindness on some
  /// Samsung handsets. PHY time-slicing is a property of the SCANNER, not of the
  /// peers, so two phones scanning the same room with different values of this
  /// flag is a valid controlled experiment — the A leg's W9 histogram should
  /// show a ~4 s mode the B leg's does not.
  ///
  /// Android-only in effect (iOS CoreBluetooth exposes no PHY choice), but read
  /// on both so a walk log states the arm on either handset.
  static bool get scanLegacyPhyOnly {
    final raw = (_env('INRANGE_SCAN_LEGACY_ONLY').isEmpty
            ? 'true'
            : _env('INRANGE_SCAN_LEGACY_ONLY'))
        .toLowerCase();
    return raw != 'false' && raw != '0' && raw != 'no';
  }

  /// Minutes between scan restarts (finding D7). Default **8** = the fix; the
  /// pre-2026-07-26 value was 25.
  ///
  /// AOSP force-downgrades a long-running filtered scan after 10 min on
  /// Android 14+ and makes it sticky for that scanner's life
  /// (ScanManager.java:1550-1578, AppScanStats.java:801-810), which is why 8
  /// won. The 30-minute figure the old comment cited is real and sourced — a
  /// quoted paper in docs/research/ble-radio-optimization.md:19-21 — it is just
  /// the ≤13 behaviour. Set 25 on one handset to measure whether the mid-window
  /// duty-cycle collapse is observable on the S9s at all.
  ///
  /// Clamped 1–60: below 1 the AOSP scan quota (5 registrations per 30 s) would
  /// dominate, above 60 the restart stops being upkeep against the demotion it
  /// exists to prevent.
  static int get scanRestartMinutes {
    final parsed = int.tryParse(_env('INRANGE_SCAN_RESTART_MINUTES')) ?? 8;
    return parsed.clamp(1, 60);
  }

  static Duration get scanRestartInterval =>
      Duration(minutes: scanRestartMinutes);

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
