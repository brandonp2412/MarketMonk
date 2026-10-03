import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/backup_archive.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/unified_backup_store.dart';
import 'package:market_monk/unified_database.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('unified-backup-test-');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test(
    'new backup is one unified snapshot preserving profile identity and caches',
    () async {
      final source = UnifiedDatabase.connect(NativeDatabase.memory());
      addTearDown(source.close);

      await source.upsertProfile(
        id: 'profile-default-stable',
        name: 'Default',
        sortOrder: 0,
      );
      await source.upsertProfile(
        id: 'profile-bot-stable',
        name: 'IBKR Bot',
        sortOrder: 1,
      );
      await source.setActiveProfileId('profile-bot-stable');
      await source.writeSetting('displayCurrency', 'NZD');
      await source.addTrade(
        profileId: 'profile-bot-stable',
        symbol: 'VTI',
        name: 'Vanguard Total Stock Market ETF',
        quantity: 3,
        price: 250,
        tradeType: 'open',
        tradeDate: DateTime.utc(2026, 10, 1),
      );
      await source.writeIbkrSettings(
        profileId: 'profile-bot-stable',
        enabled: true,
        baseUrl: 'https://example.invalid',
        token: 'secret',
      );
      await source.writeIbkrCache(
        profileId: 'profile-bot-stable',
        kind: 'portfolio',
        cacheKey: 'snapshot',
        payloadJson: '{"positions":[{"symbol":"VTI"}]}',
        cachedAt: DateTime.utc(2026, 10, 3),
      );
      await source.upsertCandle(
        symbol: 'VTI',
        date: DateTime.utc(2026, 10, 2),
        open: 250,
        high: 255,
        low: 249,
        close: 254,
        volume: 1234,
        adjClose: 254,
      );
      await source.upsertSymbolMetadata(
        symbol: 'VTI',
        displayName: 'Vanguard Total Stock Market ETF',
        currency: 'USD',
        exchange: 'NYSE',
        quoteType: 'ETF',
        payloadJson: '{"source":"test"}',
        cachedAt: DateTime.utc(2026, 10, 3),
      );

      final archive = await UnifiedBackupStore(source).exportArchive(tempDir);
      final extractedDir = await tempDir.createTemp('extract-');
      final extracted = await extractMarketMonkBackupArchive(
        archiveFile: archive,
        workingDirectory: extractedDir,
      );

      expect(
        extracted.storage.layout,
        MarketMonkBackupStorageLayout.unifiedDatabase,
      );
      expect(extracted.storage.profileDatabases, isEmpty);
      expect(extracted.logical.profiles, ['Default', 'IBKR Bot']);
      expect(extracted.logical.activeProfile, 'IBKR Bot');
      expect(extracted.logical.settings['displayCurrency'], 'NZD');

      final target = UnifiedDatabase.connect(NativeDatabase.memory());
      addTearDown(target.close);
      await target.upsertProfile(id: 'old', name: 'Default', sortOrder: 0);
      await target.setActiveProfileId('old');

      await UnifiedBackupStore(target).restoreBackup(extracted, extractedDir);

      final profiles = await target.readProfiles();
      expect(profiles.map((profile) => profile.id), [
        'profile-default-stable',
        'profile-bot-stable',
      ]);
      expect(await target.readActiveProfileId(), 'profile-bot-stable');
      expect(await target.readSetting('displayCurrency'), 'NZD');

      final trades = await target.readTrades('profile-bot-stable');
      expect(trades.single.symbol, 'VTI');
      final config = await target.readIbkrSettings('profile-bot-stable');
      expect(config!.token, 'secret');
      final cache = await target.readIbkrCache(
        'profile-bot-stable',
        'portfolio',
        'snapshot',
      );
      expect(cache!.payloadJson, contains('"VTI"'));
      expect(await target.readCandles('VTI'), hasLength(1));
      expect((await target.readSymbolMetadata('VTI'))!.currency, 'USD');
    },
  );

  test(
    'restore transaction rolls back live unified data on insert failure',
    () async {
      final source = UnifiedDatabase.connect(NativeDatabase.memory());
      addTearDown(source.close);
      await source.upsertProfile(id: 'restored', name: 'Default', sortOrder: 0);
      await source.setActiveProfileId('restored');

      final snapshotFile = File('${tempDir.path}/source.sqlite');
      await source.customStatement('VACUUM INTO ?', [snapshotFile.path]);

      final target = UnifiedDatabase.connect(NativeDatabase.memory());
      addTearDown(target.close);
      await target.upsertProfile(id: 'original', name: 'Default', sortOrder: 0);
      await target.setActiveProfileId('original');
      await target.writeSetting('sentinel', 'keep-me');
      await target.customStatement('''
      CREATE TRIGGER fail_profile_restore
      BEFORE INSERT ON profiles
      BEGIN
        SELECT RAISE(ABORT, 'simulated restore failure');
      END
    ''');

      await expectLater(
        UnifiedBackupStore(target).restoreUnifiedFile(snapshotFile),
        throwsA(anything),
      );

      final profiles = await target.readProfiles();
      expect(profiles.single.id, 'original');
      expect(await target.readActiveProfileId(), 'original');
      expect(await target.readSetting('sentinel'), 'keep-me');
    },
  );

  test(
    'legacy profile database imports into the same unified profile id',
    () async {
      final legacyFile = File('${tempDir.path}/legacy.sqlite');
      final legacy = Database.connect(NativeDatabase(legacyFile));
      await legacy.into(legacy.trades).insert(
            TradesCompanion.insert(
              symbol: 'VXUS',
              name: 'Vanguard Total International Stock ETF',
              quantity: 4,
              price: 70,
              tradeType: 'open',
              tradeDate: DateTime.utc(2026, 9, 1),
            ),
          );
      await legacy.writeIbkrProfileSettings(
        enabled: true,
        baseUrl: 'https://legacy.invalid',
        token: 'legacy-token',
      );
      await legacy.writeIbkrCache(
        kind: 'portfolio',
        cacheKey: 'snapshot',
        payloadJson: '{"legacy":true}',
        cachedAt: DateTime.utc(2026, 9, 2),
      );
      await legacy.into(legacy.candles).insert(
            CandlesCompanion.insert(
              symbol: 'VXUS',
              date: DateTime.utc(2026, 9, 1),
              open: const Value(70),
              high: const Value(72),
              low: const Value(69),
              close: const Value(71),
              volume: const Value(900),
              adjClose: const Value(71),
            ),
          );
      await legacy.close();

      final target = UnifiedDatabase.connect(NativeDatabase.memory());
      addTearDown(target.close);
      await target.upsertProfile(
        id: 'stable-profile-id',
        name: 'IBKR Bot',
        sortOrder: 0,
      );
      await target.setActiveProfileId('stable-profile-id');
      await target.addTrade(
        profileId: 'stable-profile-id',
        symbol: 'OLD',
        name: 'Old',
        quantity: 1,
        price: 1,
        tradeType: 'open',
        tradeDate: DateTime.utc(2020),
      );

      await UnifiedBackupStore(target).importLegacyProfile(
        sourceFile: legacyFile,
        profileId: 'stable-profile-id',
      );

      expect((await target.readProfiles()).single.id, 'stable-profile-id');
      expect(
        (await target.readTrades('stable-profile-id')).single.symbol,
        'VXUS',
      );
      expect(
        (await target.readIbkrSettings('stable-profile-id'))!.token,
        'legacy-token',
      );
      expect(
        (await target.readIbkrCache(
          'stable-profile-id',
          'portfolio',
          'snapshot',
        ))!
            .payloadJson,
        '{"legacy":true}',
      );
      expect(await target.readCandles('VXUS'), hasLength(1));
    },
  );

  test(
    'legacy multi-file backup restores both profiles into unified storage',
    () async {
      final defaultFile = File('${tempDir.path}/default.sqlite');
      final botFile = File('${tempDir.path}/bot.sqlite');

      final legacyDefault = Database.connect(NativeDatabase(defaultFile));
      await legacyDefault.into(legacyDefault.trades).insert(
            TradesCompanion.insert(
              symbol: 'VOO',
              name: 'Vanguard S&P 500 ETF',
              quantity: 2,
              price: 600,
              tradeType: 'open',
              tradeDate: DateTime.utc(2026, 8, 1),
            ),
          );
      await legacyDefault.close();

      final legacyBot = Database.connect(NativeDatabase(botFile));
      await legacyBot.into(legacyBot.trades).insert(
            TradesCompanion.insert(
              symbol: 'QQQ',
              name: 'Invesco QQQ',
              quantity: 1,
              price: 620,
              tradeType: 'open',
              tradeDate: DateTime.utc(2026, 8, 2),
            ),
          );
      await legacyBot.writeIbkrCache(
        kind: 'portfolio',
        cacheKey: 'snapshot',
        payloadJson: '{"account":"bot"}',
        cachedAt: DateTime.utc(2026, 8, 3),
      );
      await legacyBot.close();

      final restored = MarketMonkBackupContents(
        logical: const MarketMonkLogicalBackup(
          profiles: ['Default', 'IBKR Bot'],
          activeProfile: 'IBKR Bot',
          settings: {'displayCurrency': 'AUD'},
        ),
        storage: MarketMonkBackupStorage.profileDatabases({
          'Default': defaultFile,
          'IBKR Bot': botFile,
        }),
      );

      final target = UnifiedDatabase.connect(NativeDatabase.memory());
      addTearDown(target.close);
      await UnifiedBackupStore(target).restoreBackup(restored, tempDir);

      final profiles = await target.readProfiles();
      expect(profiles.map((profile) => profile.name), ['Default', 'IBKR Bot']);
      final defaultId =
          profiles.singleWhere((profile) => profile.name == 'Default').id;
      final botId =
          profiles.singleWhere((profile) => profile.name == 'IBKR Bot').id;
      expect((await target.readTrades(defaultId)).single.symbol, 'VOO');
      expect((await target.readTrades(botId)).single.symbol, 'QQQ');
      expect(
        (await target.readIbkrCache(
          botId,
          'portfolio',
          'snapshot',
        ))!
            .payloadJson,
        '{"account":"bot"}',
      );
      expect(await target.readActiveProfileId(), botId);
      expect(await target.readSetting('displayCurrency'), 'AUD');
    },
  );
}
