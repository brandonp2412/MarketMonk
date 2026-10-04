import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:drafter/drafter.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:market_monk/candle_ticker.dart';
import 'package:market_monk/adaptive_layout.dart';
import 'package:market_monk/background_network_coordinator.dart';
import 'package:market_monk/bottom_nav.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/edit_ticker_page.dart';
import 'package:market_monk/empty_state.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/market_line_chart.dart';
import 'package:market_monk/profile_data_repository.dart';
import 'package:market_monk/portfolio_chart_scale.dart';
import 'package:market_monk/l10n/app_localizations.dart';
import 'package:market_monk/logging.dart';
import 'package:market_monk/market_data_store.dart';
import 'package:market_monk/settings_page.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/ticker_line.dart';
import 'package:market_monk/utils.dart';
import 'package:provider/provider.dart';
import 'package:market_monk/sqlite_settings.dart';

enum _ChartMode { portfolio, searching, stock }

class _LoadedChartPortfolio {
  final List<Position> positions;
  final IbkrAccountValue? currentValue;
  final double? currentValueUsd;

  const _LoadedChartPortfolio({
    required this.positions,
    required this.currentValue,
    required this.currentValueUsd,
  });
}

class ChartsPage extends StatefulWidget {
  final bool isActive;
  final Future<IbkrPortfolioSnapshot> Function(IbkrAccountConfig)? _ibkrLoader;
  final Future<IbkrPerformanceSeries> Function(IbkrAccountConfig, String)?
      _ibkrPerformanceLoader;

  const ChartsPage({
    super.key,
    this.isActive = true,
    Future<IbkrPortfolioSnapshot> Function(IbkrAccountConfig)? ibkrLoader,
    Future<IbkrPerformanceSeries> Function(IbkrAccountConfig, String)?
        ibkrPerformanceLoader,
  })  : _ibkrLoader = ibkrLoader,
        _ibkrPerformanceLoader = ibkrPerformanceLoader;

  @override
  State<ChartsPage> createState() => ChartsPageState();
}

class ChartsPageState extends State<ChartsPage>
    with AutomaticKeepAliveClientMixin {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  _ChartMode _mode = _ChartMode.portfolio;
  String? _selectedSymbol;
  List<String> _favoriteStocks = [];
  bool _networkLoading = false;
  String? _stockError;
  String _nativeCurrency = 'USD';
  double _centDivisor = 1.0;

  // Measured height of the floating search bar overlay so chart content can
  // be padded beneath it, while the chart's canvas extends to the top and
  // tooltips can render above the data without being clipped. Re-measured
  // whenever the overlay's laid-out size changes (the first frame can be
  // laid out at a degenerate size, e.g. before the Linux window is realized).
  final _overlayKey = GlobalKey();
  double _overlayHeight = 80.0;

  int years = 1;
  int months = 0;
  int days = 0;

  Stream<List<CandleTicker>>? _stockStream;

  Map<String, List<_DateValue>> _portfolioSeriesByAccount = {};
  Map<String, double> _portfolioReturnsByAccount = {};
  Map<String, double> _portfolioReturnAmountsByAccount = {};
  String? _portfolioError;
  bool _portfolioLoading = true;
  bool _chartPeriodLoaded = false;
  final Set<String> _hiddenAccounts = {};
  final Map<String, Future<_LoadedChartPortfolio>> _ibkrLoads = {};
  final Map<String, Future<IbkrPerformanceSeries>> _ibkrPerformanceLoads = {};

  final _yahooApi = YahooFinanceApi();
  List<StockResult> _searchResults = [];
  bool _searchLoading = false;

  int _lastTradesVersion = 0;
  String _lastAccountsKey = '';
  String _lastActiveAccount = '';
  int _lastIbkrRefreshVersion = 0;
  int _portfolioLoadGeneration = 0;
  AccountManager? _accountManager;
  final Map<(bool, bool), Future<void>> _backgroundSyncs = {};
  final Map<(bool, bool, bool, bool), Future<void>> _portfolioLoads = {};

  @override
  void initState() {
    super.initState();
    runDetachedTask(_loadFavorites(), 'Failed to load chart favorites');
    runDetachedTask(
      _loadPeriodThenPortfolios(),
      'Failed to initialize chart period and portfolios',
    );
    _setColors();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureOverlay());
  }

  @override
  void didUpdateWidget(covariant ChartsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive && !widget.isActive) {
      _portfolioLoadGeneration++;
      _stockStream = null;
      return;
    }
    if (!oldWidget.isActive && widget.isActive && _chartPeriodLoaded) {
      final accountManager = context.read<AccountManager>();
      _hydratePortfolioSeriesFromCache(accountManager);
      if (_selectedSymbol != null) _setStockStream(_selectedSymbol!);
      runDetachedTask(
        _syncCandlesInBackground(refreshPerformance: true),
        'Failed to refresh chart data after activation',
      );
    }
  }

  void _setColors() {}

  void _measureOverlay() {
    final box = _overlayKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !mounted) return;
    final measuredHeight = box.size.height;
    if (measuredHeight != _overlayHeight) {
      setState(() => _overlayHeight = measuredHeight);
    }
  }

  Future<void> _loadPeriodThenPortfolios() async {
    final settings = context.read<SettingsState>();
    await settings.initialized;
    if (!mounted) return;

    final prefs = await SqliteSettings.getInstance();
    final periodYears = prefs.getInt('chartPeriodYears') ?? 1;
    final periodMonths = prefs.getInt('chartPeriodMonths') ?? 0;
    final periodDays = prefs.getInt('chartPeriodDays') ?? 0;
    if (!mounted) return;

    setState(() {
      years = periodYears;
      months = periodMonths;
      days = periodDays;
      _chartPeriodLoaded = true;
    });

    final accountManager = context.read<AccountManager>();
    _hydratePortfolioSeriesFromCache(accountManager);
    if (widget.isActive) {
      runDetachedTask(
        () async {
          await _syncCandlesInBackground(refreshPerformance: true);
          talker.info(
            backgroundNetworkCoordinator.diagnosticsSummary(
              label: 'Startup request summary',
            ),
          );
        }(),
        'Failed to initialize active chart data',
      );
    }
  }

  Future<void> _savePeriod() async {
    final prefs = await SqliteSettings.getInstance();
    await prefs.setInt('chartPeriodYears', years);
    await prefs.setInt('chartPeriodMonths', months);
    await prefs.setInt('chartPeriodDays', days);
  }

  void _hydratePortfolioSeriesFromCache(AccountManager accountManager) {
    if (!_chartPeriodLoaded || _portfolioSeriesByAccount.isNotEmpty) return;

    // The persisted IBKR performance cache is one year of history. It can
    // faithfully satisfy any selected period up to one year, but must never be
    // flashed for a longer saved period while the real series is rebuilding.
    if (years > 1 || (years == 1 && (months > 0 || days > 0))) return;

    final cachedSeries = <String, List<_DateValue>>{};
    final cachedReturns = <String, double>{};
    final cachedReturnAmounts = <String, double>{};

    for (final accountName in accountManager.accounts) {
      final config = accountManager.ibkrConfigFor(accountName);
      if (!config.enabled) return;

      final cachedPortfolio = accountManager.portfolioCacheFor(accountName);
      final performance = accountManager.ibkrPerformanceCacheFor(
        accountName,
        '1Y',
      );
      if (cachedPortfolio == null || performance == null) return;

      final currentValue = cachedPortfolio.netLiquidation;
      final currentValueUsd = cachedPortfolio.netLiquidationUsd;
      if (currentValue != null &&
          currentValueUsd != null &&
          currentValueUsd != 0 &&
          currentValue.currency.isNotEmpty &&
          currentValue.currency != 'USD') {
        allRatesFromUsd[currentValue.currency] =
            currentValue.value / currentValueUsd;
      }

      final brokerSeries = _buildBrokerPerformanceSeries(
        performance,
        _LoadedChartPortfolio(
          positions: cachedPortfolio.positions,
          currentValue: currentValue,
          currentValueUsd: currentValueUsd,
        ),
      );
      if (brokerSeries.series.isEmpty) return;

      cachedSeries[accountName] = brokerSeries.series;
      cachedReturns[accountName] = brokerSeries.twrPercent;
      cachedReturnAmounts[accountName] = brokerSeries.returnAmount;
    }

    if (cachedSeries.length != accountManager.accounts.length) return;
    _portfolioSeriesByAccount = cachedSeries;
    _portfolioReturnsByAccount = cachedReturns;
    _portfolioReturnAmountsByAccount = cachedReturnAmounts;
    _portfolioLoading = false;
  }

  Future<_LoadedChartPortfolio> _portfolioForAccount(
    String accountName,
    IbkrAccountConfig ibkrConfig,
    AccountManager accountManager, {
    bool refreshIbkr = false,
    bool forceIbkrRefresh = false,
  }) async {
    final trades =
        await profileDataRepository.readTradesForAccount(accountName);
    if (ibkrConfig.enabled) {
      final cached = accountManager.portfolioCacheFor(accountName);
      final cacheFresh = accountManager.isPortfolioCacheFresh(accountName);
      final shouldUseCache = cached != null &&
          !forceIbkrRefresh &&
          (!refreshIbkr || cacheFresh || !ibkrConfig.isConfigured);
      if (shouldUseCache) {
        final currentValue = cached.netLiquidation;
        final currentValueUsd = cached.netLiquidationUsd;
        if (currentValue != null &&
            currentValueUsd != null &&
            currentValueUsd != 0 &&
            currentValue.currency.isNotEmpty &&
            currentValue.currency != 'USD') {
          allRatesFromUsd[currentValue.currency] =
              currentValue.value / currentValueUsd;
        }
        return _LoadedChartPortfolio(
          positions: cached.positions,
          currentValue: currentValue,
          currentValueUsd: currentValueUsd,
        );
      }
      if (!ibkrConfig.isConfigured) {
        if (cached != null) {
          return _LoadedChartPortfolio(
            positions: cached.positions,
            currentValue: cached.netLiquidation,
            currentValueUsd: cached.netLiquidationUsd,
          );
        }
        throw StateError('IBKR portfolio source is not fully configured');
      }
      if (!widget.isActive) {
        return _LoadedChartPortfolio(
          positions: cached?.positions ?? const [],
          currentValue: cached?.netLiquidation,
          currentValueUsd: cached?.netLiquidationUsd,
        );
      }

      final loadKey = [accountName, ibkrConfig.hashCode].join('|');
      try {
        return await _ibkrLoads.putIfAbsent(loadKey, () async {
          try {
            final snapshot = await (widget._ibkrLoader?.call(ibkrConfig) ??
                IbkrApiClient(ibkrConfig).fetchPortfolio());
            cacheIbkrAccountExchangeRate(snapshot);
            final positions = await computeIbkrPositions(
              snapshot.positions,
              trades,
            );
            final currentValue = snapshot.netLiquidation;
            final currentValueUsd = snapshot.netLiquidationUsd?.value;
            await accountManager.cachePortfolio(
              accountName,
              positions,
              snapshot.netLiquidation,
              netLiquidationUsd: currentValueUsd,
            );
            return _LoadedChartPortfolio(
              positions: positions,
              currentValue: currentValue,
              currentValueUsd: currentValueUsd,
            );
          } finally {
            _ibkrLoads.removeWhere((key, value) => key == loadKey);
          }
        });
      } catch (error) {
        if (cached != null) {
          talker.warning(
            'IBKR portfolio unavailable for $accountName; using cached data: '
            '$error',
          );
          return _LoadedChartPortfolio(
            positions: cached.positions,
            currentValue: cached.netLiquidation,
            currentValueUsd: cached.netLiquidationUsd,
          );
        }
        rethrow;
      }
    }
    if (!widget.isActive) {
      return const _LoadedChartPortfolio(
        positions: [],
        currentValue: null,
        currentValueUsd: null,
      );
    }
    final symbols = trades.map((trade) => trade.symbol).toSet().toList();
    final prices = await fetchLatestPrices(symbols);
    return _LoadedChartPortfolio(
      positions: computePositions(trades, prices),
      currentValue: null,
      currentValueUsd: null,
    );
  }

  Future<void> _syncCandlesInBackground({
    bool refreshPerformance = false,
    bool forcePerformanceRefresh = false,
  }) {
    final key = (refreshPerformance, forcePerformanceRefresh);
    final existing = _backgroundSyncs[key];
    if (existing != null) return existing;

    late final Future<void> future;
    future = _performBackgroundSync(
      refreshPerformance: refreshPerformance,
      forcePerformanceRefresh: forcePerformanceRefresh,
    ).whenComplete(() {
      _backgroundSyncs.removeWhere(
        (entryKey, value) => entryKey == key && identical(value, future),
      );
    });
    _backgroundSyncs[key] = future;
    return future;
  }

  Future<void> _performBackgroundSync({
    bool refreshPerformance = false,
    bool forcePerformanceRefresh = false,
  }) async {
    if (!mounted || !widget.isActive) return;

    final accountManager = context.read<AccountManager>();
    for (final accountName in accountManager.accounts) {
      if (!mounted || !widget.isActive) return;
      final ibkrConfig = accountManager.ibkrConfigFor(accountName);
      if (ibkrConfig.enabled) continue;
      await _syncLocalAccountCandles(accountName, ibkrConfig);
    }

    if (!mounted || !widget.isActive) return;
    await _loadAllPortfolios(
      refreshIbkrPerformance: refreshPerformance,
      forceIbkrPerformanceRefresh: forcePerformanceRefresh,
      refreshIbkrPortfolio: refreshPerformance,
      forceIbkrPortfolioRefresh: forcePerformanceRefresh,
    );
  }

  Future<void> _syncLocalAccountCandles(
    String accountName,
    IbkrAccountConfig ibkrConfig,
  ) async {
    try {
      final trades =
          await profileDataRepository.readTradesForAccount(accountName);
      if (!mounted || !widget.isActive) return;
      final symbols = trades.map((trade) => trade.symbol).toSet();
      for (final symbol in symbols) {
        if (!mounted || !widget.isActive) return;
        await syncCandles(
          symbol,
          ibkrConfig: ibkrConfig,
          syncNamespace: accountName,
          requiredFrom: _requiredCandleStart(),
        );
      }
    } catch (error, stackTrace) {
      talker.handle(
        error,
        stackTrace,
        'Background candle sync failed for $accountName',
      );
    }
  }

  void _handleAccountManagerChanged() {
    final accountManager = _accountManager;
    if (!mounted ||
        !widget.isActive ||
        accountManager == null ||
        !_chartPeriodLoaded) {
      return;
    }

    final accountsKey = accountManager.accounts.join(',');
    final activeAccount = accountManager.activeAccount;
    final ibkrRefreshVersion = accountManager.ibkrRefreshVersion;
    final accountsChanged = accountsKey != _lastAccountsKey;
    final activeAccountChanged = activeAccount != _lastActiveAccount;
    final ibkrChanged = ibkrRefreshVersion != _lastIbkrRefreshVersion;
    if (!accountsChanged && !activeAccountChanged && !ibkrChanged) return;

    _lastAccountsKey = accountsKey;
    _lastActiveAccount = activeAccount;
    _lastIbkrRefreshVersion = ibkrRefreshVersion;
    if (ibkrChanged) clearAllSyncCache();

    if (accountsChanged || ibkrChanged) {
      runDetachedTask(
        _syncCandlesInBackground(
          refreshPerformance: true,
          forcePerformanceRefresh: ibkrChanged,
        ),
        'Failed to refresh charts after account change',
      );
    }
    if (_selectedSymbol != null) _setStockStream(_selectedSymbol!);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final version = context.watch<SettingsState>().tradesVersion;
    if (version != _lastTradesVersion) {
      _lastTradesVersion = version;
      if (version > 0 && widget.isActive) {
        runDetachedTask(
          _loadAllPortfolios(),
          'Failed to reload portfolios after trade change',
        );
      }
    }

    final accountManager = context.read<AccountManager>();
    if (!identical(_accountManager, accountManager)) {
      final firstManager = _accountManager == null;
      _accountManager?.removeListener(_handleAccountManagerChanged);
      _accountManager = accountManager;
      accountManager.addListener(_handleAccountManagerChanged);
      if (firstManager) {
        _lastAccountsKey = accountManager.accounts.join(',');
        _lastActiveAccount = accountManager.activeAccount;
        _lastIbkrRefreshVersion = accountManager.ibkrRefreshVersion;
      }
    }
    if (_chartPeriodLoaded) {
      _hydratePortfolioSeriesFromCache(accountManager);
      _handleAccountManagerChanged();
    }
  }

  @override
  void dispose() {
    _accountManager?.removeListener(_handleAccountManagerChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    _yahooApi.dispose();
    super.dispose();
  }

  /// Syncs candles for all accounts. Caller is responsible for setting
  /// [_networkLoading].
  Future<void> _refreshAllPortfolioCandles() async {
    if (!mounted || !widget.isActive) return;
    final accountManager = context.read<AccountManager>();

    for (final accountName in accountManager.accounts) {
      if (!mounted || !widget.isActive) return;
      final ibkrConfig = accountManager.ibkrConfigFor(accountName);
      if (ibkrConfig.enabled) continue;

      try {
        final trades =
            await profileDataRepository.readTradesForAccount(accountName);
        if (!mounted || !widget.isActive) return;
        for (final symbol in trades.map((trade) => trade.symbol).toSet()) {
          if (!mounted || !widget.isActive) return;
          await syncCandles(
            symbol,
            ibkrConfig: ibkrConfig,
            syncNamespace: accountName,
            requiredFrom: _requiredCandleStart(),
            forceRefresh: true,
          );
        }
      } catch (error, stackTrace) {
        talker.handle(
          error,
          stackTrace,
          'Portfolio candle refresh failed for $accountName',
        );
      }
    }
  }

  /// Refreshes whichever chart the user is currently viewing. This is used by
  /// the page's pull-to-refresh gesture, keeping the chart controls focused on
  /// navigation and actions other than loading data.
  Future<void> _refreshCurrentChart() async {
    if (!mounted || !widget.isActive || _networkLoading) return;

    setState(() {
      _networkLoading = true;
      _stockError = null;
    });

    try {
      if (_mode == _ChartMode.stock && _selectedSymbol != null) {
        clearSyncCache(_selectedSymbol!);
        final accountManager = context.read<AccountManager>();
        await syncCandles(
          _selectedSymbol!,
          ibkrConfig: accountManager.ibkrConfigFor(),
          syncNamespace: accountManager.activeAccount,
          requiredFrom: _requiredCandleStart(),
          forceRefresh: true,
        );
        if (mounted) _setStockStream(_selectedSymbol!);
      } else {
        clearAllSyncCache();
        await _refreshAllPortfolioCandles();
        await _loadAllPortfolios(
          refreshIbkrPerformance: true,
          forceIbkrPerformanceRefresh: true,
          refreshIbkrPortfolio: true,
          forceIbkrPortfolioRefresh: true,
        );
      }
    } catch (error, stackTrace) {
      talker.handle(error, stackTrace, 'Chart refresh failed');
      if (mounted && _mode == _ChartMode.stock) {
        setState(() => _stockError = error.toString());
      }
    } finally {
      if (mounted) setState(() => _networkLoading = false);
    }
  }

  Future<void> _loadFavorites() async {
    final prefs = await SqliteSettings.getInstance();
    var favorites = prefs.getStringList('favoriteStocks');
    if (favorites == null) {
      final legacy = prefs.getString('favoriteStock');
      favorites = legacy != null ? [legacy] : [];
      await prefs.setStringList('favoriteStocks', favorites);
      if (legacy != null) await prefs.remove('favoriteStock');
    }
    if (mounted) setState(() => _favoriteStocks = favorites!);
    if (widget.isActive) {
      runDetachedTask(
        _syncFavoriteCandles(),
        'Failed to sync favorite ticker candles',
      );
    }
  }

  Future<void> _syncFavoriteCandles() async {
    for (final symbol in _favoriteStocks) {
      if (!mounted || !widget.isActive) return;
      await _syncFavoriteCandle(symbol);
    }
  }

  Future<void> _syncFavoriteCandle(String symbol) async {
    if (!mounted || !widget.isActive) return;
    try {
      final accountManager = context.read<AccountManager>();
      await syncCandles(
        symbol,
        ibkrConfig: accountManager.ibkrConfigFor(),
        syncNamespace: accountManager.activeAccount,
      );
    } catch (error, stackTrace) {
      talker.handle(error, stackTrace, 'Favorite ticker candle sync failed');
    }
  }

  Future<void> _toggleFavorite(String symbol) async {
    final ctx = context;
    final prefs = await SqliteSettings.getInstance();
    if (!ctx.mounted) return;
    final isFavorite = _favoriteStocks.contains(symbol);
    setState(() {
      if (isFavorite) {
        _favoriteStocks.remove(symbol);
      } else {
        _favoriteStocks.add(symbol);
      }
    });
    await prefs.setStringList('favoriteStocks', _favoriteStocks);
    if (!ctx.mounted) return;
    if (isFavorite) {
      toast(ctx, ctx.l10n.text('Removed as favorite'));
      return;
    }
    runDetachedTask(
      _syncFavoriteCandle(symbol),
      'Failed to sync favorite ticker candle',
    );
    toast(ctx, ctx.l10n.text('Set as favorite'));
  }

  Future<IbkrPerformanceSeries> _performanceForAccount(
    String accountName,
    IbkrAccountConfig config,
    AccountManager accountManager,
    String period, {
    bool refreshIfStale = false,
    bool forceRefresh = false,
  }) async {
    final cached = accountManager.ibkrPerformanceCacheFor(accountName, period);
    final cacheFresh = accountManager.isIbkrPerformanceCacheFresh(
      accountName,
      period,
    );
    if (cached != null &&
        !forceRefresh &&
        (!refreshIfStale || cacheFresh || !config.isConfigured)) {
      return cached;
    }
    if (!config.isConfigured) {
      if (cached != null) return cached;
      throw StateError('IBKR performance source is not fully configured');
    }
    if (!widget.isActive) {
      if (cached != null) return cached;
      throw StateError('Charts page is inactive');
    }

    final loadKey = '$accountName|$period|${config.hashCode}';
    try {
      return await _ibkrPerformanceLoads.putIfAbsent(loadKey, () async {
        try {
          final performance =
              await (widget._ibkrPerformanceLoader?.call(config, period) ??
                  IbkrApiClient(config).fetchPerformance(period));
          await accountManager.cacheIbkrPerformance(accountName, performance);
          return performance;
        } finally {
          _ibkrPerformanceLoads.removeWhere((key, value) => key == loadKey);
        }
      });
    } catch (error) {
      if (cached != null) {
        talker.warning('IBKR performance unavailable; using cached data');
        return cached;
      }
      rethrow;
    }
  }

  Future<({List<_DateValue> series, double twrPercent, double returnAmount})?>
      _loadBrokerPerformanceSeries(
    String accountName,
    IbkrAccountConfig ibkrConfig,
    AccountManager accountManager,
    _LoadedChartPortfolio loaded, {
    required bool refreshIfStale,
    required bool forceRefresh,
  }) async {
    try {
      final performance = await _performanceForAccount(
        accountName,
        ibkrConfig,
        accountManager,
        '1Y',
        refreshIfStale: refreshIfStale,
        forceRefresh: forceRefresh,
      );
      final brokerSeries = _buildBrokerPerformanceSeries(performance, loaded);
      return brokerSeries.series.isEmpty ? null : brokerSeries;
    } catch (error) {
      talker.warning(
        'IBKR performance history unavailable; '
        'showing current broker value only: $error',
      );
      return null;
    }
  }

  Future<void> _loadAllPortfolios({
    bool refreshIbkrPerformance = false,
    bool forceIbkrPerformanceRefresh = false,
    bool refreshIbkrPortfolio = false,
    bool forceIbkrPortfolioRefresh = false,
  }) {
    final key = (
      refreshIbkrPerformance,
      forceIbkrPerformanceRefresh,
      refreshIbkrPortfolio,
      forceIbkrPortfolioRefresh,
    );
    final existing = _portfolioLoads[key];
    if (existing != null) return existing;

    late final Future<void> future;
    future = _performLoadAllPortfolios(
      refreshIbkrPerformance: refreshIbkrPerformance,
      forceIbkrPerformanceRefresh: forceIbkrPerformanceRefresh,
      refreshIbkrPortfolio: refreshIbkrPortfolio,
      forceIbkrPortfolioRefresh: forceIbkrPortfolioRefresh,
    ).whenComplete(() {
      _portfolioLoads.removeWhere(
        (entryKey, value) => entryKey == key && identical(value, future),
      );
    });
    _portfolioLoads[key] = future;
    return future;
  }

  Future<void> _performLoadAllPortfolios({
    bool refreshIbkrPerformance = false,
    bool forceIbkrPerformanceRefresh = false,
    bool refreshIbkrPortfolio = false,
    bool forceIbkrPortfolioRefresh = false,
  }) async {
    if (!mounted || !widget.isActive || !_chartPeriodLoaded) return;
    final generation = ++_portfolioLoadGeneration;
    final accountManager = context.read<AccountManager>();
    final accounts = accountManager.accounts;

    setState(() {
      _portfolioError = null;
      _portfolioLoading = _portfolioSeriesByAccount.isEmpty;
    });

    final newSeries = <String, List<_DateValue>>{};
    final newReturns = <String, double>{};
    final newReturnAmounts = <String, double>{};
    String? firstError;

    for (final accountName in accounts) {
      if (!mounted ||
          !widget.isActive ||
          generation != _portfolioLoadGeneration) {
        return;
      }
      try {
        final ibkrConfig = accountManager.ibkrConfigFor(accountName);
        final loaded = await _portfolioForAccount(
          accountName,
          ibkrConfig,
          accountManager,
          refreshIbkr: refreshIbkrPortfolio,
          forceIbkrRefresh: forceIbkrPortfolioRefresh,
        );
        if (!mounted ||
            !widget.isActive ||
            generation != _portfolioLoadGeneration) {
          return;
        }
        if (ibkrConfig.isConfigured && years <= 1) {
          final brokerSeries = await _loadBrokerPerformanceSeries(
            accountName,
            ibkrConfig,
            accountManager,
            loaded,
            refreshIfStale: refreshIbkrPerformance,
            forceRefresh: forceIbkrPerformanceRefresh,
          );
          if (!mounted ||
              !widget.isActive ||
              generation != _portfolioLoadGeneration) {
            return;
          }
          if (brokerSeries != null) {
            newSeries[accountName] = brokerSeries.series;
            newReturns[accountName] = brokerSeries.twrPercent;
            newReturnAmounts[accountName] = brokerSeries.returnAmount;
            continue;
          }
        }
        if (ibkrConfig.enabled) {
          final currentValueUsd = loaded.currentValueUsd;
          if (currentValueUsd != null && currentValueUsd.isFinite) {
            final now = DateTime.now();
            newSeries[accountName] = [
              _DateValue(
                DateTime(now.year, now.month, now.day),
                currentValueUsd,
              ),
            ];
          } else {
            newSeries[accountName] = [];
          }
          continue;
        }

        final fallback = await _buildPortfolioSeries(
          accountName,
          loaded.positions,
        );
        newSeries[accountName] = fallback.series;
      } catch (error) {
        newSeries[accountName] = [];
        firstError ??= error.toString();
      }
    }

    if (!mounted ||
        !widget.isActive ||
        generation != _portfolioLoadGeneration) {
      return;
    }
    setState(() {
      _portfolioSeriesByAccount = newSeries;
      _portfolioReturnsByAccount = newReturns;
      _portfolioReturnAmountsByAccount = newReturnAmounts;
      _portfolioError = firstError;
      _portfolioLoading = false;
    });
  }

  Future<({List<_DateValue> series, bool currentHoldingsReplay})>
      _buildPortfolioSeries(
    String accountName,
    List<Position> positions, {
    double? currentPortfolioValueUsd,
  }) async {
    if (positions.isEmpty) {
      return (series: const <_DateValue>[], currentHoldingsReplay: false);
    }

    final now = DateTime.now();
    final after = days > 0
        ? DateTime(now.year, now.month, now.day - days - 4)
        : DateTime(now.year - years, now.month - months, now.day - 1);
    final trades =
        await profileDataRepository.readTradesForAccount(accountName);
    final currentHoldingsReplay = trades.isEmpty;
    final currentHoldingsValueUsd = positions.fold<double>(
      0,
      (sum, position) => sum + position.currentValue,
    );
    final replayResidualUsd = currentHoldingsReplay &&
            currentPortfolioValueUsd != null &&
            currentPortfolioValueUsd.isFinite
        ? currentPortfolioValueUsd - currentHoldingsValueUsd
        : 0.0;
    final symbols = {
      ...positions.map((position) => position.symbol),
      ...trades.map((trade) => trade.symbol),
    };
    final Map<String, Map<DateTime, double>> pricesBySymbol = {};

    for (final symbol in symbols) {
      final marketSymbol = canonicalMarketSymbol(symbol);
      final rows = await (marketDataDatabase.candles.select()
            ..where(
              (candle) =>
                  candle.symbol.equals(marketSymbol) &
                  candle.date.isBiggerThanValue(after),
            )
            ..orderBy([
              (candle) => OrderingTerm(
                    expression: candle.date,
                    mode: OrderingMode.asc,
                  ),
            ]))
          .get();
      final centDiv = symbolCentDivisor(symbol);
      final nativeRate = allRatesFromUsd[symbolCurrency(symbol)] ?? 1.0;
      pricesBySymbol[symbol] = {
        for (final candle in rows)
          DateTime(candle.date.year, candle.date.month, candle.date.day):
              candle.close / centDiv / nativeRate,
      };
    }

    final allDates = <DateTime>{};
    for (final prices in pricesBySymbol.values) {
      allDates.addAll(prices.keys);
    }
    final sortedDates = allDates.toList()..sort();

    final Map<String, double> lastKnown = {};
    final Map<DateTime, double> valueByDate = {};
    final Map<String, double> shares = currentHoldingsReplay
        ? {
            for (final position in positions)
              position.symbol: position.netShares,
          }
        : {};
    var tradeIndex = 0;

    for (final date in sortedDates) {
      while (tradeIndex < trades.length &&
          !DateTime(
            trades[tradeIndex].tradeDate.year,
            trades[tradeIndex].tradeDate.month,
            trades[tradeIndex].tradeDate.day,
          ).isAfter(date)) {
        final trade = trades[tradeIndex];
        shares[trade.symbol] = (shares[trade.symbol] ?? 0) + trade.quantity;
        tradeIndex++;
      }
      for (final symbol in symbols) {
        final price = pricesBySymbol[symbol]?[date];
        if (price != null) lastKnown[symbol] = price;
      }

      var total = 0.0;
      var hasHoldings = false;
      var complete = true;
      for (final entry in shares.entries) {
        if (entry.value.abs() < 1e-9) continue;
        hasHoldings = true;
        final price = lastKnown[entry.key];
        if (price == null) {
          complete = false;
          break;
        }
        total += entry.value * price;
      }
      if (hasHoldings && complete) {
        valueByDate[date] = total + replayResidualUsd;
      }
    }

    final currentValueUsd = currentPortfolioValueUsd ?? currentHoldingsValueUsd;
    if (currentValueUsd.isFinite && currentValueUsd > 0) {
      valueByDate[DateTime(now.year, now.month, now.day)] = currentValueUsd;
    }

    var series = valueByDate.entries
        .map((entry) => _DateValue(entry.key, entry.value))
        .toList()
      ..sort(
        (firstPoint, secondPoint) =>
            firstPoint.date.compareTo(secondPoint.date),
      );

    if (days > 0 && series.length > days) {
      series = series.sublist(series.length - days);
    } else if (years > 0 || months > 5) {
      final Map<String, _DateValue> byWeek = {};
      for (final dv in series) {
        final key = '${dv.date.year}-${_isoWeek(dv.date)}';
        final existing = byWeek[key];
        if (existing == null || dv.date.isAfter(existing.date)) {
          byWeek[key] = dv;
        }
      }
      series = byWeek.values.toList()
        ..sort(
          (firstPoint, secondPoint) =>
              firstPoint.date.compareTo(secondPoint.date),
        );
    }

    return (series: series, currentHoldingsReplay: currentHoldingsReplay);
  }

  ({List<_DateValue> series, double twrPercent, double returnAmount})
      _buildBrokerPerformanceSeries(
    IbkrPerformanceSeries performance,
    _LoadedChartPortfolio loaded,
  ) {
    if (performance.nav.isEmpty || performance.dates.isEmpty) {
      return (series: const [], twrPercent: 0, returnAmount: 0);
    }

    var basePerUsd = allRatesFromUsd[performance.currency] ?? 1.0;
    final currentValue = loaded.currentValue;
    final exactCurrentValueUsd = loaded.currentValueUsd;
    if (currentValue != null &&
        exactCurrentValueUsd != null &&
        exactCurrentValueUsd > 0 &&
        currentValue.currency == performance.currency) {
      basePerUsd = currentValue.value / exactCurrentValueUsd;
    }
    if (!basePerUsd.isFinite || basePerUsd <= 0) basePerUsd = 1.0;

    final points = <_DateValue>[];
    final fundedFirstNav = performance.nav.first != 0;
    if (performance.startDate != null &&
        performance.startNav != null &&
        performance.startDate!.weekday != DateTime.saturday &&
        performance.startDate!.weekday != DateTime.sunday &&
        !(performance.startNav == 0 && fundedFirstNav)) {
      points.add(
        _DateValue(performance.startDate!, performance.startNav! / basePerUsd),
      );
    }
    for (var index = 0; index < performance.dates.length; index++) {
      final date = performance.dates[index];
      if (date.weekday == DateTime.saturday ||
          date.weekday == DateTime.sunday) {
        continue;
      }
      points.add(
        _DateValue(
          date,
          performance.nav[index] / basePerUsd,
        ),
      );
    }
    points.sort(
      (firstPoint, secondPoint) => firstPoint.date.compareTo(secondPoint.date),
    );
    if (points.isEmpty) {
      return (series: const [], twrPercent: 0, returnAmount: 0);
    }

    final anchor = points.last.date;
    int baselineIndex;
    if (days > 0) {
      baselineIndex =
          (points.length - days).clamp(0, points.length - 1).toInt();
    } else {
      final cutoff = DateTime(
        anchor.year - years,
        anchor.month - months,
        anchor.day,
      );
      baselineIndex = 0;
      for (var index = 0; index < points.length; index++) {
        if (!points[index].date.isAfter(cutoff)) baselineIndex = index;
      }
    }

    final historicalSeries = points.sublist(baselineIndex);
    final baselineDate = historicalSeries.first.date;
    final historicalEndDate = historicalSeries.last.date;
    final cashFlows = performance.cashFlows.length == performance.dates.length
        ? performance.cashFlows
        : List<double>.filled(performance.dates.length, 0);
    var externalFlowsUsd = 0.0;
    for (var index = 0; index < performance.dates.length; index++) {
      final date = performance.dates[index];
      if (date.isAfter(baselineDate) && !date.isAfter(historicalEndDate)) {
        externalFlowsUsd += cashFlows[index] / basePerUsd;
      }
    }
    final returnAmount = historicalSeries.last.value -
        historicalSeries.first.value -
        externalFlowsUsd;

    final series = historicalSeries;

    var startReturn = 0.0;
    var endReturn = 0.0;
    for (var index = 0; index < performance.returnDates.length; index++) {
      final value = performance.returns[index];
      if (!performance.returnDates[index].isAfter(baselineDate)) {
        startReturn = value;
      }
      endReturn = value;
    }
    final denominator = 1 + startReturn;
    final twr = denominator == 0 ? 0.0 : ((1 + endReturn) / denominator) - 1;
    return (series: series, twrPercent: twr * 100, returnAmount: returnAmount);
  }

  static int _isoWeek(DateTime date) {
    final startOfYear = DateTime(date.year, 1, 1);
    return (date.difference(startOfYear).inDays / 7).floor() + 1;
  }

  void _onSearchChanged(String text) {
    if (text.trim().isEmpty) {
      _yahooApi.cancelPendingSearch();
      setState(() {
        _mode = _ChartMode.portfolio;
        _searchResults = [];
        _searchLoading = false;
      });
      return;
    }
    setState(() {
      _mode = _ChartMode.searching;
      _searchLoading = true;
    });
    runDetachedTask(_runTickerSearch(text), 'Ticker search failed');
  }

  Future<void> _runTickerSearch(String text) async {
    if (!mounted || !widget.isActive) return;
    try {
      final results = await _yahooApi.searchTickers(text);
      if (!mounted || _searchController.text != text) return;
      setState(() {
        _searchResults = results;
        _searchLoading = false;
      });
    } catch (error, stackTrace) {
      talker.handle(error, stackTrace, 'Ticker search failed');
      if (!mounted || _searchController.text != text) return;
      setState(() => _searchLoading = false);
    }
  }

  void _selectStock(StockResult result) => _selectSymbol(result.symbol);

  void _selectFavorite(String symbol) {
    _searchController.value = TextEditingValue(
      text: symbol,
      selection: TextSelection.collapsed(offset: symbol.length),
    );
    _selectSymbol(symbol);
  }

  void _selectSymbol(String symbol) {
    _searchFocus.unfocus();
    setState(() {
      _mode = _ChartMode.stock;
      _selectedSymbol = symbol;
      _networkLoading = true;
      _stockError = null;
    });
    _setStockStream(symbol);
    runDetachedTask(
      () async {
        String? err;
        try {
          final accountManager = context.read<AccountManager>();
          await syncCandles(
            symbol,
            ibkrConfig: accountManager.ibkrConfigFor(),
            syncNamespace: accountManager.activeAccount,
            requiredFrom: _requiredCandleStart(),
          );
        } catch (error, stackTrace) {
          talker.handle(error, stackTrace, 'Selected ticker sync failed');
          err = error.toString();
        }
        await fetchSymbolCurrencyAndRate(symbol);
        if (!mounted) return;
        _setStockStream(symbol);
        setState(() {
          _networkLoading = false;
          _stockError = err;
          _nativeCurrency = symbolCurrency(symbol);
          _centDivisor = symbolCentDivisor(symbol);
        });
      }(),
      'Failed to load selected ticker',
    );
  }

  DateTime _requiredCandleStart() {
    final now = DateTime.now();
    return days > 0
        ? DateTime(now.year, now.month, now.day - days - 4)
        : DateTime(now.year - years, now.month - months, now.day - 1);
  }

  void _setStockStream(String symbol) {
    if (!widget.isActive) {
      _stockStream = null;
      return;
    }
    final after = _requiredCandleStart();
    final marketSymbol = canonicalMarketSymbol(symbol);

    const weekExpression = CustomExpression<String>(
      "STRFTIME('%Y-%m-%W', DATE(\"date\", 'unixepoch', 'localtime'))",
    );
    Iterable<Expression<Object>> groupBy = [
      marketDataDatabase.candles.date,
    ];
    if (years > 0 || months > 5) groupBy = [weekExpression];

    final capturedDays = days;
    _stockStream = (marketDataDatabase.selectOnly(marketDataDatabase.candles)
          ..addColumns([
            marketDataDatabase.candles.date,
            marketDataDatabase.candles.close,
          ])
          ..where(
            marketDataDatabase.candles.symbol.equals(marketSymbol) &
                marketDataDatabase.candles.date.isBiggerThanValue(after),
          )
          ..orderBy([
            OrderingTerm(
              expression: marketDataDatabase.candles.date,
              mode: OrderingMode.asc,
            ),
          ])
          ..groupBy(groupBy))
        .watch()
        .map((results) {
      var list = results
          .map(
            (result) => CandleTicker(
              candle: CandlesCompanion(
                date: Value(result.read(marketDataDatabase.candles.date)!),
                close: Value(
                  result.read(marketDataDatabase.candles.close)!,
                ),
              ),
            ),
          )
          .toList();
      if (capturedDays > 0 && list.length > capturedDays) {
        list = list.sublist(list.length - capturedDays);
      }
      return list;
    });
    setState(() {});
  }

  void _onPeriodSelected({
    int selectedYears = 0,
    int selectedMonths = 0,
    int selectedDays = 0,
  }) {
    setState(() {
      years = selectedYears;
      months = selectedMonths;
      days = selectedDays;
    });
    runDetachedTask(_savePeriod(), 'Failed to save chart period');
    if (_mode == _ChartMode.stock && _selectedSymbol != null) {
      final symbol = _selectedSymbol!;
      _setStockStream(symbol);
      runDetachedTask(
        () async {
          final accountManager = context.read<AccountManager>();
          await syncCandles(
            symbol,
            ibkrConfig: accountManager.ibkrConfigFor(),
            syncNamespace: accountManager.activeAccount,
            requiredFrom: _requiredCandleStart(),
          );
          if (mounted &&
              widget.isActive &&
              _mode == _ChartMode.stock &&
              _selectedSymbol == symbol) {
            _setStockStream(symbol);
          }
        }(),
        'Failed to backfill selected chart period',
      );
    } else {
      runDetachedTask(
        () async {
          await _syncCandlesInBackground();
          await _loadAllPortfolios();
        }(),
        'Failed to reload portfolios for chart period',
      );
    }
  }

  void _clearSearch() {
    _searchController.clear();
    _searchFocus.unfocus();
    _yahooApi.cancelPendingSearch();
    setState(() {
      _mode = _ChartMode.portfolio;
      _searchResults = [];
      _selectedSymbol = null;
      _searchLoading = false;
      _stockError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final settings = context.watch<SettingsState>();

    final accountColors = [
      Theme.of(context).colorScheme.primary,
      Theme.of(context).colorScheme.secondary,
      Theme.of(context).colorScheme.tertiary,
      Theme.of(context).colorScheme.onSurface,
      Color(0xFFE91E63),
      Color(0xFF00BCD4),
      Color(0xFFFF5722),
      Color(0xFF607D8B),
    ];
    final hasText = _searchController.text.isNotEmpty;

    // The chart fills the available height so the Drafter tooltip overlay can
    // render above its data points without being obscured by the search bar.
    return PopScope<void>(
      canPop: !hasText,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (hasText) _clearSearch();
      },
      child: Stack(
        children: [
          if (_mode == _ChartMode.searching)
            Padding(
              padding: EdgeInsets.only(top: _overlayHeight + 8),
              child: _buildSearchResults(),
            )
          else
            _buildChartContent(settings, accountColors),
          Align(
            alignment: Alignment.topCenter,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // The page can briefly receive tiny constraints while a desktop
                // window is being created or resized. SearchBar has a minimum
                // interactive height, so laying it out in that space produces a
                // RenderFlex overflow. It is safe to defer this visual overlay:
                // the next real layout re-measures and displays it normally.
                if (constraints.maxHeight < 72 || constraints.maxWidth < 120) {
                  return const SizedBox.shrink();
                }

                return NotificationListener<SizeChangedLayoutNotification>(
                  onNotification: (_) {
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _measureOverlay(),
                    );
                    return true;
                  },
                  child: SizeChangedLayoutNotifier(
                    child: Column(
                      key: _overlayKey,
                      mainAxisSize: MainAxisSize.min,
                      children: [_buildSearchBar()],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final hasText = _searchController.text.isNotEmpty;
    final desktop = isDesktopLayout(context);
    final leading = hasText
        ? IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: context.l10n.text('Back'),
            padding: const EdgeInsets.only(left: 16, right: 8),
            onPressed: _clearSearch,
          )
        : const Padding(
            padding: EdgeInsets.only(left: 16, right: 8),
            child: Icon(Icons.search),
          );

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: desktop ? 760 : double.infinity),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            desktop ? 24 : 8,
            8,
            desktop ? 24 : 8,
            4,
          ),
          child: SearchBar(
            controller: _searchController,
            focusNode: _searchFocus,
            hintText: context.l10n.text('Search stocks...'),
            leading: leading,
            onChanged: _onSearchChanged,
            onTap: () => _searchController.selection = TextSelection(
              baseOffset: 0,
              extentOffset: _searchController.text.length,
            ),
            onSubmitted: (text) {
              if (text.isNotEmpty) _onSearchChanged(text);
            },
            trailing: [
              if (desktop && _mode != _ChartMode.searching)
                IconButton(
                  onPressed: _networkLoading ? null : _refreshCurrentChart,
                  tooltip: context.l10n.text('Refresh'),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              if (!desktop)
                IconButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsPage()),
                  ),
                  tooltip: context.l10n.text('Settings'),
                  icon: const Icon(Icons.settings),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    final query = _searchController.text.trim().toUpperCase();
    if (query.isEmpty) return const SizedBox.shrink();

    // "Use anyway" tile — always shown so a known symbol remains usable even
    // while Yahoo search is slow or unavailable (e.g. GLD).
    final useAnywayTile = ListTile(
      leading: const Icon(Icons.open_in_new),
      title: Text(context.l10n.text('Use "{query}" anyway', {'query': query})),
      subtitle: Text(context.l10n.text('Load chart for this exact ticker')),
      onTap: () => _selectSymbol(query),
    );

    return RefreshIndicator(
      triggerMode: RefreshIndicatorTriggerMode.anywhere,
      onRefresh: () => _runTickerSearch(_searchController.text),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: bottomNavScrollClearance),
        itemCount: _searchLoading || _searchResults.isEmpty
            ? 1
            : _searchResults.length + 1,
        itemBuilder: (context, index) {
          if (_searchLoading ||
              _searchResults.isEmpty ||
              index == _searchResults.length) {
            return useAnywayTile;
          }
          final result = _searchResults[index];
          final name =
              result.longname.isNotEmpty ? result.longname : result.shortname;
          return ListTile(
            title: Text(result.symbol),
            subtitle: Text(name),
            trailing: Text(
              result.exchange,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            onTap: () => _selectStock(result),
          );
        },
      ),
    );
  }

  bool _isMarketClosed() {
    final weekday = DateTime.now().weekday;
    return weekday == DateTime.saturday || weekday == DateTime.sunday;
  }

  Widget _buildMarketClosedBanner(SettingsState settings) {
    return GestureDetector(
      onLongPress: () {
        runDetachedTask(
          settings.setShowMarketClosed(false),
          'Failed to hide market-closed indicator',
        );
        toast(
          context,
          'Market closed indicator hidden',
          SnackBarAction(
            label: context.l10n.text('Undo'),
            onPressed: () => runDetachedTask(
              settings.setShowMarketClosed(true),
              'Failed to restore market-closed indicator',
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.schedule,
                  size: 14,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 6),
                Text(
                  'Market closed',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChartContent(SettingsState settings, List<Color> accountColors) {
    final desktop = isDesktopLayout(context);
    return RefreshIndicator(
      triggerMode: RefreshIndicatorTriggerMode.anywhere,
      onRefresh: _refreshCurrentChart,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          top: _overlayHeight + 8,
          bottom: desktop ? 24 : bottomNavScrollClearance,
        ),
        children: [
          _buildTimeChips(),
          if (settings.showMarketClosed && _isMarketClosed()) ...[
            const SizedBox(height: 8),
            _buildMarketClosedBanner(settings),
          ],
          if (_mode == _ChartMode.stock)
            ..._buildStockContent(settings)
          else
            ..._buildPortfolioContent(settings, accountColors),
        ],
      ),
    );
  }

  Widget _buildTimeChips() {
    final options = [
      ('5d', 0, 0, 5),
      ('1m', 0, 1, 0),
      ('2m', 0, 2, 0),
      ('3m', 0, 3, 0),
      ('6m', 0, 6, 0),
      ('1y', 1, 0, 0),
      ('2y', 2, 0, 0),
      ('3y', 3, 0, 0),
      ('5y', 5, 0, 0),
      ('10y', 10, 0, 0),
    ];

    return Center(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            for (final (label, optionYears, optionMonths, optionDays)
                in options)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _PeriodChip(
                  label: label,
                  selected: optionYears == years &&
                      optionMonths == months &&
                      optionDays == days,
                  onTap: () => _onPeriodSelected(
                    selectedYears: optionYears,
                    selectedMonths: optionMonths,
                    selectedDays: optionDays,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildStockContent(SettingsState settings) {
    return [
      StreamBuilder(
        stream: _stockStream,
        builder: (context, snapshot) =>
            _buildStockChart(context, snapshot, settings),
      ),
      StreamBuilder(stream: _stockStream, builder: _buildStockSummary),
    ];
  }

  Widget _buildStockChart(
    BuildContext context,
    AsyncSnapshot<List<CandleTicker>> snapshot,
    SettingsState settings,
  ) {
    final height = MediaQuery.of(context).size.height * 0.35;
    if (snapshot.hasError) {
      return SizedBox(
        height: height,
        child: Center(child: Text(snapshot.error.toString())),
      );
    }
    if (snapshot.data == null || snapshot.data!.isEmpty) {
      if (_stockError != null) {
        return SizedBox(
          height: height,
          child: Center(child: Text(_stockError!)),
        );
      }
      return SizedBox(height: height, child: const Center());
    }

    final candles = snapshot.data!.map((tc) => tc.candle).toList();
    final spots = <MarketLineChartPoint>[
      for (var index = 0; index < candles.length; index++)
        MarketLineChartPoint(
          index.toDouble(),
          candles[index].close.value / _centDivisor,
          column: index,
        ),
    ];

    return SizedBox(
      height: height,
      child: TickerLine(
        dates: candles.map((candle) => candle.date.value),
        spots: spots,
        nativeCurrency: _nativeCurrency,
      ),
    );
  }

  Widget _buildStockSummary(
    BuildContext context,
    AsyncSnapshot<List<CandleTicker>> snapshot,
  ) {
    if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox();

    final candles = snapshot.data!.map((tc) => tc.candle).toList();
    final pct = safePercentChange(
      candles.first.close.value,
      candles.last.close.value,
    );
    final color = pct >= 0 ? Colors.green : Colors.redAccent;
    final symbol = _selectedSymbol ?? '';
    final dollarChange =
        (candles.last.close.value - candles.first.close.value) / _centDivisor;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktopLayout(context) ? 32 : 16,
        vertical: 8,
      ),
      child: Column(
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    pct >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                    color: color,
                  ),
                  Text(
                    '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge!
                        .copyWith(color: color),
                  ),
                ],
              ),
              Text(
                fmtNativeCurrency(
                  candles.last.close.value / _centDivisor,
                  _nativeCurrency,
                ),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            context.l10n.text('{value} period change', {
              'value':
                  '${dollarChange >= 0 ? '+' : ''}${fmtNativeCurrency(dollarChange, _nativeCurrency)}',
            }),
            style: TextStyle(color: color, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              _ActionChip(
                icon: Icons.add,
                label: context.l10n.text('Add trade'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditTickerPage(symbol: symbol),
                  ),
                ),
              ),
              _ActionChip(
                icon: _favoriteStocks.contains(symbol)
                    ? Icons.favorite
                    : Icons.favorite_border,
                label: context.l10n.text('Favorite'),
                onTap: () => _toggleFavorite(symbol),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPortfolioContent(
    SettingsState settings,
    List<Color> accountColors,
  ) {
    return [
      _buildFavoritesRow(),
      _buildPortfolioChart(context, settings, accountColors),
      _buildPortfolioSummary(context, settings, accountColors),
    ];
  }

  Widget _buildFavoritesRow() {
    if (_favoriteStocks.isEmpty) return const SizedBox.shrink();
    return Padding(
      // The period selector sits immediately above this row. Give the cards a
      // clear separation without making the landing page feel oversized.
      padding: EdgeInsets.fromLTRB(
        isDesktopLayout(context) ? 24 : 16,
        16,
        isDesktopLayout(context) ? 24 : 16,
        8,
      ),
      child: SizedBox(
        height: 64,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: _favoriteStocks.length,
          itemBuilder: (context, index) {
            final symbol = _favoriteStocks[index];
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _FavoriteCard(
                symbol: symbol,
                isActive: widget.isActive,
                onTap: () => _selectFavorite(symbol),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPortfolioChart(
    BuildContext context,
    SettingsState settings,
    List<Color> accountColors,
  ) {
    final height = MediaQuery.of(context).size.height * 0.30;

    if (_portfolioLoading) {
      return SizedBox(
        height: height,
        child: Center(
          child: Semantics(
            label: context.l10n.text('Loading portfolio'),
            child: const CircularProgressIndicator(),
          ),
        ),
      );
    }
    if (_portfolioError != null && _portfolioSeriesByAccount.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(child: Text(_portfolioError!)),
      );
    }

    final accountManager = context.read<AccountManager>();
    final accounts = accountManager.accounts;
    final visibleSeries = {
      for (final entry in _portfolioSeriesByAccount.entries)
        if (!_hiddenAccounts.contains(entry.key) && entry.value.isNotEmpty)
          entry.key: entry.value,
    };

    if (visibleSeries.isEmpty) {
      final allEmpty = _portfolioSeriesByAccount.values.every(
        (series) => series.isEmpty,
      );
      return SizedBox(
        height: height,
        child: AppEmptyState(
          icon: allEmpty
              ? Icons.candlestick_chart_rounded
              : Icons.visibility_off_rounded,
          title: allEmpty
              ? context.l10n.text('No trades yet')
              : context.l10n.text('All portfolios are hidden'),
          message: allEmpty
              ? context.l10n.text(
                  'Search for a stock to start building your portfolio history.',
                )
              : context.l10n.text(
                  'Show your portfolios again to restore the chart.',
                ),
          actionLabel: allEmpty
              ? context.l10n.text('Search stocks')
              : context.l10n.text('Show all'),
          actionIcon:
              allEmpty ? Icons.search_rounded : Icons.visibility_rounded,
          onAction: () {
            if (allEmpty) {
              setState(() => _mode = _ChartMode.searching);
              _searchFocus.requestFocus();
            } else {
              setState(_hiddenAccounts.clear);
            }
          },
        ),
      );
    }

    final allDates = <DateTime>{};
    for (final series in visibleSeries.values) {
      for (final point in series) {
        allDates.add(point.date);
      }
    }
    final sortedDates = allDates.toList()..sort();
    final dateIndex = <DateTime, int>{
      for (var index = 0; index < sortedDates.length; index++)
        sortedDates[index]: index,
    };

    final singleLine = visibleSeries.length == 1;
    final scaleForComparison = !singleLine;
    final chartSeries = <MarketLineChartSeries>[];
    for (final entry in visibleSeries.entries) {
      final accountIndex = accounts.indexOf(entry.key);
      final color =
          accountColors[accountIndex.clamp(0, accountColors.length - 1)];
      final displayValues = scaleForComparison
          ? scalePortfolioSeriesForComparison(
              entry.value.map((point) => point.value),
            )
          : entry.value.map((point) => point.value).toList(growable: false);
      chartSeries.add(
        MarketLineChartSeries(
          name: entry.key,
          color: color,
          strokeWidth: 2.5,
          fill: true,
          points: [
            for (var index = 0; index < entry.value.length; index++)
              MarketLineChartPoint(
                dateIndex[entry.value[index].date]!.toDouble(),
                displayValues[index],
                column: dateIndex[entry.value[index].date]!,
              ),
          ],
        ),
      );
    }

    final formatter = DateFormat(settings.dateFormat);
    final visibleKeys = visibleSeries.keys.toList();

    return SizedBox(
      height: height,
      child: MarketLineChart(
        series: chartSeries,
        xLabels: [for (final date in sortedDates) formatter.format(date)],
        pointCount: sortedDates.length,
        yLabelFormatter: (value) => scaleForComparison
            ? fmtChartAxisPercent(value)
            : fmtCompactCurrency(value),
        tooltipRowLabel: (PlotMark mark) {
          final accountName = mark.seriesIndex < visibleKeys.length
              ? visibleKeys[mark.seriesIndex]
              : '';
          final date = mark.index >= 0 && mark.index < sortedDates.length
              ? sortedDates[mark.index]
              : null;
          double? actualValue;
          if (date != null) {
            for (final point
                in visibleSeries[accountName] ?? const <_DateValue>[]) {
              if (point.date == date) {
                actualValue = point.value;
                break;
              }
            }
          }
          final valueLabel = fmtCurrency(actualValue ?? mark.value);
          final dateLabel = date == null ? '' : formatter.format(date);
          return dateLabel.isEmpty ? valueLabel : '$valueLabel · $dateLabel';
        },
        curveLines: settings.curveLines,
        curveSmoothness: settings.curveSmoothness,
        leftInset: scaleForComparison ? 72 : 64,
        accessibilityLabel: context.l10n.text('Portfolio performance'),
        accessibilityValue:
            '${chartSeries.length} ${context.l10n.text('portfolios')}',
      ),
    );
  }

  Widget _buildPortfolioSummary(
    BuildContext context,
    SettingsState settings,
    List<Color> accountColors,
  ) {
    final accounts = context.read<AccountManager>().accounts;
    final allSeries = {
      for (final entry in _portfolioSeriesByAccount.entries)
        if (entry.value.isNotEmpty) entry.key: entry.value,
    };
    if (allSeries.isEmpty) return const SizedBox();

    return Padding(
      key: const Key('portfolio-summary-content'),
      padding: EdgeInsets.symmetric(
        horizontal: isDesktopLayout(context) ? 32 : 16,
        vertical: 8,
      ),
      child: Column(
        children: [
          for (final entry in allSeries.entries)
            _buildAccountSummaryRow(
              context,
              accounts,
              entry.key,
              entry.value,
              accountColors,
            ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<String>(
                value: settings.displayCurrency,
                isDense: true,
                underline: const SizedBox(),
                items: settings.visibleCurrencies
                    .map(
                      (currencyCode) => DropdownMenuItem(
                        value: currencyCode,
                        child: Text(currencyCode),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    runDetachedTask(
                      settings.setDisplayCurrency(value),
                      'Failed to change display currency',
                    );
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAccountSummaryRow(
    BuildContext context,
    List<String> accounts,
    String accountName,
    List<_DateValue> series,
    List<Color> accountColors,
  ) {
    final idx = accounts.indexOf(accountName);
    final dotColor = accountColors[idx.clamp(0, accountColors.length - 1)];
    final brokerReturn = _portfolioReturnsByAccount[accountName];
    final brokerReturnAmount = _portfolioReturnAmountsByAccount[accountName];
    final hasHistory = brokerReturn != null || series.length > 1;
    final pct = brokerReturn ??
        (hasHistory
            ? safePercentChange(series.first.value, series.last.value)
            : 0.0);
    final returnColor = hasHistory
        ? (pct >= 0 ? Colors.green : Colors.redAccent)
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final change =
        brokerReturnAmount ?? (series.last.value - series.first.value);
    final isHidden = _hiddenAccounts.contains(accountName);
    final accountManager = context.read<AccountManager>();
    final cachedPortfolio = accountManager.portfolioCacheFor(accountName);
    var currentValueUsd = cachedPortfolio?.netLiquidationUsd;
    final netLiquidation = cachedPortfolio?.netLiquidation;
    if ((currentValueUsd == null || !currentValueUsd.isFinite) &&
        netLiquidation != null) {
      if (netLiquidation.currency == 'USD') {
        currentValueUsd = netLiquidation.value;
      } else {
        final basePerUsd = allRatesFromUsd[netLiquidation.currency];
        if (basePerUsd != null && basePerUsd.isFinite && basePerUsd > 0) {
          currentValueUsd = netLiquidation.value / basePerUsd;
        }
      }
    }
    final summaryValue = currentValueUsd != null && currentValueUsd.isFinite
        ? currentValueUsd
        : series.last.value;
    final theme = Theme.of(context);

    Widget accountLabel() => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration:
                  BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                accountName,
                style: theme.textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );

    Widget returnLabel() => Text(
          hasHistory
              ? '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%'
              : context.l10n.text('History unavailable'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium!.copyWith(color: returnColor),
        );

    final valueText = Text(
      fmtCurrency(summaryValue),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.right,
      style: theme.textTheme.titleMedium,
    );
    final changeText = Text(
      hasHistory
          ? '${change >= 0 ? '+' : ''}${fmtCurrency(change)}'
          : context.l10n.text('Historical prices unavailable'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: returnColor, fontSize: 13),
    );

    return GestureDetector(
      onTap: () => setState(() {
        if (isHidden) {
          _hiddenAccounts.remove(accountName);
        } else {
          _hiddenAccounts.add(accountName);
        }
      }),
      child: AnimatedOpacity(
        opacity: isHidden ? 0.35 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 900;
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(child: accountLabel()),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: valueText,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(child: returnLabel()),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: changeText,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: accountLabel(),
                    ),
                  ),
                  Expanded(child: Center(child: returnLabel())),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        valueText,
                        const SizedBox(height: 2),
                        changeText,
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

class _DateValue {
  final DateTime date;
  final double value;

  const _DateValue(this.date, this.value);
}

/// A chip button styled after Flexify's DaySelector — animated border
/// highlights the selected state.
class _PeriodChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.7)
              : colorScheme.outline.withValues(alpha: 0.3),
          width: selected ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Center(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
                child: Text(label),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A chip-styled action button (no toggle state, always consistent border).
class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small card showing a favorited symbol's latest price and day change,
/// used in the favorites row on the portfolio landing view.
class _FavoriteCard extends StatelessWidget {
  final String symbol;
  final bool isActive;
  final VoidCallback onTap;

  const _FavoriteCard({
    required this.symbol,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final stream = isActive
        ? (marketDataDatabase.candles.select()
              ..where((candle) => candle.symbol.equals(symbol))
              ..orderBy([
                (candle) => OrderingTerm(
                      expression: candle.date,
                      mode: OrderingMode.desc,
                    ),
              ])
              ..limit(2))
            .watch()
        : const Stream<List<StoredCandle>>.empty();

    return Container(
      width: 92,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  symbol,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                StreamBuilder<List<StoredCandle>>(
                  stream: stream,
                  builder: (context, snapshot) {
                    final candles = snapshot.data;
                    if (candles == null || candles.isEmpty) {
                      return const SizedBox(height: 14, width: 14);
                    }
                    final centDivisor = symbolCentDivisor(symbol);
                    final price = candles.first.close / centDivisor;
                    final pct = candles.length > 1
                        ? safePercentChange(
                            candles[1].close,
                            candles.first.close,
                          )
                        : null;
                    final changeColor =
                        (pct ?? 0) >= 0 ? Colors.green : Colors.redAccent;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fmtNativeCurrency(price, symbolCurrency(symbol)),
                          style: const TextStyle(fontSize: 11, height: 1),
                        ),
                        if (pct != null)
                          Text(
                            '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%',
                            style: TextStyle(
                              fontSize: 10,
                              height: 1,
                              color: changeColor,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
