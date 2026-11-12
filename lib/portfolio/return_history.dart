part of '../portfolio_page.dart';

extension _PortfolioReturnHistory on PortfolioPageState {
  DateTime? _cutoff(int period, DateTime now) =>
      period == -1 ? _inceptionDate : portfolioReturnCutoff(period, now);

  DateTime? get _returnCutoff => _cutoff(_period, DateTime.now());

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
        _updateState(() {
          _returnHistory = cachedHistory;
          _returnTrades = cachedHistory.trades;
          _returnCandles = cachedHistory.candles;
          _loadedTradeCache = accounts.ibkrTradeHistoryCacheFor(accountName);
          _historyLoading = false;
        });
      }
      final intradayCacheFresh =
          await _restoreCachedReturnIntraday(account, accountName, positions);
      if (!mounted || _historyAccount != account) return;
      final history = await loadPortfolioHistory(
        accounts: accounts,
        accountName: accountName,
        positions: positions,
        database: marketDataDatabase,
        forceRefresh: forceRefresh,
        tradeLoader: widget._historyTradeLoader,
        candleSync: widget._historyCandleSync,
        rateLoader: widget._historyRateLoader,
      ).timeout(const Duration(seconds: 90));
      if (!mounted || _historyAccount != account) return;
      _updateState(() {
        _returnHistory = history;
        _loadedTradeCache = accounts.ibkrTradeHistoryCacheFor(accountName);
        _returnTrades = history.trades;
        _returnCandles = history.candles;
        _historyLoading = false;
        _historyRefreshing = false;
      });
      final config = accounts.ibkrConfigFor(accountName);
      if (config.enabled &&
          !intradayCacheFresh &&
          positions.any((position) => position.netShares != 0)) {
        await _loadReturnIntraday(
          account,
          accountName,
          positions,
          history.trades,
          config,
        );
      }
    } catch (error, stack) {
      talker.handle(error, stack, 'Failed to load portfolio return history');
      if (!mounted || _historyAccount != account) return;
      _updateState(() {
        _historyLoading = false;
        _historyRefreshing = false;
        _historyFailed = _returnHistory == null;
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
      final holdings = <IntradayPortfolioHolding>[];
      for (final position in priced) {
        final series = await _returnIntraday.fetch(
          position.symbol,
          days: 1,
          config: config,
        );
        await fetchSymbolCurrencyAndRate(
          position.symbol,
          rawCurrency: series.currency,
        );
        holdings.add(
          IntradayPortfolioHolding.fromSeries(
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
          ),
        );
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
