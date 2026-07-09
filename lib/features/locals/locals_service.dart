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

  void setRange(String range) {
    _range = range;
    if (state.hasFix) {
      _syncServer(state.lat!, state.lon!, state.neighborhood);
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
        _applyPosition(pos);
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
    try {
      Position? pos = await Geolocator.getLastKnownPosition();
      pos ??= await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
      await _applyPosition(pos);
    } catch (e) {
      state = state.copyWith(error: 'Location unavailable: $e');
      debugPrint('Locals fix failed: $e');
    }
  }

  Future<void> _applyPosition(Position pos) async {
    final hood = _coarseNeighborhood(pos.latitude, pos.longitude);
    state = state.copyWith(
      lat: pos.latitude,
      lon: pos.longitude,
      updatedAt: DateTime.now(),
      neighborhood: hood,
      clearError: true,
      broadcasting: true,
    );
    await _syncServer(pos.latitude, pos.longitude, hood);
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

      state = state.copyWith(
        serverPeers: peers,
        usingServer: true,
        clearSyncError: true,
      );
    } catch (e) {
      debugPrint('Locals server sync: $e');
      state = state.copyWith(
        usingServer: false,
        lastSyncError: e.toString(),
      );
    }
  }

  /// Neighborhood-level label only (privacy). No reverse-geocode dependency.
  static String _coarseNeighborhood(double lat, double lon) {
    final cellLat = (lat * 100).floor() / 100;
    final cellLon = (lon * 100).floor() / 100;
    return 'Area ${cellLat.toStringAsFixed(2)}, ${cellLon.toStringAsFixed(2)}';
  }

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
