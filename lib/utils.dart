import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:market_monk/background_network_coordinator.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/logging.dart';
import 'package:market_monk/sqlite_settings.dart';
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
  try {
    await backgroundNetworkCoordinator.coalesce<void>(
      'yahoo.symbolMetadata',
      symbol,
      () => _fetchSymbolCurrencyAndRate(symbol).timeout(
        const Duration(seconds: 2),
      ),
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
String fmtCompactNativeCurrency(
  double nativeValue,
  String nativeCurrency,
) {
  final nativeRate = requireUsdRate(nativeCurrency);
  return fmtCompactCurrency(nativeValue / nativeRate);
}

/// Formats percentage axis values without letting large labels dominate the
/// chart. Values at 1,000% and above are abbreviated (for example +35K%).
String fmtChartAxisPercent(double value) {
  final absolute = value.abs();
  final magnitude = absolute >= 1000
      ? NumberFormat.compact().format(absolute)
      : NumberFormat('#,##0.0').format(absolute);
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
    final nativeCurrency = cacheSymbolMeta(
      position.symbol,
      position.currency,
    );
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

    final netShares =
        symbolTrades.fold(0.0, (sum, trade) => sum + trade.quantity);
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
  Database? database,
}) async {
  if (symbols.isEmpty) return {};
  final targetDatabase = database ?? db;

  await Future.wait(
    symbols.map((symbol) async {
      await fetchSymbolCurrencyAndRate(symbol);
      final nativeCurrency = _symbolCurrencies[symbol];
      if (nativeCurrency == null || nativeCurrency.isEmpty) {
        throw StateError('Currency metadata unavailable for $symbol');
      }
      requireUsdRate(nativeCurrency);
    }),
  );

  final placeholders = List.filled(symbols.length, '?').join(', ');
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
      variables: [for (final symbol in symbols) Variable(symbol)],
      readsFrom: {targetDatabase.candles},
    ).get();

    return {
      for (final row in rows)
        row.readNullable<String>('symbol') ?? '':
            row.readNullable<double>('close') ?? 0.0,
    }..removeWhere(
        (symbol, price) => symbol.isEmpty || price <= 0,
      );
  } catch (error, stackTrace) {
    talker.handle(
      error,
      stackTrace,
      'Latest-price query failed; using fallback',
    );
    final prices = <String, double>{};
    for (final symbol in symbols) {
      final candle = await (targetDatabase.candles.select()
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

Future<void> insertCandles(
  List<YahooFinanceCandleData> dataList,
  String symbol, {
  Database? database,
}) async {
  const batchSize = 1000;
  final targetDatabase = database ?? db;

  for (var offset = 0; offset < dataList.length; offset += batchSize) {
    final candleBatch = dataList.skip(offset).take(batchSize).map((data) {
      return CandlesCompanion.insert(
        date: data.date,
        symbol: symbol,
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
        targetDatabase.candles,
        candleBatch,
        mode: InsertMode.insertOrReplace,
      );
    });

    final upsertedCount = offset + candleBatch.length;
    talker.debug('Upserted $upsertedCount Yahoo candle records');
  }
}

/// Stores daily IBKR bars in the same candle cache used by chart rendering.
Future<void> insertIbkrCandles(
  List<IbkrHistoricalCandle> dataList,
  String symbol, {
  Database? database,
}) async {
  const batchSize = 1000;
  final targetDatabase = database ?? db;

  for (var offset = 0; offset < dataList.length; offset += batchSize) {
    final candleBatch = dataList.skip(offset).take(batchSize).map((data) {
      return CandlesCompanion.insert(
        date: data.date,
        symbol: symbol,
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
        targetDatabase.candles,
        candleBatch,
        mode: InsertMode.insertOrReplace,
      );
    });

    final upsertedCount = offset + candleBatch.length;
    talker.debug('Upserted $upsertedCount IBKR candle records');
  }
}

Future<Candle?> findClosestDate(DateTime date, String symbol) {
  final dateOnly = DateTime(date.year, date.month, date.day);
  final timestamp = dateOnly.millisecondsSinceEpoch / 1000;

  return (db.candles.select()
        ..where((candle) => candle.symbol.equals(symbol))
        ..orderBy([
          (candle) => OrderingTerm.asc(
                CustomExpression('ABS("date" - $timestamp)'),
              ),
        ])
        ..limit(1))
      .getSingleOrNull();
}

Future<Candle?> findClosestPrice(double price, String symbol) {
  return (db.candles.select()
        ..where((candle) => candle.symbol.equals(symbol))
        ..orderBy([
          (candle) => OrderingTerm.asc(
                CustomExpression('ABS(close - $price)'),
              ),
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
/// Removes [symbol] from the sync guard for all databases so the next
/// [syncCandles] call will actually re-check (used by pull-to-refresh).
void clearSyncCache(String symbol) =>
    backgroundNetworkCoordinator.clearFreshness(
      'market.candles',
      where: (key) => key is String && key.endsWith(':$symbol'),
    );

/// Removes all symbols from the sync guard (e.g. after a full manual refresh).
void clearAllSyncCache() =>
    backgroundNetworkCoordinator.clearFreshness('market.candles');

/// Syncs daily candles for [symbol], preferring the configured IBKR service.
///
/// IBKR is used for current broker stock positions. If IBKR historical data is
/// unavailable, Yahoo remains the fallback source. The first successful IBKR
/// sync seeds up to ten years of bars; later daily refreshes request one year.
DateTime _latestExpectedMarketDay(DateTime today) {
  var expectedDay = today;
  while (expectedDay.weekday == DateTime.saturday ||
      expectedDay.weekday == DateTime.sunday) {
    expectedDay = expectedDay.subtract(const Duration(days: 1));
  }
  return expectedDay;
}

Future<bool> _syncIbkrCandlesIfAvailable(
  String symbol, {
  required Database targetDatabase,
  required IbkrAccountConfig? ibkrConfig,
  required String syncNamespace,
  required Candle? latest,
  required DateTime? latestDay,
  required DateTime expectedMarketDay,
}) async {
  if (ibkrConfig?.isConfigured != true) return false;

  final prefs = await SqliteSettings.getInstance();
  final config = ibkrConfig!;
  final baseUrl = config.baseUrl;
  final seedKey = 'ibkrHistorySeeded:$baseUrl:$syncNamespace:$symbol';
  final seeded = prefs.getBool(seedKey) ?? false;
  if (seeded && latestDay != null && !expectedMarketDay.isAfter(latestDay)) {
    return true;
  }

  try {
    final history = await IbkrApiClient(config).fetchHistoricalCandles(
      symbol,
      years: latest == null ? 10 : 1,
    );
    if (history.candles.isEmpty) {
      throw StateError('IBKR returned no historical candles');
    }

    final normalizedCurrency = cacheSymbolMeta(symbol, history.currency);
    await prefs.setString('symbolRawCurrency_$symbol', history.currency);
    if (normalizedCurrency != 'USD' &&
        !allRatesFromUsd.containsKey(normalizedCurrency)) {
      await _fetchAndCacheRate(normalizedCurrency);
    }
    await insertIbkrCandles(
      history.candles,
      symbol,
      database: targetDatabase,
    );
    await prefs.setBool(seedKey, true);
    talker.info('Completed IBKR candle sync');
    return true;
  } catch (error) {
    talker.warning(
      'IBKR candle sync failed for $symbol; falling back to Yahoo: $error',
    );
    return false;
  }
}

Future<void> syncCandles(
  String symbol, {
  Database? database,
  IbkrAccountConfig? ibkrConfig,
  String syncNamespace = 'Default',
}) async {
  final targetDatabase = database ?? db;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final expectedMarketDay = _latestExpectedMarketDay(today);
  final databaseKey = targetDatabase.hashCode;
  final guardKey = '$databaseKey:$symbol';

  try {
    return await backgroundNetworkCoordinator.runFresh(
      'market.candles',
      guardKey,
      today,
      () => targetDatabase.runWhileOpen(() async {
        final latest = await (targetDatabase.candles.select()
              ..where((row) => row.symbol.equals(symbol))
              ..orderBy([
                (row) => OrderingTerm(
                      expression: row.date,
                      mode: OrderingMode.desc,
                    ),
              ])
              ..limit(1))
            .getSingleOrNull();
        final latestDay = latest == null
            ? null
            : DateTime(latest.date.year, latest.date.month, latest.date.day);

        final ibkrHandled = await _syncIbkrCandlesIfAvailable(
          symbol,
          targetDatabase: targetDatabase,
          ibkrConfig: ibkrConfig,
          syncNamespace: syncNamespace,
          latest: latest,
          latestDay: latestDay,
          expectedMarketDay: expectedMarketDay,
        );
        if (ibkrHandled) return;

        unawaited(fetchSymbolCurrencyAndRate(symbol));

        if (latest == null) {
          final response = await const YahooFinanceDailyReader().getDailyDTOs(
            symbol,
          );
          await insertCandles(
            response.candlesData,
            symbol,
            database: targetDatabase,
          );
          talker.info('Completed initial Yahoo candle sync');
          return;
        }

        if (!expectedMarketDay.isAfter(latestDay!)) return;
        final response = await const YahooFinanceDailyReader().getDailyDTOs(
          symbol,
          startDate: latest.date,
        );
        await insertCandles(
          response.candlesData,
          symbol,
          database: targetDatabase,
        );
        talker.info('Completed incremental Yahoo candle sync');
      }),
    );
  } catch (error, stackTrace) {
    talker.handle(error, stackTrace, 'Candle sync failed');
    rethrow;
  }
}

/// Fetches the native currency for [symbol] from the Yahoo Finance chart API,
/// then — only if that currency differs from USD — lazily fetches its USD-based
/// exchange rate from Frankfurter and stores it in [allRatesFromUsd].
///
/// Results are cached in-memory and in SqliteSettings, so repeat calls are
/// free and cent-quoted stocks (GBp/ZAc) keep the right scale offline.
Future<void> _fetchSymbolCurrencyAndRate(String symbol) async {
  if (_symbolCurrencies.containsKey(symbol)) return;

  final prefs = await SqliteSettings.getInstance();
  final savedRaw = prefs.getString('symbolRawCurrency_$symbol');
  if (savedRaw != null) {
    final normalized = cacheSymbolMeta(symbol, savedRaw);
    if (normalized != 'USD' && !allRatesFromUsd.containsKey(normalized)) {
      final savedRate = prefs.getDouble('exchangeRate_$normalized');
      if (savedRate != null) {
        allRatesFromUsd[normalized] = savedRate;
        unawaited(_fetchAndCacheRate(normalized));
      } else {
        await _fetchAndCacheRate(normalized);
      }
    }
    return;
  }

  try {
    final uri = Uri.parse(
      'https://query1.finance.yahoo.com/v8/finance/chart/$symbol'
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

    final normalizedCurr = cacheSymbolMeta(symbol, rawCurr);
    await prefs.setString('symbolRawCurrency_$symbol', rawCurr);

    if (!allRatesFromUsd.containsKey(normalizedCurr) &&
        normalizedCurr != 'USD') {
      await _fetchAndCacheRate(normalizedCurr);
    }
  } catch (error, stackTrace) {
    // Positions fall back to treating native as USD.
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
      'fx.rate',
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

  YahooFinanceApi({Future<http.Response> Function(Uri)? searchFetcher})
      : _searchFetcher = searchFetcher ?? http.get;

  Future<List<StockResult>> searchTickers(String query) {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      cancelPendingSearch();
      return Future.value([]);
    }

    cancelPendingSearch();
    final completer = Completer<List<StockResult>>();
    _pendingSearch = completer;

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
          _debounceTimer = null;
        }
      }
    });

    return completer.future;
  }

  Future<List<StockResult>> _performSearch(String query) =>
      backgroundNetworkCoordinator.coalesce<List<StockResult>>(
        'yahoo.search',
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
