import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/native_backup_layout.dart';
import 'package:market_monk/native_web_backup.dart';
import 'package:market_monk/sqlite_backup_export.dart';
import 'package:market_monk/unified_database_backup.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database source;
  late Database destination;
  late Directory directory;

  setUp(() async {
    source = Database.connect(NativeDatabase.memory());
    destination = Database.connect(NativeDatabase.memory());
    directory = await Directory.systemTemp.createTemp('marketmonk-sqlite-');
    await source.upsertProfile(
      id: 'profile-default',
      name: 'Default',
      sortOrder: 0,
    );
    await source.upsertProfile(
      id: 'profile-broker',
      name: 'Broker',
      sortOrder: 1,
    );
    await source.setActiveProfileId('profile-broker');
    await source.writeSetting('displayCurrency', 'NZD');
    await source.addTrade(
      profileId: 'profile-broker',
      symbol: 'AAPL',
      name: 'Apple',
      quantity: 3,
      price: 125,
      tradeType: 'open',
      tradeDate: DateTime.utc(2026, 11, 18),
      rawCurrency: 'USD',
      usdRateAtTrade: 1.72,
    );
    await source.writeIbkrSettings(
      profileId: 'profile-broker',
      enabled: true,
      baseUrl: 'https://broker.test',
      token: 'private-token',
    );
    await source.upsertSymbolMetadata(
      symbol: 'AAPL',
      currency: 'USD',
      cachedAt: DateTime.utc(2026, 11, 18),
    );
    for (var i = 0; i < 1250; i++) {
      await source.upsertCandle(
        symbol: 'AAPL',
        date: DateTime.utc(2020, 1, 1).add(Duration(days: i)),
        open: 100,
        high: 110,
        low: 90,
        close: i.toDouble() + 100,
        volume: 1000 + i,
        adjClose: i.toDouble() + 100,
      );
    }
  });

  tearDown(() async {
    await source.close();
    await destination.close();
    await directory.delete(recursive: true);
  });

  test('browser-style export produces portable complete SQLite', () async {
    final bytes = await exportSqliteBackup(source);
    expect(bytes.sublist(0, 16), 'SQLite format 3\x00'.codeUnits);
    final file = File('${directory.path}/$sqliteBackupFileName');
    await file.writeAsBytes(bytes);
    expect(await isUnifiedBackupSqlite(file), isTrue);
    final sqliteFile = sqlite.sqlite3.open(
      file.path,
      mode: sqlite.OpenMode.readOnly,
    );
    try {
      expect(sqliteFile.userVersion, source.schemaVersion);
      expect(
        sqliteFile.select('PRAGMA quick_check').single.values.single,
        'ok',
      );
      expect(sqliteFile.select('PRAGMA foreign_key_check'), isEmpty);
      expect(
        sqliteFile.select('SELECT COUNT(*) AS c FROM candles').single['c'],
        1250,
      );
      expect(
        sqliteFile.select(
          "SELECT name FROM sqlite_master WHERE type='index' AND "
          "name='idx_quote_currency_changes_symbol_date'",
        ),
        hasLength(1),
      );
    } finally {
      sqliteFile.close();
    }

    await importNativeBackup(destination, bytes);
    expect(await destination.readActiveProfile(), 'Broker');
    expect(await destination.readSetting('displayCurrency'), 'NZD');
    final trades = await destination.readTrades('profile-broker');
    expect(trades, hasLength(1));
    expect(trades.single.rawCurrency, 'USD');
    expect(trades.single.usdRateAtTrade, 1.72);
    expect(
      (await destination.readIbkrSettings('profile-broker'))!.token,
      'private-token',
    );
    expect(
      (await destination.readSymbolMetadata('AAPL'))!.currency,
      'USD',
    );
    expect(
      (await destination.readCandles('AAPL')).length,
      1250,
    );

    await destination.delete(destination.trades).go();
    await restoreUnifiedDatabase(destination, file);
    expect(await destination.readTrades('profile-broker'), hasLength(1));
    expect(await destination.readSetting('displayCurrency'), 'NZD');
  });

  test('native SQLite restore replaces complete data without ZIP manifest',
      () async {
    final target = File('${directory.path}/native.sqlite');
    await snapshotUnifiedDatabase(source, target);
    await destination.upsertProfile(
      id: 'profile-default',
      name: 'Default',
      sortOrder: 0,
    );
    await destination.writeSetting('displayCurrency', 'EUR');
    await restoreUnifiedDatabase(destination, target);
    expect(await destination.readProfileNames(), ['Default', 'Broker']);
    expect(await destination.readActiveProfile(), 'Broker');
    expect(await destination.readSetting('displayCurrency'), 'NZD');
    expect(
      await destination.readTrades('profile-broker'),
      hasLength(1),
    );
    expect(
      (await destination.readCandles('AAPL')).length,
      1250,
    );
  });
}
