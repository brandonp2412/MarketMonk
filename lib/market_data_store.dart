import 'dart:convert';

import 'package:market_monk/database.dart';
import 'package:market_monk/profile_data_repository.dart';

Database? _marketDataDatabase;

Database get marketDataDatabase => _marketDataDatabase ?? profileDataDatabase;

void setMarketDataDatabaseForTesting(Database? database) {
  _marketDataDatabase = database;
}

String _canonicalSymbol(String symbol) => symbol.trim().toUpperCase();

String _normalizedCurrency(String rawCurrency) => switch (rawCurrency) {
      'GBp' => 'GBP',
      'ZAc' => 'ZAR',
      _ => rawCurrency,
    };

String? rawCurrencyFromMetadata(StoredSymbolMetadata? metadata) {
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

Future<bool> upsertSymbolCurrencyMetadata(
  String symbol,
  String rawCurrency, {
  Database? database,
  DateTime? cachedAt,
  String source = 'market-data',
}) async {
  final target = database ?? marketDataDatabase;
  final canonical = _canonicalSymbol(symbol);
  if (canonical.isEmpty || rawCurrency.isEmpty) return false;
  final observedAt = (cachedAt ?? DateTime.now()).toUtc();
  return target.transaction(() async {
    final existing = await target.readSymbolMetadata(canonical);
    final previous = rawCurrencyFromMetadata(existing);
    final changed =
        previous != null && previous.isNotEmpty && previous != rawCurrency;
    final payload = <String, dynamic>{};
    final existingPayload = existing?.payloadJson;
    if (existingPayload != null && existingPayload.isNotEmpty) {
      try {
        final decoded = jsonDecode(existingPayload);
        if (decoded is Map<String, dynamic>) payload.addAll(decoded);
      } catch (_) {}
    }
    payload['rawCurrency'] = rawCurrency;

    if (changed) {
      await target.recordQuoteCurrencyChange(
        symbol: canonical,
        previousRawCurrency: previous,
        nextRawCurrency: rawCurrency,
        source: source,
        observedAt: observedAt,
      );
    }
    await target.upsertSymbolMetadata(
      symbol: canonical,
      displayName: existing?.displayName,
      currency: _normalizedCurrency(rawCurrency),
      exchange: existing?.exchange,
      quoteType: existing?.quoteType,
      payloadJson: jsonEncode(payload),
      cachedAt: observedAt,
    );
    return changed;
  });
}
