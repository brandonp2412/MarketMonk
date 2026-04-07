import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/main.dart';
import 'package:yahoo_finance_data_reader/yahoo_finance_data_reader.dart';

final currency = NumberFormat.simpleCurrency();

void selectAll(TextEditingController controller) => controller.selection =
    TextSelection(baseOffset: 0, extentOffset: controller.text.length);

void toast(BuildContext context, String message, [SnackBarAction? action]) {
  final defaultAction = SnackBarAction(label: 'OK', onPressed: () {});

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      action: action ?? defaultAction,
    ),
  );
}

/// A computed portfolio position derived from trades + candles.
class Position {
  final String symbol;
  final String name;
  final double netShares; // SUM(quantity) across all trades
  final double avgCost; // weighted avg buy price
  final double currentPrice; // latest candle close (or avgCost if no candles)
  final DateTime firstBuyDate;

  Position({
    required this.symbol,
    required this.name,
    required this.netShares,
    required this.avgCost,
    required this.currentPrice,
    required this.firstBuyDate,
  });

  double get change => safePercentChange(avgCost, currentPrice);
  double get currentValue => netShares * currentPrice;
  double get costBasis => netShares * avgCost;
  double get unrealizedPL => netShares * (currentPrice - avgCost);
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
    final weightedCost =
        buyTrades.fold(0.0, (sum, t) => sum + t.quantity * t.price);
    final avgCost = totalBuyQty > 0 ? weightedCost / totalBuyQty : 0.0;
    final currentPrice = latestPrices[symbol] ?? avgCost;

    final name = symbolTrades.first.name;
    final firstBuyDate = buyTrades.isNotEmpty
        ? buyTrades
            .map((t) => t.tradeDate)
            .reduce((a, b) => a.isBefore(b) ? a : b)
        : DateTime.now();

    positions.add(
      Position(
        symbol: symbol,
        name: name,
        netShares: netShares,
        avgCost: avgCost,
        currentPrice: currentPrice,
        firstBuyDate: firstBuyDate,
      ),
    );
  }

  return positions;
}

/// Returns the latest candle close price per symbol.
/// Uses an INNER JOIN with a GROUP BY subquery so the DB returns exactly
/// one row per symbol instead of all historical candles.
Future<Map<String, double>> fetchLatestPrices(List<String> symbols) async {
  if (symbols.isEmpty) return {};

  final ph = List.filled(symbols.length, '?').join(', ');
  try {
    final rows = await db.customSelect(
      'SELECT c.symbol, c.close '
      'FROM candles c '
      'INNER JOIN ('
      '  SELECT symbol, MAX(date) AS md FROM candles '
      '  WHERE symbol IN ($ph) GROUP BY symbol'
      ') sub ON c.symbol = sub.symbol AND c.date = sub.md '
      'WHERE c.close > 0',
      variables: [for (final s in symbols) Variable(s)],
      readsFrom: {db.candles},
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
      final c = await (db.candles.select()
            ..where((r) => r.symbol.equals(s))
            ..orderBy(
              [
                (r) =>
                    OrderingTerm(expression: r.date, mode: OrderingMode.desc),
              ],
            )
            ..limit(1))
          .getSingleOrNull();
      if (c != null && c.close > 0) prices[s] = c.close;
    }
    return prices;
  }
}

Future<void> insertCandles(
  List<YahooFinanceCandleData> dataList,
  String symbol,
) async {
  const int batchSize = 1000;

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

    await db.batch((batchBuilder) {
      batchBuilder.insertAllOnConflictUpdate(
        db.candles,
        batch,
      );
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
          (t) => OrderingTerm.asc(
                CustomExpression(
                  "ABS(\"date\" - $timestamp)",
                ),
              ),
        ])
        ..limit(1))
      .getSingleOrNull();
}

Future<Candle?> findClosestPrice(double price, String symbol) {
  return (db.candles.select()
        ..where((u) => u.symbol.equals(symbol))
        ..orderBy([
          (t) => OrderingTerm.asc(
                CustomExpression(
                  "ABS(close - $price)",
                ),
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
DateTime? _syncGuardDate;
final Set<String> _syncedSymbols = {};

/// Removes [symbol] from the sync guard so the next [syncCandles] call will
/// actually re-check (used by pull-to-refresh).
void clearSyncCache(String symbol) => _syncedSymbols.remove(symbol);

/// Removes all symbols from the sync guard (e.g. after a full manual refresh).
void clearAllSyncCache() => _syncedSymbols.clear();

/// Syncs candles for a symbol from Yahoo Finance. Does not touch any other
/// table — the position data is computed on demand from trades + candles.
///
/// Skips the network call if the symbol has already been synced today in this
/// session, or if the local DB already has today's data.
Future<void> syncCandles(String symbol) async {
  // Roll the guard over on a new calendar day
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  if (_syncGuardDate != today) {
    _syncedSymbols.clear();
    _syncGuardDate = today;
  }

  if (_syncedSymbols.contains(symbol)) return;
  _syncedSymbols.add(symbol); // mark before async gap to prevent races

  try {
    var latest = await (db.candles.select()
          ..where((tbl) => tbl.symbol.equals(symbol))
          ..orderBy(
            [(u) => OrderingTerm(expression: u.date, mode: OrderingMode.desc)],
          )
          ..limit(1))
        .getSingleOrNull();

    if (latest == null) {
      final response = await const YahooFinanceDailyReader().getDailyDTOs(
        symbol,
      );
      await insertCandles(response.candlesData, symbol);
    } else if (today.isAfter(
      DateTime(latest.date.year, latest.date.month, latest.date.day),
    )) {
      final response = await const YahooFinanceDailyReader().getDailyDTOs(
        symbol,
        startDate: latest.date,
      );
      await insertCandles(response.candlesData, symbol);
    }
  } catch (_) {
    // Remove from guard on failure so next attempt can retry
    _syncedSymbols.remove(symbol);
    rethrow;
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

      return quotes
          .where((quote) => quote['quoteType'] == 'EQUITY')
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
