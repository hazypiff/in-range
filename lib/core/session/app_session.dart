import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_range/core/config/app_config.dart';
import 'package:in_range/core/network/supabase_client.dart';
import 'package:in_range/shared/services/auth_service.dart';
import 'package:in_range/shared/services/profile_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Local-first session with optional cloud bind when Supabase is live.
class AppSession {
  const AppSession({
    required this.onboardingComplete,
    required this.signedIn,
    required this.profileComplete,
    required this.paused,
    this.userId,
    this.displayName,
    this.bio,
    this.gender,
    this.preference,
    this.interests = const [],
    this.customInterest,
    this.birthYear,
    this.photoPaths = const [],
    this.photoVerificationStatus = 'pending',
    this.isCloudUser = false,
    this.email,
    this.isSubscriber = false,
    this.incognito = false,
  });

  final bool onboardingComplete;
  final bool signedIn;
  final bool profileComplete;
  final bool paused;
  final String? userId;
  final String? displayName;
  final String? bio;
  final String? gender;
  final String? preference;
  final List<String> interests;
  final String? customInterest;
  final int? birthYear;
  final List<String> photoPaths;

  /// pending | verified | rejected
  final String photoVerificationStatus;
  final bool isCloudUser;
  final String? email;
  final bool isSubscriber;
  final bool incognito;

  int? get age {
    if (birthYear == null) return null;
    return DateTime.now().year - birthYear!;
  }

  bool get needsOnboarding => !onboardingComplete;
  bool get needsAuth => onboardingComplete && !signedIn;
  bool get needsProfile => signedIn && !profileComplete;
  bool get canUseApp =>
      onboardingComplete && signedIn && profileComplete && !paused;

  AppSession copyWith({
    bool? onboardingComplete,
    bool? signedIn,
    bool? profileComplete,
    bool? paused,
    String? userId,
    String? displayName,
    String? bio,
    String? gender,
    String? preference,
    List<String>? interests,
    String? customInterest,
    int? birthYear,
    List<String>? photoPaths,
    String? photoVerificationStatus,
    bool? isCloudUser,
    String? email,
    bool? isSubscriber,
    bool? incognito,
  }) {
    return AppSession(
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      signedIn: signedIn ?? this.signedIn,
      profileComplete: profileComplete ?? this.profileComplete,
      paused: paused ?? this.paused,
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      gender: gender ?? this.gender,
      preference: preference ?? this.preference,
      interests: interests ?? this.interests,
      customInterest: customInterest ?? this.customInterest,
      birthYear: birthYear ?? this.birthYear,
      photoPaths: photoPaths ?? this.photoPaths,
      photoVerificationStatus:
          photoVerificationStatus ?? this.photoVerificationStatus,
      isCloudUser: isCloudUser ?? this.isCloudUser,
      email: email ?? this.email,
      isSubscriber: isSubscriber ?? this.isSubscriber,
      incognito: incognito ?? this.incognito,
    );
  }

  static const empty = AppSession(
    onboardingComplete: false,
    signedIn: false,
    profileComplete: false,
    paused: false,
  );
}

class SessionController extends StateNotifier<AppSession> {
  SessionController(this._prefs) : super(AppSession.empty) {
    _load();
    _bindCloudSessionIfAny();
  }

  final SharedPreferences _prefs;
  final _auth = AuthService();
  final _profileSync = ProfileSyncService();
  static const _uuid = Uuid();

  void _load() {
    final interestsRaw = _prefs.getStringList('interests') ?? const <String>[];
    final photos = _prefs.getStringList('photo_paths') ?? const <String>[];
    state = AppSession(
      onboardingComplete: _prefs.getBool('onboarding_complete') ?? false,
      signedIn: _prefs.getBool('signed_in') ?? false,
      profileComplete: _prefs.getBool('profile_complete') ?? false,
      paused: _prefs.getBool('paused') ?? false,
      userId: _prefs.getString('user_id'),
      displayName: _prefs.getString('display_name'),
      bio: _prefs.getString('bio'),
      gender: _prefs.getString('gender'),
      preference: _prefs.getString('preference'),
      interests: interestsRaw,
      customInterest: _prefs.getString('custom_interest'),
      birthYear: _prefs.getInt('birth_year'),
      photoPaths: photos,
      photoVerificationStatus:
          _prefs.getString('photo_verification') ?? 'pending',
      isCloudUser: _prefs.getBool('is_cloud_user') ?? false,
      email: _prefs.getString('email_hint'),
      isSubscriber: _prefs.getBool('is_subscriber') ?? false,
      incognito: _prefs.getBool('incognito') ?? false,
    );
    debugPrint(
      'Session loaded: onboard=${state.onboardingComplete} '
      'auth=${state.signedIn} profile=${state.profileComplete} '
      'photos=${state.photoPaths.length} uid=${state.userId} '
      'cloud=${state.isCloudUser}',
    );
  }

  Future<void> _bindCloudSessionIfAny() async {
    if (!AppConfig.hasRealSupabase) return;
    try {
      final user = InRangeSupabase.clientOrNull?.auth.currentUser;
      if (user == null) {
        debugPrint('Cloud bind: no Supabase user yet');
        return;
      }
      // Prefer cloud uid for server RPCs even when anonymous; keep local
      // profile flags (onboarding/profile complete) intact.
      await _applyCloudUser(
        user.id,
        email: user.email,
        isAnonymous: user.isAnonymous,
      );
      debugPrint(
        'Cloud bind OK uid=${user.id} anon=${user.isAnonymous}',
      );
    } catch (e) {
      debugPrint('Cloud session bind skipped: $e');
    }
  }

  Future<void> _applyCloudUser(
    String id, {
    String? email,
    bool isAnonymous = false,
  }) async {
    await _prefs.setBool('signed_in', true);
    await _prefs.setString('user_id', id);
    // Anonymous still counts as cloud-backed for feeds/RPC; only OAuth/email
    // is "full" account for display purposes.
    final cloudBacked = true;
    await _prefs.setBool('is_cloud_user', cloudBacked && !isAnonymous);
    await _prefs.setBool('has_cloud_session', true);
    if (email != null) await _prefs.setString('email_hint', email);
    state = state.copyWith(
      signedIn: true,
      userId: id,
      isCloudUser: cloudBacked && !isAnonymous,
      email: email ?? state.email,
    );
  }

  Future<void> completeOnboarding() async {
    await _prefs.setBool('onboarding_complete', true);
    state = state.copyWith(onboardingComplete: true);
  }

  Future<void> signInAsGuest({String? emailHint}) async {
    // Prefer anonymous cloud session when available
    if (AppConfig.hasRealSupabase) {
      try {
        final res = await _auth.signInAnonymously();
        final uid = res.user?.id;
        if (uid != null) {
          await _applyCloudUser(uid, email: emailHint, isAnonymous: true);
          return;
        }
      } catch (e) {
        debugPrint('Anonymous cloud auth failed, local guest: $e');
      }
    }
    final id = state.userId ?? _uuid.v4();
    await _prefs.setBool('signed_in', true);
    await _prefs.setString('user_id', id);
    await _prefs.setBool('is_cloud_user', false);
    if (emailHint != null && emailHint.isNotEmpty) {
      await _prefs.setString('email_hint', emailHint);
    }
    state = state.copyWith(
      signedIn: true,
      userId: id,
      isCloudUser: false,
      email: emailHint ?? state.email,
    );
  }

  Future<void> signInEmail({
    required String email,
    required String password,
  }) async {
    if (AppConfig.hasRealSupabase) {
      try {
        // Try sign-in first; if user missing, sign-up
        try {
          final res = await _auth.signInEmail(email: email, password: password);
          final uid = res.user?.id;
          if (uid != null) {
            await _applyCloudUser(uid, email: email);
            return;
          }
        } catch (_) {
          final res = await _auth.signUpEmail(email: email, password: password);
          final uid = res.user?.id;
          if (uid != null) {
            await _applyCloudUser(uid, email: email);
            return;
          }
          // Email confirmation required — still allow local progression
          if (res.session == null) {
            await signInAsGuest(emailHint: email);
            throw StateError(
              'Check your email to confirm the account. Continuing in local mode until confirmed.',
            );
          }
        }
      } catch (e) {
        if (e is StateError && e.message.contains('Check your email')) rethrow;
        debugPrint('Cloud email auth failed: $e');
        // Fall through to local so dual-phone testing never blocks
        await signInAsGuest(emailHint: email);
        rethrow;
      }
    } else {
      await signInAsGuest(emailHint: email);
    }
  }

  Future<void> signUpEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    if (!AppConfig.hasRealSupabase) {
      await signInAsGuest(emailHint: email);
      return;
    }
    final res = await _auth.signUpEmail(
      email: email,
      password: password,
      displayName: displayName,
    );
    final uid = res.user?.id;
    if (uid != null && res.session != null) {
      await _applyCloudUser(uid, email: email);
    } else {
      await signInAsGuest(emailHint: email);
    }
  }

  Future<void> startPhoneAuth(String phoneE164) async {
    await _auth.signInWithPhone(phoneE164);
  }

  Future<void> verifyPhone({
    required String phoneE164,
    required String code,
  }) async {
    final res = await _auth.verifyPhoneOtp(phoneE164: phoneE164, token: code);
    final uid = res.user?.id;
    if (uid != null) {
      await _applyCloudUser(uid);
    }
  }

  Future<void> signInWithGoogle() async {
    final launched = await _auth.signInWithGoogle();
    if (!launched) {
      throw StateError('Could not launch Google sign-in');
    }
    // Session arrives via deep link / onAuthStateChange
  }

  Future<void> signInWithApple() async {
    final launched = await _auth.signInWithApple();
    if (!launched) {
      throw StateError('Could not launch Apple sign-in');
    }
  }

  /// Call when OAuth deep link restores a session.
  Future<void> syncFromCloudAuth() async {
    await _bindCloudSessionIfAny();
  }

  Future<void> saveProfile({
    required String displayName,
    required String bio,
    required String gender,
    required String preference,
    required int birthYear,
    required List<String> interests,
    String? customInterest,
    List<String>? photoPaths,
  }) async {
    final age = DateTime.now().year - birthYear;
    if (age < 18) {
      throw StateError('Must be 18+');
    }
    if (displayName.trim().isEmpty) {
      throw StateError('Display name required');
    }
    var photos = photoPaths ?? state.photoPaths;

    // Upload photos + profile when cloud is live
    if (AppConfig.hasRealSupabase && state.isCloudUser) {
      try {
        photos = await _profileSync.uploadPhotos(photos);
        final draft = state.copyWith(
          displayName: displayName.trim(),
          bio: bio.trim(),
          gender: gender,
          preference: preference,
          birthYear: birthYear,
          interests: interests,
          customInterest: customInterest?.trim(),
          photoPaths: photos,
        );
        await _profileSync.syncProfile(draft);
      } catch (e) {
        debugPrint('Cloud profile sync deferred: $e');
      }
    }

    await _prefs.setString('display_name', displayName.trim());
    await _prefs.setString('bio', bio.trim());
    await _prefs.setString('gender', gender);
    await _prefs.setString('preference', preference);
    await _prefs.setInt('birth_year', birthYear);
    await _prefs.setStringList('interests', interests);
    if (customInterest != null) {
      await _prefs.setString('custom_interest', customInterest.trim());
    }
    await _prefs.setStringList('photo_paths', photos);
    await _prefs.setString('photo_verification', 'pending');
    await _prefs.setBool('profile_complete', true);
    state = state.copyWith(
      displayName: displayName.trim(),
      bio: bio.trim(),
      gender: gender,
      preference: preference,
      birthYear: birthYear,
      interests: interests,
      customInterest: customInterest?.trim(),
      photoPaths: photos,
      photoVerificationStatus: 'pending',
      profileComplete: true,
    );
  }

  Future<void> setPhotoPaths(List<String> paths) async {
    final clipped = paths.take(6).toList();
    await _prefs.setStringList('photo_paths', clipped);
    state = state.copyWith(photoPaths: clipped);
  }

  Future<void> setPaused(bool paused) async {
    await _prefs.setBool('paused', paused);
    state = state.copyWith(paused: paused);
    await _profileSync.setPaused(paused);
  }

  Future<void> setIncognito(bool enabled) async {
    await _prefs.setBool('incognito', enabled);
    state = state.copyWith(incognito: enabled);
    await _profileSync.setIncognito(enabled);
  }

  Future<void> deleteAccountLocal() async {
    try {
      await _profileSync.requestDeletion();
      await _auth.signOut();
    } catch (e) {
      debugPrint('Cloud delete: $e');
    }
    await _prefs.clear();
    state = AppSession.empty;
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (_) {}
    await _prefs.setBool('signed_in', false);
    await _prefs.setBool('is_cloud_user', false);
    state = state.copyWith(signedIn: false, isCloudUser: false);
  }
}

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Override in main()');
});

final sessionControllerProvider =
    StateNotifierProvider<SessionController, AppSession>((ref) {
  return SessionController(ref.watch(sharedPreferencesProvider));
});
