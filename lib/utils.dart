import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/main.dart';
import 'package:http/http.dart' as http;
import 'package:yahoo_finance_data_reader/yahoo_finance_data_reader.dart';

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

Future<void> syncCandles(String symbol) async {
  var latest = await (db.candles.select()
        ..where((tbl) => tbl.symbol.equals(symbol))
        ..orderBy(
          [
            (u) => OrderingTerm(
                  expression: u.date,
                  mode: OrderingMode.desc,
                ),
          ],
        )
        ..limit(1))
      .getSingleOrNull();

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
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

  final ticker = await (db.tickers.select()
        ..where((u) => u.symbol.equals(symbol))
        ..limit(1))
      .getSingleOrNull();
  if (ticker == null) return;

  latest = await (db.candles.select()
        ..where((tbl) => tbl.symbol.equals(symbol))
        ..orderBy(
          [
            (u) => OrderingTerm(
                  expression: u.date,
                  mode: OrderingMode.desc,
                ),
          ],
        )
        ..limit(1))
      .getSingleOrNull();
  if (latest == null) return;

  final newChange = safePercentChange(ticker.price, latest.close);
  await (db.tickers.update()..where((u) => u.symbol.equals(symbol))).write(
    TickersCompanion(
      change: Value(newChange),
    ),
  );
}

(double dollarReturn, double percentReturn) calculateTotalReturns(
  List<Ticker> tickers,
) {
  double totalCurrentValue = 0.0;
  double totalInitialValue = 0.0;

  for (final ticker in tickers) {
    if (ticker.price.isNaN || ticker.change.isNaN) continue;

    double currentPositionValue = ticker.amount * ticker.price;
    if (currentPositionValue.isNaN) continue;

    double initialPositionValue = ticker.change == -100
        ? currentPositionValue
        : currentPositionValue / (1 + (ticker.change / 100));

    if (initialPositionValue.isNaN) continue;

    totalCurrentValue += currentPositionValue;
    totalInitialValue += initialPositionValue;
  }

  if (totalInitialValue == 0) return (0.0, 0.0);

  double dollarReturn = totalCurrentValue - totalInitialValue;
  double percentReturn = ((totalCurrentValue / totalInitialValue) - 1) * 100;

  return (dollarReturn, percentReturn);
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
