import 'package:drift/drift.dart';

@TableIndex(
  name: 'idx_unified_profiles_sort_order',
  columns: {#sortOrder},
)
@DataClassName('StoredProfile')
class Profiles extends Table {
  @override
  String get tableName => 'profiles';
  TextColumn get id => text().withLength(min: 1, max: 128)();
  TextColumn get name => text().withLength(min: 1, max: 256).unique()();
  IntColumn get sortOrder => integer()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('StoredAppState')
class AppState extends Table {
  @override
  String get tableName => 'app_state';
  IntColumn get id => integer().withDefault(const Constant(1))();
  TextColumn get activeProfileId => text()
      .nullable()
      .references(Profiles, #id, onDelete: KeyAction.setNull)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('StoredAppSetting')
class AppSettings extends Table {
  @override
  String get tableName => 'app_settings';
  TextColumn get key => text()();
  TextColumn get valueType => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@TableIndex(
  name: 'idx_unified_trades_profile_symbol_date',
  columns: {#profileId, #symbol, #tradeDate},
)
@DataClassName('StoredTrade')
class Trades extends Table {
  @override
  String get tableName => 'trades';
  IntColumn get id => integer().autoIncrement()();
  TextColumn get profileId =>
      text().references(Profiles, #id, onDelete: KeyAction.cascade)();
  TextColumn get symbol => text()();
  TextColumn get name => text()();
  RealColumn get quantity => real()();
  RealColumn get price => real()();
  TextColumn get tradeType => text()();
  DateTimeColumn get tradeDate => dateTime()();
  RealColumn get realizedPL => real().withDefault(const Constant(0.0))();
  RealColumn get commission => real().withDefault(const Constant(0.0))();
}

@DataClassName('StoredIbkrSetting')
class IbkrSettings extends Table {
  @override
  String get tableName => 'ibkr_settings';
  TextColumn get profileId =>
      text().references(Profiles, #id, onDelete: KeyAction.cascade)();
  BoolColumn get enabled => boolean().withDefault(const Constant(false))();
  TextColumn get baseUrl => text().withDefault(const Constant(''))();
  TextColumn get token => text().withDefault(const Constant(''))();

  @override
  Set<Column<Object>> get primaryKey => {profileId};
}

@DataClassName('StoredIbkrCacheEntry')
class IbkrCacheEntries extends Table {
  @override
  String get tableName => 'ibkr_cache_entries';
  TextColumn get profileId =>
      text().references(Profiles, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => text()();
  TextColumn get cacheKey => text()();
  TextColumn get payloadJson => text()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {profileId, kind, cacheKey};
}

@DataClassName('StoredCandle')
class Candles extends Table {
  @override
  String get tableName => 'candles';
  TextColumn get symbol => text()();
  DateTimeColumn get date => dateTime()();
  RealColumn get open => real().withDefault(const Constant(-1.0))();
  RealColumn get high => real().withDefault(const Constant(-1.0))();
  RealColumn get low => real().withDefault(const Constant(-1.0))();
  RealColumn get close => real().withDefault(const Constant(-1.0))();
  IntColumn get volume => integer().withDefault(const Constant(0))();
  RealColumn get adjClose => real().withDefault(const Constant(-1.0))();

  @override
  Set<Column<Object>> get primaryKey => {symbol, date};
}

@DataClassName('StoredSymbolMetadata')
class SymbolMetadata extends Table {
  @override
  String get tableName => 'symbol_metadata';
  TextColumn get symbol => text()();
  TextColumn get displayName => text().nullable()();
  TextColumn get currency => text().nullable()();
  TextColumn get exchange => text().nullable()();
  TextColumn get quoteType => text().nullable()();
  TextColumn get payloadJson => text().nullable()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {symbol};
}
