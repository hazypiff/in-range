import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

/// One access point as seen in a WiFi scan.
class ApSighting {
  const ApSighting({
    required this.bssid,
    required this.rssi,
    required this.freq,
    this.ageMs = 0,
  });

  /// Raw BSSID — NEVER leaves the device. Hash before upload (see [Fingerprint.hashed]).
  final String bssid;
  final int rssi;
  final int freq;

  /// How old this result is in the platform's scan cache. Android refreshes on
  /// its own schedule, so a "current" scan can contain minutes-old entries —
  /// which would silently attribute the previous room's APs to this one.
  final int ageMs;

  bool get is5GHz => freq >= 4900;

  /// A stale entry is worse than no entry for venue matching: it asserts you
  /// are somewhere you have already left.
  bool get isStale => ageMs > staleAfterMs;
  static const int staleAfterMs = 90 * 1000;
}

/// A phone's view of the surrounding access points at one moment.
///
/// Venue-level co-location: two phones in the same room see the same APs at
/// similar strengths. Published accuracy for fingerprint co-location is
/// 94-96% indoors (near/medium/far classes) but only 70-74% outdoors, and
/// WiFi alone tops out at ~67-78% for "within 2m" — so this is a VENUE
/// signal, never a distance tier. See docs/PROXIMITY_ALGORITHM.md §3.
class Fingerprint {
  Fingerprint(this.aps, {required this.takenAt});

  final List<ApSighting> aps;
  final DateTime takenAt;

  /// Weak APs are unstable and add noise — the published gate is -70 dBm.
  static const int minRssi = -70;

  /// Floor for the "powed" transform. Below this an AP counts as absent.
  static const int rssiFloor = -100;

  /// Exponent for the "powed" representation (Torres-Sospedra et al.): a
  /// non-linear transform of dBm that beat linear/normalized forms for nearly
  /// every similarity metric tested, because it penalizes fluctuation near
  /// strong signals and respects the logarithmic nature of RSS.
  static final double _beta = math.e;

  /// Usable APs: strong enough, fresh, and not our own travelling hotspot.
  List<ApSighting> usable(Set<String> excludedBssids) => aps
      .where((a) =>
          a.rssi >= minRssi &&
          !a.isStale &&
          !excludedBssids.contains(a.bssid.toLowerCase()))
      .toList();

  static double powed(int rssi) {
    if (rssi <= rssiFloor) return 0;
    final positive = (rssi - rssiFloor).toDouble(); // 0 … 100
    final normalized = positive / (-rssiFloor); // 0 … 1
    return math.pow(normalized, _beta).toDouble();
  }

  /// Privacy: BSSIDs are salted-hashed before they ever leave the device, so
  /// the server can compare fingerprints without learning which networks —
  /// and therefore which places — a user is near.
  Map<String, int> hashed(String salt) {
    final out = <String, int>{};
    for (final a in aps) {
      if (a.rssi < minRssi) continue;
      final mac = Hmac(sha256, utf8.encode(salt));
      final digest = mac.convert(utf8.encode(a.bssid.toLowerCase()));
      // 12 hex chars is ample to avoid collisions and keeps the payload small.
      out[digest.toString().substring(0, 12)] = a.rssi;
    }
    return out;
  }
}

/// The venue score for a pair of fingerprints, plus the parts it was built
/// from (kept for calibration — walk #4 logs these).
class VenueScore {
  const VenueScore({
    required this.score,
    required this.jaccard,
    required this.sorensen,
    required this.sharedAps,
    required this.totalAps,
  });

  /// 0…1. Higher = more likely the same place.
  final double score;
  final double jaccard;
  final double sorensen;
  final int sharedAps;
  final int totalAps;

  /// Not enough APs around to say anything (outdoors, rural). MUST degrade to
  /// "unknown", never to "different place" — abstaining is the honest answer.
  bool get isUnknown => totalAps < minApsForVerdict;

  static const int minApsForVerdict = 3;

  /// [NEEDS CALIBRATION] Starting thresholds from the literature; walk #4
  /// (indoor same-room / different-room stops) measures the real ones.
  static const double sameVenueThreshold = 0.60;
  static const double sameBuildingThreshold = 0.30;

  String get verdict {
    if (isUnknown) return 'unknown';
    if (score >= sameVenueThreshold) return 'same_venue';
    if (score >= sameBuildingThreshold) return 'same_building';
    return 'different_place';
  }

  @override
  String toString() =>
      'V=${score.toStringAsFixed(2)} (J=${jaccard.toStringAsFixed(2)} '
      'S=${sorensen.toStringAsFixed(2)} shared=$sharedAps/$totalAps) $verdict';
}

/// Compares two phones' WiFi fingerprints to decide "same place?".
class VenueMatcher {
  /// Weights for the two halves of the score. [NEEDS CALIBRATION]
  static const double wJaccard = 0.5;
  static const double wSorensen = 0.5;

  /// Compare two hashed fingerprints (the form that crosses the wire):
  /// {hashedBssid: rssi}.
  static VenueScore compare(Map<String, int> a, Map<String, int> b) {
    if (a.isEmpty || b.isEmpty) {
      return const VenueScore(
        score: 0,
        jaccard: 0,
        sorensen: 0,
        sharedAps: 0,
        totalAps: 0,
      );
    }

    final union = <String>{...a.keys, ...b.keys};
    final shared = a.keys.where(b.containsKey).length;

    // Co-visibility: do we see the same networks at all?
    final jaccard = union.isEmpty ? 0.0 : shared / union.length;

    // Signal-vector similarity: Sørensen (Bray-Curtis) distance over the
    // "powed" RSSI representation. This pairing beat all 51 metrics tested in
    // the literature — notably beating the obvious Euclidean default.
    var numerator = 0.0;
    var denominator = 0.0;
    for (final k in union) {
      final pa = a.containsKey(k) ? Fingerprint.powed(a[k]!) : 0.0;
      final pb = b.containsKey(k) ? Fingerprint.powed(b[k]!) : 0.0;
      numerator += (pa - pb).abs();
      denominator += pa + pb;
    }
    final distance = denominator == 0 ? 1.0 : numerator / denominator;
    final sorensen = (1.0 - distance).clamp(0.0, 1.0);

    final score = (wJaccard * jaccard + wSorensen * sorensen).clamp(0.0, 1.0);

    return VenueScore(
      score: score,
      jaccard: jaccard,
      sorensen: sorensen,
      sharedAps: shared,
      totalAps: union.length,
    );
  }
}

/// The fusion table from docs/PROXIMITY_ALGORITHM.md §5.
///
/// WiFi's job is to resolve BLE's ambiguity, never to overrule it:
/// a weak BLE signal means "far" OR "close but blocked", and only a second
/// radio can tell those apart. The row that earns this whole layer is
/// `feet_60 + same_venue -> blocked, not far` — the crowded-bar case that
/// BLE alone gets wrong every time.
class ProximityFusion {
  static const String veryClose = 'very_close'; // BLE feet_10
  static const String near = 'near'; // BLE feet_30, or blocked-in-venue
  static const String inRange = 'in_range'; // BLE feet_60
  static const String sameVenue = 'same_venue'; // WiFi only, BLE silent
  static const String none = 'none';

  /// [bleBand] is the RangeEstimator verdict; [venue] may be null when WiFi
  /// has nothing to say (no scan yet, or too few APs).
  static FusedProximity fuse({
    required String bleBand,
    VenueScore? venue,
  }) {
    final v = venue;
    final venueSaysSame =
        v != null && !v.isUnknown && v.verdict == 'same_venue';

    switch (bleBand) {
      case 'feet_10':
        // Strong BLE is self-sufficient; nothing can counterfeit it.
        return FusedProximity(veryClose, bleBand, v, 'strong BLE');
      case 'feet_20':
      case 'feet_30':
        return FusedProximity(near, bleBand, v, 'BLE medium-power slot');
      case 'feet_60':
        if (venueSaysSame) {
          // The row this layer exists for: in radio range AND demonstrably in
          // the same room => the weak signal is a body in the path, not distance.
          return FusedProximity(
              near, bleBand, v, 'BLE in range + same venue => blocked, not far');
        }
        return FusedProximity(inRange, bleBand, v, 'BLE presence only');
      default:
        // BLE silent.
        if (venueSaysSame) {
          return FusedProximity(
              sameVenue, bleBand, v, 'WiFi same venue, BLE silent');
        }
        return FusedProximity(none, bleBand, v, 'no signal');
    }
  }
}

class FusedProximity {
  const FusedProximity(this.proximity, this.bleBand, this.venue, this.reason);

  final String proximity;
  final String bleBand;
  final VenueScore? venue;
  final String reason;

  String get label {
    switch (proximity) {
      case ProximityFusion.veryClose:
        return 'Close By';
      case ProximityFusion.near:
        return 'Near By';
      case ProximityFusion.inRange:
        return 'In Range';
      case ProximityFusion.sameVenue:
        return 'Same Venue';
      default:
        return 'Nearby';
    }
  }

  @override
  String toString() => '$proximity (ble=$bleBand, venue=${venue ?? "n/a"}) — $reason';
}
