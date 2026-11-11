part of '../market_data.dart';

Future<Map<String, double>> fetchLatestPrices(
  List<String> symbols, {
  Database? database,
}) async {
  if (symbols.isEmpty) return {};
  final targetDatabase = database ?? marketDataDatabase;
  final canonicalSymbols = symbols
      .map(canonicalMarketSymbol)
      .where((symbol) => symbol.isNotEmpty)
      .toSet();
  if (canonicalSymbols.isEmpty) return {};

  await Future.wait(
    canonicalSymbols.map((symbol) async {
      await fetchSymbolCurrencyAndRate(symbol);
      final nativeCurrency = _symbolCurrencies[symbol];
      if (nativeCurrency == null || nativeCurrency.isEmpty) {
        throw StateError('Currency metadata unavailable for $symbol');
      }
      requireUsdRate(nativeCurrency);
    }),
  );

  final prices = <String, double>{};
  await Future.wait(
    canonicalSymbols.map((symbol) async {
      final latest = await (targetDatabase.candles.select()
            ..where(
              (row) =>
                  row.symbol.equals(symbol) & row.close.isBiggerThanValue(0),
            )
            ..orderBy([(row) => OrderingTerm.desc(row.date)])
            ..limit(1))
          .getSingleOrNull();
      if (latest == null) return;
      final storedRaw = latest.rawCurrency;
      final currentRaw = rawCurrencyFromMetadata(
        await targetDatabase.readSymbolMetadata(symbol),
      );
      if ((storedRaw == null && _symbolsWithCurrencyChanges.contains(symbol)) ||
          (storedRaw != null &&
              currentRaw != null &&
              storedRaw != currentRaw)) {
        throw StateError(
          'Cannot value $symbol until historical candle units are reconciled',
        );
      }
      prices[symbol] = latest.close;
    }),
  );
  return prices;
}

typedef YahooCandleFetcher = Future<List<YahooFinanceCandleData>> Function(
  String symbol,
  DateTime startDate,
);

typedef IbkrCandleFetcher = Future<IbkrHistoricalSeries> Function(
  String symbol,
  int years,
);

const defaultMarketCandleLookback = Duration(days: 14);

String canonicalMarketSymbol(String symbol) => symbol.trim().toUpperCase();

DateTime canonicalMarketDay(DateTime date) =>
    DateTime(date.year, date.month, date.day);

DateTime _offsetMarketDay(DateTime day, int offsetDays) =>
    DateTime(day.year, day.month, day.day + offsetDays);

DateTime _boundedRequiredCandleStart(DateTime requested, DateTime latestDay) {
  final day = canonicalMarketDay(requested);
  return day.isAfter(latestDay) ? latestDay : day;
}

int _ibkrYearsForRange(DateTime from, DateTime through) {
  final days = through.difference(from).inDays.abs() + 1;
  final years = (days + 364) ~/ 365;
  if (years < 1) return 1;
  if (years > 10) return 10;
  return years;
}

Future<int> insertCandles(
  List<YahooFinanceCandleData> dataList,
  String symbol, {
  Database? database,
  String? rawCurrency,
  bool preserveExisting = false,
}) async {
  const batchSize = 1000;
  final targetDatabase = database ?? marketDataDatabase;
  final canonicalSymbol = canonicalMarketSymbol(symbol);
  final byDay = <int, YahooFinanceCandleData>{};

  for (final data in dataList) {
    final day = canonicalMarketDay(data.date);
    final dayKey = day.year * 10000 + day.month * 100 + day.day;
    byDay[dayKey] = data.copyWith(date: day);
  }

  final normalized = byDay.values.toList()
    ..sort((a, b) => a.date.compareTo(b.date));

  for (var offset = 0; offset < normalized.length; offset += batchSize) {
    final candleBatch = normalized.skip(offset).take(batchSize).map((data) {
      return CandlesCompanion.insert(
        date: data.date,
        symbol: canonicalSymbol,
        open: Value(data.open),
        high: Value(data.high),
        low: Value(data.low),
        close: Value(data.close),
        adjClose: Value(data.adjClose),
        volume: Value(data.volume),
        rawCurrency: Value(rawCurrency),
      );
    }).toList();

    await targetDatabase.batch((batchBuilder) {
      batchBuilder.insertAll(
        targetDatabase.candles,
        candleBatch,
        mode: preserveExisting
            ? InsertMode.insertOrIgnore
            : InsertMode.insertOrReplace,
      );
    });
  }

  if (normalized.isNotEmpty) {
    talker.debug(
      'Stored ${normalized.length} Yahoo candles for $canonicalSymbol '
      '(${normalized.first.date.toIso8601String()}..'
      '${normalized.last.date.toIso8601String()})',
    );
  }
  return normalized.length;
}

Future<int> insertIbkrCandles(
  List<IbkrHistoricalCandle> dataList,
  String symbol, {
  Database? database,
  String? rawCurrency,
  bool preserveExisting = false,
}) async {
  const batchSize = 1000;
  final targetDatabase = database ?? marketDataDatabase;
  final canonicalSymbol = canonicalMarketSymbol(symbol);
  final byDay = <int, IbkrHistoricalCandle>{};

  final existingRows = await (targetDatabase.candles.select()
        ..where((candle) => candle.symbol.equals(canonicalSymbol)))
      .get();
  for (final row in existingRows) {
    if (row.date.weekday != DateTime.saturday &&
        row.date.weekday != DateTime.sunday) {
      continue;
    }
    await (targetDatabase.delete(targetDatabase.candles)
          ..where(
            (candle) =>
                candle.symbol.equals(canonicalSymbol) &
                candle.date.equals(row.date),
          ))
        .go();
  }

  for (final data in dataList) {
    final day = canonicalMarketDay(data.date);
    if (day.weekday == DateTime.saturday || day.weekday == DateTime.sunday) {
      continue;
    }
    final dayKey = day.year * 10000 + day.month * 100 + day.day;
    byDay[dayKey] = IbkrHistoricalCandle(
      date: day,
      open: data.open,
      high: data.high,
      low: data.low,
      close: data.close,
      volume: data.volume,
    );
  }

  final normalized = byDay.values.toList()
    ..sort((a, b) => a.date.compareTo(b.date));

  for (var offset = 0; offset < normalized.length; offset += batchSize) {
    final candleBatch = normalized.skip(offset).take(batchSize).map((data) {
      return CandlesCompanion.insert(
        date: data.date,
        symbol: canonicalSymbol,
        open: Value(data.open),
        high: Value(data.high),
        low: Value(data.low),
        close: Value(data.close),
        adjClose: Value(data.close),
        volume: Value(data.volume),
        rawCurrency: Value(rawCurrency),
      );
    }).toList();

    await targetDatabase.batch((batchBuilder) {
      batchBuilder.insertAll(
        targetDatabase.candles,
        candleBatch,
        mode: preserveExisting
            ? InsertMode.insertOrIgnore
            : InsertMode.insertOrReplace,
      );
    });
  }

  if (normalized.isNotEmpty) {
    talker.debug(
      'Stored ${normalized.length} IBKR candles for $canonicalSymbol '
      '(${normalized.first.date.toIso8601String()}..'
      '${normalized.last.date.toIso8601String()})',
    );
  }
  return normalized.length;
}

Future<StoredCandle?> findClosestDate(DateTime date, String symbol) {
  final canonicalSymbol = canonicalMarketSymbol(symbol);
  final dateOnly = canonicalMarketDay(date);
  final timestamp = dateOnly.millisecondsSinceEpoch / 1000;
  final targetDatabase = marketDataDatabase;

  return (targetDatabase.candles.select()
        ..where((candle) => candle.symbol.equals(canonicalSymbol))
        ..orderBy([
          (candle) =>
              OrderingTerm.asc(CustomExpression('ABS("date" - $timestamp)')),
        ])
        ..limit(1))
      .getSingleOrNull();
}

Future<StoredCandle?> findClosestPrice(double price, String symbol) {
  final canonicalSymbol = canonicalMarketSymbol(symbol);
  final targetDatabase = marketDataDatabase;
  return (targetDatabase.candles.select()
        ..where((candle) => candle.symbol.equals(canonicalSymbol))
        ..orderBy([
          (candle) => OrderingTerm.asc(CustomExpression('ABS(close - $price)')),
        ])
        ..limit(1))
      .getSingleOrNull();
}
