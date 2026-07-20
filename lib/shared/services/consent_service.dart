import 'package:flutter/foundation.dart';

import 'package:in_range/core/config/app_config.dart';
import 'package:in_range/core/network/supabase_client.dart';

/// The purposes we take consent for, one per processing activity.
///
/// Deliberately narrow. NJDPA excludes "acceptance of a general or broad terms
/// of use" from what counts as consent, and the FTC's X-Mode/InMarket orders
/// make location consent purpose-scoped — consent for proximity matching does
/// not stretch to anything else. Adding a use means adding a purpose here and
/// asking again, not quietly reusing an existing grant.
enum ConsentPurpose {
  /// Gender + sexual orientation. Special-category data under GDPR Art. 9 and
  /// "sensitive data" under NJDPA, CT, MD and others.
  sensitiveProfile('sensitive_profile'),

  /// GPS upload for proximity matching.
  preciseLocation('precise_location'),

  /// Collection while the app is closed.
  backgroundLocation('background_location'),

  /// BLE scan/advertise and the encounter records it produces.
  bleProximity('ble_proximity'),

  /// Profile photo storage and verification.
  photoProcessing('photo_processing');

  const ConsentPurpose(this.wire);

  /// The value stored server-side. Must match the CHECK constraint in 0039.
  final String wire;
}

/// Records and revokes unbundled, purpose-scoped consent.
///
/// The client never writes `consent_records` directly — it has SELECT only, so
/// the audit trail cannot be forged. Everything goes through the RPCs.
class ConsentService {
  const ConsentService();

  /// Bump when the privacy policy changes materially. Stored per grant so a
  /// policy change can invalidate prior consent and force a re-ask.
  ///
  /// TODO: move to AppConfig once counsel has settled the actual policy text
  /// and its versioning scheme.
  static const String policyVersion = '2026-07-20';

  bool get _ready =>
      AppConfig.hasRealSupabase &&
      InRangeSupabase.clientOrNull?.auth.currentUser != null;

  /// Records consent for one purpose. Idempotent — re-granting an active
  /// consent does not restamp the original moment, which is the fact we have
  /// to be able to evidence later.
  ///
  /// [uiSurface] identifies where it was taken (e.g. 'onboarding.consent_step')
  /// and lands in the audit trail.
  Future<void> grant(ConsentPurpose purpose,
      {required String uiSurface}) async {
    if (!_ready) return;
    await InRangeSupabase.client.rpc('grant_consent', params: {
      'p_purpose': purpose.wire,
      'p_policy_version': policyVersion,
      'p_ui_surface': uiSurface,
    });
  }

  /// Withdraws consent. Must stay exactly as easy to reach as granting
  /// (GDPR Art. 7(3)); NJDPA allows 15 days to take effect, the server takes
  /// effect immediately and deletes location data for location purposes.
  Future<bool> withdraw(ConsentPurpose purpose) async {
    if (!_ready) return false;
    final result = await InRangeSupabase.client
        .rpc('withdraw_consent', params: {'p_purpose': purpose.wire});
    return result == true;
  }

  /// Current state for every purpose, for the consent screen and for answering
  /// "what did I agree to?".
  Future<Map<ConsentPurpose, bool>> current() async {
    if (!_ready) return const {};
    try {
      final rows = await InRangeSupabase.client.rpc('my_consents') as List;
      final byWire = {for (final p in ConsentPurpose.values) p.wire: p};
      final out = <ConsentPurpose, bool>{};
      for (final row in rows.cast<Map<String, dynamic>>()) {
        final purpose = byWire[row['purpose'] as String?];
        // Rows are ordered newest-first per purpose, so the first one wins.
        if (purpose != null && !out.containsKey(purpose)) {
          out[purpose] = row['granted'] == true;
        }
      }
      return out;
    } catch (e) {
      debugPrint('ConsentService.current failed: $e');
      return const {};
    }
  }
}
