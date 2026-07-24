import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Local SQLite for BLE sightings + device aliases (survives restarts).
class LocalDb {
  LocalDb._(this.db);
  final Database db;

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE sightings (
        correlation_id TEXT PRIMARY KEY NOT NULL,
        first_seen_ms INTEGER NOT NULL,
        last_seen_ms INTEGER NOT NULL,
        best_rssi INTEGER NOT NULL,
        range_type TEXT NOT NULL,
        best_band TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute('''
      CREATE TABLE aliases (
        correlation_id TEXT PRIMARY KEY NOT NULL,
        alias TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_sightings_last ON sightings(last_seen_ms DESC)',
    );
    await _createRssiLog(db);
    await _createMeta(db);
  }

  /// Small key/value side table. Holds the upload identity ([deviceId]) and the
  /// upload watermark ([uploadCursor]) — both deliberately in THIS file rather
  /// than SharedPreferences, so they share a lifetime with the rssi_log rowid
  /// sequence they describe. If the DB file is ever recreated the sequence
  /// restarts at 1; keeping the device id here means it is recreated too, and
  /// the server's (device_id, device_seq) key cannot collide with rows from the
  /// previous DB. In prefs it would survive the reset and silently shadow them.
  static Future<void> _createMeta(Database db) async {
    await db.execute('''
      CREATE TABLE meta (
        key TEXT PRIMARY KEY NOT NULL,
        value TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _createRssiLog(Database db) async {
    // Raw per-advert RSSI stream. The estimator's medians live in memory
    // only; without this table a calibration walk persists nothing but
    // best_rssi (a max — multipath spikes at 60 ft matched 10 ft readings
    // in the 2026-07 beacon test), which cannot yield distance thresholds.
    await db.execute('''
      CREATE TABLE rssi_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        at_ms INTEGER NOT NULL,
        correlation_id TEXT NOT NULL,
        rssi INTEGER NOT NULL,
        power TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_rssi_log_at ON rssi_log(at_ms)');
  }

  static Future<void> _onUpgrade(
      Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // v2: persist the narrowest estimator band per peer.
      await db.execute(
        "ALTER TABLE sightings ADD COLUMN best_band TEXT NOT NULL DEFAULT ''",
      );
    }
    if (oldVersion < 3) {
      // v3: raw RSSI sample log for calibration.
      await _createRssiLog(db);
    }
    if (oldVersion < 4) {
      // v4: upload identity + watermark for shipping rssi_log to the server.
      await _createMeta(db);
    }
  }

  static Future<LocalDb> open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'in_range_local.db');
    final database = await openDatabase(
      path,
      version: 4,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    // Keep the raw log bounded (~1-2 rows/s per peer while scanning):
    // calibration sessions get pulled off-device within days.
    await database.delete(
      'rssi_log',
      where: 'at_ms < ?',
      whereArgs: [
        DateTime.now()
            .subtract(const Duration(days: 7))
            .millisecondsSinceEpoch,
      ],
    );
    return LocalDb._(database);
  }

  /// In-memory DB for widget/unit tests (set `databaseFactory` first if needed).
  static Future<LocalDb> openInMemory() async {
    final database = await openDatabase(
      inMemoryDatabasePath,
      version: 4,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return LocalDb._(database);
  }

  Future<List<Map<String, Object?>>> allSightings() =>
      db.query('sightings', orderBy: 'last_seen_ms DESC');

  Future<void> upsertSighting({
    required String correlationId,
    required int firstSeenMs,
    required int lastSeenMs,
    required int bestRssi,
    required String rangeType,
    String bestBand = '',
  }) async {
    await db.insert(
      'sightings',
      {
        'correlation_id': correlationId,
        'first_seen_ms': firstSeenMs,
        'last_seen_ms': lastSeenMs,
        'best_rssi': bestRssi,
        'range_type': rangeType,
        'best_band': bestBand,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Append one raw advert sample (power: 'H' | 'M'). Fire-and-forget from
  /// the scan path — must never throw into the BLE callback.
  Future<void> logRssiSample({
    required int atMs,
    required String correlationId,
    required int rssi,
    required String power,
  }) async {
    try {
      await db.insert('rssi_log', {
        'at_ms': atMs,
        'correlation_id': correlationId,
        'rssi': rssi,
        'power': power,
      });
    } catch (_) {
      // Calibration logging must never break scanning.
    }
  }

  Future<List<Map<String, Object?>>> allRssiSamples() =>
      db.query('rssi_log', orderBy: 'at_ms ASC');

  // --- upload plumbing (see docs/CLOUD_RSSI_UPLOAD_SPEC.md) -----------------

  static const String _kDeviceId = 'device_id';
  static const String _kUploadCursor = 'rssi_upload_cursor';
  static const Uuid _uuid = Uuid();

  Future<String?> _meta(String key) async {
    final rows = await db.query('meta',
        columns: ['value'], where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> _setMeta(String key, String value) async {
    await db.insert('meta', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Opaque, stable id for this install's rssi_log sequence. Minted on first
  /// use. Names the SEQUENCE, not the hardware: one user walks with two phones
  /// and the extractor has to tell the sides apart.
  Future<String> deviceId() async {
    final existing = await _meta(_kDeviceId);
    if (existing != null) return existing;
    final minted = _uuid.v4();
    await _setMeta(_kDeviceId, minted);
    return minted;
  }

  /// Highest rssi_log rowid confirmed accepted by the server. 0 = nothing sent.
  ///
  /// This — not a per-row flag or an in-memory queue — is the whole outbox:
  /// rowids are monotonic, so "everything above the watermark is unsent" holds
  /// across process death for free. Only ever moves forward, and only after the
  /// server has confirmed the batch.
  Future<int> uploadCursor() async =>
      int.tryParse(await _meta(_kUploadCursor) ?? '') ?? 0;

  Future<void> setUploadCursor(int rowId) async =>
      _setMeta(_kUploadCursor, '$rowId');

  /// The next page of unsent samples, oldest first.
  ///
  /// Ordered by `id`, NOT by `at_ms`: the cursor is a rowid watermark, and on
  /// iOS the native background buffer flushes older timestamps late, so at_ms
  /// order and insertion order genuinely diverge. Sorting by at_ms here would
  /// let a late-flushed row sit below the watermark and never ship.
  Future<List<Map<String, Object?>>> samplesAfter(int afterId,
          {int limit = 500}) =>
      db.query('rssi_log',
          where: 'id > ?', whereArgs: [afterId], orderBy: 'id ASC', limit: limit);

  Future<void> clearRssiLog() async {
    await db.delete('rssi_log');
  }

  Future<void> deleteSighting(String correlationId) async {
    await db.delete(
      'sightings',
      where: 'correlation_id = ?',
      whereArgs: [correlationId],
    );
  }

  Future<void> clearSightings() async {
    await db.delete('sightings');
  }

  Future<void> clearAliases() async {
    await db.delete('aliases');
  }

  /// Wipe ALL local proximity/location traces — sightings, raw RSSI samples,
  /// and peer aliases. Used by delete-history / sign-out / account deletion so
  /// no place-fingerprint or peer history survives in the shared DB.
  Future<void> wipeAll() async {
    await db.delete('sightings');
    await db.delete('rssi_log');
    await db.delete('aliases');
    // Rotate the upload identity for UNLINKABILITY, not for collision safety:
    // `DELETE FROM rssi_log` leaves sqlite_sequence intact (verified — the next
    // rowid after a wipe is N+1, not 1), so rowids can never be reused. But
    // this runs on sign-out and account deletion, and a device_id carried into
    // the next account would let anyone reading the server table join the two
    // users as "same phone". A fresh id costs nothing and closes that.
    await db.delete('meta', where: 'key = ?', whereArgs: [_kDeviceId]);
  }

  Future<Map<String, String>> allAliases() async {
    final rows = await db.query('aliases');
    return {
      for (final r in rows)
        r['correlation_id']! as String: r['alias']! as String,
    };
  }

  Future<void> setAlias(String correlationId, String alias) async {
    final a = alias.trim();
    if (a.isEmpty) {
      await db.delete(
        'aliases',
        where: 'correlation_id = ?',
        whereArgs: [correlationId],
      );
      return;
    }
    await db.insert(
      'aliases',
      {'correlation_id': correlationId, 'alias': a},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
