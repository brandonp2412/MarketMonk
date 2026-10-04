import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/profile_data_repository.dart';
import 'package:market_monk/database.dart';

void main() {
  late Database database;
  late ProfileDataRepository repository;

  setUp(() async {
    database = Database.connect(NativeDatabase.memory());
    repository = ProfileDataRepository(database);
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
  });

  tearDown(() => database.close());

  test('profile-scoped trade reads and watches never bleed across accounts',
      () async {
    await repository.addTrade(
      'profile-default',
      ProfileTradeWrite(
        symbol: 'VTI',
        name: 'Vanguard',
        quantity: 1,
        price: 100,
        tradeType: 'open',
        tradeDate: DateTime.utc(2026, 10, 1),
      ),
    );
    await repository.addTrade(
      'profile-bot',
      ProfileTradeWrite(
        symbol: 'AAPL',
        name: 'Apple',
        quantity: 2,
        price: 200,
        tradeType: 'open',
        tradeDate: DateTime.utc(2026, 10, 2),
      ),
    );

    expect(
      (await repository.readTrades('profile-default')).single.symbol,
      'VTI',
    );
    expect((await repository.readTrades('profile-bot')).single.symbol, 'AAPL');

    final next = repository.watchTrades('profile-default').first;
    await repository.addTrade(
      'profile-bot',
      ProfileTradeWrite(
        symbol: 'MSFT',
        name: 'Microsoft',
        quantity: 1,
        price: 300,
        tradeType: 'open',
        tradeDate: DateTime.utc(2026, 10, 3),
      ),
    );
    expect((await next).map((trade) => trade.symbol), ['VTI']);
  });

  test('profile lookup preserves stable id after rename', () async {
    expect(await repository.profileIdForName('Bot'), 'profile-bot');

    await database.upsertProfile(
      id: 'profile-bot',
      name: 'Trading Bot',
      sortOrder: 1,
    );

    expect(await repository.profileIdForName('Trading Bot'), 'profile-bot');
  });

  test('mutations require the profile id and affect only that profile',
      () async {
    final id = await repository.addTrade(
      'profile-default',
      ProfileTradeWrite(
        symbol: 'VTI',
        name: 'Vanguard',
        quantity: 1,
        price: 100,
        tradeType: 'open',
        tradeDate: DateTime.utc(2026, 10, 1),
      ),
    );
    await repository.addTrade(
      'profile-bot',
      ProfileTradeWrite(
        symbol: 'VTI',
        name: 'Vanguard',
        quantity: 5,
        price: 110,
        tradeType: 'open',
        tradeDate: DateTime.utc(2026, 10, 1),
      ),
    );

    await repository.updateTrade(
      profileId: 'profile-default',
      tradeId: id,
      quantity: 3,
    );
    expect((await repository.readTrades('profile-default')).single.quantity, 3);
    expect((await repository.readTrades('profile-bot')).single.quantity, 5);

    await repository.deleteTradesForSymbols('profile-default', ['VTI']);
    expect(await repository.readTrades('profile-default'), isEmpty);
    expect(await repository.readTrades('profile-bot'), hasLength(1));
  });
}
