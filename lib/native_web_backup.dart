import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:market_monk/backup_sqlite_source.dart';
import 'package:market_monk/database.dart';
import 'package:sqlite3/common.dart';

const _sqliteHeader = 'SQLite format 3';
const _maxArchiveBytes = 128 * 1024 * 1024;
const _maxSqliteBytes = 256 * 1024 * 1024;
const _pageSize = 500;

bool isNativeBackup(Uint8List bytes) =>
    bytes.length >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4b ||
    _isSqlite(bytes);

bool _isSqlite(Uint8List bytes) =>
    bytes.length > 16 &&
    String.fromCharCodes(bytes.sublist(0, 15)) == _sqliteHeader &&
    bytes[15] == 0;

class _ProfileSource {
  const _ProfileSource(this.name, this.source);
  final String name;
  final BackupSqliteSource? source;
}

class _LogicalBackup {
  const _LogicalBackup({
    required this.profiles,
    required this.active,
    required this.settings,
  });

  final List<String> profiles;
  final String active;
  final Map<String, Object?> settings;
}

_LogicalBackup _readLogical(Map raw, {required bool legacy}) {
  final data = legacy ? raw : raw['logical'];
  if (data is! Map ||
      data['profiles'] is! List ||
      data[legacy ? 'activeAccount' : 'activeProfile'] is! String ||
      data[legacy
          ? (raw['version'] == 1 ? 'preferences' : 'settings')
          : 'settings'] is! Map) {
    throw const FormatException('Invalid MarketMonk backup manifest');
  }
  final namesRaw = data['profiles'] as List;
  final names = legacy
      ? [
          for (final entry in namesRaw)
            if (entry is Map && entry['name'] is String)
              entry['name'] as String
            else
              throw const FormatException('Invalid profile metadata'),
        ]
      : [
          for (final entry in namesRaw)
            if (entry is String)
              entry
            else
              throw const FormatException('Invalid profile metadata'),
        ];
  final active = data[legacy ? 'activeAccount' : 'activeProfile'] as String;
  if (names.isEmpty ||
      !names.contains('Default') ||
      !names.contains(active) ||
      names.toSet().length != names.length ||
      names.any(
        (name) => name.isEmpty || name.contains('/') || name.contains(r'\'),
      )) {
    throw const FormatException('Invalid backup profile names');
  }
  return _LogicalBackup(
    profiles: names,
    active: active,
    settings: Map<String, Object?>.from(
      data[legacy
          ? (raw['version'] == 1 ? 'preferences' : 'settings')
          : 'settings'] as Map,
    ),
  );
}

Uint8List _entryBytes(Archive archive, String path) {
  final entry = archive.find(path);
  if (entry == null ||
      !entry.isFile ||
      entry.size <= 0 ||
      entry.size > _maxSqliteBytes) {
    throw FormatException('Missing or invalid backup file: $path');
  }
  return Uint8List.fromList(entry.content as List<int>);
}

void _validateSource(CommonDatabase source, {required bool unified}) {
  if (source.select('PRAGMA quick_check').single.values.single != 'ok') {
    throw const FormatException('Backup SQLite integrity check failed');
  }
  final version = source.userVersion;
  if (unified ? version != 2 : version < 8 || version > 12) {
    throw FormatException(
      'Unsupported SQLite backup version $version',
    );
  }
  final tables = _tableNames(source);
  if (!tables.contains('trades') || !tables.contains('candles')) {
    throw const FormatException('Backup database is missing core tables');
  }
}

Set<String> _tableNames(CommonDatabase source) {
  return source
      .select("SELECT name FROM sqlite_master WHERE type='table'")
      .map((row) => row['name'] as String)
      .toSet();
}

Future<void> _validateUnifiedSource(
  CommonDatabase source,
  Database destination,
  _LogicalBackup? logical,
) async {
  _validateSource(source, unified: true);
  final expected = destination.allTables.map((t) => t.actualTableName).toList();
  final names = _tableNames(source);
  if (!names.containsAll(expected)) {
    throw const FormatException('Backup is missing unified SQLite tables');
  }
  for (final name in expected) {
    final columns = source
        .select('PRAGMA table_info("$name")')
        .map((row) => row['name'])
        .toSet();
    final current = (await destination
            .customSelect(
              'PRAGMA table_info("$name")',
            )
            .get())
        .map((row) => row.read<String>('name'))
        .toSet();
    if (columns.length != current.length || !columns.containsAll(current)) {
      throw FormatException('Backup table schema differs: $name');
    }
  }
  if (logical != null) {
    final names = source
        .select('SELECT name FROM profiles ORDER BY sort_order')
        .map((row) => row['name'])
        .toList();
    final state = source.select(
      'SELECT profiles.name FROM app_state LEFT JOIN profiles '
      'ON profiles.id = app_state.active_profile_id LIMIT 1',
    );
    if (names.join('\u0000') != logical.profiles.join('\u0000') ||
        state.isEmpty ||
        state.single['name'] != logical.active) {
      throw const FormatException('Backup manifest does not match profiles');
    }
  }
}

Future<void> _clearDestination(Database destination) async {
  await destination.customStatement('PRAGMA defer_foreign_keys = ON');
  for (final table in destination.allTables.toList().reversed) {
    await destination.customStatement(
      'DELETE FROM "${table.actualTableName}"',
    );
  }
}

Future<void> _insertAllRows(
  Database destination,
  CommonDatabase source,
  String table, {
  bool replace = false,
}) async {
  final columns = source
      .select('PRAGMA table_info("$table")')
      .map((row) => row['name'] as String)
      .toList();
  final quoted = columns.map((name) => '"$name"').join(', ');
  final placeholders = List.filled(columns.length, '?').join(', ');
  final sql =
      'INSERT ${replace ? 'OR REPLACE ' : ''}INTO "$table" ($quoted) VALUES ($placeholders)';
  for (var offset = 0;; offset += _pageSize) {
    final rows = source.select(
      'SELECT * FROM "$table" LIMIT ? OFFSET ?',
      [_pageSize, offset],
    );
    if (rows.isEmpty) break;
    await destination.batch((batch) {
      for (final row in rows) {
        batch.customStatement(sql, [for (final name in columns) row[name]]);
      }
    });
  }
}

Future<void> _restoreUnified(
  Database destination,
  CommonDatabase source,
) async {
  await destination.transaction(() async {
    await _clearDestination(destination);
    final tables = destination.allTables.map((t) => t.actualTableName).toList();
    for (final table in ['profiles', ...tables.where((t) => t != 'profiles')]) {
      await _insertAllRows(destination, source, table);
    }
    if (await destination.customSelect('PRAGMA foreign_key_check').get()
        case final failures when failures.isNotEmpty) {
      throw const FormatException('Backup has invalid profile references');
    }
  });
}

Future<void> _restoreLegacy(
  Database destination,
  _LogicalBackup logical,
  List<_ProfileSource> sources,
) async {
  await destination.transaction(() async {
    await _clearDestination(destination);
    final profileIds = <String, String>{};
    for (var i = 0; i < logical.profiles.length; i++) {
      final name = logical.profiles[i];
      final id = name == 'Default' ? 'profile-default' : 'profile-import-$i';
      profileIds[name] = id;
      await destination.upsertProfile(id: id, name: name, sortOrder: i);
    }
    await destination.setActiveProfileId(profileIds[logical.active]);
    for (final entry in logical.settings.entries) {
      if ({'accounts', 'activeAccount', 'activeProfile'}.contains(entry.key)) {
        continue;
      }
      if (entry.value != null) {
        await destination.writeSetting(entry.key, entry.value);
      }
    }

    for (final profile in sources) {
      final source = profile.source?.database;
      if (source == null) continue;
      final profileId = profileIds[profile.name]!;
      final tradesSql =
          'INSERT INTO trades (profile_id, symbol, name, quantity, price, '
          'trade_type, trade_date, realized_p_l, commission) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)';
      for (var offset = 0;; offset += _pageSize) {
        final trades = source.select(
          'SELECT * FROM trades ORDER BY id LIMIT ? OFFSET ?',
          [_pageSize, offset],
        );
        if (trades.isEmpty) break;
        await destination.batch((batch) {
          for (final trade in trades) {
            batch.customStatement(tradesSql, [
              profileId,
              trade['symbol'],
              trade['name'],
              trade['quantity'],
              trade['price'],
              trade['trade_type'],
              trade['trade_date'],
              trade['realized_p_l'] ?? 0.0,
              trade['commission'] ?? 0.0,
            ]);
          }
        });
      }
      final sourceTables = _tableNames(source);
      if (sourceTables.contains('ibkr_profile_settings')) {
        final settings =
            source.select('SELECT * FROM ibkr_profile_settings LIMIT 1');
        if (settings.isNotEmpty) {
          final s = settings.single;
          await destination.writeIbkrSettings(
            profileId: profileId,
            enabled: (s['enabled'] as int) != 0,
            baseUrl: s['base_url'] as String,
            token: s['token'] as String,
          );
        }
      }
      if (sourceTables.contains('ibkr_cache_entries')) {
        for (final row in source.select('SELECT * FROM ibkr_cache_entries')) {
          await destination.writeIbkrCache(
            profileId: profileId,
            kind: row['kind'] as String,
            cacheKey: row['cache_key'] as String,
            payloadJson: row['payload_json'] as String,
            cachedAt: DateTime.fromMillisecondsSinceEpoch(
              (row['cached_at'] as int) * 1000,
            ),
          );
        }
      }
      const candleSql = 'INSERT OR REPLACE INTO candles '
          '(symbol, date, open, high, low, close, volume, adj_close) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?)';
      for (var offset = 0;; offset += _pageSize) {
        final candles = source.select(
          'SELECT symbol, date, open, high, low, close, volume, adj_close '
          'FROM candles ORDER BY id LIMIT ? OFFSET ?',
          [_pageSize, offset],
        );
        if (candles.isEmpty) break;
        await destination.batch((batch) {
          for (final candle in candles) {
            final timestamp = candle['date'] as int;
            final date = DateTime.fromMillisecondsSinceEpoch(
              timestamp * 1000,
              isUtc: true,
            );
            final midnight = DateTime.utc(date.year, date.month, date.day);
            batch.customStatement(candleSql, [
              (candle['symbol'] as String).trim().toUpperCase(),
              midnight.millisecondsSinceEpoch ~/ 1000,
              candle['open'],
              candle['high'],
              candle['low'],
              candle['close'],
              candle['volume'],
              candle['adj_close'],
            ]);
          }
        });
      }
    }
    await destination.writeSetting(Database.legacyMigrationCompleteKey, true);
    await destination.writeSetting('sqliteMigrationCompleteV1', true);
    await destination.writeSetting('legacyAppStateMigrationCompleteV1', true);
    if (await destination.customSelect('PRAGMA foreign_key_check').get()
        case final failures when failures.isNotEmpty) {
      throw const FormatException('Backup has invalid profile references');
    }
  });
}

Future<void> importNativeBackup(Database destination, Uint8List bytes) async {
  if (_isSqlite(bytes)) {
    final source = await openBackupSqlite(bytes);
    try {
      await _validateUnifiedSource(source.database, destination, null);
      await _restoreUnified(destination, source.database);
    } finally {
      source.close();
    }
    return;
  }
  if (bytes.length > _maxArchiveBytes ||
      bytes.length < 4 ||
      bytes[0] != 0x50 ||
      bytes[1] != 0x4b) {
    throw const FormatException('Not a valid MarketMonk backup');
  }
  final archive = ZipDecoder().decodeBytes(bytes, verify: true);
  final manifestEntry = archive.find('manifest.json');
  if (manifestEntry == null ||
      !manifestEntry.isFile ||
      manifestEntry.size > 1024 * 1024) {
    throw const FormatException('Backup ZIP has no valid manifest');
  }
  final manifest = jsonDecode(utf8.decode(manifestEntry.content as List<int>));
  if (manifest is! Map ||
      manifest['format'] != 'market-monk-backup' ||
      manifest['version'] is! int ||
      (manifest['version'] as int) < 1 ||
      (manifest['version'] as int) > 3) {
    throw const FormatException('Unsupported MarketMonk backup archive');
  }
  final version = manifest['version'] as int;
  final logical = _readLogical(manifest, legacy: version < 3);
  final sources = <_ProfileSource>[];
  try {
    if (version == 3 &&
        manifest['storage'] is Map &&
        manifest['storage']['layout'] == 'unified-database') {
      const path = 'payload/market-monk.sqlite';
      if (manifest['storage']['database'] != path) {
        throw const FormatException('Invalid unified backup path');
      }
      final source = await openBackupSqlite(_entryBytes(archive, path));
      sources.add(_ProfileSource('unified', source));
      await _validateUnifiedSource(source.database, destination, logical);
      await _restoreUnified(destination, source.database);
      return;
    }
    if (version == 3 &&
        (manifest['storage'] is! Map ||
            manifest['storage']['layout'] != 'profile-databases')) {
      throw const FormatException('Unsupported backup storage layout');
    }
    final descriptions = version == 3
        ? manifest['storage']['profiles'] as List?
        : manifest['profiles'] as List?;
    if (descriptions == null ||
        descriptions.length != logical.profiles.length) {
      throw const FormatException('Invalid profile database list');
    }
    for (var index = 0; index < descriptions.length; index++) {
      final description = descriptions[index];
      if (description is! Map ||
          description['name'] != logical.profiles[index]) {
        throw const FormatException('Invalid profile database entry');
      }
      final path = description['database'];
      final expected = version == 3
          ? 'payload/profiles/$index.sqlite'
          : 'databases/$index.sqlite';
      if (path != null && path != expected) {
        throw const FormatException('Invalid profile database path');
      }
      final source = path == null
          ? null
          : await openBackupSqlite(_entryBytes(archive, expected));
      if (source != null) _validateSource(source.database, unified: false);
      sources.add(_ProfileSource(logical.profiles[index], source));
    }
    await _restoreLegacy(destination, logical, sources);
  } finally {
    for (final source in sources) {
      source.source?.close();
    }
  }
}
