import 'dart:async';
import 'dart:math';
import 'dart:math' show max, min;

import 'package:drafter/drafter.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:market_monk/adaptive_layout.dart';
import 'package:market_monk/background_network_coordinator.dart';
import 'package:market_monk/bottom_nav.dart';
import 'package:market_monk/candle_ticker.dart';
import 'package:market_monk/chart_colors.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/desktop_context_menu.dart';
import 'package:market_monk/edit_ticker_page.dart';
import 'package:market_monk/empty_state.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/intraday_market_data.dart';
import 'package:market_monk/intraday_portfolio.dart';
import 'package:market_monk/l10n/app_localizations.dart';
import 'package:market_monk/logging.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/market_data_store.dart';
import 'package:market_monk/market_line_chart.dart';
import 'package:market_monk/portfolio_chart_scale.dart';
import 'package:market_monk/provisional_portfolio.dart';
import 'package:market_monk/profile_data_repository.dart';
import 'package:market_monk/settings_page.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/sqlite_settings.dart';
import 'package:market_monk/ticker_line.dart';
import 'package:market_monk/utils.dart';
import 'package:provider/provider.dart';

enum _ChartMode { portfolio, searching, stock }

class _LoadedChartPortfolio {
  final List<Position> positions;
  final IbkrAccountValue? currentValue;
  final double? currentValueUsd;
  final DateTime? asOfDate;
  final DateTime? cachedAt;

  const _LoadedChartPortfolio({
    required this.positions,
    required this.currentValue,
    required this.currentValueUsd,
    this.asOfDate,
    this.cachedAt,
  });
}

class _CachedIntradayPortfolio {
  final Map<String, List<_DateValue>> series;
  final String? error;
  const _CachedIntradayPortfolio(this.series, this.error);
}

class _CachedChartPeriod {
  final Map<String, List<_DateValue>> series;
  final Map<String, List<_DateValue>> returns;
  final Map<String, Map<DateTime, double>> flows;
  final Map<String, IntradaySeries> favorites;
  final Map<String, String> favoriteErrors;
  final Set<String> dailyPreviews;
  final Map<String, DateTime> provisionalStarts;
  final List<StoredCandle> candles;
  final String? error;

  const _CachedChartPeriod({
    required this.series,
    required this.returns,
    required this.flows,
    required this.favorites,
    required this.favoriteErrors,
    required this.dailyPreviews,
    required this.provisionalStarts,
    required this.candles,
    required this.error,
  });
}

class ChartsPage extends StatefulWidget {
  final bool isActive;

  /// Ticker to display when opening a chart from another screen.
  final String? initialSymbol;
  final IntradayMarketData? _intradayData;
  final Future<IbkrPortfolioSnapshot> Function(IbkrAccountConfig)? _ibkrLoader;
  final Future<IbkrPerformanceSeries> Function(IbkrAccountConfig, String)?
      _ibkrPerformanceLoader;

  const ChartsPage({
    super.key,
    this.isActive = true,
    this.initialSymbol,
    IntradayMarketData? intradayData,
    Future<IbkrPortfolioSnapshot> Function(IbkrAccountConfig)? ibkrLoader,
    Future<IbkrPerformanceSeries> Function(IbkrAccountConfig, String)?
        ibkrPerformanceLoader,
  })  : _intradayData = intradayData,
        _ibkrLoader = ibkrLoader,
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
  Map<String, String> _favoriteNames = {};
  final Set<String> _selectedFavorites = {};
  Stream<List<StoredCandle>>? _favoriteChartStream;
  String _favoriteChartStreamKey = '';
  final _favoriteIntraday = <String, IntradaySeries>{};
  final _favoriteIntradayErrors = <String, String>{};
  int _favoriteLoadGeneration = 0;
  bool _networkLoading = false;
  String? _stockContentKey;
  int _pendingRemoteLoads = 0;

  Future<T> _withRemoteLoading<T>(Future<T> Function() load) async {
    if (mounted) setState(() => _pendingRemoteLoads++);
    try {
      return await load();
    } finally {
      if (mounted) setState(() => _pendingRemoteLoads--);
    }
  }

  bool get _showRollingAverage =>
      context.read<SettingsState>().showRollingAverage;
  bool get _showCandlesticks => context.read<SettingsState>().showCandlesticks;
  final ValueNotifier<int?> _candleSelection = ValueNotifier(null);
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
  double _chartBottomPadding = 0;

  int years = 1;
  int months = 0;
  int days = 0;
  (DateTime, DateTime)? _customChartRange;

  Stream<List<CandleTicker>>? _stockStream;
  late final _intradayData = widget._intradayData ?? IntradayMarketData();
  IntradaySeries? _intradaySeries;
  List<CandleTicker> _stockDailyPreview = const [];
  int _stockLoadGeneration = 0;

  bool get _usesIntraday =>
      years == 0 && months == 0 && (days == 1 || days == 5);

  Map<String, List<_DateValue>> _portfolioSeriesByAccount = {};
  Map<String, List<_DateValue>> _portfolioReturnSeriesByAccount = {};
  Map<String, Map<DateTime, double>> _portfolioCashFlowsByAccount = {};
  final _intradayPortfolioCache = <String, _CachedIntradayPortfolio>{};
  final _portfolioDailyPreviewAccounts = <String>{};
  final _provisionalStartByAccount = <String, DateTime>{};
  Timer? _provisionalRefreshTimer;
  bool _provisionalRefreshInFlight = false;
  String? _portfolioError;
  bool _portfolioLoading = true;
  bool _periodTransition = false;
  int _periodTransitionGeneration = 0;
  Widget? _lastPortfolioChart;
  final _chartPeriodCache = <String, _CachedChartPeriod>{};
  List<StoredCandle>? _restoredFavoriteCandles;
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
  final Map<(bool, bool, bool, bool, String), Future<void>> _portfolioLoads =
      {};

  @override
  void initState() {
    super.initState();
    runDetachedTask(_loadFavorites(), 'Failed to load chart favorites');
    runDetachedTask(
      _loadPeriodThenPortfolios(),
      'Failed to initialize chart period and portfolios',
    );
    _provisionalRefreshTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => runDetachedTask(
        _refreshProvisionalAccounts(),
        'Failed to refresh provisional account quotes',
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _measureOverlay();
      if (widget.initialSymbol != null) _selectSymbol(widget.initialSymbol!);
    });
  }

  @override
  void didUpdateWidget(covariant ChartsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive && !widget.isActive) {
      _candleSelection.value = null;
      _portfolioLoadGeneration++;
      _stockLoadGeneration++;
      _favoriteLoadGeneration++;
      _networkLoading = false;
      _stockStream = null;
      return;
    }
    if (!oldWidget.isActive && widget.isActive && _chartPeriodLoaded) {
      runDetachedTask(_loadFavorites(), 'Failed to reload favorites');
      final accountManager = context.read<AccountManager>();
      _hydratePortfolioSeriesFromCache(accountManager);
      if (_selectedSymbol != null) {
        runDetachedTask(_loadSelectedStock(), 'Failed to reload stock chart');
      }
      runDetachedTask(
        _syncCandlesInBackground(refreshPerformance: true),
        'Failed to refresh chart data after activation',
      );
    }
  }

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
      if (_selectedSymbol != null) {
        runDetachedTask(
          _loadSelectedStock(),
          'Failed to initialize stock period',
        );
        return;
      }
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

  void _hydratePortfolioSeriesFromCache(
    AccountManager accountManager, {
    bool replaceExisting = false,
  }) {
    if (!_chartPeriodLoaded ||
        _usesIntraday ||
        !replaceExisting && _portfolioSeriesByAccount.isNotEmpty) return;

    // The persisted IBKR performance cache is one year of history. It can
    // faithfully satisfy any selected period up to one year, but must never be
    // flashed for a longer saved period while the real series is rebuilding.
    if (years > 1 || (years == 1 && (months > 0 || days > 0))) return;

    final cachedSeries = <String, List<_DateValue>>{};
    final cachedReturns = <String, List<_DateValue>>{};
    final cachedFlows = <String, Map<DateTime, double>>{};

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
          asOfDate: cachedPortfolio.asOfDate,
        ),
      );
      if (brokerSeries.series.isEmpty) return;

      cachedSeries[accountName] = brokerSeries.series;
      cachedReturns[accountName] = brokerSeries.returnSeries;
      cachedFlows[accountName] = brokerSeries.cashFlowsByDate;
    }

    if (cachedSeries.length != accountManager.accounts.length) return;
    _portfolioSeriesByAccount = cachedSeries;
    _portfolioReturnSeriesByAccount = cachedReturns;
    _portfolioCashFlowsByAccount = cachedFlows;
    if (replaceExisting) {
      _portfolioDailyPreviewAccounts.clear();
      _provisionalStartByAccount.clear();
      _portfolioError = null;
    }
    _portfolioLoading = false;
  }

  Future<_LoadedChartPortfolio> _portfolioForAccount(
    String accountName,
    IbkrAccountConfig ibkrConfig,
    AccountManager accountManager, {
    bool refreshIbkr = false,
    bool forceIbkrRefresh = false,
  }) async {
    final trades = await profileDataRepository.readTradesForAccount(
      accountName,
    );
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
          asOfDate: cached.asOfDate,
          cachedAt: cached.cachedAt,
        );
      }
      if (!ibkrConfig.isConfigured) {
        if (cached != null) {
          return _LoadedChartPortfolio(
            positions: cached.positions,
            currentValue: cached.netLiquidation,
            currentValueUsd: cached.netLiquidationUsd,
            asOfDate: cached.asOfDate,
            cachedAt: cached.cachedAt,
          );
        }
        throw StateError('IBKR portfolio source is not fully configured');
      }
      if (!widget.isActive) {
        return _LoadedChartPortfolio(
          positions: cached?.positions ?? const [],
          currentValue: cached?.netLiquidation,
          currentValueUsd: cached?.netLiquidationUsd,
          asOfDate: cached?.asOfDate,
        );
      }

      final loadKey = [accountName, ibkrConfig.hashCode].join('|');
      try {
        return await _ibkrLoads.putIfAbsent(loadKey, () async {
          try {
            final snapshot = await _withRemoteLoading(
              () => (widget._ibkrLoader?.call(ibkrConfig) ??
                  IbkrApiClient(ibkrConfig).fetchPortfolio()),
            );
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
              asOfDate: snapshot.asOfDate,
            );
            return _LoadedChartPortfolio(
              positions: positions,
              currentValue: currentValue,
              currentValueUsd: currentValueUsd,
              asOfDate: snapshot.asOfDate,
              cachedAt: accountManager.portfolioCacheFor(accountName)?.cachedAt,
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
            asOfDate: cached.asOfDate,
            cachedAt: cached.cachedAt,
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
      final trades = await profileDataRepository.readTradesForAccount(
        accountName,
      );
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
      _portfolioLoads.clear();
      _backgroundSyncs.clear();
      runDetachedTask(
        _syncCandlesInBackground(
          refreshPerformance: true,
          forcePerformanceRefresh: ibkrChanged,
        ),
        'Failed to refresh charts after account change',
      );
    }
    _favoriteLoadGeneration++;
    _favoriteIntraday.clear();
    _favoriteIntradayErrors.clear();
    runDetachedTask(_syncFavoriteCandles(), 'Failed to reload favorite charts');
    if (_selectedSymbol != null) {
      runDetachedTask(
        _loadSelectedStock(forceRefresh: ibkrChanged),
        'Failed to reload stock after account change',
      );
    }
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
    _provisionalRefreshTimer?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    _candleSelection.dispose();
    _yahooApi.dispose();
    _stockLoadGeneration++;
    _favoriteLoadGeneration++;
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
        final trades = await profileDataRepository.readTradesForAccount(
          accountName,
        );
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

    if (_mode == _ChartMode.stock && _selectedSymbol != null) {
      await _loadSelectedStock(forceRefresh: true);
      return;
    }
    setState(() {
      _networkLoading = true;
      _stockError = null;
    });

    try {
      clearAllSyncCache();
      _intradayPortfolioCache.clear();
      _chartPeriodCache.clear();
      _restoredFavoriteCandles = null;
      await _refreshAllPortfolioCandles();
      await _loadAllPortfolios(
        refreshIbkrPortfolio: true,
        forceIbkrPortfolioRefresh: true,
      );
      if (mounted && widget.isActive) {
        runDetachedTask(
          _syncFavoriteCandles(forceRefresh: true),
          'Failed to refresh favorite charts',
        );
        runDetachedTask(
          _loadAllPortfolios(
            refreshIbkrPerformance: true,
            forceIbkrPerformanceRefresh: true,
          ),
          'Failed to refresh IBKR performance history',
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
    if (mounted) {
      setState(() {
        _favoriteStocks = favorites!;
        _favoriteNames = {
          for (final symbol in favorites)
            if (prefs.getString('favoriteName:$symbol') case final String name)
              symbol: name,
        };
      });
    }
    if (widget.isActive) {
      runDetachedTask(
        _syncFavoriteCandles(),
        'Failed to sync favorite ticker candles',
      );
    }
  }

  Future<void> _syncFavoriteCandles({
    bool forceRefresh = false,
    bool selectedOnly = false,
  }) async {
    final generation = _favoriteLoadGeneration;
    for (final symbol in _favoriteStocks) {
      if (selectedOnly && !_selectedFavorites.contains(symbol)) continue;
      if (!mounted || !widget.isActive || generation != _favoriteLoadGeneration)
        return;
      await _syncFavoriteCandle(symbol, forceRefresh: forceRefresh);
    }
  }

  Future<void> _syncFavoriteCandle(
    String symbol, {
    bool forceRefresh = false,
  }) async {
    if (!mounted || !widget.isActive) return;
    final generation = _favoriteLoadGeneration;
    final selectedDays = days;
    final intraday = _usesIntraday && _selectedFavorites.contains(symbol);
    try {
      final accountManager = context.read<AccountManager>();
      if (intraday) {
        final series = await _withRemoteLoading(
          () => _intradayData.fetch(
            symbol,
            days: selectedDays,
            config: accountManager.ibkrConfigFor(),
            forceRefresh: forceRefresh,
          ),
        );
        if (!mounted ||
            !widget.isActive ||
            generation != _favoriteLoadGeneration) return;
        await fetchSymbolCurrencyAndRate(symbol, rawCurrency: series.currency);
        if (!mounted ||
            !widget.isActive ||
            generation != _favoriteLoadGeneration) return;
        requireUsdRate(symbolCurrency(symbol));
        setState(() {
          _favoriteIntraday[symbol] = series;
          _favoriteIntradayErrors.remove(symbol);
        });
        return;
      }
      await _withRemoteLoading(
        () => syncCandles(
          symbol,
          ibkrConfig: accountManager.ibkrConfigFor(),
          syncNamespace: accountManager.activeAccount,
          requiredFrom: _requiredCandleStart(),
          forceRefresh: forceRefresh,
        ),
      );
    } catch (error, stackTrace) {
      talker.handle(error, stackTrace, 'Favorite ticker candle sync failed');
      if (intraday &&
          mounted &&
          widget.isActive &&
          generation == _favoriteLoadGeneration) {
        setState(() => _favoriteIntradayErrors[symbol] = error.toString());
      }
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
        _selectedFavorites.remove(symbol);
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
          final performance = await _withRemoteLoading(
            () => (widget._ibkrPerformanceLoader?.call(config, period) ??
                IbkrApiClient(config).fetchPerformance(period)),
          );
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

  Future<
      ({
        List<_DateValue> series,
        List<_DateValue> returnSeries,
        Map<DateTime, double> cashFlowsByDate,
      })?> _loadBrokerPerformanceSeries(
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
      return brokerSeries.series.isEmpty || brokerSeries.returnSeries.length < 2
          ? null
          : brokerSeries;
    } catch (error) {
      talker.warning(
        'IBKR performance history unavailable; '
        'showing current broker value only: $error',
      );
      return null;
    }
  }

  String get _intradayPortfolioCacheKey {
    final manager = context.read<AccountManager>();
    return '$days|${manager.ibkrRefreshVersion}|${context.read<SettingsState>().tradesVersion}|'
        '${manager.accounts.map((name) => '$name:${manager.ibkrConfigFor(name).hashCode}').join(',')}';
  }

  bool _restoreIntradayPortfolio() {
    if (!_usesIntraday) return false;
    final cached = _intradayPortfolioCache[_intradayPortfolioCacheKey];
    if (cached == null) return false;
    setState(() {
      _portfolioSeriesByAccount = Map.of(cached.series);
      _portfolioDailyPreviewAccounts.clear();
      _portfolioReturnSeriesByAccount.clear();
      _portfolioCashFlowsByAccount.clear();
      _portfolioError = cached.error;
      _portfolioLoading = false;
    });
    return true;
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
      '$years|$months|$_intradayPortfolioCacheKey',
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

  Map<String, List<_DateValue>> _cachedFiveDayPortfolioPreviews(
    AccountManager accountManager,
  ) {
    if (!_usesIntraday || days != 5) return {};
    final previews = <String, List<_DateValue>>{};
    for (final name in accountManager.accounts) {
      final portfolio = accountManager.portfolioCacheFor(name);
      final performance = accountManager.ibkrPerformanceCacheFor(name, '1Y');
      if (portfolio == null || performance == null) continue;
      final preview = _buildBrokerPerformanceSeries(
        performance,
        _LoadedChartPortfolio(
          positions: portfolio.positions,
          currentValue: portfolio.netLiquidation,
          currentValueUsd: portfolio.netLiquidationUsd,
          asOfDate: portfolio.asOfDate,
        ),
      ).series;
      if (preview.isNotEmpty) previews[name] = preview;
    }
    return previews;
  }

  Future<void> _performLoadAllPortfolios({
    bool refreshIbkrPerformance = false,
    bool forceIbkrPerformanceRefresh = false,
    bool refreshIbkrPortfolio = false,
    bool forceIbkrPortfolioRefresh = false,
  }) async {
    if (!mounted || !widget.isActive || !_chartPeriodLoaded) return;
    if (!forceIbkrPortfolioRefresh &&
        !forceIbkrPerformanceRefresh &&
        _restoreIntradayPortfolio()) return;
    final rangeCacheKey = _intradayPortfolioCacheKey;
    final generation = ++_portfolioLoadGeneration;
    final accountManager = context.read<AccountManager>();
    final accounts = accountManager.accounts;
    final fiveDayPreview = _usesIntraday && days == 5;
    final cachedPreviews = _cachedFiveDayPortfolioPreviews(accountManager);

    final newSeries = <String, List<_DateValue>>{
      for (final name in accounts) name: <_DateValue>[],
    };
    final dailyFallbacks = Map<String, List<_DateValue>>.of(cachedPreviews);
    setState(() {
      _portfolioError = null;
      _portfolioLoading = true;
    });

    bool isCurrent() =>
        mounted && widget.isActive && generation == _portfolioLoadGeneration;

    final newReturns = <String, List<_DateValue>>{};
    final newFlows = <String, Map<DateTime, double>>{};
    final loadedAccounts = <String, _LoadedChartPortfolio>{};
    String? firstError;

    Future<void> loadAccount(String accountName) async {
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
        loadedAccounts[accountName] = loaded;
        if (_usesIntraday) {
          if (fiveDayPreview && !dailyFallbacks.containsKey(accountName)) {
            try {
              final preview = await _buildPortfolioSeries(
                accountName,
                loaded.positions,
                currentPortfolioValueUsd: loaded.currentValueUsd,
              );
              if (preview.series.isNotEmpty) {
                dailyFallbacks[accountName] = preview.series;
              }
            } catch (error, stackTrace) {
              talker.handle(error, stackTrace, 'Daily preview unavailable');
            }
          }
          if (!isCurrent()) return;
          final series = await _buildIntradayPortfolioSeries(
            accountName,
            loaded,
            ibkrConfig,
            generation: generation,
            forceRefresh: forceIbkrPortfolioRefresh,
          );
          if (!isCurrent()) return;
          if (series.isNotEmpty) {
            newSeries[accountName] = series;
          }
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
            newReturns[accountName] = brokerSeries.returnSeries;
            newFlows[accountName] = brokerSeries.cashFlowsByDate;
            return;
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
          return;
        }

        final fallback = await _buildPortfolioSeries(
          accountName,
          loaded.positions,
        );
        newSeries[accountName] = fallback.series;
      } catch (error) {
        newSeries[accountName] ??= [];
        firstError ??= error.toString();
      }
    }

    if (_usesIntraday) {
      await Future.wait(accounts.map(loadAccount));
    } else {
      for (final account in accounts) {
        await loadAccount(account);
      }
    }

    if (!mounted ||
        !widget.isActive ||
        generation != _portfolioLoadGeneration) {
      return;
    }
    setState(() {
      _portfolioDailyPreviewAccounts.clear();
      if (fiveDayPreview) {
        for (final name in accounts) {
          if (newSeries[name]!.isEmpty &&
              dailyFallbacks[name]?.isNotEmpty == true) {
            newSeries[name] = dailyFallbacks[name]!;
            _portfolioDailyPreviewAccounts.add(name);
          }
        }
      }
      _portfolioSeriesByAccount = newSeries;
      _portfolioReturnSeriesByAccount = newReturns;
      _portfolioCashFlowsByAccount = newFlows;
      _portfolioError = firstError;
      _portfolioLoading = false;
      _provisionalStartByAccount.clear();
      if (_usesIntraday &&
          _portfolioDailyPreviewAccounts.isEmpty &&
          newSeries.values.any((series) => series.isNotEmpty)) {
        if (_intradayPortfolioCache.length >= 16)
          _intradayPortfolioCache.remove(_intradayPortfolioCache.keys.first);
        _intradayPortfolioCache[rangeCacheKey] = _CachedIntradayPortfolio(
          Map.of(newSeries),
          firstError,
        );
      }
    });
    if (!_usesIntraday) {
      for (final entry in loadedAccounts.entries) {
        final config = accountManager.ibkrConfigFor(entry.key);
        if (!config.enabled || newReturns[entry.key]?.isEmpty != false)
          continue;
        runDetachedTask(
          _loadProvisionalAccount(entry.key, entry.value, config, generation),
          'Failed to update provisional portfolio prices',
        );
      }
    }
  }

  Future<void> _refreshProvisionalAccounts() async {
    if (!mounted ||
        !widget.isActive ||
        _usesIntraday ||
        _mode != _ChartMode.portfolio ||
        _provisionalRefreshInFlight) return;
    _provisionalRefreshInFlight = true;
    try {
      final manager = context.read<AccountManager>();
      final generation = _portfolioLoadGeneration;
      await Future.wait(
        manager.accounts.map((name) async {
          final config = manager.ibkrConfigFor(name);
          final cached = manager.portfolioCacheFor(name);
          if (!config.enabled ||
              cached == null ||
              !_portfolioSeriesByAccount.containsKey(name)) return;
          await _loadProvisionalAccount(
            name,
            _LoadedChartPortfolio(
              positions: cached.positions,
              currentValue: cached.netLiquidation,
              currentValueUsd: cached.netLiquidationUsd,
              asOfDate: cached.asOfDate,
              cachedAt: cached.cachedAt,
            ),
            config,
            generation,
          );
        }),
      );
    } finally {
      _provisionalRefreshInFlight = false;
    }
  }

  Future<void> _loadProvisionalAccount(
    String name,
    _LoadedChartPortfolio loaded,
    IbkrAccountConfig config,
    int generation,
  ) async {
    bool isCurrent() =>
        mounted &&
        widget.isActive &&
        generation == _portfolioLoadGeneration &&
        !_usesIntraday;
    final existing = _portfolioSeriesByAccount[name];
    if (existing == null || existing.isEmpty || loaded.positions.isEmpty)
      return;
    final provisionalStart = _provisionalStartByAccount[name];
    final official = provisionalStart == null
        ? existing
        : existing
            .where((point) => point.date.isBefore(provisionalStart))
            .toList();
    if (official.isEmpty) return;
    final anchor = official.last;
    final brokerDay = usSessionDateFromDisplayDay(anchor.date);
    final now = DateTime.now();
    if (anchor.date.isAfter(now) || now.difference(anchor.date).inDays > 14) {
      return;
    }
    final positions = loaded.positions.where((p) => p.netShares != 0).toList();
    if (positions.isEmpty) return;
    final from = brokerDay.subtract(const Duration(days: 4));
    for (var start = 0; start < positions.length; start += 4) {
      if (!isCurrent()) return;
      await Future.wait(
        positions.skip(start).take(4).map((position) async {
          try {
            await syncCandles(
              position.symbol,
              ibkrConfig: config,
              syncNamespace: name,
              requiredFrom: from,
            );
          } catch (error) {
            talker.warning(
              'Provisional price unavailable for ${position.symbol}: $error',
            );
          }
        }),
      );
    }
    if (!isCurrent()) return;
    final holdings = <ProvisionalHolding>[];
    for (final position in positions) {
      final rows = await (marketDataDatabase.candles.select()
            ..where(
              (c) =>
                  c.symbol.equals(canonicalMarketSymbol(position.symbol)) &
                  c.date.isBiggerThanValue(from),
            )
            ..orderBy([(c) => OrderingTerm.asc(c.date)]))
          .get();
      if (rows.isEmpty) return;
      final rate = requireUsdRate(position.nativeCurrency);
      final divisor = symbolCentDivisor(position.symbol);
      holdings.add(
        ProvisionalHolding(
          shares: position.netShares,
          closesUsd: {
            for (final row in rows)
              DateTime(row.date.year, row.date.month, row.date.day):
                  row.close / divisor / rate,
          },
        ),
      );
    }
    final projected = [
      for (final point in projectPortfolioFromCloses(
        brokerDate: brokerDay,
        brokerNavUsd: anchor.value,
        holdings: holdings,
        latestDate: now,
      ))
        if (point.date.isAfter(anchor.date)) point,
    ];
    final quotes = <ProvisionalQuote>[];
    await _intradayData.prefetchPortfolio(config, days: 1);
    for (var start = 0; start < positions.length; start += 4) {
      if (!isCurrent()) return;
      final batch = await Future.wait(
        positions.skip(start).take(4).map((position) async {
          try {
            final intraday = await _intradayData.fetch(
              position.symbol,
              days: 1,
              config: config,
            );
            await fetchSymbolCurrencyAndRate(
              position.symbol,
              rawCurrency: intraday.currency,
            );
            final last = intraday.candles.last;
            return ProvisionalQuote(
              observedAt: last.date,
              priceUsd: last.close /
                  symbolCentDivisor(position.symbol) /
                  requireUsdRate(symbolCurrency(position.symbol)),
            );
          } catch (error) {
            talker.warning(
              'Live portfolio quote unavailable for ${position.symbol}: $error',
            );
            return null;
          }
        }),
      );
      quotes.addAll(batch.whereType<ProvisionalQuote>());
    }
    if (!isCurrent()) return;
    if (quotes.length == holdings.length) {
      final quoteNow = DateTime.now();
      var live = projectPortfolioFromQuotes(
        brokerDate: brokerDay,
        brokerNavUsd: anchor.value,
        holdings: holdings,
        quotes: quotes,
        now: quoteNow,
      );
      final lastQuoteUtc = quotes.last.observedAt.toUtc();
      final quoteDay = DateTime(
        lastQuoteUtc.year,
        lastQuoteUtc.month,
        lastQuoteUtc.day,
      );
      if (live == null &&
          quoteDay == brokerDay &&
          loaded.cachedAt != null &&
          positions.every((position) => position.brokerMarketValue != null)) {
        live = projectPortfolioSinceSnapshot(
          snapshotAt: loaded.cachedAt!,
          brokerNavUsd: anchor.value,
          brokerMarketValuesUsd: [
            for (final position in positions)
              position.brokerMarketValue! /
                  requireUsdRate(position.nativeCurrency),
          ],
          holdings: holdings,
          quotes: quotes,
          now: quoteNow,
        );
      }
      if (live != null &&
          (projected.isEmpty || live.date.isAfter(projected.last.date))) {
        projected.add(live);
      }
    }
    if (projected.isEmpty) return;
    final originalReturns = [
      for (final point
          in _portfolioReturnSeriesByAccount[name] ?? <_DateValue>[])
        if (provisionalStart == null || point.date.isBefore(provisionalStart))
          point,
    ];
    final baseReturn =
        originalReturns.isEmpty ? null : originalReturns.last.value;
    setState(() {
      _portfolioSeriesByAccount[name] = [
        ...official,
        for (final point in projected) _DateValue(point.date, point.valueUsd),
      ];
      if (baseReturn != null && baseReturn.isFinite && baseReturn > 0) {
        _portfolioReturnSeriesByAccount[name] = [
          ...originalReturns,
          for (final point in projected)
            _DateValue(point.date, baseReturn * point.valueUsd / anchor.value),
        ];
      }
      _provisionalStartByAccount[name] = projected.first.date;
    });
  }

  Future<List<_DateValue>> _buildIntradayPortfolioSeries(
    String accountName,
    _LoadedChartPortfolio loaded,
    IbkrAccountConfig config, {
    required int generation,
    required bool forceRefresh,
  }) async {
    final selectedDays = days;
    final holdings = <IntradayPortfolioHolding>[];
    final failureReasons = <String>[];
    final prefetched = loaded.positions.isNotEmpty &&
        await _withRemoteLoading(
          () => _intradayData.prefetchPortfolio(
            config,
            days: selectedDays,
            forceRefresh: forceRefresh,
          ),
        );
    Future<IntradayPortfolioHolding?> loadHolding(Position position) async {
      try {
        final series = await _withRemoteLoading(
          () => _intradayData.fetch(
            position.symbol,
            days: selectedDays,
            config: config,
            forceRefresh: forceRefresh && !prefetched,
          ),
        );
        await fetchSymbolCurrencyAndRate(
          position.symbol,
          rawCurrency: series.currency,
        );
        return IntradayPortfolioHolding.fromSeries(
          series,
          quantity: position.netShares,
          currencyPerUsd: requireUsdRate(symbolCurrency(position.symbol)),
          centDivisor: symbolCentDivisor(position.symbol),
        );
      } catch (error, stackTrace) {
        failureReasons.add(error.toString().replaceFirst('Bad state: ', ''));
        talker.handle(
          error,
          stackTrace,
          'Portfolio intraday prices unavailable',
        );
        return null;
      }
    }

    final positions =
        loaded.positions.where((position) => position.netShares != 0).toList();
    for (var start = 0; start < positions.length; start += 4) {
      if (!mounted ||
          !widget.isActive ||
          generation != _portfolioLoadGeneration) return [];
      final batch = await Future.wait(
        positions.skip(start).take(4).map(loadHolding),
      );
      holdings.addAll(batch.whereType<IntradayPortfolioHolding>());
    }
    if (!mounted || !widget.isActive || generation != _portfolioLoadGeneration)
      return [];
    if (holdings.isEmpty && loaded.positions.isNotEmpty) {
      final firstReason =
          failureReasons.isEmpty ? '' : ': ${failureReasons.first}';
      throw StateError(
        'No intraday portfolio prices available for $accountName$firstReason',
      );
    }
    final nav = loaded.currentValue;
    final currentValueUsd = loaded.currentValueUsd ??
        (nav != null
            ? nav.value / requireUsdRate(nav.currency)
            : loaded.positions.fold<double>(
                0,
                (sum, position) => sum + position.currentValue,
              ));
    return [
      for (final point in buildIntradayPortfolio(
        holdings: holdings,
        currentValueUsd: currentValueUsd,
      ))
        _DateValue(point.date.toLocal(), point.valueUsd),
    ];
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
    final trades = await profileDataRepository.readTradesForAccount(
      accountName,
    );
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

  ({
    List<_DateValue> series,
    List<_DateValue> returnSeries,
    Map<DateTime, double> cashFlowsByDate,
  }) _buildBrokerPerformanceSeries(
    IbkrPerformanceSeries performance,
    _LoadedChartPortfolio loaded,
  ) {
    if (performance.nav.isEmpty || performance.dates.isEmpty) {
      return (
        series: <_DateValue>[],
        returnSeries: <_DateValue>[],
        cashFlowsByDate: <DateTime, double>{},
      );
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
        _DateValue(
          usSessionDisplayDay(performance.startDate!),
          performance.startNav! / basePerUsd,
        ),
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
          usSessionDisplayDay(date),
          performance.nav[index] / basePerUsd,
        ),
      );
    }
    points.sort((a, b) => a.date.compareTo(b.date));
    final asOfDate = loaded.asOfDate;
    final currentValueUsd = loaded.currentValueUsd ??
        (loaded.currentValue == null
            ? null
            : loaded.currentValue!.value / basePerUsd);
    if (asOfDate != null &&
        currentValueUsd != null &&
        currentValueUsd.isFinite &&
        currentValueUsd > 0 &&
        points.isNotEmpty) {
      final snapshotDate = usSessionDisplayDay(asOfDate);
      if (snapshotDate.isAfter(points.last.date)) {
        points.add(_DateValue(snapshotDate, currentValueUsd));
      }
    }
    if (points.isEmpty) {
      return (
        series: <_DateValue>[],
        returnSeries: <_DateValue>[],
        cashFlowsByDate: <DateTime, double>{},
      );
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
      for (var i = 0; i < points.length; i++) {
        if (!points[i].date.isAfter(cutoff)) baselineIndex = i;
      }
    }
    final series = points.sublist(baselineIndex);
    final cashFlowsByDate = <DateTime, double>{};
    if (performance.cashFlows.length == performance.dates.length) {
      for (var i = 0; i < performance.dates.length; i++) {
        final date = performance.dates[i];
        cashFlowsByDate.update(
          usSessionDisplayDay(date),
          (amount) => amount + performance.cashFlows[i] / basePerUsd,
          ifAbsent: () => performance.cashFlows[i] / basePerUsd,
        );
      }
    }

    // Broker returns are cumulative, cash-flow-adjusted fractions. NAV is
    // retained for currency tooltips; comparison charts use return factors.
    final returnSeries = <_DateValue>[];
    if (performance.returnDates.length == performance.returns.length &&
        performance.returnDates.isNotEmpty) {
      var returnIndex = 0;
      var cumulative = 0.0;
      for (final point in series) {
        while (returnIndex < performance.returnDates.length &&
            !usSessionDisplayDay(performance.returnDates[returnIndex])
                .isAfter(point.date)) {
          cumulative = performance.returns[returnIndex++];
        }
        if (cumulative.isFinite && cumulative > -1) {
          returnSeries.add(_DateValue(point.date, 1 + cumulative));
        }
      }
    }
    return (
      series: series,
      returnSeries: returnSeries,
      cashFlowsByDate: cashFlowsByDate,
    );
  }

  static int _isoWeek(DateTime date) {
    final startOfYear = DateTime(date.year, 1, 1);
    return (date.difference(startOfYear).inDays / 7).floor() + 1;
  }

  void _onSearchChanged(String text) {
    if (text.trim().isEmpty) {
      _yahooApi.cancelPendingSearch();
      setState(() {
        _customChartRange = null;
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
    setState(() {
      if (!_selectedFavorites.add(symbol)) {
        _selectedFavorites.remove(symbol);
      }
    });
    if (_selectedFavorites.contains(symbol)) {
      runDetachedTask(
        _syncFavoriteCandle(symbol),
        'Failed to sync selected favorite',
      );
    }
  }

  Color _favoriteColor(String symbol) {
    final index =
        _favoriteStocks.indexOf(symbol).clamp(0, _favoriteStocks.length);
    return chartSeriesColor(
      Theme.of(context).colorScheme,
      context.read<AccountManager>().accounts.length + index,
    );
  }

  void _selectSymbol(String symbol) {
    _searchController.text = symbol;
    _candleSelection.value = null;
    _searchFocus.unfocus();
    setState(() {
      _customChartRange = null;
      _mode = _ChartMode.stock;
      _selectedSymbol = symbol;
      _networkLoading = widget.isActive;
      _stockError = null;
    });
    if (_chartPeriodLoaded) {
      runDetachedTask(_loadSelectedStock(), 'Failed to load selected ticker');
    }
  }

  Future<void> _loadSelectedStock({bool forceRefresh = false}) async {
    if (!mounted || !widget.isActive || _selectedSymbol == null) return;
    final generation = ++_stockLoadGeneration;
    final symbol = _selectedSymbol!;
    final accountManager = context.read<AccountManager>();
    final config = accountManager.ibkrConfigFor();
    final namespace = accountManager.activeAccount;
    final intraday = _usesIntraday;
    final selectedDays = days;
    setState(() {
      _networkLoading = true;
      _stockError = null;
      final contentKey = '$namespace|$symbol|$years|$months|$days';
      if (_stockContentKey != contentKey) {
        _intradaySeries = null;
        _stockDailyPreview = const [];
        _stockContentKey = contentKey;
      }
      _nativeCurrency = symbolCurrency(symbol);
      _centDivisor = symbolCentDivisor(symbol);
    });
    _setStockStream(symbol);

    bool isCurrent() =>
        mounted &&
        widget.isActive &&
        _mode == _ChartMode.stock &&
        _selectedSymbol == symbol &&
        generation == _stockLoadGeneration;
    try {
      if (intraday) {
        if (selectedDays == 5) {
          runDetachedTask(
            _loadFiveDayStockPreview(symbol, generation),
            'Failed to load daily stock preview',
          );
        }
        final series = await _withRemoteLoading(
          () => _intradayData.fetch(
            symbol,
            days: selectedDays,
            config: config,
            forceRefresh: forceRefresh,
          ),
        );
        if (!isCurrent()) return;
        await fetchSymbolCurrencyAndRate(symbol, rawCurrency: series.currency);
        if (!isCurrent()) return;
        requireUsdRate(symbolCurrency(symbol));
        setState(() => _intradaySeries = series);
      } else {
        await syncCandles(
          symbol,
          ibkrConfig: config,
          syncNamespace: namespace,
          requiredFrom: _requiredCandleStart(),
          forceRefresh: forceRefresh,
        );
        if (!isCurrent()) return;
        await fetchSymbolCurrencyAndRate(symbol);
        if (!isCurrent()) return;
      }
      setState(() {
        _nativeCurrency = symbolCurrency(symbol);
        _centDivisor = symbolCentDivisor(symbol);
      });
      _setStockStream(symbol);
    } catch (error, stackTrace) {
      talker.handle(error, stackTrace, 'Selected ticker sync failed');
      if (isCurrent()) setState(() => _stockError = error.toString());
    } finally {
      if (isCurrent()) setState(() => _networkLoading = false);
    }
  }

  Future<void> _loadFiveDayStockPreview(String symbol, int generation) async {
    final after = DateTime.now().subtract(const Duration(days: 14));
    final rows = await (marketDataDatabase.candles.select()
          ..where(
            (candle) =>
                candle.symbol.equals(canonicalMarketSymbol(symbol)) &
                candle.date.isBiggerThanValue(after),
          )
          ..orderBy([(candle) => OrderingTerm.desc(candle.date)])
          ..limit(5))
        .get();
    if (rows.isEmpty) return;
    await fetchSymbolCurrencyAndRate(symbol);
    try {
      requireUsdRate(symbolCurrency(symbol));
    } on StateError {
      return;
    }
    if (!mounted ||
        !widget.isActive ||
        !_usesIntraday ||
        days != 5 ||
        _mode != _ChartMode.stock ||
        _selectedSymbol != symbol ||
        generation != _stockLoadGeneration ||
        _intradaySeries != null ||
        rows.isEmpty) {
      return;
    }
    setState(() {
      _stockDailyPreview = [
        for (final row in rows.reversed)
          CandleTicker(
            candle: CandlesCompanion(
              date: Value(row.date),
              open: Value(row.open),
              high: Value(row.high),
              low: Value(row.low),
              close: Value(row.close),
            ),
          ),
      ];
    });
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
    if (_usesIntraday) {
      _stockStream = null;
      setState(() {});
      return;
    }
    final after = _requiredCandleStart();
    final marketSymbol = canonicalMarketSymbol(symbol);

    final capturedDays = days;
    _stockStream = (marketDataDatabase.candles.select()
          ..where(
            (candle) =>
                candle.symbol.equals(marketSymbol) &
                candle.date.isBiggerThanValue(after),
          )
          ..orderBy([(candle) => OrderingTerm.asc(candle.date)]))
        .watch()
        .map((rows) {
      final selected = capturedDays > 0 && rows.length > capturedDays
          ? rows.sublist(rows.length - capturedDays)
          : rows;
      return [
        for (final row in selected)
          CandleTicker(
            candle: CandlesCompanion(
              date: Value(row.date),
              open: Value(row.open),
              high: Value(row.high),
              low: Value(row.low),
              close: Value(row.close),
            ),
          ),
      ];
    });
    setState(() {});
  }

  (int, int)? _chartRangeFor(List<DateTime> dates) {
    final range = _customChartRange;
    if (range == null || dates.isEmpty) return null;
    final first = dates.indexWhere((date) => !date.isBefore(range.$1));
    final last = dates.lastIndexWhere((date) => !date.isAfter(range.$2));
    final start = first < 0 ? dates.length - 1 : first;
    final end = last < start ? start : last;
    return (start, end);
  }

  List<_DateValue> _visibleValues(List<_DateValue> values) {
    final range = _customChartRange;
    if (range == null) return values;
    return [
      for (final point in values)
        if (!point.date.isBefore(range.$1) && !point.date.isAfter(range.$2))
          point,
    ];
  }

  void _setChartRange(List<DateTime> dates, (int, int)? range) {
    setState(() {
      _customChartRange =
          range == null ? null : (dates[range.$1], dates[range.$2]);
    });
  }

  String get _chartPeriodCacheKey {
    final manager = context.read<AccountManager>();
    final now = DateTime.now();
    return '$years|$months|$_intradayPortfolioCacheKey|'
        '$_selectedFavorites|$_favoriteStocks|${now.year}-${now.month}-${now.day}|'
        '${manager.accounts.map((name) => '$name:${manager.portfolioCacheFor(name)?.cachedAt}:${identityHashCode(manager.ibkrPerformanceCacheFor(name, '1Y'))}').join(',')}';
  }

  void _onPeriodSelected({
    int selectedYears = 0,
    int selectedMonths = 0,
    int selectedDays = 0,
  }) {
    final transitionGeneration = ++_periodTransitionGeneration;
    setState(() {
      _periodTransition = true;
      _customChartRange = null;
      _portfolioLoadGeneration++;
      _portfolioLoads.clear();
      _backgroundSyncs.clear();
      _portfolioLoading = true;
      years = selectedYears;
      months = selectedMonths;
      days = selectedDays;
      _favoriteLoadGeneration++;
      _favoriteIntraday.clear();
      _favoriteIntradayErrors.clear();
      _restoredFavoriteCandles = null;
      if (_mode != _ChartMode.stock) {
        final cached = _chartPeriodCache[_chartPeriodCacheKey];
        if (cached != null) {
          _portfolioSeriesByAccount = Map.of(cached.series);
          _portfolioReturnSeriesByAccount = Map.of(cached.returns);
          _portfolioCashFlowsByAccount = Map.of(cached.flows);
          _favoriteIntraday.addAll(cached.favorites);
          _favoriteIntradayErrors.addAll(cached.favoriteErrors);
          _portfolioDailyPreviewAccounts
            ..clear()
            ..addAll(cached.dailyPreviews);
          _provisionalStartByAccount
            ..clear()
            ..addAll(cached.provisionalStarts);
          _portfolioError = cached.error;
          _restoredFavoriteCandles = cached.candles;
          _portfolioLoading = false;
          _periodTransition = false;
        } else if (_selectedFavorites.isEmpty) {
          _hydratePortfolioSeriesFromCache(
            context.read<AccountManager>(),
            replaceExisting: true,
          );
          if (!_portfolioLoading) _periodTransition = false;
        }
      }
    });
    runDetachedTask(_savePeriod(), 'Failed to save chart period');
    if (!_periodTransition) return;
    runDetachedTask(
      () async {
        try {
          await Future.wait([
            if (_selectedFavorites.isNotEmpty)
              _syncFavoriteCandles(selectedOnly: true),
            if (_mode == _ChartMode.stock && _selectedSymbol != null)
              _loadSelectedStock()
            else if (!_restoreIntradayPortfolio())
              _syncCandlesInBackground(),
          ]);
        } finally {
          if (mounted && transitionGeneration == _periodTransitionGeneration) {
            setState(() => _periodTransition = false);
          }
        }
      }(),
      'Failed to load selected chart period',
    );
  }

  void _clearSearch() {
    _candleSelection.value = null;
    _searchController.clear();
    _searchFocus.unfocus();
    _yahooApi.cancelPendingSearch();
    setState(() {
      _customChartRange = null;
      _mode = _ChartMode.portfolio;
      _searchResults = [];
      _selectedSymbol = null;
      _stockLoadGeneration++;
      _networkLoading = false;
      _searchLoading = false;
      _stockError = null;
    });
    runDetachedTask(_loadAllPortfolios(), 'Failed to reload portfolio chart');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final settings = context.watch<SettingsState>();

    final accountColors = List.generate(
      context.watch<AccountManager>().accounts.length + 1,
      (index) => chartSeriesColor(Theme.of(context).colorScheme, index),
    );
    final canReturnToPortfolio =
        _mode != _ChartMode.portfolio || _searchController.text.isNotEmpty;

    // The chart fills the available height so the Drafter tooltip overlay can
    // render above its data points without being obscured by the search bar.
    return DesktopContextMenu(
      actions: [
        DesktopMenuAction(
          context.l10n.text('Refresh'),
          () => runDetachedTask(
            _refreshCurrentChart(),
            'Failed to refresh chart',
          ),
        ),
      ],
      child: ValueListenableBuilder<int?>(
        valueListenable: _candleSelection,
        builder: (context, activeIndex, child) => PopScope<void>(
          canPop: !canReturnToPortfolio &&
              (!_showCandlesticks || activeIndex == null),
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            if (_showCandlesticks && _candleSelection.value != null) {
              _candleSelection.value = null;
              return;
            }
            if (canReturnToPortfolio) _clearSearch();
          },
          child: child!,
        ),
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
                  if (constraints.maxHeight < 72 ||
                      constraints.maxWidth < 120) {
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
      ),
    );
  }

  Widget _buildSearchBar() {
    final canReturnToPortfolio =
        _mode != _ChartMode.portfolio || _searchController.text.isNotEmpty;
    final desktop = isDesktopLayout(context);
    final settings = context.watch<SettingsState>();
    final leading = canReturnToPortfolio
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

    return Padding(
      padding: EdgeInsets.fromLTRB(
        desktop ? 32 : 8,
        desktop ? 28 : 8,
        desktop ? 32 : 8,
        4,
      ),
      child: SearchBar(
        key: const Key('chart-search-bar'),
        constraints: const BoxConstraints(
          minHeight: 56,
          maxWidth: double.infinity,
        ),
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
          PopupMenuButton<String>(
            key: const Key('chart-menu-button'),
            icon: const Icon(Icons.more_vert),
            tooltip: context.l10n.text('Show menu'),
            onSelected: (value) {
              if (value == '__settings__') {
                Navigator.push(
                  context,
                  adaptivePageRoute(
                    context,
                    builder: (_) => const SettingsPage(),
                  ),
                );
              } else if (value == '__rolling_average__') {
                runDetachedTask(
                  settings.setShowRollingAverage(!settings.showRollingAverage),
                  'Failed to save rolling average',
                );
              } else if (value == '__candles__') {
                _candleSelection.value = null;
                runDetachedTask(
                  settings.setShowCandlesticks(!settings.showCandlesticks),
                  'Failed to save chart style',
                );
              } else if (value.startsWith('currency:')) {
                runDetachedTask(
                  settings.setDisplayCurrency(value.substring(9)),
                  'Failed to change display currency',
                );
              }
            },
            itemBuilder: (context) => [
              if (settings.visibleCurrencies.length > 1) ...[
                for (final currencyCode in settings.visibleCurrencies)
                  CheckedPopupMenuItem<String>(
                    value: 'currency:$currencyCode',
                    checked: currencyCode == settings.displayCurrency,
                    child: Text(currencyCode),
                  ),
                const PopupMenuDivider(),
              ],
              if (!desktop) ...[
                PopupMenuItem<String>(
                  key: const Key('chart-menu-rolling-average'),
                  value: '__rolling_average__',
                  child: Row(
                    children: [
                      Icon(
                        settings.showRollingAverage
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                      ),
                      const SizedBox(width: 12),
                      Text(context.l10n.text('Rolling average')),
                      if (settings.showRollingAverage) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.check, size: 18),
                      ],
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  key: const Key('chart-menu-candles'),
                  value: '__candles__',
                  child: Row(
                    children: [
                      Icon(
                        settings.showCandlesticks
                            ? Icons.candlestick_chart
                            : Icons.candlestick_chart_outlined,
                      ),
                      const SizedBox(width: 12),
                      const Text('Candles'),
                      if (settings.showCandlesticks) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.check, size: 18),
                      ],
                    ],
                  ),
                ),
                const PopupMenuDivider(),
              ],
              PopupMenuItem<String>(
                value: '__settings__',
                child: ListTile(
                  leading: const Icon(Icons.settings),
                  title: Text(context.l10n.text('Settings')),
                ),
              ),
            ],
          ),
        ],
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
        itemCount: _searchResults.length + 1 + (_searchLoading ? 1 : 0),
        itemBuilder: (context, index) {
          if (_searchLoading && index == _searchResults.length + 1) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (index == _searchResults.length) {
            return useAnywayTile;
          }
          final result = _searchResults[index];
          final name =
              result.longname.isNotEmpty ? result.longname : result.shortname;
          return DesktopContextMenu(
            actions: [
              DesktopMenuAction(
                context.l10n.text('Open chart'),
                () => _selectStock(result),
              ),
              DesktopMenuAction(
                context.l10n.text(
                  _favoriteStocks.contains(result.symbol)
                      ? 'Remove favorite'
                      : 'Add favorite',
                ),
                () => _toggleFavorite(result.symbol),
              ),
            ],
            copyText: result.symbol,
            copyLabel: context.l10n.text('Copy symbol'),
            child: ListTile(
              title: Text(result.symbol),
              subtitle: Text(name),
              trailing: Text(
                result.exchange,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              onTap: () => _selectStock(result),
            ),
          );
        },
      ),
    );
  }

  Widget _buildChartContent(SettingsState settings, List<Color> accountColors) {
    final desktop = isDesktopLayout(context);
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        if (desktop ||
            notification.depth != 0 ||
            notification.metrics.axis != Axis.vertical) {
          return false;
        }
        final desiredPadding =
            notification.metrics.maxScrollExtent > _chartBottomPadding + 0.5
                ? bottomNavScrollClearance
                : 0.0;
        if (desiredPadding != _chartBottomPadding) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _chartBottomPadding != desiredPadding) {
              setState(() => _chartBottomPadding = desiredPadding);
            }
          });
        }
        return false;
      },
      child: RefreshIndicator(
        edgeOffset: _overlayHeight + 8,
        triggerMode: RefreshIndicatorTriggerMode.anywhere,
        onRefresh: _refreshCurrentChart,
        child: ListView(
          key: const Key('charts-main-scroll'),
          physics: const AlwaysScrollableScrollPhysics(
            parent: ClampingScrollPhysics(),
          ),
          padding: EdgeInsets.only(
            top: _overlayHeight + 8,
            bottom: desktop ? 24 : _chartBottomPadding,
          ),
          children: [
            _buildTimeChips(),
            if (_mode == _ChartMode.stock)
              ..._buildStockContent(settings)
            else
              ..._buildPortfolioContent(settings, accountColors),
          ],
        ),
      ),
    );
  }

  void _toggleCandlesticks() {
    _candleSelection.value = null;
    final settings = context.read<SettingsState>();
    runDetachedTask(
      settings.setShowCandlesticks(!settings.showCandlesticks),
      'Failed to save chart style',
    );
  }

  Widget _buildTimeChips() {
    final options = [
      ('1d', 0, 0, 1),
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

    final chips = [
      for (final (label, optionYears, optionMonths, optionDays) in options)
        _PeriodChip(
          key: Key('chart-period-$label'),
          label: label,
          selected: _customChartRange == null &&
              optionYears == years &&
              optionMonths == months &&
              optionDays == days,
          onTap: () => _onPeriodSelected(
            selectedYears: optionYears,
            selectedMonths: optionMonths,
            selectedDays: optionDays,
          ),
        ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          for (final chip in chips)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: chip,
            ),
        ],
      ),
    );
  }

  List<Widget> _buildStockContent(SettingsState settings) {
    final intradaySnapshot = AsyncSnapshot.withData(
      ConnectionState.done,
      _intradaySeries == null
          ? _networkLoading || _stockError == null
              ? const <CandleTicker>[]
              : _stockDailyPreview
          : [
              for (final bar in _intradaySeries!.candles)
                CandleTicker(
                  candle: CandlesCompanion(
                    date: Value(bar.date.toLocal()),
                    open: Value(bar.open),
                    high: Value(bar.high),
                    low: Value(bar.low),
                    close: Value(bar.close),
                  ),
                ),
            ],
    );
    return [
      if (_usesIntraday)
        _buildStockChart(context, intradaySnapshot, settings)
      else
        StreamBuilder(
          key: ValueKey('stock-chart-$_stockLoadGeneration'),
          stream: _stockStream,
          builder: (context, snapshot) =>
              _buildStockChart(context, snapshot, settings),
        ),
      if (_usesIntraday && _intradaySeries != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '${_intradaySeries!.source} · ${_intradaySeries!.isDaily ? "1 day" : (days == 1 ? "1 min" : "15 min")} · ${context.l10n.text('Local time')}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      if (_usesIntraday)
        _buildStockSummary(context, intradaySnapshot)
      else
        StreamBuilder(
          key: ValueKey('stock-summary-$_stockLoadGeneration'),
          stream: _stockStream,
          builder: _buildStockSummary,
        ),
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
      return SizedBox(
        height: height,
        child: _networkLoading && (_usesIntraday || snapshot.hasData)
            ? const Center(child: CircularProgressIndicator())
            : null,
      );
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

    return DesktopContextMenu(
      actions: [
        DesktopMenuAction(
          context.l10n.text('Refresh'),
          () => runDetachedTask(
            _refreshCurrentChart(),
            'Failed to refresh chart',
          ),
        ),
        DesktopMenuAction(
          context.l10n.text(
            _favoriteStocks.contains(_selectedSymbol)
                ? 'Remove favorite'
                : 'Add favorite',
          ),
          () => _toggleFavorite(_selectedSymbol!),
        ),
        if (!context.read<AccountManager>().ibkrConfigFor().enabled)
          DesktopMenuAction(
            context.l10n.text('Add trade'),
            () => Navigator.push(
              context,
              adaptivePageRoute(
                context,
                builder: (_) => EditTickerPage(symbol: _selectedSymbol),
              ),
            ),
          ),
      ],
      copyText: _selectedSymbol,
      copyLabel: context.l10n.text('Copy symbol'),
      child: SizedBox(
        height: height,
        child: TickerLine(
          key: ValueKey('$_selectedSymbol|$years|$months|$days'),
          range: _chartRangeFor([
            for (final candle in candles) candle.date.value,
          ]),
          onRangeChanged: (range) => _setChartRange(
            [
              for (final candle in candles) candle.date.value,
            ],
            range,
          ),
          dates: candles.map((candle) => candle.date.value),
          spots: spots,
          candles: [
            for (var i = 0; i < candles.length; i++)
              MarketCandlePoint(
                column: i,
                open: candles[i].open.value / _centDivisor,
                high: candles[i].high.value / _centDivisor,
                low: candles[i].low.value / _centDivisor,
                close: candles[i].close.value / _centDivisor,
              ),
          ],
          showCandlesticks: _showCandlesticks,
          candleSelection: _candleSelection,
          showRollingAverage: _showRollingAverage,
          nativeCurrency: _nativeCurrency,
          intraday: _usesIntraday && _intradaySeries != null,
        ),
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
            runSpacing: 8,
            children: [
              _ActionChip(
                icon: Icons.add,
                label: context.l10n.text('Add trade'),
                onTap: () => Navigator.push(
                  context,
                  adaptivePageRoute(
                    context,
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
              _buildRollingAverageChip(),
              Semantics(
                key: const Key('chart-candlestick-toggle'),
                selected: _showCandlesticks,
                button: true,
                child: _ActionChip(
                  icon: _showCandlesticks
                      ? Icons.candlestick_chart
                      : Icons.candlestick_chart_outlined,
                  label: 'Candles',
                  onTap: _toggleCandlesticks,
                ),
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
      for (final symbol in _selectedFavorites)
        if (_usesIntraday && _favoriteIntradayErrors.containsKey(symbol))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('$symbol: ${_favoriteIntradayErrors[symbol]}'),
          ),
      _buildPortfolioChart(context, settings, accountColors),
      _buildPortfolioSummary(context, accountColors),
      if (isDesktopLayout(context)) _buildPortfolioChartControls(),
    ];
  }

  Widget _buildRollingAverageChip() => Semantics(
        key: const Key('chart-rolling-average'),
        selected: _showRollingAverage,
        button: true,
        child: _ActionChip(
          icon: _showRollingAverage
              ? Icons.radio_button_checked
              : Icons.radio_button_unchecked,
          label: context.l10n.text('Rolling average'),
          onTap: () {
            final settings = context.read<SettingsState>();
            runDetachedTask(
              settings.setShowRollingAverage(!settings.showRollingAverage),
              'Failed to save rolling average',
            );
          },
        ),
      );

  Widget _buildPortfolioCandleChip() => Semantics(
        key: const Key('chart-portfolio-candle-toggle'),
        selected: _showCandlesticks,
        button: true,
        child: _ActionChip(
          icon: _showCandlesticks
              ? Icons.candlestick_chart
              : Icons.candlestick_chart_outlined,
          label: 'Candles',
          onTap: _toggleCandlesticks,
        ),
      );

  Widget _buildPortfolioChartControls() => Padding(
        key: const Key('desktop-portfolio-chart-controls'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildRollingAverageChip(),
              const SizedBox(width: 8),
              _buildPortfolioCandleChip(),
            ],
          ),
        ),
      );

  Future<void> _renameFavorite(String symbol) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) =>
          _RenameFavoriteDialog(currentName: _favoriteNames[symbol] ?? symbol),
    );
    if (name == null || !mounted) return;
    final prefs = await SqliteSettings.getInstance();
    if (name.isEmpty || name == symbol) {
      await prefs.remove('favoriteName:$symbol');
    } else {
      await prefs.setString('favoriteName:$symbol', name);
    }
    if (!mounted) return;
    setState(() {
      if (name.isEmpty || name == symbol) {
        _favoriteNames.remove(symbol);
      } else {
        _favoriteNames[symbol] = name;
      }
    });
  }

  void _showFavoriteActions(String symbol) {
    runDetachedTask(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(context.l10n.text('Rename')),
                onTap: () {
                  Navigator.pop(sheetContext);
                  runDetachedTask(
                    _renameFavorite(symbol),
                    'Failed to rename favorite',
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.favorite_border),
                title: Text(context.l10n.text('Remove favorite')),
                onTap: () {
                  Navigator.pop(sheetContext);
                  if (_favoriteStocks.contains(symbol)) {
                    runDetachedTask(
                      _toggleFavorite(symbol),
                      'Failed to remove favorite',
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.close),
                title: Text(context.l10n.text('Cancel')),
                onTap: () => Navigator.pop(sheetContext),
              ),
            ],
          ),
        ),
      ),
      'Failed to show favorite actions',
    );
  }

  Widget _buildFavoritesRow() {
    final hasFavorites = _favoriteStocks.isNotEmpty;
    if (!hasFavorites) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isDesktopLayout(context) ? 32 : 16,
        12,
        isDesktopLayout(context) ? 32 : 16,
        8,
      ),
      child: Column(
        children: [
          if (hasFavorites) ...[
            SizedBox(
              height: 64,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _favoriteStocks.length,
                itemBuilder: (context, index) {
                  final symbol = _favoriteStocks[index];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: DesktopContextMenu(
                      actions: [
                        DesktopMenuAction(
                          context.l10n.text('Rename'),
                          () => runDetachedTask(
                            _renameFavorite(symbol),
                            'Failed to rename favorite',
                          ),
                        ),
                        DesktopMenuAction(
                          context.l10n.text('Open chart'),
                          () => _selectSymbol(symbol),
                        ),
                        DesktopMenuAction(
                          context.l10n.text('Remove favorite'),
                          () => _toggleFavorite(symbol),
                        ),
                        if (!context
                            .read<AccountManager>()
                            .ibkrConfigFor()
                            .enabled)
                          DesktopMenuAction(
                            context.l10n.text('Add trade'),
                            () => Navigator.push(
                              context,
                              adaptivePageRoute(
                                context,
                                builder: (_) => EditTickerPage(symbol: symbol),
                              ),
                            ),
                          ),
                      ],
                      copyText: symbol,
                      copyLabel: context.l10n.text('Copy symbol'),
                      child: _FavoriteCard(
                        symbol: symbol,
                        displayName: _favoriteNames[symbol] ?? symbol,
                        periodStart: _requiredCandleStart(),
                        periodDays: days,
                        visibleRange: _customChartRange,
                        intraday: _usesIntraday &&
                            _selectedFavorites.contains(symbol) &&
                            (days != 5 ||
                                _favoriteIntraday.containsKey(symbol)),
                        intradaySeries: _favoriteIntraday[symbol],
                        isActive: widget.isActive,
                        selected: _selectedFavorites.contains(symbol),
                        selectionColor: _favoriteColor(symbol),
                        onTap: () => _selectFavorite(symbol),
                        onLongPress: () => _showFavoriteActions(symbol),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildPortfolioChart(
    BuildContext context,
    SettingsState settings,
    List<Color> accountColors,
  ) {
    final streamKey =
        '${widget.isActive}|$_selectedFavorites|$years|$months|$days';
    if (_favoriteChartStreamKey != streamKey) {
      _favoriteChartStreamKey = streamKey;
      _favoriteChartStream = widget.isActive &&
              (!_usesIntraday || days == 5) &&
              _selectedFavorites.isNotEmpty
          ? (marketDataDatabase.candles.select()
                ..where(
                  (candle) =>
                      candle.symbol.isIn(
                        _selectedFavorites.map(canonicalMarketSymbol),
                      ) &
                      candle.date.isBiggerThanValue(_requiredCandleStart()),
                )
                ..orderBy([(candle) => OrderingTerm.asc(candle.date)]))
              .watch()
          : null;
    }
    return StreamBuilder<List<StoredCandle>>(
      key: const Key('portfolio-price-stream'),
      stream: _favoriteChartStream,
      builder: (context, snapshot) => _buildCombinedPortfolioChart(
        context,
        settings,
        accountColors,
        snapshot.connectionState == ConnectionState.active
            ? snapshot.data ?? const []
            : _restoredFavoriteCandles ?? const [],
        localPricesReady: _selectedFavorites.isEmpty ||
            _usesIntraday && days != 5 ||
            snapshot.connectionState == ConnectionState.active &&
                snapshot.hasData ||
            _restoredFavoriteCandles != null,
      ),
    );
  }

  Widget _buildCombinedPortfolioChart(
    BuildContext context,
    SettingsState settings,
    List<Color> accountColors,
    List<StoredCandle> favoriteCandles, {
    required bool localPricesReady,
  }) {
    if (_periodTransition || !localPricesReady) {
      return _lastPortfolioChart ??
          SizedBox(height: MediaQuery.of(context).size.height * 0.30);
    }
    final chart = _buildReadyPortfolioChart(
      context,
      settings,
      accountColors,
      favoriteCandles,
      localPricesReady: localPricesReady,
    );
    if (!_portfolioLoading &&
        !_networkLoading &&
        (!_usesIntraday ||
            _selectedFavorites.every(
              (symbol) =>
                  _favoriteIntraday.containsKey(symbol) ||
                  _favoriteIntradayErrors.containsKey(symbol),
            ))) {
      if (_chartPeriodCache.length >= 16 &&
          !_chartPeriodCache.containsKey(_chartPeriodCacheKey)) {
        _chartPeriodCache.remove(_chartPeriodCache.keys.first);
      }
      _chartPeriodCache[_chartPeriodCacheKey] = _CachedChartPeriod(
        series: Map.of(_portfolioSeriesByAccount),
        returns: Map.of(_portfolioReturnSeriesByAccount),
        flows: Map.of(_portfolioCashFlowsByAccount),
        favorites: Map.of(_favoriteIntraday),
        favoriteErrors: Map.of(_favoriteIntradayErrors),
        dailyPreviews: Set.of(_portfolioDailyPreviewAccounts),
        provisionalStarts: Map.of(_provisionalStartByAccount),
        candles: favoriteCandles,
        error: _portfolioError,
      );
    }
    _lastPortfolioChart = chart;
    return chart;
  }

  Widget _buildReadyPortfolioChart(
    BuildContext context,
    SettingsState settings,
    List<Color> accountColors,
    List<StoredCandle> favoriteCandles, {
    required bool localPricesReady,
  }) {
    final height = MediaQuery.of(context).size.height * 0.30;

    final hasFavoritePrices = _selectedFavorites.any(
      (symbol) =>
          _favoriteIntraday[symbol]?.candles.isNotEmpty == true ||
          favoriteCandles.any(
            (candle) => candle.symbol == canonicalMarketSymbol(symbol),
          ),
    );
    if (!hasFavoritePrices &&
        _portfolioLoading &&
        _portfolioSeriesByAccount.values.every((series) => series.isEmpty)) {
      return SizedBox(
        height: height,
        child: _pendingRemoteLoads > 0 && localPricesReady
            ? const Center(child: CircularProgressIndicator())
            : null,
      );
    }
    if (_portfolioError != null &&
        _portfolioSeriesByAccount.values.every((series) => series.isEmpty) &&
        _selectedFavorites.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(child: Text(_portfolioError!)),
      );
    }

    final accountManager = context.read<AccountManager>();
    final accounts = accountManager.accounts;
    final favoriteOhlcBySymbol = <String,
        Map<DateTime,
            ({double open, double high, double low, double close})>>{};
    final visibleSeries = <String, List<_DateValue>>{};

    for (final symbol in _favoriteStocks.where(_selectedFavorites.contains)) {
      if (_usesIntraday) {
        final series = _favoriteIntraday[symbol];
        if (series != null) {
          final divisor = symbolCentDivisor(symbol);
          favoriteOhlcBySymbol[symbol] = {
            for (final bar in series.candles)
              bar.date.toLocal(): (
                open: bar.open / divisor,
                high: bar.high / divisor,
                low: bar.low / divisor,
                close: bar.close / divisor,
              ),
          };
          visibleSeries[symbol] = [
            for (final bar in series.candles)
              _DateValue(
                bar.date.toLocal(),
                bar.close / symbolCentDivisor(symbol),
              ),
          ];
          continue;
        }
        if (days != 5 || !_favoriteIntradayErrors.containsKey(symbol)) continue;
      }
      var candles = favoriteCandles
          .where((candle) => candle.symbol == canonicalMarketSymbol(symbol))
          .toList();
      if (days > 0 && candles.length > days) {
        candles = candles.sublist(candles.length - days);
      }
      if (candles.isNotEmpty) {
        final divisor = symbolCentDivisor(symbol);
        favoriteOhlcBySymbol[symbol] = {
          for (final candle in candles)
            candle.date: (
              open: candle.open / divisor,
              high: candle.high / divisor,
              low: candle.low / divisor,
              close: candle.close / divisor,
            ),
        };
        visibleSeries[symbol] = [
          for (final candle in candles)
            _DateValue(candle.date, candle.close / symbolCentDivisor(symbol)),
        ];
      }
    }

    for (final account in accounts) {
      final series = _portfolioSeriesByAccount[account];
      if (!_hiddenAccounts.contains(account) &&
          series != null &&
          series.isNotEmpty) {
        visibleSeries[account] = series;
      }
    }

    if (visibleSeries.isEmpty) {
      if (_pendingRemoteLoads > 0 && localPricesReady) {
        return SizedBox(
          height: height,
          child: const Center(child: CircularProgressIndicator()),
        );
      }
      final allEmpty = _portfolioSeriesByAccount.values.every(
        (series) => series.isEmpty,
      );
      final hasCachedHoldings = accounts.any(
        (name) =>
            accountManager.portfolioCacheFor(name)?.positions.isNotEmpty ??
            false,
      );
      final pricesUnavailable = allEmpty && hasCachedHoldings;
      return ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: height,
          maxHeight: allEmpty ? height : double.infinity,
        ),
        child: AppEmptyState(
          icon: allEmpty
              ? Icons.candlestick_chart_rounded
              : Icons.visibility_off_rounded,
          title: pricesUnavailable
              ? context.l10n.text('Historical prices unavailable')
              : allEmpty
                  ? context.l10n.text('No trades yet')
                  : context.l10n.text('All portfolios are hidden'),
          message: pricesUnavailable
              ? context.l10n.text('No market data found')
              : allEmpty
                  ? context.l10n.text(
                      'Search for a stock to start building your portfolio history.',
                    )
                  : context.l10n.text(
                      'Show your portfolios again to restore the chart.',
                    ),
          actionLabel: pricesUnavailable
              ? context.l10n.text('Refresh')
              : allEmpty
                  ? context.l10n.text('Search stocks')
                  : context.l10n.text('Show all'),
          actionIcon: pricesUnavailable
              ? Icons.refresh_rounded
              : allEmpty
                  ? Icons.search_rounded
                  : Icons.visibility_rounded,
          onAction: () {
            if (pricesUnavailable) {
              runDetachedTask(
                _refreshCurrentChart(),
                'Failed to refresh chart',
              );
            } else if (allEmpty) {
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
    final scaleForComparison = !singleLine || _selectedFavorites.isNotEmpty;
    final chartSeries = <MarketLineChartSeries>[];
    final chartCandles = <MarketCandlePoint>[];
    final candleTooltipRowsByIndex = <int, List<String>>{};
    for (final entry in visibleSeries.entries) {
      final accountIndex = accounts.indexOf(entry.key);
      final color = _selectedFavorites.contains(entry.key)
          ? _favoriteColor(entry.key)
          : accountColors[accountIndex.clamp(0, accountColors.length - 1)];
      final returnByDate = {
        for (final point
            in _portfolioReturnSeriesByAccount[entry.key] ?? <_DateValue>[])
          point.date: point.value,
      };
      final comparisonValues = [
        for (final point in entry.value)
          returnByDate[point.date] ?? point.value,
      ];
      final displayValues = scaleForComparison
          ? scalePortfolioSeriesForComparison(comparisonValues)
          : entry.value.map((point) => point.value).toList(growable: false);
      final baseline = comparisonValues.firstWhere(
        (value) => value.isFinite && value.abs() > 1e-9,
        orElse: () => 0,
      );
      double chartValue(double value) => scaleForComparison
          ? baseline == 0
              ? 0
              : (value / baseline - 1) * 100
          : value;
      final seriesIndex = chartSeries.length;
      final ohlcByDate = favoriteOhlcBySymbol[entry.key];
      for (var index = 0; index < entry.value.length; index++) {
        final point = entry.value[index];
        final column = dateIndex[point.date]!;
        final rawOhlc = ohlcByDate?[point.date];
        if (rawOhlc != null) {
          chartCandles.add(
            MarketCandlePoint(
              column: column,
              seriesIndex: seriesIndex,
              open: chartValue(rawOhlc.open),
              high: chartValue(rawOhlc.high),
              low: chartValue(rawOhlc.low),
              close: chartValue(rawOhlc.close),
            ),
          );
          if (_showCandlesticks) {
            candleTooltipRowsByIndex.putIfAbsent(column, () => []).addAll([
              entry.key,
              'O ${fmtNativeCurrency(rawOhlc.open, symbolCurrency(entry.key))}  H ${fmtNativeCurrency(rawOhlc.high, symbolCurrency(entry.key))}',
              'L ${fmtNativeCurrency(rawOhlc.low, symbolCurrency(entry.key))}  C ${fmtNativeCurrency(rawOhlc.close, symbolCurrency(entry.key))}',
            ]);
          }
        } else {
          final previous =
              index == 0 ? point.value : entry.value[index - 1].value;
          final open =
              index == 0 ? displayValues[index] : displayValues[index - 1];
          final close = displayValues[index];
          chartCandles.add(
            MarketCandlePoint(
              column: column,
              seriesIndex: seriesIndex,
              sampled: true,
              open: open,
              high: max(open, close),
              low: min(open, close),
              close: close,
            ),
          );
          if (_showCandlesticks) {
            candleTooltipRowsByIndex.putIfAbsent(column, () => []).addAll([
              '${entry.key} · sampled',
              'O ${fmtCurrency(previous)}  C ${fmtCurrency(point.value)}',
            ]);
          }
        }
      }
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
                comparisonValue:
                    scaleForComparison ? comparisonValues[index] : null,
                column: dateIndex[entry.value[index].date]!,
              ),
          ],
        ),
      );
    }

    final dailyOnly = _usesIntraday &&
        days == 5 &&
        visibleSeries.keys.every(
          (name) => accounts.contains(name)
              ? _portfolioDailyPreviewAccounts.contains(name)
              : !_favoriteIntraday.containsKey(name),
        );
    final formatter = DateFormat(
      _usesIntraday && !dailyOnly
          ? '${settings.dateFormat} HH:mm'
          : settings.dateFormat,
    );
    final axisFormatter = DateFormat(
      _usesIntraday && !dailyOnly ? 'HH:mm' : settings.dateFormat,
    );
    final visibleKeys = visibleSeries.keys.toList();

    return SizedBox(
      height: height,
      child: MarketLineChart(
        key: ValueKey('portfolio|$years|$months|$days'),
        range: _chartRangeFor(sortedDates),
        onRangeChanged: (range) => _setChartRange(sortedDates, range),
        series: chartSeries,
        candles: chartCandles,
        showCandlesticks: _showCandlesticks,
        candleSelection: _candleSelection,
        candleTooltipTitle: (index) => index >= 0 && index < sortedDates.length
            ? formatter.format(sortedDates[index])
            : '',
        candleTooltipRows: _showCandlesticks
            ? (index) => candleTooltipRowsByIndex[index] ?? const []
            : null,
        showRollingAverage: _showRollingAverage,
        xLabels: [for (final date in sortedDates) axisFormatter.format(date)],
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
          final valueLabel = _selectedFavorites.contains(accountName)
              ? fmtNativeCurrency(
                  actualValue ?? mark.value,
                  symbolCurrency(accountName),
                )
              : fmtCurrency(actualValue ?? mark.value);
          final dateLabel = date == null ? '' : formatter.format(date);
          final returnLabel = scaleForComparison
              ? '${mark.value >= 0 ? '+' : ''}${mark.value.toStringAsFixed(2)}% · '
              : '';
          return dateLabel.isEmpty
              ? '$returnLabel$valueLabel'
              : '$returnLabel$valueLabel · $dateLabel';
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
    List<Color> accountColors,
  ) {
    final accounts = context.read<AccountManager>().accounts;
    if (accounts.isEmpty) return const SizedBox.shrink();

    return Padding(
      key: const Key('portfolio-summary-content'),
      padding: EdgeInsets.symmetric(
        horizontal: isDesktopLayout(context) ? 32 : 16,
        vertical: 8,
      ),
      child: Column(
        children: [
          for (final accountName in accounts)
            _buildAccountSummaryRow(
              context,
              accounts,
              accountName,
              _portfolioSeriesByAccount[accountName] ?? const [],
              accountColors,
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
    final accountReturns = _portfolioReturnSeriesByAccount[accountName];
    final visibleSeries = _visibleValues(series);
    final visibleReturns = _visibleValues(accountReturns ?? <_DateValue>[]);
    final hasHistory = accountReturns != null
        ? visibleReturns.length > 1
        : visibleSeries.length > 1;
    final pct = hasHistory
        ? safePercentChange(
            accountReturns != null
                ? visibleReturns.first.value
                : visibleSeries.first.value,
            accountReturns != null
                ? visibleReturns.last.value
                : visibleSeries.last.value,
          )
        : 0.0;
    final returnColor = hasHistory
        ? (pct >= 0 ? Colors.green : Colors.redAccent)
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final flows = _portfolioCashFlowsByAccount[accountName];
    final externalFlows = flows == null || visibleSeries.length < 2
        ? 0.0
        : flows.entries
            .where(
              (entry) =>
                  entry.key.isAfter(visibleSeries.first.date) &&
                  !entry.key.isAfter(visibleSeries.last.date),
            )
            .fold<double>(0.0, (total, entry) => total + entry.value);
    final change = visibleSeries.length > 1
        ? visibleSeries.last.value - visibleSeries.first.value - externalFlows
        : 0.0;
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
    final estimated = series.isNotEmpty &&
        _provisionalStartByAccount[accountName] != null &&
        !series.last.date.isBefore(_provisionalStartByAccount[accountName]!);
    final summaryValue = estimated
        ? series.last.value
        : currentValueUsd != null && currentValueUsd.isFinite
            ? currentValueUsd
            : series.isNotEmpty
                ? series.last.value
                : null;
    final theme = Theme.of(context);

    Widget returnLabel() => Text(
          (hasHistory
              ? <String>[if (pct >= 0) '+', pct.toStringAsFixed(2), '%'].join()
              : _portfolioLoading
                  ? '—'
                  : context.l10n.text('History unavailable')),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium!.copyWith(color: returnColor),
        );

    final valueText = Text(
      summaryValue == null ? '—' : fmtCurrency(summaryValue),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.right,
      style: theme.textTheme.titleMedium!.copyWith(height: 1.1),
    );
    final changeText = Text(
      hasHistory
          ? (change >= 0 ? '+' : '') + fmtCurrency(change)
          : _portfolioLoading
              ? '—'
              : context.l10n.text('Historical prices unavailable'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: returnColor, fontSize: 13, height: 1.1),
    );
    return Column(
      children: [
        AnimatedOpacity(
          opacity: isHidden ? 0.35 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: DesktopContextMenu(
              actions: [
                DesktopMenuAction(
                  context.l10n.text('Show only this account'),
                  () => setState(() {
                    _hiddenAccounts.clear();
                    _hiddenAccounts.addAll(
                      accounts.where((name) => name != accountName),
                    );
                  }),
                ),
                if (_hiddenAccounts.isNotEmpty)
                  DesktopMenuAction(
                    context.l10n.text('Show all accounts'),
                    () => setState(_hiddenAccounts.clear),
                  ),
              ],
              copyText: '$accountName: ${valueText.data} · ${changeText.data}',
              copyLabel: context.l10n.text('Copy account summary'),
              child: ListTile(
                dense: true,
                key: Key('chart-account-selector-$accountName'),
                onTap: () => setState(() {
                  if (isHidden) {
                    _hiddenAccounts.remove(accountName);
                  } else {
                    _hiddenAccounts.add(accountName);
                  }
                }),
                leading: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: isHidden
                        ? theme.colorScheme.surfaceContainerHighest
                        : dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                title: Text(
                  accountName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: returnLabel(),
                trailing: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 110),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      valueText,
                      const SizedBox(height: 2),
                      changeText,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
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
    super.key,
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
                style: TextStyle(color: colorScheme.onSurface, fontSize: 13),
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
                  style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small card showing a favorited symbol's latest price and selected period change,
/// used in the favorites row on the portfolio landing view.
class _FavoriteCard extends StatelessWidget {
  final String symbol;
  final String displayName;
  final DateTime periodStart;
  final int periodDays;
  final (DateTime, DateTime)? visibleRange;
  final bool intraday;
  final IntradaySeries? intradaySeries;
  final bool isActive;
  final bool selected;
  final Color selectionColor;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _FavoriteCard({
    required this.symbol,
    required this.displayName,
    required this.periodStart,
    required this.periodDays,
    this.visibleRange,
    required this.intraday,
    this.intradaySeries,
    required this.isActive,
    required this.selected,
    required this.selectionColor,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final stream = isActive && !intraday
        ? (marketDataDatabase.candles.select()
              ..where(
                (candle) =>
                    candle.symbol.equals(canonicalMarketSymbol(symbol)) &
                    candle.date.isBiggerThanValue(periodStart),
              )
              ..orderBy([
                (candle) => OrderingTerm(
                      expression: candle.date,
                      mode: OrderingMode.desc,
                    ),
              ])
              ..limit(periodDays > 0 ? periodDays : -1))
            .watch()
        : const Stream<List<StoredCandle>>.empty();

    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        width: 108,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected ? selectionColor.withValues(alpha: 0.10) : null,
          border: Border.all(
            color: selected
                ? selectionColor
                : colorScheme.outline.withValues(alpha: 0.3),
            width: selected ? 2 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            onLongPress: onLongPress,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          displayName,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (selected)
                        Icon(
                          Icons.check_circle_rounded,
                          size: 14,
                          color: selectionColor,
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  StreamBuilder<List<StoredCandle>>(
                    stream: intraday
                        ? Stream.value([
                            for (final bar
                                in intradaySeries?.candles.reversed ??
                                    <IbkrHistoricalCandle>[])
                              StoredCandle(
                                symbol: canonicalMarketSymbol(symbol),
                                date: bar.date.toLocal(),
                                open: bar.open,
                                high: bar.high,
                                low: bar.low,
                                close: bar.close,
                                adjClose: bar.close,
                                volume: bar.volume,
                              ),
                          ])
                        : stream,
                    builder: (context, snapshot) {
                      final candles = snapshot.data;
                      if (candles == null || candles.isEmpty) {
                        return const SizedBox(height: 14, width: 14);
                      }
                      final range = visibleRange;
                      final visibleCandles = range == null
                          ? candles
                          : candles
                              .where(
                                (candle) =>
                                    !candle.date.isBefore(range.$1) &&
                                    !candle.date.isAfter(range.$2),
                              )
                              .toList();
                      if (visibleCandles.isEmpty) {
                        return const SizedBox(height: 14, width: 14);
                      }
                      final centDivisor = symbolCentDivisor(symbol);
                      final price = visibleCandles.first.close / centDivisor;
                      final pct = visibleCandles.length > 1
                          ? safePercentChange(
                              visibleCandles.last.close,
                              visibleCandles.first.close,
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
                          const SizedBox(height: 8),
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
      ),
    );
  }
}

class _RenameFavoriteDialog extends StatefulWidget {
  const _RenameFavoriteDialog({required this.currentName});

  final String currentName;

  @override
  State<_RenameFavoriteDialog> createState() => _RenameFavoriteDialogState();
}

class _RenameFavoriteDialogState extends State<_RenameFavoriteDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.text('Rename favorite')),
      content: TextField(
        controller: _controller,
        decoration: InputDecoration(labelText: context.l10n.text('Name')),
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        onSubmitted: (value) => Navigator.pop(context, value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.text('Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(context.l10n.text('Rename')),
        ),
      ],
    );
  }
}
