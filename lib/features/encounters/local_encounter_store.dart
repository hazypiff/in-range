import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_range/core/config/app_config.dart';
import 'package:in_range/core/db/local_db.dart';
import 'package:in_range/core/prefs/app_prefs.dart';
import 'package:in_range/features/beacon/range_estimator.dart';
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
    String? bestBand,
  })  : lastSeenAt = lastSeenAt ?? firstSeenAt,
        bestBand = bestBand ?? _bandFromRssi(bestRssi);

  final String correlationId;
  final DateTime firstSeenAt;
  DateTime lastSeenAt;
  int bestRssi;
  final String rangeType;
  final String? alias;

  /// Narrowest RangeEstimator band this peer ever achieved (feet_10 |
  /// feet_30 | feet_60). Persisted so restarts don't forget a close pass.
  final String bestBand;

  /// Fallback for rows persisted before the estimator existed. −75 best-RSSI
  /// ≈ the walk #3 in-hand floor; anything weaker can't claim NEAR, and
  /// without power-slot data mid-range can't be proven → widest band.
  static String _bandFromRssi(int bestRssi) =>
      bestRssi >= -75 ? 'feet_10' : 'feet_60';

  static const feetLifespan = Duration(hours: 24);

  DateTime get revealAt => firstSeenAt.add(AppConfig.encounterRevealDelay);

  DateTime? get expiresAt {
    if (rangeType.startsWith('feet')) {
      // From LAST seen: a peer you're still standing next to must not
      // expire mid-conversation because you first met 24h ago.
      return lastSeenAt.add(feetLifespan);
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

  String get estimatedFeetBand => bestBand;

  int get estimatedFeet {
    switch (estimatedFeetBand) {
      case 'feet_10':
        return 10;
      case 'feet_20': // legacy rows
      case 'feet_30':
        return 30;
      default:
        return 60;
    }
  }

  /// Narrower bands satisfy wider filters: a feet_10 encounter shows under
  /// a feet_60 filter, never the reverse.
  bool matchesBandFilter(String band) {
    if (band == 'any') return true;
    return rangeBandRank(estimatedFeetBand) <= rangeBandRank(band);
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
      // "Closest:" — this is the best moment ever observed, not a live
      // distance; qualitative until the mid tier is field-calibrated.
      return 'Closest: ${rangeBandLabel(bestBand)} · RSSI $bestRssi';
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
  /// Hard cap on locally-held encounters — a hostile advertiser can't grow
  /// state/disk without bound (reviewer #9). Far above any real crowd.
  static const int _maxLocalEncounters = 500;

  LocalEncounterStore(this._db, {bool hydrate = true}) : super(const {}) {
    if (hydrate) {
      _hydrate();
    }
  }

  /// Empty store for widget tests (no SQLite / platform plugins).
  LocalEncounterStore.empty()
      : _db = null,
        super(const {});

  final LocalDb? _db;
  Map<String, String> _aliases = {};

  /// Bumped by clear(); hydration checks it before publishing so a stale
  /// snapshot can't resurrect a cleared / signed-out account's cards
  /// (reviewer #19).
  int _generation = 0;

  Future<void> _hydrate() async {
    final db = _db;
    if (db == null) return;
    final gen = _generation;
    try {
      final aliases = await db.allAliases();
      final rows = await db.allSightings();
      final map = <String, LocalEncounter>{};
      for (final r in rows) {
        final id = r['correlation_id']! as String;
        final storedBand = r['best_band'] as String?;
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
          alias: aliases[id],
          bestBand:
              (storedBand == null || storedBand.isEmpty) ? null : storedBand,
        );
        if (!enc.isExpired) {
          map[id] = enc;
        } else {
          await db.deleteSighting(id);
        }
      }
      // A clear() or live sighting may have raced ahead while we were reading.
      // Don't clobber current state with the stale snapshot: merge in only
      // ids we don't already hold, and abort entirely if we were cleared.
      if (gen != _generation) {
        debugPrint('Hydrate discarded — store changed during load');
        return;
      }
      _aliases = aliases;
      state = {...map, ...state}; // live entries win over the disk snapshot
      debugPrint('Hydrated ${map.length} local sightings from SQLite');
    } catch (e) {
      debugPrint('Sighting hydrate failed: $e');
    }
  }

  Future<void> noteSighting({
    required String correlationId,
    required int rssi,
    required String rangeType,
    String? estimatedBand,
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
        bestBand: _validBand(estimatedBand),
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
        bestBand: _narrowest(existing.bestBand, _validBand(estimatedBand)),
      );
    }
    var updated = {...state, correlationId: next};
    // Global cap: a hostile peripheral rotating 16-byte payloads would
    // otherwise grow this map (and the SQLite table) without bound before the
    // server ever rejects a token (reviewer #9). Keep the most-recently-seen.
    if (updated.length > _maxLocalEncounters) {
      final keep = updated.values.toList()
        ..sort((a, b) => b.lastSeenAt.compareTo(a.lastSeenAt));
      final trimmed = keep.take(_maxLocalEncounters).toList();
      final trimmedIds = trimmed.map((e) => e.correlationId).toSet();
      for (final e in keep.skip(_maxLocalEncounters)) {
        await _db?.deleteSighting(e.correlationId);
      }
      updated = {
        for (final e in trimmed) e.correlationId: e,
        if (trimmedIds.contains(correlationId)) correlationId: next,
      };
    }
    state = updated;
    await _db?.upsertSighting(
      correlationId: next.correlationId,
      firstSeenMs: next.firstSeenAt.millisecondsSinceEpoch,
      lastSeenMs: next.lastSeenAt.millisecondsSinceEpoch,
      bestRssi: next.bestRssi,
      rangeType: next.rangeType,
      bestBand: next.bestBand,
    );
  }

  /// Raw advert sample straight off the scan path (unthrottled — every
  /// packet, unlike noteSighting's 5 s gate). Feeds calibration analysis.
  Future<void> logRssiSample({
    required String correlationId,
    required int rssi,
    required String power,
    required DateTime at,
  }) async {
    await _db?.logRssiSample(
      atMs: at.millisecondsSinceEpoch,
      correlationId: correlationId,
      rssi: rssi,
      power: power,
    );
  }

  /// Estimator can return 'none' (window raced empty) — treat as widest.
  static String? _validBand(String? band) =>
      (band == null || rangeBandRank(band) > 2) ? null : band;

  static String _narrowest(String a, String? b) {
    if (b == null) return a;
    return rangeBandRank(b) < rangeBandRank(a) ? b : a;
  }

  Future<void> setAlias(String correlationId, String alias) async {
    final db = _db;
    if (db == null) {
      _aliases = {..._aliases, correlationId: alias};
    } else {
      await db.setAlias(correlationId, alias);
      _aliases = await db.allAliases();
    }
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
          bestBand: e.bestBand,
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
    // Invalidate any in-flight hydration so a stale snapshot can't reappear
    // after the wipe (reviewer #19), and delete ALL local traces — sightings,
    // raw RSSI samples, and aliases — not just sightings (reviewer #18).
    _generation++;
    _aliases = {};
    await _db?.wipeAll();
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
