import 'package:drift/drift.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/holdings_page.dart' show tradesFromIbkr;
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/logging.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/portfolio_allocation.dart';
import 'package:market_monk/portfolio_returns.dart';
import 'package:market_monk/profile_data_repository.dart';
import 'package:market_monk/utils.dart';
import 'package:market_monk/sqlite_settings.dart';

typedef PortfolioCandleSync = Future<void> Function(
  String symbol,
  DateTime from,
  IbkrAccountConfig config,
);

typedef PortfolioHistoricalRate = Future<double> Function(
  String currency,
  DateTime date,
);

DateTime? portfolioInception(IbkrPerformanceSeries? performance) {
  if (performance == null ||
      performance.dates.length != performance.nav.length) {
    return null;
  }
  for (var index = 0; index < performance.dates.length; index++) {
    if (performance.nav[index].isFinite && performance.nav[index] > 0) {
      return performance.dates[index];
    }
  }
  return performance.dates.firstOrNull;
}

class PortfolioHistory {
  final List<Trade> trades;
  final Map<String, List<StoredCandle>> candles;
  final Map<DateTime, Map<String, double>> rates;

  const PortfolioHistory({
    required this.trades,
    required this.candles,
    required this.rates,
  });

  List<PortfolioAllocation>? allocationAt({
    required List<Position> positions,
    required DateTime? date,
    IbkrPerformanceSeries? performance,
    double? currentCashUsd,
  }) {
    final index = date == null || performance == null
        ? null
        : accountNetAssetValueIndexAt(performance, date);
    if (date != null && performance != null && index == null) return null;
    final valuationDate = index == null ? date : performance!.dates[index];
    final dayRates = rates[valuationDate];
    final nav = index == null ? null : performance!.nav[index];
    final navRate = performance == null
        ? null
        : dayRates?[performance.currency.toUpperCase()];
    if (nav != null && navRate == null) return null;
    return portfolioAllocationAt(
      positions: positions,
      trades: trades,
      candles: candles,
      date: valuationDate,
      cashValueUsd: currentCashUsd,
      historicalAccountValueUsd: nav == null ? null : nav / navRate!,
      currencyRates: dayRates,
    );
  }
}

Future<PortfolioHistory> loadPortfolioHistory({
  required AccountManager accounts,
  required String accountName,
  required List<Position> positions,
  required Database database,
  DateTime? now,
  bool forceRefresh = false,
  bool cacheOnly = false,
  Future<IbkrTradeHistory> Function(IbkrAccountConfig)? tradeLoader,
  PortfolioCandleSync? candleSync,
  PortfolioHistoricalRate? rateLoader,
}) async {
  final config = accounts.ibkrConfigFor(accountName);
  var brokerHistory =
      config.enabled ? accounts.ibkrTradeHistoryCacheFor(accountName) : null;
  if (!cacheOnly &&
      config.isConfigured &&
      (forceRefresh || !accounts.isIbkrTradeHistoryCacheFresh(accountName))) {
    try {
      final loaded = await (tradeLoader?.call(config) ??
          IbkrApiClient(config).fetchTradeHistory());
      if (loaded.available) {
        await accounts.cacheIbkrTradeHistory(accountName, loaded);
        brokerHistory = loaded;
      } else if (brokerHistory?.available != true) {
        throw StateError('IBKR transaction history is unavailable');
      }
    } catch (error, stack) {
      if (brokerHistory?.available != true) rethrow;
      talker.handle(error, stack, 'Using cached IBKR portfolio trades');
    }
  }
  final trades = switch (true) {
    _ when (brokerHistory?.available == true) && (cacheOnly) =>
      tradesFromIbkr(brokerHistory!.trades),
    _ when (brokerHistory?.available == true) =>
      await enrichHistoricalTradeRates(tradesFromIbkr(brokerHistory!.trades)),
    _ =>
      await ProfileDataRepository(database).readTradesForAccount(accountName),
  };
  final performance = config.enabled
      ? accounts.ibkrPerformanceCacheFor(accountName, '1Y')
      : null;
  final today = now ?? DateTime.now();
  final starts = [
    if (portfolioInception(performance) case final inception?) inception,
    ...trades.map((trade) => trade.tradeDate),
  ];
  final from = starts.isEmpty
      ? today.subtract(defaultMarketCandleLookback)
      : starts
          .reduce((a, b) => a.isBefore(b) ? a : b)
          .subtract(const Duration(days: 7));
  final dates = <DateTime>{
    if (portfolioInception(performance) case final inception?) inception,
    for (var period = 1; period < firstIntradayPeriod; period++)
      if (performance != null)
        if (accountNetAssetValueIndexAt(
          performance,
          portfolioReturnCutoff(period, today)!,
        )
            case final index?)
          performance.dates[index],
  };
  final sharesByDate = {
    for (final date in dates)
      date: portfolioSharesAt(positions: positions, trades: trades, date: date),
  };
  final candles = <String, List<StoredCandle>>{};
  final currentSymbols = {
    for (final position in positions)
      if (position.netShares != 0) position.symbol,
  };
  final symbols = {
    ...currentSymbols,
    ...trades.map((trade) => trade.symbol),
  };
  Future<List<StoredCandle>> readCandles(String symbol) async {
    final rows = await (database.candles.select()
          ..where((row) => row.symbol.equals(canonicalMarketSymbol(symbol)))
          ..orderBy([(row) => OrderingTerm.asc(row.date)]))
        .get();
    return [
      for (final row in rows) row.copyWith(date: canonicalMarketDay(row.date)),
    ];
  }

  for (final symbol in symbols) {
    candles[symbol] = await readCandles(symbol);
    final covered = dates.isNotEmpty &&
        dates.every((date) {
          if ((sharesByDate[date]![symbol] ?? 0) <= 1e-6) return true;
          return candles[symbol]!.any(
            (candle) =>
                !candle.date.isAfter(date) &&
                date.difference(candle.date).inDays <= 7 &&
                candle.close.isFinite &&
                candle.close > 0,
          );
        });
    final refreshCurrent = forceRefresh && currentSymbols.contains(symbol);
    if (cacheOnly || (covered && !refreshCurrent)) continue;
    final priceConfig =
        currentSymbols.contains(symbol) ? config : const IbkrAccountConfig();
    try {
      if (candleSync != null) {
        await candleSync(symbol, from, priceConfig);
      } else {
        await syncCandles(
          symbol,
          database: database,
          ibkrConfig: priceConfig,
          requiredFrom: from,
          forceRefresh: refreshCurrent,
        );
      }
    } catch (error, stack) {
      talker.handle(
        error,
        stack,
        'Failed to backfill portfolio prices: $symbol',
      );
    }
    candles[symbol] = await readCandles(symbol);
  }
  final rates = <DateTime, Map<String, double>>{};
  final currencies = {
    'USD',
    if (performance != null) performance.currency.toUpperCase(),
    for (final series in candles.values)
      for (final candle in series)
        if (candle.rawCurrency != null)
          normalizedQuoteCurrency(candle.rawCurrency!),
  };
  for (final date in dates) {
    rates[date] = {'USD': 1};
    for (final currency in currencies.where((currency) => currency != 'USD')) {
      try {
        final dateKey = DateTime.utc(date.year, date.month, date.day)
            .toIso8601String()
            .substring(0, 10);
        final rate = cacheOnly
            ? (await SqliteSettings.getInstance()).getDouble(
                'historicalUsdRate_${currency}_$dateKey',
              )
            : await (rateLoader ?? historicalTradeUsdRate)(currency, date);
        if (rate == null) continue;
        if (!rate.isFinite || rate <= 0) {
          throw StateError('Invalid historical USD/$currency rate');
        }
        rates[date]![currency] = rate;
      } catch (error, stack) {
        talker.handle(error, stack, 'Failed to load portfolio exchange rate');
      }
    }
  }
  return PortfolioHistory(trades: trades, candles: candles, rates: rates);
}
