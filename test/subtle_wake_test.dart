import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_range/features/beacon/location_keepalive.dart';
import 'package:in_range/features/beacon/subtle_wake_service.dart';
import 'package:in_range/features/beacon/venue_matcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('io.inrange.app/subtle_wake');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  // Small helper so tests read as coordinates, not constructor noise.
  LocationAssistFix makeFix(double lat, double lon) => LocationAssistFix(
        lat: lat,
        lon: lon,
        accuracyM: 20,
        at: DateTime(2026, 7, 25, 12),
      );

  group('flag (dotenv-direct, default off)', () {
    test('is off when the key is absent', () {
      dotenv.testLoad(fileInput: '');
      final s = SubtleWakeService(platform: TargetPlatform.iOS);
      expect(s.isSupported, isFalse);
    });

    test('reads INRANGE_SUBTLE_WAKE straight from dotenv', () {
      dotenv.testLoad(fileInput: 'INRANGE_SUBTLE_WAKE=true');
      expect(SubtleWakeService(platform: TargetPlatform.iOS).isSupported,
          isTrue);

      dotenv.testLoad(fileInput: 'INRANGE_SUBTLE_WAKE=1');
      expect(SubtleWakeService(platform: TargetPlatform.iOS).isSupported,
          isTrue);

      dotenv.testLoad(fileInput: 'INRANGE_SUBTLE_WAKE=false');
      expect(SubtleWakeService(platform: TargetPlatform.iOS).isSupported,
          isFalse);
    });

    test('stays off on Android even with the flag set', () {
      dotenv.testLoad(fileInput: 'INRANGE_SUBTLE_WAKE=true');
      expect(SubtleWakeService(platform: TargetPlatform.android).isSupported,
          isFalse,
          reason: 'Android already scans acceptably in the background');
      dotenv.testLoad(fileInput: '');
    });
  });

  group('lifecycle', () {
    test('start/stop drive the native coordinator', () async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return call.method == 'start' ? true : null;
      });

      final s = SubtleWakeService(
        platform: TargetPlatform.iOS,
        enabled: () => true,
      );
      await s.start();
      expect(s.isRunning, isTrue);
      await s.stop();
      expect(s.isRunning, isFalse);
      // drainBufferedWakes rides every successful start: wakes that fired
      // while the engine was dead are pulled (and acked) via the same channel.
      expect(calls, ['start', 'drainBufferedWakes', 'stop']);
    });

    test('start is a no-op while the flag is off', () async {
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls++;
        return true;
      });

      final s = SubtleWakeService(
        platform: TargetPlatform.iOS,
        enabled: () => false,
      );
      await s.start();
      expect(calls, 0);
      expect(s.isRunning, isFalse);
    });

    test('syncAnchors sends an updateRegions snapshot', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });

      final s = SubtleWakeService(
        platform: TargetPlatform.iOS,
        enabled: () => true,
      );
      await s.syncAnchors(const [
        {'id': 'v1', 'lat': 40.7, 'lon': -74.0, 'radius': 300.0},
      ]);

      expect(calls.single.method, 'updateRegions');
      final regions =
          (calls.single.arguments as Map)['regions'] as List<dynamic>;
      expect(regions.single, {'id': 'v1', 'lat': 40.7, 'lon': -74.0, 'radius': 300.0});
    });

    // The coordinator ships in a later build than the Dart side; an older
    // binary must degrade to tiers 0-1 without an error escaping.
    test('a missing native module degrades quietly', () async {
      final s = SubtleWakeService(
        platform: TargetPlatform.iOS,
        enabled: () => true,
      );
      await expectLater(s.start(), completes);
      expect(s.isRunning, isFalse);
      await expectLater(s.syncAnchors(const []), completes);
      await expectLater(s.stop(), completes);
    });
  });

  group('wakes', () {
    late int bursts;
    late LocationAssistFix? fedFix;
    late int refreshes;
    late List<(String, String?)> uploads;
    late DateTime now;

    SubtleWakeService build({
      bool Function() enabled = _yes,
      Future<String?> Function()? currentBssid,
      LocationAssistFix? Function()? cachedFix,
      bool failUploads = false,
    }) {
      final s = SubtleWakeService(
        platform: TargetPlatform.iOS,
        enabled: enabled,
        clock: () => now,
        currentBssid: currentBssid ?? () async => 'AA:BB:CC:DD:EE:FF',
        upload: (geohash, bssid) async {
          if (failUploads) throw StateError('dead network');
          uploads.add((geohash, bssid));
        },
      );
      s.onBurst = () async => bursts++;
      s.onFix = (f) => fedFix = f;
      s.onRefreshLocation = () => refreshes++;
      s.cachedFix = cachedFix;
      s.hashSalt = () => 'test-salt';
      return s;
    }

    setUp(() {
      bursts = 0;
      fedFix = null;
      refreshes = 0;
      uploads = [];
      now = DateTime(2026, 7, 25, 12);
    });

    test('an SLC wake feeds its fix, bursts, and uploads the venue hint',
        () async {
      final s = build();
      await s.handleWake(SubtleWake(
        source: SubtleWakeSource.slc,
        fix: makeFix(42.6, -5.6),
      ));

      expect(fedFix?.lat, closeTo(42.6, 0.0001));
      expect(refreshes, 0,
          reason: 'a wake that carries its fix must not spend a GPS fix');
      expect(bursts, 1);
      expect(uploads.single.$1, 'ezs42');
      expect(
        uploads.single.$2,
        SubtleWakeService.hashBssid('AA:BB:CC:DD:EE:FF', 'test-salt'),
      );
    });

    test('a push wake without a fix nudges the cache and uses it', () async {
      final s = build(cachedFix: () => makeFix(42.6, -5.6));
      await s.handleWake(const SubtleWake(
        source: SubtleWakeSource.push,
        nonce: 'n-1',
      ));

      expect(refreshes, 1);
      expect(fedFix, isNull);
      expect(bursts, 1);
      expect(uploads.single.$1, 'ezs42');
    });

    test('no fix anywhere means no hint row', () async {
      final s = build(cachedFix: () => null);
      await s.handleWake(const SubtleWake(source: SubtleWakeSource.push));

      expect(bursts, 1, reason: 'the burst is what a wake is FOR');
      expect(uploads, isEmpty);
    });

    test('no WiFi association still uploads, with a null BSSID', () async {
      final s = build(currentBssid: () async => null);
      await s.handleWake(SubtleWake(
        source: SubtleWakeSource.slc,
        fix: makeFix(42.6, -5.6),
      ));

      expect(uploads.single, ('ezs42', null));
    });

    test('a wake while the flag is off does nothing', () async {
      var flag = true;
      final s = build(enabled: () => flag);
      await s.handleWake(const SubtleWake(source: SubtleWakeSource.push));
      expect(bursts, 1);

      flag = false;
      await s.handleWake(const SubtleWake(source: SubtleWakeSource.push));
      expect(bursts, 1, reason: 'checked per wake, not cached at start');
      expect(uploads, isEmpty);
    });

    test('one hint per cell per interval; a new cell reports again', () async {
      final s = build();
      final wake = SubtleWake(
        source: SubtleWakeSource.slc,
        fix: makeFix(42.6, -5.6),
      );

      await s.handleWake(wake);
      now = now.add(const Duration(minutes: 5));
      await s.handleWake(wake);
      expect(uploads.length, 1,
          reason: 'same cell inside the interval is a duplicate row');

      now = now.add(const Duration(minutes: 6));
      await s.handleWake(wake);
      expect(uploads.length, 2, reason: 'interval elapsed');

      await s.handleWake(SubtleWake(
        source: SubtleWakeSource.slc,
        fix: makeFix(48.85, 2.35), // Paris: a different precision-5 cell
      ));
      expect(uploads.length, 3, reason: 'a cell change is real movement');
    });

    test('a failed upload leaves the next wake free to retry', () async {
      final s = build(failUploads: true);
      final wake = SubtleWake(
        source: SubtleWakeSource.slc,
        fix: makeFix(42.6, -5.6),
      );
      await s.handleWake(wake);
      await s.handleWake(wake); // must not throw, must not be throttled
      expect(bursts, 2);
      expect(uploads, isEmpty);
    });
  });

  group('channel parsing', () {
    Future<void> sendWake(Object? arguments) => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'io.inrange.app/subtle_wake',
          const StandardMethodCodec()
              .encodeMethodCall(MethodCall('onWake', arguments)),
          (_) {},
        );

    test('a native onWake message becomes a full wake', () async {
      var bursts = 0;
      LocationAssistFix? fed;
      final s = SubtleWakeService(
        platform: TargetPlatform.iOS,
        enabled: () => true,
        upload: (_, __) async {},
      );
      s.onBurst = () async => bursts++;
      s.onFix = (f) => fed = f;

      await sendWake({
        'kind': 'regionEnter',
        'id': 'venue-1',
        'lat': 42.6,
        'lon': -5.6,
        'acc': 30.0,
        'ts': 1753478400000,
      });
      // The handler dispatches handleWake unawaited; let it run.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(bursts, 1);
      expect(fed?.accuracyM, 30.0);
      expect(fed?.at, DateTime.fromMillisecondsSinceEpoch(1753478400000));
    });

    test('an unknown source is ignored, not acted on', () async {
      var bursts = 0;
      final s = SubtleWakeService(
        platform: TargetPlatform.iOS,
        enabled: () => true,
        upload: (_, __) async {},
      );
      s.onBurst = () async => bursts++;

      await sendWake({
        'source': 'teleport', // wrong KEY, not just an unknown value
        'kind': 'teleport',
        'lat': 42.6,
        'lon': -5.6,
      });
      await sendWake([1, 2, 3]); // malformed arguments
      await sendWake({'lat': 1}); // no kind at all
      await Future<void>.delayed(Duration.zero);

      expect(bursts, 0);
    });

    // Pins the Dart parser to SubtleWakeCoordinator.swift's vocabulary: both
    // region directions are the same wake tier, and the region's CLRegion
    // identifier arrives as 'id'.
    test('regionEnter/regionExit both wake, carrying the anchor id', () async {
      var bursts = 0;
      final s = SubtleWakeService(
        platform: TargetPlatform.iOS,
        enabled: () => true,
        upload: (_, __) async {},
      );
      s.onBurst = () async => bursts++;

      await sendWake({'kind': 'regionEnter', 'id': 'venue-1'});
      await sendWake({'kind': 'regionExit', 'id': 'venue-1'});
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(bursts, 2);
    });
  });

  group('geohash + bssid primitives', () {
    test('encodes known vectors at city-level precision', () {
      expect(SubtleWakeService.geohashEncode(42.6, -5.6), 'ezs42');
      expect(SubtleWakeService.geohashEncode(37.7749, -122.4194), '9q8yy');
    });

    // The whole privacy model rests on hints being comparable to the venue
    // matcher's fingerprints — pin the two implementations to one form.
    test('hashBssid matches Fingerprint.hashed', () {
      final fp = Fingerprint(
        [ApSighting(bssid: 'aa:bb:cc:dd:ee:ff', rssi: -50, freq: 2412)],
        takenAt: DateTime(2026, 7, 25),
      );
      expect(
        SubtleWakeService.hashBssid('AA:BB:CC:DD:EE:FF', 'test-salt'),
        fp.hashed('test-salt').keys.single,
      );
    });
  });
}

bool _yes() => true;
