part of '../charts_page.dart';

extension _ChartPortfolioLoading on ChartsPageState {
  Future<void> _loadPeriodThenPortfolios() async {
    final settings = context.read<SettingsState>();
    await settings.initialized;
    if (!mounted) return;

    final prefs = await SqliteSettings.getInstance();
    final periodYears = prefs.getInt('chartPeriodYears') ?? 1;
    final periodMonths = prefs.getInt('chartPeriodMonths') ?? 0;
    final periodDays = prefs.getInt('chartPeriodDays') ?? 0;
    if (!mounted) return;

    _updateState(() {
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
            final cash = resolveIbkrCash(snapshot);
            await accountManager.cachePortfolio(
              accountName,
              positions,
              snapshot.netLiquidation,
              netLiquidationUsd: currentValueUsd,
              cashBalance: cash?.reported,
              cashUsd: cash?.usd,
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
}
