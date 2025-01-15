import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:market_monk/symbol.dart';

Future<List<Symbol>> getSymbols() async {
  final String response =
      await rootBundle.loadString('assets/nasdaq-full-tickers.json');
  final List<dynamic> jsonData = json.decode(response);
  return jsonData.map((d) => Symbol.fromJson(d)).toList();
}

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
