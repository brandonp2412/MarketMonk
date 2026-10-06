import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:market_monk/adaptive_layout.dart';
import 'package:market_monk/bottom_nav.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/empty_state.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/ibkr_cash_out_pnl.dart';
import 'package:market_monk/l10n/app_localizations.dart';
import 'package:market_monk/logging.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/market_donut_chart.dart';
import 'package:market_monk/profile_data_repository.dart';
import 'package:market_monk/settings_page.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/utils.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

class _LoadedPortfolio {
  final List<Position> positions;
  final IbkrAccountValue? netLiquidation;
  final double? netLiquidationUsd;

  const _LoadedPortfolio({
    required this.positions,
    required this.netLiquidation,
    required this.netLiquidationUsd,
  });
}

class PortfolioPage extends StatefulWidget {
  final bool isActive;
  final Future<IbkrPortfolioSnapshot> Function(IbkrAccountConfig)? _ibkrLoader;
  final Future<IbkrPerformanceSeries> Function(IbkrAccountConfig, String)?
      _ibkrPerformanceLoader;

  const PortfolioPage({
    super.key,
    this.isActive = true,
    Future<IbkrPortfolioSnapshot> Function(IbkrAccountConfig)? ibkrLoader,
    Future<IbkrPerformanceSeries> Function(IbkrAccountConfig, String)?
        ibkrPerformanceLoader,
  })  : _ibkrLoader = ibkrLoader,
        _ibkrPerformanceLoader = ibkrPerformanceLoader;

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
  bool _isLoadingPortfolio = false;
  Object? _loadError;
  int? touchedIndex;
  final _filterController = TextEditingController();
  final _allocationScrollController = ScrollController();
  String _filterText = '';
  String _lastAccount = '';
  int _lastIbkrRefreshVersion = -1;
  IbkrAccountConfig _lastIbkrConfig = const IbkrAccountConfig();
  final Map<(String, IbkrAccountConfig), Future<IbkrPortfolioSnapshot>>
      _ibkrSnapshotLoads = {};
  final Map<(String, IbkrAccountConfig), Future<IbkrPerformanceSeries>>
      _ibkrPerformanceLoads = {};
  final Map<bool, Future<void>> _preloadLoads = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _stream = _buildStream(skipInitial: widget.isActive);
  }

  @override
  void didUpdateWidget(covariant PortfolioPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive == widget.isActive) return;

    setState(() => _stream = _buildStream());
    if (widget.isActive) {
      runDetachedTask(_preload(), 'Failed to preload portfolio');
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
    final cacheFresh = accounts.isPortfolioCacheFresh(account);
    final hadAccount = _lastAccount.isNotEmpty;
    final refreshRequested =
        hadAccount && refreshVersion != _lastIbkrRefreshVersion;
    final willLoadPortfolio = widget.isActive &&
        (ibkrConfig.enabled
            ? ibkrConfig.isConfigured &&
                (refreshRequested || cached == null || !cacheFresh)
            : true);

    if (account == _lastAccount &&
        ibkrConfig == _lastIbkrConfig &&
        refreshVersion == _lastIbkrRefreshVersion) {
      return;
    }

    _lastAccount = account;
    _lastIbkrConfig = ibkrConfig;
    _lastIbkrRefreshVersion = refreshVersion;
    setState(() {
      _stream = _buildStream(skipInitial: widget.isActive);
      _positions = cached?.positions ?? [];
      _netLiquidation = cached?.netLiquidation;
      _hasCachedPortfolio = cached != null;
      _isLoadingPortfolio = willLoadPortfolio;
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
    _filterController.dispose();
    _allocationScrollController.dispose();
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
      );
    }
    final loadKey = (accountName, config);
    final snapshot = await _ibkrSnapshotLoads.putIfAbsent(loadKey, () async {
      try {
        return await (widget._ibkrLoader?.call(config) ??
            IbkrApiClient(config).fetchPortfolio());
      } finally {
        _ibkrSnapshotLoads.removeWhere((key, value) => key == loadKey);
      }
    });
    cacheIbkrAccountExchangeRate(snapshot);
    return _LoadedPortfolio(
      positions: await computeIbkrPositions(snapshot.positions, trades),
      netLiquidation: snapshot.netLiquidation,
      netLiquidationUsd: snapshot.netLiquidationUsd?.value,
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
    final existing = _preloadLoads[forceRefresh];
    if (existing != null) return existing;

    late final Future<void> future;
    future = _performPreload(forceRefresh: forceRefresh).whenComplete(() {
      _preloadLoads.removeWhere(
        (key, value) => key == forceRefresh && identical(value, future),
      );
    });
    _preloadLoads[forceRefresh] = future;
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
    final willLoadPortfolio = !config.enabled || willFetchIbkr;
    if (_loadError != null && mounted) {
      setState(() => _loadError = null);
    }
    if (willLoadPortfolio &&
        mounted &&
        accounts.activeAccount == accountName &&
        !_isLoadingPortfolio) {
      setState(() => _isLoadingPortfolio = true);
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
      if (mounted && widget.isActive) {
        setState(() => _loadError = error);
      }
      talker.handle(error, stackTrace, 'Failed to preload portfolio positions');
    } finally {
      if (mounted &&
          accounts.activeAccount == accountName &&
          _isLoadingPortfolio) {
        setState(() => _isLoadingPortfolio = false);
      }
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
    clearAllSyncCache();
    await _preload(forceRefresh: true);
    await _syncAllInBackground();
  }

  Future<void> _exportCsv(
    BuildContext context,
    List<Position> positions,
  ) async {
    final accountName = context.read<AccountManager>().activeAccount;
    final buf = StringBuffer();
    buf.writeln(
      'Symbol,Name,Shares,Avg Cost,Current Price,Current Value,Cost Basis,Unrealized P/L,% Change,Last Purchase Date',
    );
    final dateFmt = DateFormat('yyyy-MM-dd');
    for (final position in positions) {
      final cells = [
        position.symbol,
        '"${position.name.replaceAll('"', '""')}"',
        position.netShares.toStringAsFixed(6),
        position.avgCost.toStringAsFixed(4),
        position.currentPrice.toStringAsFixed(4),
        position.currentValue.toStringAsFixed(2),
        position.costBasis.toStringAsFixed(2),
        position.unrealizedPL.toStringAsFixed(2),
        position.change.toStringAsFixed(2),
        dateFmt.format(position.lastBuyDate),
      ];
      buf.writeln(cells.join(','));
    }

    final safeName = accountName.replaceAll(RegExp(r'[^\w\-]'), '_');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/positions_$safeName.csv');
    await file.writeAsString(buf.toString());
    talker.info('Exported portfolio CSV with ${positions.length} positions');
    if (!context.mounted) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: 'Portfolio Positions',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<_LoadedPortfolio>(
          key: ValueKey(_lastAccount),
          stream: _stream,
          builder: (context, snapshot) {
            final body = _buildBody(context, snapshot);
            if (!_isLoadingPortfolio || !_hasCachedPortfolio) return body;
            return Stack(
              fit: StackFit.expand,
              children: [
                body,
                Positioned(
                  top: 16,
                  right: 16,
                  child: Semantics(
                    label: context.l10n.text('Loading portfolio'),
                    child: const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ),
                ),
              ],
            );
          },
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
                    ? 'Couldn’t refresh IBKR. Showing the last loaded portfolio.'
                    : 'Couldn’t refresh market data. Showing the last loaded portfolio.',
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
        Center(
          child: Semantics(
            label: context.l10n.text('Loading portfolio'),
            child: const CircularProgressIndicator(),
          ),
        ),
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
    final totalGain = cashOutSummary?.gainUsd ?? costBasisGain;
    final totalGainPct = cashOutSummary?.gainPct ??
        (totalCost > 0 ? (costBasisGain / totalCost) * 100 : 0.0);

    final sorted = [...positions]..sort(
        (firstPosition, secondPosition) =>
            secondPosition.currentValue.compareTo(firstPosition.currentValue),
      );

    final query = _filterText.toLowerCase();
    final filtered = query.isEmpty
        ? sorted
        : sorted
            .where(
              (position) =>
                  position.symbol.toLowerCase().contains(query) ||
                  position.name.toLowerCase().contains(query),
            )
            .toList();

    final colors = _buildColors(context, sorted.length);
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
        value: sorted[index].currentValue,
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
        totalValue: totalValue,
        netLiquidation: netLiquidation,
        totalGain: totalGain,
        totalGainPct: totalGainPct,
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
                totalValue: totalValue,
                netLiquidation: netLiquidation,
                totalGain: totalGain,
                totalGainPct: totalGainPct,
                onExport: () => _exportCsv(context, positions),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: _FilterRow(
                controller: _filterController,
                filterText: _filterText,
                onChanged: (value) =>
                    setState(() => _filterText = value.trim()),
                onClear: () => setState(() {
                  _filterText = '';
                  _filterController.clear();
                }),
              ),
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
                  MarketDonutChart(
                    slices: slices,
                    selectedIndex: selectedIndex,
                    onSelectionChanged: (index) {
                      if (index == touchedIndex) return;
                      setState(() => touchedIndex = index);
                    },
                    centerSpaceRadius: 55,
                    radius: 75,
                    selectedRadius: 90,
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
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final position = filtered[index];
                final sortedIndex = sorted.indexOf(position);
                final val = position.currentValue;
                final pct = totalValue > 0 ? val / totalValue * 100 : 0.0;
                return _LegendTile(
                  color: colors[sortedIndex >= 0 ? sortedIndex : index],
                  symbol: position.symbol,
                  name: position.name,
                  value: val,
                  allocationPct: pct,
                  changePct: position.change,
                  isHighlighted: sortedIndex == selectedIndex,
                  onTap: () => setState(
                    () => touchedIndex =
                        touchedIndex == sortedIndex ? null : sortedIndex,
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
    required List<Position> sorted,
    required int? selectedIndex,
    required bool compact,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Stack(
      alignment: Alignment.center,
      children: [
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
                      : fmtCurrency(sorted[selectedIndex].currentValue),
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
    required List<Position> sorted,
    required List<Color> colors,
    required List<MarketDonutSlice> slices,
    required int? selectedIndex,
    required double totalValue,
    required IbkrAccountValue? netLiquidation,
    required double totalGain,
    required double totalGainPct,
    required bool hasRefreshWarning,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final settings = context.watch<SettingsState>();
    final accounts = context.watch<AccountManager>();
    final byReturn = [...positions]..sort(
        (firstPosition, secondPosition) =>
            secondPosition.change.compareTo(firstPosition.change),
      );
    final accountValue = netLiquidation == null
        ? fmtCurrency(totalValue)
        : fmtNativeCurrency(netLiquidation.value, netLiquidation.currency);

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.text('Portfolio'),
                      style: theme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      accounts.activeAccount,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: context.l10n.text('Refresh'),
                child: IconButton(
                  onPressed: _isLoadingPortfolio ? null : _updateCandles,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == '__export__') {
                    runDetachedTask(
                      _exportCsv(context, positions),
                      'Failed to export portfolio CSV',
                    );
                  } else if (value.startsWith('cur:')) {
                    runDetachedTask(
                      settings.setDisplayCurrency(value.substring(4)),
                      'Failed to change display currency',
                    );
                  } else if (value.startsWith('acc:')) {
                    runDetachedTask(
                      accounts.switchAccount(value.substring(4)),
                      'Failed to switch account',
                    );
                  }
                },
                itemBuilder: (popupContext) => [
                  ...settings.visibleCurrencies.map(
                    (currencyCode) => CheckedPopupMenuItem(
                      value: 'cur:$currencyCode',
                      checked: currencyCode == settings.displayCurrency,
                      child: Text(currencyCode),
                    ),
                  ),
                  if (accounts.accounts.length > 1) ...[
                    const PopupMenuDivider(),
                    ...accounts.accounts.map(
                      (account) => CheckedPopupMenuItem(
                        value: 'acc:$account',
                        checked: account == accounts.activeAccount,
                        child: Text(account),
                      ),
                    ),
                  ],
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: '__export__',
                    child: Row(
                      children: [
                        const Icon(Icons.download_rounded, size: 20),
                        const SizedBox(width: 8),
                        Text(context.l10n.text('Export CSV')),
                      ],
                    ),
                  ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: colorScheme.outlineVariant),
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
          Row(
            children: [
              _DesktopPortfolioMetric(
                label: context.l10n.text('Account value'),
                value: accountValue,
                icon: Icons.account_balance_wallet_outlined,
              ),
              const SizedBox(width: 12),
              _DesktopPortfolioMetric(
                label: context.l10n.text('Market value'),
                value: fmtCurrency(totalValue),
                detail: context.l10n.text('Open stock positions'),
                icon: Icons.show_chart_rounded,
              ),
              const SizedBox(width: 12),
              _DesktopPortfolioMetric(
                label: context.l10n.text('Unrealized P/L'),
                value: '${totalGain >= 0 ? '+' : ''}${fmtCurrency(totalGain)}',
                detail:
                    '${totalGainPct >= 0 ? '+' : ''}${totalGainPct.toStringAsFixed(2)}%',
                valueColor: totalGain >= 0 ? Colors.green : Colors.redAccent,
                icon: totalGain >= 0
                    ? Icons.trending_up_rounded
                    : Icons.trending_down_rounded,
              ),
              const SizedBox(width: 12),
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
                            context.l10n.text(
                              'How your stock portfolio is distributed',
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 28),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final holdingsList = Scrollbar(
                                  controller: _allocationScrollController,
                                  child: ListView.separated(
                                    controller: _allocationScrollController,
                                    padding: const EdgeInsets.only(right: 12),
                                    itemCount: sorted.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 14),
                                    itemBuilder: (context, index) {
                                      final position = sorted[index];
                                      final allocationPct = totalValue > 0
                                          ? position.currentValue /
                                              totalValue *
                                              100
                                          : 0.0;
                                      return _DesktopAllocationRow(
                                        color: colors[index],
                                        symbol: position.symbol,
                                        name: position.name,
                                        value: position.currentValue,
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
                                final compact = constraints.maxWidth < 600;
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
                                        Expanded(flex: 6, child: holdingsList),
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
                                    Expanded(flex: 6, child: holdingsList),
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
                      padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.text('Return by holding'),
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            context.l10n.text('Since average cost'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Expanded(
                            child: ListView.separated(
                              itemCount: byReturn.length,
                              separatorBuilder: (_, __) => Divider(
                                height: 1,
                                color: colorScheme.outlineVariant.withValues(
                                  alpha: 0.7,
                                ),
                              ),
                              itemBuilder: (context, index) {
                                final position = byReturn[index];
                                return _DesktopReturnRow(position: position);
                              },
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
    );
  }

  List<Color> _buildColors(BuildContext context, int count) {
    final base = Theme.of(context).colorScheme.primary;
    final hsl = HSLColor.fromColor(base);
    return List.generate(count, (index) {
      final hue = (hsl.hue + index * (360 / count)) % 360;
      return HSLColor.fromAHSL(
        1.0,
        hue,
        hsl.saturation.clamp(0.4, 0.8),
        hsl.lightness.clamp(0.35, 0.65),
      ).toColor();
    });
  }
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
    return Material(
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
                          fontFeatures: const [FontFeature.tabularFigures()],
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
    );
  }
}

class _DesktopReturnRow extends StatelessWidget {
  final Position position;

  const _DesktopReturnRow({required this.position});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final positive = position.change >= 0;
    final color = positive ? Colors.green : Colors.redAccent;
    final pnl = position.unrealizedPL;

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
                (pnl >= 0 ? '+' : '') + fmtCurrency(pnl),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: pnl >= 0 ? Colors.green : Colors.redAccent,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                '${positive ? '+' : ''}${position.change.toStringAsFixed(2)}%',
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
  final double totalValue;
  final IbkrAccountValue? netLiquidation;
  final double totalGain;
  final double totalGainPct;
  final VoidCallback onExport;

  const _SummaryCard({
    required this.totalValue,
    required this.netLiquidation,
    required this.totalGain,
    required this.totalGainPct,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    final gainColor = totalGain >= 0 ? Colors.green : Colors.redAccent;
    final settings = context.watch<SettingsState>();
    final accounts = context.watch<AccountManager>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            const Icon(Icons.account_balance, size: 32),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  netLiquidation == null
                      ? fmtCurrency(totalValue)
                      : fmtNativeCurrency(
                          netLiquidation!.value,
                          netLiquidation!.currency,
                        ),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(
                  '${totalGain >= 0 ? '+' : ''}${fmtCurrency(totalGain)}'
                  '  (${totalGainPct.toStringAsFixed(2)}%)',
                  style: TextStyle(color: gainColor, fontSize: 13),
                ),
              ],
            ),
            const Spacer(),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == '__export__') {
                  onExport();
                } else if (value.startsWith('cur:')) {
                  runDetachedTask(
                    settings.setDisplayCurrency(value.substring(4)),
                    'Failed to change display currency',
                  );
                } else if (value.startsWith('acc:')) {
                  runDetachedTask(
                    accounts.switchAccount(value.substring(4)),
                    'Failed to switch account',
                  );
                }
              },
              itemBuilder: (ctx) => [
                ...settings.visibleCurrencies.map(
                  (currencyCode) => CheckedPopupMenuItem(
                    value: 'cur:$currencyCode',
                    checked: currencyCode == settings.displayCurrency,
                    child: Text(currencyCode),
                  ),
                ),
                if (accounts.accounts.length > 1) ...[
                  const PopupMenuDivider(),
                  ...accounts.accounts.map(
                    (accountName) => CheckedPopupMenuItem(
                      value: 'acc:$accountName',
                      checked: accountName == accounts.activeAccount,
                      child: Text(accountName),
                    ),
                  ),
                ],
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: '__export__',
                  child: Row(
                    children: [
                      const Icon(Icons.download, size: 20),
                      const SizedBox(width: 8),
                      Text(context.l10n.text('Export CSV')),
                    ],
                  ),
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

class _FilterRow extends StatelessWidget {
  final TextEditingController controller;
  final String filterText;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _FilterRow({
    required this.controller,
    required this.filterText,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: context.l10n.text('Filter holdings...'),
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              suffixIcon: filterText.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: onClear,
                    )
                  : null,
            ),
          ),
        ),
      ],
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
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0),
      onTap: onTap,
      selected: isHighlighted,
      leading: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      title: Text(symbol),
      subtitle: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            fmtCurrency(value),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          Text(
            '${allocationPct.toStringAsFixed(1)}%  '
            '${changePct >= 0 ? '+' : ''}${changePct.toStringAsFixed(2)}%',
            style: TextStyle(
              fontSize: 13,
              color: changePct >= 0 ? Colors.green : Colors.redAccent,
            ),
          ),
        ],
      ),
    );
  }
}
