import 'dart:math' as math;

/// The classifier extension point for the self-learning calibration loop
/// (Work repo `learn/` — walk archives → fitted model → human-gated registry
/// → exported artifact → loaded here).
///
/// NOT wired into the runtime pipeline yet: RangeEstimator keeps the
/// hand-tuned S9 logic until a walk-validated model is PROMOTED and exported
/// (deferral decision 2026-07-18). When that happens, load the artifact with
/// [GnbClassifier.fromJson] and swap it in behind a flag — callers only see
/// [ProximityClassifier].
abstract class ProximityClassifier {
  /// Feature names match learn/train.py FEATURES: high_med, iqr_w, rate,
  /// high_n, med_n, venue_v, gps_delta. Missing evidence (silence, no WiFi,
  /// no GPS) is a null value — never an imputed zero.
  String classify(Map<String, double?> features);
}

/// The current hand-tuned thresholds as a [ProximityClassifier], so the
/// fitted model can be A/B'd against the exact baseline it must beat.
class RulesClassifier implements ProximityClassifier {
  RulesClassifier.iphone()
      : _s9 = false,
        closeCutoffDbm = -84,
        nearFloorDbm = -96;

  RulesClassifier.s9()
      : _s9 = true,
        closeCutoffDbm = -80,
        nearFloorDbm = double.negativeInfinity;

  final bool _s9;
  final double closeCutoffDbm;
  final double nearFloorDbm;

  @override
  String classify(Map<String, double?> features) {
    final med = features['high_med'];
    if (_s9) {
      if (med != null && med >= closeCutoffDbm && (features['high_n'] ?? 0) >= 5) {
        return 'close';
      }
      if ((features['med_n'] ?? 0) > 0) return 'near';
      return 'inrange';
    }
    if (med == null) return 'inrange';
    if (med >= closeCutoffDbm) return 'close';
    if (med >= nearFloorDbm) return 'near';
    return 'inrange';
  }
}

/// Gaussian naive Bayes inference over the `inrange-gnb-1` artifact schema.
/// Mirrors learn/train.py gnb_predict exactly: argmax over classes of
/// ln(prior) + Σ over PRESENT features of ln N(x | mean, var).
class GnbClassifier implements ProximityClassifier {
  GnbClassifier._(this._classes);

  factory GnbClassifier.fromJson(Map<String, dynamic> json) {
    if (json['schema'] != 'inrange-gnb-1') {
      throw FormatException('unsupported model schema: ${json['schema']}');
    }
    final classes = <String, _GnbClass>{};
    (json['classes'] as Map<String, dynamic>).forEach((name, c) {
      final stats = <String, List<double>>{};
      ((c as Map<String, dynamic>)['stats'] as Map<String, dynamic>)
          .forEach((f, mv) {
        final l = (mv as List).cast<num>();
        stats[f] = [l[0].toDouble(), l[1].toDouble()];
      });
      classes[name] = _GnbClass((c['prior'] as num).toDouble(), stats);
    });
    if (classes.isEmpty) throw const FormatException('model has no classes');
    return GnbClassifier._(classes);
  }

  final Map<String, _GnbClass> _classes;

  /// Log-scores per class (unnormalized). Exposed so a caller can derive a
  /// confidence (softmax) or apply hysteresis on the margin.
  Map<String, double> scores(Map<String, double?> features) {
    final out = <String, double>{};
    _classes.forEach((name, c) {
      var s = math.log(c.prior);
      c.stats.forEach((f, mv) {
        final x = features[f];
        if (x == null) return; // missing feature: skipped, never imputed
        final mean = mv[0], variance = mv[1];
        s += -0.5 * math.log(2 * math.pi * variance) -
            (x - mean) * (x - mean) / (2 * variance);
      });
      out[name] = s;
    });
    return out;
  }

  @override
  String classify(Map<String, double?> features) {
    final s = scores(features);
    return s.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }
}

class _GnbClass {
  _GnbClass(this.prior, this.stats);
  final double prior;
  final Map<String, List<double>> stats;
}
