import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_range/core/config/app_config.dart';
import 'package:in_range/core/network/supabase_client.dart';
import 'package:in_range/core/session/app_session.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Syncs local profile + photos to Supabase when cloud is live.
class ProfileSyncService {
  bool get cloudReady =>
      AppConfig.hasRealSupabase && InRangeSupabase.clientOrNull != null;

  /// Upsert profile fields via RPC.
  Future<void> syncProfile(AppSession session) async {
    if (!cloudReady || session.userId == null) return;
    final client = InRangeSupabase.client;
    if (client.auth.currentUser == null) return;

    final dob = session.birthYear != null
        ? DateTime(session.birthYear!, 1, 1)
        : null;

    try {
      await client.rpc('upsert_my_profile', params: {
        'p_display_name': session.displayName ?? 'User',
        'p_bio': session.bio,
        'p_dob': dob?.toIso8601String().split('T').first,
        'p_gender': session.gender,
        'p_sexual_preference': session.preference,
        'p_interests': [
          ...session.interests,
          if (session.customInterest != null &&
              session.customInterest!.isNotEmpty)
            session.customInterest!,
        ],
        'p_photo_urls': session.photoPaths.isEmpty ? null : session.photoPaths,
      });
      debugPrint('Profile sync OK');
    } catch (e) {
      debugPrint('Profile sync failed (will retry later): $e');
      rethrow;
    }
  }

  /// Upload local photo files to storage + submit verification for each.
  /// Returns public/storage paths. The caller is responsible for calling
  /// [syncProfile] afterward with the returned paths in the session's
  /// photoPaths (already done in SessionController.finishOnboarding).
  Future<List<String>> uploadPhotos(List<String> localPaths) async {
    if (!cloudReady) return localPaths;
    final client = InRangeSupabase.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return localPaths;

    final uploaded = <String>[];
    for (var i = 0; i < localPaths.length && i < 6; i++) {
      final path = localPaths[i];
      // Already a remote path?
      if (path.startsWith('http') || path.startsWith('$uid/')) {
        uploaded.add(path);
        continue;
      }
      final file = File(path);
      if (!await file.exists()) continue;

      final ext = p.extension(path).replaceFirst('.', '');
      final safeExt = ext.isEmpty ? 'jpg' : ext;
      final storagePath = '$uid/$i-${DateTime.now().millisecondsSinceEpoch}.$safeExt';

      try {
        await client.storage.from('profile_photos').upload(
              storagePath,
              file,
              fileOptions: const FileOptions(
                upsert: true,
                contentType: 'image/jpeg',
              ),
            );

        await client.rpc('submit_photo_for_verification', params: {
          'p_photo_path': storagePath,
          'p_slot_index': i,
        });

        // Store storage path only — bucket is private (migration 0017).
        // Clients resolve display URLs via createSignedUrl.
        uploaded.add(storagePath);
        debugPrint('Photo slot $i uploaded + verification queued path=$storagePath');
      } catch (e) {
        debugPrint('Photo upload slot $i failed: $e');
        uploaded.add(path); // keep local path as fallback
      }
    }
    return uploaded;
  }

  Future<void> setPaused(bool paused) async {
    if (!cloudReady) return;
    try {
      await InRangeSupabase.client.rpc(
        'set_account_paused',
        params: {'p_paused': paused},
      );
    } catch (e) {
      debugPrint('set_account_paused failed: $e');
    }
  }

  Future<void> requestDeletion() async {
    if (!cloudReady) return;
    try {
      await InRangeSupabase.client.rpc('request_account_deletion');
    } catch (e) {
      debugPrint('request_account_deletion failed: $e');
    }
  }

  Future<void> deleteLocationHistory() async {
    if (!cloudReady) return;
    try {
      await InRangeSupabase.client.rpc('delete_my_location_history');
    } catch (e) {
      debugPrint('delete_my_location_history failed: $e');
    }
  }

  Future<void> setIncognito(bool enabled) async {
    if (!cloudReady) return;
    try {
      await InRangeSupabase.client.rpc(
        'set_incognito',
        params: {'p_enabled': enabled},
      );
    } catch (e) {
      debugPrint('set_incognito failed: $e');
      rethrow;
    }
  }
}
