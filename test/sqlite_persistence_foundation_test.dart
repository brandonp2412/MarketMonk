import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/legacy_preferences_migration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Database stores profiles, active profile, and typed settings',
      () async {
    final database = Database.connect(NativeDatabase.memory());
    addTearDown(database.close);

    await database.upsertProfile(
      id: 'profile-default',
      name: 'Default',
      sortOrder: 0,
    );
    await database.upsertProfile(
      id: 'profile-brokerage',
      name: 'Brokerage',
      sortOrder: 1,
    );
    await database.setActiveProfile('Brokerage');
    await database.writeSetting('pureBlack', true);
    await database.writeSetting('seedColor', 123);
    await database.writeSetting('exchangeRate_NZD', 1.73);
    await database.writeSetting('visibleCurrencies', ['NZD', 'USD']);

    expect(await database.readProfileNames(), ['Default', 'Brokerage']);
    expect(await database.readActiveProfile(), 'Brokerage');
    expect(await database.readSetting('pureBlack'), isTrue);
    expect(await database.readSetting('seedColor'), 123);
    expect(await database.readSetting('exchangeRate_NZD'), 1.73);
    expect(
      await database.readSetting('visibleCurrencies'),
      ['NZD', 'USD'],
    );
  });

  test('Database stores profile-scoped IBKR config and cache entries',
      () async {
    final database = Database.connect(NativeDatabase.memory());
    addTearDown(database.close);
    const profileId = 'profile-default';

    await database.upsertProfile(
      id: profileId,
      name: 'Default',
      sortOrder: 0,
    );
    await database.writeIbkrSettings(
      profileId: profileId,
      enabled: true,
      baseUrl: 'https://ibkr.example.test',
      token: 'secret',
    );
    await database.writeIbkrCache(
      profileId: profileId,
      kind: 'performance',
      cacheKey: '1y',
      payloadJson: '{"period":"1y"}',
      cachedAt: DateTime.utc(2026, 10, 2),
    );

    final config = await database.readIbkrSettings(profileId);
    final cache = await database.readIbkrCache(profileId, 'performance', '1y');

    expect(config?.enabled, isTrue);
    expect(config?.baseUrl, 'https://ibkr.example.test');
    expect(config?.token, 'secret');
    expect(cache?.payloadJson, '{"period":"1y"}');
    expect(cache?.cachedAt.isAtSameMomentAs(DateTime.utc(2026, 10, 2)), isTrue);
  });

  test('legacy preference values seed the one database without mutating source',
      () async {
    final database = Database.connect(NativeDatabase.memory());
    addTearDown(database.close);
    final cachedAt = DateTime.utc(2026, 10, 2, 1, 2, 3);
    final legacyValues = <String, Object?>{
      'accounts': ['Default', 'Brokerage'],
      'activeAccount': 'Brokerage',
      'pureBlack': true,
      'visibleCurrencies': ['NZD', 'USD'],
      'ibkrAccountConfigs': jsonEncode({
        'Brokerage': {
          'enabled': true,
          'baseUrl': 'https://ibkr.example.test',
          'token': 'legacy-token',
        },
      }),
      'portfolioCacheV1': jsonEncode({
        'Brokerage': {
          'positions': <Object?>[],
          'netLiquidation': null,
          'netLiquidationUsd': 1234.5,
          'cachedAt': cachedAt.toIso8601String(),
        },
      }),
      'ibkrPerformanceCacheV1': jsonEncode({
        'Brokerage': {
          '1y': {
            'series': {'period': '1y', 'points': <Object?>[]},
            'cachedAt': cachedAt.toIso8601String(),
          },
        },
      }),
    };

    await seedDatabaseFromLegacyValues(
      values: legacyValues,
      database: database,
    );

    expect(await database.readProfileNames(), ['Default', 'Brokerage']);
    expect(await database.readActiveProfile(), 'Brokerage');
    expect(await database.readSetting('pureBlack'), isTrue);
    expect(await database.readSetting('visibleCurrencies'), ['NZD', 'USD']);

    final brokerage = await database.readProfileByName('Brokerage');
    expect(brokerage, isNotNull);
    final config = await database.readIbkrSettings(brokerage!.id);
    final portfolio =
        await database.readIbkrCache(brokerage.id, 'portfolio', 'snapshot');
    final performance =
        await database.readIbkrCache(brokerage.id, 'performance', '1y');

    expect(config?.baseUrl, 'https://ibkr.example.test');
    expect(config?.token, 'legacy-token');
    expect(portfolio?.cachedAt.isAtSameMomentAs(cachedAt), isTrue);
    expect(performance?.cachedAt.isAtSameMomentAs(cachedAt), isTrue);

    expect(legacyValues['accounts'], ['Default', 'Brokerage']);
    expect(legacyValues['activeAccount'], 'Brokerage');
    expect(legacyValues['ibkrAccountConfigs'], isNotNull);
  });

  test('legacy preference values never overwrite newer database state',
      () async {
    final database = Database.connect(NativeDatabase.memory());
    addTearDown(database.close);

    await database.upsertProfile(
      id: 'profile-default',
      name: 'Default',
      sortOrder: 0,
    );
    await database.upsertProfile(
      id: 'profile-existing',
      name: 'Existing',
      sortOrder: 1,
    );
    await database.setActiveProfile('Existing');
    await database.writeSetting('theme', 'ThemeMode.dark');
    await database.writeIbkrSettings(
      profileId: 'profile-default',
      enabled: true,
      baseUrl: 'https://new.example.test',
      token: 'new-token',
    );

    await seedDatabaseFromLegacyValues(
      values: {
        'accounts': ['Default'],
        'activeAccount': 'Default',
        'theme': 'ThemeMode.light',
        'ibkrAccountConfigs': jsonEncode({
          'Default': {
            'enabled': true,
            'baseUrl': 'https://legacy.example.test',
            'token': 'legacy-token',
          },
        }),
      },
      database: database,
    );

    expect(await database.readProfileNames(), ['Default', 'Existing']);
    expect(await database.readActiveProfile(), 'Existing');
    expect(await database.readSetting('theme'), 'ThemeMode.dark');
    final config = await database.readIbkrSettings('profile-default');
    expect(config?.baseUrl, 'https://new.example.test');
    expect(config?.token, 'new-token');
  });
}
