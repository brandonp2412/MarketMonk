import 'package:drift/drift.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/sqlite_backup_output.dart';

const sqliteBackupFileName = 'market-monk-backup.sqlite';
const _pageSize = 1000;

Future<Uint8List> exportSqliteBackup(Database source) async {
  final output = await openSqliteBackupOutput();
  var finished = false;
  try {
    await source.transaction(() async {
      final schema = await source
          .customSelect(
            "SELECT type, name, sql FROM sqlite_master "
            "WHERE name NOT LIKE 'sqlite_%' AND sql IS NOT NULL",
          )
          .get();
      final tables = schema
          .where((entry) => entry.read<String>('type') == 'table')
          .toList();
      final secondary = schema
          .where((entry) => entry.read<String>('type') != 'table')
          .toList();
      final target = output.database;
      target.execute('PRAGMA foreign_keys = OFF');
      for (final table in tables) {
        target.execute(table.read<String>('sql'));
      }

      target.execute('BEGIN TRANSACTION');
      try {
        for (final table in source.allTables) {
          final name = table.actualTableName;
          final info = await source
              .customSelect(
                'PRAGMA table_info("$name")',
              )
              .get();
          final columns = info.map((row) => row.read<String>('name')).toList();
          final quotedColumns = columns.map((name) => '"$name"').join(', ');
          final placeholders = List.filled(columns.length, '?').join(', ');
          final insert = target.prepare(
            'INSERT INTO "$name" ($quotedColumns) VALUES ($placeholders)',
          );
          try {
            for (var offset = 0;; offset += _pageSize) {
              final rows = await source.customSelect(
                'SELECT * FROM "$name" ORDER BY rowid LIMIT ? OFFSET ?',
                variables: [
                  Variable.withInt(_pageSize),
                  Variable.withInt(offset),
                ],
              ).get();
              if (rows.isEmpty) break;
              for (final row in rows) {
                insert
                    .execute([for (final column in columns) row.data[column]]);
              }
            }
          } finally {
            insert.close();
          }
        }

        final hasSequence = await source
            .customSelect(
              "SELECT 1 FROM sqlite_master WHERE name = 'sqlite_sequence'",
            )
            .get();
        if (hasSequence.isNotEmpty) {
          target.execute('DELETE FROM sqlite_sequence');
          final sequences = await source
              .customSelect(
                'SELECT name, seq FROM sqlite_sequence',
              )
              .get();
          final insert = target.prepare(
            'INSERT INTO sqlite_sequence(name, seq) VALUES (?, ?)',
          );
          try {
            for (final row in sequences) {
              insert.execute([row.read<String>('name'), row.read<int>('seq')]);
            }
          } finally {
            insert.close();
          }
        }

        target.execute('COMMIT');
      } catch (_) {
        target.execute('ROLLBACK');
        rethrow;
      }

      for (final object in secondary) {
        target.execute(object.read<String>('sql'));
      }
      target.userVersion = source.schemaVersion;
      if (target.select('PRAGMA quick_check').single.values.single != 'ok' ||
          target.select('PRAGMA foreign_key_check').isNotEmpty) {
        throw const FormatException(
          'Generated SQLite backup failed validation',
        );
      }
    });
    finished = true;
    return output.closeAndRead();
  } finally {
    if (!finished) {
      try {
        output.closeAndRead();
      } catch (_) {}
    }
  }
}
