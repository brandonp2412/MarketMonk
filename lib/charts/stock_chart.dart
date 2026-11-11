part of '../charts_page.dart';

extension _ChartStockView on ChartsPageState {
  List<Widget> _buildStockContent(SettingsState settings) {
    final intradaySnapshot = AsyncSnapshot.withData(
      ConnectionState.done,
      switch (true) {
        _
            when (_intradaySeries == null) &&
                (_networkLoading || _stockError == null) =>
          const <CandleTicker>[],
        _ when (_intradaySeries == null) => _stockDailyPreview,
        _ => [
            for (final bar in _intradaySeries!.candles)
              CandleTicker(
                candle: CandlesCompanion(
                  date: Value(bar.date.toLocal()),
                  open: Value(bar.open),
                  high: Value(bar.high),
                  low: Value(bar.low),
                  close: Value(bar.close),
                ),
              ),
          ],
      },
    );
    return [
      if (_usesIntraday)
        _buildStockChart(context, intradaySnapshot, settings)
      else
        StreamBuilder(
          key: ValueKey('stock-chart-$_stockLoadGeneration'),
          stream: _stockStream,
          builder: (context, snapshot) =>
              _buildStockChart(context, snapshot, settings),
        ),
      if (_usesIntraday && _intradaySeries != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '${_intradaySeries!.source} · ${switch (true) {
              _ when _intradaySeries!.isDaily => "1 day",
              _
                  when (days == 1) &&
                      (cryptoAssetForSymbol(_selectedSymbol ?? '') != null) =>
                "5 min",
              _ when (days == 1) => "1 min",
              _ => "15 min",
            }} · ${context.l10n.text('Local time')}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      if (_usesIntraday)
        _buildStockSummary(context, intradaySnapshot)
      else
        StreamBuilder(
          key: ValueKey('stock-summary-$_stockLoadGeneration'),
          stream: _stockStream,
          builder: _buildStockSummary,
        ),
    ];
  }

  Widget _stockUnavailable(BuildContext context, Object error, double height) {
    final missing = RegExp(r'(?<!\d)404(?!\d)').hasMatch(error.toString());
    final theme = Theme.of(context);
    return SizedBox(
      height: height,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                missing ? Icons.search_off_rounded : Icons.cloud_off_rounded,
                size: 44,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                missing ? 'Stock not found' : 'Stock data unavailable',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                missing
                    ? 'This stock could not be found. Check the ticker symbol.'
                    : error.toString(),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStockChart(
    BuildContext context,
    AsyncSnapshot<List<CandleTicker>> snapshot,
    SettingsState settings,
  ) {
    final height = MediaQuery.of(context).size.height * 0.35;
    if (snapshot.hasError) {
      return _stockUnavailable(context, snapshot.error!, height);
    }
    if (_networkLoading) {
      if (isDesktopLayout(context)) {
        return SizedBox(
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              TickerLine(
                key: const ValueKey('stock-loading-frame'),
                spots: const [],
                dates: const [],
                loading: true,
                nativeCurrency: _nativeCurrency,
                intraday: _usesIntraday,
                requestedStartDate:
                    _usesIntraday ? null : _requiredCandleStart(),
              ),
              const Center(
                child: MarketChartLoading(key: Key('stock-period-loading')),
              ),
            ],
          ),
        );
      }
      return SizedBox(
        height: height,
        child: const Center(
          child: MarketChartLoading(key: Key('stock-period-loading')),
        ),
      );
    }
    if (snapshot.data == null || snapshot.data!.isEmpty) {
      if (_stockError != null) {
        return _stockUnavailable(context, _stockError!, height);
      }
      return SizedBox(
        height: height,
        child:
            _networkLoading ? const Center(child: MarketChartLoading()) : null,
      );
    }

    final allCandles = snapshot.data!.map((tc) => tc.candle).toList();
    final cryptoCandlesRequested = _showCandlesticks &&
        !_usesIntraday &&
        cryptoAssetForSymbol(_selectedSymbol ?? '') != null;
    final genuineCandles = cryptoCandlesRequested
        ? allCandles
            .where(
              (candle) =>
                  candle.high.value > candle.low.value ||
                  candle.open.value != candle.close.value,
            )
            .toList()
        : const <CandlesCompanion>[];
    final usingCryptoCandles = genuineCandles.isNotEmpty;
    final candles = usingCryptoCandles ? genuineCandles : allCandles;
    String? observedUnit(CandlesCompanion candle) =>
        candle.rawCurrency.present ? candle.rawCurrency.value : null;
    if ((!_usesIntraday || _intradaySeries == null) &&
        _selectedSymbol != null &&
        symbolHasQuoteCurrencyChange(_selectedSymbol!) &&
        candles.any((candle) => observedUnit(candle) == null)) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text(
            'Historical candle quotation units are unverified following a '
            'currency change. Refresh or reconcile the history before charting.',
          ),
        ),
      );
    }
    if (candles.any(
      (candle) =>
          observedUnit(candle) != null &&
          normalizedQuoteCurrency(observedUnit(candle)!) != _nativeCurrency,
    )) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text(
            'Historical prices use different currencies; verify the source '
            'before displaying a combined chart.',
          ),
        ),
      );
    }
    double scale(CandlesCompanion candle) => observedUnit(candle) == null
        ? _centDivisor
        : quoteUnitDivisor(observedUnit(candle)!);
    final spots = <MarketLineChartPoint>[
      for (var index = 0; index < candles.length; index++)
        MarketLineChartPoint(
          index.toDouble(),
          candles[index].close.value / scale(candles[index]),
          column: index,
        ),
    ];

    return DesktopContextMenu(
      actions: [
        DesktopMenuAction(
          context.l10n.text('Refresh'),
          () => runDetachedTask(
            _refreshCurrentChart(),
            'Failed to refresh chart',
          ),
          icon: Icons.refresh_rounded,
        ),
        DesktopMenuAction(
          context.l10n.text(
            _favoriteStocks.contains(_selectedSymbol)
                ? 'Remove favorite'
                : 'Add favorite',
          ),
          () => _toggleFavorite(_selectedSymbol!),
          icon: _favoriteStocks.contains(_selectedSymbol)
              ? Icons.star_rounded
              : Icons.star_border_rounded,
        ),
        if (!context.read<AccountManager>().ibkrConfigFor().enabled)
          DesktopMenuAction(
            context.l10n.text('Add trade'),
            () => Navigator.push(
              context,
              adaptivePageRoute(
                context,
                builder: (_) => EditTickerPage(symbol: _selectedSymbol),
              ),
            ),
            icon: Icons.add_rounded,
          ),
      ],
      copyText: _selectedSymbol,
      copyLabel: context.l10n.text('Copy symbol'),
      child: SizedBox(
        height: height,
        child: TickerLine(
          key: ValueKey('$_selectedSymbol|$years|$months|$days'),
          range: _chartRangeFor([
            for (final candle in candles) candle.date.value,
          ]),
          pickRange: _pickingChartRange,
          onRangeChanged: (range) => _setChartRange(
            [for (final candle in candles) candle.date.value],
            range,
          ),
          dates: candles.map((candle) => candle.date.value),
          spots: spots,
          candles: [
            for (var i = 0; i < candles.length; i++)
              MarketCandlePoint(
                column: i,
                open: candles[i].open.value / scale(candles[i]),
                high: candles[i].high.value / scale(candles[i]),
                low: candles[i].low.value / scale(candles[i]),
                close: candles[i].close.value / scale(candles[i]),
              ),
          ],
          showCandlesticks: _showCandlesticks &&
              (cryptoAssetForSymbol(_selectedSymbol!) == null ||
                  _usesIntraday ||
                  usingCryptoCandles),
          candleSelection: _candleSelection,
          showRollingAverage: _showRollingAverage,
          nativeCurrency: _nativeCurrency,
          intraday: _usesIntraday && _intradaySeries != null,
          requestedStartDate: _usesIntraday ? null : _requiredCandleStart(),
        ),
      ),
    );
  }

  // Total height of the summary rows (percent + price, then period change),
  // so the loading placeholder takes exactly the space the values will.
}
