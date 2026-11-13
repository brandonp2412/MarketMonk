import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:market_monk/accounts/account_manager.dart';
import 'package:market_monk/adaptive_layout.dart';
import 'package:market_monk/app.dart';
import 'package:market_monk/bottom_nav.dart';
import 'package:market_monk/chart_colors.dart';
import 'package:market_monk/currency_buttons.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/desktop_context_menu.dart';
import 'package:market_monk/empty_state.dart';
import 'package:market_monk/holdings/symbol_summary.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/ibkr_cash.dart';
import 'package:market_monk/ibkr_cash_out_pnl.dart';
import 'package:market_monk/intraday_market_data.dart';
import 'package:market_monk/intraday_portfolio.dart';
import 'package:market_monk/l10n/app_localizations.dart';
import 'package:market_monk/logging.dart';
import 'package:market_monk/market_data_store.dart';
import 'package:market_monk/market_donut_chart.dart';
import 'package:market_monk/portfolio_allocation.dart';
import 'package:market_monk/portfolio_history.dart';
import 'package:market_monk/portfolio_intraday_cache.dart';
import 'package:market_monk/portfolio_period_picker.dart';
import 'package:market_monk/portfolio_returns.dart';
import 'package:market_monk/profile_data_repository.dart';
import 'package:market_monk/profile_picker.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/sqlite_settings.dart';
import 'package:market_monk/ticker_context_actions.dart';
import 'package:market_monk/trade_history_page.dart';
import 'package:market_monk/utils.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

part 'portfolio/csv_export.dart';
part 'portfolio/desktop_allocation.dart';
part 'portfolio/desktop_portfolio.dart';
part 'portfolio/portfolio_loading.dart';
part 'portfolio/portfolio_widgets.dart';
part 'portfolio/return_history.dart';

bool get _supportsFileSharing => switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.macOS ||
      TargetPlatform.windows =>
        true,
      _ => false,
    };

class _LoadedPortfolio {
  final List<Position> positions;
  final IbkrAccountValue? netLiquidation;
  final double? netLiquidationUsd;
  final IbkrAccountValue? cashBalance;
  final double? cashUsd;
  final DateTime? asOfDate;

  const _LoadedPortfolio({
    required this.positions,
    required this.netLiquidation,
    required this.netLiquidationUsd,
    this.cashBalance,
    this.cashUsd,
    this.asOfDate,
  });
}

class PortfolioPage extends StatefulWidget {
  final bool isActive;
  final Future<IbkrPortfolioSnapshot> Function(IbkrAccountConfig)? _ibkrLoader;
  final Future<IbkrPerformanceSeries> Function(IbkrAccountConfig, String)?
      _ibkrPerformanceLoader;
  final Future<ShareResult> Function(ShareParams)? _shareFile;
  final Future<void> Function(File, List<int>)? _writeShareFile;
  final IntradayMarketData? _intradayData;
  final Future<IbkrTradeHistory> Function(IbkrAccountConfig)?
      _historyTradeLoader;
  final PortfolioCandleSync? _historyCandleSync;
  final PortfolioHistoricalRate? _historyRateLoader;

  const PortfolioPage({
    super.key,
    this.isActive = true,
    Future<IbkrPortfolioSnapshot> Function(IbkrAccountConfig)? ibkrLoader,
    Future<IbkrPerformanceSeries> Function(IbkrAccountConfig, String)?
        ibkrPerformanceLoader,
    Future<ShareResult> Function(ShareParams)? shareFile,
    Future<void> Function(File, List<int>)? writeShareFile,
    IntradayMarketData? intradayData,
    Future<IbkrTradeHistory> Function(IbkrAccountConfig)? historyTradeLoader,
    PortfolioCandleSync? historyCandleSync,
    PortfolioHistoricalRate? historyRateLoader,
  })  : _ibkrLoader = ibkrLoader,
        _ibkrPerformanceLoader = ibkrPerformanceLoader,
        _shareFile = shareFile,
        _writeShareFile = writeShareFile,
        _intradayData = intradayData,
        _historyTradeLoader = historyTradeLoader,
        _historyCandleSync = historyCandleSync,
        _historyRateLoader = historyRateLoader;

  @override
  State<PortfolioPage> createState() => PortfolioPageState();
}

class PortfolioPageState extends State<PortfolioPage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final Map<String, int> _holdingColorIndices = {};
  void _updateState(VoidCallback update) {
    _retainBodyOnDeactivation = false;
    setState(update);
  }

  @override
  bool get wantKeepAlive => true;

  late Stream<_LoadedPortfolio> _stream;
  Widget? _portfolioBody;
  bool _retainBodyOnDeactivation = false;
  List<Position> _positions = [];
  IbkrAccountValue? _netLiquidation;
  bool _hasCachedPortfolio = false;
  int _pendingRemoteLoads = 0;

  Future<T> _withRemoteLoading<T>(Future<T> Function() load) async {
    if (mounted) _updateState(() => _pendingRemoteLoads++);
    try {
      return await load();
    } finally {
      if (mounted) _updateState(() => _pendingRemoteLoads--);
    }
  }

  static const _periods = [
    'All time',
    '5Y',
    '4Y',
    '3Y',
    '2Y',
    '1Y',
    '6M',
    '3M',
    '1M',
    '1W',
    '1D',
    '2M',
    '2W',
    '12H',
    '6H',
    '2H',
    '1H',
  ];
  int _period = 0;
  String? _historyAccount;
  // Cached candles are provisional until the full history has completed.
  String? _completedHistoryAccount;
  bool get _periodHistoryIncomplete =>
      _historyLoading ||
      (_historyRefreshing && _completedHistoryAccount != _historyAccount) ||
      // An existing broker-performance cache can contain only a few dates.
      // Do not expose those stops while fresher history is being fetched.
      _performanceLoadingAccounts.contains(_lastAccount) ||
      _intradayHistoryPending;
  Future<void>? _historyFuture;
  bool _forceHistoryRefresh = false;
  IbkrTradeHistory? _loadedTradeCache;
  Map<String, List<StoredCandle>> _returnCandles = {};
  List<Trade> _returnTrades = [];
  PortfolioHistory? _returnHistory;
  (
    List<Position>,
    PortfolioHistory?,
    IbkrPerformanceSeries?,
    bool
  )? _allocationCacheSource;
  final Map<(DateTime?, double?), List<PortfolioAllocation>?> _allocationCache =
      {};
  late final IntradayMarketData _returnIntraday =
      widget._intradayData ?? IntradayMarketData();
  List<IntradayPortfolioValue> _intradayValues = const [];
  final Map<String, IntradayPortfolioHolding> _intradayHoldings = {};
  double? _intradayCurrentValueUsd;
  bool _historyLoading = false;
  bool _historyRefreshing = false;
  bool _intradayHistoryPending = false;
  bool _historyFailed = false;

  List<int> _availablePeriods = const [0];

  DateTime? _inceptionDate;

  Widget _periodPicker() {
    final now = DateTime.now();
    final past = _availablePeriods.where((period) => period != 0).toList()
      ..sort(
        (a, b) => _cutoff(
          b,
          now,
        )!
            .compareTo(_cutoff(a, now)!),
      );
    final ordered = [0, ...past];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PortfolioPeriodPicker(
          key: ValueKey('portfolio-period-$_lastAccount'),
          loading: !_historyFailed && _periodHistoryIncomplete,
          labels: [
            for (final period in ordered)
              switch (true) {
                _ when period == 0 => 'Now',
                _ when period == -1 => 'Inception',
                _ => _periods[period],
              },
          ],
          dates: [for (final period in ordered) _cutoff(period, now)],
          value: ordered.indexOf(_period),
          onChanged: (index) => _updateState(() {
            _period = ordered[index];
            touchedIndex = null;
          }),
        ),
        if (_historyFailed)
          TextButton.icon(
            onPressed: () => _updateState(() => _historyAccount = null),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry account history'),
          ),
      ],
    );
  }

  Object? _loadError;
  int? touchedIndex;
  List<String> _chartFavorites = [];
  final _allocationScrollController = ScrollController();
  final _returnScrollController = ScrollController();
  String _lastAccount = '';
  SymbolSummary? _desktopHistorySummary;
  int _lastIbkrRefreshVersion = -1;
  IbkrAccountConfig _lastIbkrConfig = const IbkrAccountConfig();
  final Map<(String, IbkrAccountConfig), Future<IbkrPortfolioSnapshot>>
      _ibkrSnapshotLoads = {};
  final Map<(String, IbkrAccountConfig), Future<IbkrPerformanceSeries>>
      _ibkrPerformanceLoads = {};
  final Map<(String, bool), Future<void>> _preloadLoads = {};
  final Set<String> _performanceLoadingAccounts = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _stream = _buildStream(skipInitial: widget.isActive);
    runDetachedTask(_loadChartFavorites(), 'Failed to load chart colors');
  }

  @override
  void didUpdateWidget(covariant PortfolioPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive == widget.isActive) return;

    _retainBodyOnDeactivation = !widget.isActive;
    if (widget.isActive) {
      _stream = _buildStream();
      runDetachedTask(_preload(), 'Failed to preload portfolio');
      runDetachedTask(_loadChartFavorites(), 'Failed to load chart colors');
    }
  }

  Future<void> _loadChartFavorites() async {
    final prefs = await SqliteSettings.getInstance();
    if (!mounted) return;
    final favorites = prefs.getStringList('favoriteStocks') ?? [];
    if (!listEquals(favorites, _chartFavorites)) {
      _updateState(() => _chartFavorites = favorites);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final accounts = context.watch<AccountManager>();
    final account = accounts.activeAccount;
    final ibkrConfig = accounts.ibkrConfigFor(account);
    final refreshVersion = accounts.ibkrRefreshVersion;
    final cached = accounts.portfolioCacheFor(account);
    final hadAccount = _lastAccount.isNotEmpty;
    final accountChanged = account != _lastAccount;
    final refreshRequested =
        hadAccount && refreshVersion != _lastIbkrRefreshVersion;

    if (account == _lastAccount &&
        ibkrConfig == _lastIbkrConfig &&
        refreshVersion == _lastIbkrRefreshVersion) {
      return;
    }

    _historyAccount = null;
    if (accountChanged || ibkrConfig != _lastIbkrConfig) {
      _completedHistoryAccount = null;
      _intradayHistoryPending = false;
      _returnCandles = {};
      _returnTrades = [];
      _returnHistory = null;
      _intradayValues = const [];
      _intradayHoldings.clear();
      _intradayCurrentValueUsd = null;
    }
    _lastAccount = account;
    _lastIbkrConfig = ibkrConfig;
    _lastIbkrRefreshVersion = refreshVersion;
    _updateState(() {
      _stream = _buildStream(skipInitial: widget.isActive);
      _positions = cached?.positions ?? [];
      _netLiquidation = cached?.netLiquidation;
      _hasCachedPortfolio = cached != null;
      if (accountChanged) {
        _period = 0;
        _desktopHistorySummary = null;
      }
      touchedIndex = null;
    });
    if (widget.isActive) {
      runDetachedTask(
        _preload(forceRefresh: refreshRequested),
        'Failed to refresh portfolio preload',
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.isActive) {
      runDetachedTask(_preload(), 'Failed to preload portfolio');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _allocationScrollController.dispose();
    _returnScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!_retainBodyOnDeactivation || _portfolioBody == null) {
      _portfolioBody = StreamBuilder<_LoadedPortfolio>(
        key: ValueKey(_lastAccount),
        stream: _stream,
        builder: _buildBody,
      );
    }
    _retainBodyOnDeactivation = false;
    final summary = _desktopHistorySummary;
    if (isDesktopLayout(context) && summary != null) {
      return TradeHistoryPage(
        key: ValueKey('portfolio-history-$_lastAccount-${summary.symbol}'),
        summary: summary,
        onClose: () => _updateState(() => _desktopHistorySummary = null),
      );
    }
    return DesktopContextMenu(
      actions: [
        DesktopMenuAction(
          context.l10n.text('Refresh'),
          () =>
              runDetachedTask(_updateCandles(), 'Failed to refresh portfolio'),
          icon: Icons.refresh_rounded,
        ),
      ],
      child: Scaffold(
        body: SafeArea(
          child: _portfolioBody!,
        ),
      ),
    );
  }

  void _retryPortfolio() {
    _updateState(() => _stream = _buildStream(skipInitial: true));
    runDetachedTask(
      _preload(forceRefresh: true),
      'Failed to retry portfolio preload',
    );
  }

  void _openSettings() {
    openAppSettings(context);
  }

  Widget _buildLoadError(BuildContext context) {
    final ibkrEnabled = context.watch<AccountManager>().ibkrConfigFor().enabled;
    final title = ibkrEnabled
        ? 'Couldn’t load Interactive Brokers'
        : 'Couldn’t load portfolio';
    final message = ibkrEnabled
        ? 'MarketMonk couldn’t load your portfolio from your IBKR server. '
            'Check the server connection, then try again.'
        : 'MarketMonk couldn’t refresh your portfolio. Check your internet '
            'connection, then try again.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_off_outlined,
                    size: 48,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _retryPortfolio,
                        icon: const Icon(Icons.refresh),
                        label: Text(context.l10n.text('Try again')),
                      ),
                      if (ibkrEnabled)
                        OutlinedButton.icon(
                          onPressed: _openSettings,
                          icon: const Icon(Icons.settings_outlined),
                          label: Text(context.l10n.text('IBKR settings')),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRefreshWarning(BuildContext context) {
    final ibkrEnabled = context.watch<AccountManager>().ibkrConfigFor().enabled;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Icon(
              Icons.cloud_off_outlined,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                ibkrEnabled
                    ? 'Couldn’t refresh IBKR.'
                    : 'Couldn’t refresh market data.',
              ),
            ),
            TextButton(
              onPressed: _retryPortfolio,
              child: Text(context.l10n.text('Try again')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _refreshableState(Widget child) {
    return RefreshIndicator(
      triggerMode: RefreshIndicatorTriggerMode.anywhere,
      onRefresh: _updateCandles,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [SliverFillRemaining(child: child)],
      ),
    );
  }

  ({double gainUsd, double gainPct})? _ibkrCashOutSummary(
    IbkrPerformanceSeries? performance,
    IbkrAccountValue? netLiquidation,
  ) {
    if (performance == null || netLiquidation == null) return null;
    try {
      final pnl = calculateIbkrCashOutPnl(performance, netLiquidation);
      final basePerUsd = requireUsdRate(performance.currency);
      if (!basePerUsd.isFinite || basePerUsd <= 0) return null;
      return (gainUsd: pnl.profitLoss / basePerUsd, gainPct: pnl.percent ?? 0);
    } catch (_) {
      return null;
    }
  }

  ({double gainUsd, double gainPct})? _ibkrCashOutSummaryAt(
    IbkrPerformanceSeries? performance,
    DateTime cutoff,
  ) {
    if (performance == null) return null;
    if (performance.startNav == 0 && cutoff == performance.startDate) {
      return (gainUsd: 0, gainPct: 0);
    }
    try {
      final pnl = calculateIbkrCashOutPnlAt(performance, cutoff);
      if (pnl == null) return null;
      final index = accountNetAssetValueIndexAt(performance, cutoff);
      if (index == null) return null;
      final basePerUsd = _returnHistory?.rates[performance.dates[index]]
          ?[performance.currency.toUpperCase()];
      if (basePerUsd == null || !basePerUsd.isFinite || basePerUsd <= 0) {
        return null;
      }
      return (gainUsd: pnl.profitLoss / basePerUsd, gainPct: pnl.percent ?? 0);
    } catch (_) {
      return null;
    }
  }

  Widget _buildBody(
    BuildContext context,
    AsyncSnapshot<_LoadedPortfolio> snap,
  ) {
    final positions = snap.data?.positions ?? _positions;
    final netLiquidation = snap.data?.netLiquidation ?? _netLiquidation;
    final accounts = context.watch<AccountManager>();
    final cachedPortfolio = accounts.portfolioCacheFor();
    final navUsd =
        snap.data?.netLiquidationUsd ?? cachedPortfolio?.netLiquidationUsd;
    if (netLiquidation != null &&
        navUsd != null &&
        navUsd.isFinite &&
        navUsd > 0 &&
        netLiquidation.value.isFinite &&
        netLiquidation.value > 0) {
      allRatesFromUsd[netLiquidation.currency] = netLiquidation.value / navUsd;
    }
    final cashBalance = snap.data?.cashBalance ?? cachedPortfolio?.cashBalance;
    final cashUsd = snap.data?.cashUsd ??
        cachedPortfolio?.cashUsd ??
        ibkrCashValueUsd(
          cashBalance: cashBalance,
          netLiquidation:
              snap.data?.netLiquidation ?? cachedPortfolio?.netLiquidation,
          netLiquidationUsd: snap.data?.netLiquidationUsd ??
              cachedPortfolio?.netLiquidationUsd,
        );
    final performance = accounts.ibkrPerformanceCacheFor(
      accounts.activeAccount,
      '1Y',
    );
    final hasLoadError = snap.hasError || _loadError != null;

    if (hasLoadError && positions.isEmpty && cashBalance == null) {
      return _refreshableState(_buildLoadError(context));
    }

    if (positions.isEmpty && !snap.hasData && !_hasCachedPortfolio) {
      return _refreshableState(
        _pendingRemoteLoads > 0
            ? const Center(child: CircularProgressIndicator())
            : const SizedBox.shrink(),
      );
    }

    if (snap.hasData &&
        (snap.data!.positions != _positions ||
            snap.data!.netLiquidation != _netLiquidation)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _updateState(() {
          _positions = snap.data!.positions;
          _netLiquidation = snap.data!.netLiquidation;
          _hasCachedPortfolio = true;
        });
      });
    }
    if (positions.isEmpty && cashBalance == null) {
      final ibkrEnabled =
          context.watch<AccountManager>().ibkrConfigFor().enabled;
      return _refreshableState(
        AppEmptyState(
          icon: ibkrEnabled
              ? Icons.account_balance_rounded
              : Icons.pie_chart_outline_rounded,
          title: ibkrEnabled
              ? context.l10n.text('No IBKR stock positions')
              : context.l10n.text('No holdings yet'),
          message: ibkrEnabled
              ? context.l10n.text(
                  'Check your Interactive Brokers connection or refresh your account.',
                )
              : context.l10n.text(
                  'Import your trades to build your portfolio.',
                ),
          actionLabel: ibkrEnabled
              ? context.l10n.text('IBKR settings')
              : context.l10n.text('Import CSV'),
          actionIcon:
              ibkrEnabled ? Icons.settings_rounded : Icons.upload_file_rounded,
          onAction: () => openAppSettings(context),
        ),
      );
    }

    final historyKey = _returnHistoryKey(accounts, positions);
    final tradesChanged = !_historyRefreshing &&
        !_historyFailed &&
        !identical(
          _loadedTradeCache,
          accounts.ibkrTradeHistoryCacheFor(accounts.activeAccount),
        );
    if (widget.isActive && (_historyAccount != historyKey || tradesChanged)) {
      if (tradesChanged) _historyAccount = null;
      unawaited(_ensureReturnHistory(historyKey, positions));
    }

    _availablePeriods = _coveredPeriods(
      positions,
      performance,
      netLiquidation,
    );
    if (!_availablePeriods.contains(_period)) _period = _availablePeriods.first;

    final totalValue = positions.fold(
      0.0,
      (sum, position) => sum + position.currentValue,
    );
    final totalCost = positions.fold(
      0.0,
      (sum, position) => sum + position.costBasis,
    );
    final costBasisGain = totalValue - totalCost;
    final cashOutSummary = _ibkrCashOutSummary(performance, netLiquidation);
    final cutoff = _returnCutoff;
    final intraday = cutoff != null && _period >= firstIntradayPeriod;
    final intradayValueUsd =
        intraday ? intradayAccountValueAt(_intradayValues, cutoff) : null;
    final historicalCashOut = cutoff == null || intraday
        ? null
        : _ibkrCashOutSummaryAt(performance, cutoff);
    final totalGain = switch (true) {
      _ when cutoff == null => cashOutSummary?.gainUsd ?? costBasisGain,
      _ when intradayValueUsd != null && _intradayCurrentValueUsd != null =>
        _intradayCurrentValueUsd! - intradayValueUsd,
      _ => historicalCashOut?.gainUsd ?? double.nan,
    };
    final totalGainPct = switch (true) {
      _ when cutoff == null => cashOutSummary?.gainPct ??
          (totalCost > 0 ? (costBasisGain / totalCost) * 100 : 0.0),
      _
          when intradayValueUsd != null &&
              _intradayCurrentValueUsd != null &&
              intradayValueUsd != 0 =>
        (_intradayCurrentValueUsd! / intradayValueUsd - 1) * 100,
      _ => historicalCashOut?.gainPct ?? double.nan,
    };

    final allocation = intraday
        ? _intradayAllocationAt(positions, cutoff)!
        : _allocationAt(
            positions,
            _period,
            cashValueUsd: _returnCutoff == null ? cashUsd : null,
          )!;
    final allocationTotal = allocation.fold<double>(
      0,
      (sum, holding) => sum + holding.value,
    );
    final historicalNav = switch (true) {
      _ when cutoff == null || intraday || performance == null => null,
      _ when performance.startNav == 0 && cutoff == performance.startDate =>
        0.0,
      _ => accountNetAssetValueAt(performance, cutoff),
    };
    final navIndex = cutoff == null || performance == null
        ? null
        : accountNetAssetValueIndexAt(performance, cutoff);
    final historicalRate = navIndex == null
        ? null
        : _returnHistory?.rates[performance!.dates[navIndex]]
            ?[performance.currency.toUpperCase()];
    final String displayTotal;
    if (intraday && intradayValueUsd != null) {
      displayTotal = fmtCurrency(intradayValueUsd);
    } else if (cutoff == null) {
      if (netLiquidation == null) {
        displayTotal = fmtCurrency(totalValue + (cashUsd ?? 0));
      } else if (allRatesFromUsd.containsKey(netLiquidation.currency)) {
        displayTotal = fmtNativeCurrency(
          netLiquidation.value,
          netLiquidation.currency,
        );
      } else {
        displayTotal =
            NumberFormat.simpleCurrency(name: netLiquidation.currency)
                .format(netLiquidation.value);
      }
    } else if (historicalNav == null) {
      displayTotal = fmtCurrency(allocationTotal);
    } else if (historicalRate == null) {
      displayTotal = 'Unavailable';
    } else {
      displayTotal = fmtCurrency(historicalNav / historicalRate);
    }
    final totalLabel = switch (true) {
      _ when intraday => 'Account value',
      _ when cutoff == null && netLiquidation == null && cashUsd == null =>
        'Market value',
      _ when cutoff != null && historicalNav == null => 'Holdings value',
      _ => 'Account value',
    };
    final sorted = [...allocation]..sort((a, b) => b.value.compareTo(a.value));
    final currentBySymbol = {
      for (final position in positions) position.symbol: position,
    };

    final colors = _buildColors(context, [
      for (final position in sorted) position.symbol,
    ]);
    // Holdings can change while this page is kept alive (for example, after
    // switching accounts). Do not use a selection from the previous list.
    final selectedIndex = touchedIndex != null &&
            touchedIndex! >= 0 &&
            touchedIndex! < sorted.length
        ? touchedIndex
        : null;

    final slices = List.generate(
      sorted.length,
      (index) => MarketDonutSlice(
        value: sorted[index].value,
        color: colors[index],
        label: sorted[index].symbol,
      ),
    );

    if (isDesktopLayout(context)) {
      return _buildDesktopPortfolio(
        positions: positions,
        sorted: sorted,
        colors: colors,
        slices: slices,
        selectedIndex: selectedIndex,
        displayTotal: displayTotal,
        totalLabel: totalLabel,
        cashBalance: _returnCutoff == null ? cashBalance : null,
        totalGain: totalGain,
        totalGainPct: totalGainPct,
        isCashOut: cutoff == null ? cashOutSummary != null : !intraday,
        hasRefreshWarning: hasLoadError,
      );
    }

    return RefreshIndicator(
      triggerMode: RefreshIndicatorTriggerMode.anywhere,
      onRefresh: _updateCandles,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (hasLoadError)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: _buildRefreshWarning(context),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _SummaryCard(
                displayTotal: displayTotal,
                totalLabel: totalLabel,
                totalGain: totalGain,
                totalGainPct: totalGainPct,
                onExport: () => runDetachedTask(
                  _exportCsv(context, positions),
                  'Failed to export portfolio CSV',
                ),
                onShare: () => runDetachedTask(
                  _shareCsv(context, positions),
                  'Failed to share portfolio CSV',
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(36, 12, 36, 8),
              child: _periodPicker(),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _PieHeaderDelegate(
              height: 260,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              child: Stack(
                fit: StackFit.expand,
                alignment: Alignment.center,
                children: [
                  if (slices.isEmpty)
                    const Text('No holdings on this date')
                  else
                    MarketDonutChart(
                      slices: slices,
                      selectedIndex: selectedIndex,
                      onSelectionChanged: (index) {
                        if (index == touchedIndex) return;
                        _updateState(() => touchedIndex = index);
                      },
                      centerSpaceRadius: 55,
                      radius: 60,
                      selectedRadius: 75,
                    ),
                  if (selectedIndex != null)
                    IgnorePointer(
                      child: Center(
                        child: SizedBox(
                          width: 100,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                sorted[selectedIndex].symbol,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              Text(
                                sorted[selectedIndex].name,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.builder(
              itemCount: sorted.length,
              itemBuilder: (context, index) {
                final position = sorted[index];
                final val = position.value;
                final pct =
                    allocationTotal > 0 ? val / allocationTotal * 100 : 0.0;
                return _LegendTile(
                  color: colors[index],
                  symbol: position.symbol,
                  name: position.name,
                  value: val,
                  allocationPct: pct,
                  changePct: currentBySymbol[position.symbol] == null
                      ? double.nan
                      : _holdingReturn(currentBySymbol[position.symbol]!)
                              ?.percent ??
                          double.nan,
                  isHighlighted: index == selectedIndex,
                  onTap: () => _updateState(
                    () => touchedIndex = touchedIndex == index ? null : index,
                  ),
                );
              },
            ),
          ),
          const SliverToBoxAdapter(
            child: SizedBox(height: bottomNavScrollClearance),
          ),
        ],
      ),
    );
  }

  void _openHoldingHistory(Position position) {
    final trades = _returnTrades
        .where((trade) => trade.symbol == position.symbol)
        .toList();
    final summary = SymbolSummary(
      symbol: position.symbol,
      name: position.name,
      position: position,
      trades: trades,
    );
    if (isDesktopLayout(context)) {
      _updateState(() => _desktopHistorySummary = summary);
      return;
    }
    Navigator.of(context).push(
      adaptivePageRoute(
        context,
        builder: (_) => TradeHistoryPage(summary: summary),
      ),
    );
  }
}
