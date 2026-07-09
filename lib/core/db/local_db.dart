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
        range_type TEXT NOT NULL
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
  }

  static Future<LocalDb> open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'in_range_local.db');
    final database = await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
    return LocalDb._(database);
  }

  /// In-memory DB for widget/unit tests (set `databaseFactory` first if needed).
  static Future<LocalDb> openInMemory() async {
    final database = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: _onCreate,
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
  }) async {
    await db.insert(
      'sightings',
      {
        'correlation_id': correlationId,
        'first_seen_ms': firstSeenMs,
        'last_seen_ms': lastSeenMs,
        'best_rssi': bestRssi,
        'range_type': rangeType,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
