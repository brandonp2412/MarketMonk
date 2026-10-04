import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/profile_data_repository.dart';
import 'package:market_monk/unified_database.dart';

UnifiedDatabase? _marketDataDatabase;

UnifiedDatabase get marketDataDatabase =>
    _marketDataDatabase ?? profileDataDatabase;

void setMarketDataDatabaseForTesting(UnifiedDatabase? database) {
  _marketDataDatabase = database;
}

String _canonicalSymbol(String symbol) => symbol.trim().toUpperCase();

DateTime _canonicalDay(DateTime date) =>
    DateTime(date.year, date.month, date.day);

String _normalizedCurrency(String rawCurrency) => switch (rawCurrency) {
      'GBp' => 'GBP',
      'ZAc' => 'ZAR',
      _ => rawCurrency,
    };

String? rawCurrencyFromMetadata(UnifiedSymbolMetadataData? metadata) {
  if (metadata == null) return null;
  final payload = metadata.payloadJson;
  if (payload != null && payload.isNotEmpty) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        final raw = decoded['rawCurrency'];
        if (raw is String && raw.isNotEmpty) return raw;
      }
    } catch (_) {}
  }
  return metadata.currency;
}

Future<void> upsertSymbolCurrencyMetadata(
  String symbol,
  String rawCurrency, {
  UnifiedDatabase? database,
  DateTime? cachedAt,
}) async {
  final target = database ?? marketDataDatabase;
  final canonical = _canonicalSymbol(symbol);
  final existing = await target.readSymbolMetadata(canonical);
  final payload = <String, dynamic>{};
  final existingPayload = existing?.payloadJson;
  if (existingPayload != null && existingPayload.isNotEmpty) {
    try {
      final decoded = jsonDecode(existingPayload);
      if (decoded is Map<String, dynamic>) payload.addAll(decoded);
    } catch (_) {}
  }
  payload['rawCurrency'] = rawCurrency;

  await target.upsertSymbolMetadata(
    symbol: canonical,
    displayName: existing?.displayName,
    currency: _normalizedCurrency(rawCurrency),
    exchange: existing?.exchange,
    quoteType: existing?.quoteType,
    payloadJson: jsonEncode(payload),
    cachedAt: cachedAt ?? DateTime.now(),
  );
}

class LegacyMarketDataMergeResult {
  const LegacyMarketDataMergeResult({
    required this.scannedRows,
    required this.writtenRows,
    required this.symbols,
  });

  final int scannedRows;
  final int writtenRows;
  final int symbols;
}

class _CandleCandidate {
  const _CandleCandidate({
    required this.symbol,
    required this.date,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
    required this.adjClose,
  });

  factory _CandleCandidate.fromLegacy(Candle candle) => _CandleCandidate(
        symbol: _canonicalSymbol(candle.symbol),
        date: _canonicalDay(candle.date),
        open: candle.open,
        high: candle.high,
        low: candle.low,
        close: candle.close,
        volume: candle.volume,
        adjClose: candle.adjClose,
      );

  factory _CandleCandidate.fromUnified(UnifiedCandle candle) =>
      _CandleCandidate(
        symbol: _canonicalSymbol(candle.symbol),
        date: _canonicalDay(candle.date),
        open: candle.open,
        high: candle.high,
        low: candle.low,
        close: candle.close,
        volume: candle.volume,
        adjClose: candle.adjClose,
      );

  final String symbol;
  final DateTime date;
  final double open;
  final double high;
  final double low;
  final double close;
  final int volume;
  final double adjClose;

  int get quality {
    var score = 0;
    for (final value in [open, high, low, close, adjClose]) {
      if (value.isFinite && value > 0) score += 2;
    }
    if (volume > 0) score += 1;
    return score;
  }

  UnifiedCandlesCompanion toCompanion() => UnifiedCandlesCompanion.insert(
        symbol: symbol,
        date: date,
        open: Value(open),
        high: Value(high),
        low: Value(low),
        close: Value(close),
        volume: Value(volume),
        adjClose: Value(adjClose),
      );
}

Future<LegacyMarketDataMergeResult> mergeLegacyCandlesIntoUnified({
  required UnifiedDatabase target,
  required Iterable<Database> legacyDatabases,
}) async {
  final selected = <(String, int), _CandleCandidate>{};
  final existingQuality = <(String, int), int>{};

  final existing = await target.select(target.unifiedCandles).get();
  for (final candle in existing) {
    final candidate = _CandleCandidate.fromUnified(candle);
    final key = (candidate.symbol, candidate.date.millisecondsSinceEpoch);
    selected[key] = candidate;
    existingQuality[key] = candidate.quality;
  }

  var scannedRows = 0;
  for (final legacy in legacyDatabases) {
    final rows = await legacy.select(legacy.candles).get();
    scannedRows += rows.length;
    for (final candle in rows) {
      final candidate = _CandleCandidate.fromLegacy(candle);
      if (candidate.symbol.isEmpty) continue;
      final key = (candidate.symbol, candidate.date.millisecondsSinceEpoch);
      final current = selected[key];
      if (current == null || candidate.quality > current.quality) {
        selected[key] = candidate;
      }
    }
  }

  final toWrite = <_CandleCandidate>[];
  for (final entry in selected.entries) {
    final oldQuality = existingQuality[entry.key];
    if (oldQuality == null || entry.value.quality > oldQuality) {
      toWrite.add(entry.value);
    }
  }

  const batchSize = 1000;
  for (var offset = 0; offset < toWrite.length; offset += batchSize) {
    final rows = toWrite
        .skip(offset)
        .take(batchSize)
        .map((candidate) => candidate.toCompanion())
        .toList();
    await target.batch((batch) {
      batch.insertAll(
        target.unifiedCandles,
        rows,
        mode: InsertMode.insertOrReplace,
      );
    });
  }

  return LegacyMarketDataMergeResult(
    scannedRows: scannedRows,
    writtenRows: toWrite.length,
    symbols: selected.values.map((row) => row.symbol).toSet().length,
  );
}
