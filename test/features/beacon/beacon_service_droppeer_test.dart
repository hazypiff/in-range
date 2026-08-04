import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_range/features/beacon/beacon_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// B1 (_doPass bridge): the REAL BeaconService.dropPeer that _doPass invokes
/// (`beacon.dropPeer` inside resolvePassTeardown). Proves it forwards the token
/// to the platform channel on iOS and parses the native dict, and is a no-op
/// off-iOS. Together with pass_teardown_test (the orchestration over the real
/// channel), the whole _doPass path is covered.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('io.inrange/background_beacon');
  final calls = <MethodCall>[];
  late BeaconService svc;

  setUp(() async {
    dotenv.testLoad(fileInput: '');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    svc = BeaconService(
      userIdSecret: '',
      userId: '',
      hmacSecret: '',
      sharedPreferences: prefs,
    );
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'dropPeer') {
        return {
          'lookupHit': true,
          'leaseEnded': true,
          'rolesClosed': ['outbound'],
          'rawSessionsReaped': 0,
        };
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('dropPeer on iOS forwards the token and parses the native dict',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final res = await svc.dropPeer('feedface00');
    expect(calls.single.method, 'dropPeer');
    expect(calls.single.arguments, 'feedface00');
    expect(res?['lookupHit'], true);
    expect(res?['rolesClosed'], ['outbound']);
  });

  test('dropPeer off-iOS is a no-op returning null (native unavailable)',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final res = await svc.dropPeer('feedface00');
    expect(calls, isEmpty);
    expect(res, isNull);
  });
}
