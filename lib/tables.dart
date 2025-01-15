import 'package:drift/drift.dart';

class Tickers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get symbol => text().unique()();
  TextColumn get name => text()();
  RealColumn get change => real()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  RealColumn get amount => real()();
}

class Candles extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get date => dateTime()();
  RealColumn get open => real().withDefault(const Constant(-1.0))();
  RealColumn get high => real().withDefault(const Constant(-1.0))();
  RealColumn get low => real().withDefault(const Constant(-1.0))();
  RealColumn get close => real().withDefault(const Constant(-1.0))();
  IntColumn get volume => integer().withDefault(const Constant(0))();
  RealColumn get adjClose => real().withDefault(const Constant(-1.0))();
}
