import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_range/features/beacon/background_beacon_channel.dart';

/// B2/B3: the COMMITTED Dart control paths for the diagnostic layer — arming the
/// Case-1 pending-dial fault and provisioning the fleet run secret. Verifies the
/// exact platform-channel calls the diagnostic app makes; native gates them
/// behind the diag compile flag, so these are safe no-ops in release.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('io.inrange/background_beacon');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  final bb = BackgroundBeaconChannel();

  test('armW5Fault(peer) invokes the native hook with the raw token', () async {
    await bb.armW5Fault(peerAlias: 'peer-token-xyz');
    expect(calls, hasLength(1));
    expect(calls.single.method, 'armW5Fault');
    expect(calls.single.arguments, 'peer-token-xyz');
  });

  test('armW5Fault() with no peer arms the wildcard (null argument)', () async {
    await bb.armW5Fault();
    expect(calls.single.method, 'armW5Fault');
    expect(calls.single.arguments, isNull);
  });

  test('disarmW5Fault invokes the native disarm control', () async {
    await bb.disarmW5Fault();
    expect(calls.single.method, 'disarmW5Fault');
  });

  test('resetW5Diag invokes the native session-reset control', () async {
    await bb.resetW5Diag();
    expect(calls.single.method, 'resetW5Diag');
  });

  test('setDiagRunSecret forwards a non-empty secret', () async {
    await bb.setDiagRunSecret('deadbeef' * 8); // 64 hex
    expect(calls.single.method, 'setDiagRunSecret');
    expect(calls.single.arguments, 'deadbeef' * 8);
  });

  test('setDiagRunSecret is a no-op for an empty secret (no channel call)',
      () async {
    await bb.setDiagRunSecret('');
    expect(calls, isEmpty);
  });
}
