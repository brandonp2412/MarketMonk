import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/native_web_backup.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

Uint8List zipBackup(
  Map<String, dynamic> manifest,
  Map<String, Uint8List> files,
) {
  final manifestBytes = utf8.encode(jsonEncode(manifest));
  final archive = Archive()
    ..addFile(
      ArchiveFile(
        'manifest.json',
        manifestBytes.length,
        manifestBytes,
      ),
    );
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Database destination;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('marketmonk-web-import-');
    destination = Database.connect(NativeDatabase.memory());
    await destination.upsertProfile(
      id: 'profile-default',
      name: 'Default',
      sortOrder: 0,
    );
  });

  tearDown(() async {
    await destination.close();
    await directory.delete(recursive: true);
  });

  test('imports current Linux ZIP and direct unified SQLite', () async {
    final source = Database.connect(NativeDatabase.memory());
    final path = File('${directory.path}/unified.sqlite');
    try {
      await source.upsertProfile(
        id: 'profile-default',
        name: 'Default',
        sortOrder: 0,
      );
      await source.upsertProfile(
        id: 'profile-bot',
        name: 'Bot',
        sortOrder: 1,
      );
      await source.setActiveProfileId('profile-bot');
      await source.writeSetting('displayCurrency', 'NZD');
      await source.addTrade(
        profileId: 'profile-bot',
        symbol: 'AAPL',
        name: 'Apple',
        quantity: 2,
        price: 150,
        tradeType: 'open',
        tradeDate: DateTime.utc(2026, 11, 12),
      );
      await source.customStatement('VACUUM INTO ?', [path.path]);
    } finally {
      await source.close();
    }
    final bytes = await path.readAsBytes();
    final manifest = <String, dynamic>{
      'format': 'market-monk-backup',
      'version': 3,
      'logical': {
        'profiles': ['Default', 'Bot'],
        'activeProfile': 'Bot',
        'settings': {},
      },
      'storage': {
        'layout': 'unified-database',
        'database': 'payload/market-monk.sqlite',
      },
    };
    final archive = zipBackup(manifest, {
      'payload/market-monk.sqlite': bytes,
    });
    await importNativeBackup(destination, archive);
    expect(await destination.readActiveProfile(), 'Bot');
    expect(await destination.readSetting('displayCurrency'), 'NZD');
    final trades = await destination.readTrades('profile-bot');
    expect(trades, hasLength(1));
    expect(trades.single.quantity, 2);

    await destination.clearTrades('profile-bot');
    await importNativeBackup(destination, bytes);
    expect(await destination.readTrades('profile-bot'), hasLength(1));
  });

  test('imports older per-profile Linux ZIP with settings and candles',
      () async {
    final path = File('${directory.path}/legacy.sqlite');
    final source = sqlite.sqlite3.open(path.path);
    try {
      source.execute('PRAGMA user_version = 10');
      source.execute('CREATE TABLE trades ('
          'id INTEGER PRIMARY KEY, symbol TEXT, name TEXT, quantity REAL,'
          'price REAL, trade_type TEXT, trade_date INTEGER,'
          'realized_p_l REAL, commission REAL)');
      source.execute('CREATE TABLE candles ('
          'id INTEGER PRIMARY KEY, symbol TEXT, date INTEGER, open REAL,'
          'high REAL, low REAL, close REAL, volume INTEGER, adj_close REAL)');
      source.execute(
        'INSERT INTO trades VALUES (1, ?, ?, 2, 125, ?, ?, 0, 0)',
        ['AAPL', 'Apple', 'open', 1794355200],
      );
      source.execute(
        'INSERT INTO candles VALUES (1, ?, ?, 125, 130, 122, 128, 100, 128)',
        ['AAPL', 1794355200],
      );
    } finally {
      source.close();
    }
    final archive = zipBackup({
      'format': 'market-monk-backup',
      'version': 1,
      'activeAccount': 'Default',
      'profiles': [
        {'name': 'Default', 'database': 'databases/0.sqlite'},
      ],
      'preferences': {'displayCurrency': 'NZD'},
    }, {
      'databases/0.sqlite': await path.readAsBytes(),
    });

    await importNativeBackup(destination, archive);
    expect(await destination.readActiveProfile(), 'Default');
    expect(await destination.readSetting('displayCurrency'), 'NZD');
    final trades = await destination.readTrades('profile-default');
    expect(trades, hasLength(1));
    expect(trades.single.price, 125);
    final count = await destination
        .customSelect(
          'SELECT COUNT(*) AS count FROM candles',
        )
        .getSingle();
    expect(count.read<int>('count'), 1);
  });

  test('invalid native ZIP leaves existing browser database unchanged',
      () async {
    await destination.writeSetting('displayCurrency', 'NZD');
    final invalid = zipBackup({
      'format': 'market-monk-backup',
      'version': 3,
      'logical': {
        'profiles': ['Default'],
        'activeProfile': 'Default',
        'settings': {},
      },
      'storage': {
        'layout': 'unified-database',
        'database': 'payload/market-monk.sqlite',
      },
    }, {
      'payload/market-monk.sqlite': Uint8List.fromList([1, 2, 3, 4]),
    });

    await expectLater(
      importNativeBackup(destination, invalid),
      throwsA(isA<Exception>()),
    );
    expect(await destination.readSetting('displayCurrency'), 'NZD');
    expect(await destination.readProfileByName('Default'), isNotNull);
  });
}
