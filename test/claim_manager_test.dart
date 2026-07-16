import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_range/features/beacon/claim_manager.dart';

void main() {
  group('ClaimManager — claim retry (#11)', () {
    test('success on first try: reports synced=true, no retry scheduled', () {
      fakeAsync((async) {
        final states = <bool>[];
        final mgr = ClaimManager(upload: () async {})..onState = states.add;
        final gen = mgr.newSession();
        mgr.attempt(gen);
        async.flushMicrotasks();
        expect(states, [true]);
        expect(mgr.hasPendingRetry, isFalse);
      });
    });

    test('transient failure retries with exponential backoff, then succeeds',
        () {
      fakeAsync((async) {
        var calls = 0;
        final states = <bool>[];
        // Fail the first two attempts, succeed on the third.
        final mgr = ClaimManager(upload: () async {
          calls++;
          if (calls < 3) throw Exception('network');
        })
          ..onState = states.add;

        final gen = mgr.newSession();
        mgr.attempt(gen);
        async.flushMicrotasks();
        expect(states, [false]); // 1st failed
        expect(mgr.hasPendingRetry, isTrue);

        async.elapse(const Duration(seconds: 2)); // backoff 2s -> 2nd attempt
        expect(states, [false, false]);

        async.elapse(const Duration(seconds: 4)); // backoff 4s -> 3rd, succeeds
        expect(states, [false, false, true]);
        expect(calls, 3);
        expect(mgr.hasPendingRetry, isFalse);
      });
    });

    test('stops after maxRetries failures', () {
      fakeAsync((async) {
        var calls = 0;
        final mgr = ClaimManager(upload: () async {
          calls++;
          throw Exception('always down');
        });
        final gen = mgr.newSession();
        mgr.attempt(gen);
        async.flushMicrotasks();
        // Drain every backoff (2,4,8,16,32 s and beyond).
        async.elapse(const Duration(minutes: 5));
        // 1 initial + maxRetries retries.
        expect(calls, 1 + ClaimManager.maxRetries);
        expect(mgr.hasPendingRetry, isFalse);
      });
    });

    test('rotation supersedes a pending retry (no stale attempt fires)', () {
      fakeAsync((async) {
        var calls = 0;
        final mgr = ClaimManager(upload: () async {
          calls++;
          throw Exception('down');
        });
        final gen1 = mgr.newSession();
        mgr.attempt(gen1);
        async.flushMicrotasks();
        expect(calls, 1);
        expect(mgr.hasPendingRetry, isTrue);

        // Rotation: new token supersedes the old retry before it fires.
        mgr.newSession();
        expect(mgr.hasPendingRetry, isFalse);
        async.elapse(const Duration(seconds: 10));
        expect(calls, 1); // the old retry never ran
      });
    });

    test('rotation flips cloudSynced true->false (initial ok, rotation fails)',
        () {
      // This is the cloudSynced source the controller republishes: an initial
      // success then a rotation whose claim fails must report false, not keep
      // the stale true (reviewer #11).
      fakeAsync((async) {
        var fail = false;
        final states = <bool>[];
        final mgr = ClaimManager(upload: () async {
          if (fail) throw Exception('rotation network fail');
        })
          ..onState = states.add;

        final g1 = mgr.newSession();
        mgr.attempt(g1);
        async.flushMicrotasks();
        expect(states.last, isTrue); // initial claim synced

        fail = true;
        final g2 = mgr.newSession(); // rotation
        mgr.attempt(g2);
        async.flushMicrotasks();
        expect(states.last, isFalse); // rotation failure reported
      });
    });

    test('teardown cancels a pending retry', () {
      fakeAsync((async) {
        var calls = 0;
        final states = <bool>[];
        final mgr = ClaimManager(upload: () async {
          calls++;
          throw Exception('down');
        })
          ..onState = states.add;
        final gen = mgr.newSession();
        mgr.attempt(gen);
        async.flushMicrotasks();
        expect(mgr.hasPendingRetry, isTrue);

        mgr.cancel(); // teardown
        expect(mgr.hasPendingRetry, isFalse);
        async.elapse(const Duration(minutes: 1));
        expect(calls, 1); // no further attempts after teardown
      });
    });

    test('an in-flight attempt that resolves after teardown does not report',
        () {
      fakeAsync((async) {
        final completer = Completer<void>();
        final states = <bool>[];
        final mgr = ClaimManager(upload: () => completer.future)
          ..onState = states.add;
        final gen = mgr.newSession();
        mgr.attempt(gen); // suspends on the upload future
        async.flushMicrotasks();

        mgr.cancel(); // teardown while the upload is in flight
        completer.complete(); // upload now "succeeds"
        async.flushMicrotasks();

        // Superseded by the generation bump — must not report success.
        expect(states, isEmpty);
      });
    });
  });
}
