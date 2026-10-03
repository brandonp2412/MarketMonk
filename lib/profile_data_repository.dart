import 'package:market_monk/database.dart';
import 'package:market_monk/unified_database.dart';

UnifiedDatabase? _profileDataDatabase;

UnifiedDatabase get profileDataDatabase =>
    _profileDataDatabase ??= UnifiedDatabase();

ProfileDataRepository get profileDataRepository =>
    ProfileDataRepository(profileDataDatabase);

void setProfileDataDatabaseForTesting(UnifiedDatabase? database) {
  _profileDataDatabase = database;
}

class ProfileTradeWrite {
  final String symbol;
  final String name;
  final double quantity;
  final double price;
  final String tradeType;
  final DateTime tradeDate;
  final double realizedPL;
  final double commission;

  const ProfileTradeWrite({
    required this.symbol,
    required this.name,
    required this.quantity,
    required this.price,
    required this.tradeType,
    required this.tradeDate,
    this.realizedPL = 0,
    this.commission = 0,
  });
}

/// Thin application boundary around profile-scoped rows in the unified store.
///
/// The UI keeps using the existing [Trade] value type while persistence is
/// scoped by stable profile id. Market candles intentionally do not live here.
class ProfileDataRepository {
  final UnifiedDatabase database;

  const ProfileDataRepository(this.database);

  Future<String> profileIdForName(String accountName) async {
    final profile = await database.readProfileByName(accountName);
    if (profile == null) {
      throw StateError('Unknown Market Monk profile: $accountName');
    }
    return profile.id;
  }

  Future<List<Trade>> readTrades(String profileId) async =>
      (await database.readTrades(profileId)).map(_toTrade).toList();

  Future<List<Trade>> readTradesForAccount(String accountName) async =>
      readTrades(await profileIdForName(accountName));

  Stream<List<Trade>> watchTradesForAccount(String accountName) async* {
    final profileId = await profileIdForName(accountName);
    yield* watchTrades(profileId);
  }

  Stream<List<Trade>> watchTrades(String profileId) =>
      database.watchTrades(profileId).map(
            (rows) => rows.map(_toTrade).toList(),
          );

  Future<int> addTrade(String profileId, ProfileTradeWrite trade) =>
      database.addTrade(
        profileId: profileId,
        symbol: trade.symbol,
        name: trade.name,
        quantity: trade.quantity,
        price: trade.price,
        tradeType: trade.tradeType,
        tradeDate: trade.tradeDate,
        realizedPL: trade.realizedPL,
        commission: trade.commission,
      );

  Future<int> addTrades(
    String profileId,
    Iterable<ProfileTradeWrite> trades,
  ) {
    return database.transaction(() async {
      var inserted = 0;
      for (final trade in trades) {
        await addTrade(profileId, trade);
        inserted++;
      }
      return inserted;
    });
  }

  Future<int> deleteTrade(String profileId, int tradeId) =>
      database.deleteTrade(profileId, tradeId);

  Future<int> deleteTradesForSymbols(
    String profileId,
    Iterable<String> symbols,
  ) =>
      database.deleteTradesForSymbols(profileId, symbols);

  Future<int> clearTrades(String profileId) => database.clearTrades(profileId);

  Future<int> updateTrade({
    required String profileId,
    required int tradeId,
    double? quantity,
    double? price,
    String? tradeType,
    DateTime? tradeDate,
    double? realizedPL,
    double? commission,
  }) =>
      database.updateTrade(
        profileId: profileId,
        tradeId: tradeId,
        quantity: quantity,
        price: price,
        tradeType: tradeType,
        tradeDate: tradeDate,
        realizedPL: realizedPL,
        commission: commission,
      );
}

Trade _toTrade(UnifiedTrade row) => Trade(
      id: row.id,
      symbol: row.symbol,
      name: row.name,
      quantity: row.quantity,
      price: row.price,
      tradeType: row.tradeType,
      tradeDate: row.tradeDate,
      realizedPL: row.realizedPL,
      commission: row.commission,
    );
