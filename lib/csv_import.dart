import 'package:drift/drift.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/utils.dart';

class ImportedHolding {
  final String symbol;
  final String name;
  final double amount;
  final double purchasePrice;
  final double currentPrice;
  final DateTime purchasedAt;

  ImportedHolding({
    required this.symbol,
    required this.name,
    required this.amount,
    required this.purchasePrice,
    required this.currentPrice,
    required this.purchasedAt,
  });
}

class ImportedTrade {
  final String symbol;
  final String name;
  final double quantity;
  final double price;
  final String tradeType;
  final DateTime tradeDate;
  final double realizedPL;
  final double commission;

  ImportedTrade({
    required this.symbol,
    required this.name,
    required this.quantity,
    required this.price,
    required this.tradeType,
    required this.tradeDate,
    required this.realizedPL,
    required this.commission,
  });
}

class ParseResult {
  final List<ImportedHolding> holdings;
  final List<ImportedTrade> trades;

  ParseResult({required this.holdings, required this.trades});
}

abstract class BrokerCsvParser {
  String get name;
  ParseResult parse(String csvContent);
}

/// Parses activity statement CSVs exported from Tiger Brokers.
/// Reads the Holdings section for current positions and the Trades section
/// for individual buy/sell transactions.
class TigerBrokersParser extends BrokerCsvParser {
  @override
  String get name => 'Tiger Brokers';

  static final _symbolRegex = RegExp(r'^(.*)\s+\(([^)]+)\)\s*$');

  @override
  ParseResult parse(String csvContent) {
    final rows = _parseCsv(csvContent);

    // Parse Trades DATA rows (both Open and Close)
    final List<ImportedTrade> trades = [];
    for (final row in rows) {
      if (row.length < 53) continue;
      if (row[0] != 'Trades' || row[1] != 'Stock' || row[3] != 'DATA')
        continue;
      final activityType = row[7].trim();
      if (activityType != 'Open' && activityType != 'Close') continue;

      final match = _symbolRegex.firstMatch(row[4].trim());
      if (match == null) continue;
      final name = match.group(1)!.trim();
      final symbol = match.group(2)!.trim();

      final quantity = double.tryParse(row[8].replaceAll(',', ''));
      final tradePrice = double.tryParse(row[9].replaceAll(',', ''));
      if (quantity == null || tradePrice == null) continue;

      // Realized P/L is at column 48; only meaningful for Close trades
      final realizedPL =
          double.tryParse(row[48].replaceAll(',', '')) ?? 0.0;

      // Tiger Brokers places the broker fee in the second "Transaction Fee"
      // column (index 33), not in the "Commission" column (index 23).
      final commission =
          (double.tryParse(row[33].replaceAll(',', '')) ?? 0.0).abs();

      // Trade date: first 10 chars of Trade Time field (row[50] = "YYYY-MM-DD\n...")
      final tradeTimeRaw = row[row.length - 3].trim();
      final tradeDateStr =
          tradeTimeRaw.length >= 10 ? tradeTimeRaw.substring(0, 10) : '';
      final tradeDate = DateTime.tryParse(tradeDateStr) ?? DateTime.now();

      trades.add(
        ImportedTrade(
          symbol: symbol,
          name: name,
          quantity: quantity,
          price: tradePrice,
          tradeType: activityType.toLowerCase(),
          tradeDate: tradeDate,
          realizedPL: activityType == 'Close' ? realizedPL : 0.0,
          commission: commission,
        ),
      );
    }

    // Collect earliest open-trade date per symbol (for purchasedAt)
    final Map<String, DateTime> earliestDates = {};
    for (final trade in trades) {
      if (trade.tradeType != 'open') continue;
      if (!earliestDates.containsKey(trade.symbol) ||
          trade.tradeDate.isBefore(earliestDates[trade.symbol]!)) {
        earliestDates[trade.symbol] = trade.tradeDate;
      }
    }

    // Parse Holdings DATA rows
    final List<ImportedHolding> holdings = [];
    for (final row in rows) {
      if (row.length < 14) continue;
      if (row[0] != 'Holdings' || row[1] != 'Stock' || row[3] != 'DATA')
        continue;

      final match = _symbolRegex.firstMatch(row[4].trim());
      if (match == null) continue;

      final name = match.group(1)!.trim();
      final symbol = match.group(2)!.trim();

      final amount = double.tryParse(row[5].replaceAll(',', ''));
      final costPrice = double.tryParse(row[7].replaceAll(',', ''));
      final closePrice = double.tryParse(row[8].replaceAll(',', ''));

      if (amount == null || costPrice == null || closePrice == null) continue;
      if (amount <= 0 || costPrice <= 0) continue;

      holdings.add(
        ImportedHolding(
          symbol: symbol,
          name: name,
          amount: amount,
          purchasePrice: costPrice,
          currentPrice: closePrice,
          purchasedAt: earliestDates[symbol] ?? DateTime.now(),
        ),
      );
    }

    return ParseResult(holdings: holdings, trades: trades);
  }
}

final List<BrokerCsvParser> supportedBrokers = [
  TigerBrokersParser(),
];

Future<int> importHoldings(List<ImportedHolding> holdings) async {
  int count = 0;
  for (final holding in holdings) {
    final change =
        safePercentChange(holding.purchasePrice, holding.currentPrice);
    await db.tickers.insertOne(
      TickersCompanion(
        symbol: Value(holding.symbol),
        name: Value(holding.name),
        amount: Value(holding.amount),
        price: Value(holding.purchasePrice),
        change: Value(change),
        purchasedAt: Value(holding.purchasedAt),
        updatedAt: Value(DateTime.now()),
      ),
    );
    count++;
  }
  return count;
}

Future<int> importTrades(List<ImportedTrade> trades) async {
  int count = 0;
  for (final trade in trades) {
    await db.trades.insertOne(
      TradesCompanion(
        symbol: Value(trade.symbol),
        name: Value(trade.name),
        quantity: Value(trade.quantity),
        price: Value(trade.price),
        tradeType: Value(trade.tradeType),
        tradeDate: Value(trade.tradeDate),
        realizedPL: Value(trade.realizedPL),
        commission: Value(trade.commission),
      ),
    );
    count++;
  }
  return count;
}

/// Minimal CSV parser that handles quoted fields containing commas and newlines.
List<List<String>> _parseCsv(String content) {
  // Strip leading UTF-8 BOM(s) (\uFEFF)
  var text = content;
  while (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
    text = text.substring(1);
  }

  final rows = <List<String>>[];
  var currentRow = <String>[];
  final buffer = StringBuffer();
  var inQuotes = false;

  for (int i = 0; i < text.length; i++) {
    final char = text[i];

    if (inQuotes) {
      if (char == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          // Escaped quote inside quoted field
          buffer.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        buffer.write(char);
      }
    } else {
      if (char == '"') {
        inQuotes = true;
      } else if (char == ',') {
        currentRow.add(buffer.toString());
        buffer.clear();
      } else if (char == '\n') {
        currentRow.add(buffer.toString());
        buffer.clear();
        if (currentRow.any((f) => f.isNotEmpty)) {
          rows.add(List.from(currentRow));
        }
        currentRow = [];
      } else if (char != '\r') {
        buffer.write(char);
      }
    }
  }

  // Flush any remaining data
  if (buffer.isNotEmpty || currentRow.isNotEmpty) {
    currentRow.add(buffer.toString());
    if (currentRow.any((f) => f.isNotEmpty)) {
      rows.add(currentRow);
    }
  }

  return rows;
}
