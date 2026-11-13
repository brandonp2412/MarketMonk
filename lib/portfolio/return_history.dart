part of '../portfolio_page.dart';

extension _PortfolioReturnHistory on PortfolioPageState {
  DateTime? _cutoff(int period, DateTime now) =>
      period == -1 ? _inceptionDate : portfolioReturnCutoff(period, now);

  DateTime? get _returnCutoff => _cutoff(_period, DateTime.now());

  List<int> _coveredPeriods(
    List<Position> positions,
    IbkrPerformanceSeries? performance,
    IbkrAccountValue? netLiquidation, {
    bool ignoreLoading = false,
  }) {
    if (!ignoreLoading && (_periodHistoryIncomplete || _historyFailed)) {
      return const [0];
    }
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
      _inceptionDate = portfolioInception(performance);
      final covered = <int>[
        0,
        if (_allocationAt(positions, -1) != null) -1,
      ];
      for (var period = 1;
          period < PortfolioPageState._periods.length;
          period++) {
        final cutoff = _cutoff(period, DateTime.now())!;
        if (cutoff.isBefore(firstKnownDate)) continue;
        if (period >= firstIntradayPeriod) {
          if (intradayAccountValueAt(_intradayValues, cutoff) != null &&
              _intradayAllocationAt(positions, cutoff) != null) {
            covered.add(period);
          }
          continue;
        }
        if (accountNetAssetValueAt(performance, cutoff) != null &&
            _allocationAt(positions, period) != null) {
          covered.add(period);
        }
      }
      return covered;
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
      for (var period = 1; period < firstIntradayPeriod; period++)
        if (!_cutoff(
              period,
              DateTime.now(),
            )!
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
    int period, {
    double? cashValueUsd,
  }) {
    final accounts = context.read<AccountManager>();
    final history = _returnHistory;
    if (period != 0 && history == null) return null;
    final ibkrEnabled = accounts.ibkrConfigFor().enabled;
    final performance = ibkrEnabled
        ? accounts.ibkrPerformanceCacheFor(accounts.activeAccount, '1Y')
        : null;
    if (period == 0) {
      return portfolioAllocationAt(
        positions: positions,
        trades: const [],
        candles: const {},
        date: null,
        cashValueUsd: cashValueUsd,
      );
    }
    final source = (positions, history, performance, ibkrEnabled);
    if (_allocationCacheSource != source) {
      _allocationCacheSource = source;
      _allocationCache.clear();
    }
    final cutoff = _cutoff(period, DateTime.now());
    final key = (cutoff, cashValueUsd);
    if (_allocationCache.containsKey(key)) return _allocationCache[key];
    if (_allocationCache.length >= 32) _allocationCache.clear();
    final allocation =
        (history ?? const PortfolioHistory(trades: [], candles: {}, rates: {}))
            .allocationAt(
      positions: positions,
      date: cutoff,
      performance: performance,
      currentCashUsd: cashValueUsd,
    );
    _allocationCache[key] = allocation;
    return allocation;
  }

  String _returnHistoryKey(AccountManager accounts, List<Position> positions) =>
      '${accounts.activeAccount}:${accounts.ibkrConfigFor().hashCode}:${accounts.ibkrRefreshVersion}:${identityHashCode(accounts.ibkrPerformanceCacheFor(accounts.activeAccount, '1Y'))}:${positions.map((p) => '${p.symbol}:${p.netShares}:${p.costBasis}').join(',')}';

  Future<void> _ensureReturnHistory(String key, List<Position> positions) {
    if (_historyAccount == key && _historyFuture != null)
      return _historyFuture!;
    return _historyFuture = _loadReturnHistory(key, positions);
  }

  Future<bool> _restoreCompletedPeriodCheckpoint(
    String accountName,
    List<Position> positions,
  ) async {
    try {
      final accounts = context.read<AccountManager>();
      final entry = await marketDataDatabase.readIbkrCache(
        accounts.activeProfileId,
        'portfolioPeriods',
        'complete',
      );
      if (entry == null) return false;
      final data = jsonDecode(entry.payloadJson) as Map<String, dynamic>;
      if (data['version'] != 1) return false;
      final signature = portfolioHistoryCacheSignature(
        positions: positions,
        trades: accounts.ibkrTradeHistoryCacheFor(accountName),
        performance: accounts.ibkrPerformanceCacheFor(accountName, '1Y'),
      );
      if (data['signature'] != signature) return false;
      final cached = _returnHistory;
      if (cached == null ||
          !cachedPortfolioDailyPeriodsComplete(
            history: cached,
            positions: positions,
            performance: accounts.ibkrPerformanceCacheFor(accountName, '1Y'),
          )) {
        return false;
      }
      final verified = (data['periods'] as List<dynamic>)
          .whereType<num>()
          .map((period) => period.toInt())
          .where((period) => period != 0)
          .toSet();
      if (verified.isEmpty) return false;
      final available = _coveredPeriods(
        positions,
        accounts.ibkrPerformanceCacheFor(accountName, '1Y'),
        accounts.portfolioCacheFor(accountName)?.netLiquidation,
        ignoreLoading: true,
      ).toSet();
      // A checkpoint never authorizes displaying an incomplete period ruler.
      // If any previously verified period is now unavailable, repair it first.
      return verified.every(available.contains);
    } catch (error, stackTrace) {
      talker.handle(
        error,
        stackTrace,
        'Skipped invalid portfolio period cache',
      );
      return false;
    }
  }

  Future<void> _saveCompletedPeriodCheckpoint(
    String key,
    String accountName,
    List<Position> positions,
  ) async {
    if (!mounted || _historyAccount != key || _historyRefreshing) return;
    final accounts = context.read<AccountManager>();
    final history = _returnHistory;
    if (history == null ||
        !cachedPortfolioDailyPeriodsComplete(
          history: history,
          positions: positions,
          performance: accounts.ibkrPerformanceCacheFor(accountName, '1Y'),
        )) {
      return;
    }
    final periods = _coveredPeriods(
      positions,
      accounts.ibkrPerformanceCacheFor(accountName, '1Y'),
      accounts.portfolioCacheFor(accountName)?.netLiquidation,
      ignoreLoading: true,
    );
    if (periods.where((period) => period != 0).isEmpty) return;
    try {
      await marketDataDatabase.writeIbkrCache(
        profileId: accounts.activeProfileId,
        kind: 'portfolioPeriods',
        cacheKey: 'complete',
        payloadJson: jsonEncode({
          'version': 1,
          'signature': portfolioHistoryCacheSignature(
            positions: positions,
            trades: accounts.ibkrTradeHistoryCacheFor(accountName),
            performance: accounts.ibkrPerformanceCacheFor(accountName, '1Y'),
          ),
          'periods': periods,
        }),
        cachedAt: DateTime.now(),
      );
    } catch (error, stackTrace) {
      talker.handle(error, stackTrace, 'Failed to save completed period cache');
    }
  }

  /// A stale trade cache is sufficient for reconstructing the already saved
  /// periods. Refresh trades independently rather than making candle backfill
  /// wait on the slow /v1/trades endpoint.
  Future<void> _refreshCachedBrokerTrades(
    String accountName,
    IbkrAccountConfig config,
  ) async {
    if (!_refreshingHistoryTrades.add(accountName)) return;
    final accounts = context.read<AccountManager>();
    try {
      final previous = accounts.ibkrTradeHistoryCacheFor(accountName);
      final updated = await (widget._historyTradeLoader?.call(config) ??
          IbkrApiClient(config).fetchTradeHistory());
      if (!updated.available) {
        throw StateError('IBKR trade history is unavailable');
      }
      final changed =
          jsonEncode(previous?.toJson()) != jsonEncode(updated.toJson());
      await accounts.cacheIbkrTradeHistory(accountName, updated);
      if (!mounted || accounts.activeAccount != accountName) return;
      _updateState(() {
        if (changed || _historyRefreshing) {
          // Build from the new broker history only when it changed or an
          // earlier attempt was waiting for the refresh to finish.
          _historyAccount = null;
        } else {
          _loadedTradeCache = updated;
        }
      });
    } catch (error, stackTrace) {
      talker.handle(error, stackTrace, 'Failed to refresh cached IBKR trades');
      if (mounted && accounts.activeAccount == accountName) {
        _updateState(() {
          if (_returnHistory != null) {
            _historyRefreshing = false;
            _completedHistoryAccount = _historyAccount;
          }
        });
      }
    } finally {
      _refreshingHistoryTrades.remove(accountName);
    }
  }

  Future<void> _loadReturnHistory(
    String account,
    List<Position> positions,
  ) async {
    _historyAccount = account;
    _historyLoading = _returnHistory == null;
    _historyRefreshing = true;
    _historyFailed = false;
    final accounts = context.read<AccountManager>();
    final accountName = accounts.activeAccount;
    final cacheStopwatch = Stopwatch()..start();
    try {
      final forceRefresh = _forceHistoryRefresh;
      _forceHistoryRefresh = false;
      final cachedHistory = await loadPortfolioHistory(
        accounts: accounts,
        accountName: accountName,
        positions: positions,
        database: marketDataDatabase,
        cacheOnly: true,
      );
      if (!mounted || _historyAccount != account) return;
      final hasBrokerTrades = !accounts.ibkrConfigFor(accountName).enabled ||
          accounts.ibkrTradeHistoryCacheFor(accountName)?.available == true;
      if (hasBrokerTrades) {
        final completeDailyCache = cachedPortfolioDailyPeriodsComplete(
          history: cachedHistory,
          positions: positions,
          performance: accounts.ibkrPerformanceCacheFor(accountName, '1Y'),
        );
        _updateState(() {
          _returnHistory = cachedHistory;
          _returnTrades = cachedHistory.trades;
          _returnCandles = cachedHistory.candles;
          _loadedTradeCache = accounts.ibkrTradeHistoryCacheFor(accountName);
          _historyLoading = false;
          // This check uses local data only. Never wait for the broker when
          // the cached daily ruler can already be reconstructed in full.
          _completedHistoryAccount = completeDailyCache ? account : null;
          _verifiedCachedHistoryKey = completeDailyCache ? account : null;
        });
        talker.info(
          'Portfolio SQLite history ready for $accountName: '
          'complete=$completeDailyCache, '
          'elapsed=${cacheStopwatch.elapsedMilliseconds}ms',
        );
      }
      final intradayCacheFresh =
          await _restoreCachedReturnIntraday(account, accountName, positions);
      if (!mounted || _historyAccount != account) return;
      if (hasBrokerTrades && _verifiedCachedHistoryKey != account) {
        final verified = await _restoreCompletedPeriodCheckpoint(
          accountName,
          positions,
        );
        if (!mounted || _historyAccount != account) return;
        if (verified) {
          _updateState(() {
            _verifiedCachedHistoryKey = account;
            _completedHistoryAccount = account;
          });
          talker.info(
            'Portfolio saved period coverage restored for $accountName',
          );
        }
      }
      final config = accounts.ibkrConfigFor(accountName);
      final useCachedTrades = !forceRefresh &&
          config.isConfigured &&
          accounts.ibkrTradeHistoryCacheFor(accountName)?.available == true &&
          !accounts.isIbkrTradeHistoryCacheFresh(accountName);
      if (useCachedTrades) {
        runDetachedTask(
          _refreshCachedBrokerTrades(accountName, config),
          'Failed to refresh historical broker trades',
        );
      }
      final history = await loadPortfolioHistory(
        accounts: accounts,
        accountName: accountName,
        positions: positions,
        database: marketDataDatabase,
        forceRefresh: forceRefresh,
        preferCachedBrokerTrades: useCachedTrades,
        tradeLoader: widget._historyTradeLoader,
        candleSync: widget._historyCandleSync,
        rateLoader: widget._historyRateLoader,
      ).timeout(const Duration(seconds: 90));
      if (!mounted || _historyAccount != account) return;
      final needsIntraday = config.enabled &&
          !intradayCacheFresh &&
          positions.any((position) => position.netShares != 0);
      // A usable older intraday cache already supplies complete period stops.
      // Otherwise, keep the ruler in its loading state until the daily and
      // intraday sources have both finished.
      final waitingForIntraday = needsIntraday && _intradayValues.isEmpty;
      _updateState(() {
        _returnHistory = history;
        _loadedTradeCache = accounts.ibkrTradeHistoryCacheFor(accountName);
        _returnTrades = history.trades;
        _returnCandles = history.candles;
        final completeDailyHistory = cachedPortfolioDailyPeriodsComplete(
          history: history,
          positions: positions,
          performance: accounts.ibkrPerformanceCacheFor(accountName, '1Y'),
        );
        final pendingTrades = useCachedTrades &&
            _refreshingHistoryTrades.contains(accountName) &&
            !completeDailyHistory;
        _completedHistoryAccount = pendingTrades ? null : account;
        _historyLoading = false;
        _historyRefreshing = pendingTrades;
        _intradayHistoryPending = waitingForIntraday;
      });
      // Commit verified daily periods before potentially slow intraday calls.
      // A process kill must not discard a completed daily-history warmup.
      await _saveCompletedPeriodCheckpoint(account, accountName, positions);
      if (needsIntraday) {
        try {
          await _loadReturnIntraday(
            account,
            accountName,
            positions,
            history.trades,
            config,
          );
        } finally {
          if (mounted && _historyAccount == account && waitingForIntraday) {
            _updateState(() => _intradayHistoryPending = false);
          }
        }
      }
      await _saveCompletedPeriodCheckpoint(account, accountName, positions);
    } catch (error, stack) {
      talker.handle(error, stack, 'Failed to load portfolio return history');
      if (!mounted || _historyAccount != account) return;
      _updateState(() {
        _historyLoading = false;
        _historyRefreshing = false;
        _intradayHistoryPending = false;
        _historyFailed = _completedHistoryAccount != account;
      });
    }
  }

  PortfolioReturn? _holdingReturn(Position position, {int? period}) {
    final cutoff = _cutoff(period ?? _period, DateTime.now());
    if (cutoff == null) {
      return PortfolioReturn(position.unrealizedPL, position.costBasis);
    }
    if (_historyLoading || _historyFailed) return null;
    if (period != null && period >= firstIntradayPeriod) {
      final holding = _intradayHoldings[position.symbol];
      if (holding == null) return null;
      double? baselineUsd;
      for (final entry in holding.pricesUsd.entries) {
        if (entry.key.isAfter(cutoff)) break;
        baselineUsd = entry.value;
      }
      if (baselineUsd == null || baselineUsd <= 0) return null;
      final basis = position.netShares * baselineUsd;
      if (basis <= 0) return null;
      return PortfolioReturn(position.currentValue - basis, basis);
    }
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
    if (trades.any(
      (trade) => verifiedTradeAmountUsd(trade, trade.price) == null,
    )) return null;
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
            price: tradeAmountUsd(trade, trade.price),
          ),
      ],
    );
  }

  Future<bool> _restoreCachedReturnIntraday(
    String historyKey,
    String accountName,
    List<Position> positions,
  ) async {
    try {
      final accounts = context.read<AccountManager>();
      final entry = await marketDataDatabase.readIbkrCache(
        accounts.activeProfileId,
        'portfolioIntraday',
        '1D',
      );
      if (entry == null) return false;
      final cache = CachedPortfolioIntraday.fromJson(
        jsonDecode(entry.payloadJson) as Map<String, dynamic>,
      );
      final now = DateTime.now();
      if (!cache.isUsableFor(positions, now)) return false;
      final snapshot = accounts.portfolioCacheFor(accountName);
      final nav = snapshot?.netLiquidation;
      final currentValueUsd = snapshot?.netLiquidationUsd ??
          (nav != null && nav.value.isFinite
              ? nav.value / requireUsdRate(nav.currency)
              : null) ??
          positions.fold<double>(
            0,
            (sum, position) => sum + position.currentValue,
          );
      final values = buildIntradayPortfolio(
        holdings: cache.holdings.values.toList(),
        currentValueUsd: currentValueUsd,
      );
      if (values.isEmpty ||
          !mounted ||
          _historyAccount != historyKey ||
          accounts.activeAccount != accountName) {
        return false;
      }
      _updateState(() {
        _intradayValues = values;
        _intradayHoldings
          ..clear()
          ..addAll(cache.holdings);
        _intradayCurrentValueUsd = currentValueUsd;
      });
      return now.difference(cache.cachedAt) < const Duration(minutes: 5);
    } catch (error, stack) {
      talker.handle(
        error,
        stack,
        'Skipped invalid SQLite portfolio intraday cache',
      );
      return false;
    }
  }

  Future<void> _loadReturnIntraday(
    String historyKey,
    String accountName,
    List<Position> positions,
    List<Trade> trades,
    IbkrAccountConfig config,
  ) async {
    final accounts = context.read<AccountManager>();
    final priced =
        positions.where((position) => position.netShares != 0).toList();
    if (priced.isEmpty) return;
    try {
      await _returnIntraday.prefetchPortfolio(config, days: 1);
      Future<IntradayPortfolioHolding> loadHolding(Position position) async {
        final series = await _returnIntraday.fetch(
          position.symbol,
          days: 1,
          config: config,
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
          trades: [
            for (final trade in trades)
              if (trade.symbol == position.symbol)
                IntradayPortfolioTrade(
                  trade.tradeDate.toUtc(),
                  trade.quantity,
                  tradeAmountUsd(trade, trade.price),
                ),
          ],
        );
      }

      // Independent holdings are fetched in bounded parallel batches instead
      // of serially blocking on every IBKR/Yahoo round trip.
      final holdings = <IntradayPortfolioHolding>[];
      const batchSize = 4;
      for (var offset = 0; offset < priced.length; offset += batchSize) {
        if (!mounted || _historyAccount != historyKey) return;
        final batch = await Future.wait(
          priced.skip(offset).take(batchSize).map(loadHolding),
        );
        holdings.addAll(batch);
      }
      final cached = accounts.portfolioCacheFor(accountName);
      final nav = cached?.netLiquidation;
      final currentValueUsd = cached?.netLiquidationUsd ??
          (nav != null && nav.value.isFinite
              ? nav.value / requireUsdRate(nav.currency)
              : null) ??
          positions.fold<double>(
            0,
            (sum, position) => sum + position.currentValue,
          );
      if (!mounted || _historyAccount != historyKey) return;
      _updateState(() {
        _intradayValues = buildIntradayPortfolio(
          holdings: holdings,
          currentValueUsd: currentValueUsd,
        );
        _intradayHoldings
          ..clear()
          ..addAll({
            for (var i = 0; i < holdings.length; i++)
              priced[i].symbol: holdings[i],
          });
        _intradayCurrentValueUsd = currentValueUsd;
      });
      if (_intradayValues.isNotEmpty) {
        try {
          final cache = CachedPortfolioIntraday(
            positionsKey: CachedPortfolioIntraday.keyFor(positions),
            cachedAt: DateTime.now(),
            holdings: {
              for (var i = 0; i < holdings.length; i++)
                priced[i].symbol: holdings[i],
            },
          );
          await marketDataDatabase.writeIbkrCache(
            profileId: accounts.activeProfileId,
            kind: 'portfolioIntraday',
            cacheKey: '1D',
            payloadJson: jsonEncode(cache.toJson()),
            cachedAt: cache.cachedAt,
          );
        } catch (error, stack) {
          talker.handle(
            error,
            stack,
            'Failed to cache intraday portfolio in SQLite',
          );
        }
      }
    } catch (error, stack) {
      talker.handle(error, stack, 'Failed to load intraday portfolio values');
    }
  }

  List<PortfolioAllocation>? _intradayAllocationAt(
    List<Position> positions,
    DateTime cutoff,
  ) {
    final allocations = <PortfolioAllocation>[];
    for (final position in positions) {
      if (position.netShares == 0) continue;
      final holding = _intradayHoldings[position.symbol];
      if (holding == null) return null;
      final priceUsd = holding.priceAt(cutoff);
      if (priceUsd == null || !priceUsd.isFinite) return null;
      final quantity = holding.quantityAt(cutoff);
      if (quantity.abs() <= 1e-6) continue;
      final value = quantity * priceUsd;
      if (value.isFinite) {
        allocations.add(
          PortfolioAllocation(position.symbol, position.name, value),
        );
      }
    }
    final accountValue = intradayAccountValueAt(_intradayValues, cutoff);
    if (accountValue != null) {
      final holdingsValue = allocations.fold<double>(
        0,
        (sum, holding) => sum + holding.value,
      );
      final cash = accountValue - holdingsValue;
      if (cash > 0.01) {
        allocations
            .add(PortfolioAllocation('CASH', 'Cash', cash, isCash: true));
      }
    }
    return allocations;
  }
}
