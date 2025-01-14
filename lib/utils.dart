import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:market_monk/symbol.dart';

Future<List<Symbol>> getSymbols() async {
  final String response =
      await rootBundle.loadString('assets/nasdaq-full-tickers.json');
  final List<dynamic> jsonData = json.decode(response);
  return jsonData.map((d) => Symbol.fromJson(d)).toList();
}
