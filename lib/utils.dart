import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/main.dart';
import 'package:yahoo_finance_data_reader/yahoo_finance_data_reader.dart';

var currency = NumberFormat.simpleCurrency();

/// USD-based rates for every supported currency (key=ISO code, value=units per 1 USD).
/// Populated by SettingsState on startup and currency change.
Map<String, double> allRatesFromUsd = {'USD': 1.0};

/// The current USD → displayCurrency conversion factor.
double get exchangeRate =>
    allRatesFromUsd[currency.currencyName ?? 'USD'] ?? 1.0;

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

/// Ensures the native currency and its exchange rate are cached for [symbol].
/// Returns immediately if already cached. Safe to call concurrently.
Future<void> fetchSymbolCurrencyAndRate(String symbol) =>
    _fetchSymbolCurrencyAndRate(symbol);

/// Formats [v] (assumed to be in USD) in the user's display currency.
String fmtCurrency(double v) => currency.format(v * exchangeRate);

/// Formats [v] which is denominated in [nativeCurrency], converting it to the
/// user's chosen display currency via the cached cross-rates.
///
/// Example: fmtNativeCurrency(1370.0, 'INR') with display=USD and
/// allRatesFromUsd['INR']=84 → formats 1370/84 ≈ $16.31.
String fmtNativeCurrency(double v, String nativeCurrency) {
  final nativeRate = allRatesFromUsd[nativeCurrency] ?? 1.0;
  return fmtCurrency(v / nativeRate);
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      action: action ?? defaultAction,
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

  Position({
    required this.symbol,
    required this.name,
    required this.nativeCurrency,
    required this.netShares,
    required this.avgCost,
    required this.currentPrice,
    required this.firstBuyDate,
    required this.lastBuyDate,
  });

  /// Conversion factor from [nativeCurrency] to USD.
  /// All monetary getters below return values in USD so that
  /// [fmtCurrency] (which applies USD → displayCurrency) works correctly.
  double get _nativeToUsd => 1.0 / (allRatesFromUsd[nativeCurrency] ?? 1.0);

  /// Percentage gain/loss relative to average cost. Currency-agnostic.
  double get change => safePercentChange(avgCost, currentPrice);

  /// Current market value in USD.
  double get currentValue => netShares * currentPrice * _nativeToUsd;

  /// Total cost basis in USD.
  double get costBasis => netShares * avgCost * _nativeToUsd;

  /// Unrealised profit/loss in USD.
  double get unrealizedPL =>
      netShares * (currentPrice - avgCost) * _nativeToUsd;
}

/// Computes open positions from a list of trades and a symbol→latestPrice map.
/// Only returns positions with net shares > 0 (i.e. not fully closed).
List<Position> computePositions(
  List<Trade> trades,
  Map<String, double> latestPrices,
) {
  final Map<String, List<Trade>> bySymbol = {};
  for (final t in trades) {
    bySymbol.putIfAbsent(t.symbol, () => []).add(t);
  }

  final positions = <Position>[];
  for (final entry in bySymbol.entries) {
    final symbol = entry.key;
    final symbolTrades = entry.value;

    final netShares = symbolTrades.fold(0.0, (sum, t) => sum + t.quantity);
    if (netShares <= 0) continue; // closed position

    final buyTrades = symbolTrades.where((t) => t.quantity > 0).toList();
    final totalBuyQty = buyTrades.fold(0.0, (sum, t) => sum + t.quantity);
    final weightedCost = buyTrades.fold(
      0.0,
      (sum, t) => sum + t.quantity * t.price,
    );
    final avgCost = totalBuyQty > 0 ? weightedCost / totalBuyQty : 0.0;
    final currentPrice = latestPrices[symbol] ?? avgCost;

    final name = symbolTrades.first.name;
    final dates = buyTrades.map((t) => t.tradeDate);
    final firstBuyDate = buyTrades.isNotEmpty
        ? dates.reduce((a, b) => a.isBefore(b) ? a : b)
        : DateTime.now();
    final lastBuyDate = buyTrades.isNotEmpty
        ? dates.reduce((a, b) => a.isAfter(b) ? a : b)
        : DateTime.now();

    final centDiv = symbolCentDivisor(symbol);

    positions.add(
      Position(
        symbol: symbol,
        name: name,
        nativeCurrency: symbolCurrency(symbol),
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
  final d = database ?? db;

  final ph = List.filled(symbols.length, '?').join(', ');
  try {
    final rows = await d.customSelect(
      'SELECT c.symbol, c.close '
      'FROM candles c '
      'INNER JOIN ('
      '  SELECT symbol, MAX(date) AS md FROM candles '
      '  WHERE symbol IN ($ph) GROUP BY symbol'
      ') sub ON c.symbol = sub.symbol AND c.date = sub.md '
      'WHERE c.close > 0',
      variables: [for (final s in symbols) Variable(s)],
      readsFrom: {d.candles},
    ).get();

    return {
      for (final row in rows)
        row.readNullable<String>('symbol') ?? '':
            row.readNullable<double>('close') ?? 0.0,
    }..removeWhere((k, v) => k.isEmpty || v <= 0);
  } catch (_) {
    // Fall back to N individual limit-1 queries if the JOIN fails
    final prices = <String, double>{};
    for (final s in symbols) {
      final c = await (d.candles.select()
            ..where((r) => r.symbol.equals(s))
            ..orderBy([
              (r) => OrderingTerm(expression: r.date, mode: OrderingMode.desc),
            ])
            ..limit(1))
          .getSingleOrNull();
      if (c != null && c.close > 0) prices[s] = c.close;
    }
    return prices;
  }
}

Future<void> insertCandles(
  List<YahooFinanceCandleData> dataList,
  String symbol, {
  Database? database,
}) async {
  const int batchSize = 1000;
  final d = database ?? db;

  for (int i = 0; i < dataList.length; i += batchSize) {
    final batch = dataList.skip(i).take(batchSize).map((data) {
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

    await d.batch((batchBuilder) {
      batchBuilder.insertAllOnConflictUpdate(d.candles, batch);
    });

    debugPrint('Inserted ${i + batch.length}');
  }
}

Future<Candle?> findClosestDate(DateTime date, String symbol) {
  final dateOnly = DateTime(date.year, date.month, date.day);
  final timestamp = dateOnly.millisecondsSinceEpoch / 1000;

  return (db.candles.select()
        ..where((u) => u.symbol.equals(symbol))
        ..orderBy([
          (t) =>
              OrderingTerm.asc(CustomExpression("ABS(\"date\" - $timestamp)")),
        ])
        ..limit(1))
      .getSingleOrNull();
}

Future<Candle?> findClosestPrice(double price, String symbol) {
  return (db.candles.select()
        ..where((u) => u.symbol.equals(symbol))
        ..orderBy([
          (t) => OrderingTerm.asc(CustomExpression("ABS(close - $price)")),
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
DateTime? _syncGuardDate;
final Set<String> _syncedSymbols = {};

/// Removes [symbol] from the sync guard for all databases so the next
/// [syncCandles] call will actually re-check (used by pull-to-refresh).
void clearSyncCache(String symbol) =>
    _syncedSymbols.removeWhere((k) => k.endsWith(':$symbol'));

/// Removes all symbols from the sync guard (e.g. after a full manual refresh).
void clearAllSyncCache() => _syncedSymbols.clear();

/// Syncs candles for a symbol from Yahoo Finance. Does not touch any other
/// table — the position data is computed on demand from trades + candles.
///
/// Skips the network call if the symbol has already been synced today in this
/// session, or if the local DB already has today's data.
///
/// Pass [database] to write into a specific account's DB instead of the
/// global active-account [db].
Future<void> syncCandles(String symbol, {Database? database}) async {
  final d = database ?? db;

  // Roll the guard over on a new calendar day
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  if (_syncGuardDate != today) {
    _syncedSymbols.clear();
    _syncGuardDate = today;
  }

  // Guard key includes the DB identity so different accounts sync independently.
  final guardKey = '${d.hashCode}:$symbol';
  if (_syncedSymbols.contains(guardKey)) return;
  _syncedSymbols.add(guardKey); // mark before async gap to prevent races

  // Lazily populate this symbol's native currency and its exchange rate.
  // Fires in the background so it doesn't block candle loading.
  unawaited(_fetchSymbolCurrencyAndRate(symbol));

  try {
    var latest = await (d.candles.select()
          ..where((tbl) => tbl.symbol.equals(symbol))
          ..orderBy([
            (u) => OrderingTerm(expression: u.date, mode: OrderingMode.desc),
          ])
          ..limit(1))
        .getSingleOrNull();

    if (latest == null) {
      final response = await const YahooFinanceDailyReader().getDailyDTOs(
        symbol,
      );
      await insertCandles(response.candlesData, symbol, database: d);
    } else if (today.isAfter(
      DateTime(latest.date.year, latest.date.month, latest.date.day),
    )) {
      final response = await const YahooFinanceDailyReader().getDailyDTOs(
        symbol,
        startDate: latest.date,
      );
      await insertCandles(response.candlesData, symbol, database: d);
    }
  } catch (_) {
    // Remove from guard on failure so next attempt can retry
    _syncedSymbols.remove(guardKey);
    rethrow;
  }
}

/// Fetches the native currency for [symbol] from the Yahoo Finance chart API,
/// then — only if that currency differs from USD — lazily fetches its USD-based
/// exchange rate from Frankfurter and stores it in [allRatesFromUsd].
///
/// Both results are cached in-memory so repeat calls are free.
Future<void> _fetchSymbolCurrencyAndRate(String symbol) async {
  if (_symbolCurrencies.containsKey(symbol)) return;

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

    final centInfo = _yahooCentCurrencies[rawCurr];
    final String normalizedCurr;
    final double centDivisor;
    if (centInfo != null) {
      normalizedCurr = centInfo.$1;
      centDivisor = centInfo.$2;
    } else {
      normalizedCurr = rawCurr;
      centDivisor = 1.0;
    }

    _symbolCurrencies[symbol] = normalizedCurr;
    _symbolCentDivisors[symbol] = centDivisor;

    if (!allRatesFromUsd.containsKey(normalizedCurr) &&
        normalizedCurr != 'USD') {
      await _fetchAndCacheRate(normalizedCurr);
    }
  } catch (_) {
    // Silently ignore — positions fall back to treating native as USD.
  }
}

/// Fetches the USD → [currencyCode] rate from Frankfurter and stores it in
/// [allRatesFromUsd]. Called lazily, only for currencies we haven't seen yet.
Future<void> _fetchAndCacheRate(String currencyCode) async {
  try {
    final uri = Uri.parse(
      'https://api.frankfurter.app/latest?from=USD&to=$currencyCode',
    );
    final response = await http.get(uri);
    if (response.statusCode != 200) return;

    final data = json.decode(response.body) as Map<String, dynamic>;
    final rate = ((data['rates'] as Map<String, dynamic>)[currencyCode] as num?)
        ?.toDouble();
    if (rate != null) allRatesFromUsd[currencyCode] = rate;
  } catch (_) {
    // Silently ignore — the position falls back to treating native as USD.
  }
}

class YahooFinanceApi {
  static const String _baseUrl =
      'https://query1.finance.yahoo.com/v1/finance/search';
  Timer? _debounceTimer;

  Future<List<StockResult>> searchTickers(String query) async {
    if (query.isEmpty) return [];

    return await _debounce(() async {
      final response = await http.get(
        Uri.parse('$_baseUrl?q=${Uri.encodeComponent(query)}'),
      );

      if (response.statusCode != 200) return [];

      final Map<String, dynamic> data = json.decode(response.body);
      final List<dynamic> quotes = data['quotes'] ?? [];

      // Include EQUITYs, ETFs, and ETNs — all have tradeable candle data.
      const tradeable = {'EQUITY', 'ETF', 'ETN'};
      return quotes
          .where((quote) => tradeable.contains(quote['quoteType']))
          .map((quote) => StockResult.fromJson(quote))
          .toList();
    });
  }

  Future<T> _debounce<T>(Future<T> Function() action) {
    final completer = Completer<T>();

    if (_debounceTimer?.isActive ?? false) {
      _debounceTimer!.cancel();
    }

    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      try {
        final result = await action();
        completer.complete(result);
      } catch (e) {
        completer.completeError(e);
      }
    });

    return completer.future;
  }

  void dispose() {
    _debounceTimer?.cancel();
  }
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
