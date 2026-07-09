import 'package:flutter/foundation.dart';
import 'package:in_range/core/config/app_config.dart';
import 'package:in_range/core/network/supabase_client.dart';

/// Resolves profile photo paths for private `profile_photos` bucket.
class PhotoUrlService {
  static final _cache = <String, ({String url, DateTime exp})>{};

  /// Returns a displayable URL for network Image widgets.
  /// - http(s): returned as-is (legacy public URLs)
  /// - storage path: signed URL (1h)
  /// - local filesystem: returned as-is (Image.file handles)
  static Future<String?> resolve(String? pathOrUrl) async {
    if (pathOrUrl == null || pathOrUrl.isEmpty) return null;
    if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
      return pathOrUrl;
    }
    if (pathOrUrl.startsWith('/') || pathOrUrl.contains(r'\')) {
      // Local absolute path
      return pathOrUrl;
    }
    if (!AppConfig.hasRealSupabase) return pathOrUrl;

    final cached = _cache[pathOrUrl];
    if (cached != null && cached.exp.isAfter(DateTime.now())) {
      return cached.url;
    }

    try {
      final client = InRangeSupabase.clientOrNull;
      if (client == null) return null;
      final signed = await client.storage
          .from('profile_photos')
          .createSignedUrl(pathOrUrl, 3600);
      _cache[pathOrUrl] = (
        url: signed,
        exp: DateTime.now().add(const Duration(minutes: 50)),
      );
      return signed;
    } catch (e) {
      debugPrint('PhotoUrlService.resolve failed: $e');
      return null;
    }
  }

  static void clearCache() => _cache.clear();
}
