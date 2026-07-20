import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_range/core/permissions/permission_service.dart';

/// Google Play requires a prominent in-app disclosure BEFORE the OS
/// background-location prompt. These tests pin the fail-closed contract:
/// no disclosure (or a declined one) must never reach `requestPermissions`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter.baseflow.com/permissions/methods');
  late List<String> calls;

  setUp(() {
    calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'checkPermissionStatus':
          return 0; // denied — so the code must decide whether to ask
        case 'requestPermissions':
          return <int, int>{for (final p in call.arguments as List) p as int: 1};
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('no disclosure callback: never requests background location', () async {
    final granted = await PermissionService.requestBackgroundLocation();

    expect(granted, isFalse);
    expect(
      calls,
      isNot(contains('requestPermissions')),
      reason: 'prompted for background location with no prominent disclosure',
    );
  });

  test('declined disclosure: never requests background location', () async {
    var shown = false;
    final granted = await PermissionService.requestBackgroundLocation(
      onDisclosure: () async {
        shown = true;
        return false; // user tapped "Not now"
      },
    );

    expect(shown, isTrue, reason: 'disclosure was not presented');
    expect(granted, isFalse);
    expect(
      calls,
      isNot(contains('requestPermissions')),
      reason: 'prompted after the user declined the disclosure',
    );
  });

  test('accepted disclosure: discloses first, then requests', () async {
    final order = <String>[];
    final granted = await PermissionService.requestBackgroundLocation(
      onDisclosure: () async {
        order.add('disclosure');
        return true;
      },
    );

    order.addAll(calls.where((c) => c == 'requestPermissions'));
    expect(granted, isTrue);
    expect(
      order,
      containsAllInOrder(<String>['disclosure', 'requestPermissions']),
      reason: 'the OS prompt must come after the disclosure, never before',
    );
  });
}
