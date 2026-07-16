import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

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
  }

  static Future<LocalDb> open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'in_range_local.db');
    final database = await openDatabase(
      path,
      version: 3,
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
      version: 3,
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
