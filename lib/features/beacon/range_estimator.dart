import 'dart:collection';

/// Which transmit-power slot a received advert was sent in.
///
/// The beacon alternates high/medium TX power and stamps the level into the
/// advert (`includePowerLevel`). Medium-power packets physically die at
/// mid-range while high-power carries past 60 ft (walks #2/#3), so
/// "heard on medium" is itself a distance gate that RSSI can't fake.
enum AdvertPower { high, medium }

class _Sample {
  const _Sample(this.at, this.rssi, this.power);
  final DateTime at;
  final int rssi;
  final AdvertPower power;
}

class _PeerTrack {
  final Queue<_Sample> samples = Queue();
  DateTime? nearSince;
  Duration nearAccum = Duration.zero;
}

/// Calibrated range classifier — walk #3 (2026-07-13, S9 @ txPowerHigh) is
/// the baseline for every constant here.
///
/// Bands (narrowest satisfied wins):
/// - feet_10: ≥5 high-power samples in window AND their median RSSI ≥ −80.
///   Close range reads −66…−73, 10 ft+ reads −83…−92 (~10 dB median gap).
///   Median, not max: multipath spikes reached −64 at 60 ft.
/// - feet_30: ≥2 medium-power samples in window. Interim gate until walk #4
///   measures medium's true cutoff with verified distances.
/// - feet_60: any sample in window. Walk #3: continuous ~1 pkt/s at every
///   stop through 60 ft, silence beyond ~80 ft.
/// - none: window empty (only silence ever demotes — a weak stretch just
///   means bodies in the 2.4 GHz path).
class RangeEstimator {
  RangeEstimator({
    this.window = const Duration(seconds: 90),
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final Duration window;
  final DateTime Function() _now;

  static const int nearMedianDbm = -80;
  static const int nearMinSamples = 5;
  static const int midMinMediumSamples = 2;
  static const int _maxPeers = 500;
  static const int _maxSamplesPerPeer = 256;

  final Map<String, _PeerTrack> _peers = {};

  void addSample(String correlationId, int rssi, AdvertPower power) {
    final now = _now();
    final track = _peers.putIfAbsent(correlationId, _PeerTrack.new);
    // Prune BEFORE appending: if the window went silent, the stale NEAR
    // interval must close at its evidence expiry — appending first would
    // keep the window non-empty and bank the whole silent gap as dwell.
    _prune(track, now);
    track.samples.addLast(_Sample(now, rssi, power));
    while (track.samples.length > _maxSamplesPerPeer) {
      track.samples.removeFirst();
    }
    _updateNearDwell(correlationId, track, now);

    if (_peers.length > _maxPeers) {
      final stale = _peers.entries
          .where((e) =>
              e.value.samples.isEmpty ||
              now.difference(e.value.samples.last.at) > window)
          .map((e) => e.key)
          .toList();
      stale.forEach(_peers.remove);
    }
  }

  /// Narrowest band the current window supports: feet_10 | feet_30 |
  /// feet_60 | none.
  String classify(String correlationId) {
    final track = _peers[correlationId];
    if (track == null) return 'none';
    _prune(track, _now());
    if (track.samples.isEmpty) return 'none';
    if (_isNear(track)) return 'feet_10';
    final mediumCount =
        track.samples.where((s) => s.power == AdvertPower.medium).length;
    if (mediumCount >= midMinMediumSamples) return 'feet_30';
    return 'feet_60';
  }

  /// Cumulative time this peer has held the feet_10 band (session-scoped).
  /// An open NEAR interval never accrues past the last evidence + window —
  /// silence (peer walked away) must not bank wall-clock time.
  Duration nearDwell(String correlationId) {
    final track = _peers[correlationId];
    if (track == null) return Duration.zero;
    final since = track.nearSince;
    if (since == null) return track.nearAccum;
    var end = _now();
    if (track.samples.isNotEmpty) {
      final cap = track.samples.last.at.add(window);
      if (end.isAfter(cap)) end = cap;
    }
    if (end.isBefore(since)) end = since;
    return track.nearAccum + end.difference(since);
  }

  bool _isNear(_PeerTrack track) {
    final highRssi = track.samples
        .where((s) => s.power == AdvertPower.high)
        .map((s) => s.rssi)
        .toList();
    if (highRssi.length < nearMinSamples) return false;
    highRssi.sort();
    final mid = highRssi.length ~/ 2;
    final median = highRssi.length.isOdd
        ? highRssi[mid].toDouble()
        : (highRssi[mid - 1] + highRssi[mid]) / 2.0;
    return median >= nearMedianDbm;
  }

  void _updateNearDwell(String corr, _PeerTrack track, DateTime now) {
    final near = _isNear(track);
    if (near && track.nearSince == null) {
      track.nearSince = now;
    } else if (!near && track.nearSince != null) {
      // Cap the interval at last-evidence + window so a long silent gap
      // before this demoting sample doesn't get banked as NEAR time.
      var end = now;
      if (track.samples.length >= 2) {
        final prevAt = track.samples.elementAt(track.samples.length - 2).at;
        final cap = prevAt.add(window);
        if (end.isAfter(cap)) end = cap;
      }
      if (end.isBefore(track.nearSince!)) end = track.nearSince!;
      track.nearAccum += end.difference(track.nearSince!);
      track.nearSince = null;
    }
  }

  void _prune(_PeerTrack track, DateTime now) {
    DateTime? lastRemovedAt;
    while (track.samples.isNotEmpty &&
        now.difference(track.samples.first.at) > window) {
      lastRemovedAt = track.samples.removeFirst().at;
    }
    // Window emptied by silence: close any open NEAR interval at the
    // moment its evidence expired, not at whenever we next look.
    if (track.samples.isEmpty && track.nearSince != null) {
      var end = (lastRemovedAt ?? track.nearSince!).add(window);
      if (end.isBefore(track.nearSince!)) end = track.nearSince!;
      track.nearAccum += end.difference(track.nearSince!);
      track.nearSince = null;
    }
  }

  void clear() => _peers.clear();
}

/// User-facing product tiers (docs/PROXIMITY_TIERS.md). Deliberately
/// qualitative until the middle tier is field-calibrated (walk #4). The S9
/// data supports "Close By" and "In Range" with confidence; exact-feet
/// claims would overpromise past ~15 ft, where RSSI goes flat.
String rangeBandLabel(String band) {
  switch (band) {
    case 'feet_10':
      return 'Close By';
    case 'feet_20':
    case 'feet_30':
      return 'Near By';
    case 'feet_60':
      return 'In Range';
    default:
      return 'Nearby';
  }
}

/// Band ordering for filters: an encounter in a narrower band always
/// satisfies a wider filter (feet_10 counts under a feet_60 filter).
int rangeBandRank(String band) {
  switch (band) {
    case 'feet_10':
      return 0;
    case 'feet_20': // legacy rows from pre-calibration builds
    case 'feet_30':
      return 1;
    case 'feet_60':
      return 2;
    default:
      return 3;
  }
}
