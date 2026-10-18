import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
import 'package:market_monk/legacy_profile_database.dart' as legacy;
import 'package:market_monk/holdings_page.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/l10n/app_localizations.dart';
import 'package:market_monk/logging.dart';
import 'package:market_monk/portfolio_page.dart';
import 'package:market_monk/profile_data_repository.dart';
import 'package:market_monk/settings_page.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/utils.dart';
import 'package:market_monk/update_notice.dart';
import 'package:market_monk/whats_new.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:market_monk/sqlite_settings.dart';
import 'package:market_monk/legacy_database_source.dart';
import 'package:market_monk/legacy_profile_import.dart';
import 'package:market_monk/unified_database_backup.dart';

Future<void> main() async {
  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await CrashLogger.install(fileName: 'marketmonk-crash.log');
      installTalkerErrorHandlers();
      talker.info('Starting Market Monk');

      final sqliteSettings = await SqliteSettings.getInstance();
      final database = profileDataDatabase;
      await database.migrateLegacyDatabases(
        snapshotLoader: () => readLegacyDatabaseSnapshot(
          readSettings: sqliteSettings.database.readSettings,
          readProfileNames: sqliteSettings.database.readProfileNames,
          readActiveProfile: sqliteSettings.database.readActiveProfile,
          openProfileDatabase: (name) async {
            final directory = await getApplicationSupportDirectory();
            final file =
                File(p.join(directory.path, databaseFileNameForAccount(name)));
            if (!await file.exists()) return null;
            return legacy.LegacyProfileDatabase.connect(NativeDatabase(file));
          },
        ),
      );
      final settings = SettingsState();
      final accounts = AccountManager(database: database);
      await Future.wait([settings.initialized, accounts.init()]);
      await sqliteSettings.cleanupLegacyAppStateAfterMigration();
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

class CachedPortfolioData {
  final List<Position> positions;
  final IbkrAccountValue? netLiquidation;
  final double? netLiquidationUsd;
  final DateTime? asOfDate;
  final DateTime cachedAt;

  const CachedPortfolioData({
    required this.positions,
    required this.netLiquidation,
    this.netLiquidationUsd,
    this.asOfDate,
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
        'asOfDate': asOfDate?.toIso8601String(),
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
      asOfDate: DateTime.tryParse(json['asOfDate'] as String? ?? ''),
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

class CachedIbkrTradeHistoryData {
  final IbkrTradeHistory history;
  final DateTime cachedAt;

  const CachedIbkrTradeHistoryData({
    required this.history,
    required this.cachedAt,
  });

  Map<String, dynamic> toJson() => {
        'history': history.toJson(),
        'cachedAt': cachedAt.toIso8601String(),
      };

  factory CachedIbkrTradeHistoryData.fromJson(Map<String, dynamic> json) =>
      CachedIbkrTradeHistoryData(
        history: IbkrTradeHistory.fromJson(
          json['history'] as Map<String, dynamic>,
        ),
        cachedAt: DateTime.tryParse(json['cachedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// Manages named portfolio profiles in the unified SQLite database.
/// Account switches update profile identity/state without replacing the runtime database.
class AccountManager extends ChangeNotifier {
  List<String> accounts = ['Default'];
  String activeAccount = 'Default';
  int ibkrRefreshVersion = 0;
  final Map<String, IbkrAccountConfig> _ibkrConfigs = {};
  static const ibkrPortfolioCacheMaxAge =
      BackgroundNetworkCoordinator.ibkrPortfolioFreshness;
  static const ibkrPerformanceCacheMaxAge =
      BackgroundNetworkCoordinator.ibkrPerformanceFreshness;
  static const ibkrTradeHistoryCacheMaxAge = Duration(minutes: 15);

  final Map<String, CachedPortfolioData> _portfolioCache = {};
  final Map<String, CachedIbkrTradeHistoryData> _ibkrTradeHistoryCache = {};
  final Map<String, Map<String, CachedIbkrPerformanceData>>
      _ibkrPerformanceCache = {};

  /// Loads the profile registry, credentials and caches from SQLite.
  Future<void> init() async {
    final prefs = await SqliteSettings.getInstance();
    _ibkrConfigs.clear();
    _portfolioCache.clear();
    _ibkrTradeHistoryCache.clear();
    _ibkrPerformanceCache.clear();
    _profileIdsByName.clear();

    var legacyAccounts = prefs.getStringList('accounts') ?? ['Default'];
    if (!legacyAccounts.contains('Default')) {
      legacyAccounts = ['Default', ...legacyAccounts];
    }
    var legacyActive = prefs.getString('activeAccount') ?? 'Default';
    if (!legacyAccounts.contains(legacyActive)) {
      talker.warning(
        'Saved active portfolio account no longer exists; using Default',
      );
      legacyActive = 'Default';
    }

    var profiles = await _database.readProfiles();
    if (profiles.isEmpty) {
      for (var index = 0; index < legacyAccounts.length; index++) {
        final account = legacyAccounts[index];
        final profileId =
            account == 'Default' ? 'profile-default' : 'profile-legacy-$index';
        _profileIdsByName[account] = profileId;
        await _database.upsertProfile(
          id: profileId,
          name: account,
          sortOrder: index,
        );
      }
      activeAccount = legacyActive;
      await _database.setActiveProfileId(activeProfileId);
      profiles = await _database.readProfiles();
    } else if (!profiles.any((profile) => profile.name == 'Default')) {
      await _database.upsertProfile(
        id: 'profile-default',
        name: 'Default',
        sortOrder: 0,
      );
      profiles = await _database.readProfiles();
    }

    accounts = profiles.map((profile) => profile.name).toList();
    for (final profile in profiles) {
      _profileIdsByName[profile.name] = profile.id;
    }

    final savedProfileId = await _database.readActiveProfileId();
    activeAccount = 'Default';
    for (final profile in profiles) {
      if (profile.id == savedProfileId) {
        activeAccount = profile.name;
        break;
      }
    }
    if (savedProfileId == null ||
        _profileIdsByName[activeAccount] != savedProfileId) {
      await _database.setActiveProfileId(activeProfileId);
    }

    await prefs.setProfiles(accounts, activeAccount);
    for (final account in accounts) {
      await _loadProfileState(account);
    }

    talker.info('Loaded ${accounts.length} portfolio accounts');
  }

  Future<void> _loadProfileState(String account) async {
    final profileId = _profileIdsByName[account];
    if (profileId == null) return;

    _ibkrConfigs.remove(account);
    _portfolioCache.remove(account);
    _ibkrTradeHistoryCache.remove(account);
    _ibkrPerformanceCache.remove(account);

    final config = await _database.readIbkrSettings(profileId);
    if (config != null) {
      _ibkrConfigs[account] = IbkrAccountConfig(
        enabled: config.enabled,
        baseUrl: config.baseUrl,
        token: config.token,
      );
    }

    final entries = await _database.readIbkrCaches(profileId);
    for (final entry in entries) {
      try {
        final value = json.decode(entry.payloadJson) as Map<String, dynamic>;
        if (entry.kind == 'portfolio' && entry.cacheKey == 'snapshot') {
          _portfolioCache[account] = CachedPortfolioData.fromJson(value);
        } else if (entry.kind == 'trades' && entry.cacheKey == 'history') {
          final cached = CachedIbkrTradeHistoryData.fromJson(value);
          if (cached.history.available)
            _ibkrTradeHistoryCache[account] = cached;
        } else if (entry.kind == 'performance') {
          _ibkrPerformanceCache.putIfAbsent(account, () => {})[entry.cacheKey] =
              CachedIbkrPerformanceData.fromJson(value);
        }
      } catch (error, stack) {
        talker.handle(error, stack, 'Skipped malformed SQLite IBKR cache');
      }
    }
  }

  AccountManager({Database? database})
      : _database = database ?? profileDataDatabase;

  final Database _database;
  final Map<String, String> _profileIdsByName = {};
  Future<void>? _pendingStorage;

  String get activeProfileId =>
      _profileIdsByName[activeAccount] ?? 'profile-default';

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

  IbkrTradeHistory? ibkrTradeHistoryCacheFor(String name) =>
      _ibkrTradeHistoryCache[name]?.history;

  bool isIbkrTradeHistoryCacheFresh(String name) {
    final cached = _ibkrTradeHistoryCache[name];
    return cached != null &&
        backgroundNetworkCoordinator.isTimestampFresh(
          cached.cachedAt,
          ibkrTradeHistoryCacheMaxAge,
        );
  }

  /// Stores only successful broker trade-history responses for offline display.
  Future<void> cacheIbkrTradeHistory(String name, IbkrTradeHistory history) =>
      history.available
          ? _serializeStorage(() async {
              final profileId = _profileIdsByName[name];
              if (profileId == null) return;
              final cached = CachedIbkrTradeHistoryData(
                history: history,
                cachedAt: DateTime.now(),
              );
              await _database.writeIbkrCache(
                profileId: profileId,
                kind: 'trades',
                cacheKey: 'history',
                payloadJson: json.encode(cached.toJson()),
                cachedAt: cached.cachedAt,
              );
              _ibkrTradeHistoryCache[name] = cached;
            })
          : Future<void>.value();

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
    final profileId = _profileIdsByName[name];
    if (profileId == null) return;
    final cached = CachedIbkrPerformanceData(
      series: series,
      cachedAt: DateTime.now(),
    );
    await _database.writeIbkrCache(
      profileId: profileId,
      kind: 'performance',
      cacheKey: series.period,
      payloadJson: json.encode(cached.toJson()),
      cachedAt: cached.cachedAt,
    );
    _ibkrPerformanceCache.putIfAbsent(name, () => {})[series.period] = cached;
  }

  /// Persists a portfolio snapshot in its owning profile database.
  Future<void> cachePortfolio(
    String name,
    List<Position> positions,
    IbkrAccountValue? netLiquidation, {
    double? netLiquidationUsd,
    DateTime? asOfDate,
  }) =>
      _serializeStorage(
        () => _cachePortfolio(
          name,
          positions,
          netLiquidation,
          netLiquidationUsd: netLiquidationUsd,
          asOfDate: asOfDate,
        ),
      );

  Future<void> _cachePortfolio(
    String name,
    List<Position> positions,
    IbkrAccountValue? netLiquidation, {
    double? netLiquidationUsd,
    DateTime? asOfDate,
  }) async {
    final profileId = _profileIdsByName[name];
    if (profileId == null) return;
    final cached = CachedPortfolioData(
      positions: List.unmodifiable(positions),
      netLiquidation: netLiquidation,
      netLiquidationUsd: netLiquidationUsd,
      asOfDate: asOfDate,
      cachedAt: DateTime.now(),
    );
    await _database.writeIbkrCache(
      profileId: profileId,
      kind: 'portfolio',
      cacheKey: 'snapshot',
      payloadJson: json.encode(cached.toJson()),
      cachedAt: cached.cachedAt,
    );
    _portfolioCache[name] = cached;
  }

  /// Saves the connection and invalidates its caches in one SQLite transaction.
  Future<void> setIbkrConfig(String name, IbkrAccountConfig config) =>
      _serializeStorage(() => _setIbkrConfig(name, config));

  Future<void> _setIbkrConfig(String name, IbkrAccountConfig config) async {
    final profileId = _profileIdsByName[name];
    if (profileId == null) return;
    final changed = _ibkrConfigs[name] != config;
    await _database.transaction(() async {
      await _database.writeIbkrSettings(
        profileId: profileId,
        enabled: config.enabled,
        baseUrl: config.baseUrl,
        token: config.token,
      );
      if (changed) await _database.deleteIbkrCache(profileId);
    });
    _ibkrConfigs[name] = config;
    if (changed) {
      _portfolioCache.remove(name);
      _ibkrTradeHistoryCache.remove(name);
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
    final profileId = _profileIdsByName[name];
    if (profileId == null) {
      talker.warning('Ignored switch to an unknown portfolio account');
      return;
    }

    activeAccount = name;
    clearAllSyncCache();
    notifyListeners();
    talker.info('Switched active portfolio account');

    await _database.setActiveProfileId(profileId);
    final prefs = await SqliteSettings.getInstance();
    if (activeAccount == name) {
      await prefs.setString('activeAccount', name);
    }
  }

  /// Replaces the active profile, reloading its credentials and cached state.
  Future<void> importDatabase(File sourceFile) =>
      _serializeStorage(() => _importDatabase(sourceFile));

  Future<void> _importDatabase(File sourceFile) async {
    final temp = await (await getTemporaryDirectory()).createTemp(
      'market-monk-profile-import-',
    );
    try {
      final copy = await sourceFile.copy(p.join(temp.path, 'profile.sqlite'));
      final source = legacy.LegacyProfileDatabase.connect(NativeDatabase(copy));
      try {
        await importLegacyProfile(_database, source, activeProfileId);
      } finally {
        await source.close();
      }
      await _loadProfileState(activeAccount);
      clearAllSyncCache();
      notifyListeners();
      talker.info('Imported SQLite profile into unified database');
    } finally {
      await temp.delete(recursive: true);
    }
  }

  /// Snapshots every profile and exports the SQLite application settings.
  Future<File> exportBackup(Directory workingDirectory) =>
      _serializeStorage(() => _exportBackup(workingDirectory));

  Future<File> _exportBackup(Directory workingDirectory) async {
    final prefs = await SqliteSettings.getInstance();
    await prefs.flush();
    final temp = await workingDirectory.createTemp('unified-snapshot-');
    try {
      final snapshot = await snapshotUnifiedDatabase(
        _database,
        File(p.join(temp.path, 'market-monk.unified.sqlite')),
      );
      return await buildMarketMonkBackupArchive(
        workingDirectory: workingDirectory,
        logical: MarketMonkLogicalBackup(
          profiles: List<String>.of(accounts),
          activeProfile: activeAccount,
          settings: prefs.snapshot(),
        ),
        storage: MarketMonkBackupStorage.unifiedDatabase(snapshot),
      );
    } finally {
      await temp.delete(recursive: true);
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
      await _applyRestoredBackup(restored);
    } finally {
      if (await workingDirectory.exists()) {
        await workingDirectory.delete(recursive: true);
      }
    }
  }

  Future<void> _applyRestoredBackup(MarketMonkBackupContents restored) async {
    final logical = restored.logical;
    final storage = restored.storage;
    if (storage.layout == MarketMonkBackupStorageLayout.unifiedDatabase) {
      await restoreUnifiedDatabase(
        _database,
        storage.unifiedDatabase!,
        expectedProfiles: logical.profiles,
        expectedActiveProfile: logical.activeProfile,
      );
    } else {
      await _restoreLegacyArchive(restored);
    }
    final prefs = await SqliteSettings.getInstance();
    await prefs.reload();
    await init();
    clearAllSyncCache();
    notifyListeners();
    talker.info('Restored full Market Monk backup');
  }

  Future<void> _restoreLegacyArchive(MarketMonkBackupContents restored) async {
    final logical = restored.logical;
    final files = restored.storage.profileDatabases;
    final snapshot = await readLegacyDatabaseSnapshot(
      readSettings: () async => logical.settings,
      readProfileNames: () async => logical.profiles,
      readActiveProfile: () async => logical.activeProfile,
      openProfileDatabase: (name) async {
        final file = files[name];
        if (file == null) {
          throw const FormatException('Missing profile database in backup');
        }
        return legacy.LegacyProfileDatabase.connect(NativeDatabase(file));
      },
    );
    await _database.migrateLegacySnapshot(snapshot, replaceExisting: true);
  }

  Future<void> _deleteLegacyProfileDatabase(String name) async {
    try {
      final directory = await getApplicationSupportDirectory();
      final path = p.join(directory.path, databaseFileNameForAccount(name));
      for (final suffix in ['', '-wal', '-shm']) {
        final file = File('$path$suffix');
        if (await file.exists()) await file.delete();
      }
    } catch (error, stackTrace) {
      talker.handle(
        error,
        stackTrace,
        'Failed to remove retired profile database for $name',
      );
    }
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

    final seed = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    var profileId = 'profile-$seed';
    var suffix = 0;
    while (_profileIdsByName.containsValue(profileId)) {
      suffix++;
      profileId = 'profile-$seed-$suffix';
    }

    final updated = [...accounts, name];
    await _database.upsertProfile(
      id: profileId,
      name: name,
      sortOrder: updated.length - 1,
    );
    _profileIdsByName[name] = profileId;

    final prefs = await SqliteSettings.getInstance();
    await prefs.setProfiles(updated, activeAccount);
    accounts = updated;
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
    final profileId = _profileIdsByName[oldName];
    if (profileId == null) return;
    _validateProfileName(newName);

    final index = accounts.indexOf(oldName);
    await _database.upsertProfile(
      id: profileId,
      name: newName,
      sortOrder: index,
    );

    accounts = accounts
        .map((account) => account == oldName ? newName : account)
        .toList();
    _profileIdsByName.remove(oldName);
    _profileIdsByName[newName] = profileId;

    final ibkrConfig = _ibkrConfigs.remove(oldName);
    if (ibkrConfig != null) _ibkrConfigs[newName] = ibkrConfig;
    final cachedPortfolio = _portfolioCache.remove(oldName);
    if (cachedPortfolio != null) _portfolioCache[newName] = cachedPortfolio;
    final cachedPerformance = _ibkrPerformanceCache.remove(oldName);
    if (cachedPerformance != null) {
      _ibkrPerformanceCache[newName] = cachedPerformance;
    }

    if (activeAccount == oldName) {
      activeAccount = newName;
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
    final profileId = _profileIdsByName[name];
    if (profileId == null) return;

    if (activeAccount == name) await _switchAccount('Default');
    await _database.deleteProfile(profileId);
    await _deleteLegacyProfileDatabase(name);

    accounts = accounts.where((account) => account != name).toList();
    _profileIdsByName.remove(name);
    _ibkrConfigs.remove(name);
    _portfolioCache.remove(name);
    _ibkrPerformanceCache.remove(name);

    final prefs = await SqliteSettings.getInstance();
    await prefs.setProfiles(accounts, activeAccount);
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
          popupMenuTheme: const PopupMenuThemeData(
            menuPadding: EdgeInsets.zero,
          ),
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
          popupMenuTheme: const PopupMenuThemeData(
            menuPadding: EdgeInsets.zero,
          ),
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showUpdateNotice());
  }

  Future<void> _showUpdateNotice() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final build = int.tryParse(info.buildNumber);
      if (build == null) return;
      final prefs = await SqliteSettings.getInstance();
      const buildKey = 'last_seen_build_number';
      const noticeKey = 'last_update_notice_ms';
      final previousBuild = prefs.getInt(buildKey);
      if (previousBuild == null || build > previousBuild) {
        await prefs.setInt(buildKey, build);
      }
      if (!mounted) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (!shouldShowUpdateNotice(
        previousBuild: previousBuild,
        currentBuild: build,
        lastShownAtMs: prefs.getInt(noticeKey),
        nowMs: now,
      )) return;
      await prefs.setInt(noticeKey, now);
      if (!mounted) return;
      toast(
        context,
        'New version ${info.version}',
        SnackBarAction(
          label: context.l10n.text("What's New"),
          onPressed: () => Navigator.of(context).push(
            adaptivePageRoute(context, builder: (_) => const WhatsNew()),
          ),
        ),
      );
    } catch (error, stackTrace) {
      talker.handle(
        error,
        stackTrace,
        'Unable to show MarketMonk update notice',
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _selectPage(int index) {
    if (_pageController.hasClients) {
      unawaited(
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        ),
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
                  compact: false,
                  currentIndex: _currentIndex,
                  onTap: _selectDesktopPage,
                  onSettings: () => Navigator.push(
                    context,
                    adaptivePageRoute(
                      context,
                      builder: (_) => const SettingsPage(),
                    ),
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
