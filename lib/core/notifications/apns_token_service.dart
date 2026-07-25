import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_range/core/notifications/push_service.dart';

/// Registers the raw APNs device token with the server so the proximity-wake
/// Edge Function can send silent pushes (Tier 4 of
/// docs/SUBTLE_TRACKING_ARCHITECTURE.md).
///
/// This is deliberately separate from [PushService], which owns the FCM
/// namespace. `device_push_tokens` now carries a `provider` column
/// ('fcm' | 'apns'); mixing the two would make every APNs send fail with
/// BadDeviceToken once firebase_messaging lands.
///
/// iOS only. Android push continues through FCM when it is wired.
class ApnsTokenService {
  ApnsTokenService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('io.inrange.app/apns') {
    try {
      _channel.setMethodCallHandler(_handleCall);
    } catch (e) {
      debugPrint('APNs token handler not registered: ${e.runtimeType}');
    }
  }

  final MethodChannel _channel;
  String? _token;
  bool _registered = false;

  String? get token => _token;
  bool get isRegistered => _registered;

  /// Call after auth session is ready. Pulls any token that arrived before
  /// Dart attached, then registers it.
  Future<void> ensureRegistered() async {
    if (!Platform.isIOS) return;
    try {
      final token = await _channel.invokeMethod<String>('getDeviceToken');
      if (token != null && token.isNotEmpty) {
        await _register(token);
      }
    } on MissingPluginException {
      // Older build without the APNs channel; nothing to do.
    } catch (e) {
      debugPrint('APNs token pull failed: $e');
    }
  }

  Future<dynamic> _handleCall(MethodCall call) async {
    switch (call.method) {
      case 'onDeviceToken':
        final token = call.arguments as String?;
        if (token != null && token.isNotEmpty) {
          await _register(token);
        }
    }
    return null;
  }

  Future<void> _register(String token) async {
    if (_token == token && _registered) return;
    _token = token;
    // registerToken returns false when there is no session or the RPC
    // failed — only a real server row marks us registered, so a later
    // ensureRegistered (after sign-in) retries instead of trusting the flag.
    _registered = await PushService().registerToken(
      token,
      platform: 'ios',
      provider: 'apns',
    );
    if (_registered) debugPrint('APNs token registered');
  }

  /// Removes this device's APNs token from the server (sign-out, account
  /// deletion). The token is pulled from the native side if necessary so a
  /// fresh instance can unregister without having registered first.
  Future<void> unregister() async {
    if (!Platform.isIOS) return;
    try {
      final token = _token ??
          await _channel.invokeMethod<String>('getDeviceToken');
      if (token != null && token.isNotEmpty) {
        await PushService().unregister(token);
      }
    } on MissingPluginException {
      // Older build without the APNs channel; nothing to do.
    } catch (e) {
      debugPrint('APNs unregister failed: $e');
    }
    _token = null;
    _registered = false;
  }
}

final apnsTokenServiceProvider =
    Provider<ApnsTokenService>((ref) => ApnsTokenService());
