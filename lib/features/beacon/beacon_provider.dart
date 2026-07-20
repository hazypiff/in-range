import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_range/core/config/app_config.dart';
import 'package:in_range/core/permissions/permission_service.dart';
import 'package:in_range/core/prefs/app_prefs.dart';
import 'package:in_range/core/session/app_session.dart';
import 'package:in_range/features/beacon/beacon_service.dart';
import 'package:in_range/features/beacon/range_estimator.dart';
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
    onAdvertSample: (correlationId, rssi, power, at) {
      store.logRssiSample(
        correlationId: correlationId,
        rssi: rssi,
        power: power == AdvertPower.medium ? 'M' : 'H',
        at: at,
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
    this.discoverable = true,
  });
  final bool isOn;
  final DateTime? tokenExpiresAt;
  final bool? cloudSynced;

  /// False when the beacon is scanning but can't advertise (iOS scan-only) —
  /// peers can't discover this device. UI shows "scanning only".
  final bool discoverable;

  BeaconState copyWith({
    bool? isOn,
    DateTime? tokenExpiresAt,
    bool? cloudSynced,
    bool? discoverable,
  }) =>
      BeaconState(
        isOn: isOn ?? this.isOn,
        tokenExpiresAt: tokenExpiresAt ?? this.tokenExpiresAt,
        cloudSynced: cloudSynced ?? this.cloudSynced,
        discoverable: discoverable ?? this.discoverable,
      );
}

class BeaconController extends StateNotifier<BeaconState> {
  /// Lazy: BeaconService (BLE plugins) is only created when [toggle] turns ON.
  /// Keeps widget tests / cold UI free of platform BLE init side-effects.
  BeaconController(this._ref, this._service) : super(const BeaconState()) {
    // Internal stops (failed token rotation etc.) must reach the UI —
    // otherwise the screen shows a green beacon over dead BLE.
    _service.onBeaconStopped = () {
      if (mounted && state.isOn) state = const BeaconState();
    };
    // Every claim attempt / rotation republishes token expiry + cloud state,
    // so the UI can't show the first token's stale values (reviewer #11).
    _service.onClaimStateChanged = (expiresAt, cloudSynced) {
      if (!mounted || !state.isOn) return;
      state = BeaconState(
        isOn: true,
        tokenExpiresAt: expiresAt ?? state.tokenExpiresAt,
        cloudSynced: cloudSynced,
        discoverable: state.discoverable,
      );
    };
  }

  final Ref _ref;
  final BeaconService _service;
  bool _busy = false;

  /// [onBackgroundDisclosure] must present Google Play's prominent disclosure
  /// and resolve true only on an affirmative tap; callers with a BuildContext
  /// pass `() => showBackgroundLocationDisclosure(context)`. Omitting it keeps
  /// the beacon foreground-only rather than prompting without a disclosure.
  Future<void> toggle({
    Future<bool> Function()? onBackgroundDisclosure,
  }) async {
    // Re-entrancy guard: rapid double-taps interleaved on/off mid-flight and
    // null-crashed turnOnBeacon in the 2026-07-13 field test.
    if (_busy) return;
    _busy = true;
    try {
      await _toggleInner(onBackgroundDisclosure);
    } finally {
      _busy = false;
    }
  }

  Future<void> _toggleInner(
      Future<bool> Function()? onBackgroundDisclosure) async {
    if (state.isOn) {
      await _service.turnOffBeacon();
      state = const BeaconState();
    } else {
      final perm = await PermissionService.requestAllForBeacon(
        onBackgroundDisclosure: onBackgroundDisclosure,
      );
      if (!perm.canUseBeacon) {
        state = const BeaconState();
        return;
      }
      final range = _ref.read(selectedRangeProvider);
      try {
        // Auto-retry once on a transient BLE-not-ready failure so the user
        // doesn't have to tap the toggle repeatedly (2026-07-17): after many
        // on/off cycles CoreBluetooth can take a moment to re-initialise, and
        // the first attempt may fire before it's ready. A 1 s pause + one
        // retry clears it invisibly.
        try {
          await _service.turnOnBeacon(rangeType: range);
        } on StateError catch (e) {
          if (e.message.contains('Bluetooth is not ready')) {
            debugPrint('Beacon start not-ready; auto-retrying once…');
            await Future<void>.delayed(const Duration(seconds: 1));
            await _service.turnOnBeacon(rangeType: range);
          } else {
            rethrow;
          }
        }
        state = BeaconState(
          isOn: true,
          tokenExpiresAt: _service.currentToken?.expiresAt,
          cloudSynced: AppConfig.hasRealSupabase ? _service.cloudClaimed : null,
          discoverable: _service.discoverable,
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
