import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/symbol.dart';
import 'package:yahoo_finance_data_reader/yahoo_finance_data_reader.dart';

Future<List<Symbol>> getSymbols() async {
  final List<dynamic> nasdaq = json
      .decode(await rootBundle.loadString('assets/nasdaq-full-tickers.json'));
  final List<dynamic> amex =
      json.decode(await rootBundle.loadString('assets/amex-full-tickers.json'));
  final List<dynamic> nyse =
      json.decode(await rootBundle.loadString('assets/nyse-full-tickers.json'));
  return nasdaq.map((d) => Symbol.fromJson(d)).toList() +
      amex.map((d) => Symbol.fromJson(d)).toList() +
      nyse.map((d) => Symbol.fromJson(d)).toList();
}

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
