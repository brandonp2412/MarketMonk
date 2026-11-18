import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:market_monk/database.dart';

/// Portable, self-contained browser backup of all unified SQLite tables.
/// Native .zip backups remain available on desktop and mobile.
const webDatabaseBackupFileName = 'market-monk-web-backup.json';
const _webBackupFormat = 'market-monk-web-database';
const _webBackupVersion = 1;

Future<Uint8List> exportWebDatabaseBackup(Database database) async {
  final tables = <String, Object?>{};
  await database.transaction(() async {
    for (final table in database.allTables) {
      final tableName = table.actualTableName;
      final rows =
          await database.customSelect('SELECT * FROM "$tableName"').get();
      tables[tableName] = rows.map((row) => row.data).toList();
    }
  });
  return Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'format': _webBackupFormat,
        'version': _webBackupVersion,
        'schemaVersion': database.schemaVersion,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'tables': tables,
      }),
    ),
  );
}

/// Validates all data before an atomic restore; invalid imports preserve data.
Future<void> importWebDatabaseBackup(
  Database database,
  Uint8List bytes,
) async {
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
  } on FormatException {
    throw const FormatException('Not a valid MarketMonk web backup');
  }
  if (decoded is! Map ||
      decoded['format'] != _webBackupFormat ||
      decoded['version'] != _webBackupVersion ||
      decoded['schemaVersion'] != database.schemaVersion ||
      decoded['tables'] is! Map) {
    throw const FormatException('Unsupported MarketMonk web backup format');
  }

  final rawTables = decoded['tables'] as Map;
  final expectedTables =
      database.allTables.map((table) => table.actualTableName).toList();
  if (rawTables.length != expectedTables.length ||
      !rawTables.keys.toSet().containsAll(expectedTables)) {
    throw const FormatException('Backup is missing database tables');
  }

  final tables = <String, List<Map<String, Object?>>>{};
  for (final name in expectedTables) {
    final rawRows = rawTables[name];
    if (rawRows is! List) {
      throw FormatException('Invalid rows for $name');
    }
    final tableInfo =
        await database.customSelect('PRAGMA table_info("$name")').get();
    final columns = tableInfo.map((row) => row.read<String>('name')).toSet();
    if (columns.isEmpty) throw FormatException('Unknown table $name');
    final rows = <Map<String, Object?>>[];
    for (final rawRow in rawRows) {
      if (rawRow is! Map ||
          rawRow.keys.any((key) => key is! String || !columns.contains(key)) ||
          rawRow.length != columns.length ||
          rawRow.values.any(
            (value) =>
                value != null &&
                value is! String &&
                value is! num &&
                value is! bool,
          )) {
        throw FormatException('Invalid backup row in $name');
      }
      rows.add(rawRow.cast<String, Object?>());
    }
    tables[name] = rows;
  }

  await database.transaction(() async {
    await database.customStatement('PRAGMA defer_foreign_keys = ON');
    for (final name in expectedTables.reversed) {
      await database.customStatement('DELETE FROM "$name"');
    }
    final insertionOrder = [
      'profiles',
      ...expectedTables.where((table) => table != 'profiles'),
    ];
    for (final name in insertionOrder) {
      final rows = tables[name]!;
      if (rows.isEmpty) continue;
      final columns = rows.first.keys.toList();
      final quotedColumns = columns.map((column) => '"$column"').join(', ');
      final placeholders = List.filled(columns.length, '?').join(', ');
      final sql = 'INSERT INTO "$name" ($quotedColumns) VALUES ($placeholders)';
      await database.batch((batch) {
        for (final row in rows) {
          batch.customStatement(
            sql,
            [for (final column in columns) row[column]],
          );
        }
      });
    }
    final problems =
        await database.customSelect('PRAGMA foreign_key_check').get();
    if (problems.isNotEmpty) {
      throw const FormatException('Backup contains invalid profile references');
    }
  });
}
