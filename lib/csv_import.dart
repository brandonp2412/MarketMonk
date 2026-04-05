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

abstract class BrokerCsvParser {
  String get name;
  List<ImportedHolding> parse(String csvContent);
}

/// Parses activity statement CSVs exported from Tiger Brokers.
/// Reads the Holdings section for current positions and the Trades section
/// to determine the earliest purchase date per symbol.
class TigerBrokersParser extends BrokerCsvParser {
  @override
  String get name => 'Tiger Brokers';

  static final _symbolRegex = RegExp(r'^(.*)\s+\(([^)]+)\)\s*$');

  @override
  List<ImportedHolding> parse(String csvContent) {
    final rows = _parseCsv(csvContent);

    // Collect earliest open-trade settle date per symbol
    final Map<String, DateTime> earliestDates = {};
    for (final row in rows) {
      if (row.length < 53) continue;
      if (row[0] != 'Trades' || row[1] != 'Stock' || row[3] != 'DATA') continue;
      if (row[7] != 'Open') continue;

      final match = _symbolRegex.firstMatch(row[4].trim());
      if (match == null) continue;
      final symbol = match.group(2)!.trim();

      // Settle Date is the second-to-last field; Currency is last
      final settleStr = row[row.length - 2].trim();
      final date = DateTime.tryParse(settleStr);
      if (date == null) continue;

      if (!earliestDates.containsKey(symbol) ||
          date.isBefore(earliestDates[symbol]!)) {
        earliestDates[symbol] = date;
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

    return holdings;
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
