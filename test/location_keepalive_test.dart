import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:in_range/features/beacon/location_keepalive.dart';

void main() {
  late int opens;
  late List<StreamController<Position>> controllers;
  late LocationSettings? captured;

  setUp(() {
    opens = 0;
    controllers = [];
    captured = null;
  });

  LocationKeepalive build({
    TargetPlatform platform = TargetPlatform.iOS,
    bool enabled = true,
  }) =>
      LocationKeepalive(
        platform: platform,
        enabled: () => enabled,
        openStream: (settings) {
          opens++;
          captured = settings;
          final c = StreamController<Position>();
          controllers.add(c);
          return c.stream;
        },
      );

  group('residency settings', () {
    // The load-bearing flag. iOS pauses a location session once it decides the
    // device is stationary, and a paused session stops holding the process up
    // — surrendering residency at exactly the moment it matters, since sitting
    // still in one place IS the encounter this app exists to detect.
    test('never lets iOS auto-pause the session', () {
      final s = LocationKeepalive.settingsForResidency() as AppleSettings;
      expect(s.pauseLocationUpdatesAutomatically, isFalse);
    });

    test('runs in the background and shows the indicator', () {
      final s = LocationKeepalive.settingsForResidency() as AppleSettings;
      expect(s.allowBackgroundLocationUpdates, isTrue);
      expect(s.showBackgroundLocationIndicator, isTrue,
          reason: 'required for background updates under when-in-use, '
              'and the honest signal to the user');
    });

    // We keep the session, not the coordinates: asking for precision would
    // spend battery and collect sensitive data the feature has no use for.
    test('asks for the coarsest accuracy and a wide distance filter', () {
      final s = LocationKeepalive.settingsForResidency() as AppleSettings;
      expect(s.accuracy, LocationAccuracy.lowest);
      expect(s.distanceFilter, greaterThanOrEqualTo(100));
    });
  });

  group('lifecycle', () {
    test('starts a session on iOS', () async {
      final k = build();
      await k.start();

      expect(opens, 1);
      expect(k.isRunning, isTrue);
      expect(captured, isA<AppleSettings>());
    });

    test('is a no-op on Android', () async {
      final k = build(platform: TargetPlatform.android);
      await k.start();

      expect(opens, 0, reason: 'Android already scans in the background; a '
          'second session would cost battery for no gain');
      expect(k.isRunning, isFalse);
    });

    // Default-off is the contract, not a preference: enabling this couples
    // location to the beacon toggle, which contradicts a recorded owner
    // decision, and its BLE benefit is still unmeasured.
    test('opens nothing while the flag is off', () async {
      final k = build(enabled: false);
      await k.start();

      expect(opens, 0);
      expect(k.isRunning, isFalse);
    });

    test('double start does not open a second session', () async {
      final k = build();
      await k.start();
      await k.start();

      expect(opens, 1);
    });

    // If this leaks, the app keeps itself alive and keeps the location
    // indicator lit after the user turned discoverability off.
    test('stop cancels the session', () async {
      final k = build();
      await k.start();
      await k.stop();

      expect(k.isRunning, isFalse);
      expect(controllers.single.hasListener, isFalse);
    });

    // start() is called from BeaconService's turn-on path and is documented to
    // never throw. Reading the flag touches dotenv, which throws when it has
    // not been loaded — so the config read must sit inside the guard too.
    test('a config read that throws does not escape start', () async {
      final k = LocationKeepalive(
        platform: TargetPlatform.iOS,
        enabled: () => throw StateError('dotenv not initialized'),
        openStream: (_) => const Stream<Position>.empty(),
      );

      await expectLater(k.start(), completes);
      expect(k.isRunning, isFalse);
    });

    test('stop before start is harmless', () async {
      final k = build();
      await k.stop();

      expect(k.isRunning, isFalse);
    });

    test('can restart after a stop', () async {
      final k = build();
      await k.start();
      await k.stop();
      await k.start();

      expect(opens, 2);
      expect(k.isRunning, isTrue);
    });

    // A revoked grant or a plugin error must degrade to foreground-only
    // detection, never take the beacon down with it.
    test('a stream error clears the session instead of throwing', () async {
      final k = build();
      await k.start();
      controllers.single.addError(StateError('permission revoked'));
      await Future<void>.delayed(Duration.zero);

      expect(k.isRunning, isFalse);
    });

    test('a throwing plugin does not propagate', () async {
      final k = LocationKeepalive(
        platform: TargetPlatform.iOS,
        enabled: () => true,
        openStream: (_) => throw StateError('plugin missing'),
      );

      await expectLater(k.start(), completes);
      expect(k.isRunning, isFalse);
    });
  });
}
