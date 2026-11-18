import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/web_database_backup.dart';

void main() {
  late Database database;

  setUp(() {
    database = Database.connect(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test('browser backup restores profiles, trades, settings and cache rows',
      () async {
    await database.upsertProfile(
      id: 'profile-default',
      name: 'Default',
      sortOrder: 0,
    );
    await database.upsertProfile(
      id: 'profile-test',
      name: 'Test',
      sortOrder: 1,
    );
    await database.setActiveProfileId('profile-test');
    await database.writeSetting('displayCurrency', 'NZD');
    await database.addTrade(
      profileId: 'profile-test',
      symbol: 'AAPL',
      name: 'Apple',
      quantity: 3,
      price: 125,
      tradeType: 'open',
      tradeDate: DateTime.utc(2025, 5, 12),
      rawCurrency: 'USD',
    );
    await database.customStatement(
      'INSERT INTO "symbol_metadata" '
      '(symbol, currency, cached_at) VALUES (?, ?, ?)',
      ['AAPL', 'USD', 1730000000],
    );
    final backup = await exportWebDatabaseBackup(database);

    await database.customStatement('DELETE FROM "trades"');
    await database.writeSetting('displayCurrency', 'EUR');
    await database.deleteProfile('profile-test');
    expect(await database.readTrades('profile-test'), isEmpty);

    await importWebDatabaseBackup(database, backup);
    expect(await database.readActiveProfile(), 'Test');
    expect(await database.readSetting('displayCurrency'), 'NZD');
    final trades = await database.readTrades('profile-test');
    expect(trades, hasLength(1));
    expect(trades.single.symbol, 'AAPL');
    expect(trades.single.quantity, 3);
    expect(trades.single.rawCurrency, 'USD');
    expect((await database.readSymbolMetadata('AAPL'))?.currency, 'USD');
  });

  test('rejects corrupt backup without deleting the current database',
      () async {
    await database.upsertProfile(
      id: 'profile-default',
      name: 'Default',
      sortOrder: 0,
    );
    await database.writeSetting('displayCurrency', 'NZD');
    await database.setActiveProfileId('profile-default');
    final goodBackup = jsonDecode(
      utf8.decode(await exportWebDatabaseBackup(database)),
    ) as Map<String, dynamic>;
    final rows = (goodBackup['tables'] as Map<String, dynamic>)['profiles'];
    (rows as List).first['id'] = 'missing-parent';
    // Corrupt references are checked transactionally, after all insertions.
    await expectLater(
      importWebDatabaseBackup(
        database,
        Uint8List.fromList(utf8.encode(jsonEncode(goodBackup))),
      ),
      throwsA(isA<Exception>()),
    );
    expect(await database.readProfileByName('Default'), isNotNull);
    expect(await database.readSetting('displayCurrency'), 'NZD');
  });

  test('rejects invalid format before touching database', () async {
    await database.writeSetting('displayCurrency', 'NZD');
    await expectLater(
      importWebDatabaseBackup(database, Uint8List.fromList([123, 125])),
      throwsFormatException,
    );
    expect(await database.readSetting('displayCurrency'), 'NZD');
  });
}
