import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_range/core/config/app_config.dart';
import 'package:in_range/core/network/supabase_client.dart';
import 'package:in_range/core/notifications/local_notify.dart';

/// Push notification integration (FCM-ready).
///
/// Without `google-services.json` / APNs, firebase_messaging is not linked
/// (would break the Android build). This service:
/// 1. Registers mock or provided tokens via `register_push_token` RPC
/// 2. Handles notification *payloads* the same way FCM will deliver them
/// 3. Surfaces local notifications for offline/dev
///
/// When you add Firebase:
///   - Add firebase_core + firebase_messaging to pubspec
///   - Drop google-services.json / GoogleService-Info.plist
///   - Call [PushService.bindFirebaseToken] from onTokenRefresh
class PushService {
  PushService();

  String? _token;
  String? get token => _token;

  bool _registered = false;
  bool get isRegistered => _registered;

  /// Call after auth session is ready.
  Future<void> ensureRegistered() async {
    if (!AppConfig.hasRealSupabase) {
      debugPrint('Push: skip register (no cloud)');
      return;
    }

    final mock = AppConfig.mockFcmToken;
    if (mock != null) {
      await registerToken(mock, platform: _platform());
      return;
    }

    // No FCM plugin yet — nothing to register. Server send-push will skip
    // users without tokens (status=skipped / no_device_token).
    debugPrint(
      'Push: no FCM token yet. Set FCM_MOCK_TOKEN in .env for lab, '
      'or wire firebase_messaging when Firebase project is ready.',
    );
  }

  /// Bind a real FCM/APNs token (from firebase_messaging when enabled).
  Future<void> bindFirebaseToken(String token) async {
    await registerToken(token, platform: _platform());
  }

  Future<void> registerToken(
    String token, {
    required String platform,
    String? appVersion,
  }) async {
    _token = token;
    final client = InRangeSupabase.clientOrNull;
    if (client == null || client.auth.currentUser == null) {
      debugPrint('Push: cannot register token — no session');
      return;
    }
    try {
      await client.rpc('register_push_token', params: {
        'p_token': token,
        'p_platform': platform,
        'p_app_version': appVersion,
      });
      _registered = true;
      debugPrint('Push: token registered ($platform)');
    } catch (e) {
      debugPrint('Push: register_push_token failed: $e');
    }
  }

  Future<void> unregister() async {
    final client = InRangeSupabase.clientOrNull;
    final t = _token;
    if (client == null || t == null) return;
    try {
      await client.rpc('unregister_push_token', params: {'p_token': t});
    } catch (e) {
      debugPrint('Push: unregister failed: $e');
    }
    _token = null;
    _registered = false;
  }

  /// Handle a remote message data payload (FCM / APNs).
  /// Call from FirebaseMessaging.onMessage / onMessageOpenedApp.
  Future<void> handlePayload(Map<String, dynamic> data) async {
    final kind = data['kind']?.toString() ?? '';
    final title = data['title']?.toString();
    final body = data['body']?.toString();

    switch (kind) {
      case 'new_encounter':
        await LocalNotify.instance.notifyNewEncounter(
          data['other_user_id']?.toString() ?? 'nearby',
        );
        break;
      case 'new_match':
        await LocalNotify.instance.notifyMatch(
          data['other_user_id']?.toString() ?? 'someone',
        );
        break;
      case 'new_message':
        await LocalNotify.instance.show(
          id: 9100,
          title: title ?? 'New message',
          body: body ?? 'Open Messages to reply.',
        );
        break;
      case 'expiring_encounter':
        await LocalNotify.instance.notifyExpiringSoon(
          data['encounter_id']?.toString() ?? '',
        );
        break;
      case 'photo_verified':
        await LocalNotify.instance.show(
          id: 9101,
          title: title ?? 'You\'re verified ✓',
          body: body ?? 'Your photo passed review.',
        );
        break;
      case 'photo_rejected':
        await LocalNotify.instance.show(
          id: 9102,
          title: title ?? 'Photo not approved',
          body: body ?? 'Please upload a clearer photo.',
        );
        break;
      default:
        if (title != null || body != null) {
          await LocalNotify.instance.show(
            id: kind.hashCode & 0x7fffffff,
            title: title ?? 'In Range',
            body: body ?? '',
          );
        }
    }
  }

  static String _platform() {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    return 'android';
  }
}

final pushServiceProvider = Provider<PushService>((ref) => PushService());
