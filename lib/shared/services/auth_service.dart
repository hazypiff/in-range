import 'package:flutter/foundation.dart';
import 'package:in_range/core/config/app_config.dart';
import 'package:in_range/core/network/supabase_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Full auth flows: email, phone OTP, Google, Apple, anonymous/guest.
///
/// Provider configs live in Supabase Dashboard. Client code is complete —
/// once OAuth client IDs / SMS / Email are enabled, these methods work.
class AuthService {
  SupabaseClient? get _client => InRangeSupabase.clientOrNull;

  bool get cloudReady => AppConfig.hasRealSupabase && _client != null;

  User? get currentUser => _client?.auth.currentUser;

  Session? get currentSession => _client?.auth.currentSession;

  Stream<AuthState> get onAuthStateChange =>
      _client?.auth.onAuthStateChange ?? const Stream.empty();

  /// Email + password sign-up (sends confirmation if enabled in Dashboard).
  Future<AuthResponse> signUpEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    _requireCloud();
    return _client!.auth.signUp(
      email: email.trim(),
      password: password,
      data: {
        if (displayName != null && displayName.isNotEmpty)
          'display_name': displayName,
      },
    );
  }

  /// Email + password sign-in.
  Future<AuthResponse> signInEmail({
    required String email,
    required String password,
  }) async {
    _requireCloud();
    return _client!.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Phone OTP start (requires Twilio/MessageBird in Supabase Auth).
  Future<void> signInWithPhone(String phoneE164) async {
    _requireCloud();
    await _client!.auth.signInWithOtp(phone: phoneE164.trim());
  }

  /// Verify SMS code.
  Future<AuthResponse> verifyPhoneOtp({
    required String phoneE164,
    required String token,
  }) async {
    _requireCloud();
    return _client!.auth.verifyOTP(
      phone: phoneE164.trim(),
      token: token.trim(),
      type: OtpType.sms,
    );
  }

  /// Resend email confirmation.
  Future<void> resendEmailConfirmation(String email) async {
    _requireCloud();
    await _client!.auth.resend(type: OtpType.signup, email: email.trim());
  }

  /// Google OAuth via browser / system sheet (Supabase provider must be on).
  Future<bool> signInWithGoogle() async {
    _requireCloud();
    return _client!.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: AppConfig.authRedirectUrl,
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  }

  /// Apple Sign-In via Supabase OAuth (iOS native path can replace later).
  Future<bool> signInWithApple() async {
    _requireCloud();
    return _client!.auth.signInWithOAuth(
      OAuthProvider.apple,
      redirectTo: AppConfig.authRedirectUrl,
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  }

  /// Anonymous cloud session (enable Anonymous provider in Dashboard).
  Future<AuthResponse> signInAnonymously() async {
    _requireCloud();
    return _client!.auth.signInAnonymously();
  }

  Future<void> signOut() async {
    final c = _client;
    if (c != null) {
      try {
        await c.auth.signOut();
      } catch (e) {
        debugPrint('Cloud signOut: $e');
      }
    }
  }

  Future<void> sendPasswordReset(String email) async {
    _requireCloud();
    await _client!.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: AppConfig.authRedirectUrl,
    );
  }

  void _requireCloud() {
    if (!cloudReady) {
      throw StateError(
        'Cloud auth unavailable. Add SUPABASE_URL + SUPABASE_PUBLISHABLE_KEY '
        'to .env, or use Continue as guest.',
      );
    }
  }
}
