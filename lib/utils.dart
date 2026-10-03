import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:market_monk/background_network_coordinator.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/logging.dart';
import 'package:market_monk/market_data_store.dart';
import 'package:market_monk/sqlite_settings.dart';
import 'package:market_monk/unified_database.dart';
import 'package:yahoo_finance_data_reader/yahoo_finance_data_reader.dart';

var currency = NumberFormat.simpleCurrency();

/// USD-based rates for every supported currency (key=ISO code, value=units per 1 USD).
/// Populated by SettingsState on startup and currency change.
Map<String, double> allRatesFromUsd = {'USD': 1.0};

/// Returns the USD-based exchange rate for [currencyCode].
///
/// A missing rate is an unavailable valuation, never evidence of a 1:1 USD
/// rate. Failing closed prevents foreign holdings from being multiplied by an
/// unrelated display-currency rate.
double requireUsdRate(String currencyCode) {
  final rate = allRatesFromUsd[currencyCode];
  if (rate == null || rate <= 0 || !rate.isFinite) {
    throw StateError('Exchange rate unavailable for $currencyCode');
  }
  return rate;
}

/// The current USD → displayCurrency conversion factor.
double get exchangeRate => requireUsdRate(currency.currencyName ?? 'USD');

/// Yahoo Finance uses cent-based currency codes for some exchanges.
/// Maps cent code → (parent ISO code, divisor from cents to base units).
const _yahooCentCurrencies = <String, (String, double)>{
  'ZAc': ('ZAR', 100.0),
  'GBp': ('GBP', 100.0),
};

/// In-memory cache: symbol → native ISO currency code (e.g. "INR" for .NS stocks).
final Map<String, String> _symbolCurrencies = {};

/// In-memory cache: symbol → cent divisor (100.0 for ZAc/GBp, else 1.0).
final Map<String, double> _symbolCentDivisors = {};

/// Returns the cached native currency for [symbol], defaulting to 'USD'.
String symbolCurrency(String symbol) => _symbolCurrencies[symbol] ?? 'USD';

/// Returns the cent divisor for [symbol] (100.0 for ZAc/GBp stocks, else 1.0).
double symbolCentDivisor(String symbol) => _symbolCentDivisors[symbol] ?? 1.0;

void runDetachedTask<T>(Future<T> future, String label) {
  unawaited(
    future.then<void>((_) {}).catchError((Object error, StackTrace stackTrace) {
      talker.handle(error, stackTrace, label);
    }),
  );
}

/// Caches [rawCurrency] (as reported by Yahoo, e.g. 'GBp') for [symbol],
/// normalizing cent codes to their parent ISO currency (GBp → GBP ÷ 100).
/// Returns the normalized ISO code.
String cacheSymbolMeta(String symbol, String rawCurrency) {
  final centInfo = _yahooCentCurrencies[rawCurrency];
  _symbolCurrencies[symbol] = centInfo?.$1 ?? rawCurrency;
  _symbolCentDivisors[symbol] = centInfo?.$2 ?? 1.0;
  return centInfo?.$1 ?? rawCurrency;
}

/// Uses IBKR's own base-currency conversion when the snapshot exposes the same
/// net-liquidation value in both base currency and USD.
void cacheIbkrAccountExchangeRate(IbkrPortfolioSnapshot snapshot) {
  final base = snapshot.netLiquidation;
  final usd = snapshot.netLiquidationUsd;
  if (base == null ||
      usd == null ||
      base.currency.isEmpty ||
      base.currency == 'USD' ||
      usd.value == 0) {
    return;
  }
  allRatesFromUsd[base.currency] = base.value / usd.value;
}

/// Label for the raw unit that [symbol]'s prices are quoted in — the cent
/// code (e.g. "GBp") for cent-quoted stocks, else the currency symbol.
String symbolPriceUnit(String symbol) {
  final curr = symbolCurrency(symbol);
  if (symbolCentDivisor(symbol) == 1.0) return nativeCurrencySymbol(curr);
  return '${_yahooCentCurrencies.entries.firstWhere((entry) => entry.value.$1 == curr).key} ';
}

/// Ensures the native currency and its exchange rate are cached for [symbol].
/// Returns immediately if already cached. Remote metadata is best-effort so
/// local portfolio and chart UI remain responsive when Yahoo is unavailable.
Future<void> fetchSymbolCurrencyAndRate(String symbol) async {
  final canonicalSymbol = canonicalMarketSymbol(symbol);
  if (canonicalSymbol.isEmpty) return;
  try {
    await backgroundNetworkCoordinator.coalesce<void>(
      RequestCategory.yahooSymbolMetadata,
      canonicalSymbol,
      () => _fetchSymbolCurrencyAndRate(canonicalSymbol)
          .timeout(const Duration(seconds: 2)),
    );
  } on TimeoutException {
    talker.warning(
      'Symbol currency metadata timed out; using cached/default currency',
    );
  } catch (error, stackTrace) {
    talker.handle(
      error,
      stackTrace,
      'Failed to resolve symbol currency metadata',
    );
  }
}

/// Formats [v] (assumed to be in USD) in the user's display currency.
String fmtCurrency(double usdValue) => currency.format(usdValue * exchangeRate);

/// Formats [v] which is denominated in [nativeCurrency], converting it to the
/// user's chosen display currency via the cached cross-rates.
///
/// Example: fmtNativeCurrency(1370.0, 'INR') with display=USD and
/// allRatesFromUsd['INR']=84 → formats 1370/84 ≈ $16.31.
String fmtNativeCurrency(double nativeValue, String nativeCurrency) {
  final nativeRate = requireUsdRate(nativeCurrency);
  return fmtCurrency(nativeValue / nativeRate);
}

/// Compact display-currency label for chart axes (e.g. $1.2K).
String fmtCompactCurrency(double usdValue) =>
    NumberFormat.compactCurrency(symbol: currency.currencySymbol)
        .format(usdValue * exchangeRate);

/// Compact axis label for [v] denominated in [nativeCurrency].
String fmtCompactNativeCurrency(double nativeValue, String nativeCurrency) {
  final nativeRate = requireUsdRate(nativeCurrency);
  return fmtCompactCurrency(nativeValue / nativeRate);
}

/// Formats percentage axis values without letting large labels dominate the
/// chart. Values at 1,000% and above are abbreviated (for example +35K%).
String fmtChartAxisPercent(double value) {
  final absolute = value.abs();
  final magnitude = absolute >= 1000
      ? NumberFormat.compact().format(absolute)
      : NumberFormat('#,##0.#').format(absolute);
  final sign = value > 0
      ? '+'
      : value < 0
          ? '-'
          : '';
  return '$sign$magnitude%';
}

/// Returns the [NumberFormat.currencySymbol] for [nativeCurrency].
String nativeCurrencySymbol(String nativeCurrency) =>
    NumberFormat.simpleCurrency(name: nativeCurrency).currencySymbol;

void selectAll(TextEditingController controller) => controller.selection =
    TextSelection(baseOffset: 0, extentOffset: controller.text.length);

void toast(BuildContext context, String message, [SnackBarAction? action]) {
  final defaultAction = SnackBarAction(label: 'OK', onPressed: () {});

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      action: action ?? defaultAction,
      persist: false,
    ),
  );
}

/// A computed portfolio position derived from trades + candles.
class Position {
  final String symbol;
  final String name;

  /// ISO 4217 currency that [avgCost] and [currentPrice] are denominated in.
  final String nativeCurrency;

  final double netShares; // SUM(quantity) across all trades

  /// Weighted average buy price in [nativeCurrency].
  final double avgCost;

  /// Latest candle close price in [nativeCurrency].
  final double currentPrice;

  final DateTime firstBuyDate;
  final DateTime lastBuyDate;
  final double? brokerMarketValue;
  final double? brokerUnrealizedPL;
  final double? brokerRealizedPL;

  Position({
    required this.symbol,
    required this.name,
    required this.nativeCurrency,
    required this.netShares,
    required this.avgCost,
    required this.currentPrice,
    required this.firstBuyDate,
    required this.lastBuyDate,
    this.brokerMarketValue,
    this.brokerUnrealizedPL,
    this.brokerRealizedPL,
  });

  /// Conversion factor from [nativeCurrency] to USD.
  /// All monetary getters below return values in USD so that
  /// [fmtCurrency] (which applies USD → displayCurrency) works correctly.
  double get _nativeToUsd => 1.0 / requireUsdRate(nativeCurrency);

  /// Percentage gain/loss relative to average cost. Currency-agnostic.
  double get change => safePercentChange(avgCost, currentPrice);

  /// Current market value in USD.
  double get currentValue =>
      (brokerMarketValue ?? netShares * currentPrice) * _nativeToUsd;

  /// Total cost basis in USD.
  double get costBasis => netShares * avgCost * _nativeToUsd;

  /// Unrealised profit/loss in USD.
  double get unrealizedPL =>
      (brokerUnrealizedPL ?? netShares * (currentPrice - avgCost)) *
      _nativeToUsd;

  /// IBKR realized P/L for the current day, converted to USD when available.
  double? get realizedToday =>
      brokerRealizedPL == null ? null : brokerRealizedPL! * _nativeToUsd;
}

/// Converts current IBKR stock positions into MarketMonk positions while using
/// local trades only for display names and purchase dates.
Future<List<Position>> computeIbkrPositions(
  List<IbkrPosition> brokerPositions,
  List<Trade> localTrades,
) async {
  final stockPositions = brokerPositions
      .where(
        (position) => position.securityType == 'STK' && position.quantity > 0,
      )
      .toList();

  for (final position in stockPositions) {
    final nativeCurrency = cacheSymbolMeta(position.symbol, position.currency);
    if (nativeCurrency != 'USD' &&
        !allRatesFromUsd.containsKey(nativeCurrency)) {
      await _fetchAndCacheRate(nativeCurrency);
    }
    requireUsdRate(nativeCurrency);
  }

  return stockPositions.map((broker) {
    final trades =
        localTrades.where((trade) => trade.symbol == broker.symbol).toList();
    final buys = trades.where((trade) => trade.quantity > 0).toList();
    final now = DateTime.now();
    final firstBuyDate = buys.isEmpty
        ? now
        : buys.map((trade) => trade.tradeDate).reduce(
              (firstDate, secondDate) =>
                  firstDate.isBefore(secondDate) ? firstDate : secondDate,
            );
    final lastBuyDate = buys.isEmpty
        ? now
        : buys.map((trade) => trade.tradeDate).reduce(
              (firstDate, secondDate) =>
                  firstDate.isAfter(secondDate) ? firstDate : secondDate,
            );
    final currentPrice = broker.marketPrice ?? broker.averageCost ?? 0.0;
    final avgCost = broker.averageCost ?? currentPrice;
    return Position(
      symbol: broker.symbol,
      name: trades.isEmpty ? broker.symbol : trades.first.name,
      nativeCurrency: broker.currency,
      netShares: broker.quantity,
      avgCost: avgCost,
      currentPrice: currentPrice,
      firstBuyDate: firstBuyDate,
      lastBuyDate: lastBuyDate,
      brokerMarketValue: broker.marketValue,
      brokerUnrealizedPL: broker.unrealizedPnl,
      brokerRealizedPL: broker.realizedPnl,
    );
  }).toList();
}

double _averageCostForOpenPosition(List<Trade> trades) {
  final ordered = List<Trade>.from(trades)
    ..sort((firstTrade, secondTrade) {
      final byDate = firstTrade.tradeDate.compareTo(secondTrade.tradeDate);
      return byDate != 0 ? byDate : firstTrade.id.compareTo(secondTrade.id);
    });

  var openShares = 0.0;
  var averageCost = 0.0;
  for (final trade in ordered) {
    final quantity = trade.quantity;
    if (quantity > 0) {
      final previousLongShares = openShares > 0 ? openShares : 0.0;
      final shortShares = openShares < 0 ? -openShares : 0.0;
      final openingShares =
          quantity > shortShares ? quantity - shortShares : 0.0;
      openShares += quantity;
      if (openShares > 0) {
        averageCost = previousLongShares > 0
            ? (previousLongShares * averageCost + openingShares * trade.price) /
                openShares
            : trade.price;
      } else {
        averageCost = 0.0;
      }
    } else if (quantity < 0) {
      openShares += quantity;
      if (openShares <= 0) averageCost = 0.0;
    }
  }
  return averageCost;
}

/// Computes open positions from a list of trades and a symbol→latestPrice map.
/// Only returns positions with net shares > 0 (i.e. not fully closed).
List<Position> computePositions(
  List<Trade> trades,
  Map<String, double> latestPrices,
) {
  final Map<String, List<Trade>> bySymbol = {};
  for (final trade in trades) {
    bySymbol.putIfAbsent(trade.symbol, () => []).add(trade);
  }

  final positions = <Position>[];
  for (final entry in bySymbol.entries) {
    final symbol = entry.key;
    final symbolTrades = entry.value;

    final netShares = symbolTrades.fold(
      0.0,
      (sum, trade) => sum + trade.quantity,
    );
    if (netShares <= 0) continue;

    final buyTrades =
        symbolTrades.where((trade) => trade.quantity > 0).toList();
    final avgCost = _averageCostForOpenPosition(symbolTrades);
    final currentPrice = latestPrices[symbol] ?? avgCost;

    final name = symbolTrades.first.name;
    final dates = buyTrades.map((trade) => trade.tradeDate);
    final firstBuyDate = buyTrades.isNotEmpty
        ? dates.reduce(
            (firstDate, candidateDate) =>
                firstDate.isBefore(candidateDate) ? firstDate : candidateDate,
          )
        : DateTime.now();
    final lastBuyDate = buyTrades.isNotEmpty
        ? dates.reduce(
            (lastDate, candidateDate) =>
                lastDate.isAfter(candidateDate) ? lastDate : candidateDate,
          )
        : DateTime.now();

    final centDiv = symbolCentDivisor(symbol);

    positions.add(
      Position(
        symbol: symbol,
        name: name,
        nativeCurrency: _symbolCurrencies[symbol] ?? 'UNKNOWN',
        netShares: netShares,
        avgCost: avgCost / centDiv,
        currentPrice: currentPrice / centDiv,
        firstBuyDate: firstBuyDate,
        lastBuyDate: lastBuyDate,
      ),
    );
  }

  return positions;
}

/// Returns the latest candle close price per symbol.
/// Uses an INNER JOIN with a GROUP BY subquery so the DB returns exactly
/// one row per symbol instead of all historical candles.
Future<Map<String, double>> fetchLatestPrices(
  List<String> symbols, {
  UnifiedDatabase? database,
}) async {
  if (symbols.isEmpty) return {};
  final targetDatabase = database ?? marketDataDatabase;
  final canonicalSymbols = symbols
      .map(canonicalMarketSymbol)
      .where((symbol) => symbol.isNotEmpty)
      .toSet()
      .toList();
  if (canonicalSymbols.isEmpty) return {};

  await Future.wait(
    canonicalSymbols.map((symbol) async {
      await fetchSymbolCurrencyAndRate(symbol);
      final nativeCurrency = _symbolCurrencies[symbol];
      if (nativeCurrency == null || nativeCurrency.isEmpty) {
        throw StateError('Currency metadata unavailable for $symbol');
      }
      requireUsdRate(nativeCurrency);
    }),
  );

  final placeholders = List.filled(canonicalSymbols.length, '?').join(', ');
  try {
    final rows = await targetDatabase.customSelect(
      'SELECT candle.symbol, candle.close '
      'FROM candles candle '
      'INNER JOIN ('
      '  SELECT symbol, MAX(date) AS max_date FROM candles '
      '  WHERE symbol IN ($placeholders) GROUP BY symbol'
      ') latest ON candle.symbol = latest.symbol '
      'AND candle.date = latest.max_date '
      'WHERE candle.close > 0',
      variables: [
        for (final symbol in canonicalSymbols) Variable(symbol),
      ],
      readsFrom: {targetDatabase.unifiedCandles},
    ).get();

    return {
      for (final row in rows)
        row.readNullable<String>('symbol') ?? '':
            row.readNullable<double>('close') ?? 0.0,
    }..removeWhere((symbol, price) => symbol.isEmpty || price <= 0);
  } catch (error, stackTrace) {
    talker.handle(
      error,
      stackTrace,
      'Latest-price query failed; using fallback',
    );
    final prices = <String, double>{};
    for (final symbol in canonicalSymbols) {
      final candle = await (targetDatabase.unifiedCandles.select()
            ..where((row) => row.symbol.equals(symbol))
            ..orderBy([
              (row) => OrderingTerm(
                    expression: row.date,
                    mode: OrderingMode.desc,
                  ),
            ])
            ..limit(1))
          .getSingleOrNull();
      if (candle != null && candle.close > 0) {
        prices[symbol] = candle.close;
      }
    }
    return prices;
  }
}

typedef YahooCandleFetcher = Future<List<YahooFinanceCandleData>> Function(
  String symbol,
  DateTime startDate,
);

typedef IbkrCandleFetcher = Future<IbkrHistoricalSeries> Function(
  String symbol,
  int years,
);

const defaultMarketCandleLookback = Duration(days: 14);

String canonicalMarketSymbol(String symbol) => symbol.trim().toUpperCase();

DateTime canonicalMarketDay(DateTime date) =>
    DateTime(date.year, date.month, date.day);

DateTime _offsetMarketDay(DateTime day, int offsetDays) =>
    DateTime(day.year, day.month, day.day + offsetDays);

DateTime _boundedRequiredCandleStart(DateTime requested, DateTime latestDay) {
  final day = canonicalMarketDay(requested);
  return day.isAfter(latestDay) ? latestDay : day;
}

int _ibkrYearsForRange(DateTime from, DateTime through) {
  final days = through.difference(from).inDays.abs() + 1;
  final years = (days + 364) ~/ 365;
  if (years < 1) return 1;
  if (years > 10) return 10;
  return years;
}

Future<int> insertCandles(
  List<YahooFinanceCandleData> dataList,
  String symbol, {
  UnifiedDatabase? database,
}) async {
  const batchSize = 1000;
  final targetDatabase = database ?? marketDataDatabase;
  final canonicalSymbol = canonicalMarketSymbol(symbol);
  final byDay = <int, YahooFinanceCandleData>{};

  for (final data in dataList) {
    final day = canonicalMarketDay(data.date);
    final dayKey = day.year * 10000 + day.month * 100 + day.day;
    byDay[dayKey] = data.copyWith(date: day);
  }

  final normalized = byDay.values.toList()
    ..sort((a, b) => a.date.compareTo(b.date));

  for (var offset = 0; offset < normalized.length; offset += batchSize) {
    final candleBatch = normalized.skip(offset).take(batchSize).map((data) {
      return UnifiedCandlesCompanion.insert(
        date: data.date,
        symbol: canonicalSymbol,
        open: Value(data.open),
        high: Value(data.high),
        low: Value(data.low),
        close: Value(data.close),
        adjClose: Value(data.adjClose),
        volume: Value(data.volume),
      );
    }).toList();

    await targetDatabase.batch((batchBuilder) {
      batchBuilder.insertAll(
        targetDatabase.unifiedCandles,
        candleBatch,
        mode: InsertMode.insertOrReplace,
      );
    });
  }

  if (normalized.isNotEmpty) {
    talker.debug(
      'Stored ${normalized.length} Yahoo candles for $canonicalSymbol '
      '(${normalized.first.date.toIso8601String()}..'
      '${normalized.last.date.toIso8601String()})',
    );
  }
  return normalized.length;
}

Future<int> insertIbkrCandles(
  List<IbkrHistoricalCandle> dataList,
  String symbol, {
  UnifiedDatabase? database,
}) async {
  const batchSize = 1000;
  final targetDatabase = database ?? marketDataDatabase;
  final canonicalSymbol = canonicalMarketSymbol(symbol);
  final byDay = <int, IbkrHistoricalCandle>{};

  for (final data in dataList) {
    final day = canonicalMarketDay(data.date);
    final dayKey = day.year * 10000 + day.month * 100 + day.day;
    byDay[dayKey] = IbkrHistoricalCandle(
      date: day,
      open: data.open,
      high: data.high,
      low: data.low,
      close: data.close,
      volume: data.volume,
    );
  }

  final normalized = byDay.values.toList()
    ..sort((a, b) => a.date.compareTo(b.date));

  for (var offset = 0; offset < normalized.length; offset += batchSize) {
    final candleBatch = normalized.skip(offset).take(batchSize).map((data) {
      return UnifiedCandlesCompanion.insert(
        date: data.date,
        symbol: canonicalSymbol,
        open: Value(data.open),
        high: Value(data.high),
        low: Value(data.low),
        close: Value(data.close),
        adjClose: Value(data.close),
        volume: Value(data.volume),
      );
    }).toList();

    await targetDatabase.batch((batchBuilder) {
      batchBuilder.insertAll(
        targetDatabase.unifiedCandles,
        candleBatch,
        mode: InsertMode.insertOrReplace,
      );
    });
  }

  if (normalized.isNotEmpty) {
    talker.debug(
      'Stored ${normalized.length} IBKR candles for $canonicalSymbol '
      '(${normalized.first.date.toIso8601String()}..'
      '${normalized.last.date.toIso8601String()})',
    );
  }
  return normalized.length;
}

Future<UnifiedCandle?> findClosestDate(DateTime date, String symbol) {
  final canonicalSymbol = canonicalMarketSymbol(symbol);
  final dateOnly = canonicalMarketDay(date);
  final timestamp = dateOnly.millisecondsSinceEpoch / 1000;
  final targetDatabase = marketDataDatabase;

  return (targetDatabase.unifiedCandles.select()
        ..where((candle) => candle.symbol.equals(canonicalSymbol))
        ..orderBy([
          (candle) =>
              OrderingTerm.asc(CustomExpression('ABS("date" - $timestamp)')),
        ])
        ..limit(1))
      .getSingleOrNull();
}

Future<UnifiedCandle?> findClosestPrice(double price, String symbol) {
  final canonicalSymbol = canonicalMarketSymbol(symbol);
  final targetDatabase = marketDataDatabase;
  return (targetDatabase.unifiedCandles.select()
        ..where((candle) => candle.symbol.equals(canonicalSymbol))
        ..orderBy([
          (candle) => OrderingTerm.asc(CustomExpression('ABS(close - $price)')),
        ])
        ..limit(1))
      .getSingleOrNull();
}

double safePercentChange(double oldValue, double newValue) {
  if (oldValue == 0) return 0;
  return ((newValue - oldValue) / oldValue) * 100;
}

// ---------------------------------------------------------------------------
// Per-session sync guard — prevents redundant HTTP calls and DB queries when
// the same symbol is requested multiple times in one app session.
// Resets automatically when the calendar day changes.
// ---------------------------------------------------------------------------
/// Removes [symbol] from the global market-data sync guard so the next
/// [syncCandles] call will actually re-check (used by pull-to-refresh).
void clearSyncCache(String symbol) {
  final canonicalSymbol = canonicalMarketSymbol(symbol);
  backgroundNetworkCoordinator.clearFreshness(
    RequestCategory.marketCandles,
    where: (key) => key is (String, int, bool) && key.$1 == canonicalSymbol,
  );
}

/// Removes all symbols from the sync guard (e.g. after a full manual refresh).
void clearAllSyncCache() =>
    backgroundNetworkCoordinator.clearFreshness(RequestCategory.marketCandles);

DateTime _latestExpectedMarketDay(DateTime today) {
  var expectedDay = today;
  while (expectedDay.weekday == DateTime.saturday ||
      expectedDay.weekday == DateTime.sunday) {
    expectedDay = _offsetMarketDay(expectedDay, -1);
  }
  return expectedDay;
}

Future<bool> _syncIbkrCandlesIfAvailable(
  String symbol, {
  required UnifiedDatabase targetDatabase,
  required IbkrAccountConfig? ibkrConfig,
  required DateTime requestFrom,
  required DateTime expectedMarketDay,
  IbkrCandleFetcher? ibkrFetcher,
}) async {
  if (ibkrConfig?.isConfigured != true) return false;

  final config = ibkrConfig!;
  final years = _ibkrYearsForRange(requestFrom, expectedMarketDay);

  try {
    final history = ibkrFetcher != null
        ? await backgroundNetworkCoordinator.observe<IbkrHistoricalSeries>(
            RequestCategory.ibkrHistorical,
            () => ibkrFetcher(symbol, years),
          )
        : await IbkrApiClient(config)
            .fetchHistoricalCandles(symbol, years: years);
    if (history.candles.isEmpty) {
      throw StateError('IBKR returned no historical candles');
    }

    final normalizedCurrency = cacheSymbolMeta(symbol, history.currency);
    await upsertSymbolCurrencyMetadata(
      symbol,
      history.currency,
      database: targetDatabase,
    );
    if (normalizedCurrency != 'USD' &&
        !allRatesFromUsd.containsKey(normalizedCurrency)) {
      await _fetchAndCacheRate(normalizedCurrency);
    }

    final requestedCandles = history.candles.where((candle) {
      final day = canonicalMarketDay(candle.date);
      return !day.isBefore(requestFrom) && !day.isAfter(expectedMarketDay);
    }).toList();
    if (requestedCandles.isEmpty) {
      throw StateError('IBKR returned no candles in the requested range');
    }

    final stored = await insertIbkrCandles(
      requestedCandles,
      symbol,
      database: targetDatabase,
    );
    backgroundNetworkCoordinator.recordRows(
      RequestCategory.ibkrHistorical,
      stored,
    );
    talker.info(
      'Completed IBKR candle sync for $symbol: $stored rows from '
      '${requestFrom.toIso8601String()}',
    );
    return true;
  } catch (error) {
    talker.warning(
      'IBKR candle sync failed for $symbol; falling back to Yahoo: $error',
    );
    return false;
  }
}

/// Synchronizes reusable daily market data for [symbol].
///
/// [requiredFrom] describes the oldest day the caller actually needs. Coverage
/// is derived from stored symbol/date rows, so an empty cache does not imply an
/// all-history seed and widening a chart backfills only the missing range.
/// [syncNamespace] is retained for current call-site compatibility only; candle
/// identity and coverage are deliberately independent of account ownership.

Future<void> syncCandles(
  String symbol, {
  UnifiedDatabase? database,
  IbkrAccountConfig? ibkrConfig,
  String syncNamespace = 'Default',
  DateTime? requiredFrom,
  bool forceRefresh = false,
  YahooCandleFetcher? yahooFetcher,
  IbkrCandleFetcher? ibkrFetcher,
}) async {
  final targetDatabase = database ?? marketDataDatabase;
  final canonicalSymbol = canonicalMarketSymbol(symbol);
  final now = DateTime.now();
  final today = canonicalMarketDay(now);
  final expectedMarketDay = _latestExpectedMarketDay(today);
  final requiredStart = _boundedRequiredCandleStart(
    requiredFrom ??
        _offsetMarketDay(today, -defaultMarketCandleLookback.inDays),
    expectedMarketDay,
  );

  Future<({bool covered, DateTime? oldestDay, DateTime? latestDay})>
      readCoverage() async {
    final oldest = await (targetDatabase.unifiedCandles.select()
          ..where((row) => row.symbol.equals(canonicalSymbol))
          ..orderBy([
            (row) => OrderingTerm(expression: row.date, mode: OrderingMode.asc),
          ])
          ..limit(1))
        .getSingleOrNull();
    final latest = await (targetDatabase.unifiedCandles.select()
          ..where((row) => row.symbol.equals(canonicalSymbol))
          ..orderBy([
            (row) =>
                OrderingTerm(expression: row.date, mode: OrderingMode.desc),
          ])
          ..limit(1))
        .getSingleOrNull();

    final oldestDay = oldest == null ? null : canonicalMarketDay(oldest.date);
    final latestDay = latest == null ? null : canonicalMarketDay(latest.date);
    final covered = oldestDay != null &&
        !oldestDay.isAfter(requiredStart) &&
        latestDay != null &&
        !expectedMarketDay.isAfter(latestDay);
    return (covered: covered, oldestDay: oldestDay, latestDay: latestDay);
  }

  Future<({bool requested, bool progressed})> performSync() async {
    final coverage = await readCoverage();
    if (!forceRefresh && coverage.covered) {
      return (requested: false, progressed: false);
    }

    var requestFrom = coverage.latestDay == null
        ? requiredStart
        : _offsetMarketDay(coverage.latestDay!, -1);
    if (!coverage.covered &&
        (coverage.oldestDay == null ||
            coverage.oldestDay!.isAfter(requiredStart))) {
      requestFrom = requiredStart;
    }
    if (requestFrom.isBefore(requiredStart)) {
      requestFrom = requiredStart;
    }

    final ibkrHandled = await _syncIbkrCandlesIfAvailable(
      canonicalSymbol,
      targetDatabase: targetDatabase,
      ibkrConfig: ibkrConfig,
      requestFrom: requestFrom,
      expectedMarketDay: expectedMarketDay,
      ibkrFetcher: ibkrFetcher,
    );
    if (ibkrHandled) {
      final after = await readCoverage();
      final progressed = coverage.oldestDay != after.oldestDay ||
          coverage.latestDay != after.latestDay;
      return (requested: true, progressed: progressed);
    }

    runDetachedTask(
      fetchSymbolCurrencyAndRate(canonicalSymbol),
      'Failed to refresh candle currency metadata',
    );

    final fetch = yahooFetcher ??
        (String ticker, DateTime startDate) async {
          final response = await const YahooFinanceDailyReader().getDailyDTOs(
            ticker,
            startDate: startDate,
          );
          return response.candlesData;
        };
    final response = await backgroundNetworkCoordinator
        .observe<List<YahooFinanceCandleData>>(
      RequestCategory.yahooCandles,
      () => fetch(canonicalSymbol, requestFrom),
    );
    final requestedCandles = response.where((candle) {
      final day = canonicalMarketDay(candle.date);
      return !day.isBefore(requestFrom) && !day.isAfter(expectedMarketDay);
    }).toList();
    final stored = await insertCandles(
      requestedCandles,
      canonicalSymbol,
      database: targetDatabase,
    );
    backgroundNetworkCoordinator.recordRows(
      RequestCategory.yahooCandles,
      stored,
    );
    talker.info(
      'Completed Yahoo candle sync for $canonicalSymbol: $stored rows '
      'from ${requestFrom.toIso8601String()}',
    );
    final after = await readCoverage();
    final progressed = coverage.oldestDay != after.oldestDay ||
        coverage.latestDay != after.latestDay;
    return (requested: true, progressed: progressed);
  }

  try {
    while (true) {
      final syncResult = await backgroundNetworkCoordinator
          .coalesce<({bool requested, bool progressed})>(
        RequestCategory.marketCandles,
        canonicalSymbol,
        performSync,
      );

      if (forceRefresh) {
        if (syncResult.requested) return;
        continue;
      }

      if ((await readCoverage()).covered) return;
      if (!syncResult.requested) continue;
      if (!syncResult.progressed) return;
    }
  } catch (error, stackTrace) {
    talker.handle(error, stackTrace, 'Candle sync failed');
    rethrow;
  }
}

/// Fetches the native currency for [symbol] from the Yahoo Finance chart API,
/// then — only if that currency differs from USD — lazily fetches its USD-based
/// exchange rate from Frankfurter and stores it in [allRatesFromUsd].
///
/// Results are cached in-memory and in the unified symbol metadata table, so repeat calls are
/// free and cent-quoted stocks (GBp/ZAc) keep the right scale offline.
Future<void> _fetchSymbolCurrencyAndRate(String symbol) async {
  final canonicalSymbol = canonicalMarketSymbol(symbol);
  if (_symbolCurrencies.containsKey(canonicalSymbol)) return;

  final metadata = await marketDataDatabase.readSymbolMetadata(canonicalSymbol);
  final savedRaw = rawCurrencyFromMetadata(metadata);
  final prefs = await SqliteSettings.getInstance();
  if (savedRaw != null && savedRaw.isNotEmpty) {
    final normalized = cacheSymbolMeta(canonicalSymbol, savedRaw);
    if (normalized != 'USD' && !allRatesFromUsd.containsKey(normalized)) {
      final savedRate = prefs.getDouble('exchangeRate_$normalized');
      if (savedRate != null) {
        allRatesFromUsd[normalized] = savedRate;
        runDetachedTask(
          _fetchAndCacheRate(normalized),
          'Failed to refresh cached exchange rate',
        );
      } else {
        await _fetchAndCacheRate(normalized);
      }
    }
    return;
  }

  try {
    final uri = Uri.parse(
      'https://query1.finance.yahoo.com/v8/finance/chart/$canonicalSymbol'
      '?interval=1d&range=1d',
    );
    final response = await http.get(uri);
    if (response.statusCode != 200) return;

    final data = json.decode(response.body) as Map<String, dynamic>;
    final result =
        ((data['chart'] as Map<String, dynamic>?)?['result'] as List?)?.first
            as Map<String, dynamic>?;
    final rawCurr =
        (result?['meta'] as Map<String, dynamic>?)?['currency'] as String?;
    if (rawCurr == null || rawCurr.isEmpty) return;

    final normalizedCurr = cacheSymbolMeta(canonicalSymbol, rawCurr);
    await upsertSymbolCurrencyMetadata(canonicalSymbol, rawCurr);

    if (!allRatesFromUsd.containsKey(normalizedCurr) &&
        normalizedCurr != 'USD') {
      await _fetchAndCacheRate(normalizedCurr);
    }
  } catch (error, stackTrace) {
    talker.handle(
      error,
      stackTrace,
      'Failed to fetch symbol currency metadata',
    );
  }
}

/// Fetches the USD → [currencyCode] rate from Frankfurter and stores it in
/// [allRatesFromUsd]. Called lazily, only for currencies we haven't seen yet.
Future<void> _fetchAndCacheRate(String currencyCode) async {
  try {
    final rate = await backgroundNetworkCoordinator.coalesce<double?>(
      RequestCategory.fxRate,
      currencyCode,
      () async {
        final uri = Uri.parse(
          'https://api.frankfurter.app/latest?from=USD&to=$currencyCode',
        );
        final response = await http.get(uri);
        if (response.statusCode != 200) return null;

        final data = json.decode(response.body) as Map<String, dynamic>;
        return ((data['rates'] as Map<String, dynamic>)[currencyCode] as num?)
            ?.toDouble();
      },
    );
    if (rate != null) {
      allRatesFromUsd[currencyCode] = rate;
      final prefs = await SqliteSettings.getInstance();
      await prefs.setDouble('exchangeRate_$currencyCode', rate);
    }
  } catch (error, stackTrace) {
    // The position falls back to treating native as USD.
    talker.handle(error, stackTrace, 'Failed to fetch exchange rate');
  }
}

class YahooFinanceApi {
  static const String _baseUrl =
      'https://query1.finance.yahoo.com/v1/finance/search';

  final Future<http.Response> Function(Uri) _searchFetcher;
  Timer? _debounceTimer;
  Completer<List<StockResult>>? _pendingSearch;
  String? _pendingQuery;

  YahooFinanceApi({Future<http.Response> Function(Uri)? searchFetcher})
      : _searchFetcher = searchFetcher ?? http.get;

  Future<List<StockResult>> searchTickers(String query) {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      cancelPendingSearch();
      return Future.value([]);
    }

    final pending = _pendingSearch;
    if (_pendingQuery == trimmedQuery && pending != null) {
      return pending.future;
    }

    cancelPendingSearch();
    final completer = Completer<List<StockResult>>();
    _pendingSearch = completer;
    _pendingQuery = trimmedQuery;

    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      try {
        final result = await _performSearch(trimmedQuery);
        if (!completer.isCompleted) completer.complete(result);
      } catch (error, stackTrace) {
        talker.handle(error, stackTrace, 'Ticker search request failed');
        if (!completer.isCompleted) completer.complete([]);
      } finally {
        if (identical(_pendingSearch, completer)) {
          _pendingSearch = null;
          _pendingQuery = null;
          _debounceTimer = null;
        }
      }
    });

    return completer.future;
  }

  Future<List<StockResult>> _performSearch(String query) =>
      backgroundNetworkCoordinator.coalesce<List<StockResult>>(
        RequestCategory.yahooSearch,
        query,
        () async {
          try {
            final response = await _searchFetcher(
              Uri.parse('$_baseUrl?q=${Uri.encodeComponent(query)}'),
            ).timeout(const Duration(seconds: 5));

            if (response.statusCode != 200) {
              talker.warning(
                'Ticker search returned HTTP ${response.statusCode}',
              );
              return [];
            }

            final Map<String, dynamic> data = json.decode(response.body);
            final List<dynamic> quotes = data['quotes'] ?? [];

            // Include EQUITYs, ETFs, and ETNs — all have tradeable candle data.
            const tradeable = {'EQUITY', 'ETF', 'ETN'};
            return quotes
                .where((quote) => tradeable.contains(quote['quoteType']))
                .map((quote) => StockResult.fromJson(quote))
                .toList();
          } catch (error, stackTrace) {
            talker.handle(error, stackTrace, 'Ticker search request failed');
            return [];
          }
        },
      );

  void cancelPendingSearch() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    final pending = _pendingSearch;
    _pendingSearch = null;
    _pendingQuery = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete([]);
    }
  }

  void dispose() => cancelPendingSearch();
}

class StockResult {
  final String symbol;
  final String shortname;
  final String longname;
  final String exchange;

  StockResult({
    required this.symbol,
    required this.shortname,
    required this.longname,
    required this.exchange,
  });

  factory StockResult.fromJson(Map<String, dynamic> json) {
    return StockResult(
      symbol: json['symbol'] ?? '',
      shortname: json['shortname'] ?? '',
      longname: json['longname'] ?? '',
      exchange: json['exchange'] ?? '',
    );
  }

  @override
  String toString() =>
      '$symbol ($exchange) - ${longname.isNotEmpty ? longname : shortname}';
}
