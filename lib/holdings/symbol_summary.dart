import 'package:market_monk/database.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/market_data.dart';

/// A summary of a symbol: open position (if any) + full trade history.
class SymbolSummary {
  final String symbol;
  final String name;
  final Position? position; // null = fully closed position
  final List<Trade> trades;
  final bool brokerTradeHistoryAvailable;

  SymbolSummary({
    required this.symbol,
    required this.name,
    required this.position,
    required this.trades,
    this.brokerTradeHistoryAvailable = true,
  });

  /// Uses dated executions instead of the frequently zero broker position P/L.
  double? realizedTodayUsd({DateTime? tradingDate}) {
    final today = tradingDate ?? DateTime.now();
    final datedTrades = trades.where(
      (trade) =>
          trade.tradeDate.year == today.year &&
          trade.tradeDate.month == today.month &&
          trade.tradeDate.day == today.day,
    );
    var realized = 0.0;
    for (final trade in datedTrades) {
      final amount = verifiedTradeAmountUsd(trade, trade.realizedPL);
      if (amount == null) return null;
      realized += amount;
    }
    if (realized != 0) return realized;
    if (brokerTradeHistoryAvailable) return null;
    final snapshot = position?.realizedToday;
    return snapshot == 0 ? null : snapshot;
  }
}

/// Converts IBKR executions into trades without persisting broker history locally.
List<Trade> tradesFromIbkr(List<IbkrTrade> brokerTrades) => [
      for (var index = 0; index < brokerTrades.length; index++)
        Trade(
          id: -index - 1,
          symbol: brokerTrades[index].symbol,
          name: brokerTrades[index].name.isEmpty
              ? brokerTrades[index].symbol
              : brokerTrades[index].name,
          quantity: brokerTrades[index].quantity,
          price: brokerTrades[index].price,
          tradeType: brokerTrades[index].tradeType,
          tradeDate: brokerTrades[index].tradeDate,
          realizedPL: brokerTrades[index].realizedPnl,
          commission: brokerTrades[index].commission,
          rawCurrency: brokerTrades[index].currency,
          brokerConid: brokerTrades[index].conid,
        ),
    ];
