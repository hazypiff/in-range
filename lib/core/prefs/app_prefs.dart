import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:in_range/core/session/app_session.dart';

/// Persistent UI prefs (beacon range, swipe band filter).
class AppPrefs {
  AppPrefs(this._prefs);
  final SharedPreferences _prefs;

  static const _rangeKey = 'beacon_range';
  static const _bandKey = 'swipe_band_filter';

  String get beaconRange => _prefs.getString(_rangeKey) ?? 'feet_10';

  Future<void> setBeaconRange(String range) =>
      _prefs.setString(_rangeKey, range);

  /// any | feet_10 | feet_30 | feet_60
  String get swipeBandFilter {
    final stored = _prefs.getString(_bandKey) ?? 'any';
    // Pre-calibration builds offered feet_20; it ranks with feet_30 now.
    return stored == 'feet_20' ? 'feet_30' : stored;
  }

  Future<void> setSwipeBandFilter(String band) =>
      _prefs.setString(_bandKey, band);
}

final appPrefsProvider = Provider<AppPrefs>((ref) {
  return AppPrefs(ref.watch(sharedPreferencesProvider));
});

final swipeBandFilterProvider =
    StateNotifierProvider<SwipeBandFilterController, String>((ref) {
  return SwipeBandFilterController(ref.watch(appPrefsProvider));
});

class SwipeBandFilterController extends StateNotifier<String> {
  SwipeBandFilterController(this._prefs) : super(_prefs.swipeBandFilter);
  final AppPrefs _prefs;

  Future<void> set(String band) async {
    state = band;
    await _prefs.setSwipeBandFilter(band);
  }
}
