import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_range/core/permissions/permission_service.dart';
import 'package:in_range/core/prefs/app_prefs.dart';
import 'package:in_range/features/beacon/beacon_service.dart';
import 'package:in_range/features/encounters/local_encounter_store.dart';

final _userIdSecretProvider = Provider<String>((ref) {
  return dotenv.maybeGet('INRANGE_USER_ID_SECRET') ?? 'inrange-user-id-fallback';
});

final _hmacSecretProvider = Provider<String>((ref) {
  return dotenv.maybeGet('INRANGE_HMAC_SECRET') ?? 'inrange-hmac-fallback';
});

/// Beacon feet range — persisted across restarts.
final selectedRangeProvider =
    StateNotifierProvider<SelectedRangeController, String>((ref) {
  return SelectedRangeController(ref.watch(appPrefsProvider));
});

class SelectedRangeController extends StateNotifier<String> {
  SelectedRangeController(this._prefs) : super(_prefs.beaconRange);
  final AppPrefs _prefs;

  Future<void> set(String range) async {
    state = range;
    await _prefs.setBeaconRange(range);
  }
}

final beaconServiceProvider = Provider<BeaconService>((ref) {
  final store = ref.read(localEncounterStoreProvider.notifier);
  return BeaconService(
    userIdSecret: ref.watch(_userIdSecretProvider),
    hmacSecret: ref.watch(_hmacSecretProvider),
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
});

class BeaconState {
  const BeaconState({this.isOn = false, this.tokenExpiresAt});
  final bool isOn;
  final DateTime? tokenExpiresAt;

  BeaconState copyWith({bool? isOn, DateTime? tokenExpiresAt}) => BeaconState(
        isOn: isOn ?? this.isOn,
        tokenExpiresAt: tokenExpiresAt ?? this.tokenExpiresAt,
      );
}

class BeaconController extends StateNotifier<BeaconState> {
  BeaconController(this._service, this._ref) : super(const BeaconState());

  final BeaconService _service;
  final Ref _ref;

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
  return BeaconController(ref.watch(beaconServiceProvider), ref);
});
