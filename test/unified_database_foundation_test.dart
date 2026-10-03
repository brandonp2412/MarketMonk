import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/unified_database.dart';

void main() {
  late UnifiedDatabase database;

  setUp(() {
    database = UnifiedDatabase.connect(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test('stable profile ids scope account data and preserve global market data',
      () async {
    await database.upsertProfile(
      id: 'profile-default',
      name: 'Default',
      sortOrder: 0,
    );
    await database.upsertProfile(
      id: 'profile-bot',
      name: 'Bot',
      sortOrder: 1,
    );
    await database.setActiveProfileId('profile-bot');
    await database.writeSetting('displayCurrency', 'NZD');

    await database.addTrade(
      profileId: 'profile-bot',
      symbol: 'AAPL',
      name: 'Apple',
      quantity: 2,
      price: 200,
      tradeType: 'open',
      tradeDate: DateTime.utc(2026, 10, 3),
    );
    await database.writeIbkrSettings(
      profileId: 'profile-bot',
      enabled: true,
      baseUrl: 'https://ibkr.example.test',
      token: 'secret',
    );
    await database.writeIbkrCache(
      profileId: 'profile-bot',
      kind: 'portfolio',
      cacheKey: 'snapshot',
      payloadJson: '{"value":1}',
      cachedAt: DateTime.utc(2026, 10, 3),
    );
    await database.upsertCandle(
      symbol: 'AAPL',
      date: DateTime.utc(2026, 10, 3),
      open: 198,
      high: 203,
      low: 197,
      close: 201,
      volume: 123,
      adjClose: 201,
    );
    await database.upsertSymbolMetadata(
      symbol: 'AAPL',
      displayName: 'Apple Inc.',
      currency: 'USD',
      exchange: 'NMS',
      quoteType: 'EQUITY',
      cachedAt: DateTime.utc(2026, 10, 3),
    );

    expect(await database.readActiveProfileId(), 'profile-bot');
    expect(await database.readSetting('displayCurrency'), 'NZD');
    expect(await database.readTrades('profile-bot'), hasLength(1));
    expect((await database.readIbkrSettings('profile-bot'))?.enabled, isTrue);
    expect(
      (await database.readIbkrCache(
        'profile-bot',
        'portfolio',
        'snapshot',
      ))
          ?.payloadJson,
      '{"value":1}',
    );

    await database.deleteProfile('profile-bot');

    expect(await database.readActiveProfileId(), isNull);
    expect(await database.readTrades('profile-bot'), isEmpty);
    expect(await database.readIbkrSettings('profile-bot'), isNull);
    expect(
      await database.readIbkrCache('profile-bot', 'portfolio', 'snapshot'),
      isNull,
    );
    expect(await database.readCandles('AAPL'), hasLength(1));
    expect((await database.readSymbolMetadata('AAPL'))?.currency, 'USD');
    expect(await database.readSetting('displayCurrency'), 'NZD');
  });

  test('profile ids stay stable across profile renames', () async {
    await database.upsertProfile(
      id: 'profile-123',
      name: 'Brokerage',
      sortOrder: 1,
    );
    await database.upsertProfile(
      id: 'profile-123',
      name: 'Long-term',
      sortOrder: 0,
    );

    final profiles = await database.readProfiles();
    expect(profiles, hasLength(1));
    expect(profiles.single.id, 'profile-123');
    expect(profiles.single.name, 'Long-term');
    expect(profiles.single.sortOrder, 0);
  });

  test('foreign keys reject profile-scoped rows without a profile', () async {
    await expectLater(
      database.addTrade(
        profileId: 'missing',
        symbol: 'VTI',
        name: 'Vanguard Total Stock Market ETF',
        quantity: 1,
        price: 100,
        tradeType: 'open',
        tradeDate: DateTime.utc(2026, 10, 3),
      ),
      throwsA(anything),
    );
  });

  test('global candles are unique by canonical symbol and date', () async {
    final date = DateTime.utc(2026, 10, 3);
    await database.upsertCandle(
      symbol: 'VTI',
      date: date,
      open: 100,
      high: 101,
      low: 99,
      close: 100,
      volume: 10,
      adjClose: 100,
    );
    await database.upsertCandle(
      symbol: 'VTI',
      date: date,
      open: 110,
      high: 111,
      low: 109,
      close: 110,
      volume: 20,
      adjClose: 110,
    );

    final rows = await database.readCandles('VTI');
    expect(rows, hasLength(1));
    expect(rows.single.close, 110);
    expect(rows.single.volume, 20);
  });

  test('profile names are unique independently of stable ids', () async {
    await database.upsertProfile(
      id: 'profile-a',
      name: 'Default',
      sortOrder: 0,
    );

    await expectLater(
      database.upsertProfile(
        id: 'profile-b',
        name: 'Default',
        sortOrder: 1,
      ),
      throwsA(anything),
    );
  });
}
