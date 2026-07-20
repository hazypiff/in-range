import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_range/core/config/app_config.dart';
import 'package:in_range/core/network/supabase_client.dart';
import 'package:in_range/shared/services/media_hash_service.dart';
import 'package:in_range/core/privacy/image_sanitizer.dart';
import 'package:in_range/core/session/app_session.dart';
import 'package:in_range/core/session/age_gate.dart';
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

    final dob = session.birthDate;

    try {
      await client.rpc('upsert_my_profile', params: {
        'p_display_name': session.displayName ?? 'User',
        'p_bio': session.bio,
        'p_dob': dob == null ? null : AgeGate.format(dob),
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
      if (path.startsWith('$uid/')) {
        uploaded.add(path);
        continue;
      }
      if (path.startsWith('http')) {
        throw StateError('External profile photo URLs are not accepted');
      }
      final file = File(path);
      if (!await file.exists()) {
        throw StateError('Profile photo is no longer available on this device');
      }

      final clean = await ImageSanitizer.toJpeg(
        path,
        prefix: 'profile_upload_$i',
      );
      final storagePath =
          '$uid/$i-${DateTime.now().microsecondsSinceEpoch}.jpg';

      try {
        await client.storage.from('profile_photos').upload(
              storagePath,
              clean,
              fileOptions: const FileOptions(
                upsert: false,
                contentType: 'image/jpeg',
              ),
            );
        // TAKE IT DOWN: record the digest so a removal reaches identical copies.
        await MediaHashService.record(
          bucketId: 'profile_photos',
          objectName: storagePath,
          file: clean,
        );

        await client.rpc('submit_photo_for_verification', params: {
          'p_photo_path': storagePath,
          'p_slot_index': i,
        });

        // Store storage path only; bucket privacy is enforced by migration 0018.
        // Clients resolve display URLs via createSignedUrl.
        uploaded.add(storagePath);
        debugPrint(
            'Photo slot $i uploaded + verification queued path=$storagePath');
      } catch (e) {
        debugPrint('Photo upload slot $i failed: $e');
        rethrow;
      }
    }
    return uploaded;
  }

  Future<void> setPaused(bool paused) async {
    if (!cloudReady) return;
    await InRangeSupabase.client.rpc(
      'set_account_paused',
      params: {'p_paused': paused},
    );
  }

  Future<void> requestDeletion() async {
    if (!cloudReady) return;
    await InRangeSupabase.client.rpc('request_account_deletion');
  }

  Future<void> deleteLocationHistory() async {
    if (!cloudReady) return;
    await InRangeSupabase.client.rpc('delete_my_location_history');
  }

  /// Right-of-access export of everything the server holds for this account.
  ///
  /// Returns the raw `in_range.export.v1` document, or null when running
  /// without a cloud backend. The server scopes this to the caller: a
  /// counterpart appears only as an opaque user id.
  Future<Map<String, dynamic>?> exportMyData() async {
    if (!cloudReady) return null;
    final result = await InRangeSupabase.client.rpc('export_my_data');
    return (result as Map).cast<String, dynamic>();
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
