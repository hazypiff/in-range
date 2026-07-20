import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'package:in_range/core/network/supabase_client.dart';

/// Records the SHA-256 of uploaded media so a TAKE IT DOWN removal can reach
/// every identical copy, not just the one object a reporter happened to find.
///
/// Removing "known identical copies" is a statutory duty under the TAKE IT DOWN
/// Act. `ncii_resolve()` fans out across `media_hashes` by digest — which only
/// works if uploads are recorded here.
///
/// The table is insert-only for users and never readable by them: readable, it
/// would answer "does this exact image exist anywhere in the system?" for
/// anyone who could guess a hash.
class MediaHashService {
  MediaHashService._();

  /// Best-effort. A hashing or network failure must never block a user from
  /// sending a photo, so this swallows errors — but it degrades takedown
  /// coverage for that object, hence the loud log.
  static Future<void> record({
    required String bucketId,
    required String objectName,
    required File file,
  }) async {
    try {
      final client = InRangeSupabase.clientOrNull;
      final uid = client?.auth.currentUser?.id;
      if (client == null || uid == null) return;

      final digest = sha256.convert(await file.readAsBytes());

      await client.from('media_hashes').insert({
        'bucket_id': bucketId,
        'object_name': objectName,
        'sha256': digest.toString(),
        'user_id': uid,
      });
    } catch (e) {
      debugPrint(
          'MediaHashService: failed to record hash for $bucketId/$objectName '
          '(takedown copy-matching will miss this object): $e');
    }
  }
}
