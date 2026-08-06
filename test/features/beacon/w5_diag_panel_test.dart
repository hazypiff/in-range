// E-B2 widget proof: the installed diag selected-peer control lists eligible
// peers as handles, arms the SELECTED peer's handle over the native channel,
// surfaces the structured ack, and fails closed on no selection / a rejected
// (ineligible) peer.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_range/features/beacon/w5_diag_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('io.inrange/background_beacon');
  late List<MethodCall> calls;
  const hA = 'id:aaaaaaaaaaaaaa';
  const hB = 'id:bbbbbbbbbbbbbb';

  void install({required bool Function(String handle) eligible}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'listW5Peers':
          return [
            {'handle': hA},
            {'handle': hB},
          ];
        case 'w5DiagStatus':
          return {'armed': false, 'eligibleCount': 2};
        case 'armW5FaultForPeer':
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final h = args['handle'] as String;
          if (!eligible(h)) {
            return {'ok': false, 'rejected': 'peer-not-eligible'};
          }
          return {'ok': true, 'peer': h, 'delaySeconds': args['delaySeconds']};
        default:
          return null;
      }
    });
  }

  setUp(() => calls = <MethodCall>[]);
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> pumpPanel(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: W5DiagPanel()))),
    );
    await tester.pumpAndSettle();
  }

  MethodCall? armCall() {
    for (final c in calls) {
      if (c.method == 'armW5FaultForPeer') return c;
    }
    return null;
  }

  testWidgets('lists handles and arms the selected peer by handle', (tester) async {
    install(eligible: (_) => true);
    await pumpPanel(tester);

    expect(find.text('W5 diagnostics — eligible peers: 2'), findsOneWidget);
    expect(find.byKey(const Key('w5peer_$hA')), findsOneWidget);
    expect(find.byKey(const Key('w5peer_$hB')), findsOneWidget);

    // Arm with NO selection → UI fails closed, no channel arm call.
    await tester.tap(find.byKey(const Key('w5DiagArm')));
    await tester.pump();
    expect(armCall(), isNull, reason: 'no arm call without a selection');
    expect(find.text('status: no-peer-selected'), findsOneWidget);

    // Select peer A, then arm → the selected handle crosses.
    await tester.tap(find.byKey(const Key('w5peer_$hA')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('w5DiagArm')));
    await tester.pump();

    final arm = armCall();
    expect(arm, isNotNull);
    expect((arm!.arguments as Map)['handle'], hA,
        reason: 'the SELECTED peer handle is armed');
    expect(find.byKey(const Key('w5DiagArmed')),
        findsOneWidget); // armed line present
    expect(find.textContaining('armed $hA'), findsOneWidget);
  });

  testWidgets('an ineligible peer is surfaced as rejected (fail closed)',
      (tester) async {
    install(eligible: (h) => false); // native rejects everything
    await pumpPanel(tester);
    await tester.tap(find.byKey(const Key('w5peer_$hA')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('w5DiagArm')));
    await tester.pump();
    expect(find.text('status: rejected:peer-not-eligible'), findsOneWidget);
    expect(find.text('armed: false'), findsOneWidget);
  });
}
