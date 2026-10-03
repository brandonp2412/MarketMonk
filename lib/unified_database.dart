import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'unified_tables.dart';

part 'unified_database.g.dart';

@DriftDatabase(
  tables: [
    UnifiedProfiles,
    UnifiedAppState,
    UnifiedAppSettings,
    UnifiedTrades,
    UnifiedIbkrSettings,
    UnifiedIbkrCacheEntries,
    UnifiedCandles,
    UnifiedSymbolMetadata,
  ],
)
class UnifiedDatabase extends _$UnifiedDatabase {
  static const databaseName = 'market-monk.unified';
  static const _appStateRowId = 1;

  UnifiedDatabase() : super(_openConnection());

  UnifiedDatabase.connect(super.executor);

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() => driftDatabase(
        name: databaseName,
        native: const DriftNativeOptions(
          shareAcrossIsolates: true,
          databaseDirectory: getApplicationSupportDirectory,
        ),
      );

  @override
  MigrationStrategy get migration => MigrationStrategy(
        beforeOpen: (_) async {
          await customStatement('PRAGMA foreign_keys = ON');
          if (kDebugMode) await validateDatabaseSchema();
        },
      );

  Future<List<UnifiedProfile>> readProfiles() => (select(unifiedProfiles)
        ..orderBy([
          (row) => OrderingTerm.asc(row.sortOrder),
          (row) => OrderingTerm.asc(row.name),
        ]))
      .get();

  Future<void> upsertProfile({
    required String id,
    required String name,
    required int sortOrder,
  }) {
    return into(unifiedProfiles).insertOnConflictUpdate(
      UnifiedProfilesCompanion.insert(
        id: id,
        name: name,
        sortOrder: sortOrder,
      ),
    );
  }

  Future<int> deleteProfile(String profileId) =>
      (delete(unifiedProfiles)..where((row) => row.id.equals(profileId))).go();

  Future<String?> readActiveProfileId() async {
    final row = await (select(unifiedAppState)
          ..where((row) => row.id.equals(_appStateRowId)))
        .getSingleOrNull();
    return row?.activeProfileId;
  }

  Future<void> setActiveProfileId(String? profileId) {
    return into(unifiedAppState).insertOnConflictUpdate(
      UnifiedAppStateCompanion.insert(
        id: const Value(_appStateRowId),
        activeProfileId: Value(profileId),
      ),
    );
  }

  Future<Object?> readSetting(String key) async {
    final row = await (select(unifiedAppSettings)
          ..where((row) => row.key.equals(key)))
        .getSingleOrNull();
    if (row == null) return null;
    return _decodeSetting(row.valueType, row.value);
  }

  Future<Map<String, Object?>> readSettings() async {
    final rows = await select(unifiedAppSettings).get();
    return {
      for (final row in rows) row.key: _decodeSetting(row.valueType, row.value),
    };
  }

  Future<void> writeSetting(String key, Object? value) async {
    if (value == null) {
      await (delete(unifiedAppSettings)..where((row) => row.key.equals(key)))
          .go();
      return;
    }
    final encoded = _encodeSetting(value);
    await into(unifiedAppSettings).insertOnConflictUpdate(
      UnifiedAppSettingsCompanion.insert(
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
    return into(unifiedTrades).insert(
      UnifiedTradesCompanion.insert(
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

  Future<List<UnifiedTrade>> readTrades(String profileId) =>
      (select(unifiedTrades)
            ..where((row) => row.profileId.equals(profileId))
            ..orderBy([(row) => OrderingTerm.asc(row.tradeDate)]))
          .get();

  Future<UnifiedIbkrSetting?> readIbkrSettings(String profileId) =>
      (select(unifiedIbkrSettings)
            ..where((row) => row.profileId.equals(profileId)))
          .getSingleOrNull();

  Future<void> writeIbkrSettings({
    required String profileId,
    required bool enabled,
    required String baseUrl,
    required String token,
  }) {
    return into(unifiedIbkrSettings).insertOnConflictUpdate(
      UnifiedIbkrSettingsCompanion.insert(
        profileId: profileId,
        enabled: Value(enabled),
        baseUrl: Value(baseUrl),
        token: Value(token),
      ),
    );
  }

  Future<UnifiedIbkrCacheEntry?> readIbkrCache(
    String profileId,
    String kind,
    String cacheKey,
  ) {
    return (select(unifiedIbkrCacheEntries)
          ..where(
            (row) =>
                row.profileId.equals(profileId) &
                row.kind.equals(kind) &
                row.cacheKey.equals(cacheKey),
          ))
        .getSingleOrNull();
  }

  Future<void> writeIbkrCache({
    required String profileId,
    required String kind,
    required String cacheKey,
    required String payloadJson,
    required DateTime cachedAt,
  }) {
    return into(unifiedIbkrCacheEntries).insertOnConflictUpdate(
      UnifiedIbkrCacheEntriesCompanion.insert(
        profileId: profileId,
        kind: kind,
        cacheKey: cacheKey,
        payloadJson: payloadJson,
        cachedAt: cachedAt,
      ),
    );
  }

  Future<int> deleteIbkrCache(String profileId, {String? kind}) {
    final statement = delete(unifiedIbkrCacheEntries)
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
    return into(unifiedCandles).insertOnConflictUpdate(
      UnifiedCandlesCompanion.insert(
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

  Future<List<UnifiedCandle>> readCandles(
    String symbol, {
    DateTime? from,
    DateTime? to,
  }) {
    final query = select(unifiedCandles)
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

  Future<UnifiedSymbolMetadataData?> readSymbolMetadata(String symbol) =>
      (select(unifiedSymbolMetadata)..where((row) => row.symbol.equals(symbol)))
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
    return into(unifiedSymbolMetadata).insertOnConflictUpdate(
      UnifiedSymbolMetadataCompanion.insert(
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
