import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:market_monk/background_network_coordinator.dart';
import 'package:market_monk/crypto_market_data.dart';
import 'package:market_monk/exchange_rate_service.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/ibkr_candle_failure_notice.dart';
import 'package:market_monk/logging.dart';
import 'package:market_monk/market_data_store.dart';
import 'package:market_monk/sqlite_settings.dart';
import 'package:yahoo_finance_data_reader/yahoo_finance_data_reader.dart';

var currency = NumberFormat.simpleCurrency();
bool maskCurrencyAmounts = false;

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

String normalizedQuoteCurrency(String rawCurrency) =>
    _yahooCentCurrencies[rawCurrency]?.$1 ?? rawCurrency;

double quoteUnitDivisor(String rawCurrency) =>
    _yahooCentCurrencies[rawCurrency]?.$2 ?? 1.0;

bool hasKnownQuoteCurrencyChange(String symbol) =>
    _symbolsWithCurrencyChanges.contains(canonicalMarketSymbol(symbol));

final Set<String> _symbolsWithCurrencyChanges = {};

/// In-memory cache: symbol → native ISO currency code (e.g. "INR" for .NS stocks).
final Map<String, String> _symbolCurrencies = {};

/// In-memory cache: symbol → cent divisor (100.0 for ZAc/GBp, else 1.0).
final Map<String, double> _symbolCentDivisors = {};
final Map<String, DateTime> _observedSymbolAt = {};

/// Returns the cached native currency for [symbol], defaulting to 'USD'.
String symbolCurrency(String symbol) => _symbolCurrencies[symbol] ?? 'USD';

/// Returns the cent divisor for [symbol] (100.0 for ZAc/GBp stocks, else 1.0).
double symbolCentDivisor(String symbol) => _symbolCentDivisors[symbol] ?? 1.0;

bool symbolHasQuoteCurrencyChange(String symbol) =>
    _symbolsWithCurrencyChanges.contains(canonicalMarketSymbol(symbol));

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
  final normalized = normalizedQuoteCurrency(rawCurrency);
  _symbolCurrencies[symbol] = normalized;
  _symbolCentDivisors[symbol] = quoteUnitDivisor(rawCurrency);
  _observedSymbolAt[symbol] = DateTime.now().toUtc();
  return normalized;
}

Future<double> historicalTradeUsdRate(String rawCurrency, DateTime date) async {
  final code = normalizedQuoteCurrency(rawCurrency).toUpperCase();
  if (code == 'USD') return 1.0;
  final day = DateTime.utc(date.year, date.month, date.day);
  final dateKey = day.toIso8601String().substring(0, 10);
  final settingKey = 'historicalUsdRate_${code}_$dateKey';
  final prefs = await SqliteSettings.getInstance();
  final cached = prefs.getDouble(settingKey);
  if (cached != null && cached.isFinite && cached > 0) return cached;
  return backgroundNetworkCoordinator.coalesce<double>(
    'fx.historical',
    settingKey,
    () async {
      final quote = await fetchHistoricalUsdRate(code, day);
      await prefs.setDouble(settingKey, quote.rate);
      return quote.rate;
    },
  );
}

Future<List<Trade>> enrichHistoricalTradeRates(List<Trade> trades) async {
  final verified = List<Trade>.of(trades);
  for (var offset = 0; offset < verified.length; offset += 4) {
    final end = (offset + 4).clamp(0, verified.length);
    final batch = await Future.wait([
      for (var index = offset; index < end; index++)
        () async {
          final trade = verified[index];
          final raw = trade.rawCurrency;
          if (raw == null || trade.usdRateAtTrade != null) return trade;
          try {
            return trade.withUsdRate(
              await historicalTradeUsdRate(raw, trade.tradeDate),
            );
          } catch (error) {
            talker.warning(
              'Historical FX unavailable for ${trade.symbol} '
              '${trade.tradeDate}: $error',
            );
            return trade;
          }
        }(),
    ]);
    for (var index = offset; index < end; index++) {
      verified[index] = batch[index - offset];
    }
  }
  return verified;
}

double tradeAmountUsd(Trade trade, double rawAmount) {
  final rawCurrency = trade.rawCurrency;
  if (rawCurrency == null &&
      _symbolsWithCurrencyChanges.contains(trade.symbol)) {
    throw StateError('${trade.symbol} has an unverified historical quote unit');
  }
  final currencyCode = rawCurrency == null
      ? symbolCurrency(trade.symbol)
      : normalizedQuoteCurrency(rawCurrency);
  final divisor = rawCurrency == null
      ? symbolCentDivisor(trade.symbol)
      : quoteUnitDivisor(rawCurrency);
  if (rawCurrency != null &&
      currencyCode != 'USD' &&
      trade.usdRateAtTrade == null) {
    throw StateError('Historical FX rate unavailable for ${trade.symbol}');
  }
  final rate = trade.usdRateAtTrade ?? requireUsdRate(currencyCode);
  if (!rate.isFinite || rate <= 0) {
    throw StateError('Invalid trade FX rate for ${trade.symbol}');
  }
  return rawAmount / divisor / rate;
}

double? verifiedTradeAmountUsd(Trade trade, double rawAmount) {
  if (rawAmount == 0) return 0;
  final raw = trade.rawCurrency;
  if (raw != null &&
      normalizedQuoteCurrency(raw) != 'USD' &&
      trade.usdRateAtTrade == null) {
    return null;
  }
  try {
    return tradeAmountUsd(trade, rawAmount);
  } on StateError {
    return null;
  }
}

String fmtTradeNative(Trade trade, double amount) {
  final raw = trade.rawCurrency;
  if (raw == null) {
    return '${amount.toStringAsFixed(2)} (unit unverified)';
  }
  final code = normalizedQuoteCurrency(raw);
  return NumberFormat.simpleCurrency(name: code)
      .format(amount / quoteUnitDivisor(raw));
}

double candleCentDivisor(StoredCandle candle) {
  final raw = candle.rawCurrency;
  if (raw != null) return quoteUnitDivisor(raw);
  if (_symbolsWithCurrencyChanges.contains(candle.symbol)) {
    throw StateError('${candle.symbol} has unverified historical candle units');
  }
  return symbolCentDivisor(candle.symbol);
}

/// Uses IBKR's own base-currency conversion when the snapshot exposes the same
/// net-liquidation value in both base currency and USD.
void cacheIbkrAccountExchangeRate(IbkrPortfolioSnapshot snapshot) {
  final base = snapshot.netLiquidation;
  final usd = snapshot.netLiquidationUsd;
  if (base == null || base.currency.isEmpty || base.currency == 'USD') {
    return;
  }
  final brokerRate = snapshot.usdExchangeRateInBase;
  if (brokerRate != null) {
    allRatesFromUsd[base.currency] = brokerRate;
    return;
  }
  if (usd == null || usd.value == 0) return;
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
/// Uses [rawCurrency] when a price response already supplies the quote unit.
/// Remote metadata is best-effort, and missing rates use the persisted cache.
Future<void> fetchSymbolCurrencyAndRate(
  String symbol, {
  String? rawCurrency,
}) async {
  final canonicalSymbol = canonicalMarketSymbol(symbol);
  if (canonicalSymbol.isEmpty) return;
  if (cryptoAssetForSymbol(canonicalSymbol) != null) {
    cacheSymbolMeta(canonicalSymbol, 'USD');
    final metadata = await marketDataDatabase.readSymbolMetadata(
      canonicalSymbol,
    );
    if (rawCurrencyFromMetadata(metadata) != 'USD') {
      await upsertSymbolCurrencyMetadata(
        canonicalSymbol,
        'USD',
        source: 'crypto',
      );
    }
    return;
  }
  final seenAt = _observedSymbolAt[canonicalSymbol];
  final cachedCurrency = _symbolCurrencies[canonicalSymbol];
  if (rawCurrency == null &&
      seenAt != null &&
      DateTime.now().toUtc().difference(seenAt) < const Duration(hours: 24) &&
      cachedCurrency != null &&
      allRatesFromUsd.containsKey(cachedCurrency)) {
    return;
  }
  if (rawCurrency != null && rawCurrency.isNotEmpty) {
    await upsertSymbolCurrencyMetadata(
      canonicalSymbol,
      rawCurrency,
      source: 'live-quote',
    );
    cacheSymbolMeta(canonicalSymbol, rawCurrency);
  }
  try {
    await backgroundNetworkCoordinator.coalesce<void>(
      'yahoo.symbolMetadata',
      canonicalSymbol,
      () => _fetchSymbolCurrencyAndRate(canonicalSymbol)
          .timeout(const Duration(seconds: 2)),
    );
    if ((await marketDataDatabase.readQuoteCurrencyChanges(canonicalSymbol))
        .isNotEmpty) {
      _symbolsWithCurrencyChanges.add(canonicalSymbol);
    }
  } on TimeoutException {
    talker.warning('Symbol currency metadata timed out for $canonicalSymbol');
  } catch (error, stackTrace) {
    talker.handle(error, stackTrace, 'Failed to resolve symbol currency');
  }
}

/// Formats [v] (assumed to be in USD) in the user's display currency.
String fmtCurrency(double usdValue) {
  if (maskCurrencyAmounts) return '••••';
  final rate = allRatesFromUsd[currency.currencyName ?? 'USD'];
  if (rate == null || !rate.isFinite || rate <= 0) return '—';
  return currency.format(usdValue * rate);
}

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
String fmtCompactCurrency(double usdValue) {
  if (maskCurrencyAmounts) return '••••';
  final rate = allRatesFromUsd[currency.currencyName ?? 'USD'];
  if (rate == null || !rate.isFinite || rate <= 0) return '—';
  return NumberFormat.compactCurrency(symbol: currency.currencySymbol)
      .format(usdValue * rate);
}

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
  final double? historicalCostBasisUsd;

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
    this.historicalCostBasisUsd,
  });

  /// Conversion factor from [nativeCurrency] to USD.
  /// All monetary getters below return values in USD so that
  /// [fmtCurrency] (which applies USD → displayCurrency) works correctly.
  double get _nativeToUsd => 1.0 / requireUsdRate(nativeCurrency);

  /// Percentage gain/loss relative to average cost. Currency-agnostic.
  double get change => historicalCostBasisUsd == null
      ? safePercentChange(avgCost, currentPrice)
      : safePercentChange(costBasis, currentValue);

  /// Current market value in USD.
  double get currentValue =>
      (brokerMarketValue ?? netShares * currentPrice) * _nativeToUsd;

  /// Total cost basis in USD.
  double get costBasis =>
      historicalCostBasisUsd ?? netShares * avgCost * _nativeToUsd;

  /// Unrealised profit/loss in USD.
  double get unrealizedPL =>
      historicalCostBasisUsd != null || brokerUnrealizedPL == null
          ? currentValue - costBasis
          : brokerUnrealizedPL! * _nativeToUsd;

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
    final historyVerified = trades.isNotEmpty &&
        trades.every(
          (trade) =>
              trade.rawCurrency != null &&
              (trade.usdRateAtTrade != null ||
                  normalizedQuoteCurrency(trade.rawCurrency!) == 'USD'),
        ) &&
        ((trades.fold<double>(0, (sum, trade) => sum + trade.quantity)) -
                    broker.quantity)
                .abs() <
            0.00001;
    final historicalCostBasisUsd = historyVerified
        ? _averageCostForOpenPosition(
              trades,
              priceForTrade: (trade) => tradeAmountUsd(trade, trade.price),
            ) *
            broker.quantity
        : null;
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
      historicalCostBasisUsd: historicalCostBasisUsd,
    );
  }).toList();
}

double _averageCostForOpenPosition(
  List<Trade> trades, {
  double Function(Trade)? priceForTrade,
}) {
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
            ? (previousLongShares * averageCost +
                    openingShares *
                        (priceForTrade?.call(trade) ?? trade.price)) /
                openShares
            : (priceForTrade?.call(trade) ?? trade.price);
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
  Map<String, double> latestPrices, {
  Map<String, String> nativeCurrencies = const {},
}) {
  final bySymbol = <String, List<Trade>>{};
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

    final nativeCurrency =
        nativeCurrencies[symbol] ?? _symbolCurrencies[symbol] ?? 'UNKNOWN';
    if (_symbolsWithCurrencyChanges.contains(symbol) &&
        symbolTrades.any((trade) => trade.rawCurrency == null)) {
      throw StateError(
        '$symbol changed quotation currency. Confirm the original currency '
        'and unit of legacy trades before calculating its cost basis.',
      );
    }
    final legacyUnits = symbolTrades.every(
      (trade) => trade.rawCurrency == null,
    );
    final avgCostUsd = legacyUnits
        ? null
        : _averageCostForOpenPosition(
            symbolTrades,
            priceForTrade: (trade) => tradeAmountUsd(trade, trade.price),
          );
    final buyTrades = symbolTrades.where((trade) => trade.quantity > 0);
    final dates = buyTrades.map((trade) => trade.tradeDate).toList();
    final firstBuyDate = dates.isNotEmpty
        ? dates.reduce((a, b) => a.isBefore(b) ? a : b)
        : DateTime.now();
    final lastBuyDate = dates.isNotEmpty
        ? dates.reduce((a, b) => a.isAfter(b) ? a : b)
        : DateTime.now();

    final nativeAvgCost = avgCostUsd == null
        ? _averageCostForOpenPosition(symbolTrades) / symbolCentDivisor(symbol)
        : avgCostUsd * requireUsdRate(nativeCurrency);
    final currentPrice = latestPrices.containsKey(symbol)
        ? latestPrices[symbol]! / symbolCentDivisor(symbol)
        : nativeAvgCost;
    positions.add(
      Position(
        symbol: symbol,
        name: symbolTrades.first.name,
        nativeCurrency: nativeCurrency,
        netShares: netShares,
        avgCost: nativeAvgCost,
        currentPrice: currentPrice,
        historicalCostBasisUsd:
            avgCostUsd == null ? null : netShares * avgCostUsd,
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
  final targetDatabase = database ?? marketDataDatabase;
  final canonicalSymbols = symbols
      .map(canonicalMarketSymbol)
      .where((symbol) => symbol.isNotEmpty)
      .toSet();
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

  final prices = <String, double>{};
  await Future.wait(
    canonicalSymbols.map((symbol) async {
      final latest = await (targetDatabase.candles.select()
            ..where(
              (row) =>
                  row.symbol.equals(symbol) & row.close.isBiggerThanValue(0),
            )
            ..orderBy([(row) => OrderingTerm.desc(row.date)])
            ..limit(1))
          .getSingleOrNull();
      if (latest == null) return;
      final storedRaw = latest.rawCurrency;
      final currentRaw = rawCurrencyFromMetadata(
        await targetDatabase.readSymbolMetadata(symbol),
      );
      if ((storedRaw == null && _symbolsWithCurrencyChanges.contains(symbol)) ||
          (storedRaw != null &&
              currentRaw != null &&
              storedRaw != currentRaw)) {
        throw StateError(
          'Cannot value $symbol until historical candle units are reconciled',
        );
      }
      prices[symbol] = latest.close;
    }),
  );
  return prices;
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
  Database? database,
  String? rawCurrency,
  bool preserveExisting = false,
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
      return CandlesCompanion.insert(
        date: data.date,
        symbol: canonicalSymbol,
        open: Value(data.open),
        high: Value(data.high),
        low: Value(data.low),
        close: Value(data.close),
        adjClose: Value(data.adjClose),
        volume: Value(data.volume),
        rawCurrency: Value(rawCurrency),
      );
    }).toList();

    await targetDatabase.batch((batchBuilder) {
      batchBuilder.insertAll(
        targetDatabase.candles,
        candleBatch,
        mode: preserveExisting
            ? InsertMode.insertOrIgnore
            : InsertMode.insertOrReplace,
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
  Database? database,
  String? rawCurrency,
  bool preserveExisting = false,
}) async {
  const batchSize = 1000;
  final targetDatabase = database ?? marketDataDatabase;
  final canonicalSymbol = canonicalMarketSymbol(symbol);
  final byDay = <int, IbkrHistoricalCandle>{};

  final existingRows = await (targetDatabase.candles.select()
        ..where((candle) => candle.symbol.equals(canonicalSymbol)))
      .get();
  for (final row in existingRows) {
    if (row.date.weekday != DateTime.saturday &&
        row.date.weekday != DateTime.sunday) {
      continue;
    }
    await (targetDatabase.delete(targetDatabase.candles)
          ..where(
            (candle) =>
                candle.symbol.equals(canonicalSymbol) &
                candle.date.equals(row.date),
          ))
        .go();
  }

  for (final data in dataList) {
    final day = canonicalMarketDay(data.date);
    if (day.weekday == DateTime.saturday || day.weekday == DateTime.sunday) {
      continue;
    }
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
      return CandlesCompanion.insert(
        date: data.date,
        symbol: canonicalSymbol,
        open: Value(data.open),
        high: Value(data.high),
        low: Value(data.low),
        close: Value(data.close),
        adjClose: Value(data.close),
        volume: Value(data.volume),
        rawCurrency: Value(rawCurrency),
      );
    }).toList();

    await targetDatabase.batch((batchBuilder) {
      batchBuilder.insertAll(
        targetDatabase.candles,
        candleBatch,
        mode: preserveExisting
            ? InsertMode.insertOrIgnore
            : InsertMode.insertOrReplace,
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

Future<StoredCandle?> findClosestDate(DateTime date, String symbol) {
  final canonicalSymbol = canonicalMarketSymbol(symbol);
  final dateOnly = canonicalMarketDay(date);
  final timestamp = dateOnly.millisecondsSinceEpoch / 1000;
  final targetDatabase = marketDataDatabase;

  return (targetDatabase.candles.select()
        ..where((candle) => candle.symbol.equals(canonicalSymbol))
        ..orderBy([
          (candle) =>
              OrderingTerm.asc(CustomExpression('ABS("date" - $timestamp)')),
        ])
        ..limit(1))
      .getSingleOrNull();
}

Future<StoredCandle?> findClosestPrice(double price, String symbol) {
  final canonicalSymbol = canonicalMarketSymbol(symbol);
  final targetDatabase = marketDataDatabase;
  return (targetDatabase.candles.select()
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
    'market.candles',
    where: (key) => key is (String, int, bool) && key.$1 == canonicalSymbol,
  );
}

/// Removes all symbols from the sync guard (e.g. after a full manual refresh).
void clearAllSyncCache() =>
    backgroundNetworkCoordinator.clearFreshness('market.candles');

DateTime _latestExpectedMarketDay(DateTime today) {
  var expectedDay = today;
  while (expectedDay.weekday == DateTime.saturday ||
      expectedDay.weekday == DateTime.sunday) {
    expectedDay = _offsetMarketDay(expectedDay, -1);
  }
  return expectedDay;
}

/// Provider currency metadata does not prove that pre-change bars were
/// retroactively redenominated. Only observations strictly after the most
/// recent detected transition can be labelled with its current quote unit.
Future<DateTime?> _firstVerifiedCurrentQuoteDay(
  Database database,
  String symbol,
) async {
  final changes = await database.readQuoteCurrencyChanges(symbol);
  if (changes.isEmpty) return null;
  _symbolsWithCurrencyChanges.add(symbol);
  final observed = changes.last.observedAt;
  return DateTime(observed.year, observed.month, observed.day + 1);
}

Future<bool> _syncIbkrCandlesIfAvailable(
  String symbol, {
  required Database targetDatabase,
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
        ? await ibkrFetcher(symbol, years)
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

    final verifiedFrom = await _firstVerifiedCurrentQuoteDay(
      targetDatabase,
      symbol,
    );
    var stored = 0;
    if (verifiedFrom != null) {
      // Do not overwrite known older units, or assign today's quote unit to
      // older bars that the broker may still express in their original unit.
      stored += await insertIbkrCandles(
        requestedCandles
            .where(
              (candle) =>
                  canonicalMarketDay(candle.date).isBefore(verifiedFrom),
            )
            .toList(),
        symbol,
        database: targetDatabase,
        preserveExisting: true,
      );
    }
    stored += await insertIbkrCandles(
      verifiedFrom == null
          ? requestedCandles
          : requestedCandles
              .where(
                (candle) =>
                    !canonicalMarketDay(candle.date).isBefore(verifiedFrom),
              )
              .toList(),
      symbol,
      database: targetDatabase,
      rawCurrency: history.currency,
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
    ibkrCandleFailureNotice.report(symbol, error);
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

final _cryptoSyncAt = <String, DateTime>{};
final _cryptoOhlcAttemptFrom = <String, DateTime>{};

Future<void> _syncCryptoCandles(
  Database database,
  CryptoAsset asset, {
  DateTime? requiredFrom,
  required bool forceRefresh,
  required CryptoMarketData marketData,
}) async {
  final now = DateTime.now().toUtc();
  final today = canonicalMarketDay(now);
  final requested = canonicalMarketDay(
    requiredFrom ?? now.subtract(defaultMarketCandleLookback),
  );
  final start = requested.isAfter(today) ? today : requested;
  final first = await (database.candles.select()
        ..where((row) => row.symbol.equals(asset.symbol))
        ..orderBy([
          (row) => OrderingTerm(expression: row.date, mode: OrderingMode.asc),
        ])
        ..limit(1))
      .getSingleOrNull();
  final last = await (database.candles.select()
        ..where((row) => row.symbol.equals(asset.symbol))
        ..orderBy([
          (row) => OrderingTerm(expression: row.date, mode: OrderingMode.desc),
        ])
        ..limit(1))
      .getSingleOrNull();
  final requestedFirst = await (database.candles.select()
        ..where(
          (row) =>
              row.symbol.equals(asset.symbol) &
              row.date.isBiggerOrEqualValue(start),
        )
        ..orderBy([(row) => OrderingTerm.asc(row.date)])
        ..limit(1))
      .getSingleOrNull();
  final fetchedAt = _cryptoSyncAt[asset.symbol];
  final lastOhlcFrom = _cryptoOhlcAttemptFrom[asset.symbol];
  final needsOhlcBackfill = requestedFirst != null &&
      requestedFirst.open == requestedFirst.high &&
      requestedFirst.high == requestedFirst.low &&
      requestedFirst.low == requestedFirst.close &&
      (lastOhlcFrom == null ||
          lastOhlcFrom.isAfter(start) ||
          fetchedAt == null ||
          now.difference(fetchedAt) >= const Duration(minutes: 5));
  if (!forceRefresh &&
      !needsOhlcBackfill &&
      first != null &&
      !canonicalMarketDay(first.date).isAfter(start) &&
      last != null &&
      !canonicalMarketDay(last.date).isBefore(today) &&
      fetchedAt != null &&
      now.difference(fetchedAt) < const Duration(minutes: 5)) {
    return;
  }
  final fetchFrom = forceRefresh ||
          needsOhlcBackfill ||
          first == null ||
          canonicalMarketDay(first.date).isAfter(start)
      ? start
      : canonicalMarketDay(last?.date ?? start)
          .subtract(const Duration(days: 2));
  final bars = await backgroundNetworkCoordinator.coalesce(
    'crypto.daily',
    (
      asset.symbol,
      fetchFrom,
    ),
    () => marketData.dailyHistory(asset, fetchFrom),
  );
  if (bars.isEmpty) throw StateError('No crypto prices for ${asset.symbol}');
  for (var offset = 0; offset < bars.length; offset += 1000) {
    final batch = bars.skip(offset).take(1000).map((bar) {
      return CandlesCompanion.insert(
        date: bar.date,
        symbol: asset.symbol,
        open: Value(bar.open),
        high: Value(bar.high),
        low: Value(bar.low),
        close: Value(bar.close),
        adjClose: Value(bar.close),
        volume: Value(bar.volume.round()),
        rawCurrency: const Value('USD'),
      );
    }).toList();
    await database.batch(
      (builder) => builder.insertAll(
        database.candles,
        batch,
        mode: InsertMode.insertOrReplace,
      ),
    );
  }
  _cryptoSyncAt[asset.symbol] = now;
  _cryptoOhlcAttemptFrom[asset.symbol] = fetchFrom;
}

Future<void> syncCandles(
  String symbol, {
  Database? database,
  IbkrAccountConfig? ibkrConfig,
  String syncNamespace = 'Default',
  DateTime? requiredFrom,
  bool forceRefresh = false,
  YahooCandleFetcher? yahooFetcher,
  IbkrCandleFetcher? ibkrFetcher,
  CryptoMarketData? cryptoMarketData,
}) async {
  final targetDatabase = database ?? marketDataDatabase;
  final canonicalSymbol = canonicalMarketSymbol(symbol);
  final cryptoAsset = cryptoAssetForSymbol(canonicalSymbol);
  if (cryptoAsset != null) {
    if (database == null) await fetchSymbolCurrencyAndRate(canonicalSymbol);
    cacheSymbolMeta(canonicalSymbol, 'USD');
    await _syncCryptoCandles(
      targetDatabase,
      cryptoAsset,
      requiredFrom: requiredFrom,
      forceRefresh: forceRefresh,
      marketData: cryptoMarketData ?? CryptoMarketData(),
    );
    return;
  }
  if (database == null && ibkrConfig?.isConfigured != true) {
    await fetchSymbolCurrencyAndRate(canonicalSymbol);
  }
  final now = DateTime.now();
  final today = canonicalMarketDay(now);
  final expectedMarketDay = _latestExpectedMarketDay(today);
  final requiredStart = _boundedRequiredCandleStart(
    requiredFrom ??
        _offsetMarketDay(today, -defaultMarketCandleLookback.inDays),
    expectedMarketDay,
  );

  Future<
      ({
        bool covered,
        DateTime? oldestDay,
        DateTime? latestDay,
        bool needsReconciliation,
      })> readCoverage() async {
    final oldest = await (targetDatabase.candles.select()
          ..where((row) => row.symbol.equals(canonicalSymbol))
          ..orderBy([
            (row) => OrderingTerm(expression: row.date, mode: OrderingMode.asc),
          ])
          ..limit(1))
        .getSingleOrNull();
    final latest = await (targetDatabase.candles.select()
          ..where((row) => row.symbol.equals(canonicalSymbol))
          ..orderBy([
            (row) =>
                OrderingTerm(expression: row.date, mode: OrderingMode.desc),
          ])
          ..limit(1))
        .getSingleOrNull();

    final oldestDay = oldest == null ? null : canonicalMarketDay(oldest.date);
    final latestDay = latest == null ? null : canonicalMarketDay(latest.date);
    final currentRaw = rawCurrencyFromMetadata(
      await targetDatabase.readSymbolMetadata(canonicalSymbol),
    );
    final transitioned = (await targetDatabase.readQuoteCurrencyChanges(
      canonicalSymbol,
    ))
        .isNotEmpty;
    final unresolved = transitioned &&
        (await (targetDatabase.candles.select()
                  ..where(
                    (row) =>
                        row.symbol.equals(canonicalSymbol) &
                        row.date.isBiggerOrEqualValue(requiredStart) &
                        row.rawCurrency.isNull(),
                  )
                  ..limit(1))
                .getSingleOrNull()) !=
            null;
    final staleLatest = currentRaw != null &&
        latest != null &&
        latest.rawCurrency != null &&
        latest.rawCurrency != currentRaw;
    final needsReconciliation = unresolved || staleLatest;
    final covered = oldestDay != null &&
        !oldestDay.isAfter(requiredStart) &&
        latestDay != null &&
        !expectedMarketDay.isAfter(latestDay) &&
        !needsReconciliation;
    return (
      covered: covered,
      oldestDay: oldestDay,
      latestDay: latestDay,
      needsReconciliation: needsReconciliation,
    );
  }

  Future<({bool requested, bool progressed, DateTime coverageFrom})>
      performSync() async {
    final coverage = await readCoverage();
    if (!forceRefresh && coverage.covered) {
      return (requested: false, progressed: false, coverageFrom: requiredStart);
    }

    var requestFrom = coverage.latestDay == null
        ? requiredStart
        : _offsetMarketDay(coverage.latestDay!, -1);
    if (!coverage.covered &&
        (coverage.oldestDay == null ||
            coverage.oldestDay!.isAfter(requiredStart))) {
      requestFrom = requiredStart;
    }
    if (coverage.needsReconciliation || requestFrom.isBefore(requiredStart)) {
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
          coverage.latestDay != after.latestDay ||
          coverage.needsReconciliation != after.needsReconciliation;
      return (
        requested: true,
        progressed: progressed,
        coverageFrom: requiredStart,
      );
    }

    await fetchSymbolCurrencyAndRate(canonicalSymbol);
    final seriesRawCurrency = rawCurrencyFromMetadata(
      await targetDatabase.readSymbolMetadata(canonicalSymbol),
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
    final verifiedFrom = await _firstVerifiedCurrentQuoteDay(
      targetDatabase,
      canonicalSymbol,
    );
    var stored = 0;
    if (verifiedFrom != null) {
      stored += await insertCandles(
        requestedCandles
            .where(
              (candle) =>
                  canonicalMarketDay(candle.date).isBefore(verifiedFrom),
            )
            .toList(),
        canonicalSymbol,
        database: targetDatabase,
        preserveExisting: true,
      );
    }
    stored += await insertCandles(
      verifiedFrom == null
          ? requestedCandles
          : requestedCandles
              .where(
                (candle) =>
                    !canonicalMarketDay(candle.date).isBefore(verifiedFrom),
              )
              .toList(),
      canonicalSymbol,
      database: targetDatabase,
      rawCurrency: seriesRawCurrency,
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
    return (
      requested: true,
      progressed: progressed,
      coverageFrom: requiredStart,
    );
  }

  try {
    while (true) {
      final syncResult = await backgroundNetworkCoordinator
          .coalesce<({bool requested, bool progressed, DateTime coverageFrom})>(
        RequestCategory.marketCandles,
        canonicalSymbol,
        performSync,
      );

      if (forceRefresh) {
        // A simultaneous shorter-range load may have won coalescing. Its
        // successful request cannot fulfill this wider manual prefetch.
        if (syncResult.coverageFrom.isAfter(requiredStart)) continue;
        if (syncResult.requested) {
          if ((await readCoverage()).covered || !syncResult.progressed) return;
        }
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
/// exchange rate and stores it in [allRatesFromUsd].
///
/// Results are cached in-memory and in the unified symbol metadata table, so repeat calls are
/// free and cent-quoted stocks (GBp/ZAc) keep the right scale offline.
Future<void> _fetchSymbolCurrencyAndRate(String symbol) async {
  final canonicalSymbol = canonicalMarketSymbol(symbol);
  final metadata = await marketDataDatabase.readSymbolMetadata(canonicalSymbol);
  final savedRaw = rawCurrencyFromMetadata(metadata);
  final prefs = await SqliteSettings.getInstance();
  if (savedRaw != null && savedRaw.isNotEmpty) {
    final normalized = cacheSymbolMeta(canonicalSymbol, savedRaw);
    if (normalized != 'USD' && !allRatesFromUsd.containsKey(normalized)) {
      final savedRate = readCachedUsdRate(normalized, prefs)?.rate;
      if (savedRate != null && savedRate.isFinite && savedRate > 0) {
        allRatesFromUsd[normalized] = savedRate;
      } else {
        await _fetchAndCacheRate(normalized);
      }
    }
    if (DateTime.now().toUtc().difference(metadata!.cachedAt.toUtc()) <
        const Duration(hours: 24)) {
      return;
    }
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
    final rawCurrency =
        (result?['meta'] as Map<String, dynamic>?)?['currency'] as String?;
    if (rawCurrency == null || rawCurrency.isEmpty) return;

    await upsertSymbolCurrencyMetadata(
      canonicalSymbol,
      rawCurrency,
      source: 'yahoo-chart',
    );
    final normalized = cacheSymbolMeta(canonicalSymbol, rawCurrency);
    if (normalized != 'USD' && !allRatesFromUsd.containsKey(normalized)) {
      await _fetchAndCacheRate(normalized);
    }
  } catch (error, stackTrace) {
    talker.handle(error, stackTrace, 'Failed to fetch symbol currency');
  }
}

Future<void> _fetchAndCacheRate(String currencyCode) async {
  try {
    final quote = await refreshUsdRate(currencyCode);
    allRatesFromUsd[currencyCode] = quote.rate;
  } catch (error, stackTrace) {
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
        'yahoo.search',
        query,
        () async {
          final crypto = searchCryptoAssets(query)
              .map(
                (asset) => StockResult(
                  symbol: asset.symbol,
                  shortname: asset.name,
                  longname: asset.name,
                  exchange: 'Crypto',
                ),
              )
              .toList();
          try {
            final response = await _searchFetcher(
              Uri.parse('$_baseUrl?q=${Uri.encodeComponent(query)}'),
            ).timeout(const Duration(seconds: 5));

            if (response.statusCode != 200) {
              talker.warning(
                'Ticker search returned HTTP ${response.statusCode}',
              );
              return crypto;
            }

            final Map<String, dynamic> data = json.decode(response.body);
            final List<dynamic> quotes = data['quotes'] ?? [];

            // Include EQUITYs, ETFs, and ETNs — all have tradeable candle data.
            const tradeable = {'EQUITY', 'ETF', 'ETN'};
            final stocks = quotes
                .where((quote) => tradeable.contains(quote['quoteType']))
                .map((quote) => StockResult.fromJson(quote))
                .where(
                  (stock) => !crypto.any((coin) => coin.symbol == stock.symbol),
                );
            return [...crypto, ...stocks];
          } catch (error, stackTrace) {
            talker.handle(error, stackTrace, 'Ticker search request failed');
            return crypto;
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
