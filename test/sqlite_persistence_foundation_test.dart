import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/app_state_database.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/legacy_preferences_migration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('app-state SQLite stores profiles, active profile, and typed settings',
      () async {
    final appState = AppStateDatabase.connect(NativeDatabase.memory());
    addTearDown(appState.close);

    await appState.replaceProfiles(['Default', 'Brokerage']);
    await appState.setActiveProfile('Brokerage');
    await appState.writeSetting('pureBlack', true);
    await appState.writeSetting('seedColor', 123);
    await appState.writeSetting('exchangeRate_NZD', 1.73);
    await appState.writeSetting('visibleCurrencies', ['NZD', 'USD']);

    expect(await appState.readProfiles(), ['Default', 'Brokerage']);
    expect(await appState.readActiveProfile(), 'Brokerage');
    expect(await appState.readSetting('pureBlack'), isTrue);
    expect(await appState.readSetting('seedColor'), 123);
    expect(await appState.readSetting('exchangeRate_NZD'), 1.73);
    expect(
      await appState.readSetting('visibleCurrencies'),
      ['NZD', 'USD'],
    );
  });

  test('profile SQLite stores IBKR config and keyed cache entries', () async {
    final profile = Database.connect(NativeDatabase.memory());
    addTearDown(profile.close);

    await profile.writeIbkrProfileSettings(
      enabled: true,
      baseUrl: 'https://ibkr.example.test',
      token: 'secret',
    );
    await profile.writeIbkrCache(
      kind: 'performance',
      cacheKey: '1y',
      payloadJson: '{"period":"1y"}',
      cachedAt: DateTime.utc(2026, 10, 2),
    );

    final config = await profile.readIbkrProfileSettings();
    final cache = await profile.readIbkrCache('performance', '1y');

    expect(config?.enabled, isTrue);
    expect(config?.baseUrl, 'https://ibkr.example.test');
    expect(config?.token, 'secret');
    expect(cache?.payloadJson, '{"period":"1y"}');
    expect(cache?.cachedAt.isAtSameMomentAs(DateTime.utc(2026, 10, 2)), isTrue);
  });

  test('legacy preference values copy state without mutating the source',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'market-monk-sqlite-foundation-',
    );
    addTearDown(() => tempDir.delete(recursive: true));

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
            'series': {
              'period': '1y',
              'points': <Object?>[],
            },
            'cachedAt': cachedAt.toIso8601String(),
          },
        },
      }),
    };
    final appState = AppStateDatabase.connect(NativeDatabase.memory());
    addTearDown(appState.close);

    Database factory(String profile) => Database.connect(
          NativeDatabase(
            File('${tempDir.path}/$profile.sqlite'),
          ),
        );

    await seedSqliteFromLegacyValues(
      values: legacyValues,
      appState: appState,
      profileDatabaseFactory: factory,
    );

    expect(await appState.readProfiles(), ['Default', 'Brokerage']);
    expect(await appState.readActiveProfile(), 'Brokerage');
    expect(await appState.readSetting('pureBlack'), isTrue);
    expect(
      await appState.readSetting('visibleCurrencies'),
      ['NZD', 'USD'],
    );

    final brokerage = factory('Brokerage');
    addTearDown(brokerage.close);
    final config = await brokerage.readIbkrProfileSettings();
    final portfolio = await brokerage.readIbkrCache('portfolio', 'snapshot');
    final performance = await brokerage.readIbkrCache('performance', '1y');

    expect(config?.baseUrl, 'https://ibkr.example.test');
    expect(config?.token, 'legacy-token');
    expect(portfolio?.cachedAt.isAtSameMomentAs(cachedAt), isTrue);
    expect(performance?.cachedAt.isAtSameMomentAs(cachedAt), isTrue);

    expect(legacyValues['accounts'], ['Default', 'Brokerage']);
    expect(legacyValues['activeAccount'], 'Brokerage');
    expect(legacyValues['ibkrAccountConfigs'], isNotNull);
  });

  test('legacy preference values never overwrite newer SQLite state', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'market-monk-sqlite-foundation-existing-',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    final legacyValues = <String, Object?>{
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
    };
    final appState = AppStateDatabase.connect(NativeDatabase.memory());
    addTearDown(appState.close);
    await appState.replaceProfiles(['Default', 'Existing']);
    await appState.setActiveProfile('Existing');
    await appState.writeSetting('theme', 'ThemeMode.dark');

    Database factory(String profile) => Database.connect(
          NativeDatabase(
            File('${tempDir.path}/$profile.sqlite'),
          ),
        );

    final initialDefault = factory('Default');
    await initialDefault.writeIbkrProfileSettings(
      enabled: true,
      baseUrl: 'https://new.example.test',
      token: 'new-token',
    );
    await initialDefault.close();

    await seedSqliteFromLegacyValues(
      values: legacyValues,
      appState: appState,
      profileDatabaseFactory: factory,
    );

    expect(await appState.readProfiles(), ['Default', 'Existing']);
    expect(await appState.readActiveProfile(), 'Existing');
    expect(await appState.readSetting('theme'), 'ThemeMode.dark');

    final migratedDefault = factory('Default');
    addTearDown(migratedDefault.close);
    final config = await migratedDefault.readIbkrProfileSettings();
    expect(config?.baseUrl, 'https://new.example.test');
    expect(config?.token, 'new-token');
  });
}
