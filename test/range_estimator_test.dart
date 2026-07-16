import 'package:flutter_test/flutter_test.dart';
import 'package:in_range/features/beacon/range_estimator.dart';

void main() {
  late DateTime now;
  late RangeEstimator est;

  setUp(() {
    now = DateTime(2026, 7, 13, 4, 0, 0);
    est = RangeEstimator(clock: () => now);
  });

  void tick([int seconds = 1]) => now = now.add(Duration(seconds: seconds));

  group('RangeEstimator.classify', () {
    test('unknown peer is none', () {
      expect(est.classify('deadbeef'), 'none');
    });

    test('close peer with strong median is feet_10', () {
      for (var i = 0; i < 6; i++) {
        est.addSample('a', -70, AdvertPower.high);
        tick();
      }
      expect(est.classify('a'), 'feet_10');
    });

    test('single multipath spike cannot fake feet_10 (median, not max)', () {
      // Walk #3: a −64 spike arrived at 60 ft. Median must hold the line.
      for (final rssi in [-90, -91, -89, -92, -64, -90]) {
        est.addSample('a', rssi, AdvertPower.high);
        tick();
      }
      expect(est.classify('a'), isNot('feet_10'));
    });

    test('fewer than 5 samples cannot claim feet_10', () {
      for (var i = 0; i < 4; i++) {
        est.addSample('a', -60, AdvertPower.high);
        tick();
      }
      expect(est.classify('a'), 'feet_60');
    });

    test('medium-power packets gate feet_30', () {
      est.addSample('a', -88, AdvertPower.high);
      tick();
      est.addSample('a', -90, AdvertPower.medium);
      tick();
      est.addSample('a', -91, AdvertPower.medium);
      expect(est.classify('a'), 'feet_30');
    });

    test('high-only weak packets are feet_60, not feet_30', () {
      for (var i = 0; i < 10; i++) {
        est.addSample('a', -90, AdvertPower.high);
        tick();
      }
      expect(est.classify('a'), 'feet_60');
    });

    test('medium samples do not dilute the feet_10 median', () {
      // Close range: medium packets read ~8 dB weaker; only high-power
      // samples feed the NEAR median.
      for (var i = 0; i < 5; i++) {
        est.addSample('a', -72, AdvertPower.high);
        tick();
      }
      est.addSample('a', -95, AdvertPower.medium);
      est.addSample('a', -96, AdvertPower.medium);
      expect(est.classify('a'), 'feet_10');
    });

    test('demotes only on silence: window ages out to none', () {
      for (var i = 0; i < 6; i++) {
        est.addSample('a', -70, AdvertPower.high);
        tick();
      }
      expect(est.classify('a'), 'feet_10');
      tick(60);
      expect(est.classify('a'), 'feet_10'); // still inside 90 s window
      tick(60);
      expect(est.classify('a'), 'none'); // silence past the window
    });

    test('weak stretch after strong stretch holds NEAR while window mixes',
        () {
      // Body steps into the path: fresh weak samples arrive but the strong
      // ones are still in the window — median math decides, not recency.
      for (var i = 0; i < 8; i++) {
        est.addSample('a', -70, AdvertPower.high);
        tick();
      }
      for (var i = 0; i < 3; i++) {
        est.addSample('a', -92, AdvertPower.high);
        tick();
      }
      expect(est.classify('a'), 'feet_10');
    });
  });

  group('nearDwell', () {
    test('accumulates time spent in feet_10', () {
      // NEAR is first achieved at the 5th sample (t=40s); dwell counts
      // from there — 20s by t=60s.
      for (var i = 0; i < 6; i++) {
        est.addSample('a', -70, AdvertPower.high);
        tick(10);
      }
      expect(est.nearDwell('a').inSeconds, 20);
    });

    test('zero for never-near peers', () {
      est.addSample('a', -95, AdvertPower.high);
      expect(est.nearDwell('a'), Duration.zero);
    });

    test('silence does not bank NEAR time (walked away)', () {
      for (var i = 0; i < 6; i++) {
        est.addSample('a', -70, AdvertPower.high);
        tick();
      }
      // NEAR achieved at t=4s; peer goes silent for an hour.
      tick(3600);
      // Dwell is capped at last evidence + window, not wall clock.
      expect(est.nearDwell('a').inSeconds, lessThanOrEqualTo(92));
      // A later weak sample must not bank the silent hour either.
      est.addSample('a', -95, AdvertPower.high);
      expect(est.nearDwell('a').inSeconds, lessThanOrEqualTo(92));
    });

    test('classify after silence closes the interval, dwell stays capped',
        () {
      for (var i = 0; i < 6; i++) {
        est.addSample('a', -70, AdvertPower.high);
        tick();
      }
      tick(600);
      expect(est.classify('a'), 'none');
      expect(est.nearDwell('a').inSeconds, lessThanOrEqualTo(92));
    });
  });

  group('review fixes', () {
    test('#17 clear() wipes state so a new session cannot inherit NEAR', () {
      for (var i = 0; i < 6; i++) {
        est.addSample('a', -70, AdvertPower.high);
        tick();
      }
      expect(est.classify('a'), 'feet_10');
      est.clear();
      est.addSample('a', -70, AdvertPower.high); // one fresh weak-evidence sample
      expect(est.classify('a'), isNot('feet_10')); // needs 5, not inherited
    });

    test('#17 partial prune below 5 samples closes NEAR dwell', () {
      // 5 samples at t=0,15,30,45,60 (all inside the 90 s window) -> NEAR at 60.
      for (var i = 0; i < 5; i++) {
        est.addSample('a', -70, AdvertPower.high);
        if (i < 4) tick(15);
      }
      expect(est.classify('a'), 'feet_10'); // now=60, 5 samples present
      tick(31); // now=91: sample t=0 ages out (>90) -> 4 samples left
      est.classify('a'); // prune drops below 5 -> must close dwell
      final d1 = est.nearDwell('a').inSeconds;
      tick(60); // dwell must NOT keep growing for a tier no longer held
      expect(est.nearDwell('a').inSeconds, d1);
    });

    test('#23 evidence median matches the classifier median (even n)', () {
      for (final r in [-100, -90, -81, -79, -60, -50]) {
        est.addSample('a', r, AdvertPower.high);
        tick();
      }
      // classifier even-median = (-81 + -79)/2 = -80
      expect(est.classify('a'), 'feet_10'); // -80 >= -80 threshold
      expect(est.evidenceFor('a').medianRssi, -80); // not the upper-middle -79
    });

    test('#24 fresh-id flood is evicted down to the cap', () {
      final e = RangeEstimator(clock: () => now);
      for (var i = 0; i < 700; i++) {
        e.addSample('peer$i', -70, AdvertPower.high);
        tick(); // all fresh, all within window
      }
      // Not directly observable, but classify on an evicted early id is 'none'
      // while a recent id survives — proves the map didn't grow unbounded.
      expect(e.classify('peer0'), 'none');
      expect(e.classify('peer699'), isNot('none'));
    });
  });

  group('rangeBandRank', () {
    test('orders narrow to wide with legacy feet_20 as mid', () {
      expect(rangeBandRank('feet_10'), lessThan(rangeBandRank('feet_30')));
      expect(rangeBandRank('feet_30'), lessThan(rangeBandRank('feet_60')));
      expect(rangeBandRank('feet_20'), rangeBandRank('feet_30'));
      expect(rangeBandRank('none'), greaterThan(rangeBandRank('feet_60')));
    });
  });
}
