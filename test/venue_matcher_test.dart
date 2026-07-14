import 'package:flutter_test/flutter_test.dart';
import 'package:in_range/features/beacon/venue_matcher.dart';

void main() {
  Map<String, int> fp(Map<String, int> m) => m;

  group('VenueMatcher.compare', () {
    test('identical fingerprints score ~1', () {
      final a = fp({'ap1': -45, 'ap2': -60, 'ap3': -70});
      final s = VenueMatcher.compare(a, a);
      expect(s.score, greaterThan(0.95));
      expect(s.verdict, 'same_venue');
    });

    test('same APs at similar strengths => same venue', () {
      final a = fp({'ap1': -45, 'ap2': -58, 'ap3': -66, 'ap4': -70});
      final b = fp({'ap1': -49, 'ap2': -61, 'ap3': -63, 'ap4': -68});
      final s = VenueMatcher.compare(a, b);
      expect(s.verdict, 'same_venue');
      expect(s.sharedAps, 4);
    });

    test('disjoint APs => different place', () {
      final a = fp({'ap1': -45, 'ap2': -50, 'ap3': -55});
      final b = fp({'zz1': -45, 'zz2': -50, 'zz3': -55});
      final s = VenueMatcher.compare(a, b);
      expect(s.jaccard, 0);
      expect(s.verdict, 'different_place');
    });

    test('partial overlap => same building, not same venue', () {
      final a = fp({'ap1': -45, 'ap2': -50, 'ap3': -80, 'ap4': -85});
      final b = fp({'ap3': -55, 'ap4': -60, 'zz1': -45, 'zz2': -50});
      final s = VenueMatcher.compare(a, b);
      expect(s.verdict, isNot('same_venue'));
      expect(s.sharedAps, 2);
    });

    test('too few APs => unknown, never "different place"', () {
      // Outdoors/rural: abstaining is the honest answer. Reporting "different
      // place" here would let a sparse-AP street corner veto a real encounter.
      final s = VenueMatcher.compare(fp({'ap1': -60}), fp({'zz1': -60}));
      expect(s.isUnknown, isTrue);
      expect(s.verdict, 'unknown');
    });

    test('empty fingerprint => unknown', () {
      final s = VenueMatcher.compare(fp({}), fp({'ap1': -50}));
      expect(s.isUnknown, isTrue);
    });

    test('powed transform is monotonic and floors at RSSI_MIN', () {
      expect(Fingerprint.powed(-100), 0);
      expect(Fingerprint.powed(-110), 0);
      expect(Fingerprint.powed(-40), greaterThan(Fingerprint.powed(-70)));
      expect(Fingerprint.powed(-70), greaterThan(Fingerprint.powed(-90)));
    });

    test('powed penalizes weak-signal differences less than strong ones', () {
      // The point of the non-linear representation: a 10 dB wobble down in the
      // noise should matter far less than a 10 dB difference near the AP.
      final strongGap = Fingerprint.powed(-40) - Fingerprint.powed(-50);
      final weakGap = Fingerprint.powed(-80) - Fingerprint.powed(-90);
      expect(strongGap, greaterThan(weakGap));
    });
  });

  group('Fingerprint', () {
    test('hashes BSSIDs — raw MACs never leave the device', () {
      final f = Fingerprint(
        const [
          ApSighting(bssid: 'AA:BB:CC:DD:EE:FF', rssi: -50, freq: 2412),
          ApSighting(bssid: '11:22:33:44:55:66', rssi: -95, freq: 2412),
        ],
        takenAt: DateTime(2026),
      );
      final h = f.hashed('salty');
      expect(h.length, 1); // -95 is below the -70 usable gate
      expect(h.keys.first, isNot(contains('AA:BB')));
      expect(h.keys.first.length, 12);
      expect(h.values.first, -50);
    });

    test('same BSSID + same salt => same hash (comparable across phones)', () {
      final a = Fingerprint(
        const [ApSighting(bssid: 'AA:BB:CC:DD:EE:FF', rssi: -50, freq: 2412)],
        takenAt: DateTime(2026),
      ).hashed('shared-salt');
      final b = Fingerprint(
        const [ApSighting(bssid: 'aa:bb:cc:dd:ee:ff', rssi: -55, freq: 2412)],
        takenAt: DateTime(2026),
      ).hashed('shared-salt');
      expect(a.keys.first, b.keys.first); // case-insensitive, salt-stable
    });

    test('excludes STALE cache entries — the room you already left', () {
      // Android serves cached scan results; an entry minutes old would assert
      // you are still in the previous room. Worse than no entry at all.
      final f = Fingerprint(
        const [
          ApSighting(bssid: 'AA:AA:AA:AA:AA:AA', rssi: -40, freq: 2412, ageMs: 2000),
          ApSighting(bssid: 'BB:BB:BB:BB:BB:BB', rssi: -40, freq: 2412, ageMs: 300000),
        ],
        takenAt: DateTime(2026),
      );
      final usable = f.usable({});
      expect(usable.length, 1);
      expect(usable.first.bssid, 'AA:AA:AA:AA:AA:AA');
    });

    test('excludes travelling hotspot BSSIDs', () {
      final f = Fingerprint(
        const [
          ApSighting(bssid: 'AA:AA:AA:AA:AA:AA', rssi: -40, freq: 2412),
          ApSighting(bssid: 'BB:BB:BB:BB:BB:BB', rssi: -50, freq: 2412),
        ],
        takenAt: DateTime(2026),
      );
      final usable = f.usable({'aa:aa:aa:aa:aa:aa'});
      expect(usable.length, 1);
      expect(usable.first.bssid, 'BB:BB:BB:BB:BB:BB');
    });
  });

  group('ProximityFusion — the decision table', () {
    VenueScore venue(double score, {int aps = 10}) => VenueScore(
          score: score,
          jaccard: score,
          sorensen: score,
          sharedAps: aps,
          totalAps: aps,
        );

    test('strong BLE is self-sufficient — WiFi cannot downgrade it', () {
      final f = ProximityFusion.fuse(
        bleBand: 'feet_10',
        venue: venue(0.0),
      );
      expect(f.proximity, ProximityFusion.veryClose);
    });

    test('THE KEY ROW: in-range + same venue => blocked, not far', () {
      final f = ProximityFusion.fuse(
        bleBand: 'feet_60',
        venue: venue(0.8),
      );
      expect(f.proximity, ProximityFusion.near);
      expect(f.reason, contains('blocked'));
    });

    test('in-range + different place => stays in range', () {
      final f = ProximityFusion.fuse(bleBand: 'feet_60', venue: venue(0.1));
      expect(f.proximity, ProximityFusion.inRange);
    });

    test('in-range + WiFi unknown (outdoors) => stays in range, no guessing',
        () {
      final f = ProximityFusion.fuse(
        bleBand: 'feet_60',
        venue: venue(0.0, aps: 1), // below minApsForVerdict => unknown
      );
      expect(f.proximity, ProximityFusion.inRange);
    });

    test('in-range with no WiFi data at all => stays in range', () {
      final f = ProximityFusion.fuse(bleBand: 'feet_60', venue: null);
      expect(f.proximity, ProximityFusion.inRange);
    });

    test('BLE silent + same venue => same venue (crowd / pocketed phone)', () {
      final f = ProximityFusion.fuse(bleBand: 'none', venue: venue(0.9));
      expect(f.proximity, ProximityFusion.sameVenue);
    });

    test('BLE silent + nothing from WiFi => no encounter', () {
      final f = ProximityFusion.fuse(bleBand: 'none', venue: null);
      expect(f.proximity, ProximityFusion.none);
    });

    test('medium-power slot keeps Near even when WiFi disagrees', () {
      // The medium-slot gate is physical; a WiFi mismatch (e.g. standing in a
      // doorway between two rooms) must not override it.
      final f = ProximityFusion.fuse(bleBand: 'feet_30', venue: venue(0.05));
      expect(f.proximity, ProximityFusion.near);
    });

    test('labels are qualitative, never fake feet', () {
      expect(ProximityFusion.fuse(bleBand: 'feet_10', venue: null).label,
          'Very close');
      expect(ProximityFusion.fuse(bleBand: 'feet_60', venue: null).label,
          'In range');
      expect(ProximityFusion.fuse(bleBand: 'none', venue: venue(0.9)).label,
          'Same venue');
    });
  });
}
