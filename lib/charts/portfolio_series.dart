part of '../charts_page.dart';

extension _ChartPortfolioSeries on ChartsPageState {
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
      return brokerSeries.series.length < 2 ? null : brokerSeries;
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
    _updateState(() {
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
    _updateState(() {
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
        if (ibkrConfig.enabled) {
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
    _updateState(() {
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
      holdings.add(
        ProvisionalHolding(
          shares: position.netShares,
          closesUsd: {
            for (final row in rows)
              DateTime(row.date.year, row.date.month, row.date.day): row.close /
                  candleCentDivisor(row) /
                  requireUsdRate(
                    normalizedQuoteCurrency(
                      row.rawCurrency ?? position.nativeCurrency,
                    ),
                  ),
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
    _updateState(() {
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
    final accountTrades = await profileDataRepository.readTradesForAccount(
      accountName,
    );
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
          trades: [
            for (final trade in accountTrades)
              if (trade.symbol == position.symbol)
                IntradayPortfolioTrade(
                  trade.tradeDate.toUtc(),
                  trade.quantity,
                  tradeAmountUsd(trade, trade.price),
                ),
          ],
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
      pricesBySymbol[symbol] = {
        for (final candle in rows)
          DateTime(candle.date.year, candle.date.month, candle.date.day):
              candle.close /
                  candleCentDivisor(candle) /
                  requireUsdRate(
                    normalizedQuoteCurrency(
                      candle.rawCurrency ?? symbolCurrency(symbol),
                    ),
                  ),
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
}
