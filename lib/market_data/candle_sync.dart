part of '../market_data.dart';

// ---------------------------------------------------------------------------
// Per-session sync guard — prevents redundant HTTP calls and DB queries when
// the same symbol is requested multiple times in one app session.
// Resets automatically when the calendar day changes.
// ---------------------------------------------------------------------------
/// Removes [symbol] from the global market-data sync guard so the next
/// [syncCandles] call will actually re-check (used by pull-to-refresh).
void clearSyncCache(String symbol) {
  final canonicalSymbol = canonicalMarketSymbol(symbol);
  backgroundNetworkCoordinator.clearFreshness(
    'market.candles',
    where: (key) => key is (String, int, bool) && key.$1 == canonicalSymbol,
  );
}

/// Removes all symbols from the sync guard (e.g. after a full manual refresh).
void clearAllSyncCache() =>
    backgroundNetworkCoordinator.clearFreshness('market.candles');

DateTime _latestExpectedMarketDay(DateTime today) {
  var expectedDay = today;
  while (expectedDay.weekday == DateTime.saturday ||
      expectedDay.weekday == DateTime.sunday) {
    expectedDay = _offsetMarketDay(expectedDay, -1);
  }
  return expectedDay;
}

/// Provider currency metadata does not prove that pre-change bars were
/// retroactively redenominated. Only observations strictly after the most
/// recent detected transition can be labelled with its current quote unit.
Future<DateTime?> _firstVerifiedCurrentQuoteDay(
  Database database,
  String symbol,
) async {
  final changes = await database.readQuoteCurrencyChanges(symbol);
  if (changes.isEmpty) return null;
  _symbolsWithCurrencyChanges.add(symbol);
  final observed = changes.last.observedAt;
  return DateTime(observed.year, observed.month, observed.day + 1);
}

Future<bool> _syncIbkrCandlesIfAvailable(
  String symbol, {
  required Database targetDatabase,
  required IbkrAccountConfig? ibkrConfig,
  required DateTime requestFrom,
  required DateTime expectedMarketDay,
  IbkrCandleFetcher? ibkrFetcher,
}) async {
  if (ibkrConfig?.isConfigured != true) return false;

  final config = ibkrConfig!;
  final years = _ibkrYearsForRange(requestFrom, expectedMarketDay);

  try {
    final history = ibkrFetcher != null
        ? await ibkrFetcher(symbol, years)
        : await IbkrApiClient(config)
            .fetchHistoricalCandles(symbol, years: years);
    if (history.candles.isEmpty) {
      throw StateError('IBKR returned no historical candles');
    }

    final normalizedCurrency = cacheSymbolMeta(symbol, history.currency);
    await upsertSymbolCurrencyMetadata(
      symbol,
      history.currency,
      database: targetDatabase,
    );
    if (normalizedCurrency != 'USD' &&
        !allRatesFromUsd.containsKey(normalizedCurrency)) {
      await _fetchAndCacheRate(normalizedCurrency);
    }

    final requestedCandles = history.candles.where((candle) {
      final day = canonicalMarketDay(candle.date);
      return !day.isBefore(requestFrom) && !day.isAfter(expectedMarketDay);
    }).toList();
    if (requestedCandles.isEmpty) {
      throw StateError('IBKR returned no candles in the requested range');
    }

    final verifiedFrom = await _firstVerifiedCurrentQuoteDay(
      targetDatabase,
      symbol,
    );
    var stored = 0;
    if (verifiedFrom != null) {
      // Do not overwrite known older units, or assign today's quote unit to
      // older bars that the broker may still express in their original unit.
      stored += await insertIbkrCandles(
        requestedCandles
            .where(
              (candle) =>
                  canonicalMarketDay(candle.date).isBefore(verifiedFrom),
            )
            .toList(),
        symbol,
        database: targetDatabase,
        preserveExisting: true,
      );
    }
    stored += await insertIbkrCandles(
      verifiedFrom == null
          ? requestedCandles
          : requestedCandles
              .where(
                (candle) =>
                    !canonicalMarketDay(candle.date).isBefore(verifiedFrom),
              )
              .toList(),
      symbol,
      database: targetDatabase,
      rawCurrency: history.currency,
    );
    talker.info(
      'Completed IBKR candle sync for $symbol: $stored rows from '
      '${requestFrom.toIso8601String()}',
    );
    return true;
  } catch (error) {
    talker.warning(
      'IBKR candle sync failed for $symbol; falling back to Yahoo: $error',
    );
    ibkrCandleFailureNotice.report(symbol, error);
    return false;
  }
}

/// Synchronizes reusable daily market data for [symbol].
///
/// [requiredFrom] describes the oldest day the caller actually needs. Coverage
/// is derived from stored symbol/date rows, so an empty cache does not imply an
/// all-history seed and widening a chart backfills only the missing range.
/// [syncNamespace] is retained for current call-site compatibility only; candle
/// identity and coverage are deliberately independent of account ownership.

final _cryptoSyncAt = <String, DateTime>{};
final _cryptoOhlcAttemptFrom = <String, DateTime>{};

Future<void> _syncCryptoCandles(
  Database database,
  CryptoAsset asset, {
  DateTime? requiredFrom,
  required bool forceRefresh,
  required CryptoMarketData marketData,
}) async {
  final now = DateTime.now().toUtc();
  final today = canonicalMarketDay(now);
  final requested = canonicalMarketDay(
    requiredFrom ?? now.subtract(defaultMarketCandleLookback),
  );
  final start = requested.isAfter(today) ? today : requested;
  final first = await (database.candles.select()
        ..where((row) => row.symbol.equals(asset.symbol))
        ..orderBy([
          (row) => OrderingTerm(expression: row.date, mode: OrderingMode.asc),
        ])
        ..limit(1))
      .getSingleOrNull();
  final last = await (database.candles.select()
        ..where((row) => row.symbol.equals(asset.symbol))
        ..orderBy([
          (row) => OrderingTerm(expression: row.date, mode: OrderingMode.desc),
        ])
        ..limit(1))
      .getSingleOrNull();
  final requestedFirst = await (database.candles.select()
        ..where(
          (row) =>
              row.symbol.equals(asset.symbol) &
              row.date.isBiggerOrEqualValue(start),
        )
        ..orderBy([(row) => OrderingTerm.asc(row.date)])
        ..limit(1))
      .getSingleOrNull();
  final fetchedAt = _cryptoSyncAt[asset.symbol];
  final lastOhlcFrom = _cryptoOhlcAttemptFrom[asset.symbol];
  final needsOhlcBackfill = requestedFirst != null &&
      requestedFirst.open == requestedFirst.high &&
      requestedFirst.high == requestedFirst.low &&
      requestedFirst.low == requestedFirst.close &&
      (lastOhlcFrom == null ||
          lastOhlcFrom.isAfter(start) ||
          fetchedAt == null ||
          now.difference(fetchedAt) >= const Duration(minutes: 5));
  if (!forceRefresh &&
      !needsOhlcBackfill &&
      first != null &&
      !canonicalMarketDay(first.date).isAfter(start) &&
      last != null &&
      !canonicalMarketDay(last.date).isBefore(today) &&
      fetchedAt != null &&
      now.difference(fetchedAt) < const Duration(minutes: 5)) {
    return;
  }
  final fetchFrom = forceRefresh ||
          needsOhlcBackfill ||
          first == null ||
          canonicalMarketDay(first.date).isAfter(start)
      ? start
      : canonicalMarketDay(last?.date ?? start)
          .subtract(const Duration(days: 2));
  final bars = await backgroundNetworkCoordinator.coalesce(
    'crypto.daily',
    (
      asset.symbol,
      fetchFrom,
    ),
    () => marketData.dailyHistory(asset, fetchFrom),
  );
  if (bars.isEmpty) throw StateError('No crypto prices for ${asset.symbol}');
  for (var offset = 0; offset < bars.length; offset += 1000) {
    final batch = bars.skip(offset).take(1000).map((bar) {
      return CandlesCompanion.insert(
        date: bar.date,
        symbol: asset.symbol,
        open: Value(bar.open),
        high: Value(bar.high),
        low: Value(bar.low),
        close: Value(bar.close),
        adjClose: Value(bar.close),
        volume: Value(bar.volume.round()),
        rawCurrency: const Value('USD'),
      );
    }).toList();
    await database.batch(
      (builder) => builder.insertAll(
        database.candles,
        batch,
        mode: InsertMode.insertOrReplace,
      ),
    );
  }
  _cryptoSyncAt[asset.symbol] = now;
  _cryptoOhlcAttemptFrom[asset.symbol] = fetchFrom;
}

Future<void> syncCandles(
  String symbol, {
  Database? database,
  IbkrAccountConfig? ibkrConfig,
  String syncNamespace = 'Default',
  DateTime? requiredFrom,
  bool forceRefresh = false,
  YahooCandleFetcher? yahooFetcher,
  IbkrCandleFetcher? ibkrFetcher,
  CryptoMarketData? cryptoMarketData,
}) async {
  final targetDatabase = database ?? marketDataDatabase;
  final canonicalSymbol = canonicalMarketSymbol(symbol);
  final cryptoAsset = cryptoAssetForSymbol(canonicalSymbol);
  if (cryptoAsset != null) {
    if (database == null) await fetchSymbolCurrencyAndRate(canonicalSymbol);
    cacheSymbolMeta(canonicalSymbol, 'USD');
    await _syncCryptoCandles(
      targetDatabase,
      cryptoAsset,
      requiredFrom: requiredFrom,
      forceRefresh: forceRefresh,
      marketData: cryptoMarketData ?? CryptoMarketData(),
    );
    return;
  }
  if (database == null && ibkrConfig?.isConfigured != true) {
    await fetchSymbolCurrencyAndRate(canonicalSymbol);
  }
  final now = DateTime.now();
  final today = canonicalMarketDay(now);
  final expectedMarketDay = _latestExpectedMarketDay(today);
  final requiredStart = _boundedRequiredCandleStart(
    requiredFrom ??
        _offsetMarketDay(today, -defaultMarketCandleLookback.inDays),
    expectedMarketDay,
  );

  Future<
      ({
        bool covered,
        DateTime? oldestDay,
        DateTime? latestDay,
        bool needsReconciliation,
      })> readCoverage() async {
    final oldest = await (targetDatabase.candles.select()
          ..where((row) => row.symbol.equals(canonicalSymbol))
          ..orderBy([
            (row) => OrderingTerm(expression: row.date, mode: OrderingMode.asc),
          ])
          ..limit(1))
        .getSingleOrNull();
    final latest = await (targetDatabase.candles.select()
          ..where((row) => row.symbol.equals(canonicalSymbol))
          ..orderBy([
            (row) =>
                OrderingTerm(expression: row.date, mode: OrderingMode.desc),
          ])
          ..limit(1))
        .getSingleOrNull();

    final oldestDay = oldest == null ? null : canonicalMarketDay(oldest.date);
    final latestDay = latest == null ? null : canonicalMarketDay(latest.date);
    final currentRaw = rawCurrencyFromMetadata(
      await targetDatabase.readSymbolMetadata(canonicalSymbol),
    );
    final transitioned = (await targetDatabase.readQuoteCurrencyChanges(
      canonicalSymbol,
    ))
        .isNotEmpty;
    final unresolved = transitioned &&
        (await (targetDatabase.candles.select()
                  ..where(
                    (row) =>
                        row.symbol.equals(canonicalSymbol) &
                        row.date.isBiggerOrEqualValue(requiredStart) &
                        row.rawCurrency.isNull(),
                  )
                  ..limit(1))
                .getSingleOrNull()) !=
            null;
    final staleLatest = currentRaw != null &&
        latest != null &&
        latest.rawCurrency != null &&
        latest.rawCurrency != currentRaw;
    final needsReconciliation = unresolved || staleLatest;
    final covered = oldestDay != null &&
        !oldestDay.isAfter(requiredStart) &&
        latestDay != null &&
        !expectedMarketDay.isAfter(latestDay) &&
        !needsReconciliation;
    return (
      covered: covered,
      oldestDay: oldestDay,
      latestDay: latestDay,
      needsReconciliation: needsReconciliation,
    );
  }

  Future<({bool requested, bool progressed, DateTime coverageFrom})>
      performSync() async {
    final coverage = await readCoverage();
    if (!forceRefresh && coverage.covered) {
      return (requested: false, progressed: false, coverageFrom: requiredStart);
    }

    var requestFrom = coverage.latestDay == null
        ? requiredStart
        : _offsetMarketDay(coverage.latestDay!, -1);
    if (!coverage.covered &&
        (coverage.oldestDay == null ||
            coverage.oldestDay!.isAfter(requiredStart))) {
      requestFrom = requiredStart;
    }
    if (coverage.needsReconciliation || requestFrom.isBefore(requiredStart)) {
      requestFrom = requiredStart;
    }

    final ibkrHandled = await _syncIbkrCandlesIfAvailable(
      canonicalSymbol,
      targetDatabase: targetDatabase,
      ibkrConfig: ibkrConfig,
      requestFrom: requestFrom,
      expectedMarketDay: expectedMarketDay,
      ibkrFetcher: ibkrFetcher,
    );
    if (ibkrHandled) {
      final after = await readCoverage();
      final progressed = coverage.oldestDay != after.oldestDay ||
          coverage.latestDay != after.latestDay ||
          coverage.needsReconciliation != after.needsReconciliation;
      return (
        requested: true,
        progressed: progressed,
        coverageFrom: requiredStart,
      );
    }

    await fetchSymbolCurrencyAndRate(canonicalSymbol);
    final seriesRawCurrency = rawCurrencyFromMetadata(
      await targetDatabase.readSymbolMetadata(canonicalSymbol),
    );

    final fetch = yahooFetcher ??
        (String ticker, DateTime startDate) async {
          final response = await const YahooFinanceDailyReader().getDailyDTOs(
            ticker,
            startDate: startDate,
          );
          return response.candlesData;
        };
    final response = await backgroundNetworkCoordinator
        .observe<List<YahooFinanceCandleData>>(
      RequestCategory.yahooCandles,
      () => fetch(canonicalSymbol, requestFrom),
    );
    final requestedCandles = response.where((candle) {
      final day = canonicalMarketDay(candle.date);
      return !day.isBefore(requestFrom) && !day.isAfter(expectedMarketDay);
    }).toList();
    final verifiedFrom = await _firstVerifiedCurrentQuoteDay(
      targetDatabase,
      canonicalSymbol,
    );
    var stored = 0;
    if (verifiedFrom != null) {
      stored += await insertCandles(
        requestedCandles
            .where(
              (candle) =>
                  canonicalMarketDay(candle.date).isBefore(verifiedFrom),
            )
            .toList(),
        canonicalSymbol,
        database: targetDatabase,
        preserveExisting: true,
      );
    }
    stored += await insertCandles(
      verifiedFrom == null
          ? requestedCandles
          : requestedCandles
              .where(
                (candle) =>
                    !canonicalMarketDay(candle.date).isBefore(verifiedFrom),
              )
              .toList(),
      canonicalSymbol,
      database: targetDatabase,
      rawCurrency: seriesRawCurrency,
    );
    backgroundNetworkCoordinator.recordRows(
      RequestCategory.yahooCandles,
      stored,
    );
    talker.info(
      'Completed Yahoo candle sync for $canonicalSymbol: $stored rows '
      'from ${requestFrom.toIso8601String()}',
    );
    final after = await readCoverage();
    final progressed = coverage.oldestDay != after.oldestDay ||
        coverage.latestDay != after.latestDay;
    return (
      requested: true,
      progressed: progressed,
      coverageFrom: requiredStart,
    );
  }

  try {
    while (true) {
      final syncResult = await backgroundNetworkCoordinator
          .coalesce<({bool requested, bool progressed, DateTime coverageFrom})>(
        RequestCategory.marketCandles,
        canonicalSymbol,
        performSync,
      );

      if (forceRefresh) {
        // A simultaneous shorter-range load may have won coalescing. Its
        // successful request cannot fulfill this wider manual prefetch.
        if (syncResult.coverageFrom.isAfter(requiredStart)) continue;
        if (syncResult.requested) {
          if ((await readCoverage()).covered || !syncResult.progressed) return;
        }
        continue;
      }

      if ((await readCoverage()).covered) return;
      if (!syncResult.requested) continue;
      if (!syncResult.progressed) return;
    }
  } catch (error, stackTrace) {
    talker.handle(error, stackTrace, 'Candle sync failed');
    rethrow;
  }
}
