import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'legacy_database_source.dart';
import 'tables.dart';

part 'database.g.dart';

/// App-facing trade value independent of Drift's profile-scoped storage row.
class Trade {
  final int id;
  final String symbol;
  final String name;
  final double quantity;
  final double price;
  final String tradeType;
  final DateTime tradeDate;
  final double realizedPL;
  final double commission;

  const Trade({
    required this.id,
    required this.symbol,
    required this.name,
    required this.quantity,
    required this.price,
    required this.tradeType,
    required this.tradeDate,
    required this.realizedPL,
    required this.commission,
  });
}

@DriftDatabase(
  tables: [
    Profiles,
    AppState,
    AppSettings,
    Trades,
    IbkrSettings,
    IbkrCacheEntries,
    Candles,
    SymbolMetadata,
  ],
)
class Database extends _$Database {
  static const databaseName = 'market-monk.unified';
  static const legacyMigrationCompleteKey = 'unifiedLegacyMigrationV1Complete';
  static const _appStateRowId = 1;

  final Future<LegacyDatabaseSnapshot?> Function()? _legacySnapshotLoader;

  Database()
      : _legacySnapshotLoader = null,
        super(_openConnection());

  Database.connect(
    super.executor, {
    Future<LegacyDatabaseSnapshot?> Function()? legacySnapshotLoader,
  }) : _legacySnapshotLoader = legacySnapshotLoader;

  @override
  int get schemaVersion => 1;

  Future<void> validateSchema() => validateDatabaseSchema();

  static QueryExecutor _openConnection() => driftDatabase(
        name: databaseName,
        native: const DriftNativeOptions(
          shareAcrossIsolates: true,
          databaseDirectory: getApplicationSupportDirectory,
        ),
      );

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (migrator) async {
          await customStatement(
            'DROP INDEX IF EXISTS idx_unified_profiles_sort_order',
          );
          await customStatement(
            'DROP INDEX IF EXISTS idx_unified_trades_profile_symbol_date',
          );
          await migrator.createAll();
        },
        beforeOpen: (_) async {
          await customStatement('PRAGMA foreign_keys = ON');
          final loader = _legacySnapshotLoader;
          if (loader != null) {
            await migrateLegacyDatabases(snapshotLoader: loader);
          }
          if (kDebugMode) await validateDatabaseSchema();
        },
      );

  Future<void> migrateLegacyDatabases({
    required Future<LegacyDatabaseSnapshot?> Function() snapshotLoader,
  }) async {
    if (await readSetting(legacyMigrationCompleteKey) == true) return;
    final snapshot = await snapshotLoader();
    await migrateLegacySnapshot(snapshot);
  }

  Future<void> migrateLegacySnapshot(
    LegacyDatabaseSnapshot? snapshot, {
    bool replaceExisting = false,
  }) async {
    final source = snapshot ??
        const LegacyDatabaseSnapshot(
          settings: {},
          profiles: [LegacyProfileSnapshot(name: 'Default')],
          activeProfileName: 'Default',
        );

    await transaction(() async {
      if (!replaceExisting &&
          await readSetting(legacyMigrationCompleteKey) == true) {
        return;
      }

      await _clearIncompleteLegacyMigration();

      final profileIds = <String, String>{};
      for (var index = 0; index < source.profiles.length; index++) {
        final profile = source.profiles[index];
        final profileId = 'legacy-profile-${index + 1}';
        profileIds[profile.name] = profileId;
        await upsertProfile(
          id: profileId,
          name: profile.name,
          sortOrder: index,
        );
      }

      if (profileIds.isEmpty) {
        profileIds['Default'] = 'legacy-profile-1';
        await upsertProfile(
          id: 'legacy-profile-1',
          name: 'Default',
          sortOrder: 0,
        );
      }

      final activeProfileId = profileIds[source.activeProfileName] ??
          profileIds['Default'] ??
          profileIds.values.first;
      await setActiveProfileId(activeProfileId);

      for (final setting in source.settings.entries) {
        if (setting.key == legacyMigrationCompleteKey ||
            setting.key == 'activeProfile') {
          continue;
        }
        await writeSetting(setting.key, setting.value);
        const currencyPrefix = 'symbolRawCurrency_';
        final settingValue = setting.value;
        if (setting.key.startsWith(currencyPrefix) &&
            settingValue is String &&
            settingValue.isNotEmpty) {
          final symbol = setting.key.substring(currencyPrefix.length).trim();
          if (symbol.isNotEmpty) {
            await upsertSymbolMetadata(
              symbol: symbol.toUpperCase(),
              currency: switch (settingValue) {
                'GBp' => 'GBP',
                'ZAc' => 'ZAR',
                _ => settingValue,
              },
              payloadJson: jsonEncode({'rawCurrency': settingValue}),
              cachedAt: DateTime.now().toUtc(),
            );
          }
        }
      }

      final bestCandles = <String, LegacyCandleSnapshot>{};
      for (final profile in source.profiles) {
        final profileId = profileIds[profile.name];
        if (profileId == null) continue;

        for (final trade in profile.trades) {
          await addTrade(
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
        }

        final ibkrSettings = profile.ibkrSettings;
        if (ibkrSettings != null) {
          await writeIbkrSettings(
            profileId: profileId,
            enabled: ibkrSettings.enabled,
            baseUrl: ibkrSettings.baseUrl,
            token: ibkrSettings.token,
          );
        }

        for (final entry in profile.ibkrCacheEntries) {
          await writeIbkrCache(
            profileId: profileId,
            kind: entry.kind,
            cacheKey: entry.cacheKey,
            payloadJson: entry.payloadJson,
            cachedAt: entry.cachedAt,
          );
        }

        for (final candle in profile.candles) {
          final canonical = _canonicalizeLegacyCandle(candle);
          final key =
              '${canonical.symbol}\u0000${canonical.date.microsecondsSinceEpoch}';
          final current = bestCandles[key];
          if (current == null || _isBetterCandle(canonical, current)) {
            bestCandles[key] = canonical;
          }
        }
      }

      const candleBatchSize = 1000;
      final migratedCandles = bestCandles.values.toList(growable: false);
      for (var offset = 0;
          offset < migratedCandles.length;
          offset += candleBatchSize) {
        final rows = migratedCandles
            .skip(offset)
            .take(candleBatchSize)
            .map(
              (candle) => CandlesCompanion.insert(
                symbol: candle.symbol,
                date: candle.date,
                open: Value(candle.open),
                high: Value(candle.high),
                low: Value(candle.low),
                close: Value(candle.close),
                volume: Value(candle.volume),
                adjClose: Value(candle.adjClose),
              ),
            )
            .toList(growable: false);
        await batch((batch) {
          batch.insertAll(
            candles,
            rows,
            mode: InsertMode.insertOrReplace,
          );
        });
      }

      await writeSetting(legacyMigrationCompleteKey, true);
    });
  }

  Future<void> _clearIncompleteLegacyMigration() async {
    await delete(ibkrCacheEntries).go();
    await delete(ibkrSettings).go();
    await delete(trades).go();
    await delete(appState).go();
    await delete(profiles).go();
    await delete(appSettings).go();
    await delete(candles).go();
    await delete(symbolMetadata).go();
  }

  LegacyCandleSnapshot _canonicalizeLegacyCandle(
    LegacyCandleSnapshot candle,
  ) {
    final utc = candle.date.toUtc();
    return LegacyCandleSnapshot(
      symbol: candle.symbol.trim().toUpperCase(),
      date: DateTime.utc(utc.year, utc.month, utc.day),
      open: candle.open,
      high: candle.high,
      low: candle.low,
      close: candle.close,
      volume: candle.volume,
      adjClose: candle.adjClose,
    );
  }

  bool _isBetterCandle(
    LegacyCandleSnapshot candidate,
    LegacyCandleSnapshot current,
  ) {
    final candidateQuality = _candleQuality(candidate);
    final currentQuality = _candleQuality(current);
    if (candidateQuality != currentQuality) {
      return candidateQuality > currentQuality;
    }
    return candidate.volume > current.volume;
  }

  int _candleQuality(LegacyCandleSnapshot candle) {
    final prices = [
      candle.open,
      candle.high,
      candle.low,
      candle.close,
      candle.adjClose,
    ];
    var score =
        prices.where((value) => value.isFinite && value >= 0).length * 10;
    if (candle.volume > 0) score += 2;
    if (candle.open >= 0 &&
        candle.high >= candle.open &&
        candle.high >= candle.close &&
        candle.low >= 0 &&
        candle.low <= candle.open &&
        candle.low <= candle.close) {
      score += 5;
    }
    return score;
  }

  Future<List<StoredProfile>> readProfiles() => (select(profiles)
        ..orderBy([
          (row) => OrderingTerm.asc(row.sortOrder),
          (row) => OrderingTerm.asc(row.name),
        ]))
      .get();

  Future<StoredProfile?> readProfileByName(String name) =>
      (select(profiles)..where((row) => row.name.equals(name)))
          .getSingleOrNull();

  Future<void> upsertProfile({
    required String id,
    required String name,
    required int sortOrder,
  }) {
    return into(profiles).insertOnConflictUpdate(
      ProfilesCompanion.insert(
        id: id,
        name: name,
        sortOrder: sortOrder,
      ),
    );
  }

  Future<int> deleteProfile(String profileId) =>
      (delete(profiles)..where((row) => row.id.equals(profileId))).go();

  Future<String?> readActiveProfileId() async {
    final row = await (select(appState)
          ..where((row) => row.id.equals(_appStateRowId)))
        .getSingleOrNull();
    return row?.activeProfileId;
  }

  Future<void> setActiveProfileId(String? profileId) {
    return into(appState).insertOnConflictUpdate(
      AppStateCompanion.insert(
        id: const Value(_appStateRowId),
        activeProfileId: Value(profileId),
      ),
    );
  }

  Future<List<String>> readProfileNames() async =>
      (await readProfiles()).map((profile) => profile.name).toList();

  Future<String?> readActiveProfile() async {
    final profileId = await readActiveProfileId();
    if (profileId == null) return null;
    final profile = await (select(profiles)
          ..where((row) => row.id.equals(profileId)))
        .getSingleOrNull();
    return profile?.name;
  }

  Future<void> setActiveProfile(String name) async {
    final profile = await readProfileByName(name);
    if (profile == null) {
      throw StateError('Unknown Market Monk profile: $name');
    }
    await setActiveProfileId(profile.id);
  }

  Future<void> replaceProfiles(List<String> names) async {
    if (names.isEmpty || !names.contains('Default')) {
      throw ArgumentError('Profile registry must contain Default');
    }
    if (names.toSet().length != names.length) {
      throw ArgumentError('Profile registry contains duplicate names');
    }

    await transaction(() async {
      final existing = await readProfiles();
      final existingByName = {
        for (final profile in existing) profile.name: profile,
      };
      final seed = DateTime.now().microsecondsSinceEpoch.toRadixString(36);

      for (var index = 0; index < names.length; index++) {
        final name = names[index];
        final current = existingByName[name];
        await upsertProfile(
          id: current?.id ??
              (name == 'Default' ? 'profile-default' : 'profile-$seed-$index'),
          name: name,
          sortOrder: index,
        );
      }

      final retained = names.toSet();
      for (final profile in existing) {
        if (!retained.contains(profile.name)) {
          await deleteProfile(profile.id);
        }
      }

      final activeId = await readActiveProfileId();
      if (activeId != null &&
          !existing
              .where((profile) => retained.contains(profile.name))
              .any((profile) => profile.id == activeId)) {
        final defaultProfile = await readProfileByName('Default');
        await setActiveProfileId(defaultProfile?.id);
      }
    });
  }

  Future<Object?> readSetting(String key) async {
    final row = await (select(appSettings)..where((row) => row.key.equals(key)))
        .getSingleOrNull();
    if (row == null) return null;
    return _decodeSetting(row.valueType, row.value);
  }

  Future<Map<String, Object?>> readSettings() async {
    final rows = await select(appSettings).get();
    return {
      for (final row in rows) row.key: _decodeSetting(row.valueType, row.value),
    };
  }

  Future<void> writeSetting(String key, Object? value) async {
    if (value == null) {
      await (delete(appSettings)..where((row) => row.key.equals(key))).go();
      return;
    }
    final encoded = _encodeSetting(value);
    await into(appSettings).insertOnConflictUpdate(
      AppSettingsCompanion.insert(
        key: key,
        valueType: encoded.$1,
        value: encoded.$2,
      ),
    );
  }

  Future<int> addTrade({
    required String profileId,
    required String symbol,
    required String name,
    required double quantity,
    required double price,
    required String tradeType,
    required DateTime tradeDate,
    double realizedPL = 0,
    double commission = 0,
  }) {
    return into(trades).insert(
      TradesCompanion.insert(
        profileId: profileId,
        symbol: symbol,
        name: name,
        quantity: quantity,
        price: price,
        tradeType: tradeType,
        tradeDate: tradeDate,
        realizedPL: Value(realizedPL),
        commission: Value(commission),
      ),
    );
  }

  Future<List<StoredTrade>> readTrades(String profileId) =>
      _tradesForProfile(profileId).get();

  Stream<List<StoredTrade>> watchTrades(String profileId) =>
      _tradesForProfile(profileId).watch();

  SimpleSelectStatement<$TradesTable, StoredTrade> _tradesForProfile(
    String profileId,
  ) =>
      select(trades)
        ..where((row) => row.profileId.equals(profileId))
        ..orderBy([(row) => OrderingTerm.asc(row.tradeDate)]);

  Future<int> deleteTrade(String profileId, int tradeId) => (delete(trades)
        ..where(
          (row) => row.profileId.equals(profileId) & row.id.equals(tradeId),
        ))
      .go();

  Future<int> deleteTradesForSymbols(
    String profileId,
    Iterable<String> symbols,
  ) {
    final values = symbols.toSet();
    if (values.isEmpty) return Future.value(0);
    return (delete(trades)
          ..where(
            (row) => row.profileId.equals(profileId) & row.symbol.isIn(values),
          ))
        .go();
  }

  Future<int> clearTrades(String profileId) =>
      (delete(trades)..where((row) => row.profileId.equals(profileId))).go();

  Future<int> updateTrade({
    required String profileId,
    required int tradeId,
    double? quantity,
    double? price,
    String? tradeType,
    DateTime? tradeDate,
    double? realizedPL,
    double? commission,
  }) {
    return (update(trades)
          ..where(
            (row) => row.profileId.equals(profileId) & row.id.equals(tradeId),
          ))
        .write(
      TradesCompanion(
        quantity: quantity == null ? const Value.absent() : Value(quantity),
        price: price == null ? const Value.absent() : Value(price),
        tradeType: tradeType == null ? const Value.absent() : Value(tradeType),
        tradeDate: tradeDate == null ? const Value.absent() : Value(tradeDate),
        realizedPL:
            realizedPL == null ? const Value.absent() : Value(realizedPL),
        commission:
            commission == null ? const Value.absent() : Value(commission),
      ),
    );
  }

  Future<StoredIbkrSetting?> readIbkrSettings(String profileId) =>
      (select(ibkrSettings)..where((row) => row.profileId.equals(profileId)))
          .getSingleOrNull();

  Future<void> writeIbkrSettings({
    required String profileId,
    required bool enabled,
    required String baseUrl,
    required String token,
  }) {
    return into(ibkrSettings).insertOnConflictUpdate(
      IbkrSettingsCompanion.insert(
        profileId: profileId,
        enabled: Value(enabled),
        baseUrl: Value(baseUrl),
        token: Value(token),
      ),
    );
  }

  Future<int> deleteIbkrSettings(String profileId) =>
      (delete(ibkrSettings)..where((row) => row.profileId.equals(profileId)))
          .go();

  Future<StoredIbkrCacheEntry?> readIbkrCache(
    String profileId,
    String kind,
    String cacheKey,
  ) {
    return (select(ibkrCacheEntries)
          ..where(
            (row) =>
                row.profileId.equals(profileId) &
                row.kind.equals(kind) &
                row.cacheKey.equals(cacheKey),
          ))
        .getSingleOrNull();
  }

  Future<List<StoredIbkrCacheEntry>> readIbkrCaches(String profileId) =>
      (select(ibkrCacheEntries)
            ..where((row) => row.profileId.equals(profileId)))
          .get();

  Future<void> writeIbkrCache({
    required String profileId,
    required String kind,
    required String cacheKey,
    required String payloadJson,
    required DateTime cachedAt,
  }) {
    return into(ibkrCacheEntries).insertOnConflictUpdate(
      IbkrCacheEntriesCompanion.insert(
        profileId: profileId,
        kind: kind,
        cacheKey: cacheKey,
        payloadJson: payloadJson,
        cachedAt: cachedAt,
      ),
    );
  }

  Future<int> deleteIbkrCache(String profileId, {String? kind}) {
    final statement = delete(ibkrCacheEntries)
      ..where((row) => row.profileId.equals(profileId));
    if (kind != null) {
      statement.where((row) => row.kind.equals(kind));
    }
    return statement.go();
  }

  Future<void> upsertCandle({
    required String symbol,
    required DateTime date,
    required double open,
    required double high,
    required double low,
    required double close,
    required int volume,
    required double adjClose,
  }) {
    return into(candles).insertOnConflictUpdate(
      CandlesCompanion.insert(
        symbol: symbol,
        date: date,
        open: Value(open),
        high: Value(high),
        low: Value(low),
        close: Value(close),
        volume: Value(volume),
        adjClose: Value(adjClose),
      ),
    );
  }

  Future<List<StoredCandle>> readCandles(
    String symbol, {
    DateTime? from,
    DateTime? to,
  }) {
    final query = select(candles)
      ..where((row) {
        Expression<bool> predicate = row.symbol.equals(symbol);
        if (from != null)
          predicate = predicate & row.date.isBiggerOrEqualValue(from);
        if (to != null)
          predicate = predicate & row.date.isSmallerOrEqualValue(to);
        return predicate;
      })
      ..orderBy([(row) => OrderingTerm.asc(row.date)]);
    return query.get();
  }

  Future<StoredSymbolMetadata?> readSymbolMetadata(String symbol) =>
      (select(symbolMetadata)..where((row) => row.symbol.equals(symbol)))
          .getSingleOrNull();

  Future<void> upsertSymbolMetadata({
    required String symbol,
    String? displayName,
    String? currency,
    String? exchange,
    String? quoteType,
    String? payloadJson,
    required DateTime cachedAt,
  }) {
    return into(symbolMetadata).insertOnConflictUpdate(
      SymbolMetadataCompanion.insert(
        symbol: symbol,
        displayName: Value(displayName),
        currency: Value(currency),
        exchange: Value(exchange),
        quoteType: Value(quoteType),
        payloadJson: Value(payloadJson),
        cachedAt: cachedAt,
      ),
    );
  }

  (String, String) _encodeSetting(Object value) => switch (value) {
        bool value => ('bool', value ? '1' : '0'),
        int value => ('int', value.toString()),
        double value => ('double', value.toString()),
        String value => ('string', value),
        List<String> value => ('stringList', jsonEncode(value)),
        List value when value.every((item) => item is String) => (
            'stringList',
            jsonEncode(value)
          ),
        _ => throw ArgumentError.value(value, 'value', 'Unsupported setting'),
      };

  Object _decodeSetting(String type, String value) => switch (type) {
        'bool' => value == '1',
        'int' => int.parse(value),
        'double' => double.parse(value),
        'string' => value,
        'stringList' =>
          (jsonDecode(value) as List<dynamic>).cast<String>().toList(),
        _ => throw StateError('Unsupported app setting type: $type'),
      };
}
