import 'package:drift/drift.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/main.dart';

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
  final List<ImportedTrade> trades;

  ParseResult({required this.trades});
}

abstract class BrokerCsvParser {
  String get name;
  ParseResult parse(String csvContent);
}

/// Parses activity statement CSVs exported from Tiger Brokers.
/// Reads the Trades section for individual buy/sell transactions.
class TigerBrokersParser extends BrokerCsvParser {
  @override
  String get name => 'Tiger Brokers';

  static final _symbolRegex = RegExp(r'^(.*)\s+\(([^)]+)\)\s*$');

  @override
  ParseResult parse(String csvContent) {
    final rows = _parseCsv(csvContent);

    final List<ImportedTrade> trades = [];
    for (final row in rows) {
      if (row.length < 53) continue;
      if (row[0] != 'Trades' || row[1] != 'Stock' || row[3] != 'DATA') continue;
      final activityType = row[7].trim();
      if (activityType != 'Open' && activityType != 'Close') continue;

      final match = _symbolRegex.firstMatch(row[4].trim());
      if (match == null) continue;
      final name = match.group(1)!.trim();
      final symbol = match.group(2)!.trim();

      final quantity = double.tryParse(row[8].replaceAll(',', ''));
      final tradePrice = double.tryParse(row[9].replaceAll(',', ''));
      if (quantity == null || tradePrice == null) continue;

      final realizedPL = double.tryParse(row[48].replaceAll(',', '')) ?? 0.0;
      final commission =
          (double.tryParse(row[33].replaceAll(',', '')) ?? 0.0).abs();

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

    return ParseResult(trades: trades);
  }
}

/// Parses trade execution CSVs exported from Interactive Brokers (Flex Query
/// or Activity Statement → Trades section, "EXECUTION" level of detail).
///
/// Each row in the IBKR file represents a single fill. The parser skips
/// non-STK asset classes (e.g. forex CASH rows) and any rows that are not
/// individual executions (e.g. summary ORDER rows).
class InteractiveBrokersParser extends BrokerCsvParser {
  @override
  String get name => 'Interactive Brokers';

  @override
  ParseResult parse(String csvContent) {
    final rows = _parseCsv(csvContent);
    if (rows.isEmpty) return ParseResult(trades: []);

    final header = rows.first;
    final col = <String, int>{};
    for (int i = 0; i < header.length; i++) {
      col[header[i].trim()] = i;
    }

    final symbolIdx = col['Symbol'];
    final descIdx = col['Description'];
    final assetClassIdx = col['AssetClass'];
    final buySellIdx = col['Buy/Sell'];
    final quantityIdx = col['Quantity'];
    final priceIdx = col['Price'];
    final commissionIdx = col['Commission'];
    final tradeDateIdx = col['TradeDate'];
    final levelIdx = col['LevelOfDetail'];

    if ([
      symbolIdx,
      descIdx,
      assetClassIdx,
      buySellIdx,
      quantityIdx,
      priceIdx,
      commissionIdx,
      tradeDateIdx,
      levelIdx,
    ].any((i) => i == null)) {
      return ParseResult(trades: []);
    }

    final trades = <ImportedTrade>[];
    for (final row in rows.skip(1)) {
      if (row[assetClassIdx!].trim() != 'STK') continue;
      if (row[levelIdx!].trim() != 'EXECUTION') continue;

      final symbol = row[symbolIdx!].trim();
      if (symbol.isEmpty) continue;

      final buySell = row[buySellIdx!].trim();
      if (buySell != 'BUY' && buySell != 'SELL') continue;

      final rawQty = double.tryParse(row[quantityIdx!].replaceAll(',', ''));
      final price = double.tryParse(row[priceIdx!].replaceAll(',', ''));
      if (rawQty == null || price == null) continue;

      final quantity = buySell == 'SELL' ? -rawQty.abs() : rawQty.abs();
      final commission =
          (double.tryParse(row[commissionIdx!].replaceAll(',', '')) ?? 0.0)
              .abs();

      // TradeDate column is "YYYYMMDD" (e.g. "20260413")
      final raw = row[tradeDateIdx!].trim();
      final tradeDate = raw.length == 8
          ? DateTime.tryParse(
                '${raw.substring(0, 4)}-${raw.substring(4, 6)}-${raw.substring(6, 8)}',
              ) ??
              DateTime.now()
          : DateTime.tryParse(raw) ?? DateTime.now();

      trades.add(
        ImportedTrade(
          symbol: symbol,
          name: row[descIdx!].trim(),
          quantity: quantity,
          price: price,
          tradeType: buySell == 'BUY' ? 'open' : 'close',
          tradeDate: tradeDate,
          realizedPL: 0.0,
          commission: commission,
        ),
      );
    }

    return ParseResult(trades: trades);
  }
}

final List<BrokerCsvParser> supportedBrokers = [
  TigerBrokersParser(),
  InteractiveBrokersParser(),
];

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

  if (buffer.isNotEmpty || currentRow.isNotEmpty) {
    currentRow.add(buffer.toString());
    if (currentRow.any((f) => f.isNotEmpty)) {
      rows.add(currentRow);
    }
  }

  return rows;
}
