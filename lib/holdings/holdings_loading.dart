part of '../holdings_page.dart';

extension _HoldingsLoading on HoldingsPageState {
  /// Pre-loads data immediately via get() so the UI has something to show
  /// before the watch() stream emits its first value.
  Future<List<Trade>> _loadTradesForHoldings({
    bool forceRefresh = false,
  }) async {
    final accounts = context.read<AccountManager>();
    final accountName = accounts.activeAccount;
    final config = accounts.ibkrConfigFor(accountName);
    if (!config.enabled) {
      return profileDataRepository.readTradesForAccount(accountName);
    }

    if (!config.isConfigured) {
      _ibkrTradeHistoryAvailable = false;
      _ibkrTrades = [];
      _ibkrTradesAccount = accountName;
      return const [];
    }

    if (!forceRefresh && _ibkrTradesAccount == accountName) {
      _ibkrTrades = await enrichHistoricalTradeRates(_ibkrTrades);
      return _ibkrTrades;
    }

    final existingLoad = _ibkrTradesLoad;
    if (!forceRefresh &&
        existingLoad != null &&
        _ibkrTradesLoadingAccount == accountName) {
      return existingLoad;
    }
    if (!widget.isActive) return _ibkrTrades;

    final load = () async {
      try {
        final tradeHistory =
            await (widget._ibkrTradeHistoryLoader?.call(config) ??
                IbkrApiClient(config).fetchTradeHistory());
        final trades = await enrichHistoricalTradeRates(
          tradesFromIbkr(tradeHistory.trades),
        );
        if (mounted &&
            accounts.activeAccount == accountName &&
            accounts.ibkrConfigFor(accountName) == config) {
          if (tradeHistory.available) {
            _ibkrTrades = trades;
            try {
              await accounts.cacheIbkrTradeHistory(accountName, tradeHistory);
            } catch (error, stackTrace) {
              talker.handle(error, stackTrace, 'Failed to cache IBKR trades');
            }
          }
          _ibkrTradesAccount = tradeHistory.available ? accountName : null;
          _ibkrTradeHistoryAvailable = tradeHistory.available;
        }
        return tradeHistory.available ? trades : _ibkrTrades;
      } catch (error, stackTrace) {
        if (mounted &&
            accounts.activeAccount == accountName &&
            accounts.ibkrConfigFor(accountName) == config) {
          _ibkrTradesAccount = null;
          _ibkrTradeHistoryAvailable = false;
        }
        talker.handle(
          error,
          stackTrace,
          'IBKR transaction history unavailable',
        );
        return _ibkrTrades;
      }
    }();
    _ibkrTradesLoad = load;
    _ibkrTradesLoadingAccount = accountName;
    try {
      return await load;
    } finally {
      if (identical(_ibkrTradesLoad, load)) {
        _ibkrTradesLoad = null;
        _ibkrTradesLoadingAccount = null;
      }
    }
  }

  Future<void> _preload({
    bool refreshPortfolio = false,
    bool refreshTrades = false,
  }) {
    final accountName = context.read<AccountManager>().activeAccount;
    final key = (accountName, refreshPortfolio, refreshTrades);
    final existing = _preloadLoads[key];
    if (existing != null) return existing;

    late final Future<void> future;
    future = _performPreload(
      refreshPortfolio: refreshPortfolio,
      refreshTrades: refreshTrades,
    ).whenComplete(() {
      _preloadLoads.removeWhere(
        (entryKey, value) => entryKey == key && identical(value, future),
      );
    });
    _preloadLoads[key] = future;
    return future;
  }

  Future<void> _performPreload({
    bool refreshPortfolio = false,
    bool refreshTrades = false,
  }) async {
    if (!mounted || !widget.isActive) return;
    final accounts = context.read<AccountManager>();
    final accountName = accounts.activeAccount;
    try {
      final cachedBefore = accounts.portfolioCacheFor(accountName);
      if (cachedBefore != null && accounts.ibkrConfigFor(accountName).enabled) {
        _updateState(() {
          _summaries = _summariesFromPositions(
            _ibkrTrades,
            cachedBefore.positions,
          );
          _ibkrPreloadCompleted = true;
        });
      }
      final trades = await _loadTradesForHoldings(forceRefresh: refreshTrades);
      if (!mounted ||
          !widget.isActive ||
          accounts.activeAccount != accountName) {
        return;
      }
      final cached = accounts.portfolioCacheFor(accountName);
      final cacheFresh = accounts.isPortfolioCacheFresh(accountName);
      final config = accounts.ibkrConfigFor(accountName);
      final shouldUseCache = HoldingsPageState.shouldUsePortfolioCache(
        hasCache: cached != null,
        refreshPortfolio: refreshPortfolio,
        ibkrEnabled: config.enabled,
        ibkrConfigured: config.isConfigured,
        cacheFresh: cacheFresh,
      );
      if (shouldUseCache) {
        final result = _summariesFromPositions(trades, cached!.positions);
        if (mounted) {
          _updateState(() {
            _summaries = result;
            _ibkrPreloadCompleted = true;
            _preloadError = null;
          });
        }
        return;
      }
      final result = await _computeSummaries(trades, accountName: accountName);
      if (mounted && widget.isActive && accounts.activeAccount == accountName) {
        _updateState(() {
          _summaries = result;
          _ibkrPreloadCompleted = true;
          _preloadError = null;
        });
      }
    } catch (error, stackTrace) {
      if (mounted && widget.isActive && accounts.activeAccount == accountName) {
        _updateState(() {
          _ibkrPreloadCompleted = true;
          _preloadError = error;
        });
      }
      _reportError(error, stackTrace, 'preloading holdings');
    }
  }

  Future<List<Position>> _loadPositions(
    List<Trade> trades, {
    String? forAccount,
  }) async {
    final accounts = context.read<AccountManager>();
    final accountName = forAccount ?? accounts.activeAccount;
    if (!widget.isActive) {
      return accounts.portfolioCacheFor(accountName)?.positions ??
          const <Position>[];
    }
    if (widget._positionsLoader != null) {
      return widget._positionsLoader!(trades);
    }

    final config = accounts.ibkrConfigFor(accountName);
    final cached = accounts.portfolioCacheFor(accountName);
    if (!config.enabled) {
      final symbols = trades.map((trade) => trade.symbol).toSet().toList();
      if (!widget.isActive) {
        return accounts.portfolioCacheFor(accountName)?.positions ??
            const <Position>[];
      }
      final prices = await fetchLatestPrices(symbols);
      final positions = computePositions(trades, prices);
      await _cachePortfolio(accounts, accountName, positions, null);
      return positions;
    }
    if (!config.isConfigured) {
      if (cached != null) return cached.positions;
      throw StateError('IBKR portfolio source is not fully configured');
    }
    if (!widget.isActive) {
      return accounts.portfolioCacheFor(accountName)?.positions ??
          const <Position>[];
    }
    try {
      final snapshot = await (widget._ibkrLoader?.call(config) ??
          IbkrApiClient(config).fetchPortfolio());
      cacheIbkrAccountExchangeRate(snapshot);
      final positions = await computeIbkrPositions(snapshot.positions, trades);
      final cash = resolveIbkrCash(snapshot);
      await _cachePortfolio(
        accounts,
        accountName,
        positions,
        snapshot.netLiquidation,
        netLiquidationUsd: snapshot.netLiquidationUsd?.value,
        cashBalance: cash?.reported,
        cashUsd: cash?.usd,
        asOfDate: snapshot.asOfDate,
      );
      return positions;
    } catch (error) {
      if (cached != null) {
        talker.warning('IBKR portfolio unavailable; using cached holdings');
        return cached.positions;
      }
      rethrow;
    }
  }

  Future<void> _cachePortfolio(
    AccountManager accounts,
    String accountName,
    List<Position> positions,
    IbkrAccountValue? netLiquidation, {
    double? netLiquidationUsd,
    IbkrAccountValue? cashBalance,
    double? cashUsd,
    DateTime? asOfDate,
  }) async {
    try {
      await accounts.cachePortfolio(
        accountName,
        positions,
        netLiquidation,
        netLiquidationUsd: netLiquidationUsd,
        cashBalance: cashBalance,
        cashUsd: cashUsd,
        asOfDate: asOfDate,
      );
    } catch (error, stack) {
      _reportError(error, stack, 'saving the holdings cache');
    }
  }

  void _reportError(Object error, StackTrace stack, String operation) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'Market Monk holdings',
        context: ErrorDescription('while $operation'),
      ),
    );
  }

  /// Fires candle syncs for all held symbols in the background without
  /// blocking the UI.
  Future<List<SymbolSummary>> _computeSummaries(
    List<Trade> trades, {
    String? accountName,
  }) async =>
      _summariesFromPositions(
        trades,
        await _loadPositions(trades, forAccount: accountName),
      );

  List<SymbolSummary> _summariesFromPositions(
    List<Trade> trades,
    List<Position> positions,
  ) {
    final positionMap = {
      for (final position in positions) position.symbol: position,
    };
    final query = _search.text.toLowerCase();
    final Map<String, List<Trade>> bySymbol = {};
    for (final trade in trades) {
      if (query.isNotEmpty &&
          !trade.symbol.toLowerCase().contains(query) &&
          !trade.name.toLowerCase().contains(query)) {
        continue;
      }
      bySymbol.putIfAbsent(trade.symbol, () => []).add(trade);
    }

    for (final position in positions) {
      if (query.isNotEmpty &&
          !position.symbol.toLowerCase().contains(query) &&
          !position.name.toLowerCase().contains(query)) {
        continue;
      }
      bySymbol.putIfAbsent(position.symbol, () => []);
    }

    final summaries = <SymbolSummary>[];
    for (final entry in bySymbol.entries) {
      final symbol = entry.key;
      final symbolTrades = entry.value;
      final position = positionMap[symbol];
      final name = position?.name ?? symbolTrades.first.name;
      summaries.add(
        SymbolSummary(
          symbol: symbol,
          name: name,
          position: position,
          trades: symbolTrades,
          brokerTradeHistoryAvailable: _ibkrTradeHistoryAvailable,
        ),
      );
    }

    summaries.sort((firstSummary, secondSummary) {
      if (firstSummary.position != null && secondSummary.position == null) {
        return -1;
      }
      if (firstSummary.position == null && secondSummary.position != null) {
        return 1;
      }
      return firstSummary.symbol.compareTo(secondSummary.symbol);
    });

    return summaries;
  }

  Stream<List<SymbolSummary>> _buildStream({bool skipInitial = false}) {
    if (!widget.isActive) return Stream.value(_summaries);

    final accounts = context.read<AccountManager>();
    if (accounts.ibkrConfigFor().enabled) {
      return const Stream<List<SymbolSummary>>.empty();
    }
    final accountName = accounts.activeAccount;
    Stream<List<Trade>> trades = profileDataRepository.watchTradesForAccount(
      accountName,
    );
    if (skipInitial) trades = trades.skip(1);
    return trades
        .asyncMap((rows) => _summariesForStream(accountName, rows))
        .transform(
      StreamTransformer<List<SymbolSummary>, List<SymbolSummary>>.fromHandlers(
        handleError: (error, stack, sink) {
          _reportError(error, stack, 'loading holdings');
          sink.addError(error, stack);
        },
      ),
    );
  }

  Future<List<SymbolSummary>> _summariesForStream(
    String accountName,
    List<Trade> localTrades,
  ) async {
    final accounts = context.read<AccountManager>();
    if (accounts.activeAccount != accountName) return const [];
    final config = accounts.ibkrConfigFor(accountName);
    final trades = config.enabled ? _ibkrTrades : localTrades;
    if (widget.isActive) {
      return _computeSummaries(trades, accountName: accountName);
    }

    final cachedPositions =
        accounts.portfolioCacheFor(accountName)?.positions ??
            const <Position>[];
    return _summariesFromPositions(trades, cachedPositions);
  }
}
