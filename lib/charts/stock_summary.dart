part of '../charts_page.dart';

extension _ChartStockSummary on ChartsPageState {
  Widget _buildStockSummary(
    BuildContext context,
    AsyncSnapshot<List<CandleTicker>> snapshot,
  ) {
    if (_networkLoading || !snapshot.hasData || snapshot.data!.isEmpty) {
      if (_networkLoading && _selectedSymbol != null) {
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isDesktopLayout(context) ? 32 : 16,
            vertical: 8,
          ),
          child: Column(
            children: [
              _buildStockSummarySkeleton(),
              const SizedBox(height: 12),
              _stockActionChips(_selectedSymbol!),
            ],
          ),
        );
      }
      return const SizedBox();
    }

    final allCandles = snapshot.data!.map((tc) => tc.candle).toList();
    final genuineCandles = _showCandlesticks &&
            !_usesIntraday &&
            cryptoAssetForSymbol(_selectedSymbol ?? '') != null
        ? allCandles
            .where(
              (candle) =>
                  candle.high.value > candle.low.value ||
                  candle.open.value != candle.close.value,
            )
            .toList()
        : const <CandlesCompanion>[];
    final candles = genuineCandles.isNotEmpty ? genuineCandles : allCandles;
    final pct = safePercentChange(
      candles.first.close.value,
      candles.last.close.value,
    );
    final color = pct >= 0 ? Colors.green : Colors.redAccent;
    final symbol = _selectedSymbol ?? '';
    final dollarChange =
        (candles.last.close.value - candles.first.close.value) / _centDivisor;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktopLayout(context) ? 32 : 16,
        vertical: 8,
      ),
      child: Column(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: ChartsPageState._stockSummaryHeight,
            ),
            child: Column(
              children: [
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 16,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          pct >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                          color: color,
                        ),
                        Text(
                          '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge!
                              .copyWith(color: color),
                        ),
                      ],
                    ),
                    Text(
                      fmtNativeCurrency(
                        candles.last.close.value / _centDivisor,
                        _nativeCurrency,
                      ),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  context.l10n.text('{value} period change', {
                    'value':
                        '${dollarChange >= 0 ? '+' : ''}${fmtNativeCurrency(dollarChange, _nativeCurrency)}',
                  }),
                  style: TextStyle(color: color, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _stockActionChips(symbol),
        ],
      ),
    );
  }

  Widget _stockActionChips(String symbol) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        ChartActionChip(
          icon: Icons.add,
          label: context.l10n.text('Add trade'),
          onTap: () => Navigator.push(
            context,
            adaptivePageRoute(
              context,
              builder: (_) => EditTickerPage(symbol: symbol),
            ),
          ),
        ),
        ChartActionChip(
          icon: _favoriteStocks.contains(symbol)
              ? Icons.favorite
              : Icons.favorite_border,
          label: context.l10n.text('Favorite'),
          onTap: () => _toggleFavorite(symbol),
        ),
        _buildRollingAverageChip(),
        Semantics(
          key: const Key('chart-candlestick-toggle'),
          selected: _showCandlesticks,
          button: true,
          child: ChartActionChip(
            icon: _showCandlesticks
                ? Icons.candlestick_chart
                : Icons.candlestick_chart_outlined,
            label: 'Candles',
            onTap: _toggleCandlesticks,
          ),
        ),
      ],
    );
  }

  Widget _buildStockSummarySkeleton() {
    final color = Theme.of(context).colorScheme.outline.withValues(alpha: 0.18);
    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(height / 2),
          ),
        );
    return ConstrainedBox(
      constraints:
          const BoxConstraints(minHeight: ChartsPageState._stockSummaryHeight),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [bar(88, 20), const SizedBox(width: 16), bar(96, 20)],
          ),
          const SizedBox(height: 4),
          bar(140, 12),
        ],
      ),
    );
  }
}
