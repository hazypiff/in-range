import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_range/core/config/app_config.dart';
import 'package:in_range/core/network/supabase_client.dart';
import 'package:in_range/core/session/age_gate.dart';
import 'package:in_range/shared/services/auth_service.dart';
import 'package:in_range/shared/services/profile_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
    this.birthDate,
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
  final DateTime? birthDate;
  final List<String> photoPaths;

  /// pending | verified | rejected
  final String photoVerificationStatus;
  final bool isCloudUser;
  final String? email;
  final bool isSubscriber;
  final bool incognito;

  int? get age {
    if (birthDate == null) return null;
    return AgeGate.age(birthDate!);
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
    DateTime? birthDate,
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
      birthDate: birthDate ?? this.birthDate,
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
    if (AppConfig.hasRealSupabase) {
      _authSubscription = _auth.onAuthStateChange.listen(_handleAuthState);
      _bindCloudSessionIfAny();
    } else if (_prefs.getBool('has_cloud_session') == true) {
      unawaited(_clearAccountState());
    }
  }

  final SharedPreferences _prefs;
  final _auth = AuthService();
  final _profileSync = ProfileSyncService();
  StreamSubscription<AuthState>? _authSubscription;
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
      birthDate: _storedBirthDate(),
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
      'photos=${state.photoPaths.length} hasUid=${state.userId != null} '
      'cloud=${state.isCloudUser}',
    );
  }

  DateTime? _storedBirthDate() {
    final exact = DateTime.tryParse(_prefs.getString('birth_date') ?? '');
    if (exact != null) return DateTime(exact.year, exact.month, exact.day);
    final legacyYear = _prefs.getInt('birth_year');
    // A year-only legacy value cannot prove someone has had their birthday;
    // December 31 is the conservative migration until they edit their profile.
    return legacyYear == null ? null : DateTime(legacyYear, 12, 31);
  }

  Future<void> _bindCloudSessionIfAny() async {
    if (!AppConfig.hasRealSupabase) return;
    try {
      final user = InRangeSupabase.clientOrNull?.auth.currentUser;
      if (user == null) {
        debugPrint('Cloud bind: no Supabase user yet');
        if (_prefs.getBool('has_cloud_session') == true) {
          await _clearAccountState();
        }
        return;
      }
      // Prefer cloud uid for server RPCs even when anonymous; keep local
      // profile flags (onboarding/profile complete) intact.
      await _applyCloudUser(
        user.id,
        email: user.email,
        isAnonymous: user.isAnonymous,
      );
      if (!user.isAnonymous) await _hydrateCloudProfile();
      debugPrint(
        'Cloud bind OK anon=${user.isAnonymous}',
      );
    } catch (e) {
      debugPrint('Cloud session bind skipped: $e');
    }
  }

  Future<void> _handleAuthState(AuthState authState) async {
    final user = authState.session?.user;
    if (user != null) {
      await _applyCloudUser(
        user.id,
        email: user.email,
        isAnonymous: user.isAnonymous,
      );
      if (!user.isAnonymous) await _hydrateCloudProfile();
      return;
    }
    if (authState.event == AuthChangeEvent.signedOut) {
      await _clearAccountState();
    }
  }

  Future<void> _hydrateCloudProfile() async {
    try {
      final raw = await InRangeSupabase.client.rpc('get_my_profile');
      if (raw is! Map) return;
      final profile = Map<String, dynamic>.from(raw);
      final dob = DateTime.tryParse(profile['dob']?.toString() ?? '');
      final interests =
          (profile['interests'] as List?)?.map((e) => e.toString()).toList() ??
              const <String>[];
      final photos = (profile['photo_urls'] as List?)
              ?.map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList() ??
          const <String>[];
      final displayName = profile['display_name']?.toString();
      final complete = profile['age_verified'] == true &&
          displayName != null &&
          displayName.trim().isNotEmpty;

      if (displayName != null) {
        await _prefs.setString('display_name', displayName);
      }
      await _prefs.setString('bio', profile['bio']?.toString() ?? '');
      if (dob != null) {
        await _prefs.setString('birth_date', AgeGate.format(dob));
        await _prefs.remove('birth_year');
      }
      await _prefs.setStringList('interests', interests);
      await _prefs.setStringList('photo_paths', photos);
      await _prefs.setString(
        'photo_verification',
        profile['photo_verification_status']?.toString() ?? 'pending',
      );
      await _prefs.setBool('profile_complete', complete);
      await _prefs.setBool('paused', profile['is_paused'] == true);
      await _prefs.setBool('incognito', profile['is_incognito'] == true);
      await _prefs.setBool('is_subscriber', profile['is_subscriber'] == true);

      state = state.copyWith(
        displayName: displayName,
        bio: profile['bio']?.toString(),
        gender: profile['gender']?.toString(),
        preference: profile['sexual_preference']?.toString(),
        interests: interests,
        birthDate: dob,
        photoPaths: photos,
        photoVerificationStatus:
            profile['photo_verification_status']?.toString() ?? 'pending',
        profileComplete: complete,
        paused: profile['is_paused'] == true,
        incognito: profile['is_incognito'] == true,
        isSubscriber: profile['is_subscriber'] == true,
      );
    } catch (e) {
      debugPrint('Cloud profile hydration failed: $e');
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

  Future<void> signInAsGuest({String? emailHint, DateTime? birthDate}) async {
    if (birthDate != null) await rememberBirthDate(birthDate);
    // Prefer anonymous cloud session when available
    if (AppConfig.hasRealSupabase) {
      try {
        final res = await _auth.signInAnonymously(birthDate: birthDate);
        final uid = res.user?.id;
        if (uid != null) {
          await _applyCloudUser(uid, email: emailHint, isAnonymous: true);
          if (birthDate != null) {
            state = state.copyWith(birthDate: birthDate);
          }
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
      birthDate: birthDate ?? state.birthDate,
    );
  }

  Future<void> rememberBirthDate(DateTime birthDate) async {
    if (!AgeGate.isAdult(birthDate)) {
      throw StateError('You must be 18 or older to use In Range');
    }
    await _prefs.setString('birth_date', AgeGate.format(birthDate));
    await _prefs.remove('birth_year');
    state = state.copyWith(birthDate: birthDate);
  }

  Future<void> signInEmail({
    required String email,
    required String password,
  }) async {
    if (!AppConfig.hasRealSupabase) {
      throw StateError(
          'Cloud sign-in is unavailable. Use explicit guest mode.');
    }
    final res = await _auth.signInEmail(email: email, password: password);
    final uid = res.user?.id;
    if (uid == null || res.session == null) {
      throw StateError('Sign-in did not create a session');
    }
    await _applyCloudUser(uid, email: email);
    await _hydrateCloudProfile();
  }

  Future<void> signUpEmail({
    required String email,
    required String password,
    String? displayName,
    required DateTime birthDate,
  }) async {
    await rememberBirthDate(birthDate);
    if (!AppConfig.hasRealSupabase) {
      throw StateError(
          'Cloud sign-up is unavailable. Use explicit guest mode.');
    }
    final res = await _auth.signUpEmail(
      email: email,
      password: password,
      displayName: displayName,
      birthDate: birthDate,
    );
    final uid = res.user?.id;
    if (uid != null && res.session != null) {
      await _applyCloudUser(uid, email: email);
      state = state.copyWith(birthDate: birthDate);
    } else {
      throw StateError(
          'Check your email to confirm the account, then sign in.');
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
    required DateTime birthDate,
    required List<String> interests,
    String? customInterest,
    List<String>? photoPaths,
  }) async {
    if (!AgeGate.isAdult(birthDate)) {
      throw StateError('Must be 18+');
    }
    if (displayName.trim().isEmpty) {
      throw StateError('Display name required');
    }
    var photos = photoPaths ?? state.photoPaths;
    if (photos.isEmpty) {
      throw StateError('Add at least one profile photo');
    }

    // Upload photos + profile when cloud is live
    if (AppConfig.hasRealSupabase && state.isCloudUser) {
      try {
        photos = await _profileSync.uploadPhotos(photos);
        final draft = state.copyWith(
          displayName: displayName.trim(),
          bio: bio.trim(),
          gender: gender,
          preference: preference,
          birthDate: birthDate,
          interests: interests,
          customInterest: customInterest?.trim(),
          photoPaths: photos,
        );
        await _profileSync.syncProfile(draft);
      } catch (e) {
        debugPrint('Cloud profile sync failed: $e');
        rethrow;
      }
    }

    await _prefs.setString('display_name', displayName.trim());
    await _prefs.setString('bio', bio.trim());
    await _prefs.setString('gender', gender);
    await _prefs.setString('preference', preference);
    await _prefs.setString('birth_date', AgeGate.format(birthDate));
    await _prefs.remove('birth_year');
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
      birthDate: birthDate,
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
    await _profileSync.setPaused(paused);
    await _prefs.setBool('paused', paused);
    state = state.copyWith(paused: paused);
  }

  Future<void> setIncognito(bool enabled) async {
    // Cloud gate first, like setPaused above — it throws when Incognito
    // requires a subscription. Persisting before the gate left free users
    // locally-incognito (prefs key is shared with SafetyStore) with the
    // beacon silently blocked after restart.
    await _profileSync.setIncognito(enabled);
    await _prefs.setBool('incognito', enabled);
    state = state.copyWith(incognito: enabled);
  }

  Future<void> deleteAccountLocal() async {
    if (AppConfig.hasRealSupabase &&
        InRangeSupabase.clientOrNull?.auth.currentUser != null) {
      await _profileSync.requestDeletion();
    }
    await _auth.signOut();
    await _clearAccountState(clearOnboarding: true);
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      debugPrint('Cloud sign-out failed; clearing this device session: $e');
    }
    await _clearAccountState();
  }

  Future<void> _clearAccountState({bool clearOnboarding = false}) async {
    const accountKeys = <String>[
      'signed_in',
      'user_id',
      'is_cloud_user',
      'has_cloud_session',
      'email_hint',
      'profile_complete',
      'paused',
      'display_name',
      'bio',
      'gender',
      'preference',
      'interests',
      'custom_interest',
      'birth_date',
      'birth_year',
      'photo_paths',
      'photo_verification',
      'is_subscriber',
      'incognito',
    ];
    for (final key in accountKeys) {
      await _prefs.remove(key);
    }
    if (clearOnboarding) await _prefs.remove('onboarding_complete');
    final onboarded = clearOnboarding
        ? false
        : (_prefs.getBool('onboarding_complete') ?? state.onboardingComplete);
    state = AppSession.empty.copyWith(onboardingComplete: onboarded);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Override in main()');
});

final sessionControllerProvider =
    StateNotifierProvider<SessionController, AppSession>((ref) {
  return SessionController(ref.watch(sharedPreferencesProvider));
});
