import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:market_monk/backup_archive.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/unified_database.dart';
import 'package:market_monk/unified_legacy_source.dart';
import 'package:path/path.dart' as p;

/// Portable backup/restore for the single MarketMonk database.
///
/// Current backups contain one SQLite payload created with VACUUM INTO so WAL
/// commits and all tables come from the same SQLite snapshot. Legacy multi-file
/// archives are converted to the unified schema before touching live data.
class UnifiedBackupStore {
  UnifiedBackupStore(this.database);

  final UnifiedDatabase database;

  Future<File> snapshotDatabase(File target) async {
    if (await target.exists()) await target.delete();
    await target.parent.create(recursive: true);
    await database.customStatement('VACUUM INTO ?', [target.path]);
    await _validateUnifiedFile(target);
    return target;
  }

  Future<File> exportArchive(Directory workingDirectory) async {
    final snapshotDirectory = await workingDirectory.createTemp(
      'unified-snapshot-',
    );
    try {
      final snapshot = await snapshotDatabase(
        File(p.join(snapshotDirectory.path, 'market-monk.unified.sqlite')),
      );

      final source = UnifiedDatabase.connect(NativeDatabase(snapshot));
      try {
        final profiles = await source.readProfiles();
        if (profiles.isEmpty) {
          throw const FormatException('Unified backup has no profiles');
        }
        final activeProfileId = await source.readActiveProfileId();
        String? activeProfile;
        for (final profile in profiles) {
          if (profile.id == activeProfileId) {
            activeProfile = profile.name;
            break;
          }
        }
        if (activeProfile == null) {
          throw const FormatException(
            'Unified backup active profile does not exist',
          );
        }

        final settings = Map<String, Object?>.from(await source.readSettings())
          ..remove(UnifiedDatabase.legacyMigrationCompleteKey);

        return await buildMarketMonkBackupArchive(
          workingDirectory: workingDirectory,
          logical: MarketMonkLogicalBackup(
            profiles: profiles.map((profile) => profile.name).toList(),
            activeProfile: activeProfile,
            settings: settings,
          ),
          storage: MarketMonkBackupStorage.unifiedDatabase(snapshot),
        );
      } finally {
        await source.close();
      }
    } finally {
      if (await snapshotDirectory.exists()) {
        await snapshotDirectory.delete(recursive: true);
      }
    }
  }

  Future<void> restoreBackup(
    MarketMonkBackupContents restored,
    Directory workingDirectory,
  ) async {
    final source = await _materializeUnifiedSource(restored, workingDirectory);
    await restoreUnifiedFile(source);
  }

  /// Atomically replaces every unified table while preserving stored row ids.
  Future<void> restoreUnifiedFile(File sourceFile) async {
    await _validateUnifiedFile(sourceFile);
    final source = UnifiedDatabase.connect(NativeDatabase(sourceFile));
    try {
      final snapshot = await _readSnapshot(source);
      _validateSnapshot(snapshot);

      await database.transaction(() async {
        await database.delete(database.unifiedIbkrCacheEntries).go();
        await database.delete(database.unifiedIbkrSettings).go();
        await database.delete(database.unifiedTrades).go();
        await database.delete(database.unifiedAppState).go();
        await database.delete(database.unifiedAppSettings).go();
        await database.delete(database.unifiedCandles).go();
        await database.delete(database.unifiedSymbolMetadata).go();
        await database.delete(database.unifiedProfiles).go();

        await database.batch((batch) {
          batch.insertAll(database.unifiedProfiles, snapshot.profiles);
          batch.insertAll(database.unifiedAppSettings, snapshot.settings);
          batch.insertAll(database.unifiedCandles, snapshot.candles);
          batch.insertAll(
            database.unifiedSymbolMetadata,
            snapshot.symbolMetadata,
          );
          batch.insertAll(database.unifiedIbkrSettings, snapshot.ibkrSettings);
          batch.insertAll(
            database.unifiedIbkrCacheEntries,
            snapshot.ibkrCaches,
          );
          batch.insertAll(database.unifiedTrades, snapshot.trades);
          batch.insertAll(database.unifiedAppState, snapshot.appState);
        });
      });
    } finally {
      await source.close();
    }
  }

  /// Imports an old per-profile SQLite file into an existing unified profile.
  Future<void> importLegacyProfile({
    required File sourceFile,
    required String profileId,
  }) async {
    await validateMarketMonkSqliteFile(sourceFile);
    final profile = await _readLegacyProfile('', sourceFile);

    await database.transaction(() async {
      await (database.delete(
        database.unifiedIbkrCacheEntries,
      )..where((row) => row.profileId.equals(profileId)))
          .go();
      await (database.delete(
        database.unifiedIbkrSettings,
      )..where((row) => row.profileId.equals(profileId)))
          .go();
      await (database.delete(
        database.unifiedTrades,
      )..where((row) => row.profileId.equals(profileId)))
          .go();

      for (final trade in profile.trades) {
        await database.addTrade(
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

      final ibkr = profile.ibkrSettings;
      if (ibkr != null) {
        await database.writeIbkrSettings(
          profileId: profileId,
          enabled: ibkr.enabled,
          baseUrl: ibkr.baseUrl,
          token: ibkr.token,
        );
      }
      for (final cache in profile.ibkrCacheEntries) {
        await database.writeIbkrCache(
          profileId: profileId,
          kind: cache.kind,
          cacheKey: cache.cacheKey,
          payloadJson: cache.payloadJson,
          cachedAt: cache.cachedAt,
        );
      }
      for (final candle in profile.candles) {
        await database.upsertCandle(
          symbol: candle.symbol,
          date: candle.date,
          open: candle.open,
          high: candle.high,
          low: candle.low,
          close: candle.close,
          volume: candle.volume,
          adjClose: candle.adjClose,
        );
      }
    });
  }

  Future<File> _materializeUnifiedSource(
    MarketMonkBackupContents restored,
    Directory workingDirectory,
  ) async {
    if (restored.storage.layout ==
        MarketMonkBackupStorageLayout.unifiedDatabase) {
      return restored.storage.unifiedDatabase!;
    }

    final snapshot = LegacyUnifiedSnapshot(
      settings: restored.logical.settings,
      profiles: [
        for (final name in restored.logical.profiles)
          await _readLegacyProfile(
            name,
            restored.storage.profileDatabases[name],
            legacySettings: restored.logical.settings,
          ),
      ],
      activeProfileName: restored.logical.activeProfile,
    );

    final converted = File(
      p.join(workingDirectory.path, 'converted-unified.sqlite'),
    );
    if (await converted.exists()) await converted.delete();

    final target = UnifiedDatabase.connect(NativeDatabase(converted));
    try {
      await target.migrateLegacySnapshot(snapshot);
    } finally {
      await target.close();
    }
    await _validateUnifiedFile(converted);
    return converted;
  }

  Future<LegacyProfileSnapshot> _readLegacyProfile(
    String name,
    File? file, {
    Map<String, Object?> legacySettings = const {},
  }) async {
    final fallbackSettings = _legacyIbkrSettings(legacySettings, name);
    final fallbackCaches = _legacyIbkrCaches(legacySettings, name);
    if (file == null) {
      return LegacyProfileSnapshot(
        name: name,
        ibkrSettings: fallbackSettings,
        ibkrCacheEntries: fallbackCaches,
      );
    }

    await validateMarketMonkSqliteFile(file);
    final source = Database.connect(NativeDatabase(file));
    try {
      await source.customSelect('PRAGMA user_version').getSingle();
      final trades = await source.select(source.trades).get();
      final ibkrSettings = await source.readIbkrProfileSettings();
      final ibkrCaches = await source.select(source.ibkrCacheEntries).get();
      final candles = await source.select(source.candles).get();
      final existingCacheKeys = {
        for (final cache in ibkrCaches)
          _cacheIdentity(cache.kind, cache.cacheKey),
      };
      return LegacyProfileSnapshot(
        name: name,
        trades: [
          for (final trade in trades)
            LegacyTradeSnapshot(
              symbol: trade.symbol,
              name: trade.name,
              quantity: trade.quantity,
              price: trade.price,
              tradeType: trade.tradeType,
              tradeDate: trade.tradeDate,
              realizedPL: trade.realizedPL,
              commission: trade.commission,
            ),
        ],
        ibkrSettings: ibkrSettings == null
            ? fallbackSettings
            : LegacyIbkrSettingsSnapshot(
                enabled: ibkrSettings.enabled,
                baseUrl: ibkrSettings.baseUrl,
                token: ibkrSettings.token,
              ),
        ibkrCacheEntries: [
          for (final cache in ibkrCaches)
            LegacyIbkrCacheSnapshot(
              kind: cache.kind,
              cacheKey: cache.cacheKey,
              payloadJson: cache.payloadJson,
              cachedAt: cache.cachedAt,
            ),
          for (final cache in fallbackCaches)
            if (!existingCacheKeys.contains(
              _cacheIdentity(cache.kind, cache.cacheKey),
            ))
              cache,
        ],
        candles: [
          for (final candle in candles)
            LegacyCandleSnapshot(
              symbol: candle.symbol,
              date: candle.date,
              open: candle.open,
              high: candle.high,
              low: candle.low,
              close: candle.close,
              volume: candle.volume,
              adjClose: candle.adjClose,
            ),
        ],
      );
    } finally {
      await source.close();
    }
  }

  String _cacheIdentity(String kind, String cacheKey) => '$kind $cacheKey';

  LegacyIbkrSettingsSnapshot? _legacyIbkrSettings(
    Map<String, Object?> settings,
    String profileName,
  ) {
    final configs = _decodeLegacyMap(settings['ibkrAccountConfigs']);
    final raw = configs[profileName];
    if (raw is! Map<String, dynamic>) return null;
    return LegacyIbkrSettingsSnapshot(
      enabled: raw['enabled'] == true,
      baseUrl: raw['baseUrl'] as String? ?? '',
      token: raw['token'] as String? ?? '',
    );
  }

  List<LegacyIbkrCacheSnapshot> _legacyIbkrCaches(
    Map<String, Object?> settings,
    String profileName,
  ) {
    final result = <LegacyIbkrCacheSnapshot>[];

    final portfolio = _decodeLegacyMap(
      settings['portfolioCacheV1'],
      discardMalformed: true,
    )[profileName];
    if (portfolio is Map<String, dynamic>) {
      final cachedAt = _legacyCachedAt(portfolio);
      if (cachedAt != null) {
        result.add(
          LegacyIbkrCacheSnapshot(
            kind: 'portfolio',
            cacheKey: 'snapshot',
            payloadJson: jsonEncode(portfolio),
            cachedAt: cachedAt,
          ),
        );
      }
    }

    final performance = _decodeLegacyMap(
      settings['ibkrPerformanceCacheV1'],
      discardMalformed: true,
    )[profileName];
    if (performance is Map<String, dynamic>) {
      for (final entry in performance.entries) {
        final value = entry.value;
        if (value is! Map<String, dynamic>) continue;
        final cachedAt = _legacyCachedAt(value);
        if (cachedAt == null) continue;
        result.add(
          LegacyIbkrCacheSnapshot(
            kind: 'performance',
            cacheKey: entry.key,
            payloadJson: jsonEncode(value),
            cachedAt: cachedAt,
          ),
        );
      }
    }

    return result;
  }

  Map<String, dynamic> _decodeLegacyMap(
    Object? raw, {
    bool discardMalformed = false,
  }) {
    if (raw == null || raw == '') return const {};
    if (raw is Map<String, dynamic>) return raw;
    if (raw is! String) {
      if (discardMalformed) return const {};
      throw const FormatException('Expected a legacy JSON object');
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      throw const FormatException('Expected a legacy JSON object');
    } on FormatException {
      if (discardMalformed) return const {};
      rethrow;
    }
  }

  DateTime? _legacyCachedAt(Map<String, dynamic> value) {
    final raw = value['cachedAt'];
    return raw is String ? DateTime.tryParse(raw) : null;
  }

  Future<_UnifiedSnapshot> _readSnapshot(UnifiedDatabase source) async {
    return _UnifiedSnapshot(
      profiles: await source.select(source.unifiedProfiles).get(),
      appState: await source.select(source.unifiedAppState).get(),
      settings: await source.select(source.unifiedAppSettings).get(),
      trades: await source.select(source.unifiedTrades).get(),
      ibkrSettings: await source.select(source.unifiedIbkrSettings).get(),
      ibkrCaches: await source.select(source.unifiedIbkrCacheEntries).get(),
      candles: await source.select(source.unifiedCandles).get(),
      symbolMetadata: await source.select(source.unifiedSymbolMetadata).get(),
    );
  }

  void _validateSnapshot(_UnifiedSnapshot snapshot) {
    if (snapshot.profiles.isEmpty) {
      throw const FormatException('Unified backup has no profiles');
    }
    final profileIds = snapshot.profiles.map((profile) => profile.id).toSet();
    for (final state in snapshot.appState) {
      final active = state.activeProfileId;
      if (active != null && !profileIds.contains(active)) {
        throw const FormatException(
          'Unified backup references a missing active profile',
        );
      }
    }
  }

  Future<void> _validateUnifiedFile(File file) async {
    await validateMarketMonkSqliteFile(file);
    final source = UnifiedDatabase.connect(NativeDatabase(file));
    try {
      final integrity =
          await source.customSelect('PRAGMA integrity_check').get();
      if (integrity.length != 1 ||
          integrity.single.data.values.single.toString().toLowerCase() !=
              'ok') {
        throw const FormatException('Unified database integrity check failed');
      }
      final snapshot = await _readSnapshot(source);
      _validateSnapshot(snapshot);
    } finally {
      await source.close();
    }
  }
}

class _UnifiedSnapshot {
  const _UnifiedSnapshot({
    required this.profiles,
    required this.appState,
    required this.settings,
    required this.trades,
    required this.ibkrSettings,
    required this.ibkrCaches,
    required this.candles,
    required this.symbolMetadata,
  });

  final List<UnifiedProfile> profiles;
  final List<UnifiedAppStateData> appState;
  final List<UnifiedAppSetting> settings;
  final List<UnifiedTrade> trades;
  final List<UnifiedIbkrSetting> ibkrSettings;
  final List<UnifiedIbkrCacheEntry> ibkrCaches;
  final List<UnifiedCandle> candles;
  final List<UnifiedSymbolMetadataData> symbolMetadata;
}
