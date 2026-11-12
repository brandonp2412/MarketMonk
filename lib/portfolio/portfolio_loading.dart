part of '../portfolio_page.dart';

extension _PortfolioLoading on PortfolioPageState {
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
        cashBalance: cached?.cashBalance,
        cashUsd: cached?.cashUsd,
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
        (!refreshIfStale || cacheFresh || !config.isConfigured) &&
        cached.cashChecked;
    if (shouldUseCache) {
      return _LoadedPortfolio(
        positions: cached.positions,
        netLiquidation: cached.netLiquidation,
        netLiquidationUsd: cached.netLiquidationUsd,
        cashBalance: cached.cashBalance,
        cashUsd: cached.cashUsd,
        asOfDate: cached.asOfDate,
      );
    }

    if (!config.isConfigured) {
      if (cached != null) {
        return _LoadedPortfolio(
          positions: cached.positions,
          netLiquidation: cached.netLiquidation,
          netLiquidationUsd: cached.netLiquidationUsd,
          cashBalance: cached.cashBalance,
          cashUsd: cached.cashUsd,
        );
      }
      throw StateError('IBKR portfolio source is not fully configured');
    }

    if (!widget.isActive) {
      return _LoadedPortfolio(
        positions: cached?.positions ?? _positions,
        netLiquidation: cached?.netLiquidation ?? _netLiquidation,
        netLiquidationUsd: cached?.netLiquidationUsd,
        cashBalance: cached?.cashBalance,
        cashUsd: cached?.cashUsd,
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
    final cash = resolveIbkrCash(snapshot);
    return _LoadedPortfolio(
      positions: await computeIbkrPositions(snapshot.positions, trades),
      netLiquidation: snapshot.netLiquidation,
      netLiquidationUsd: snapshot.netLiquidationUsd?.value,
      cashBalance: cash?.reported,
      cashUsd: cash?.usd,
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
    _performanceLoadingAccounts.add(accountName);
    if (mounted && accounts.activeAccount == accountName) _updateState(() {});
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
    } finally {
      _performanceLoadingAccounts.remove(accountName);
      if (mounted && accounts.activeAccount == accountName) _updateState(() {});
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
        (forceRefresh ||
            cachedBefore == null ||
            !cacheWasFresh ||
            !cachedBefore.cashChecked);
    if (_loadError != null && mounted) {
      _updateState(() => _loadError = null);
    }
    final performanceMissing =
        accounts.ibkrPerformanceCacheFor(accountName, '1Y') == null;
    if (performanceMissing) {
      runDetachedTask(
        _loadIbkrCashOutPerformance(
          accountName,
          config,
          forceRefresh: forceRefresh,
        ),
        'Failed to fetch missing IBKR performance history',
      );
    }
    try {
      final trades = await profileDataRepository.readTradesForAccount(
        accountName,
      );
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
          cashBalance: loaded.cashBalance,
          cashUsd: loaded.cashUsd,
          asOfDate: loaded.asOfDate,
        );
      }
      if (!mounted ||
          !widget.isActive ||
          accounts.activeAccount != accountName) {
        return;
      }
      _updateState(() {
        _positions = loaded.positions;
        _netLiquidation = loaded.netLiquidation;
        _hasCachedPortfolio = true;
        _loadError = null;
      });
      if (!performanceMissing) {
        runDetachedTask(
          _loadIbkrCashOutPerformance(
            accountName,
            config,
            forceRefresh: forceRefresh,
          ),
          'Failed to refresh IBKR performance history',
        );
      }
    } catch (error, stackTrace) {
      if (mounted && widget.isActive && accounts.activeAccount == accountName) {
        _updateState(() => _loadError = error);
      }
      talker.handle(error, stackTrace, 'Failed to preload portfolio positions');
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
    Stream<List<Trade>> trades = profileDataRepository.watchTradesForAccount(
      accountName,
    );
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
    _forceHistoryRefresh = true;
    _historyAccount = null;
    clearAllSyncCache();
    await _preload(forceRefresh: true);
    if (!mounted || !widget.isActive) return;
    final accounts = context.read<AccountManager>();
    await _ensureReturnHistory(
      _returnHistoryKey(accounts, _positions),
      _positions,
    );
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
}
