import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:market_monk/adaptive_layout.dart';
import 'package:market_monk/bottom_nav.dart';
import 'package:market_monk/chart_colors.dart';
import 'package:market_monk/currency_buttons.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/desktop_context_menu.dart';
import 'package:market_monk/empty_state.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/ibkr_cash_out_pnl.dart';
import 'package:market_monk/l10n/app_localizations.dart';
import 'package:market_monk/logging.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/market_donut_chart.dart';
import 'package:market_monk/market_data_store.dart';
import 'package:market_monk/profile_data_repository.dart';
import 'package:market_monk/profile_picker.dart';
import 'package:market_monk/portfolio_returns.dart';
import 'package:market_monk/portfolio_allocation.dart';
import 'package:market_monk/portfolio_period_picker.dart';
import 'package:market_monk/settings_page.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/sqlite_settings.dart';
import 'package:market_monk/ticker_context_actions.dart';
import 'package:market_monk/utils.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

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
  final DateTime? asOfDate;

  const _LoadedPortfolio({
    required this.positions,
    required this.netLiquidation,
    required this.netLiquidationUsd,
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

  const PortfolioPage({
    super.key,
    this.isActive = true,
    Future<IbkrPortfolioSnapshot> Function(IbkrAccountConfig)? ibkrLoader,
    Future<IbkrPerformanceSeries> Function(IbkrAccountConfig, String)?
        ibkrPerformanceLoader,
    Future<ShareResult> Function(ShareParams)? shareFile,
    Future<void> Function(File, List<int>)? writeShareFile,
  })  : _ibkrLoader = ibkrLoader,
        _ibkrPerformanceLoader = ibkrPerformanceLoader,
        _shareFile = shareFile,
        _writeShareFile = writeShareFile;

  @override
  State<PortfolioPage> createState() => PortfolioPageState();
}

class PortfolioPageState extends State<PortfolioPage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  @override
  bool get wantKeepAlive => true;

  late Stream<_LoadedPortfolio> _stream;
  List<Position> _positions = [];
  IbkrAccountValue? _netLiquidation;
  bool _hasCachedPortfolio = false;
  int _pendingRemoteLoads = 0;

  Future<T> _withRemoteLoading<T>(Future<T> Function() load) async {
    if (mounted) setState(() => _pendingRemoteLoads++);
    try {
      return await load();
    } finally {
      if (mounted) setState(() => _pendingRemoteLoads--);
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
  ];
  int _period = 0;
  String? _historyAccount;
  Map<String, List<StoredCandle>> _returnCandles = {};
  List<Trade> _returnTrades = [];
  bool _historyLoading = false;
  bool _historyFailed = false;

  List<int> _availablePeriods = const [0];

  DateTime? get _returnCutoff => portfolioReturnCutoff(_period, DateTime.now());

  List<int> _coveredPeriods(
    List<Position> positions,
    IbkrPerformanceSeries? performance,
    IbkrAccountValue? netLiquidation,
  ) {
    if (_historyLoading || _historyFailed) return const [0];
    if (performance != null &&
        netLiquidation != null &&
        performance.dates.isNotEmpty) {
      final knownDates = [
        ...performance.dates,
        ..._returnTrades.map((trade) => trade.tradeDate),
      ];
      final firstKnownDate = knownDates.reduce(
        (first, second) => first.isBefore(second) ? first : second,
      );
      return [
        0,
        for (var period = 1; period < _periods.length; period++)
          if (!portfolioReturnCutoff(period, DateTime.now())!
                  .isBefore(firstKnownDate) &&
              (accountPeriodReturn(
                        performance,
                        netLiquidation.value,
                        portfolioReturnCutoff(period, DateTime.now())!,
                      ) !=
                      null ||
                  positions.every(
                    (position) =>
                        _holdingReturn(position, period: period) != null,
                  )) &&
              _allocationAt(positions, period) != null)
            period,
      ];
    }
    final dates = _returnTrades.isNotEmpty
        ? _returnTrades.map((trade) => trade.tradeDate).toList()
        : [
            for (final candles in _returnCandles.values)
              ...candles.map((candle) => candle.date),
          ];
    if (dates.isEmpty) return const [0];
    dates.sort();
    return [
      0,
      for (var period = 1; period < _periods.length; period++)
        if (!portfolioReturnCutoff(period, DateTime.now())!
                .isBefore(dates.first) &&
            positions.every(
              (position) => _holdingReturn(position, period: period) != null,
            ) &&
            _allocationAt(positions, period) != null)
          period,
    ];
  }

  List<PortfolioAllocation>? _allocationAt(
    List<Position> positions,
    int period,
  ) =>
      portfolioAllocationAt(
        positions: positions,
        trades: _returnTrades,
        candles: _returnCandles,
        date: portfolioReturnCutoff(period, DateTime.now()),
      );

  Future<void> _loadReturnHistory(
    String account,
    List<Position> positions,
  ) async {
    _historyAccount = account;
    _historyLoading = true;
    _historyFailed = false;
    _returnCandles = {};
    _returnTrades = [];
    final accounts = context.read<AccountManager>();
    final accountName = accounts.activeAccount;
    try {
      final trades =
          await profileDataRepository.readTradesForAccount(accountName);
      if (!mounted || _historyAccount != account) return;
      final candles = <String, List<StoredCandle>>{};
      final symbols = {
        for (final position in positions) position.symbol,
        for (final trade in trades) trade.symbol,
      };
      for (final symbol in symbols) {
        candles[symbol] = await (marketDataDatabase.candles.select()
              ..where(
                (row) => row.symbol.equals(canonicalMarketSymbol(symbol)),
              ))
            .get();
        candles[symbol]!.sort((a, b) => a.date.compareTo(b.date));
      }
      if (!mounted || _historyAccount != account) return;
      setState(() {
        _returnTrades = trades;
        _returnCandles = candles;
        _historyLoading = false;
      });
    } catch (error, stack) {
      talker.handle(error, stack, 'Failed to load portfolio return history');
      if (!mounted || _historyAccount != account) return;
      setState(() {
        _historyLoading = false;
        _historyFailed = true;
      });
    }
  }

  PortfolioReturn? _holdingReturn(Position position, {int? period}) {
    final cutoff = portfolioReturnCutoff(period ?? _period, DateTime.now());
    if (cutoff == null) {
      return PortfolioReturn(position.unrealizedPL, position.costBasis);
    }
    if (_historyLoading || _historyFailed) return null;
    final trades = _returnTrades
        .where((trade) => trade.symbol == position.symbol)
        .toList()
      ..sort((a, b) => a.tradeDate.compareTo(b.tradeDate));
    if (trades.isNotEmpty &&
        trades.every(
          (trade) => DateTime(
            trade.tradeDate.year,
            trade.tradeDate.month,
            trade.tradeDate.day,
          ).isAfter(cutoff),
        ) &&
        (trades.fold<double>(0, (sum, trade) => sum + trade.quantity) -
                    position.netShares)
                .abs() <
            1e-6) {
      return PortfolioReturn(position.unrealizedPL, position.costBasis);
    }
    StoredCandle? baseline;
    for (final candle in _returnCandles[position.symbol] ?? <StoredCandle>[]) {
      if (!candle.date.isAfter(cutoff)) baseline = candle;
    }
    if (baseline == null || cutoff.difference(baseline.date).inDays > 7)
      return null;
    final currency = normalizedQuoteCurrency(
      baseline.rawCurrency ?? symbolCurrency(position.symbol),
    );
    final basis = position.netShares *
        baseline.close /
        candleCentDivisor(baseline) /
        requireUsdRate(currency);
    if (trades
        .any((trade) => verifiedTradeAmountUsd(trade, trade.price) == null))
      return null;
    if (trades.isEmpty)
      return PortfolioReturn(position.currentValue - basis, basis);
    return openHoldingPeriodReturn(
      currentValue: position.currentValue,
      currentShares: position.netShares,
      baselinePrice: basis / position.netShares,
      cutoff: cutoff,
      trades: [
        for (final trade in trades)
          (
            date: trade.tradeDate,
            quantity: trade.quantity,
            price: tradeAmountUsd(trade, trade.price)
          ),
      ],
    );
  }

  Widget _periodPicker() {
    final now = DateTime.now();
    final past = _availablePeriods.where((period) => period != 0).toList()
      ..sort(
        (a, b) => portfolioReturnCutoff(b, now)!
            .compareTo(portfolioReturnCutoff(a, now)!),
      );
    final ordered = [0, ...past];
    return PortfolioPeriodPicker(
      labels: [
        for (final period in ordered) period == 0 ? 'Now' : _periods[period],
      ],
      dates: [for (final period in ordered) portfolioReturnCutoff(period, now)],
      value: ordered.indexOf(_period),
      onChanged: (index) => setState(() {
        _period = ordered[index];
        touchedIndex = null;
      }),
    );
  }

  Object? _loadError;
  int? touchedIndex;
  List<String> _chartFavorites = [];
  final _allocationScrollController = ScrollController();
  final _returnScrollController = ScrollController();
  String _lastAccount = '';
  int _lastIbkrRefreshVersion = -1;
  IbkrAccountConfig _lastIbkrConfig = const IbkrAccountConfig();
  final Map<(String, IbkrAccountConfig), Future<IbkrPortfolioSnapshot>>
      _ibkrSnapshotLoads = {};
  final Map<(String, IbkrAccountConfig), Future<IbkrPerformanceSeries>>
      _ibkrPerformanceLoads = {};
  final Map<(String, bool), Future<void>> _preloadLoads = {};

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

    setState(() => _stream = _buildStream());
    if (widget.isActive) {
      runDetachedTask(_preload(), 'Failed to preload portfolio');
      runDetachedTask(_loadChartFavorites(), 'Failed to load chart colors');
    }
  }

  Future<void> _loadChartFavorites() async {
    final prefs = await SqliteSettings.getInstance();
    if (!mounted) return;
    final favorites = prefs.getStringList('favoriteStocks') ?? [];
    if (!listEquals(favorites, _chartFavorites)) {
      setState(() => _chartFavorites = favorites);
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
    _lastAccount = account;
    _lastIbkrConfig = ibkrConfig;
    _lastIbkrRefreshVersion = refreshVersion;
    setState(() {
      _stream = _buildStream(skipInitial: widget.isActive);
      _positions = cached?.positions ?? [];
      _netLiquidation = cached?.netLiquidation;
      _hasCachedPortfolio = cached != null;
      if (accountChanged) _period = 0;
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

  Future<_LoadedPortfolio> _loadPortfolio(
    String accountName,
    List<Trade> trades,
    IbkrAccountConfig config, {
    bool refreshIfStale = false,
    bool forceRefresh = false,
  }) async {
    if (!widget.isActive) {
      final cached = context.read<AccountManager>().portfolioCacheFor(
            accountName,
          );
      return _LoadedPortfolio(
        positions: cached?.positions ?? _positions,
        netLiquidation: cached?.netLiquidation ?? _netLiquidation,
        netLiquidationUsd: cached?.netLiquidationUsd,
        asOfDate: cached?.asOfDate,
      );
    }
    if (!config.enabled) {
      final symbols = trades.map((trade) => trade.symbol).toSet().toList();
      if (!widget.isActive) {
        return _LoadedPortfolio(
          positions: _positions,
          netLiquidation: _netLiquidation,
          netLiquidationUsd: null,
        );
      }
      final prices = await fetchLatestPrices(symbols);
      return _LoadedPortfolio(
        positions: computePositions(trades, prices),
        netLiquidation: null,
        netLiquidationUsd: null,
      );
    }

    final accounts = context.read<AccountManager>();
    final cached = accounts.portfolioCacheFor(accountName);
    final cacheFresh = accounts.isPortfolioCacheFresh(accountName);
    final shouldUseCache = cached != null &&
        !forceRefresh &&
        (!refreshIfStale || cacheFresh || !config.isConfigured);
    if (shouldUseCache) {
      return _LoadedPortfolio(
        positions: cached.positions,
        netLiquidation: cached.netLiquidation,
        netLiquidationUsd: cached.netLiquidationUsd,
        asOfDate: cached.asOfDate,
      );
    }

    if (!config.isConfigured) {
      if (cached != null) {
        return _LoadedPortfolio(
          positions: cached.positions,
          netLiquidation: cached.netLiquidation,
          netLiquidationUsd: cached.netLiquidationUsd,
        );
      }
      throw StateError('IBKR portfolio source is not fully configured');
    }

    if (!widget.isActive) {
      return _LoadedPortfolio(
        positions: cached?.positions ?? _positions,
        netLiquidation: cached?.netLiquidation ?? _netLiquidation,
        netLiquidationUsd: cached?.netLiquidationUsd,
        asOfDate: cached?.asOfDate,
      );
    }
    final loadKey = (accountName, config);
    final snapshot = await _ibkrSnapshotLoads.putIfAbsent(loadKey, () async {
      try {
        return await _withRemoteLoading(
          () =>
              widget._ibkrLoader?.call(config) ??
              IbkrApiClient(config).fetchPortfolio(),
        );
      } finally {
        _ibkrSnapshotLoads.removeWhere((key, value) => key == loadKey);
      }
    });
    cacheIbkrAccountExchangeRate(snapshot);
    return _LoadedPortfolio(
      positions: await computeIbkrPositions(snapshot.positions, trades),
      netLiquidation: snapshot.netLiquidation,
      netLiquidationUsd: snapshot.netLiquidationUsd?.value,
      asOfDate: snapshot.asOfDate,
    );
  }

  Future<void> _loadIbkrCashOutPerformance(
    String accountName,
    IbkrAccountConfig config, {
    bool forceRefresh = false,
  }) async {
    if (!widget.isActive || !config.enabled || !config.isConfigured) return;

    const period = '1Y';
    final accounts = context.read<AccountManager>();
    final cached = accounts.ibkrPerformanceCacheFor(accountName, period);
    if (!forceRefresh &&
        cached != null &&
        accounts.isIbkrPerformanceCacheFresh(accountName, period)) {
      return;
    }

    if (!widget.isActive) return;
    try {
      final performance = await _fetchIbkrPerformanceOnce(
        accountName,
        config,
        period,
      );
      await accounts.cacheIbkrPerformance(accountName, performance);
    } catch (error, stackTrace) {
      talker.handle(
        error,
        stackTrace,
        'Failed to load IBKR cash-out performance',
      );
    }
  }

  Future<IbkrPerformanceSeries> _fetchIbkrPerformanceOnce(
    String accountName,
    IbkrAccountConfig config,
    String period,
  ) {
    final loadKey = (accountName, config);
    return _ibkrPerformanceLoads.putIfAbsent(loadKey, () async {
      try {
        return await (widget._ibkrPerformanceLoader?.call(config, period) ??
            IbkrApiClient(config).fetchPerformance(period));
      } finally {
        _ibkrPerformanceLoads.removeWhere((key, value) => key == loadKey);
      }
    });
  }

  Future<void> _preload({bool forceRefresh = false}) {
    final accountName = context.read<AccountManager>().activeAccount;
    final key = (accountName, forceRefresh);
    final existing = _preloadLoads[key];
    if (existing != null) return existing;

    late final Future<void> future;
    future = _performPreload(forceRefresh: forceRefresh).whenComplete(() {
      _preloadLoads.removeWhere(
        (entryKey, value) => entryKey == key && identical(value, future),
      );
    });
    _preloadLoads[key] = future;
    return future;
  }

  Future<void> _performPreload({bool forceRefresh = false}) async {
    if (!mounted || !widget.isActive) return;
    final accounts = context.read<AccountManager>();
    final accountName = accounts.activeAccount;
    final config = accounts.ibkrConfigFor(accountName);
    final cachedBefore = accounts.portfolioCacheFor(accountName);
    final cacheWasFresh = accounts.isPortfolioCacheFresh(accountName);
    final willFetchIbkr = config.enabled &&
        config.isConfigured &&
        (forceRefresh || cachedBefore == null || !cacheWasFresh);
    if (_loadError != null && mounted) {
      setState(() => _loadError = null);
    }
    try {
      final trades =
          await profileDataRepository.readTradesForAccount(accountName);
      if (!mounted ||
          !widget.isActive ||
          accounts.activeAccount != accountName) {
        return;
      }
      final loaded = await _loadPortfolio(
        accountName,
        trades,
        config,
        refreshIfStale: true,
        forceRefresh: forceRefresh,
      );
      if (!config.enabled || willFetchIbkr) {
        await accounts.cachePortfolio(
          accountName,
          loaded.positions,
          loaded.netLiquidation,
          netLiquidationUsd: loaded.netLiquidationUsd,
          asOfDate: loaded.asOfDate,
        );
      }
      if (!mounted ||
          !widget.isActive ||
          accounts.activeAccount != accountName) {
        return;
      }
      setState(() {
        _positions = loaded.positions;
        _netLiquidation = loaded.netLiquidation;
        _hasCachedPortfolio = true;
        _loadError = null;
      });
      runDetachedTask(
        _loadIbkrCashOutPerformance(
          accountName,
          config,
          forceRefresh: forceRefresh,
        ),
        'Failed to refresh IBKR performance history',
      );
    } catch (error, stackTrace) {
      if (mounted && widget.isActive && accounts.activeAccount == accountName) {
        setState(() => _loadError = error);
      }
      talker.handle(error, stackTrace, 'Failed to preload portfolio positions');
    }
  }

  Future<void> _syncAllInBackground() async {
    if (!mounted || !widget.isActive) return;
    final accounts = context.read<AccountManager>();
    final accountName = accounts.activeAccount;
    final config = accounts.ibkrConfigFor(accountName);
    try {
      final useIbkr = config.enabled;
      final trades =
          await profileDataRepository.readTradesForAccount(accountName);
      if (!mounted ||
          !widget.isActive ||
          accounts.activeAccount != accountName) {
        return;
      }
      final loaded = await _loadPortfolio(accountName, trades, config);
      final positions = loaded.positions;
      final symbols = useIbkr
          ? positions.map((position) => position.symbol).toSet()
          : trades.map((trade) => trade.symbol).toSet();
      for (final symbol in symbols) {
        if (!mounted ||
            !widget.isActive ||
            accounts.activeAccount != accountName) {
          return;
        }
        await syncCandles(
          symbol,
          ibkrConfig: config,
          syncNamespace: accountName,
        );
      }
      if (!mounted || accounts.activeAccount != accountName) return;
      setState(() {
        _historyAccount = null;
        _positions = positions;
        _netLiquidation = loaded.netLiquidation;
        _hasCachedPortfolio = true;
      });
    } catch (error, stackTrace) {
      talker.handle(error, stackTrace, 'Background portfolio sync failed');
    }
  }

  Stream<_LoadedPortfolio> _buildStream({bool skipInitial = false}) {
    final accounts = context.read<AccountManager>();
    final accountName = accounts.activeAccount;
    final cached = accounts.portfolioCacheFor(accountName);
    if (!widget.isActive) {
      return Stream.value(
        _LoadedPortfolio(
          positions: cached?.positions ?? _positions,
          netLiquidation: cached?.netLiquidation ?? _netLiquidation,
          netLiquidationUsd: cached?.netLiquidationUsd,
        ),
      );
    }

    final config = accounts.ibkrConfigFor(accountName);
    Stream<List<Trade>> trades =
        profileDataRepository.watchTradesForAccount(accountName);
    if (skipInitial) trades = trades.skip(1);
    return trades.asyncMap(
      (rows) => _loadPortfolioForStream(accountName, rows, config, accounts),
    );
  }

  Future<_LoadedPortfolio> _loadPortfolioForStream(
    String accountName,
    List<Trade> trades,
    IbkrAccountConfig config,
    AccountManager accounts,
  ) async {
    if (widget.isActive) {
      return _loadPortfolio(accountName, trades, config);
    }

    final cached = accounts.portfolioCacheFor(accountName);
    return _LoadedPortfolio(
      positions: cached?.positions ?? const [],
      netLiquidation: cached?.netLiquidation,
      netLiquidationUsd: cached?.netLiquidationUsd,
    );
  }

  Future<void> _updateCandles() async {
    _historyAccount = null;
    clearAllSyncCache();
    await _preload(forceRefresh: true);
    await _syncAllInBackground();
  }

  ({String fileName, Uint8List bytes}) _portfolioCsv(
    String accountName,
    List<Position> positions,
  ) {
    final dateFmt = DateFormat('yyyy-MM-dd');
    final rows = <List<dynamic>>[
      [
        'Symbol',
        'Name',
        'Shares',
        'Avg Cost',
        'Current Price',
        'Current Value',
        'Cost Basis',
        'Unrealized P/L',
        '% Change',
        'Last Purchase Date',
      ],
      for (final position in positions)
        [
          position.symbol,
          position.name,
          position.netShares.toStringAsFixed(6),
          position.avgCost.toStringAsFixed(4),
          position.currentPrice.toStringAsFixed(4),
          position.currentValue.toStringAsFixed(2),
          position.costBasis.toStringAsFixed(2),
          position.unrealizedPL.toStringAsFixed(2),
          position.change.toStringAsFixed(2),
          dateFmt.format(position.lastBuyDate),
        ],
    ];
    final content = '${Csv(lineDelimiter: '\n').encode(rows)}\n';

    final safeName = accountName.replaceAll(RegExp(r'[^\w-]'), '_');
    return (
      fileName: 'positions_$safeName.csv',
      bytes: Uint8List.fromList(utf8.encode(content)),
    );
  }

  Future<void> _exportCsv(
    BuildContext context,
    List<Position> positions,
  ) async {
    final accountName = context.read<AccountManager>().activeAccount;
    final csv = _portfolioCsv(accountName, positions);
    final path = await FilePicker.saveFile(
      fileName: csv.fileName,
      bytes: csv.bytes,
    );
    if (path == null) return;
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      await File(path.toFilePath()).writeAsBytes(csv.bytes);
    }
    talker.info('Exported portfolio CSV with ${positions.length} positions');
  }

  Future<void> _shareCsv(
    BuildContext context,
    List<Position> positions,
  ) async {
    if (!_supportsFileSharing) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final failureMessage = context.l10n.text('Couldn’t share CSV');
    final shareTitle = context.l10n.text('Share CSV');
    try {
      final accountName = context.read<AccountManager>().activeAccount;
      final csv = _portfolioCsv(accountName, positions);
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/${csv.fileName}');
      if (widget._writeShareFile case final writer?) {
        await writer(file, csv.bytes);
      } else {
        await file.writeAsBytes(csv.bytes, flush: true);
      }
      await (widget._shareFile ?? SharePlus.instance.share)(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          subject: 'Portfolio Positions',
          title: shareTitle,
        ),
      );
    } catch (error, stackTrace) {
      talker.handle(error, stackTrace, 'Failed to share portfolio CSV');
      if (messenger?.mounted ?? false) {
        messenger!.showSnackBar(SnackBar(content: Text(failureMessage)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return DesktopContextMenu(
      actions: [
        DesktopMenuAction(
          context.l10n.text('Refresh'),
          () => runDetachedTask(
            _updateCandles(),
            'Failed to refresh portfolio',
          ),
        ),
      ],
      child: Scaffold(
        body: SafeArea(
          child: StreamBuilder<_LoadedPortfolio>(
            key: ValueKey(_lastAccount),
            stream: _stream,
            builder: (context, snapshot) => _buildBody(context, snapshot),
          ),
        ),
      ),
    );
  }

  void _retryPortfolio() {
    setState(() => _stream = _buildStream(skipInitial: true));
    runDetachedTask(
      _preload(forceRefresh: true),
      'Failed to retry portfolio preload',
    );
  }

  void _openSettings() {
    unawaited(
      Navigator.push(
        context,
        adaptivePageRoute(context, builder: (_) => const SettingsPage()),
      ),
    );
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
    try {
      final pnl = calculateIbkrCashOutPnlAt(performance, cutoff);
      if (pnl == null) return null;
      final basePerUsd = requireUsdRate(performance.currency);
      if (!basePerUsd.isFinite || basePerUsd <= 0) return null;
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
    final performance = accounts.ibkrPerformanceCacheFor(
      accounts.activeAccount,
      '1Y',
    );
    final hasLoadError = snap.hasError || _loadError != null;

    if (hasLoadError && positions.isEmpty) {
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
        setState(() {
          _positions = snap.data!.positions;
          _netLiquidation = snap.data!.netLiquidation;
          _hasCachedPortfolio = true;
        });
      });
    }
    if (positions.isEmpty) {
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
          onAction: () => Navigator.push(
            context,
            adaptivePageRoute(context, builder: (_) => const SettingsPage()),
          ),
        ),
      );
    }

    final historyKey =
        '${accounts.activeAccount}:${positions.map((p) => '${p.symbol}:${p.netShares}:${p.costBasis}').join(',')}';
    if (_historyAccount != historyKey) {
      unawaited(_loadReturnHistory(historyKey, positions));
    }

    _availablePeriods = _coveredPeriods(positions, performance, netLiquidation);
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
    final historicalCashOut =
        cutoff == null ? null : _ibkrCashOutSummaryAt(performance, cutoff);
    final totalGain = cutoff == null
        ? cashOutSummary?.gainUsd ?? costBasisGain
        : historicalCashOut?.gainUsd ?? double.nan;
    final totalGainPct = cutoff == null
        ? cashOutSummary?.gainPct ??
            (totalCost > 0 ? (costBasisGain / totalCost) * 100 : 0.0)
        : historicalCashOut?.gainPct ?? double.nan;

    final allocation = _allocationAt(positions, _period) ?? [];
    final allocationTotal =
        allocation.fold<double>(0, (sum, holding) => sum + holding.value);
    final historicalNav = cutoff == null || performance == null
        ? null
        : accountNetAssetValueAt(performance, cutoff);
    final displayTotal = cutoff == null
        ? netLiquidation == null
            ? fmtCurrency(totalValue)
            : fmtNativeCurrency(netLiquidation.value, netLiquidation.currency)
        : historicalNav == null
            ? fmtCurrency(allocationTotal)
            : fmtNativeCurrency(historicalNav, performance!.currency);
    final totalLabel = cutoff == null && netLiquidation == null
        ? 'Market value'
        : cutoff != null && historicalNav == null
            ? 'Holdings value'
            : 'Account value';
    final sorted = [...allocation]..sort((a, b) => b.value.compareTo(a.value));
    final currentBySymbol = {
      for (final position in positions) position.symbol: position,
    };

    final colors =
        _buildColors(context, [for (final position in sorted) position.symbol]);
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
        totalGain: totalGain,
        totalGainPct: totalGainPct,
        isCashOut: cutoff == null ? cashOutSummary != null : true,
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
                alignment: Alignment.center,
                children: [
                  if (slices.isEmpty)
                    Text('No holdings on this date')
                  else
                    MarketDonutChart(
                      slices: slices,
                      selectedIndex: selectedIndex,
                      onSelectionChanged: (index) {
                        if (index == touchedIndex) return;
                        setState(() => touchedIndex = index);
                      },
                      centerSpaceRadius: 55,
                      radius: 60,
                      selectedRadius: 75,
                    ),
                  if (selectedIndex != null)
                    IgnorePointer(
                      child: SizedBox(
                        width: 100,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              sorted[selectedIndex].symbol,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              sorted[selectedIndex].name,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 10),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
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
                  onTap: () => setState(
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

  Widget _buildDesktopAllocationChart({
    required List<MarketDonutSlice> slices,
    required List<PortfolioAllocation> sorted,
    required int? selectedIndex,
    required bool compact,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Stack(
      alignment: Alignment.center,
      children: [
        if (slices.isEmpty)
          Text('No holdings on this date')
        else
          MarketDonutChart(
            slices: slices,
            selectedIndex: selectedIndex,
            onSelectionChanged: (index) {
              if (index == touchedIndex) return;
              setState(() => touchedIndex = index);
            },
            centerSpaceRadius: compact ? 48 : 72,
            radius: compact ? 54 : 75,
            selectedRadius: compact ? 60 : 90,
          ),
        if (slices.isNotEmpty)
          IgnorePointer(
            child: SizedBox(
              width: compact ? 108 : 132,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    selectedIndex == null
                        ? context.l10n.text('Holdings')
                        : sorted[selectedIndex].symbol,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    selectedIndex == null
                        ? '${sorted.length} ${context.l10n.text('positions')}'
                        : fmtCurrency(sorted[selectedIndex].value),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDesktopPortfolio({
    required List<Position> positions,
    required List<PortfolioAllocation> sorted,
    required List<Color> colors,
    required List<MarketDonutSlice> slices,
    required int? selectedIndex,
    required String displayTotal,
    required String totalLabel,
    required double totalGain,
    required double totalGainPct,
    required bool isCashOut,
    required bool hasRefreshWarning,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final settings = context.watch<SettingsState>();
    final accounts = context.watch<AccountManager>();
    final allocationTotal =
        sorted.fold<double>(0, (sum, holding) => sum + holding.value);
    final byReturn = [...positions]..sort(
        (firstPosition, secondPosition) =>
            (_holdingReturn(secondPosition)?.percent ?? double.negativeInfinity)
                .compareTo(
          _holdingReturn(firstPosition)?.percent ?? double.negativeInfinity,
        ),
      );
    final currencyCount =
        positions.map((position) => position.nativeCurrency).toSet().length;
    final positionLabel = positions.length == 1 ? 'position' : 'positions';
    final currencyLabel = currencyCount == 1 ? 'currency' : 'currencies';
    final windowWidth = MediaQuery.sizeOf(context).width;
    final expandedActions = windowWidth >= 1280;
    final inlineCurrencies = settings.visibleCurrencies.length > 1 &&
        windowWidth >= 1080 + settings.visibleCurrencies.length * 70;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: SizedBox(
          height: constraints.maxHeight < 840 ? 840 : constraints.maxHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ProfilePicker(
                      key: const Key('portfolio-profile-picker'),
                      onExport: expandedActions
                          ? null
                          : () => runDetachedTask(
                                _exportCsv(context, positions),
                                'Failed to export portfolio CSV',
                              ),
                      onShare: !expandedActions && _supportsFileSharing
                          ? () => runDetachedTask(
                                _shareCsv(context, positions),
                                'Failed to share portfolio CSV',
                              )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${accounts.activeAccount} · ${context.l10n.text('Portfolio')}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${positions.length} $positionLabel · $currencyCount $currencyLabel',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (expandedActions) ...[
                      OutlinedButton.icon(
                        key: const Key('desktop-portfolio-export'),
                        onPressed: () => runDetachedTask(
                          _exportCsv(context, positions),
                          'Failed to export portfolio CSV',
                        ),
                        icon: const Icon(Icons.download_rounded),
                        label: Text(context.l10n.text('Export CSV')),
                      ),
                      const SizedBox(width: 8),
                      if (_supportsFileSharing) ...[
                        OutlinedButton.icon(
                          key: const Key('desktop-portfolio-share'),
                          onPressed: () => runDetachedTask(
                            _shareCsv(context, positions),
                            'Failed to share portfolio CSV',
                          ),
                          icon: const Icon(Icons.share_rounded),
                          label: Text(context.l10n.text('Share CSV')),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                    Tooltip(
                      message: context.l10n.text('Refresh'),
                      child: IconButton(
                        onPressed: _updateCandles,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ),
                    if (settings.visibleCurrencies.length > 1)
                      const SizedBox(width: 8),
                    if (inlineCurrencies)
                      const CurrencyButtons(
                        key: Key('portfolio-currency-buttons'),
                      ),
                    if (settings.visibleCurrencies.length > 1 &&
                        !inlineCurrencies)
                      PopupMenuButton<String>(
                        key: const Key('portfolio-currency-menu'),
                        onSelected: (value) => runDetachedTask(
                          settings.setDisplayCurrency(value),
                          'Failed to change display currency',
                        ),
                        itemBuilder: (_) => [
                          for (final currencyCode in settings.visibleCurrencies)
                            CheckedPopupMenuItem(
                              value: currencyCode,
                              checked: currencyCode == settings.displayCurrency,
                              child: Text(currencyCode),
                            ),
                        ],
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            border:
                                Border.all(color: colorScheme.outlineVariant),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                settings.displayCurrency,
                                style: theme.textTheme.labelLarge,
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.expand_more_rounded, size: 20),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                if (hasRefreshWarning) ...[
                  const SizedBox(height: 16),
                  _buildRefreshWarning(context),
                ],
                const SizedBox(height: 20),
                _periodPicker(),
                const SizedBox(height: 12),
                desktopMetricGrid(
                  key: const Key('desktop-portfolio-metrics'),
                  minCardWidth: 270,
                  cards: [
                    _DesktopPortfolioMetric(
                      label: context.l10n.text(totalLabel),
                      value: displayTotal,
                      icon: Icons.account_balance_wallet_outlined,
                    ),
                    _DesktopPortfolioMetric(
                      label: context.l10n.text('Market value'),
                      value: fmtCurrency(allocationTotal),
                      detail: context.l10n.text('Open stock positions'),
                      icon: Icons.show_chart_rounded,
                    ),
                    _DesktopPortfolioMetric(
                      label: context.l10n.text(
                        isCashOut
                            ? 'Total P/L'
                            : _period == 0
                                ? 'Unrealized P/L'
                                : 'Open holdings P/L',
                      ),
                      value: totalGain.isFinite
                          ? '${totalGain >= 0 ? '+' : ''}${fmtCurrency(totalGain)}'
                          : 'Unavailable',
                      detail: totalGainPct.isFinite
                          ? '${totalGainPct >= 0 ? '+' : ''}${totalGainPct.toStringAsFixed(2)}%'
                          : 'History does not cover this period',
                      valueColor:
                          totalGain >= 0 ? Colors.green : Colors.redAccent,
                      icon: totalGain >= 0
                          ? Icons.trending_up_rounded
                          : Icons.trending_down_rounded,
                    ),
                    _DesktopPortfolioMetric(
                      label: context.l10n.text('Positions'),
                      value: positions.length.toString(),
                      detail: context.l10n.text('Currently open'),
                      icon: Icons.view_list_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 7,
                        child: Card(
                          margin: EdgeInsets.zero,
                          clipBehavior: Clip.antiAlias,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.l10n.text('Allocation'),
                                  style: theme.textTheme.titleLarge,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _returnCutoff == null
                                      ? context.l10n.text(
                                          'How your stock portfolio is distributed',
                                        )
                                      : DateFormat.yMMMd()
                                          .format(_returnCutoff!),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 28),
                                Expanded(
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      final holdingsList = Scrollbar(
                                        key: const Key(
                                          'desktop-allocation-scrollbar',
                                        ),
                                        controller: _allocationScrollController,
                                        child: ListView.separated(
                                          controller:
                                              _allocationScrollController,
                                          padding:
                                              const EdgeInsets.only(right: 12),
                                          itemCount: sorted.length,
                                          separatorBuilder: (_, __) =>
                                              const SizedBox(height: 14),
                                          itemBuilder: (context, index) {
                                            final position = sorted[index];
                                            final allocationPct =
                                                allocationTotal > 0
                                                    ? position.value /
                                                        allocationTotal *
                                                        100
                                                    : 0.0;
                                            return _DesktopAllocationRow(
                                              color: colors[index],
                                              symbol: position.symbol,
                                              name: position.name,
                                              value: position.value,
                                              allocationPct: allocationPct,
                                              selected: selectedIndex == index,
                                              onTap: () => setState(
                                                () => touchedIndex =
                                                    touchedIndex == index
                                                        ? null
                                                        : index,
                                              ),
                                            );
                                          },
                                        ),
                                      );
                                      final compact =
                                          constraints.maxWidth < 600;
                                      final chart = Center(
                                        child: AspectRatio(
                                          aspectRatio: 1,
                                          child: _buildDesktopAllocationChart(
                                            slices: slices,
                                            sorted: sorted,
                                            selectedIndex: selectedIndex,
                                            compact: compact,
                                          ),
                                        ),
                                      );

                                      if (compact) {
                                        if (constraints.maxHeight < 280) {
                                          return Row(
                                            key: const Key(
                                              'desktop-allocation-compact',
                                            ),
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Expanded(flex: 4, child: chart),
                                              const SizedBox(width: 14),
                                              Expanded(
                                                flex: 6,
                                                child: holdingsList,
                                              ),
                                            ],
                                          );
                                        }

                                        return Column(
                                          key: const Key(
                                            'desktop-allocation-compact',
                                          ),
                                          children: [
                                            SizedBox(height: 220, child: chart),
                                            const SizedBox(height: 14),
                                            Expanded(child: holdingsList),
                                          ],
                                        );
                                      }

                                      return Row(
                                        children: [
                                          Expanded(flex: 5, child: chart),
                                          const SizedBox(width: 28),
                                          Expanded(
                                            flex: 6,
                                            child: holdingsList,
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 5,
                        child: Card(
                          margin: EdgeInsets.zero,
                          clipBehavior: Clip.antiAlias,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(22, 22, 10, 18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.l10n.text('Return by holding'),
                                  style: theme.textTheme.titleLarge,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _returnCutoff == null
                                      ? 'Current · open holdings'
                                      : 'Since ${DateFormat.yMMMd().format(_returnCutoff!)} · open holdings',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Expanded(
                                  child: Scrollbar(
                                    key: const Key('desktop-return-scrollbar'),
                                    controller: _returnScrollController,
                                    child: ListView.separated(
                                      controller: _returnScrollController,
                                      padding: const EdgeInsets.only(right: 24),
                                      itemCount: byReturn.length,
                                      separatorBuilder: (_, __) => Divider(
                                        height: 1,
                                        color: colorScheme.outlineVariant
                                            .withValues(
                                          alpha: 0.7,
                                        ),
                                      ),
                                      itemBuilder: (context, index) {
                                        final position = byReturn[index];
                                        return _DesktopReturnRow(
                                          position: position,
                                          periodReturn:
                                              _holdingReturn(position),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Color> _buildColors(BuildContext context, List<String> symbols) =>
      portfolioHoldingColors(
        Theme.of(context).colorScheme,
        symbols,
        accountCount: context.read<AccountManager>().accounts.length,
        favorites: _chartFavorites,
      );
}

class _DesktopPortfolioMetric extends StatelessWidget {
  final String label;
  final String value;
  final String? detail;
  final IconData icon;
  final Color? valueColor;

  const _DesktopPortfolioMetric({
    required this.label,
    required this.value,
    required this.icon,
    this.detail,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        constraints: const BoxConstraints(minHeight: 104),
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 21,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: valueColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      detail!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: valueColor ?? theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopAllocationRow extends StatelessWidget {
  final Color color;
  final String symbol;
  final String name;
  final double value;
  final double allocationPct;
  final bool selected;
  final VoidCallback onTap;

  const _DesktopAllocationRow({
    required this.color,
    required this.symbol,
    required this.name,
    required this.value,
    required this.allocationPct,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DesktopContextMenu(
      actionsBuilder: () => tickerContextActions(context, symbol),
      copyText:
          '$symbol $name ${fmtCurrency(value)} (${allocationPct.toStringAsFixed(2)}%)',
      copyLabel: context.l10n.text('Copy allocation'),
      child: Material(
        color: selected
            ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.45)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            symbol,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          fmtCurrency(value),
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                        Text(
                          '${allocationPct.toStringAsFixed(1)}%',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopReturnRow extends StatelessWidget {
  final Position position;

  final PortfolioReturn? periodReturn;

  const _DesktopReturnRow({required this.position, required this.periodReturn});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final change = periodReturn?.percent ?? double.nan;
    final positive = change >= 0;
    final color = positive ? Colors.green : Colors.redAccent;
    final pnl = periodReturn?.gain ?? double.nan;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        children: [
          Icon(
            positive ? Icons.trending_up_rounded : Icons.trending_down_rounded,
            size: 20,
            color: color,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  position.symbol,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                pnl.isFinite
                    ? (pnl >= 0 ? '+' : '') + fmtCurrency(pnl)
                    : 'Unavailable',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: pnl >= 0 ? Colors.green : Colors.redAccent,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                change.isFinite
                    ? '${positive ? '+' : ''}${change.toStringAsFixed(2)}%'
                    : '—',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PieHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;
  final Color backgroundColor;

  const _PieHeaderDelegate({
    required this.child,
    required this.height,
    required this.backgroundColor,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(color: backgroundColor, child: child);
  }

  @override
  bool shouldRebuild(covariant _PieHeaderDelegate oldDelegate) =>
      child != oldDelegate.child ||
      backgroundColor != oldDelegate.backgroundColor;
}

class _SummaryCard extends StatelessWidget {
  final String displayTotal;
  final String totalLabel;
  final double totalGain;
  final double totalGainPct;
  final VoidCallback onExport;
  final VoidCallback onShare;

  const _SummaryCard({
    required this.displayTotal,
    required this.totalLabel,
    required this.totalGain,
    required this.totalGainPct,
    required this.onExport,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final gainColor = totalGain >= 0 ? Colors.green : Colors.redAccent;
    final settings = context.watch<SettingsState>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            ProfilePicker(
              key: const Key('portfolio-profile-picker'),
              onExport: onExport,
              onShare: _supportsFileSharing ? onShare : null,
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  totalLabel,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                Text(
                  displayTotal,
                  key: const Key('portfolio-total-value'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(
                  totalGain.isFinite
                      ? '${totalGain >= 0 ? '+' : ''}${fmtCurrency(totalGain)}'
                          '  (${totalGainPct.toStringAsFixed(2)}%)'
                      : 'Return history unavailable',
                  style: TextStyle(color: gainColor, fontSize: 13),
                ),
              ],
            ),
            const Spacer(),
            if (settings.visibleCurrencies.length > 1)
              PopupMenuButton<String>(
                key: const Key('portfolio-currency-menu'),
                onSelected: (value) => runDetachedTask(
                  settings.setDisplayCurrency(value),
                  'Failed to change display currency',
                ),
                itemBuilder: (_) => [
                  for (final currencyCode in settings.visibleCurrencies)
                    CheckedPopupMenuItem(
                      value: currencyCode,
                      checked: currencyCode == settings.displayCurrency,
                      child: Text(currencyCode),
                    ),
                ],
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(settings.displayCurrency),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LegendTile extends StatelessWidget {
  final Color color;
  final String symbol;
  final String name;
  final double value;
  final double allocationPct;
  final double changePct;
  final bool isHighlighted;
  final VoidCallback onTap;

  const _LegendTile({
    required this.color,
    required this.symbol,
    required this.name,
    required this.value,
    required this.allocationPct,
    required this.changePct,
    required this.isHighlighted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return DesktopContextMenu(
      actionsBuilder: () => tickerContextActions(context, symbol),
      copyText:
          '$symbol $name ${fmtCurrency(value)} (${allocationPct.toStringAsFixed(2)}%)',
      copyLabel: context.l10n.text('Copy allocation'),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 0),
        onTap: onTap,
        selected: isHighlighted,
        leading: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        title: Text(symbol),
        subtitle: Text('${allocationPct.toStringAsFixed(1)}%'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              fmtCurrency(value),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: changePct >= 0 ? Colors.green : Colors.redAccent,
                  ),
            ),
            Text(
              changePct.isFinite
                  ? '${changePct >= 0 ? '+' : ''}${changePct.toStringAsFixed(2)}%'
                  : '—',
              style: TextStyle(
                fontSize: 13,
                color: changePct >= 0 ? Colors.green : Colors.redAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
