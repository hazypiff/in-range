import 'package:flutter_test/flutter_test.dart';
import 'package:in_range/features/beacon/proximity_classifier.dart';

void main() {
  // Hand-computed two-class GNB matching learn/train.py's formula.
  final model = {
    'schema': 'inrange-gnb-1',
    'classes': {
      'close': {
        'prior': 0.6,
        'stats': {
          'high_med': [-78.0, 16.0],
          'rate': [0.9, 0.04],
        },
      },
      'inrange': {
        'prior': 0.4,
        'stats': {
          'high_med': [-95.0, 16.0],
          'rate': [0.4, 0.04],
        },
      },
    },
  };

  group('GnbClassifier', () {
    test('classifies clearly separable inputs', () {
      final c = GnbClassifier.fromJson(model);
      expect(c.classify({'high_med': -80.0, 'rate': 0.85}), 'close');
      expect(c.classify({'high_med': -93.0, 'rate': 0.45}), 'inrange');
    });

    test('missing features skipped — falls back toward priors', () {
      final c = GnbClassifier.fromJson(model);
      // No evidence at all: argmax of priors (0.6 close vs 0.4 inrange).
      expect(c.classify({'high_med': null, 'rate': null}), 'close');
      // Only rate present: strong far-rate outweighs the prior.
      expect(c.classify({'high_med': null, 'rate': 0.4}), 'inrange');
    });

    test('scores expose margin for hysteresis/confidence', () {
      final c = GnbClassifier.fromJson(model);
      final s = c.scores({'high_med': -80.0, 'rate': 0.85});
      expect(s['close']!, greaterThan(s['inrange']!));
    });

    test('rejects non_production artifacts', () {
      final stamped = Map<String, dynamic>.from(model)..['non_production'] = true;
      expect(() => GnbClassifier.fromJson(stamped), throwsFormatException);
    });

    test('rejects unknown schema and empty models', () {
      expect(() => GnbClassifier.fromJson({'schema': 'nope', 'classes': {}}),
          throwsFormatException);
      expect(
          () => GnbClassifier.fromJson(
              {'schema': 'inrange-gnb-1', 'classes': <String, dynamic>{}}),
          throwsFormatException);
    });
  });

  group('RulesClassifier', () {
    test('iphone thresholds — closer tier owns its cutoff', () {
      // 2026-07-23 locked thresholds: Close ≥ −82, Near −83…−93, InRange < −93.
      final r = RulesClassifier.iphone();
      expect(r.classify({'high_med': -82.0}), 'close');
      expect(r.classify({'high_med': -83.0}), 'near');
      expect(r.classify({'high_med': -93.0}), 'near');
      expect(r.classify({'high_med': -94.0}), 'inrange');
      expect(r.classify({'high_med': null}), 'inrange');
    });

    test('s9 rules — median gate plus medium-slot near', () {
      final r = RulesClassifier.s9();
      expect(r.classify({'high_med': -78.0, 'high_n': 6, 'med_n': 0}), 'close');
      expect(r.classify({'high_med': -78.0, 'high_n': 3, 'med_n': 0}), 'inrange');
      expect(r.classify({'high_med': -90.0, 'high_n': 6, 'med_n': 2}), 'near');
      expect(r.classify({'high_med': null, 'high_n': 0, 'med_n': 0}), 'inrange');
    });
  });
}
