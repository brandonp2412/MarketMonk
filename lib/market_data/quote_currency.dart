part of '../market_data.dart';

/// Fetches the native currency for [symbol] from the Yahoo Finance chart API,
/// then — only if that currency differs from USD — lazily fetches its USD-based
/// exchange rate and stores it in [allRatesFromUsd].
///
/// Results are cached in-memory and in the unified symbol metadata table, so repeat calls are
/// free and cent-quoted stocks (GBp/ZAc) keep the right scale offline.
Future<void> _fetchSymbolCurrencyAndRate(String symbol) async {
  final canonicalSymbol = canonicalMarketSymbol(symbol);
  final metadata = await marketDataDatabase.readSymbolMetadata(canonicalSymbol);
  final savedRaw = rawCurrencyFromMetadata(metadata);
  final prefs = await SqliteSettings.getInstance();
  if (savedRaw != null && savedRaw.isNotEmpty) {
    final normalized = cacheSymbolMeta(canonicalSymbol, savedRaw);
    if (normalized != 'USD' && !allRatesFromUsd.containsKey(normalized)) {
      final savedRate = readCachedUsdRate(normalized, prefs)?.rate;
      if (savedRate != null && savedRate.isFinite && savedRate > 0) {
        allRatesFromUsd[normalized] = savedRate;
      } else {
        await _fetchAndCacheRate(normalized);
      }
    }
    if (DateTime.now().toUtc().difference(metadata!.cachedAt.toUtc()) <
        const Duration(hours: 24)) {
      return;
    }
  }

  try {
    final uri = Uri.parse(
      'https://query1.finance.yahoo.com/v8/finance/chart/$canonicalSymbol'
      '?interval=1d&range=1d',
    );
    final response = await http.get(uri);
    if (response.statusCode != 200) return;
    final data = json.decode(response.body) as Map<String, dynamic>;
    final result =
        ((data['chart'] as Map<String, dynamic>?)?['result'] as List?)?.first
            as Map<String, dynamic>?;
    final rawCurrency =
        (result?['meta'] as Map<String, dynamic>?)?['currency'] as String?;
    if (rawCurrency == null || rawCurrency.isEmpty) return;

    await upsertSymbolCurrencyMetadata(
      canonicalSymbol,
      rawCurrency,
      source: 'yahoo-chart',
    );
    final normalized = cacheSymbolMeta(canonicalSymbol, rawCurrency);
    if (normalized != 'USD' && !allRatesFromUsd.containsKey(normalized)) {
      await _fetchAndCacheRate(normalized);
    }
  } catch (error, stackTrace) {
    talker.handle(error, stackTrace, 'Failed to fetch symbol currency');
  }
}

Future<void> _fetchAndCacheRate(String currencyCode) async {
  try {
    final quote = await refreshUsdRate(currencyCode);
    allRatesFromUsd[currencyCode] = quote.rate;
  } catch (error, stackTrace) {
    talker.handle(error, stackTrace, 'Failed to fetch exchange rate');
  }
}
