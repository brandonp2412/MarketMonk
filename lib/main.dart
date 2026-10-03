import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
import 'package:market_monk/legacy_preferences_migration.dart';
import 'package:market_monk/portfolio_page.dart';
import 'package:market_monk/profile_data_repository.dart';
import 'package:market_monk/settings_page.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/utils.dart';
import 'package:market_monk/unified_database.dart';
import 'package:market_monk/unified_backup_store.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:market_monk/sqlite_settings.dart';

Future<void> main() async {
  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await CrashLogger.install(fileName: 'marketmonk-crash.log');
      installTalkerErrorHandlers();
      talker.info('Starting Market Monk');

      final sqliteSettings = await SqliteSettings.getInstance();
      final settings = SettingsState();
      final accounts = AccountManager();
      await Future.wait([settings.initialized, accounts.init()]);
      await sqliteSettings.cleanupLegacyAppStateAfterUnifiedMigration(
        profileDataDatabase,
      );
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

Database? _legacyDatabaseShim;
Database get db => _legacyDatabaseShim ??= Database();
set db(Database value) => _legacyDatabaseShim = value;

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

  final Map<String, CachedPortfolioData> _portfolioCache = {};
  final Map<String, Map<String, CachedIbkrPerformanceData>>
      _ibkrPerformanceCache = {};

  /// Loads the profile registry, credentials and caches from SQLite.
  Future<void> init() async {
    final prefs = await SqliteSettings.getInstance();
    _ibkrConfigs.clear();
    _portfolioCache.clear();
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

    var profiles = await _unifiedDatabase.readProfiles();
    if (profiles.isEmpty) {
      for (var index = 0; index < legacyAccounts.length; index++) {
        final account = legacyAccounts[index];
        final profileId =
            account == 'Default' ? 'profile-default' : 'profile-legacy-$index';
        _profileIdsByName[account] = profileId;
        await _unifiedDatabase.upsertProfile(
          id: profileId,
          name: account,
          sortOrder: index,
        );
      }
      activeAccount = legacyActive;
      await _unifiedDatabase.setActiveProfileId(activeProfileId);
      for (final account in legacyAccounts) {
        await _migrateLegacyProfileState(account);
      }
      profiles = await _unifiedDatabase.readProfiles();
    } else if (!profiles.any((profile) => profile.name == 'Default')) {
      await _unifiedDatabase.upsertProfile(
        id: 'profile-default',
        name: 'Default',
        sortOrder: 0,
      );
      profiles = await _unifiedDatabase.readProfiles();
    }

    accounts = profiles.map((profile) => profile.name).toList();
    for (final profile in profiles) {
      _profileIdsByName[profile.name] = profile.id;
    }

    final savedProfileId = await _unifiedDatabase.readActiveProfileId();
    activeAccount = 'Default';
    for (final profile in profiles) {
      if (profile.id == savedProfileId) {
        activeAccount = profile.name;
        break;
      }
    }
    if (savedProfileId == null ||
        _profileIdsByName[activeAccount] != savedProfileId) {
      await _unifiedDatabase.setActiveProfileId(activeProfileId);
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
    _ibkrPerformanceCache.remove(account);

    final config = await _unifiedDatabase.readIbkrSettings(profileId);
    if (config != null) {
      _ibkrConfigs[account] = IbkrAccountConfig(
        enabled: config.enabled,
        baseUrl: config.baseUrl,
        token: config.token,
      );
    }

    final entries = await _unifiedDatabase.readIbkrCaches(profileId);
    for (final entry in entries) {
      try {
        final value = json.decode(entry.payloadJson) as Map<String, dynamic>;
        if (entry.kind == 'portfolio' && entry.cacheKey == 'snapshot') {
          _portfolioCache[account] = CachedPortfolioData.fromJson(value);
        } else if (entry.kind == 'performance') {
          _ibkrPerformanceCache.putIfAbsent(
            account,
            () => {},
          )[entry.cacheKey] = CachedIbkrPerformanceData.fromJson(value);
        }
      } catch (error, stack) {
        talker.handle(error, stack, 'Skipped malformed SQLite IBKR cache');
      }
    }
  }

  Future<void> _migrateLegacyProfileState(
    String account, {
    bool replace = false,
  }) async {
    final profileId = _profileIdsByName[account];
    if (profileId == null) return;

    if (replace) {
      await _unifiedDatabase.transaction(() async {
        await _unifiedDatabase.deleteIbkrSettings(profileId);
        await _unifiedDatabase.deleteIbkrCache(profileId);
      });
    }

    await _withProfileDatabase(account, (database) async {
      final config = await database.readIbkrProfileSettings();
      if (config != null) {
        await _unifiedDatabase.writeIbkrSettings(
          profileId: profileId,
          enabled: config.enabled,
          baseUrl: config.baseUrl,
          token: config.token,
        );
      }

      final entries = await database.select(database.ibkrCacheEntries).get();
      for (final entry in entries) {
        await _unifiedDatabase.writeIbkrCache(
          profileId: profileId,
          kind: entry.kind,
          cacheKey: entry.cacheKey,
          payloadJson: entry.payloadJson,
          cachedAt: entry.cachedAt,
        );
      }
    });
  }

  AccountManager({
    ProfileDatabaseFactory? profileDatabaseFactory,
    UnifiedDatabase? unifiedDatabase,
  })  : _profileDatabaseFactory =
            profileDatabaseFactory ?? _openProfileDatabase,
        _unifiedDatabase = unifiedDatabase ?? profileDataDatabase;

  final ProfileDatabaseFactory _profileDatabaseFactory;
  final UnifiedDatabase _unifiedDatabase;
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

  static Database _openProfileDatabase(String name) =>
      Database(name == 'Default' ? 'market-monk' : 'market-monk-$name');

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

  Future<void> _prepareUnifiedBackupState(SqliteSettings prefs) async {
    final currentProfiles = await _unifiedDatabase.readProfiles();
    final byName = {
      for (final profile in currentProfiles) profile.name: profile,
    };

    for (final profile in currentProfiles) {
      if (!accounts.contains(profile.name)) {
        await _unifiedDatabase.deleteProfile(profile.id);
      }
    }

    final seed = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    for (var index = 0; index < accounts.length; index++) {
      final account = accounts[index];
      final existing = byName[account];
      await _unifiedDatabase.upsertProfile(
        id: existing?.id ?? 'profile-backup-$seed-$index',
        name: account,
        sortOrder: index,
      );
    }

    final active = await _unifiedDatabase.readProfileByName(activeAccount);
    if (active == null) {
      throw StateError('Active MarketMonk profile is missing from unified DB');
    }
    await _unifiedDatabase.setActiveProfileId(active.id);

    for (final setting in prefs.snapshot().entries) {
      await _unifiedDatabase.writeSetting(setting.key, setting.value);
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
    final profileId = _profileIdsByName[name];
    if (profileId == null) return;
    final cached = CachedIbkrPerformanceData(
      series: series,
      cachedAt: DateTime.now(),
    );
    await _unifiedDatabase.writeIbkrCache(
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
    final profileId = _profileIdsByName[name];
    if (profileId == null) return;
    final cached = CachedPortfolioData(
      positions: List.unmodifiable(positions),
      netLiquidation: netLiquidation,
      netLiquidationUsd: netLiquidationUsd,
      cachedAt: DateTime.now(),
    );
    await _unifiedDatabase.writeIbkrCache(
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
    await _unifiedDatabase.transaction(() async {
      await _unifiedDatabase.writeIbkrSettings(
        profileId: profileId,
        enabled: config.enabled,
        baseUrl: config.baseUrl,
        token: config.token,
      );
      if (changed) await _unifiedDatabase.deleteIbkrCache(profileId);
    });
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
    final profileId = _profileIdsByName[name];
    if (profileId == null) {
      talker.warning('Ignored switch to an unknown portfolio account');
      return;
    }

    activeAccount = name;
    clearAllSyncCache();
    notifyListeners();
    talker.info('Switched active portfolio account');

    await _unifiedDatabase.setActiveProfileId(profileId);
    final prefs = await SqliteSettings.getInstance();
    if (activeAccount == name) {
      await prefs.setString('activeAccount', name);
    }
  }

  /// Replaces the active profile, reloading its credentials and cached state.
  Future<void> importDatabase(File sourceFile) =>
      _serializeStorage(() => _importDatabase(sourceFile));

  Future<void> _importDatabase(File sourceFile) async {
    final profile = await _unifiedDatabase.readProfileByName(activeAccount);
    if (profile == null) {
      throw StateError('Active MarketMonk profile is missing from unified DB');
    }

    try {
      await UnifiedBackupStore(_unifiedDatabase)
          .importLegacyProfile(sourceFile: sourceFile, profileId: profile.id);
      await _loadProfileState(activeAccount);
      clearAllSyncCache();
      notifyListeners();
      talker.info('Imported legacy database into active unified profile');
    } catch (error, stackTrace) {
      talker.handle(error, stackTrace, 'Failed to import portfolio database');
      rethrow;
    }
  }

  /// Snapshots every profile and exports the SQLite application settings.
  Future<File> exportBackup(Directory workingDirectory) =>
      _serializeStorage(() => _exportBackup(workingDirectory));

  Future<File> _exportBackup(Directory workingDirectory) async {
    final prefs = await SqliteSettings.getInstance();
    await prefs.flush();
    await _prepareUnifiedBackupState(prefs);
    return UnifiedBackupStore(_unifiedDatabase).exportArchive(workingDirectory);
  }

  /// Restores current or legacy backups, rolling back on restore errors.
  Future<void> importBackup(File sourceFile) =>
      _serializeStorage(() => _importBackup(sourceFile));

  Future<void> _importBackup(File sourceFile) async {
    final temporaryDirectory = await getTemporaryDirectory();
    final workingDirectory = await temporaryDirectory.createTemp(
      'market-monk-restore-',
    );
    final prefs = await SqliteSettings.getInstance();
    final previousPreferences = prefs.snapshot();
    final previousAccounts = List<String>.of(accounts);
    final previousActiveAccount = activeAccount;
    final store = UnifiedBackupStore(_unifiedDatabase);
    final rollbackFile = File.fromUri(
      workingDirectory.uri.resolve('pre-restore-unified.sqlite'),
    );

    try {
      await store.snapshotDatabase(rollbackFile);
      await _prepareUnifiedBackupState(prefs);
      final restored = await extractMarketMonkBackupArchive(
        archiveFile: sourceFile,
        workingDirectory: workingDirectory,
      );

      await store.restoreBackup(restored, workingDirectory);
      await prefs.restore(
        restored.logical.settings,
        restored.logical.profiles,
        restored.logical.activeProfile,
      );
      await init();

      clearAllSyncCache();
      notifyListeners();
      talker.info('Restored full MarketMonk backup');
    } catch (error, stackTrace) {
      if (await rollbackFile.exists()) {
        await store.restoreUnifiedFile(rollbackFile);
      }
      await prefs.restore(
        previousPreferences,
        previousAccounts,
        previousActiveAccount,
      );
      await init();
      talker.handle(error, stackTrace, 'Failed to restore MarketMonk backup');
      rethrow;
    } finally {
      if (await workingDirectory.exists()) {
        await workingDirectory.delete(recursive: true);
      }
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
    await _unifiedDatabase.upsertProfile(
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
    await _unifiedDatabase.upsertProfile(
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
    await _unifiedDatabase.deleteProfile(profileId);

    accounts = accounts.where((account) => account != name).toList();
    _profileIdsByName.remove(name);
    _ibkrConfigs.remove(name);
    _portfolioCache.remove(name);
    _ibkrPerformanceCache.remove(name);

    final prefs = await SqliteSettings.getInstance();
    await prefs.setProfiles(accounts, activeAccount);

    // Legacy per-profile databases are migration sources only. Remove them
    // after the unified schema validates so a failed cutover stays recoverable.
    try {
      await _unifiedDatabase.validateUnifiedSchema();
      final directory = await getApplicationSupportDirectory();
      final fileName = databaseFileNameForAccount(name);
      for (final suffix in ['', '-wal', '-shm', '-journal']) {
        final file = File('${directory.path}/$fileName$suffix');
        if (await file.exists()) await file.delete();
      }
    } catch (error, stackTrace) {
      talker.handle(
        error,
        stackTrace,
        'Failed to remove obsolete legacy portfolio database',
      );
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
