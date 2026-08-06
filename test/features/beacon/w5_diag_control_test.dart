import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_range/features/beacon/background_beacon_channel.dart';
import 'package:in_range/features/beacon/beacon_service.dart';

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

  // C2/A3: setW5Links is an ACKNOWLEDGED effective-state transaction — it returns
  // the native structured ack {flag, effectiveEnabled, quiescent}, not a Boolean
  // echo, so the caller can prove W5 was actually torn down (not just flagged).
  test('setW5Links returns the structured effective-state ack', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return <String, dynamic>{
        'flag': call.arguments as bool,
        'effectiveEnabled': call.arguments as bool,
        'quiescent': !(call.arguments as bool),
      };
    });
    final onAck = await bb.setW5Links(true);
    expect(onAck?['effectiveEnabled'], isTrue);
    final offAck = await bb.setW5Links(false);
    expect(offAck?['effectiveEnabled'], isFalse);
    expect(offAck?['quiescent'], isTrue);
  });

  test('setW5Links returns null on a channel error (never silent success)',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'boom');
    });
    expect(await bb.setW5Links(false), isNull,
        reason: 'a channel error is NOT an effective-off ack, not success');
  });

  // C2/A3: the CALLER decision. Before the fix a stored `false` flag (or a
  // Boolean echo) was accepted as proof W5 stopped; the panel HOLD showed a
  // restored old-key session/lease/timer can survive a flag flip. The gate now
  // demands an atomic effective-OFF ack: effectiveEnabled==false AND quiescent.
  group('w5AckIsEffectiveOff + w5StartGateAllows (C2/A3 fail-closed gate)', () {
    Map<String, dynamic> ack(bool eff, bool q) =>
        {'flag': eff, 'effectiveEnabled': eff, 'quiescent': q};
    test('null ack (dead channel) is NOT effective-off', () {
      expect(BeaconService.w5AckIsEffectiveOff(null), isFalse);
    });
    test('effectiveEnabled true is NOT effective-off', () {
      expect(BeaconService.w5AckIsEffectiveOff(ack(true, true)), isFalse);
    });
    test('effectiveEnabled false but NOT quiescent is NOT effective-off', () {
      expect(BeaconService.w5AckIsEffectiveOff(ack(false, false)), isFalse,
          reason: 'restored/live W5 state still present → not torn down');
    });
    test('effectiveEnabled false AND quiescent IS effective-off', () {
      expect(BeaconService.w5AckIsEffectiveOff(ack(false, true)), isTrue);
    });
    test('requested OFF + not effective-off ⇒ BLOCK', () {
      expect(BeaconService.w5StartGateAllows(want: false, effOff: false),
          isFalse);
    });
    test('requested OFF + proven effective-off ⇒ ALLOW', () {
      expect(
          BeaconService.w5StartGateAllows(want: false, effOff: true), isTrue);
    });
    test('requested ON ⇒ ALLOW regardless (W5 fails closed natively)', () {
      expect(BeaconService.w5StartGateAllows(want: true, effOff: true), isTrue);
      expect(BeaconService.w5StartGateAllows(want: true, effOff: false), isTrue);
    });
  });
}
