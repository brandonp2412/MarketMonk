import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:market_monk/bottom_nav.dart';
import 'package:market_monk/charts_page.dart';
import 'package:market_monk/crash_logger.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/holdings_page.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/logging.dart';
import 'package:market_monk/portfolio_page.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/utils.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await CrashLogger.install(fileName: 'marketmonk-crash.log');
      installTalkerErrorHandlers();
      talker.info('Starting Market Monk');

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

  const CachedPortfolioData({
    required this.positions,
    required this.netLiquidation,
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
              lastBuyDate: DateTime.tryParse(
                    position['lastBuyDate'] as String? ?? '',
                  ) ??
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
    );
  }
}

/// Manages named portfolio accounts backed by separate SQLite files.
/// Switching accounts has zero per-query overhead — only the DB file changes.
class AccountManager extends ChangeNotifier {
  List<String> accounts = ['Default'];
  String activeAccount = 'Default';
  int ibkrRefreshVersion = 0;
  final Map<String, IbkrAccountConfig> _ibkrConfigs = {};
  final Map<String, CachedPortfolioData> _portfolioCache = {};

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    activeAccount = prefs.getString('activeAccount') ?? 'Default';
    accounts = prefs.getStringList('accounts') ?? ['Default'];
    final savedPortfolioCache = prefs.getString('portfolioCacheV1');
    if (savedPortfolioCache != null) {
      try {
        final decoded =
            json.decode(savedPortfolioCache) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          final value = entry.value;
          if (value is Map<String, dynamic>) {
            _portfolioCache[entry.key] = CachedPortfolioData.fromJson(value);
          }
        }
      } catch (error, stackTrace) {
        talker.handle(error, stackTrace, 'Failed to load portfolio cache');
      }
    }
    final savedIbkrConfigs = prefs.getString('ibkrAccountConfigs');
    if (savedIbkrConfigs != null) {
      try {
        final decoded = json.decode(savedIbkrConfigs) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          final value = entry.value;
          if (value is Map<String, dynamic>) {
            _ibkrConfigs[entry.key] = IbkrAccountConfig.fromJson(value);
          }
        }
      } catch (error, stackTrace) {
        talker.handle(
          error,
          stackTrace,
          'Failed to load IBKR account settings',
        );
      }
    }
    if (activeAccount != 'Default') {
      db = Database('market-monk-$activeAccount');
    }
    talker.info('Loaded ${accounts.length} portfolio accounts');
  }

  /// Returns the IBKR connection associated with [name], or the active account.
  IbkrAccountConfig ibkrConfigFor([String? name]) =>
      _ibkrConfigs[name ?? activeAccount] ?? const IbkrAccountConfig();

  CachedPortfolioData? portfolioCacheFor([String? name]) =>
      _portfolioCache[name ?? activeAccount];

  Future<void> cachePortfolio(
    String name,
    List<Position> positions,
    IbkrAccountValue? netLiquidation,
  ) async {
    _portfolioCache[name] = CachedPortfolioData(
      positions: List.unmodifiable(positions),
      netLiquidation: netLiquidation,
    );
    final prefs = await SharedPreferences.getInstance();
    await _savePortfolioCache(prefs);
  }

  Future<void> _savePortfolioCache(SharedPreferences prefs) => prefs.setString(
        'portfolioCacheV1',
        json.encode({
          for (final entry in _portfolioCache.entries)
            entry.key: entry.value.toJson(),
        }),
      );

  /// Saves the read-only IBKR connection for one MarketMonk account.
  Future<void> setIbkrConfig(String name, IbkrAccountConfig config) async {
    _ibkrConfigs[name] = config;
    final prefs = await SharedPreferences.getInstance();
    await _saveIbkrConfigs(prefs);
    ibkrRefreshVersion++;
    notifyListeners();
  }

  /// Signals kept-alive portfolio pages to fetch a fresh IBKR snapshot.
  void requestIbkrRefresh() {
    ibkrRefreshVersion++;
    notifyListeners();
  }

  Future<void> _saveIbkrConfigs(SharedPreferences prefs) => prefs.setString(
        'ibkrAccountConfigs',
        json.encode({
          for (final entry in _ibkrConfigs.entries)
            entry.key: entry.value.toJson(),
        }),
      );

  Future<void> switchAccount(String name) async {
    if (name == activeAccount) return;
    await db.close();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('activeAccount', name);
    activeAccount = name;
    db = name == 'Default' ? Database() : Database('market-monk-$name');
    clearAllSyncCache();
    notifyListeners();
    talker.info('Switched active portfolio account');
  }

  Future<void> addAccount(String name) async {
    if (accounts.contains(name)) return;
    accounts = [...accounts, name];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('accounts', accounts);
    // Defer notification to post-frame so it fires after the current build
    // phase completes. Without this, notifyListeners() fires as a microtask
    // during the dialog's exit-animation frame, marking AccountsPage dirty
    // mid-build and triggering _dependents.isEmpty assertions on the Overlay.
    WidgetsBinding.instance.addPostFrameCallback((_) => notifyListeners());
    talker.info('Added portfolio account');
  }

  Future<void> renameAccount(String oldName, String newName) async {
    if (newName.isEmpty || accounts.contains(newName)) return;
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
    accounts = accounts.map((a) => a == oldName ? newName : a).toList();
    final ibkrConfig = _ibkrConfigs.remove(oldName);
    if (ibkrConfig != null) _ibkrConfigs[newName] = ibkrConfig;
    final cachedPortfolio = _portfolioCache.remove(oldName);
    if (cachedPortfolio != null) _portfolioCache[newName] = cachedPortfolio;
    if (isActive) {
      activeAccount = newName;
      db = Database('market-monk-$newName');
      clearAllSyncCache();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('accounts', accounts);
    await _saveIbkrConfigs(prefs);
    await _savePortfolioCache(prefs);
    if (isActive) await prefs.setString('activeAccount', newName);
    WidgetsBinding.instance.addPostFrameCallback((_) => notifyListeners());
    talker.info('Renamed portfolio account');
  }

  Future<void> deleteAccount(String name) async {
    if (name == 'Default') return;
    if (activeAccount == name) await switchAccount('Default');
    accounts = accounts.where((a) => a != name).toList();
    _ibkrConfigs.remove(name);
    _portfolioCache.remove(name);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('accounts', accounts);
    await _saveIbkrConfigs(prefs);
    await _savePortfolioCache(prefs);
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File(p.join(dir.path, 'market-monk-$name.sqlite'));
      if (await file.exists()) await file.delete();
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
        title: 'MarketMonk',
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
        child: Stack(
          children: [
            PageView(
              controller: _pageController,
              onPageChanged: (i) => setState(() => _currentIndex = i),
              children: const [ChartsPage(), PortfolioPage(), HoldingsPage()],
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: BottomNav(
                tabs: _tabs,
                currentIndex: _currentIndex,
                onTap: (i) {
                  _pageController.animateToPage(
                    i,
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                  );
                  setState(() => _currentIndex = i);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
