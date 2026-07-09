import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_range/core/config/app_config.dart';
import 'package:in_range/core/db/local_db.dart';
import 'package:in_range/core/prefs/app_prefs.dart';
import 'package:in_range/features/matches/match_store.dart';

/// Local BLE run-in with 24h feet lifespan + reveal delay.
class LocalEncounter {
  LocalEncounter({
    required this.correlationId,
    required this.firstSeenAt,
    required this.bestRssi,
    required this.rangeType,
    DateTime? lastSeenAt,
    this.alias,
  }) : lastSeenAt = lastSeenAt ?? firstSeenAt;

  final String correlationId;
  final DateTime firstSeenAt;
  DateTime lastSeenAt;
  int bestRssi;
  final String rangeType;
  final String? alias;

  static const feetLifespan = Duration(hours: 24);

  DateTime get revealAt => firstSeenAt.add(AppConfig.encounterRevealDelay);

  DateTime? get expiresAt {
    if (rangeType.startsWith('feet')) {
      return firstSeenAt.add(feetLifespan);
    }
    return null;
  }

  bool get isExpired {
    final exp = expiresAt;
    if (exp == null) return false;
    return DateTime.now().isAfter(exp);
  }

  bool get isVisible =>
      !isExpired && !DateTime.now().isBefore(revealAt);

  Duration get timeRemaining {
    final exp = expiresAt;
    if (exp == null) return Duration.zero;
    final d = exp.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  String get estimatedFeetBand {
    if (bestRssi >= -55) return 'feet_10';
    if (bestRssi >= -70) return 'feet_20';
    return 'feet_30';
  }

  int get estimatedFeet {
    switch (estimatedFeetBand) {
      case 'feet_10':
        return 10;
      case 'feet_20':
        return 20;
      default:
        return 30;
    }
  }

  bool matchesBandFilter(String band) {
    if (band == 'any') return true;
    return estimatedFeetBand == band;
  }

  String get displayName {
    if (alias != null && alias!.isNotEmpty) return alias!;
    final short = correlationId.length >= 6
        ? correlationId.substring(0, 6).toUpperCase()
        : correlationId.toUpperCase();
    return 'Nearby $short';
  }

  String get neighborhoodLabel {
    if (rangeType.startsWith('feet')) {
      return 'Near you · ~$estimatedFeet ft · RSSI $bestRssi';
    }
    return 'Nearby area';
  }

  Map<String, dynamic> toFeedRow() => {
        'encounter_id': correlationId.hashCode.abs(),
        'display_name': displayName,
        'neighborhood': neighborhoodLabel,
        'range_type':
            rangeType.startsWith('feet') ? estimatedFeetBand : rangeType,
        'encounter_time': firstSeenAt.toIso8601String(),
        'reveal_at': revealAt.toIso8601String(),
        'expires_at': expiresAt?.toIso8601String(),
        'time_remaining_ms': timeRemaining.inMilliseconds,
        'is_local': true,
        'correlation_id': correlationId,
        'best_rssi': bestRssi,
        'alias': alias,
        'estimated_feet_band': estimatedFeetBand,
      };
}

class LocalEncounterStore extends StateNotifier<Map<String, LocalEncounter>> {
  LocalEncounterStore(this._db) : super(const {}) {
    _hydrate();
  }

  final LocalDb _db;
  Map<String, String> _aliases = {};

  Future<void> _hydrate() async {
    try {
      _aliases = await _db.allAliases();
      final rows = await _db.allSightings();
      final map = <String, LocalEncounter>{};
      for (final r in rows) {
        final id = r['correlation_id']! as String;
        final enc = LocalEncounter(
          correlationId: id,
          firstSeenAt: DateTime.fromMillisecondsSinceEpoch(
            r['first_seen_ms']! as int,
          ),
          lastSeenAt: DateTime.fromMillisecondsSinceEpoch(
            r['last_seen_ms']! as int,
          ),
          bestRssi: r['best_rssi']! as int,
          rangeType: r['range_type']! as String,
          alias: _aliases[id],
        );
        if (!enc.isExpired) {
          map[id] = enc;
        } else {
          await _db.deleteSighting(id);
        }
      }
      state = map;
      debugPrint('Hydrated ${map.length} local sightings from SQLite');
    } catch (e) {
      debugPrint('Sighting hydrate failed: $e');
    }
  }

  Future<void> noteSighting({
    required String correlationId,
    required int rssi,
    required String rangeType,
  }) async {
    final existing = state[correlationId];
    final now = DateTime.now();
    late LocalEncounter next;
    if (existing == null) {
      next = LocalEncounter(
        correlationId: correlationId,
        firstSeenAt: now,
        bestRssi: rssi,
        rangeType: rangeType,
        alias: _aliases[correlationId],
      );
      debugPrint(
        'Local encounter first-seen corr=$correlationId '
        'rssi=$rssi band=${next.estimatedFeetBand}',
      );
    } else {
      final betterRssi = rssi > existing.bestRssi ? rssi : existing.bestRssi;
      next = LocalEncounter(
        correlationId: existing.correlationId,
        firstSeenAt: existing.firstSeenAt,
        bestRssi: betterRssi,
        rangeType: existing.rangeType,
        lastSeenAt: now,
        alias: existing.alias ?? _aliases[correlationId],
      );
    }
    state = {...state, correlationId: next};
    await _db.upsertSighting(
      correlationId: next.correlationId,
      firstSeenMs: next.firstSeenAt.millisecondsSinceEpoch,
      lastSeenMs: next.lastSeenAt.millisecondsSinceEpoch,
      bestRssi: next.bestRssi,
      rangeType: next.rangeType,
    );
  }

  Future<void> setAlias(String correlationId, String alias) async {
    await _db.setAlias(correlationId, alias);
    _aliases = await _db.allAliases();
    final e = state[correlationId];
    if (e != null) {
      state = {
        ...state,
        correlationId: LocalEncounter(
          correlationId: e.correlationId,
          firstSeenAt: e.firstSeenAt,
          bestRssi: e.bestRssi,
          rangeType: e.rangeType,
          lastSeenAt: e.lastSeenAt,
          alias: _aliases[correlationId],
        ),
      };
    }
  }

  String? aliasFor(String correlationId) => _aliases[correlationId];

  List<LocalEncounter> get visible {
    final list = state.values.where((e) => e.isVisible).toList()
      ..sort((a, b) => b.firstSeenAt.compareTo(a.firstSeenAt));
    return list;
  }

  List<LocalEncounter> get pendingReveal {
    final list = state.values
        .where((e) => !e.isExpired && !e.isVisible)
        .toList()
      ..sort((a, b) => a.revealAt.compareTo(b.revealAt));
    return list;
  }

  Future<void> clear() async {
    await _db.clearSightings();
    state = const {};
  }
}

final localDbProvider = Provider<LocalDb>((ref) {
  throw UnimplementedError('Override LocalDb in main()');
});

final localEncounterStoreProvider =
    StateNotifierProvider<LocalEncounterStore, Map<String, LocalEncounter>>(
  (ref) => LocalEncounterStore(ref.watch(localDbProvider)),
);

final visibleLocalEncountersProvider =
    Provider<List<Map<String, dynamic>>>((ref) {
  ref.watch(localEncounterStoreProvider);
  final store = ref.read(localEncounterStoreProvider.notifier);
  return store.visible.map((e) => e.toFeedRow()).toList();
});

final pendingRevealCountProvider = Provider<int>((ref) {
  ref.watch(localEncounterStoreProvider);
  return ref.read(localEncounterStoreProvider.notifier).pendingReveal.length;
});

final newEncounterCountProvider = Provider<int>((ref) {
  ref.watch(localEncounterStoreProvider);
  final matchStore = ref.watch(matchStoreProvider.notifier);
  final band = ref.watch(swipeBandFilterProvider);
  final store = ref.read(localEncounterStoreProvider.notifier);
  return store.visible.where((e) {
    if (!e.rangeType.startsWith('feet')) return false;
    if (matchStore.isDismissed(e.correlationId)) return false;
    if (!e.matchesBandFilter(band)) return false;
    return true;
  }).length;
});
