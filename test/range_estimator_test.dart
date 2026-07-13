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

  group('rangeBandRank', () {
    test('orders narrow to wide with legacy feet_20 as mid', () {
      expect(rangeBandRank('feet_10'), lessThan(rangeBandRank('feet_30')));
      expect(rangeBandRank('feet_30'), lessThan(rangeBandRank('feet_60')));
      expect(rangeBandRank('feet_20'), rangeBandRank('feet_30'));
      expect(rangeBandRank('none'), greaterThan(rangeBandRank('feet_60')));
    });
  });
}
