import 'package:in_range/core/config/app_config.dart';
import 'package:in_range/features/beacon/range_estimator.dart';
import 'package:in_range/features/encounters/local_encounter_store.dart';

/// Unified swipe deck item — local BLE run-in or server encounter.
class SwipeCard {
  SwipeCard({
    required this.id,
    required this.displayLabel,
    required this.neighborhood,
    required this.rangeType,
    required this.isServer,
    this.photoUrls = const [],
    this.otherUserId,
    this.encounterTime,
    this.expiresAt,
    this.bestRssi,
    this.local,
    this.sessionCount = 1,
    this.distinctDayCount = 1,
    this.firstSeenAt,
  });

  /// Dismiss / swipe key: server encounter_id as string, or local corr-id.
  final String id;
  final String displayLabel;
  final String neighborhood;
  final String rangeType;
  final bool isServer;
  final List<String> photoUrls;
  final String? otherUserId;
  final DateTime? encounterTime;
  final DateTime? expiresAt;
  final int? bestRssi;
  final LocalEncounter? local;

  /// Recurrence (server only): how many distinct times you've crossed paths.
  final int sessionCount;
  final int distinctDayCount;
  final DateTime? firstSeenAt;

  bool get isFeet => rangeType.startsWith('feet');

  /// A face you keep running into. Familiarity is one of the strongest
  /// signals a proximity app has — surface it, and rank it higher.
  bool get isRecurring => sessionCount > 1;

  /// Short human phrase for the recurrence, or null when it's a first meeting.
  String? get recurrenceLabel {
    if (sessionCount <= 1) return null;
    if (distinctDayCount > 1) {
      return 'Crossed paths $sessionCount times · $distinctDayCount days';
    }
    return 'Crossed paths $sessionCount times';
  }

  Duration get timeRemaining {
    final exp = expiresAt;
    if (exp == null) return Duration.zero;
    final d = exp.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  double get expiryProgress {
    if (expiresAt == null) return 0;
    // Fraction of the fixed feet lifetime still left. Using the lifetime (not
    // expires−encounterTime) keeps the bar correct for recurring encounters,
    // whose expiry now runs from last-seen, not the first meeting (#20).
    final total = LocalEncounter.feetLifespan.inMilliseconds;
    if (total <= 0) return 0;
    return (timeRemaining.inMilliseconds / total).clamp(0.0, 1.0);
  }

  bool matchesBandFilter(String band) {
    if (band == 'any') return true;
    if (local != null) return local!.matchesBandFilter(band);
    // Server cards use the same narrower-satisfies-wider rank rule as
    // local encounters; miles rows only match their exact filter.
    if (rangeType.startsWith('feet') && band.startsWith('feet')) {
      return rangeBandRank(rangeType) <= rangeBandRank(band);
    }
    return rangeType == band || rangeType.startsWith(band);
  }

  factory SwipeCard.fromServer(Map<String, dynamic> row) {
    final encId = row['encounter_id'];
    final id = encId?.toString() ?? '';
    final photos = (row['photo_urls'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];
    final rt = row['range_type']?.toString() ?? 'feet_10';
    final et = DateTime.tryParse(row['encounter_time']?.toString() ?? '');
    final lastSeen =
        DateTime.tryParse(row['last_seen_at']?.toString() ?? '');
    DateTime? exp;
    if (rt.startsWith('feet')) {
      // 24h lifetime runs from LAST seen, not first meeting — a peer seen again
      // just now must not already read "0s remaining" (reviewer #20).
      final base = lastSeen ?? et;
      if (base != null) exp = base.add(LocalEncounter.feetLifespan);
    }
    return SwipeCard(
      id: id,
      displayLabel: 'Someone nearby',
      neighborhood: row['neighborhood']?.toString() ?? 'Nearby',
      rangeType: rt,
      isServer: true,
      photoUrls: photos,
      otherUserId: row['other_user_id']?.toString(),
      encounterTime: et,
      expiresAt: exp,
      sessionCount: (row['session_count'] as int?) ?? 1,
      distinctDayCount: (row['distinct_day_count'] as int?) ?? 1,
      firstSeenAt: DateTime.tryParse(row['first_seen_at']?.toString() ?? ''),
    );
  }

  factory SwipeCard.fromLocal(LocalEncounter e) {
    return SwipeCard(
      id: e.correlationId,
      displayLabel: 'Someone nearby',
      neighborhood: e.neighborhoodLabel,
      rangeType: e.rangeType.startsWith('feet')
          ? e.estimatedFeetBand
          : e.rangeType,
      isServer: false,
      photoUrls: const [],
      encounterTime: e.firstSeenAt,
      expiresAt: e.expiresAt,
      bestRssi: e.bestRssi,
      local: e,
    );
  }
}

/// Prefer server encounters when cloud is live; always include undismissed
/// local BLE cards not already represented by a server other_user_id.
List<SwipeCard> buildHybridSwipeDeck({
  required List<Map<String, dynamic>> serverRows,
  required List<LocalEncounter> localVisible,
  required bool Function(String id) isDismissed,
  required Set<String> blocked,
}) {
  final cards = <SwipeCard>[];
  final serverOtherIds = <String>{};

  if (AppConfig.hasRealSupabase && AppConfig.preferServerFeeds) {
    for (final row in serverRows) {
      final c = SwipeCard.fromServer(row);
      if (c.id.isEmpty) continue;
      if (isDismissed(c.id)) continue;
      final other = c.otherUserId;
      if (other != null) {
        if (blocked.contains(other) || isDismissed(other)) continue;
        serverOtherIds.add(other);
      }
      cards.add(c);
    }
  }

  for (final e in localVisible) {
    if (isDismissed(e.correlationId)) continue;
    if (blocked.contains(e.correlationId)) continue;
    // If we only have server cards, still show local BLE for dual-phone lab
    // unless cloud already surfaced this peer (we can't map corr→uid reliably).
    cards.add(SwipeCard.fromLocal(e));
  }

  // Server cards first (real profiles with photos), then FAMILIAR FACES first —
  // preserve the server's session_count ordering instead of flattening it back
  // to recency (reviewer #20), then most-recent.
  cards.sort((a, b) {
    if (a.isServer != b.isServer) return a.isServer ? -1 : 1;
    if (a.sessionCount != b.sessionCount) {
      return b.sessionCount.compareTo(a.sessionCount);
    }
    final at = a.encounterTime ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bt = b.encounterTime ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bt.compareTo(at);
  });

  return cards;
}
