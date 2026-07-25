import 'dart:io';
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

  // Regression guard for a bug that no behavioural test in this file could
  // catch. The native path was previously gated on
  // BindingBase.debugBindingType() != null. That reads as "skip in unit tests",
  // but its backing field is assigned inside an assert block
  // (flutter/foundation/binding.dart:293), and asserts are stripped in release
  // AND profile builds. So it returned null on every real device, silently
  // disabling the entire native coordinator — while this suite, which runs with
  // asserts enabled, reported it working.
  //
  // A behavioural test cannot distinguish the two: `flutter test` always has
  // asserts on. Pinning the source is the only thing that catches a recurrence.
  test('never gates device behaviour on an assert-stripped debug API', () {
    final src = File('lib/features/beacon/location_keepalive.dart')
        .readAsStringSync();
    final code = src
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    expect(code.contains('debugBindingType'), isFalse,
        reason: 'debugBindingType() is null in release/profile — gating the '
            'native coordinator on it disables it on real devices');
    expect(code.contains('kDebugMode'), isFalse,
        reason: 'same class of bug: build-mode checks must not decide whether '
            'a production code path runs');
  });
}
