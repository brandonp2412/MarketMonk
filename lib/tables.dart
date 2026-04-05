import 'package:drift/drift.dart';

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

class Tickers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get symbol => text()();
  TextColumn get name => text()();
  RealColumn get change => real()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get purchasedAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  RealColumn get amount => real()();
  RealColumn get price => real()();
}

class Candles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get symbol => text().references(Tickers, #symbol)();
  DateTimeColumn get date => dateTime()();
  RealColumn get open => real().withDefault(const Constant(-1.0))();
  RealColumn get high => real().withDefault(const Constant(-1.0))();
  RealColumn get low => real().withDefault(const Constant(-1.0))();
  RealColumn get close => real().withDefault(const Constant(-1.0))();
  IntColumn get volume => integer().withDefault(const Constant(0))();
  RealColumn get adjClose => real().withDefault(const Constant(-1.0))();
}
