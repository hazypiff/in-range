import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_range/features/beacon/location_keepalive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('io.inrange.app/location_coordinator');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('native coordinator path', () {
    test('uses native coordinator when it reports ready', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'start':
            return true;
          case 'stop':
            return null;
        }
        return null;
      });

      final k = LocationKeepalive(
        platform: TargetPlatform.iOS,
        enabled: () => true,
      );
      await k.start();

      expect(k.isRunning, isTrue);
      await k.stop();
      expect(k.isRunning, isFalse);
    });

    test('drains buffered fixes on start and delivers them to onFix', () async {
      final fix = {
        'lat': 37.7749,
        'lon': -122.4194,
        'acc': 10.0,
        'ts': 1753478400000,
        'moving': false,
      };
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'start':
            return true;
          case 'stop':
            return null;
          case 'flush':
            return [fix];
        }
        return null;
      });

      LocationAssistFix? captured;
      final k = LocationKeepalive(
        platform: TargetPlatform.iOS,
        enabled: () => true,
      )..onFix = (f) => captured = f;

      await k.start();
      // _pullBufferedFixes is fire-and-forget; give it a turn.
      await Future<void>.delayed(Duration.zero);
      await k.stop();

      expect(captured, isNotNull);
      expect(captured!.lat, closeTo(37.7749, 0.0001));
      expect(captured!.lon, closeTo(-122.4194, 0.0001));
      expect(captured!.accuracyM, closeTo(10.0, 0.1));
      expect(captured!.isMoving, isFalse);
    });

    test('falls back to Dart stream when native coordinator is missing', () async {
      // No mock handler => MissingPluginException => Dart stream path.
      var opens = 0;
      final k = LocationKeepalive(
        platform: TargetPlatform.iOS,
        enabled: () => true,
        openStream: (settings) {
          opens++;
          return const Stream.empty();
        },
      );
      await k.start();

      expect(opens, 1);
      expect(k.isRunning, isTrue);
    });
  });
}
