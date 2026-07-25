import 'package:flutter_test/flutter_test.dart';
import 'package:in_range/features/beacon/venue_anchor_service.dart';

void main() {
  VenueAnchor anchor(
    String id, {
    double lat = 51.5,
    double lon = -0.12,
    double radiusM = 250,
    String? hashedBssid,
  }) =>
      VenueAnchor(
        id: id,
        lat: lat,
        lon: lon,
        radiusM: radiusM,
        hashedBssid: hashedBssid,
      );

  group('upsert validation', () {
    test('accepts a well-formed anchor', () {
      final s = VenueAnchorService();
      expect(s.upsert(anchor('a')), isTrue);
      expect(s.anchors.single.id, 'a');
    });

    test('rejects a blank id', () {
      final s = VenueAnchorService();
      expect(s.upsert(anchor('  ')), isFalse);
      expect(s.anchors, isEmpty);
    });

    test('rejects out-of-range or non-finite coordinates', () {
      final s = VenueAnchorService();
      expect(s.upsert(anchor('a', lat: 91)), isFalse);
      expect(s.upsert(anchor('b', lat: -90.1)), isFalse);
      expect(s.upsert(anchor('c', lon: 180.1)), isFalse);
      expect(s.upsert(anchor('d', lat: double.nan)), isFalse);
      expect(s.upsert(anchor('e', lon: double.infinity)), isFalse);
      expect(s.anchors, isEmpty);
    });

    test('rejects a non-positive or non-finite radius', () {
      final s = VenueAnchorService();
      expect(s.upsert(anchor('a', radiusM: 0)), isFalse);
      expect(s.upsert(anchor('b', radiusM: -5)), isFalse);
      expect(s.upsert(anchor('c', radiusM: double.nan)), isFalse);
      expect(s.anchors, isEmpty);
    });

    // A server-supplied 5 km venue must degrade to the largest monitorable
    // region, not vanish — and a 20 m one is not a venue fence at all.
    test('clamps the radius into the monitorable band', () {
      final s = VenueAnchorService();
      s.upsert(anchor('small', radiusM: 20));
      s.upsert(anchor('huge', radiusM: 5000));
      expect(s.anchorById('small')!.radiusM, VenueAnchorService.minRadiusM);
      expect(s.anchorById('huge')!.radiusM, VenueAnchorService.maxRadiusM);
    });
  });

  group('capacity', () {
    // iOS hard-caps region monitoring at 20 regions per app; a 21st
    // registration silently fails, so the cap must live here.
    test('evicts the oldest anchor when full', () {
      final s = VenueAnchorService(maxAnchors: 3);
      s.upsert(anchor('a'));
      s.upsert(anchor('b'));
      s.upsert(anchor('c'));
      expect(s.upsert(anchor('d')), isTrue);

      expect(s.anchorById('a'), isNull);
      expect(s.anchors.map((a) => a.id), ['b', 'c', 'd']);
    });

    test('replacing an existing id never evicts', () {
      final s = VenueAnchorService(maxAnchors: 2);
      s.upsert(anchor('a'));
      s.upsert(anchor('b'));
      s.upsert(anchor('a', radiusM: 500));

      expect(s.anchors.length, 2);
      expect(s.anchorById('a')!.radiusM, 500);
      expect(s.anchorById('b'), isNotNull);
    });
  });

  group('region descriptors', () {
    test('carry exactly what a CLCircularRegion needs', () {
      final s = VenueAnchorService();
      s.upsert(anchor('v1',
          lat: 40.7, lon: -74.0, radiusM: 300, hashedBssid: 'abc123def456'));

      final d = s.regionDescriptors().single;
      expect(d['id'], 'v1');
      expect(d['lat'], 40.7);
      expect(d['lon'], -74.0);
      expect(d['radius'], 300.0);
      expect(d['onEnter'], isTrue);
      expect(d['onExit'], isTrue);
      // The BSSID is corroboration metadata, not a region property — it must
      // not leak into the payload handed to native.
      expect(d.containsKey('hashedBssid'), isFalse);
    });

    test('onChanged fires the full snapshot on every mutation', () {
      final s = VenueAnchorService();
      final snapshots = <List<String>>[];
      s.onChanged = (d) =>
          snapshots.add([for (final m in d) m['id'] as String]);

      s.upsert(anchor('a'));
      s.upsert(anchor('b'));
      s.remove('a');
      s.clear();

      expect(snapshots, [
        ['a'],
        ['a', 'b'],
        ['b'],
        <String>[],
      ]);
    });

    test('clear and remove of an empty set do not fire', () {
      final s = VenueAnchorService();
      var fired = 0;
      s.onChanged = (_) => fired++;

      s.clear();
      expect(s.remove('nope'), isFalse);
      expect(fired, 0);
    });
  });
}
