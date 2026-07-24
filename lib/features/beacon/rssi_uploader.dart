import 'dart:async';

/// Returns up to [limit] rows with `id > afterId`, oldest first. Each row is a
/// raw `rssi_log` record: id, at_ms, correlation_id, rssi, power.
typedef RssiPageFetcher = Future<List<Map<String, Object?>>> Function(
    int afterId, int limit);

/// Uploads one batch. Returns the number of rows the server actually INSERTED
/// (0 means every row was a replay). Throws on any failure — the caller retries.
typedef RssiBatchSender = Future<int> Function(
    String deviceId, List<Map<String, Object?>> samples);

/// Ships rows out of the local `rssi_log` to the server, so a calibration walk
/// can be extracted without the phone in hand — see
/// docs/CLOUD_RSSI_UPLOAD_SPEC.md.
///
/// Deliberately platform-free (only `dart:async`), like `ClaimManager`: the
/// interesting behavior here is watermark arithmetic and failure handling, and
/// that should be testable without SQLite, Supabase, or a BLE stack.
///
/// The local DB is the durable queue. There is no outbox table and no in-memory
/// pending list: `rssi_log.id` is monotonic, so a single "highest id the server
/// confirmed" watermark means everything above it is unsent, and that survives
/// process death for free.
///
/// Invariant, and the reason the cursor write sits where it does: **the
/// watermark only ever advances after the server has accepted the batch.** A
/// crash or a dead network re-sends; the server's (device_id, device_seq) key
/// makes the replay a no-op. Advancing first would lose the rows silently.
class RssiUploader {
  RssiUploader({
    required Future<String> Function() deviceId,
    required RssiPageFetcher fetchPage,
    required RssiBatchSender send,
    required Future<int> Function() readCursor,
    required Future<void> Function(int rowId) writeCursor,
    required bool Function() enabled,
    this.pageSize = 500,
    this.maxPagesPerFlush = 8,
  })  : _deviceId = deviceId,
        _fetchPage = fetchPage,
        _send = send,
        _readCursor = readCursor,
        _writeCursor = writeCursor,
        _enabled = enabled;

  final Future<String> Function() _deviceId;
  final RssiPageFetcher _fetchPage;
  final RssiBatchSender _send;
  final Future<int> Function() _readCursor;
  final Future<void> Function(int rowId) _writeCursor;
  final bool Function() _enabled;

  /// Must not exceed the server's batch cap (500), or every call is rejected.
  final int pageSize;

  /// Bounds one flush so a large backlog drains across several ticks instead of
  /// tripping the server's 20-calls-per-minute limit. With a 45 s timer that is
  /// ~1.3 flushes/min x 8 = ~11 calls/min, leaving headroom for the extra flush
  /// a foreground transition triggers.
  final int maxPagesPerFlush;

  bool _busy = false;

  /// Consecutive failed flushes. Stays >0 while the uploader is stuck, which is
  /// the only outward sign of a poison-pill batch (a row the server rejects
  /// permanently blocks the watermark forever, because skipping it would
  /// silently drop calibration data — losing rows is worse than stalling).
  int _consecutiveFailures = 0;
  int get consecutiveFailures => _consecutiveFailures;
  bool get isStuck => _consecutiveFailures > 0;

  /// Called after every flush attempt with (succeeded, rowsInserted).
  void Function(bool ok, int inserted)? onState;

  /// Drains up to [maxPagesPerFlush] pages. Rethrows the first send failure so
  /// a retry wrapper (ClaimManager) can schedule the backoff.
  ///
  /// Re-entrant calls are dropped, not queued: the periodic timer and the
  /// foreground transition can both fire here, and two concurrent drains would
  /// read the same watermark and upload the same page twice.
  Future<void> flush() async {
    if (_busy || !_enabled()) return;
    _busy = true;
    var inserted = 0;
    try {
      final device = await _deviceId();
      for (var page = 0; page < maxPagesPerFlush; page++) {
        final cursor = await _readCursor();
        final rows = await _fetchPage(cursor, pageSize);
        if (rows.isEmpty) break;
        // Computed, not `rows.last`: the watermark must not depend on the
        // fetcher happening to sort ascending. Getting this wrong strands
        // every row above a mis-ordered page.
        var maxId = cursor;
        for (final r in rows) {
          final id = r['id'];
          if (id is int && id > maxId) maxId = id;
        }
        if (maxId <= cursor) break; // no forward progress; refuse to spin
        inserted += await _send(device, rows);
        await _writeCursor(maxId);
        if (rows.length < pageSize) break;
      }
      _consecutiveFailures = 0;
      onState?.call(true, inserted);
    } catch (_) {
      _consecutiveFailures++;
      onState?.call(false, inserted);
      rethrow;
    } finally {
      _busy = false;
    }
  }
}
