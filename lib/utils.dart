import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:market_monk/symbol.dart';

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
