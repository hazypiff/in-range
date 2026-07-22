import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:in_range/core/config/app_config.dart';
import 'package:in_range/shared/services/consent_service.dart';
import 'package:in_range/shared/services/encounters_api.dart';

/// Own GPS ping for Locals (miles). Server upload when Supabase is real.
///
/// Locals is AMBIENT (owner decision 2026-07-21, issue #2): ONE coarse
/// foreground fix when the Locals tab is opened defines "your area" — no
/// periodic timer, no position stream, never sampled in the background.
/// Real-time proximity is BLE-only (the beacon).
class LocalsState {
  const LocalsState({
    this.lat,
    this.lon,
    this.updatedAt,
    this.error,
    this.broadcasting = false,
    this.neighborhood = 'Your area',
    this.placeLabel,
    this.serverPeers = const [],
    this.usingServer = false,
    this.lastSyncError,
    this.consentRequired = false,
  });

  final double? lat;
  final double? lon;
  final DateTime? updatedAt;
  final String? error;
  final bool broadcasting;
  final String neighborhood;

  /// Reverse-geocoded place name for the OWN-device card only ("Norwalk,
  /// CT"), so a refresh visibly stamps the new area. NEVER synced — the
  /// server/other users only ever see the coarse [neighborhood].
  final String? placeLabel;

  /// Rows from get_locals_feed when cloud is live.
  final List<Map<String, dynamic>> serverPeers;
  final bool usingServer;
  final String? lastSyncError;

  /// True when the user has not granted (or has withdrawn) precise-location
  /// consent: no GPS is touched and the screen offers the consent screen.
  final bool consentRequired;

  bool get hasFix => lat != null && lon != null;

  LocalsState copyWith({
    double? lat,
    double? lon,
    DateTime? updatedAt,
    String? error,
    bool? broadcasting,
    String? neighborhood,
    String? placeLabel,
    List<Map<String, dynamic>>? serverPeers,
    bool? usingServer,
    String? lastSyncError,
    bool? consentRequired,
    bool clearError = false,
    bool clearSyncError = false,
  }) {
    return LocalsState(
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      updatedAt: updatedAt ?? this.updatedAt,
      error: clearError ? null : (error ?? this.error),
      broadcasting: broadcasting ?? this.broadcasting,
      neighborhood: neighborhood ?? this.neighborhood,
      placeLabel: placeLabel ?? this.placeLabel,
      serverPeers: serverPeers ?? this.serverPeers,
      usingServer: usingServer ?? this.usingServer,
      lastSyncError:
          clearSyncError ? null : (lastSyncError ?? this.lastSyncError),
      consentRequired: consentRequired ?? this.consentRequired,
    );
  }
}

class LocalsController extends StateNotifier<LocalsState> {
  LocalsController() : super(const LocalsState());

  final _api = EncountersApi();
  String _range = 'miles_10';
  bool _refreshing = false;
  bool _applyingPosition = false;

  /// Cached consent check so tab-hopping doesn't re-hit my_consents; short
  /// enough that a withdrawal in Settings takes effect on the next open.
  bool? _consentOk;
  DateTime? _consentCheckedAt;

  void setRange(String range) {
    _range = const {'miles_1', 'miles_5', 'miles_10'}.contains(range)
        ? range
        : 'miles_10';
    if (state.hasFix) {
      unawaited(_syncServer(state.lat!, state.lon!, state.neighborhood));
    }
  }

  /// One coarse foreground fix for the Locals tab (no BLE required).
  /// Called on tab open / pull-to-refresh — this is the ONLY place the
  /// Locals feature ever touches location. No timer, no stream.
  Future<void> start() async {
    // A cached denial must not outlive a re-grant: when we're already in the
    // denied state the user may have just granted in the consent screen, so
    // drop the cache and ask the server again.
    if (state.consentRequired) {
      _consentOk = null;
      _consentCheckedAt = null;
    }
    // Consent BEFORE collection: server-side require_consent only protects
    // the upload; the GPS fix and the platform reverse-geocode happen here
    // on-device, so the client must check first. Fail closed.
    if (!await _locationConsentOk()) {
      state = state.copyWith(broadcasting: false, consentRequired: true);
      return;
    }
    state = state.copyWith(
      broadcasting: true,
      consentRequired: false,
      clearError: true,
    );
    await _refreshOnce();
  }

  Future<void> stop() async {
    state = state.copyWith(broadcasting: false);
  }

  /// Sign-out: forget the previous user's coordinates and place label.
  void reset() {
    _consentOk = null;
    _consentCheckedAt = null;
    state = const LocalsState();
  }

  Future<bool> _locationConsentOk() async {
    const service = ConsentService();
    // Dev mode / signed out: nothing is uploaded and there is no server to
    // check against — behave as before.
    if (!service.ready) return true;
    final checkedAt = _consentCheckedAt;
    if (_consentOk != null &&
        checkedAt != null &&
        DateTime.now().difference(checkedAt) < const Duration(minutes: 2)) {
      return _consentOk!;
    }
    final current = await service.current(); // {} on failure → fail closed
    _consentOk = current[ConsentPurpose.preciseLocation] == true;
    _consentCheckedAt = DateTime.now();
    return _consentOk!;
  }

  Future<void> _refreshOnce() async {
    if (_refreshing) return;
    // Cooldown: a tap that arrives seconds after a successful pipeline run
    // would re-send the same coordinates and re-hit the platform geocoder
    // for nothing. GPS itself is already reuse-cached via _isFresh.
    final last = state.updatedAt;
    if (state.hasFix &&
        last != null &&
        DateTime.now().difference(last).abs() < const Duration(seconds: 30)) {
      return;
    }
    _refreshing = true;
    try {
      Position? pos = await Geolocator.getLastKnownPosition();
      if (pos == null || !_isFresh(pos)) {
        // Coarse is enough — "your area," not your street corner.
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 8),
          ),
        );
      }
      await _applyPosition(pos);
    } catch (e) {
      state = state.copyWith(error: 'Location unavailable.');
      debugPrint('Locals fix failed: $e');
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _applyPosition(Position pos) async {
    if (_applyingPosition || !state.broadcasting) return;
    _applyingPosition = true;
    try {
      final hood = _coarseNeighborhood();
      state = state.copyWith(
        lat: pos.latitude,
        lon: pos.longitude,
        updatedAt: pos.timestamp,
        neighborhood: hood,
        placeLabel: await _reverseGeocode(pos),
        clearError: true,
        broadcasting: true,
      );
      // Server gets the coarse label only — placeLabel stays on-device.
      await _syncServer(pos.latitude, pos.longitude, hood);
    } finally {
      _applyingPosition = false;
    }
  }

  Future<void> _syncServer(double lat, double lon, String hood) async {
    if (!AppConfig.hasRealSupabase) {
      state = state.copyWith(usingServer: false, serverPeers: const []);
      return;
    }

    try {
      await _api.recordLocationPing(
        lat: lat,
        lon: lon,
        range: _range,
        neighborhood: hood,
      );

      final peers = await _api.getLocalsFeed(
        lat: lat,
        lon: lon,
        range: _range,
      );
      // Server filters is_photo_verified; drop any residual unverified rows.
      final verified = peers.where((p) {
        if (p['is_photo_verified'] == false) return false;
        final urls = p['photo_urls'];
        if (urls is List && urls.isEmpty) return false;
        return true;
      }).toList();

      state = state.copyWith(
        serverPeers: verified,
        usingServer: true,
        clearSyncError: true,
      );
    } catch (e) {
      debugPrint('Locals server sync: $e');
      // require_consent raises 'Consent required for <purpose>' (42501) once
      // enforce_consent flips on — surface that specifically so the screen
      // can route to the consent screen instead of a generic sync message.
      final consentDenied = e.toString().contains('Consent required');
      if (consentDenied) {
        _consentOk = false;
        _consentCheckedAt = DateTime.now();
      }
      state = state.copyWith(
        usingServer: false,
        lastSyncError: consentDenied ? 'consent_required' : 'sync_failed',
        consentRequired: consentDenied ? true : null,
      );
    }
  }

  /// Avoid encoding coordinates into a human-readable field or notification.
  static String _coarseNeighborhood() => 'Nearby';

  /// Own-device display only (see [LocalsState.placeLabel]). Best-effort:
  /// falls back to rounded coordinates so a refresh always visibly stamps
  /// SOMETHING new, even offline.
  static Future<String> _reverseGeocode(Position pos) async {
    try {
      // Round to ~2 decimals (~1 km) before the platform geocoder call — the
      // coordinates leave the device (Google/Apple resolve them), and city-
      // level display never needs street-level input.
      final lat = (pos.latitude * 100).roundToDouble() / 100;
      final lon = (pos.longitude * 100).roundToDouble() / 100;
      final marks = await geo.placemarkFromCoordinates(lat, lon);
      final m = marks.isEmpty ? null : marks.first;
      final parts = [m?.locality, m?.administrativeArea]
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toList();
      if (parts.isNotEmpty) return parts.join(', ');
    } catch (e) {
      debugPrint('Locals reverse-geocode failed: $e');
    }
    return '${pos.latitude.toStringAsFixed(2)}, '
        '${pos.longitude.toStringAsFixed(2)}';
  }

  static bool _isFresh(Position position) =>
      DateTime.now().difference(position.timestamp).abs() <=
      const Duration(minutes: 2);

}

final localsControllerProvider =
    StateNotifierProvider<LocalsController, LocalsState>((ref) {
  final c = LocalsController();
  ref.onDispose(c.stop);
  return c;
});
