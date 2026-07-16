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
  ///
  /// Runs on the SAME filtered set as [usable] — strong, fresh, non-excluded —
  /// so the uploaded fingerprint can't assert a stale AP from a room already
  /// left, or the travelling hotspot. (Reviewer #22.)
  Map<String, int> hashed(String salt, {Set<String> excludedBssids = const {}}) {
    final out = <String, int>{};
    for (final a in usable(excludedBssids)) {
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

/// How much evidence stood behind the BLE tier — the volume that turns a
/// classification into a *confident* one. Null for rows without live data
/// (e.g. server-hydrated cards), which fall back to a tier-only confidence.
class ProximityEvidence {
  const ProximityEvidence({
    required this.bleSampleCount,
    required this.dwellSeconds,
    this.medianRssi,
  });

  final int bleSampleCount;
  final int dwellSeconds;
  final int? medianRssi;

  /// Enough samples to trust the median rather than a lucky spike.
  static const int solidSamples = 20;

  /// Dwell at which a tier is fully "earned" (matches the 30 s dwell rule).
  static const int solidDwellSeconds = 30;
}

/// Fuse the radios into a proximity tier AND a confidence in it.
///
/// The weighting principle — the whole point of the arrangement — is that
/// each radio only carries weight on the question it is actually good at:
///
///   * BLE is the distance backbone. Its evidence (median RSSI, sample count,
///     dwell) SETS the tier and the base confidence. Nothing else can assert
///     "close".
///   * WiFi CORROBORATES placement; it never sets distance. Agreement raises
///     confidence; a conflict (BLE says close, WiFi says different building)
///     lowers it — that pattern smells like a relay or a bad reading. Its one
///     decisive power is the blocked-vs-far case (feet_60 + same venue).
///   * GPS is a pure veto (applied server-side): implausible pairs are dropped
///     before they get here, so it contributes ZERO positive confidence. A
///     coarse radio must not be allowed to make anything look more certain.
///
/// Weights below are provisional — the starting point for the fusion research
/// and walk-#4 data to refine, not final constants.
class ProximityFusion {
  static const String veryClose = 'very_close'; // BLE feet_10
  static const String near = 'near'; // BLE feet_30, or blocked-in-venue
  static const String inRange = 'in_range'; // BLE feet_60
  static const String sameVenue = 'same_venue'; // WiFi only, BLE silent
  static const String none = 'none';

  // Corroboration weights: how far a WiFi verdict can move confidence.
  static const double _wifiAgreeBoost = 0.4; // toward 1.0 when WiFi agrees
  static const double _wifiConflictPenalty = 0.5; // ×0.5 when WiFi conflicts

  /// [bleBand] is the RangeEstimator verdict; [venue] may be null when WiFi
  /// has nothing to say; [evidence] carries the BLE sample volume/dwell.
  static FusedProximity fuse({
    required String bleBand,
    VenueScore? venue,
    ProximityEvidence? evidence,
  }) {
    final v = venue;
    final venueVerdict = (v == null || v.isUnknown) ? null : v.verdict;
    final venueSaysSame = venueVerdict == 'same_venue';
    final venueSaysDifferent = venueVerdict == 'different_place';

    String proximity;
    String reason;
    // Does WiFi corroborate, conflict with, or abstain from the BLE tier?
    // +1 agree, -1 conflict, 0 abstain.
    int corroboration;

    switch (bleBand) {
      case 'feet_10':
        proximity = veryClose;
        reason = 'strong BLE';
        // Close by BLE but far apart by WiFi => contradictory (relay/error).
        corroboration = venueSaysSame ? 1 : (venueSaysDifferent ? -1 : 0);
        break;
      case 'feet_20':
      case 'feet_30':
        proximity = near;
        reason = 'BLE medium-power slot';
        corroboration = venueSaysSame ? 1 : (venueSaysDifferent ? -1 : 0);
        break;
      case 'feet_60':
        if (venueSaysSame) {
          proximity = near;
          reason = 'BLE in range + same venue => blocked, not far';
          corroboration = 1;
        } else {
          proximity = inRange;
          reason = 'BLE presence only';
          // "In range" + "different place" is consistent (genuinely far),
          // so a different-place verdict AGREES here rather than conflicts.
          corroboration = venueSaysDifferent ? 1 : 0;
        }
        break;
      default:
        if (venueSaysSame) {
          proximity = sameVenue;
          reason = 'WiFi same venue, BLE silent';
          corroboration = 0; // WiFi alone; no BLE to corroborate
        } else {
          proximity = none;
          reason = 'no signal';
          corroboration = 0;
        }
    }

    final confidence =
        _confidence(proximity, corroboration, evidence, hasWifi: v != null);
    return FusedProximity(proximity, bleBand, v, reason, confidence);
  }

  static double _confidence(
    String proximity,
    int corroboration,
    ProximityEvidence? evidence, {
    required bool hasWifi,
  }) {
    if (proximity == none) return 0;

    // Base confidence from BLE evidence volume. Without evidence (server
    // cards), a tier that fired at all gets a neutral 0.6.
    double base;
    if (evidence == null) {
      base = proximity == sameVenue ? 0.55 : 0.6;
    } else if (proximity == sameVenue) {
      // Comes from WiFi alone (BLE silent) — cap it: venue co-location is
      // ~94% indoors but carries no distance corroboration here.
      base = 0.55;
    } else {
      final vol = (evidence.bleSampleCount / ProximityEvidence.solidSamples)
          .clamp(0.0, 1.0);
      final dwell = (evidence.dwellSeconds / ProximityEvidence.solidDwellSeconds)
          .clamp(0.0, 1.0);
      // Floor 0.4 for firing at all, then earn the rest from volume + dwell.
      base = (0.4 + 0.3 * vol + 0.3 * dwell).clamp(0.0, 1.0);
    }

    // WiFi corroboration modulates — but only when WiFi actually weighed in.
    if (corroboration > 0) {
      base = base + (1.0 - base) * _wifiAgreeBoost;
    } else if (corroboration < 0) {
      base = base * _wifiConflictPenalty;
    }
    return double.parse(base.clamp(0.0, 1.0).toStringAsFixed(3));
  }
}

class FusedProximity {
  const FusedProximity(
    this.proximity,
    this.bleBand,
    this.venue,
    this.reason, [
    this.confidence = 0.6,
  ]);

  final String proximity;
  final String bleBand;
  final VenueScore? venue;
  final String reason;

  /// 0…1 — how much the weighted evidence backs this tier. Drives whether an
  /// alert fires (a trustworthy Close By beats a fast one) and how the UI
  /// hedges ("Close By" vs "probably Close By").
  final double confidence;

  bool get isHighConfidence => confidence >= 0.75;

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
  String toString() =>
      '$proximity conf=${confidence.toStringAsFixed(2)} '
      '(ble=$bleBand, venue=${venue ?? "n/a"}) — $reason';
}
