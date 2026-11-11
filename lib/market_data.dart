import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:market_monk/background_network_coordinator.dart';
import 'package:market_monk/crypto_market_data.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/exchange_rate_service.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/ibkr_candle_failure_notice.dart';
import 'package:market_monk/logging.dart';
import 'package:market_monk/market_data_store.dart';
import 'package:market_monk/sqlite_settings.dart';
import 'package:yahoo_finance_data_reader/yahoo_finance_data_reader.dart';

export 'market_data/yahoo_search.dart';

part 'market_data/candle_storage.dart';
part 'market_data/candle_sync.dart';
part 'market_data/positions.dart';
part 'market_data/quote_currency.dart';

var currency = NumberFormat.simpleCurrency();
bool maskCurrencyAmounts = false;

/// USD-based rates for every supported currency (key=ISO code, value=units per 1 USD).
/// Populated by SettingsState on startup and currency change.
Map<String, double> allRatesFromUsd = {'USD': 1.0};

/// Returns the USD-based exchange rate for [currencyCode].
///
/// A missing rate is an unavailable valuation, never evidence of a 1:1 USD
/// rate. Failing closed prevents foreign holdings from being multiplied by an
/// unrelated display-currency rate.
double requireUsdRate(String currencyCode) {
  final rate = allRatesFromUsd[currencyCode];
  if (rate == null || rate <= 0 || !rate.isFinite) {
    throw StateError('Exchange rate unavailable for $currencyCode');
  }
  return rate;
}

/// The current USD → displayCurrency conversion factor.
double get exchangeRate => requireUsdRate(currency.currencyName ?? 'USD');

/// Yahoo Finance uses cent-based currency codes for some exchanges.
/// Maps cent code → (parent ISO code, divisor from cents to base units).
const _yahooCentCurrencies = <String, (String, double)>{
  'ZAc': ('ZAR', 100.0),
  'GBp': ('GBP', 100.0),
};

String normalizedQuoteCurrency(String rawCurrency) =>
    _yahooCentCurrencies[rawCurrency]?.$1 ?? rawCurrency;

double quoteUnitDivisor(String rawCurrency) =>
    _yahooCentCurrencies[rawCurrency]?.$2 ?? 1.0;

bool hasKnownQuoteCurrencyChange(String symbol) =>
    _symbolsWithCurrencyChanges.contains(canonicalMarketSymbol(symbol));

final Set<String> _symbolsWithCurrencyChanges = {};

/// In-memory cache: symbol → native ISO currency code (e.g. "INR" for .NS stocks).
final Map<String, String> _symbolCurrencies = {};

/// In-memory cache: symbol → cent divisor (100.0 for ZAc/GBp, else 1.0).
final Map<String, double> _symbolCentDivisors = {};
final Map<String, DateTime> _observedSymbolAt = {};

/// Returns the cached native currency for [symbol], defaulting to 'USD'.
String symbolCurrency(String symbol) => _symbolCurrencies[symbol] ?? 'USD';

/// Returns the cent divisor for [symbol] (100.0 for ZAc/GBp stocks, else 1.0).
double symbolCentDivisor(String symbol) => _symbolCentDivisors[symbol] ?? 1.0;

bool symbolHasQuoteCurrencyChange(String symbol) =>
    _symbolsWithCurrencyChanges.contains(canonicalMarketSymbol(symbol));

void runDetachedTask<T>(Future<T> future, String label) {
  unawaited(
    future.then<void>((_) {}).catchError((Object error, StackTrace stackTrace) {
      talker.handle(error, stackTrace, label);
    }),
  );
}

/// Caches [rawCurrency] (as reported by Yahoo, e.g. 'GBp') for [symbol],
/// normalizing cent codes to their parent ISO currency (GBp → GBP ÷ 100).
/// Returns the normalized ISO code.
String cacheSymbolMeta(String symbol, String rawCurrency) {
  final normalized = normalizedQuoteCurrency(rawCurrency);
  _symbolCurrencies[symbol] = normalized;
  _symbolCentDivisors[symbol] = quoteUnitDivisor(rawCurrency);
  _observedSymbolAt[symbol] = DateTime.now().toUtc();
  return normalized;
}

Future<double> historicalTradeUsdRate(String rawCurrency, DateTime date) async {
  final code = normalizedQuoteCurrency(rawCurrency).toUpperCase();
  if (code == 'USD') return 1.0;
  final day = DateTime.utc(date.year, date.month, date.day);
  final dateKey = day.toIso8601String().substring(0, 10);
  final settingKey = 'historicalUsdRate_${code}_$dateKey';
  final prefs = await SqliteSettings.getInstance();
  final cached = prefs.getDouble(settingKey);
  if (cached != null && cached.isFinite && cached > 0) return cached;
  return backgroundNetworkCoordinator.coalesce<double>(
    'fx.historical',
    settingKey,
    () async {
      final quote = await fetchHistoricalUsdRate(code, day);
      await prefs.setDouble(settingKey, quote.rate);
      return quote.rate;
    },
  );
}

Future<List<Trade>> enrichHistoricalTradeRates(List<Trade> trades) async {
  final verified = List<Trade>.of(trades);
  for (var offset = 0; offset < verified.length; offset += 4) {
    final end = (offset + 4).clamp(0, verified.length);
    final batch = await Future.wait([
      for (var index = offset; index < end; index++)
        () async {
          final trade = verified[index];
          final raw = trade.rawCurrency;
          if (raw == null || trade.usdRateAtTrade != null) return trade;
          try {
            return trade.withUsdRate(
              await historicalTradeUsdRate(raw, trade.tradeDate),
            );
          } catch (error) {
            talker.warning(
              'Historical FX unavailable for ${trade.symbol} '
              '${trade.tradeDate}: $error',
            );
            return trade;
          }
        }(),
    ]);
    for (var index = offset; index < end; index++) {
      verified[index] = batch[index - offset];
    }
  }
  return verified;
}

double tradeAmountUsd(Trade trade, double rawAmount) {
  final rawCurrency = trade.rawCurrency;
  if (rawCurrency == null &&
      _symbolsWithCurrencyChanges.contains(trade.symbol)) {
    throw StateError('${trade.symbol} has an unverified historical quote unit');
  }
  final currencyCode = rawCurrency == null
      ? symbolCurrency(trade.symbol)
      : normalizedQuoteCurrency(rawCurrency);
  final divisor = rawCurrency == null
      ? symbolCentDivisor(trade.symbol)
      : quoteUnitDivisor(rawCurrency);
  if (rawCurrency != null &&
      currencyCode != 'USD' &&
      trade.usdRateAtTrade == null) {
    throw StateError('Historical FX rate unavailable for ${trade.symbol}');
  }
  final rate = trade.usdRateAtTrade ?? requireUsdRate(currencyCode);
  if (!rate.isFinite || rate <= 0) {
    throw StateError('Invalid trade FX rate for ${trade.symbol}');
  }
  return rawAmount / divisor / rate;
}

double? verifiedTradeAmountUsd(Trade trade, double rawAmount) {
  if (rawAmount == 0) return 0;
  final raw = trade.rawCurrency;
  if (raw != null &&
      normalizedQuoteCurrency(raw) != 'USD' &&
      trade.usdRateAtTrade == null) {
    return null;
  }
  try {
    return tradeAmountUsd(trade, rawAmount);
  } on StateError {
    return null;
  }
}

String fmtTradeNative(Trade trade, double amount) {
  final raw = trade.rawCurrency;
  if (raw == null) {
    return '${amount.toStringAsFixed(2)} (unit unverified)';
  }
  final code = normalizedQuoteCurrency(raw);
  return NumberFormat.simpleCurrency(name: code)
      .format(amount / quoteUnitDivisor(raw));
}

double candleCentDivisor(StoredCandle candle) {
  final raw = candle.rawCurrency;
  if (raw != null) return quoteUnitDivisor(raw);
  if (_symbolsWithCurrencyChanges.contains(candle.symbol)) {
    throw StateError('${candle.symbol} has unverified historical candle units');
  }
  return symbolCentDivisor(candle.symbol);
}

/// Uses IBKR's own base-currency conversion when the snapshot exposes the same
/// net-liquidation value in both base currency and USD.
void cacheIbkrAccountExchangeRate(IbkrPortfolioSnapshot snapshot) {
  final base = snapshot.netLiquidation;
  final usd = snapshot.netLiquidationUsd;
  if (base == null || base.currency.isEmpty || base.currency == 'USD') {
    return;
  }
  final brokerRate = snapshot.usdExchangeRateInBase;
  if (brokerRate != null) {
    allRatesFromUsd[base.currency] = brokerRate;
    return;
  }
  if (usd == null || usd.value == 0) return;
  allRatesFromUsd[base.currency] = base.value / usd.value;
}

/// Label for the raw unit that [symbol]'s prices are quoted in — the cent
/// code (e.g. "GBp") for cent-quoted stocks, else the currency symbol.
String symbolPriceUnit(String symbol) {
  final curr = symbolCurrency(symbol);
  if (symbolCentDivisor(symbol) == 1.0) return nativeCurrencySymbol(curr);
  return '${_yahooCentCurrencies.entries.firstWhere((entry) => entry.value.$1 == curr).key} ';
}

/// Ensures the native currency and its exchange rate are cached for [symbol].
/// Uses [rawCurrency] when a price response already supplies the quote unit.
/// Remote metadata is best-effort, and missing rates use the persisted cache.
Future<void> fetchSymbolCurrencyAndRate(
  String symbol, {
  String? rawCurrency,
}) async {
  final canonicalSymbol = canonicalMarketSymbol(symbol);
  if (canonicalSymbol.isEmpty) return;
  if (cryptoAssetForSymbol(canonicalSymbol) != null) {
    cacheSymbolMeta(canonicalSymbol, 'USD');
    final metadata = await marketDataDatabase.readSymbolMetadata(
      canonicalSymbol,
    );
    if (rawCurrencyFromMetadata(metadata) != 'USD') {
      await upsertSymbolCurrencyMetadata(
        canonicalSymbol,
        'USD',
        source: 'crypto',
      );
    }
    return;
  }
  final seenAt = _observedSymbolAt[canonicalSymbol];
  final cachedCurrency = _symbolCurrencies[canonicalSymbol];
  if (rawCurrency == null &&
      seenAt != null &&
      DateTime.now().toUtc().difference(seenAt) < const Duration(hours: 24) &&
      cachedCurrency != null &&
      allRatesFromUsd.containsKey(cachedCurrency)) {
    return;
  }
  if (rawCurrency != null && rawCurrency.isNotEmpty) {
    await upsertSymbolCurrencyMetadata(
      canonicalSymbol,
      rawCurrency,
      source: 'live-quote',
    );
    cacheSymbolMeta(canonicalSymbol, rawCurrency);
  }
  try {
    await backgroundNetworkCoordinator.coalesce<void>(
      'yahoo.symbolMetadata',
      canonicalSymbol,
      () => _fetchSymbolCurrencyAndRate(canonicalSymbol)
          .timeout(const Duration(seconds: 2)),
    );
    if ((await marketDataDatabase.readQuoteCurrencyChanges(canonicalSymbol))
        .isNotEmpty) {
      _symbolsWithCurrencyChanges.add(canonicalSymbol);
    }
  } on TimeoutException {
    talker.warning('Symbol currency metadata timed out for $canonicalSymbol');
  } catch (error, stackTrace) {
    talker.handle(error, stackTrace, 'Failed to resolve symbol currency');
  }
}

/// Formats [v] (assumed to be in USD) in the user's display currency.
String fmtCurrency(double usdValue) {
  if (maskCurrencyAmounts) return '••••';
  final rate = allRatesFromUsd[currency.currencyName ?? 'USD'];
  if (rate == null || !rate.isFinite || rate <= 0) return '—';
  return currency.format(usdValue * rate);
}

/// Formats [v] which is denominated in [nativeCurrency], converting it to the
/// user's chosen display currency via the cached cross-rates.
///
/// Example: fmtNativeCurrency(1370.0, 'INR') with display=USD and
/// allRatesFromUsd['INR']=84 → formats 1370/84 ≈ $16.31.
String fmtNativeCurrency(double nativeValue, String nativeCurrency) {
  final nativeRate = requireUsdRate(nativeCurrency);
  return fmtCurrency(nativeValue / nativeRate);
}

/// Compact display-currency label for chart axes (e.g. $1.2K).
String fmtCompactCurrency(double usdValue) {
  if (maskCurrencyAmounts) return '••••';
  final rate = allRatesFromUsd[currency.currencyName ?? 'USD'];
  if (rate == null || !rate.isFinite || rate <= 0) return '—';
  return NumberFormat.compactCurrency(symbol: currency.currencySymbol)
      .format(usdValue * rate);
}

/// Compact axis label for [v] denominated in [nativeCurrency].
String fmtCompactNativeCurrency(double nativeValue, String nativeCurrency) {
  final nativeRate = requireUsdRate(nativeCurrency);
  return fmtCompactCurrency(nativeValue / nativeRate);
}

/// Formats percentage axis values without letting large labels dominate the
/// chart. Values at 1,000% and above are abbreviated (for example +35K%).
String fmtChartAxisPercent(double value) {
  final absolute = value.abs();
  final magnitude = absolute >= 1000
      ? NumberFormat.compact().format(absolute)
      : NumberFormat('#,##0.#').format(absolute);
  final sign = switch (true) {
    _ when value > 0 => '+',
    _ when value < 0 => '-',
    _ => '',
  };
  return '$sign$magnitude%';
}

/// Returns the [NumberFormat.currencySymbol] for [nativeCurrency].
String nativeCurrencySymbol(String nativeCurrency) =>
    NumberFormat.simpleCurrency(name: nativeCurrency).currencySymbol;

double safePercentChange(double oldValue, double newValue) {
  if (oldValue == 0) return 0;
  return ((newValue - oldValue) / oldValue) * 100;
}
