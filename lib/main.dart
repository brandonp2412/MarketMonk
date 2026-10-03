import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:market_monk/adaptive_layout.dart';
import 'package:market_monk/backup_archive.dart';
import 'package:market_monk/background_network_coordinator.dart';
import 'package:market_monk/bottom_nav.dart';
import 'package:market_monk/charts_page.dart';
import 'package:market_monk/crash_logger.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/holdings_page.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/l10n/app_localizations.dart';
import 'package:market_monk/logging.dart';
import 'package:market_monk/market_data_store.dart';
import 'package:market_monk/legacy_preferences_migration.dart';
import 'package:market_monk/portfolio_page.dart';
import 'package:market_monk/profile_data_repository.dart';
import 'package:market_monk/settings_page.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/utils.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:market_monk/sqlite_settings.dart';
import 'package:market_monk/unified_legacy_source.dart';

Future<void> main() async {
  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await CrashLogger.install(fileName: 'marketmonk-crash.log');
      installTalkerErrorHandlers();
      talker.info('Starting Market Monk');

      await SqliteSettings.getInstance();
      await migrateLegacyMarketDataOnStartup(defaultDatabase: db);
      final settings = SettingsState();
      final accounts = AccountManager();
      await Future.wait([settings.initialized, accounts.init()]);
      talker.info('Account manager initialized');

      runApp(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settings),
            ChangeNotifierProvider.value(value: accounts),
          ],
          child: const MyApp(),
        ),
      );
    },
    (error, stack) {
      CrashLogger.instance?.record(error, stack, context: 'zone');
      talker.handle(error, stack, 'Uncaught zone error');
    },
  );
}

Database db = Database();

class CachedPortfolioData {
  final List<Position> positions;
  final IbkrAccountValue? netLiquidation;
  final double? netLiquidationUsd;
  final DateTime cachedAt;

  const CachedPortfolioData({
    required this.positions,
    required this.netLiquidation,
    this.netLiquidationUsd,
    required this.cachedAt,
  });

  Map<String, dynamic> toJson() => {
        'positions': positions
            .map(
              (position) => {
                'symbol': position.symbol,
                'name': position.name,
                'nativeCurrency': position.nativeCurrency,
                'netShares': position.netShares,
                'avgCost': position.avgCost,
                'currentPrice': position.currentPrice,
                'firstBuyDate': position.firstBuyDate.toIso8601String(),
                'lastBuyDate': position.lastBuyDate.toIso8601String(),
                'brokerMarketValue': position.brokerMarketValue,
                'brokerUnrealizedPL': position.brokerUnrealizedPL,
                'brokerRealizedPL': position.brokerRealizedPL,
              },
            )
            .toList(),
        'netLiquidation': netLiquidation == null
            ? null
            : {
                'value': netLiquidation!.value,
                'currency': netLiquidation!.currency,
              },
        'netLiquidationUsd': netLiquidationUsd,
        'cachedAt': cachedAt.toIso8601String(),
      };

  factory CachedPortfolioData.fromJson(Map<String, dynamic> json) {
    final rawNetLiquidation = json['netLiquidation'];
    return CachedPortfolioData(
      positions: (json['positions'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(
            (position) => Position(
              symbol: position['symbol'] as String? ?? '',
              name: position['name'] as String? ?? '',
              nativeCurrency: position['nativeCurrency'] as String? ?? 'USD',
              netShares: (position['netShares'] as num?)?.toDouble() ?? 0,
              avgCost: (position['avgCost'] as num?)?.toDouble() ?? 0,
              currentPrice: (position['currentPrice'] as num?)?.toDouble() ?? 0,
              firstBuyDate: DateTime.tryParse(
                    position['firstBuyDate'] as String? ?? '',
                  ) ??
                  DateTime.fromMillisecondsSinceEpoch(0),
              lastBuyDate:
                  DateTime.tryParse(position['lastBuyDate'] as String? ?? '') ??
                      DateTime.fromMillisecondsSinceEpoch(0),
              brokerMarketValue:
                  (position['brokerMarketValue'] as num?)?.toDouble(),
              brokerUnrealizedPL:
                  (position['brokerUnrealizedPL'] as num?)?.toDouble(),
              brokerRealizedPL:
                  (position['brokerRealizedPL'] as num?)?.toDouble(),
            ),
          )
          .where((position) => position.symbol.isNotEmpty)
          .toList(),
      netLiquidation: rawNetLiquidation is Map<String, dynamic>
          ? IbkrAccountValue(
              value: (rawNetLiquidation['value'] as num?)?.toDouble() ?? 0,
              currency: rawNetLiquidation['currency'] as String? ?? '',
            )
          : null,
      netLiquidationUsd: (json['netLiquidationUsd'] as num?)?.toDouble(),
      cachedAt: DateTime.tryParse(json['cachedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class CachedIbkrPerformanceData {
  final IbkrPerformanceSeries series;
  final DateTime cachedAt;

  const CachedIbkrPerformanceData({
    required this.series,
    required this.cachedAt,
  });

  Map<String, dynamic> toJson() => {
        'series': series.toJson(),
        'cachedAt': cachedAt.toIso8601String(),
      };

  factory CachedIbkrPerformanceData.fromJson(Map<String, dynamic> json) =>
      CachedIbkrPerformanceData(
        series: IbkrPerformanceSeries.fromJson(
          json['series'] as Map<String, dynamic>,
        ),
        cachedAt: DateTime.tryParse(json['cachedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// Manages named portfolio accounts backed by separate SQLite files.
/// Switching accounts has zero per-query overhead — only the DB file changes.
class AccountManager extends ChangeNotifier {
  List<String> accounts = ['Default'];
  String activeAccount = 'Default';
  int ibkrRefreshVersion = 0;
  final Map<String, IbkrAccountConfig> _ibkrConfigs = {};
  static const ibkrPortfolioCacheMaxAge =
      BackgroundNetworkCoordinator.ibkrPortfolioFreshness;
  static const ibkrPerformanceCacheMaxAge =
      BackgroundNetworkCoordinator.ibkrPerformanceFreshness;

  final Map<String, CachedPortfolioData> _portfolioCache = {};
  final Map<String, Map<String, CachedIbkrPerformanceData>>
      _ibkrPerformanceCache = {};

  /// Loads the profile registry, credentials and caches from SQLite.
  Future<void> init() async {
    final prefs = await SqliteSettings.getInstance();
    _ibkrConfigs.clear();
    _portfolioCache.clear();
    _ibkrPerformanceCache.clear();
    accounts = prefs.getStringList('accounts') ?? ['Default'];
    if (!accounts.contains('Default')) {
      accounts = ['Default', ...accounts];
      await prefs.setStringList('accounts', accounts);
    }
    activeAccount = prefs.getString('activeAccount') ?? 'Default';
    if (!accounts.contains(activeAccount)) {
      talker.warning(
        'Saved active portfolio account no longer exists; using Default',
      );
      activeAccount = 'Default';
      await prefs.setString('activeAccount', activeAccount);
    }
    for (final account in accounts) {
      await _loadProfileState(account);
    }

    if (activeAccount != 'Default') {
      final previousDb = db;
      db = Database('market-monk-$activeAccount');
      await previousDb.close();
    }
    talker.info('Loaded ${accounts.length} portfolio accounts');
  }

  Future<void> _loadProfileState(String account) async {
    _ibkrConfigs.remove(account);
    _portfolioCache.remove(account);
    _ibkrPerformanceCache.remove(account);
    await _withProfileDatabase(account, (database) async {
      final config = await database.readIbkrProfileSettings();
      if (config != null) {
        _ibkrConfigs[account] = IbkrAccountConfig(
          enabled: config.enabled,
          baseUrl: config.baseUrl,
          token: config.token,
        );
      }
      final entries = await database.select(database.ibkrCacheEntries).get();
      for (final entry in entries) {
        try {
          final value = json.decode(entry.payloadJson) as Map<String, dynamic>;
          if (entry.kind == 'portfolio' && entry.cacheKey == 'snapshot') {
            _portfolioCache[account] = CachedPortfolioData.fromJson(value);
          } else if (entry.kind == 'performance') {
            _ibkrPerformanceCache.putIfAbsent(
              account,
              () => {},
            )[entry.cacheKey] = CachedIbkrPerformanceData.fromJson(
              value,
            );
          }
        } catch (error, stack) {
          talker.handle(error, stack, 'Skipped malformed SQLite IBKR cache');
        }
      }
    });
  }

  /// Opens profile connections independently so account switches cannot close a write.
  AccountManager({ProfileDatabaseFactory? profileDatabaseFactory})
      : _profileDatabaseFactory =
            profileDatabaseFactory ?? _openProfileDatabase;

  final ProfileDatabaseFactory _profileDatabaseFactory;
  Future<void>? _pendingStorage;

  Future<T> _serializeStorage<T>(Future<T> Function() operation) {
    final previous = _pendingStorage;
    final result = previous == null
        ? Future<T>.sync(operation)
        : previous.then((_) => operation());
    late final Future<void> pending;
    void release() {
      if (identical(_pendingStorage, pending)) _pendingStorage = null;
    }

    pending = result.then<void>(
      (_) => release(),
      onError: (Object _, StackTrace __) => release(),
    );
    _pendingStorage = pending;
    return result;
  }

  static Database _openProfileDatabase(String name) =>
      Database(name == 'Default' ? 'market-monk' : 'market-monk-$name');

  Future<void> _closeCurrentDatabaseQuietly() async {
    try {
      await db.close();
    } catch (_) {}
  }

  Future<T> _withProfileDatabase<T>(
    String name,
    Future<T> Function(Database database) operation,
  ) async {
    final database = _profileDatabaseFactory(name);
    try {
      return await operation(database);
    } finally {
      await database.close();
    }
  }

  /// Returns the IBKR connection associated with [name], or the active account.
  IbkrAccountConfig ibkrConfigFor([String? name]) =>
      _ibkrConfigs[name ?? activeAccount] ?? const IbkrAccountConfig();

  CachedPortfolioData? portfolioCacheFor([String? name]) =>
      _portfolioCache[name ?? activeAccount];

  bool isPortfolioCacheFresh(
    String name, {
    Duration maxAge = ibkrPortfolioCacheMaxAge,
  }) {
    final cached = _portfolioCache[name];
    return cached != null &&
        backgroundNetworkCoordinator.isTimestampFresh(cached.cachedAt, maxAge);
  }

  IbkrPerformanceSeries? ibkrPerformanceCacheFor(String name, String period) =>
      _ibkrPerformanceCache[name]?[period]?.series;

  bool isIbkrPerformanceCacheFresh(
    String name,
    String period, {
    Duration maxAge = ibkrPerformanceCacheMaxAge,
  }) {
    final cached = _ibkrPerformanceCache[name]?[period];
    return cached != null &&
        backgroundNetworkCoordinator.isTimestampFresh(cached.cachedAt, maxAge);
  }

  /// Persists a performance series in its owning profile database.
  Future<void> cacheIbkrPerformance(
    String name,
    IbkrPerformanceSeries series,
  ) =>
      _serializeStorage(() => _cacheIbkrPerformance(name, series));

  Future<void> _cacheIbkrPerformance(
    String name,
    IbkrPerformanceSeries series,
  ) async {
    if (!accounts.contains(name)) return;
    final cached = CachedIbkrPerformanceData(
      series: series,
      cachedAt: DateTime.now(),
    );
    await _withProfileDatabase(
      name,
      (database) => database.writeIbkrCache(
        kind: 'performance',
        cacheKey: series.period,
        payloadJson: json.encode(cached.toJson()),
        cachedAt: cached.cachedAt,
      ),
    );
    _ibkrPerformanceCache.putIfAbsent(name, () => {})[series.period] = cached;
  }

  /// Persists a portfolio snapshot in its owning profile database.
  Future<void> cachePortfolio(
    String name,
    List<Position> positions,
    IbkrAccountValue? netLiquidation, {
    double? netLiquidationUsd,
  }) =>
      _serializeStorage(
        () => _cachePortfolio(
          name,
          positions,
          netLiquidation,
          netLiquidationUsd: netLiquidationUsd,
        ),
      );

  Future<void> _cachePortfolio(
    String name,
    List<Position> positions,
    IbkrAccountValue? netLiquidation, {
    double? netLiquidationUsd,
  }) async {
    if (!accounts.contains(name)) return;
    final cached = CachedPortfolioData(
      positions: List.unmodifiable(positions),
      netLiquidation: netLiquidation,
      netLiquidationUsd: netLiquidationUsd,
      cachedAt: DateTime.now(),
    );
    await _withProfileDatabase(
      name,
      (database) => database.writeIbkrCache(
        kind: 'portfolio',
        cacheKey: 'snapshot',
        payloadJson: json.encode(cached.toJson()),
        cachedAt: cached.cachedAt,
      ),
    );
    _portfolioCache[name] = cached;
  }

  /// Saves the connection and invalidates its caches in one SQLite transaction.
  Future<void> setIbkrConfig(String name, IbkrAccountConfig config) =>
      _serializeStorage(() => _setIbkrConfig(name, config));

  Future<void> _setIbkrConfig(String name, IbkrAccountConfig config) async {
    if (!accounts.contains(name)) return;
    final changed = _ibkrConfigs[name] != config;
    await _withProfileDatabase(
      name,
      (database) => database.transaction(() async {
        await database.writeIbkrProfileSettings(
          enabled: config.enabled,
          baseUrl: config.baseUrl,
          token: config.token,
        );
        if (changed) await database.deleteIbkrCache();
      }),
    );
    _ibkrConfigs[name] = config;
    if (changed) {
      _portfolioCache.remove(name);
      _ibkrPerformanceCache.remove(name);
    }
    ibkrRefreshVersion++;
    notifyListeners();
  }

  /// Signals kept-alive portfolio pages to fetch a fresh IBKR snapshot.
  void requestIbkrRefresh() {
    ibkrRefreshVersion++;
    notifyListeners();
  }

  /// Switches the active portfolio and persists the selection in SQLite.
  Future<void> switchAccount(String name) =>
      _serializeStorage(() => _switchAccount(name));

  Future<void> _switchAccount(String name) async {
    if (name == activeAccount) return;
    if (!accounts.contains(name)) {
      talker.warning('Ignored switch to an unknown portfolio account');
      return;
    }

    final previousDb = db;
    activeAccount = name;
    db = name == 'Default' ? Database() : Database('market-monk-$name');
    clearAllSyncCache();
    notifyListeners();
    talker.info('Switched active portfolio account');

    final persistFuture = SqliteSettings.getInstance().then((prefs) async {
      if (activeAccount == name) {
        await prefs.setString('activeAccount', name);
      }
    });
    await Future.wait([previousDb.close(), persistFuture]);
  }

  /// Replaces the active profile, reloading its credentials and cached state.
  Future<void> importDatabase(File sourceFile) =>
      _serializeStorage(() => _importDatabase(sourceFile));

  Future<void> _importDatabase(File sourceFile) async {
    final dbName = activeAccount == 'Default'
        ? 'market-monk'
        : 'market-monk-$activeAccount';
    final dbFolder = await getApplicationSupportDirectory();
    final targetFile = File(p.join(dbFolder.path, '$dbName.sqlite'));
    final stagedFile = File('${targetFile.path}.importing');
    final backupFile = File('${targetFile.path}.pre-import');
    final sourcePath = p.normalize(p.absolute(sourceFile.path));
    final targetPath = p.normalize(p.absolute(targetFile.path));
    final sourceIsTarget = sourcePath == targetPath;

    if (!sourceIsTarget) {
      if (await stagedFile.exists()) await stagedFile.delete();
      await sourceFile.copy(stagedFile.path);
    }

    await db.close();

    try {
      if (await backupFile.exists()) await backupFile.delete();
      if (await targetFile.exists()) {
        await targetFile.copy(backupFile.path);
      }

      if (!sourceIsTarget) {
        await stagedFile.copy(targetFile.path);
      }

      for (final suffix in ['-wal', '-shm']) {
        final sidecar = File('${targetFile.path}$suffix');
        if (await sidecar.exists()) await sidecar.delete();
      }

      db = Database(dbName);
      await db.customSelect('PRAGMA user_version').getSingle();
      await _loadProfileState(activeAccount);

      clearAllSyncCache();
      notifyListeners();
      talker.info('Imported database for active portfolio account');

      if (await backupFile.exists()) await backupFile.delete();
    } catch (error, stackTrace) {
      await _closeCurrentDatabaseQuietly();

      for (final suffix in ['-wal', '-shm']) {
        final sidecar = File('${targetFile.path}$suffix');
        if (await sidecar.exists()) await sidecar.delete();
      }
      if (await backupFile.exists()) {
        await backupFile.copy(targetFile.path);
      }
      db = Database(dbName);
      await _loadProfileState(activeAccount);
      talker.handle(error, stackTrace, 'Failed to import portfolio database');
      rethrow;
    } finally {
      if (await stagedFile.exists()) await stagedFile.delete();
      if (await backupFile.exists()) await backupFile.delete();
    }
  }

  /// Snapshots every profile and exports the SQLite application settings.
  Future<File> exportBackup(Directory workingDirectory) =>
      _serializeStorage(() => _exportBackup(workingDirectory));

  Future<File> _exportBackup(Directory workingDirectory) async {
    final snapshotDirectory = await workingDirectory.createTemp(
      'sqlite-snapshot-',
    );
    final prefs = await SqliteSettings.getInstance();
    await prefs.flush();

    final unified = profileDataDatabase;
    final globalCandles = await marketDataDatabase
        .select(marketDataDatabase.unifiedCandles)
        .get();

    try {
      final profileDatabases = <String, File>{};
      for (final account in accounts) {
        final target = p.join(
          snapshotDirectory.path,
          databaseFileNameForAccount(account),
        );
        await _withProfileDatabase(account, (database) async {
          // VACUUM INTO includes committed WAL pages in a consistent snapshot.
          // https://www.sqlite.org/lang_vacuum.html#vacuum_with_an_into_clause
          await database.customStatement('VACUUM INTO ?', [target]);
        });

        // During the unified cutover, profile-local SQLite still owns IBKR
        // configuration/cache while trades and candles already live in the
        // unified store. Hydrate the portable snapshot with the authoritative
        // unified rows so a backup cannot silently omit post-cutover data.
        final snapshot = Database.connect(NativeDatabase(File(target)));
        try {
          final unifiedProfile = await unified.readProfileByName(account);
          if (unifiedProfile != null) {
            final trades = await unified.readTrades(unifiedProfile.id);
            await snapshot.transaction(() async {
              await snapshot.delete(snapshot.trades).go();
              for (final trade in trades) {
                await snapshot.into(snapshot.trades).insert(
                      TradesCompanion.insert(
                        symbol: trade.symbol,
                        name: trade.name,
                        quantity: trade.quantity,
                        price: trade.price,
                        tradeType: trade.tradeType,
                        tradeDate: trade.tradeDate,
                        realizedPL: Value(trade.realizedPL),
                        commission: Value(trade.commission),
                      ),
                    );
              }
            });
          }

          await snapshot.delete(snapshot.candles).go();
          if (account == 'Default') {
            for (final candle in globalCandles) {
              await snapshot.into(snapshot.candles).insert(
                    CandlesCompanion.insert(
                      symbol: candle.symbol,
                      date: candle.date,
                      open: Value(candle.open),
                      high: Value(candle.high),
                      low: Value(candle.low),
                      close: Value(candle.close),
                      volume: Value(candle.volume),
                      adjClose: Value(candle.adjClose),
                    ),
                  );
            }
          }
        } finally {
          await snapshot.close();
        }

        profileDatabases[account] = File(target);
      }
      return await buildMarketMonkBackupArchive(
        workingDirectory: workingDirectory,
        logical: MarketMonkLogicalBackup(
          profiles: List<String>.of(accounts),
          activeProfile: activeAccount,
          settings: prefs.snapshot(),
        ),
        storage: MarketMonkBackupStorage.profileDatabases(profileDatabases),
      );
    } finally {
      await snapshotDirectory.delete(recursive: true);
    }
  }

  /// Restores current or legacy backups, rolling back on restore errors.
  Future<void> importBackup(File sourceFile) =>
      _serializeStorage(() => _importBackup(sourceFile));

  Future<void> _importBackup(File sourceFile) async {
    final temporaryDirectory = await getTemporaryDirectory();
    final workingDirectory = await temporaryDirectory.createTemp(
      'market-monk-restore-',
    );
    try {
      final restored = await extractMarketMonkBackupArchive(
        archiveFile: sourceFile,
        workingDirectory: workingDirectory,
      );
      final rollbackDirectory = Directory(
        p.join(workingDirectory.path, 'rollback'),
      );
      final databaseDirectory = await getApplicationSupportDirectory();
      final prefs = await SqliteSettings.getInstance();
      await _applyRestoredBackup(
        restored,
        rollbackDirectory: rollbackDirectory,
        databaseDirectory: databaseDirectory,
        prefs: prefs,
        previousPreferences: prefs.snapshot(),
        previousAccounts: List<String>.of(accounts),
        previousActiveAccount: activeAccount,
      );
    } finally {
      if (await workingDirectory.exists()) {
        await workingDirectory.delete(recursive: true);
      }
    }
  }

  Future<void> _applyRestoredBackup(
    MarketMonkBackupContents restored, {
    required Directory rollbackDirectory,
    required Directory databaseDirectory,
    required SqliteSettings prefs,
    required Map<String, Object?> previousPreferences,
    required List<String> previousAccounts,
    required String previousActiveAccount,
  }) async {
    if (restored.storage.layout !=
        MarketMonkBackupStorageLayout.profileDatabases) {
      throw UnsupportedError(
        'This Market Monk build cannot apply a unified-database backup yet',
      );
    }

    final logical = restored.logical;
    final profileDatabases = restored.storage.profileDatabases;
    await rollbackDirectory.create();
    final existingFiles = _marketMonkDatabaseFiles(databaseDirectory);
    await db.close();
    var replacementStarted = false;

    try {
      for (final file in existingFiles) {
        await file.copy(p.join(rollbackDirectory.path, p.basename(file.path)));
      }
      replacementStarted = true;
      for (final file in existingFiles) {
        if (await file.exists()) await file.delete();
      }
      for (final entry in profileDatabases.entries) {
        final target = File(
          p.join(databaseDirectory.path, databaseFileNameForAccount(entry.key)),
        );
        await entry.value.copy(target.path);
      }

      await prefs.restore(
        logical.settings,
        logical.profiles,
        logical.activeProfile,
      );
      await seedSqliteFromLegacyValues(
        values: {...logical.settings, 'accounts': logical.profiles},
        appState: prefs.database,
        profileDatabaseFactory: _profileDatabaseFactory,
      );

      db = Database();
      await init();

      // Backup v3 still stores per-profile databases for compatibility. Rebuild
      // the unified store from the restored registry and database payload in one
      // transaction so restored trades/candles cannot diverge from what the UI
      // now reads. A failed rebuild rolls back without touching the prior
      // unified state.
      final restoredSnapshot = await readLegacyUnifiedSnapshot(
        appState: prefs.database,
        openProfileDatabase: (name) async => _profileDatabaseFactory(name),
      );
      await profileDataDatabase.migrateLegacySnapshot(
        restoredSnapshot,
        replaceExisting: true,
      );

      clearAllSyncCache();
      notifyListeners();
      talker.info('Restored full Market Monk backup');
    } catch (error, stackTrace) {
      await _closeCurrentDatabaseQuietly();
      if (replacementStarted) {
        await _restoreRollbackDatabases(rollbackDirectory, databaseDirectory);
      }
      await prefs.restore(
        previousPreferences,
        previousAccounts,
        previousActiveAccount,
      );
      db = Database();
      await init();
      talker.handle(error, stackTrace, 'Failed to restore Market Monk backup');
      rethrow;
    }
  }

  Future<void> _restoreRollbackDatabases(
    Directory rollbackDirectory,
    Directory databaseDirectory,
  ) async {
    for (final file in _marketMonkDatabaseFiles(databaseDirectory)) {
      if (await file.exists()) await file.delete();
    }
    if (!await rollbackDirectory.exists()) return;

    for (final entity in rollbackDirectory.listSync()) {
      if (entity is! File) continue;
      await entity.copy(
        p.join(databaseDirectory.path, p.basename(entity.path)),
      );
    }
  }

  List<File> _marketMonkDatabaseFiles(Directory directory) {
    if (!directory.existsSync()) return const [];
    final pattern = RegExp(r'^market-monk(?:-.+)?.sqlite(?:-(?:wal|shm))?$');
    return directory
        .listSync()
        .whereType<File>()
        .where((file) => pattern.hasMatch(p.basename(file.path)))
        .toList();
  }

  void _validateProfileName(String name) {
    if (name.isEmpty || name.contains('/') || name.contains(r'\')) {
      throw ArgumentError.value(name, 'name', 'Invalid profile name');
    }
  }

  /// Adds a named profile to the persisted registry.
  Future<void> addAccount(String name) =>
      _serializeStorage(() => _addAccount(name));

  Future<void> _addAccount(String name) async {
    if (accounts.contains(name)) return;
    _validateProfileName(name);
    final updated = [...accounts, name];
    final prefs = await SqliteSettings.getInstance();
    await prefs.setProfiles(updated, activeAccount);
    accounts = updated;
    // Defer notification to post-frame so it fires after the current build
    // phase completes. Without this, notifyListeners() fires as a microtask
    // during the dialog's exit-animation frame, marking AccountsPage dirty
    // mid-build and triggering _dependents.isEmpty assertions on the Overlay.
    WidgetsBinding.instance.addPostFrameCallback((_) => notifyListeners());
    talker.info('Added portfolio account');
  }

  /// Moves the profile database and updates its persisted name.
  Future<void> renameAccount(String oldName, String newName) =>
      _serializeStorage(() => _renameAccount(oldName, newName));

  Future<void> _renameAccount(String oldName, String newName) async {
    if (oldName == 'Default' || newName.isEmpty || accounts.contains(newName)) {
      return;
    }
    if (!accounts.contains(oldName)) return;
    _validateProfileName(newName);
    final dir = await getApplicationSupportDirectory();
    final oldFileName =
        oldName == 'Default' ? 'market-monk' : 'market-monk-$oldName';
    final isActive = activeAccount == oldName;
    if (isActive) await db.close();
    for (final suffix in ['', '-wal', '-shm']) {
      final src = File(p.join(dir.path, '$oldFileName.sqlite$suffix'));
      final dst = File(p.join(dir.path, 'market-monk-$newName.sqlite$suffix'));
      if (await src.exists()) await src.rename(dst.path);
    }
    accounts = accounts
        .map((account) => account == oldName ? newName : account)
        .toList();
    final ibkrConfig = _ibkrConfigs.remove(oldName);
    if (ibkrConfig != null) _ibkrConfigs[newName] = ibkrConfig;
    final cachedPortfolio = _portfolioCache.remove(oldName);
    if (cachedPortfolio != null) _portfolioCache[newName] = cachedPortfolio;
    final cachedPerformance = _ibkrPerformanceCache.remove(oldName);
    if (cachedPerformance != null) {
      _ibkrPerformanceCache[newName] = cachedPerformance;
    }
    if (isActive) {
      activeAccount = newName;
      db = Database('market-monk-$newName');
      clearAllSyncCache();
    }
    final prefs = await SqliteSettings.getInstance();
    await prefs.setProfiles(accounts, activeAccount);
    WidgetsBinding.instance.addPostFrameCallback((_) => notifyListeners());
    talker.info('Renamed portfolio account');
  }

  /// Removes a profile and all of its persisted credentials and caches.
  Future<void> deleteAccount(String name) =>
      _serializeStorage(() => _deleteAccount(name));

  Future<void> _deleteAccount(String name) async {
    if (name == 'Default') return;
    if (activeAccount == name) await _switchAccount('Default');
    accounts = accounts.where((account) => account != name).toList();
    _ibkrConfigs.remove(name);
    _portfolioCache.remove(name);
    _ibkrPerformanceCache.remove(name);
    final prefs = await SqliteSettings.getInstance();
    await prefs.setProfiles(accounts, activeAccount);
    try {
      final dir = await getApplicationSupportDirectory();
      for (final suffix in ['', '-wal', '-shm']) {
        final file = File(p.join(dir.path, 'market-monk-$name.sqlite$suffix'));
        if (await file.exists()) await file.delete();
      }
    } catch (error, stackTrace) {
      talker.handle(error, stackTrace, 'Failed to remove portfolio database');
    }
    notifyListeners();
    talker.info('Deleted portfolio account');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) => MaterialApp(
        title: 'Market Monk',
        theme: ThemeData(
          colorScheme: settings.systemColors
              ? lightDynamic
              : ColorScheme.fromSeed(seedColor: settings.seedColor),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: (settings.systemColors
                  ? (darkDynamic ??
                      ColorScheme.fromSeed(
                        seedColor: settings.seedColor,
                        brightness: Brightness.dark,
                      ))
                  : ColorScheme.fromSeed(
                      seedColor: settings.seedColor,
                      brightness: Brightness.dark,
                    ))
              .copyWith(surface: settings.pureBlack ? Colors.black : null),
          useMaterial3: true,
        ),
        themeMode: settings.theme,
        locale: settings.locale,
        localeResolutionCallback: AppLocalizations.resolveLocale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const MyHomePage(),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final _pageController = PageController();
  var _currentIndex = 0;

  static const _tabs = ['ChartPage', 'PortfolioPage', 'HoldingsPage'];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _selectPage(int index) {
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
    setState(() => _currentIndex = index);
  }

  void _selectDesktopPage(int index) {
    if (index == _currentIndex) return;
    if (_pageController.hasClients) {
      _pageController.jumpToPage(index);
    }
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
    );

    return Scaffold(
      extendBody: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= desktopLayoutBreakpoint;
            final pages = PageView(
              controller: _pageController,
              physics: desktop
                  ? const NeverScrollableScrollPhysics()
                  : const PageScrollPhysics(),
              onPageChanged: (index) => setState(() => _currentIndex = index),
              children: [
                ChartsPage(isActive: _currentIndex == 0),
                PortfolioPage(isActive: _currentIndex == 1),
                HoldingsPage(isActive: _currentIndex == 2),
              ],
            );

            final content = Stack(
              children: [
                pages,
                if (!desktop)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: BottomNav(
                      tabs: _tabs,
                      currentIndex: _currentIndex,
                      onTap: _selectPage,
                    ),
                  ),
              ],
            );

            if (!desktop) return content;

            return Row(
              children: [
                DesktopNav(
                  tabs: _tabs,
                  compact: constraints.maxWidth < compactDesktopNavBreakpoint,
                  currentIndex: _currentIndex,
                  onTap: _selectDesktopPage,
                  onSettings: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsPage()),
                  ),
                ),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(child: content),
              ],
            );
          },
        ),
      ),
    );
  }
}
