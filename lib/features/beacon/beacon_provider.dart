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
  SelectedRangeController(this._prefs) : super(_validated(_prefs.beaconRange));
  final AppPrefs _prefs;

  static const _allowed = <String>{
    'feet_10',
    'feet_20',
    'feet_30',
    'miles_1',
    'miles_5',
    'miles_10',
  };

  static String _validated(String value) =>
      _allowed.contains(value) ? value : 'feet_10';

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
    }) {
      store.noteSighting(
        correlationId: correlationId,
        rssi: rssi,
        rangeType: rangeType,
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

  Future<void> toggle() async {
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
