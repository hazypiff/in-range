import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:in_range/core/config/app_config.dart';
import 'package:in_range/shared/services/encounters_api.dart';

/// Own GPS ping for Locals (miles). Server upload when Supabase is real.
class LocalsState {
  const LocalsState({
    this.lat,
    this.lon,
    this.updatedAt,
    this.error,
    this.broadcasting = false,
    this.neighborhood = 'Your area',
    this.serverPeers = const [],
    this.usingServer = false,
    this.lastSyncError,
  });

  final double? lat;
  final double? lon;
  final DateTime? updatedAt;
  final String? error;
  final bool broadcasting;
  final String neighborhood;

  /// Rows from get_locals_feed when cloud is live.
  final List<Map<String, dynamic>> serverPeers;
  final bool usingServer;
  final String? lastSyncError;

  bool get hasFix => lat != null && lon != null;

  LocalsState copyWith({
    double? lat,
    double? lon,
    DateTime? updatedAt,
    String? error,
    bool? broadcasting,
    String? neighborhood,
    List<Map<String, dynamic>>? serverPeers,
    bool? usingServer,
    String? lastSyncError,
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
      serverPeers: serverPeers ?? this.serverPeers,
      usingServer: usingServer ?? this.usingServer,
      lastSyncError:
          clearSyncError ? null : (lastSyncError ?? this.lastSyncError),
    );
  }
}

class LocalsController extends StateNotifier<LocalsState> {
  LocalsController() : super(const LocalsState());

  final _api = EncountersApi();
  Timer? _timer;
  StreamSubscription<Position>? _sub;
  String _range = 'miles_10';
  bool _refreshing = false;
  bool _applyingPosition = false;

  void setRange(String range) {
    _range = const {'miles_1', 'miles_5', 'miles_10'}.contains(range)
        ? range
        : 'miles_10';
    if (state.hasFix) {
      unawaited(_syncServer(state.lat!, state.lon!, state.neighborhood));
    }
  }

  /// Start periodic GPS for Locals tab (no BLE required).
  Future<void> start() async {
    if (state.broadcasting) {
      await _refreshOnce();
      return;
    }
    state = state.copyWith(broadcasting: true, clearError: true);
    await _refreshOnce();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 45), (_) {
      _refreshOnce();
    });
    try {
      _sub?.cancel();
      _sub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          distanceFilter: 50,
        ),
      ).listen((pos) {
        unawaited(_applyPosition(pos));
      }, onError: (e) {
        debugPrint('Locals stream error: $e');
      });
    } catch (e) {
      debugPrint('Locals stream start failed: $e');
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _sub?.cancel();
    _sub = null;
    state = state.copyWith(broadcasting: false);
  }

  Future<void> _refreshOnce() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      Position? pos = await Geolocator.getLastKnownPosition();
      if (pos == null || !_isFresh(pos)) {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
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
        clearError: true,
        broadcasting: true,
      );
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
      state = state.copyWith(
        usingServer: false,
        lastSyncError: 'sync_failed',
      );
    }
  }

  /// Avoid encoding coordinates into a human-readable field or notification.
  static String _coarseNeighborhood() => 'Nearby';

  static bool _isFresh(Position position) =>
      DateTime.now().difference(position.timestamp).abs() <=
      const Duration(minutes: 2);

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}

final localsControllerProvider =
    StateNotifierProvider<LocalsController, LocalsState>((ref) {
  final c = LocalsController();
  ref.onDispose(c.stop);
  return c;
});
