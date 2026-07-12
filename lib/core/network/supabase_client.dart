import 'package:flutter/foundation.dart';
import 'package:in_range/core/config/app_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Centralized Supabase client.
/// Initialize once in main() before runApp.
class InRangeSupabase {
  static bool _initialized = false;

  static bool get isInitialized => _initialized;

  static SupabaseClient get client {
    if (!_initialized) {
      throw StateError(
        'InRangeSupabase not initialized. Call init() in main().',
      );
    }
    return Supabase.instance.client;
  }

  /// Safe client access — null when not initialized or placeholder keys.
  static SupabaseClient? get clientOrNull {
    if (!_initialized || !AppConfig.hasRealSupabase) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  static Future<void> init({
    required String url,
    required String publishableKey,
  }) async {
    // Always initialize so auth APIs exist; hasRealSupabase gates network use.
    await Supabase.initialize(
      url: url,
      publishableKey: publishableKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
    _initialized = true;
    debugPrint('Supabase init: real=${AppConfig.hasRealSupabase}');
  }

  static Future<void> initFromConfig() async {
    await init(
      url: AppConfig.supabaseUrl.isEmpty
          ? 'https://YOUR-PROJECT-REF.supabase.co'
          : AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey.isEmpty
          ? 'YOUR-PUBLISHABLE-KEY'
          : AppConfig.supabaseAnonKey,
    );
  }
}
