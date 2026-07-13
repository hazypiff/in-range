import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_range/core/config/app_config.dart';
import 'package:in_range/core/permissions/permission_service.dart';
import 'package:in_range/core/prefs/app_prefs.dart';
import 'package:in_range/core/session/app_session.dart';
import 'package:in_range/features/beacon/beacon_service.dart';
import 'package:in_range/features/encounters/local_encounter_store.dart';

/// Beacon feet range — persisted across restarts.
final selectedRangeProvider =
    StateNotifierProvider<SelectedRangeController, String>((ref) {
  return SelectedRangeController(ref.watch(appPrefsProvider));
});

class SelectedRangeController extends StateNotifier<String> {
  // Range is fixed at feet_60 for now (product call 2026-07-13): users don't
  // pick a range; the RangeEstimator classifies every encounter into
  // 10/30/60 ft bands regardless. Stored prefs are ignored until the
  // post-calibration UX decides whether a picker returns.
  SelectedRangeController(this._prefs) : super(fixedRange);
  final AppPrefs _prefs;

  static const String fixedRange = 'feet_60';

  static const _allowed = <String>{
    'feet_10',
    'feet_30',
    'feet_60',
    'miles_1',
    'miles_5',
    'miles_10',
  };

  static String _validated(String value) =>
      _allowed.contains(value) ? value : fixedRange;

  Future<void> set(String range) async {
    final safe = _validated(range);
    state = safe;
    await _prefs.setBeaconRange(safe);
  }
}

final beaconServiceProvider = Provider<BeaconService>((ref) {
  final store = ref.read(localEncounterStoreProvider.notifier);
  final userId = ref.watch(sessionControllerProvider.select((s) => s.userId));
  final service = BeaconService(
    userIdSecret: AppConfig.userIdSecret,
    userId: userId ?? '',
    hmacSecret: AppConfig.hmacSecret,
    onSighting: ({
      required String correlationId,
      required int rssi,
      required String rangeType,
      required String estimatedBand,
    }) {
      store.noteSighting(
        correlationId: correlationId,
        rssi: rssi,
        rangeType: rangeType,
        estimatedBand: estimatedBand,
      );
    },
  );
  ref.onDispose(service.turnOffBeacon);
  return service;
});

class BeaconState {
  const BeaconState({
    this.isOn = false,
    this.tokenExpiresAt,
    this.cloudSynced,
  });
  final bool isOn;
  final DateTime? tokenExpiresAt;
  final bool? cloudSynced;

  BeaconState copyWith({
    bool? isOn,
    DateTime? tokenExpiresAt,
    bool? cloudSynced,
  }) =>
      BeaconState(
        isOn: isOn ?? this.isOn,
        tokenExpiresAt: tokenExpiresAt ?? this.tokenExpiresAt,
        cloudSynced: cloudSynced ?? this.cloudSynced,
      );
}

class BeaconController extends StateNotifier<BeaconState> {
  /// Lazy: BeaconService (BLE plugins) is only created when [toggle] turns ON.
  /// Keeps widget tests / cold UI free of platform BLE init side-effects.
  BeaconController(this._ref, this._service) : super(const BeaconState());

  final Ref _ref;
  final BeaconService _service;
  bool _busy = false;

  Future<void> toggle() async {
    // Re-entrancy guard: rapid double-taps interleaved on/off mid-flight and
    // null-crashed turnOnBeacon in the 2026-07-13 field test.
    if (_busy) return;
    _busy = true;
    try {
      await _toggleInner();
    } finally {
      _busy = false;
    }
  }

  Future<void> _toggleInner() async {
    if (state.isOn) {
      await _service.turnOffBeacon();
      state = const BeaconState();
    } else {
      final perm = await PermissionService.requestAllForBeacon();
      if (!perm.canUseBeacon) {
        state = const BeaconState();
        return;
      }
      final range = _ref.read(selectedRangeProvider);
      try {
        await _service.turnOnBeacon(rangeType: range);
        state = BeaconState(
          isOn: true,
          tokenExpiresAt: _service.currentToken?.expiresAt,
          cloudSynced: AppConfig.hasRealSupabase ? _service.cloudClaimed : null,
        );
      } catch (e) {
        debugPrint('turnOnBeacon failed: $e');
        state = const BeaconState();
        rethrow;
      }
    }
  }
}

final beaconControllerProvider =
    StateNotifierProvider<BeaconController, BeaconState>((ref) {
  return BeaconController(ref, ref.watch(beaconServiceProvider));
});
