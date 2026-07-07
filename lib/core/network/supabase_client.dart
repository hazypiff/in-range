import 'package:supabase_flutter/supabase_flutter.dart';

/// Centralized Supabase client.
/// Initialize once in main() before runApp:
///   await Supabase.initialize(url: 'https://xxx.supabase.co', anonKey: 'ey...');
class InRangeSupabase {
  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> init({
    required String url,
    required String anonKey,
  }) async {
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
      // Add auth options, realtime, etc. as needed
    );
  }
}
