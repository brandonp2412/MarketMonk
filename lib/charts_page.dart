import 'dart:async';
import 'dart:math' show max, min;
import 'dart:math';

import 'package:drafter/drafter.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:market_monk/accounts/account_manager.dart';
import 'package:market_monk/adaptive_layout.dart';
import 'package:market_monk/app.dart';
import 'package:market_monk/background_network_coordinator.dart';
import 'package:market_monk/bottom_nav.dart';
import 'package:market_monk/candle_ticker.dart';
import 'package:market_monk/chart_colors.dart';
import 'package:market_monk/charts/chart_widgets.dart';
import 'package:market_monk/crypto_market_data.dart';
import 'package:market_monk/currency_buttons.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/desktop_context_menu.dart';
import 'package:market_monk/edit_ticker_page.dart';
import 'package:market_monk/empty_state.dart';
import 'package:market_monk/exchange_rate_service.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/ibkr_cash.dart';
import 'package:market_monk/intraday_market_data.dart';
import 'package:market_monk/intraday_portfolio.dart';
import 'package:market_monk/l10n/app_localizations.dart';
import 'package:market_monk/logging.dart';
import 'package:market_monk/market_chart_loading.dart';
import 'package:market_monk/market_data_store.dart';
import 'package:market_monk/market_line_chart.dart';
import 'package:market_monk/portfolio_chart_scale.dart';
import 'package:market_monk/profile_data_repository.dart';
import 'package:market_monk/provisional_portfolio.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/sqlite_settings.dart';
import 'package:market_monk/ticker_line.dart';
import 'package:market_monk/ticker_search_loading.dart';
import 'package:market_monk/utils.dart';
import 'package:market_monk/vi_navigation.dart';
import 'package:provider/provider.dart';

part 'charts/favorite_loading.dart';
part 'charts/favorite_widgets.dart';
part 'charts/portfolio_chart.dart';
part 'charts/portfolio_loading.dart';
part 'charts/portfolio_series.dart';
part 'charts/search_widgets.dart';
part 'charts/stock_chart.dart';
part 'charts/stock_loading.dart';
part 'charts/stock_summary.dart';

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
  final Future<void> Function(String, DateTime)? _favoriteHistoryPrefetcher;
  final Future<void> Function(String)? _localCandleSyncer;

  const ChartsPage({
    super.key,
    this.isActive = true,
    this.initialSymbol,
    IntradayMarketData? intradayData,
    Future<IbkrPortfolioSnapshot> Function(IbkrAccountConfig)? ibkrLoader,
    Future<IbkrPerformanceSeries> Function(IbkrAccountConfig, String)?
        ibkrPerformanceLoader,
    Future<void> Function(String, DateTime)? favoriteHistoryPrefetcher,
    Future<void> Function(String)? localCandleSyncer,
  })  : _intradayData = intradayData,
        _ibkrLoader = ibkrLoader,
        _ibkrPerformanceLoader = ibkrPerformanceLoader,
        _favoriteHistoryPrefetcher = favoriteHistoryPrefetcher,
        _localCandleSyncer = localCandleSyncer;

  @override
  State<ChartsPage> createState() => ChartsPageState();
}

class ChartsPageState extends State<ChartsPage>
    with AutomaticKeepAliveClientMixin {
  void _updateState(VoidCallback update) => setState(update);

  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  late final ViTarget _viTarget = ViTarget(
    requestSearch: () {
      _searchFocus.requestFocus();
      _searchController.selection =
          TextSelection.collapsed(offset: _searchController.text.length);
    },
    moveFocus: _moveViStockFocus,
  );

  _ChartMode _mode = _ChartMode.portfolio;
  String? _selectedSymbol;
  List<String> _favoriteStocks = [];
  Map<String, String> _favoriteNames = {};
  final Set<String> _selectedFavorites = {};
  Stream<List<StoredCandle>>? _favoriteChartStream;
  String _favoriteChartStreamKey = '';
  final _favoriteIntraday = <String, IntradaySeries>{};
  final _favoriteIntradayErrors = <String, String>{};
  Future<void> _favoriteDailySync = Future<void>.value();
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
  bool _pickingChartRange = false;

  Stream<List<CandleTicker>>? _stockStream;
  StreamSubscription<String>? _chartsFocusSubscription;
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
    _chartsFocusSubscription = ChartsFocusController.instance.requests.listen(
      _selectSymbol,
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
    _syncViTarget();
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
    runDetachedTask(
      _syncFavoriteCandles(selectedOnly: true),
      'Failed to reload selected favorite charts',
    );
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
    _syncViTarget();
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

  void _syncViTarget() {
    if (widget.isActive && isDesktopLayout(context)) {
      ViNavigation.instance.target = _viTarget;
    } else if (ViNavigation.instance.target == _viTarget) {
      ViNavigation.instance.target = null;
    }
  }

  @override
  void dispose() {
    if (ViNavigation.instance.target == _viTarget) {
      ViNavigation.instance.target = null;
    }
    _accountManager?.removeListener(_handleAccountManagerChanged);
    unawaited(_chartsFocusSubscription?.cancel());
    _provisionalRefreshTimer?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    _candleSelection.dispose();
    _yahooApi.dispose();
    _stockLoadGeneration++;
    _favoriteLoadGeneration++;
    super.dispose();
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
      _pickingChartRange = false;
      _customChartRange =
          range == null ? null : (dates[range.$1], dates[range.$2]);
    });
  }

  void _startChartRangePicker() {
    setState(() {
      _customChartRange = null;
      _pickingChartRange = true;
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
      _pickingChartRange = false;
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
      if (_mode == _ChartMode.stock) {
        _stockLoadGeneration++;
        _stockStream = null;
        _stockContentKey = null;
        _intradaySeries = null;
        _stockDailyPreview = const [];
        _networkLoading = true;
      }
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
      _pickingChartRange = false;
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
          icon: Icons.refresh_rounded,
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
                        children: [
                          _buildSearchBar(availableWidth: constraints.maxWidth),
                        ],
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
        triggerMode: RefreshIndicatorTriggerMode.anywhere,
        edgeOffset: _overlayHeight + 8,
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
    final enableCandles = !settings.showCandlesticks;
    runDetachedTask(
      settings.setShowCandlesticks(enableCandles),
      'Failed to save chart style',
    );
    if (enableCandles &&
        _mode == _ChartMode.stock &&
        !_usesIntraday &&
        cryptoAssetForSymbol(_selectedSymbol ?? '') != null) {
      runDetachedTask(
        _loadSelectedStock(forceRefresh: true),
        'Failed to load crypto candles',
      );
    }
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
        ChartPeriodChip(
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

    final picker = SingleChildScrollView(
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
    return isDesktopLayout(context) ? Center(child: picker) : picker;
  }

  static const double _stockSummaryHeight = 54;

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
        child: ChartActionChip(
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
        child: ChartActionChip(
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

  @override
  bool get wantKeepAlive => true;
}

class _DateValue {
  final DateTime date;
  final double value;

  const _DateValue(this.date, this.value);
}
