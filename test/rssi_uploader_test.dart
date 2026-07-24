import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_range/features/beacon/rssi_uploader.dart';

/// In-memory stand-in for the rssi_log table + meta watermark. Rowids are
/// monotonic and never reused, matching SQLite AUTOINCREMENT (verified: a
/// `DELETE FROM rssi_log` leaves sqlite_sequence intact, so the next rowid
/// after a wipe is N+1, not 1).
class _FakeStore {
  final List<Map<String, Object?>> rows = [];
  int cursor = 0;
  int _nextId = 1;

  void add(int count, {String power = 'H'}) {
    for (var i = 0; i < count; i++) {
      rows.add({
        'id': _nextId,
        'at_ms': 1784900000000 + _nextId,
        'correlation_id': 'c0ffee01',
        'rssi': -60,
        'power': power,
      });
      _nextId++;
    }
  }

  Future<List<Map<String, Object?>>> fetch(int afterId, int limit) async =>
      rows.where((r) => (r['id']! as int) > afterId).take(limit).toList();

  Future<int> read() async => cursor;
  Future<void> write(int id) async => cursor = id;
}

void main() {
  late _FakeStore store;
  late List<List<Map<String, Object?>>> sent;
  late bool enabled;

  setUp(() {
    store = _FakeStore();
    sent = [];
    enabled = true;
  });

  RssiUploader build({
    Future<int> Function(String, List<Map<String, Object?>>)? send,
    int pageSize = 500,
    int maxPages = 8,
  }) =>
      RssiUploader(
        deviceId: () async => 'device-under-test',
        fetchPage: store.fetch,
        send: send ??
            (device, rows) async {
              sent.add(rows);
              return rows.length;
            },
        readCursor: store.read,
        writeCursor: store.write,
        enabled: () => enabled,
        pageSize: pageSize,
        maxPagesPerFlush: maxPages,
      );

  test('uploads pending rows and advances the watermark', () async {
    store.add(3);
    final u = build();
    await u.flush();

    expect(sent.length, 1);
    expect(sent.first.length, 3);
    expect(store.cursor, 3);
    expect(u.isStuck, isFalse);
  });

  test('a second flush with nothing new sends nothing', () async {
    store.add(3);
    final u = build();
    await u.flush();
    await u.flush();

    expect(sent.length, 1, reason: 'already-shipped rows were re-sent');
  });

  test('only rows above the watermark are sent', () async {
    store.add(3);
    final u = build();
    await u.flush();
    store.add(2);
    await u.flush();

    expect(sent.length, 2);
    expect(sent[1].map((r) => r['id']), [4, 5]);
    expect(store.cursor, 5);
  });

  // The core durability property: a failed send must leave the watermark alone,
  // or the rows are gone. This is the one bug in this file that would be
  // invisible in the field — the walk simply comes back short.
  test('a failed send does NOT advance the watermark', () async {
    store.add(3);
    final u = build(send: (d, rows) async => throw StateError('network down'));

    await expectLater(u.flush(), throwsA(isA<StateError>()));
    expect(store.cursor, 0);
    expect(u.isStuck, isTrue);
    expect(u.consecutiveFailures, 1);
  });

  test('rows survive a failure and ship on the next flush', () async {
    store.add(3);
    var fail = true;
    final u = build(send: (d, rows) async {
      if (fail) throw StateError('network down');
      sent.add(rows);
      return rows.length;
    });

    await expectLater(u.flush(), throwsA(isA<StateError>()));
    fail = false;
    await u.flush();

    expect(sent.single.map((r) => r['id']), [1, 2, 3]);
    expect(store.cursor, 3);
    expect(u.isStuck, isFalse, reason: 'success must clear the stuck flag');
  });

  test('pages a backlog and stops at maxPagesPerFlush', () async {
    store.add(25);
    final u = build(pageSize: 5, maxPages: 3);
    await u.flush();

    expect(sent.length, 3, reason: 'page cap not honoured');
    expect(store.cursor, 15);

    await u.flush();
    expect(store.cursor, 25, reason: 'backlog did not resume on the next tick');
  });

  test('a short page ends the flush without an extra empty call', () async {
    store.add(7);
    final u = build(pageSize: 5, maxPages: 8);
    await u.flush();

    expect(sent.length, 2);
    expect(sent[1].length, 2);
    expect(store.cursor, 7);
  });

  test('does nothing while disabled', () async {
    store.add(3);
    enabled = false;
    final u = build();
    await u.flush();

    expect(sent, isEmpty);
    expect(store.cursor, 0);
  });

  // The periodic timer and the foreground transition can both call flush(). Two
  // concurrent drains would read the same watermark and ship the same page
  // twice; the server would dedupe it, but the client would double-count.
  test('re-entrant flush is dropped, not queued', () async {
    store.add(3);
    final gate = Completer<void>();
    final u = build(send: (d, rows) async {
      sent.add(rows);
      await gate.future;
      return rows.length;
    });

    final first = u.flush();
    await Future<void>.delayed(Duration.zero);
    await u.flush(); // must return immediately, sending nothing
    gate.complete();
    await first;

    expect(sent.length, 1);
  });

  // Guards the comment in flush(): the watermark is computed from the rows, so
  // a fetcher that returns out of order cannot strand everything above it.
  test('watermark is the max id, not the last row', () async {
    store.add(3);
    final u = RssiUploader(
      deviceId: () async => 'device-under-test',
      fetchPage: (after, limit) async {
        final rows = await store.fetch(after, limit);
        return rows.reversed.toList(); // descending
      },
      send: (d, rows) async {
        sent.add(rows);
        return rows.length;
      },
      readCursor: store.read,
      writeCursor: store.write,
      enabled: () => enabled,
    );
    await u.flush();

    expect(store.cursor, 3, reason: 'watermark trusted row order');
  });

  test('a page that cannot advance the cursor stops instead of spinning',
      () async {
    store.add(2);
    var calls = 0;
    final u = RssiUploader(
      deviceId: () async => 'device-under-test',
      // Pathological: always returns the same already-shipped rows.
      fetchPage: (after, limit) async {
        calls++;
        return [
          {'id': 0, 'at_ms': 1, 'correlation_id': 'x', 'rssi': -60, 'power': 'H'}
        ];
      },
      send: (d, rows) async {
        sent.add(rows);
        return rows.length;
      },
      readCursor: store.read,
      writeCursor: store.write,
      enabled: () => enabled,
      maxPagesPerFlush: 8,
    );
    await u.flush();

    expect(calls, 1);
    expect(sent, isEmpty);
  });

  test('reports inserted count, and 0 for a full replay', () async {
    store.add(3);
    var replay = false;
    final results = <(bool, int)>[];
    final u = build(send: (d, rows) async => replay ? 0 : rows.length);
    u.onState = (ok, inserted) => results.add((ok, inserted));

    await u.flush();
    store.cursor = 0; // simulate a retry of an already-accepted batch
    replay = true;
    await u.flush();

    expect(results[0], (true, 3));
    expect(results[1], (true, 0), reason: 'replay should report 0 inserted');
  });
}
