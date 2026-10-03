import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/backup_archive.dart';
import 'package:market_monk/database.dart';

void main() {
  late Directory directory;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    directory = await Directory.systemTemp.createTemp('market-monk-archive-');
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  Future<File> createProfileDatabase(
    String fileName, {
    String symbol = 'VTI',
  }) async {
    final file = File('${directory.path}/$fileName');
    final database = Database.connect(NativeDatabase(file));
    await database.trades.insertOne(
      TradesCompanion.insert(
        symbol: symbol,
        name: symbol,
        quantity: 2,
        price: 100,
        tradeType: 'open',
        tradeDate: DateTime(2026, 10, 3),
      ),
    );
    await database.candles.insertOne(
      CandlesCompanion.insert(
        symbol: symbol,
        date: DateTime(2026, 10, 3),
        close: const Value(101),
      ),
    );
    await database.writeIbkrProfileSettings(
      enabled: true,
      baseUrl: 'https://broker.test',
      token: 'token-$symbol',
    );
    await database.writeIbkrCache(
      kind: 'portfolio',
      cacheKey: 'snapshot',
      payloadJson: '{"symbol":"$symbol"}',
      cachedAt: DateTime(2026, 10, 3),
    );
    await database.close();
    return file;
  }

  test('version 3 round trip preserves logical state and profile database data',
      () async {
    final defaultDb = await createProfileDatabase(
      'default.sqlite',
      symbol: 'VTI',
    );
    final brokerageDb = await createProfileDatabase(
      'brokerage.sqlite',
      symbol: 'VXUS',
    );
    final work = await directory.createTemp('build-');

    final archive = await buildMarketMonkBackupArchive(
      workingDirectory: work,
      logical: const MarketMonkLogicalBackup(
        profiles: ['Default', 'Brokerage'],
        activeProfile: 'Brokerage',
        settings: {
          'displayCurrency': 'NZD',
          'favoriteStocks': ['VTI', 'VXUS'],
        },
      ),
      storage: MarketMonkBackupStorage.profileDatabases({
        'Default': defaultDb,
        'Brokerage': brokerageDb,
      }),
    );

    final extract = await directory.createTemp('extract-');
    final restored = await extractMarketMonkBackupArchive(
      archiveFile: archive,
      workingDirectory: extract,
    );

    expect(restored.logical.profiles, ['Default', 'Brokerage']);
    expect(restored.logical.activeProfile, 'Brokerage');
    expect(restored.logical.settings['displayCurrency'], 'NZD');
    expect(
      restored.storage.layout,
      MarketMonkBackupStorageLayout.profileDatabases,
    );

    final restoredDb = Database.connect(
      NativeDatabase(restored.storage.profileDatabases['Brokerage']!),
    );
    expect(
      (await restoredDb.select(restoredDb.trades).get()).single.symbol,
      'VXUS',
    );
    expect(
      (await restoredDb.select(restoredDb.candles).get()).single.close,
      101,
    );
    expect((await restoredDb.readIbkrProfileSettings())!.token, 'token-VXUS');
    expect(
      (await restoredDb.readIbkrCache('portfolio', 'snapshot'))!.payloadJson,
      '{"symbol":"VXUS"}',
    );
    await restoredDb.close();
  });

  test('legacy version 2 multi-file archive still extracts', () async {
    final profileDb = await createProfileDatabase(
      'legacy-source.sqlite',
      symbol: 'LEGACY',
    );
    final manifest = File('${directory.path}/legacy-manifest.json');
    await manifest.writeAsString(
      jsonEncode({
        'format': 'market-monk-backup',
        'version': 2,
        'activeAccount': 'Default',
        'profiles': [
          {'name': 'Default', 'database': 'databases/0.sqlite'},
        ],
        'settings': {'displayCurrency': 'USD'},
      }),
    );
    final archive = File('${directory.path}/legacy.zip');
    final encoder = ZipFileEncoder()..create(archive.path);
    await encoder.addFile(profileDb, 'databases/0.sqlite');
    await encoder.addFile(manifest, 'manifest.json');
    await encoder.close();

    final extract = await directory.createTemp('legacy-extract-');
    final restored = await extractMarketMonkBackupArchive(
      archiveFile: archive,
      workingDirectory: extract,
    );

    expect(restored.logical.profiles, ['Default']);
    expect(restored.logical.settings['displayCurrency'], 'USD');
    expect(
      restored.storage.layout,
      MarketMonkBackupStorageLayout.profileDatabases,
    );
    final restoredDb = Database.connect(
      NativeDatabase(restored.storage.profileDatabases['Default']!),
    );
    expect(
      (await restoredDb.select(restoredDb.trades).get()).single.symbol,
      'LEGACY',
    );
    await restoredDb.close();
  });

  test('version 3 unified database payload is layout-compatible', () async {
    final unified = await createProfileDatabase(
      'future-unified.sqlite',
      symbol: 'FUTURE',
    );
    final work = await directory.createTemp('unified-build-');
    final archive = await buildMarketMonkBackupArchive(
      workingDirectory: work,
      logical: const MarketMonkLogicalBackup(
        profiles: ['Default', 'Brokerage'],
        activeProfile: 'Default',
        settings: {'displayCurrency': 'NZD'},
      ),
      storage: MarketMonkBackupStorage.unifiedDatabase(unified),
    );

    final extract = await directory.createTemp('unified-extract-');
    final restored = await extractMarketMonkBackupArchive(
      archiveFile: archive,
      workingDirectory: extract,
    );

    expect(
      restored.storage.layout,
      MarketMonkBackupStorageLayout.unifiedDatabase,
    );
    expect(restored.storage.profileDatabases, isEmpty);
    expect(await restored.storage.unifiedDatabase!.exists(), isTrue);
    expect(restored.logical.profiles, ['Default', 'Brokerage']);
    expect(restored.logical.settings['displayCurrency'], 'NZD');
  });
}
