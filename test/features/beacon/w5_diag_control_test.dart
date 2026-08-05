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

  test('armW5Fault() with no peer sends null (native fails it closed)',
      () async {
    await bb.armW5Fault();
    expect(calls.single.method, 'armW5Fault');
    expect(calls.single.arguments, isNull);
  });

  test('disarmW5Fault invokes the native disarm control', () async {
    await bb.disarmW5Fault();
    expect(calls.single.method, 'disarmW5Fault');
  });

  test('resetW5Case invokes the native case-reset control', () async {
    await bb.resetW5Case();
    expect(calls.single.method, 'resetW5Case');
  });

  test('destroyW5Secret invokes the native secret-destroy control', () async {
    await bb.destroyW5Secret();
    expect(calls.single.method, 'destroyW5Secret');
  });

  test('setDiagRunSecret forwards a non-empty secret', () async {
    await bb.setDiagRunSecret('deadbeef' * 8); // 64 hex
    expect(calls.single.method, 'setDiagRunSecret');
    expect(calls.single.arguments, 'deadbeef' * 8);
  });

  test('setDiagRunSecret is a no-op for an empty secret (no channel call)',
      () async {
    final ack = await bb.setDiagRunSecret('');
    expect(calls, isEmpty);
    expect(ack, isNull, reason: 'empty secret ⇒ null ack ⇒ NOT key-ready');
  });

  // A3 key-ready gate: a successful provision round-trips the native ack so the
  // caller can confirm `ok:true` before enabling W5 (startup-readiness).
  test('setDiagRunSecret returns the native provisioning ack (key-ready)',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return <String, dynamic>{'ok': true, 'rotated': false, 'keyEpoch': 3};
    });
    final ack = await bb.setDiagRunSecret('a1' * 32); // 64 hex
    expect(ack, isNotNull);
    expect(ack!['ok'], isTrue, reason: 'provisioned ⇒ key-ready');
    expect(ack['keyEpoch'], 3);
  });

  // A3: a REJECTED provision (bad hex) round-trips `ok:false` — NOT null — so the
  // gate holds W5 OFF (fail closed) rather than treating it as ready.
  test('setDiagRunSecret surfaces a rejected provision as ok:false', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return <String, dynamic>{'ok': false};
    });
    final ack = await bb.setDiagRunSecret('zz'); // invalid → native rejects
    expect(ack, isNotNull);
    expect(ack!['ok'], isFalse,
        reason: 'rejected ⇒ NOT key-ready ⇒ W5 stays OFF');
  });

  // A3: a channel/persistence FAILURE fails closed to a null ack (never a throw
  // that could leave provisioning ambiguous), so the gate holds W5 OFF.
  test('setDiagRunSecret fails closed to null on a channel error', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'boom');
    });
    final ack = await bb.setDiagRunSecret('a1' * 32);
    expect(ack, isNull, reason: 'persistence failure ⇒ null ⇒ NOT key-ready');
  });

  // A3: repeated provisioning is forwarded each time (a re-key on restart must
  // reach native, not be swallowed) and the last ack governs readiness.
  test('setDiagRunSecret forwards every (repeated) provision', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return <String, dynamic>{'ok': true, 'rotated': calls.length > 1};
    });
    await bb.setDiagRunSecret('a1' * 32);
    final second = await bb.setDiagRunSecret('b2' * 32);
    expect(calls, hasLength(2), reason: 'both provisions reach native');
    expect(second!['rotated'], isTrue, reason: 'a changed key reports rotation');
  });

  // R5: setW5Links is an ACKNOWLEDGED configuration transaction — it returns the
  // CONFIRMED persisted flag so the caller can verify the requested state took.
  test('setW5Links returns the native-confirmed flag', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.arguments as bool?; // native echoes the persisted flag
    });
    expect(await bb.setW5Links(true), isTrue);
    expect(await bb.setW5Links(false), isFalse);
  });

  test('setW5Links returns null on a channel error (never silent success)',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'boom');
    });
    expect(await bb.setW5Links(false), isNull,
        reason: 'a channel error is NOT-confirmed, not success');
  });

  test('setW5Links surfaces a native OFF that was NOT honored', () async {
    // Native keeps the flag true despite an OFF request (stale flag).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => true);
    expect(await bb.setW5Links(false), isTrue,
        reason: 'caller sees the un-honored OFF and can fail closed (R5)');
  });
}
