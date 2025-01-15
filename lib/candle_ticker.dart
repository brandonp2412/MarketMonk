import 'package:market_monk/database.dart';

class CandleTicker {
  final CandlesCompanion candle;
  final TickersCompanion? ticker;

  CandleTicker({this.ticker, required this.candle});
}
