import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:in_range/core/network/supabase_client.dart';
import 'package:in_range/core/session/app_session.dart';
import 'package:in_range/features/consent/consent_screen.dart';
import 'package:in_range/shared/services/consent_service.dart';

/// The purposes the app cannot run without — must match the `required_` items
/// in consent_screen.dart.
const _requiredPurposes = <ConsentPurpose>[
  ConsentPurpose.sensitiveProfile,
  ConsentPurpose.bleProximity,
  ConsentPurpose.preciseLocation,
  ConsentPurpose.photoProcessing,
];

String _capturedKey(String uid) => 'consent_captured_v1_$uid';

/// Whether the signed-in user still owes first-run consent.
///
/// Fail-closed: if we cannot read consent state for a user we have no local
/// record for, we ask rather than assume. Returning users are never blocked
/// offline — a successful capture is remembered per-uid in prefs.
final consentRequiredProvider = FutureProvider<bool>((ref) async {
  // Recompute whenever the signed-in account changes: a cached "satisfied"
  // for user A must never let user B through within the same process.
  ref.watch(sessionControllerProvider.select((s) => s.userId));
  const service = ConsentService();
  if (!service.ready) return false; // dev mode / signed out: nothing to record
  final uid = InRangeSupabase.clientOrNull?.auth.currentUser?.id;
  if (uid == null) return false;
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_capturedKey(uid)) ?? false) return false;
  final current = await service.current(); // {} on failure → ask (fail-closed)
  final satisfied = _requiredPurposes.every((p) => current[p] == true);
  if (satisfied) {
    // Consent already on record (e.g. reinstall) — remember and let through.
    await prefs.setBool(_capturedKey(uid), true);
    return false;
  }
  return true;
});

/// Shows the first-run [ConsentScreen] before [child] until the required
/// consents are on record. Sits directly after auth — in front of BOTH
/// profile setup and the home shell — so nothing behind it can collect
/// photos/location/BLE/sensitive data before the user has answered.
class ConsentGate extends ConsumerWidget {
  const ConsentGate({super.key, required this.child});

  final Widget child;

  Future<void> _markCaptured(WidgetRef ref) async {
    final uid = InRangeSupabase.clientOrNull?.auth.currentUser?.id;
    if (uid != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_capturedKey(uid), true);
    }
    ref.invalidate(consentRequiredProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final required = ref.watch(consentRequiredProvider);
    return required.when(
      data: (needs) => needs
          ? ConsentScreen(onDone: () => _markCaptured(ref))
          : child,
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      // Provider failure = unknown state for an uncaptured user: ask.
      error: (_, __) => ConsentScreen(onDone: () => _markCaptured(ref)),
    );
  }
}
