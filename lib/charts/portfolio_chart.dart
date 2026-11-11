part of '../charts_page.dart';

extension _ChartPortfolioView on ChartsPageState {
  Widget _buildPortfolioChart(
    BuildContext context,
    SettingsState settings,
    List<Color> accountColors,
  ) {
    final streamKey =
        '${widget.isActive}|$_selectedFavorites|$years|$months|$days';
    if (_favoriteChartStreamKey != streamKey) {
      _favoriteChartStreamKey = streamKey;
      _favoriteChartStream = widget.isActive &&
              (!_usesIntraday || days == 5) &&
              _selectedFavorites.isNotEmpty
          ? (marketDataDatabase.candles.select()
                ..where(
                  (candle) =>
                      candle.symbol.isIn(
                        _selectedFavorites.map(canonicalMarketSymbol),
                      ) &
                      candle.date.isBiggerThanValue(_requiredCandleStart()),
                )
                ..orderBy([(candle) => OrderingTerm.asc(candle.date)]))
              .watch()
          : null;
    }
    return StreamBuilder<List<StoredCandle>>(
      key: const Key('portfolio-price-stream'),
      stream: _favoriteChartStream,
      builder: (context, snapshot) => _buildCombinedPortfolioChart(
        context,
        settings,
        accountColors,
        snapshot.connectionState == ConnectionState.active
            ? snapshot.data ?? const []
            : _restoredFavoriteCandles ?? const [],
        localPricesReady: _selectedFavorites.isEmpty ||
            _usesIntraday && days != 5 ||
            snapshot.connectionState == ConnectionState.active &&
                snapshot.hasData ||
            _restoredFavoriteCandles != null,
      ),
    );
  }

  Widget _buildCombinedPortfolioChart(
    BuildContext context,
    SettingsState settings,
    List<Color> accountColors,
    List<StoredCandle> favoriteCandles, {
    required bool localPricesReady,
  }) {
    if (_periodTransition || !localPricesReady) {
      return SizedBox(
        height: MediaQuery.of(context).size.height * 0.30,
        child: const Center(
          child: MarketChartLoading(key: Key('chart-period-loading')),
        ),
      );
    }
    final chart = _buildReadyPortfolioChart(
      context,
      settings,
      accountColors,
      favoriteCandles,
      localPricesReady: localPricesReady,
    );
    if (!_portfolioLoading &&
        !_networkLoading &&
        (!_usesIntraday ||
            _selectedFavorites.every(
              (symbol) =>
                  _favoriteIntraday.containsKey(symbol) ||
                  _favoriteIntradayErrors.containsKey(symbol),
            ))) {
      if (_chartPeriodCache.length >= 16 &&
          !_chartPeriodCache.containsKey(_chartPeriodCacheKey)) {
        _chartPeriodCache.remove(_chartPeriodCache.keys.first);
      }
      _chartPeriodCache[_chartPeriodCacheKey] = _CachedChartPeriod(
        series: Map.of(_portfolioSeriesByAccount),
        returns: Map.of(_portfolioReturnSeriesByAccount),
        flows: Map.of(_portfolioCashFlowsByAccount),
        favorites: Map.of(_favoriteIntraday),
        favoriteErrors: Map.of(_favoriteIntradayErrors),
        dailyPreviews: Set.of(_portfolioDailyPreviewAccounts),
        provisionalStarts: Map.of(_provisionalStartByAccount),
        candles: favoriteCandles,
        error: _portfolioError,
      );
    }
    return chart;
  }

  Widget _buildReadyPortfolioChart(
    BuildContext context,
    SettingsState settings,
    List<Color> accountColors,
    List<StoredCandle> favoriteCandles, {
    required bool localPricesReady,
  }) {
    final height = MediaQuery.of(context).size.height * 0.30;

    final hasFavoritePrices = _selectedFavorites.any(
      (symbol) =>
          _favoriteIntraday[symbol]?.candles.isNotEmpty == true ||
          favoriteCandles.any(
            (candle) => candle.symbol == canonicalMarketSymbol(symbol),
          ),
    );
    if (!hasFavoritePrices &&
        _portfolioLoading &&
        _portfolioSeriesByAccount.values.every((series) => series.isEmpty)) {
      return SizedBox(
        height: height,
        child: _pendingRemoteLoads > 0 && localPricesReady
            ? const Center(child: MarketChartLoading())
            : null,
      );
    }
    if (_portfolioError != null &&
        _portfolioSeriesByAccount.values.every((series) => series.isEmpty) &&
        _selectedFavorites.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(child: Text(_portfolioError!)),
      );
    }

    final accountManager = context.read<AccountManager>();
    final accounts = accountManager.accounts;
    final favoriteOhlcBySymbol = <String,
        Map<DateTime,
            ({double open, double high, double low, double close})>>{};
    final visibleSeries = <String, List<_DateValue>>{};

    for (final symbol in _favoriteStocks.where(_selectedFavorites.contains)) {
      if (_usesIntraday) {
        final series = _favoriteIntraday[symbol];
        if (series != null) {
          final divisor = symbolCentDivisor(symbol);
          favoriteOhlcBySymbol[symbol] = {
            for (final bar in series.candles)
              bar.date.toLocal(): (
                open: bar.open / divisor,
                high: bar.high / divisor,
                low: bar.low / divisor,
                close: bar.close / divisor,
              ),
          };
          visibleSeries[symbol] = [
            for (final bar in series.candles)
              _DateValue(
                bar.date.toLocal(),
                bar.close / symbolCentDivisor(symbol),
              ),
          ];
          continue;
        }
        if (days != 5 || !_favoriteIntradayErrors.containsKey(symbol)) continue;
      }
      var candles = favoriteCandles
          .where((candle) => candle.symbol == canonicalMarketSymbol(symbol))
          .toList();
      if (days > 0 && candles.length > days) {
        candles = candles.sublist(candles.length - days);
      }
      if (candles.isNotEmpty) {
        favoriteOhlcBySymbol[symbol] = {
          for (final candle in candles)
            candle.date: (
              open: candle.open / candleCentDivisor(candle),
              high: candle.high / candleCentDivisor(candle),
              low: candle.low / candleCentDivisor(candle),
              close: candle.close / candleCentDivisor(candle),
            ),
        };
        visibleSeries[symbol] = [
          for (final candle in candles)
            _DateValue(candle.date, candle.close / candleCentDivisor(candle)),
        ];
      }
    }

    for (final account in accounts) {
      final series = _portfolioSeriesByAccount[account];
      if (!accountManager.isAccountHidden(account) &&
          !_hiddenAccounts.contains(account) &&
          series != null &&
          series.isNotEmpty) {
        visibleSeries[account] = series;
      }
    }

    if (visibleSeries.isEmpty) {
      if (_pendingRemoteLoads > 0 && localPricesReady) {
        return SizedBox(
          height: height,
          child: const Center(child: MarketChartLoading()),
        );
      }
      final allEmpty = _portfolioSeriesByAccount.values.every(
        (series) => series.isEmpty,
      );
      final hasCachedHoldings = accounts.any(
        (name) =>
            accountManager.portfolioCacheFor(name)?.positions.isNotEmpty ??
            false,
      );
      final pricesUnavailable = allEmpty && hasCachedHoldings;
      return SizedBox(
        height: height,
        child: AppEmptyState(
          icon: allEmpty
              ? Icons.candlestick_chart_rounded
              : Icons.visibility_off_rounded,
          title: switch (true) {
            _ when pricesUnavailable =>
              context.l10n.text('Historical prices unavailable'),
            _ when allEmpty => context.l10n.text('No trades yet'),
            _ => context.l10n.text('All portfolios are hidden'),
          },
          message: switch (true) {
            _ when pricesUnavailable =>
              context.l10n.text('No market data found'),
            _ when allEmpty => context.l10n.text(
                'Search for a stock to start building your portfolio history.',
              ),
            _ => context.l10n.text(
                'Show your portfolios again to restore the chart.',
              ),
          },
          actionLabel: switch (true) {
            _ when pricesUnavailable => context.l10n.text('Refresh'),
            _ when allEmpty => context.l10n.text('Search stocks'),
            _ => context.l10n.text('Show all'),
          },
          actionIcon: switch (true) {
            _ when pricesUnavailable => Icons.refresh_rounded,
            _ when allEmpty => Icons.search_rounded,
            _ => Icons.visibility_rounded,
          },
          onAction: () {
            if (pricesUnavailable) {
              runDetachedTask(
                _refreshCurrentChart(),
                'Failed to refresh chart',
              );
            } else if (allEmpty) {
              _updateState(() => _mode = _ChartMode.searching);
              _searchFocus.requestFocus();
            } else {
              _updateState(_hiddenAccounts.clear);
            }
          },
        ),
      );
    }

    final allDates = <DateTime>{};
    for (final series in visibleSeries.values) {
      for (final point in series) {
        allDates.add(point.date);
      }
    }
    final sortedDates = allDates.toList()..sort();
    final chartStart = _usesIntraday ? null : _requiredCandleStart();
    final chartPositions = chartStart == null
        ? null
        : [
            for (final date in sortedDates)
              date.difference(chartStart).inMinutes / Duration.minutesPerDay,
          ];
    final dateIndex = <DateTime, int>{
      for (var index = 0; index < sortedDates.length; index++)
        sortedDates[index]: index,
    };

    final singleLine = visibleSeries.length == 1;
    final scaleForComparison = !singleLine || _selectedFavorites.isNotEmpty;
    final chartSeries = <MarketLineChartSeries>[];
    final chartCandles = <MarketCandlePoint>[];
    final candleTooltipRowsByIndex = <int, List<String>>{};
    for (final entry in visibleSeries.entries) {
      final accountIndex = accounts.indexOf(entry.key);
      final color = _selectedFavorites.contains(entry.key)
          ? _favoriteColor(entry.key)
          : accountColors[accountIndex.clamp(0, accountColors.length - 1)];
      final returnByDate = {
        for (final point
            in _portfolioReturnSeriesByAccount[entry.key] ?? <_DateValue>[])
          point.date: point.value,
      };
      final comparisonValues = [
        for (final point in entry.value)
          returnByDate[point.date] ?? point.value,
      ];
      final displayValues = scaleForComparison
          ? scalePortfolioSeriesForComparison(comparisonValues)
          : entry.value.map((point) => point.value).toList(growable: false);
      final baseline = comparisonValues.firstWhere(
        (value) => value.isFinite && value.abs() > 1e-9,
        orElse: () => 0,
      );
      double chartValue(double value) {
        if (!scaleForComparison) return value;
        if (baseline == 0) return 0;
        return (value / baseline - 1) * 100;
      }

      final seriesIndex = chartSeries.length;
      final ohlcByDate = favoriteOhlcBySymbol[entry.key];
      for (var index = 0; index < entry.value.length; index++) {
        final point = entry.value[index];
        final column = dateIndex[point.date]!;
        final rawOhlc = ohlcByDate?[point.date];
        if (rawOhlc != null) {
          chartCandles.add(
            MarketCandlePoint(
              column: column,
              seriesIndex: seriesIndex,
              open: chartValue(rawOhlc.open),
              high: chartValue(rawOhlc.high),
              low: chartValue(rawOhlc.low),
              close: chartValue(rawOhlc.close),
            ),
          );
          if (_showCandlesticks) {
            candleTooltipRowsByIndex.putIfAbsent(column, () => []).addAll([
              entry.key,
              'O ${fmtNativeCurrency(rawOhlc.open, symbolCurrency(entry.key))}  H ${fmtNativeCurrency(rawOhlc.high, symbolCurrency(entry.key))}',
              'L ${fmtNativeCurrency(rawOhlc.low, symbolCurrency(entry.key))}  C ${fmtNativeCurrency(rawOhlc.close, symbolCurrency(entry.key))}',
            ]);
          }
        } else {
          final previous =
              index == 0 ? point.value : entry.value[index - 1].value;
          final open =
              index == 0 ? displayValues[index] : displayValues[index - 1];
          final close = displayValues[index];
          chartCandles.add(
            MarketCandlePoint(
              column: column,
              seriesIndex: seriesIndex,
              sampled: true,
              open: open,
              high: max(open, close),
              low: min(open, close),
              close: close,
            ),
          );
          if (_showCandlesticks) {
            candleTooltipRowsByIndex.putIfAbsent(column, () => []).addAll([
              '${entry.key} · sampled',
              'O ${fmtCurrency(previous)}  C ${fmtCurrency(point.value)}',
            ]);
          }
        }
      }
      chartSeries.add(
        MarketLineChartSeries(
          name: entry.key,
          color: color,
          strokeWidth: 2.5,
          fill: true,
          points: [
            for (var index = 0; index < entry.value.length; index++)
              MarketLineChartPoint(
                chartPositions?[dateIndex[entry.value[index].date]!] ??
                    dateIndex[entry.value[index].date]!.toDouble(),
                displayValues[index],
                comparisonValue:
                    scaleForComparison ? comparisonValues[index] : null,
                column: dateIndex[entry.value[index].date]!,
              ),
          ],
        ),
      );
    }

    final dailyOnly = _usesIntraday &&
        days == 5 &&
        visibleSeries.keys.every(
          (name) => accounts.contains(name)
              ? _portfolioDailyPreviewAccounts.contains(name)
              : !_favoriteIntraday.containsKey(name),
        );
    final formatter = DateFormat(
      _usesIntraday && !dailyOnly
          ? '${settings.dateFormat} HH:mm'
          : settings.dateFormat,
    );
    final axisFormatter = DateFormat(
      _usesIntraday && !dailyOnly ? 'HH:mm' : settings.dateFormat,
    );
    final visibleKeys = visibleSeries.keys.toList();

    return SizedBox(
      height: height,
      child: Column(
        children: [
          Expanded(
            child: MarketLineChart(
              key: ValueKey('portfolio|$years|$months|$days'),
              range: _chartRangeFor(sortedDates),
              onRangeChanged: (range) => _setChartRange(sortedDates, range),
              pickRange: _pickingChartRange,
              series: chartSeries,
              candles: chartCandles,
              showCandlesticks: _showCandlesticks,
              candleSelection: _candleSelection,
              candleTooltipTitle: (index) =>
                  index >= 0 && index < sortedDates.length
                      ? formatter.format(sortedDates[index])
                      : '',
              candleTooltipRows: _showCandlesticks
                  ? (index) => candleTooltipRowsByIndex[index] ?? const []
                  : null,
              showRollingAverage: _showRollingAverage,
              xLabels: [
                for (final date in sortedDates) axisFormatter.format(date),
              ],
              pointCount: sortedDates.length,
              xAxisPositions: chartPositions,
              yLabelFormatter: (value) => scaleForComparison
                  ? fmtChartAxisPercent(value)
                  : fmtCompactCurrency(value),
              tooltipRowLabel: (PlotMark mark) {
                final accountName = mark.seriesIndex < visibleKeys.length
                    ? visibleKeys[mark.seriesIndex]
                    : '';
                final date = mark.index >= 0 && mark.index < sortedDates.length
                    ? sortedDates[mark.index]
                    : null;
                double? actualValue;
                if (date != null) {
                  for (final point
                      in visibleSeries[accountName] ?? const <_DateValue>[]) {
                    if (point.date == date) {
                      actualValue = point.value;
                      break;
                    }
                  }
                }
                final valueLabel = _selectedFavorites.contains(accountName)
                    ? fmtNativeCurrency(
                        actualValue ?? mark.value,
                        symbolCurrency(accountName),
                      )
                    : fmtCurrency(actualValue ?? mark.value);
                final dateLabel = date == null ? '' : formatter.format(date);
                final returnLabel = scaleForComparison
                    ? '${mark.value >= 0 ? '+' : ''}${mark.value.toStringAsFixed(2)}% · '
                    : '';
                return dateLabel.isEmpty
                    ? '$returnLabel$valueLabel'
                    : '$returnLabel$valueLabel · $dateLabel';
              },
              curveLines: settings.curveLines,
              curveSmoothness: settings.curveSmoothness,
              showGridlines: settings.showChartGridlines,
              fillChartArea: settings.fillChartArea,
              leftInset: scaleForComparison ? 72 : 64,
              accessibilityLabel: context.l10n.text('Portfolio performance'),
              accessibilityValue:
                  '${chartSeries.length} ${context.l10n.text('portfolios')}',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPortfolioSummary(
    BuildContext context,
    List<Color> accountColors,
  ) {
    final accounts = context.read<AccountManager>().accounts;
    if (accounts.isEmpty) return const SizedBox.shrink();

    final rows = Column(
      children: [
        for (final accountName in accounts)
          if (!context.read<AccountManager>().isAccountHidden(accountName))
            _buildAccountSummaryRow(
              context,
              accounts,
              accountName,
              _portfolioSeriesByAccount[accountName] ?? const [],
              accountColors,
            ),
      ],
    );
    return Padding(
      key: const Key('portfolio-summary-content'),
      padding: EdgeInsets.symmetric(
        horizontal: isDesktopLayout(context) ? 32 : 16,
        vertical: 8,
      ),
      child: isDesktopLayout(context)
          ? Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: rows,
              ),
            )
          : rows,
    );
  }

  Widget _buildAccountSummaryRow(
    BuildContext context,
    List<String> accounts,
    String accountName,
    List<_DateValue> series,
    List<Color> accountColors,
  ) {
    final idx = accounts.indexOf(accountName);
    final dotColor = accountColors[idx.clamp(0, accountColors.length - 1)];
    final accountReturns = _portfolioReturnSeriesByAccount[accountName];
    final visibleSeries = _visibleValues(series);
    final visibleReturns = _visibleValues(accountReturns ?? <_DateValue>[]);
    final hasHistory = accountReturns != null
        ? visibleReturns.length > 1
        : visibleSeries.length > 1;
    final pct = hasHistory
        ? safePercentChange(
            accountReturns != null
                ? visibleReturns.first.value
                : visibleSeries.first.value,
            accountReturns != null
                ? visibleReturns.last.value
                : visibleSeries.last.value,
          )
        : 0.0;
    final returnColor = switch (true) {
      _ when (hasHistory) && (pct >= 0) => Colors.green,
      _ when (hasHistory) => Colors.redAccent,
      _ => Theme.of(context).colorScheme.onSurfaceVariant,
    };
    final flows = _portfolioCashFlowsByAccount[accountName];
    final externalFlows = flows == null || visibleSeries.length < 2
        ? 0.0
        : flows.entries
            .where(
              (entry) =>
                  entry.key.isAfter(visibleSeries.first.date) &&
                  !entry.key.isAfter(visibleSeries.last.date),
            )
            .fold<double>(0.0, (total, entry) => total + entry.value);
    final change = visibleSeries.length > 1
        ? visibleSeries.last.value - visibleSeries.first.value - externalFlows
        : 0.0;
    final isHidden = _hiddenAccounts.contains(accountName);
    final accountManager = context.read<AccountManager>();
    final cachedPortfolio = accountManager.portfolioCacheFor(accountName);
    var currentValueUsd = cachedPortfolio?.netLiquidationUsd;
    final netLiquidation = cachedPortfolio?.netLiquidation;
    if ((currentValueUsd == null || !currentValueUsd.isFinite) &&
        netLiquidation != null) {
      if (netLiquidation.currency == 'USD') {
        currentValueUsd = netLiquidation.value;
      } else {
        final basePerUsd = allRatesFromUsd[netLiquidation.currency];
        if (basePerUsd != null && basePerUsd.isFinite && basePerUsd > 0) {
          currentValueUsd = netLiquidation.value / basePerUsd;
        }
      }
    }
    final estimated = series.isNotEmpty &&
        _provisionalStartByAccount[accountName] != null &&
        !series.last.date.isBefore(_provisionalStartByAccount[accountName]!);
    final summaryValue = switch (true) {
      _ when estimated => series.last.value,
      _ when currentValueUsd != null && currentValueUsd.isFinite =>
        currentValueUsd,
      _ when series.isNotEmpty => series.last.value,
      _ => null,
    };
    final theme = Theme.of(context);

    Widget returnLabel() => Text(
          (switch (true) {
            _ when hasHistory =>
              <String>[if (pct >= 0) '+', pct.toStringAsFixed(2), '%'].join(),
            _ when _portfolioLoading => '—',
            _ => '—',
          }),
          maxLines: 1,
          style: theme.textTheme.titleMedium!.copyWith(color: returnColor),
        );

    final valueText = Text(
      summaryValue == null ? '—' : fmtCurrency(summaryValue),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.right,
      style: theme.textTheme.titleMedium!.copyWith(height: 1.1),
    );
    final changeText = Text(
      switch (true) {
        _ when hasHistory => (change >= 0 ? '+' : '') + fmtCurrency(change),
        _ when _portfolioLoading => '—',
        _ => '—',
      },
      maxLines: 1,
      style: TextStyle(color: returnColor, fontSize: 13, height: 1.1),
    );
    return Column(
      children: [
        AnimatedOpacity(
          opacity: isHidden ? 0.35 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: DesktopContextMenu(
              actions: [
                DesktopMenuAction(
                  context.l10n.text('Show only this account'),
                  () => _updateState(() {
                    _hiddenAccounts.clear();
                    _hiddenAccounts.addAll(
                      accounts.where((name) => name != accountName),
                    );
                  }),
                  icon: Icons.visibility_rounded,
                ),
                if (_hiddenAccounts.isNotEmpty)
                  DesktopMenuAction(
                    context.l10n.text('Show all accounts'),
                    () => _updateState(_hiddenAccounts.clear),
                    icon: Icons.visibility_rounded,
                  ),
              ],
              copyText: '$accountName: ${valueText.data} · ${changeText.data}',
              copyLabel: context.l10n.text('Copy account summary'),
              child: ListTile(
                dense: true,
                key: Key('chart-account-selector-$accountName'),
                onLongPress: () => showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  builder: (sheetContext) => SafeArea(
                    child: ListTile(
                      leading: const Icon(Icons.visibility_off_outlined),
                      title: Text(context.l10n.text('Hide this account')),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        unawaited(
                          accountManager.setAccountHidden(accountName, true),
                        );
                      },
                    ),
                  ),
                ),
                onTap: () => _updateState(() {
                  if (isHidden) {
                    _hiddenAccounts.remove(accountName);
                  } else {
                    _hiddenAccounts.add(accountName);
                  }
                }),
                leading: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: isHidden
                        ? theme.colorScheme.surfaceContainerHighest
                        : dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                title: Text(
                  accountName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: returnLabel(),
                trailing: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 110),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      valueText,
                      const SizedBox(height: 2),
                      changeText,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
