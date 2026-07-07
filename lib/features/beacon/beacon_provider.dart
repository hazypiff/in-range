import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_range/features/beacon/beacon_service.dart';

/// Configuration providers — replace these with secrets loaded from .env /
/// flutter_dotenv or a remote config before shipping.
final _userIdSecretProvider = Provider<String>((ref) {
  throw UnimplementedError('Provide userIdSecret (from auth session) in override');
});

final _hmacSecretProvider = Provider<String>((ref) {
  throw UnimplementedError('Provide hmacSecret (from remote config) in override');
});

/// Provides the user's currently selected range ('feet' or 'miles').
final selectedRangeProvider = StateProvider<String>((ref) => 'feet');

/// Singleton BeaconService wired with secrets from upstream providers.
final beaconServiceProvider = Provider<BeaconService>((ref) {
  return BeaconService(
    userIdSecret: ref.watch(_userIdSecretProvider),
    hmacSecret: ref.watch(_hmacSecretProvider),
  );
});

/// Reactive beacon status (on/off + current token expiry if any).
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
  BeaconController(this._service, this._rangeReader) : super(const BeaconState());

  final BeaconService _service;
  final Reader _rangeReader;

  Future<void> toggle() async {
    if (state.isOn) {
      await _service.turnOffBeacon();
      state = const BeaconState();
    } else {
      final range = _rangeReader(selectedRangeProvider);
      try {
        await _service.turnOnBeacon(rangeType: range);
        state = BeaconState(
          isOn: true,
          tokenExpiresAt: _service.currentToken?.expiresAt,
        );
      } catch (_) {
        // Claim failed — surface as off.
        state = const BeaconState();
      }
    }
  }
}

final beaconControllerProvider =
    StateNotifierProvider<BeaconController, BeaconState>((ref) {
  return BeaconController(ref.watch(beaconServiceProvider), ref.read);
});
