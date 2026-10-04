import 'package:drift/drift.dart';

@TableIndex(
  name: 'idx_trades_symbol_trade_date',
  columns: {#symbol, #tradeDate},
)
class Trades extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get symbol => text()();
  TextColumn get name => text()();
  // Positive = buy (open), negative = sell (close)
  RealColumn get quantity => real()();
  RealColumn get price => real()();
  // 'open' or 'close'
  TextColumn get tradeType => text()();
  DateTimeColumn get tradeDate => dateTime()();
  RealColumn get realizedPL => real().withDefault(const Constant(0.0))();
  RealColumn get commission => real().withDefault(const Constant(0.0))();
}

@TableIndex(
  name: 'idx_candles_symbol_date',
  columns: {#symbol, #date},
  unique: true,
)
class Candles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get symbol => text()();
  DateTimeColumn get date => dateTime()();
  RealColumn get open => real().withDefault(const Constant(-1.0))();
  RealColumn get high => real().withDefault(const Constant(-1.0))();
  RealColumn get low => real().withDefault(const Constant(-1.0))();
  RealColumn get close => real().withDefault(const Constant(-1.0))();
  IntColumn get volume => integer().withDefault(const Constant(0))();
  RealColumn get adjClose => real().withDefault(const Constant(-1.0))();
}

class IbkrProfileSettings extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  BoolColumn get enabled => boolean().withDefault(const Constant(false))();
  TextColumn get baseUrl => text().withDefault(const Constant(''))();
  TextColumn get token => text().withDefault(const Constant(''))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class IbkrCacheEntries extends Table {
  TextColumn get kind => text()();
  TextColumn get cacheKey => text()();
  TextColumn get payloadJson => text()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {kind, cacheKey};
}
