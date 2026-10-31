import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:market_monk/background_network_coordinator.dart';
import 'package:market_monk/logging.dart';
import 'package:market_monk/sqlite_settings.dart';

typedef FxRateFetcher = Future<http.Response> Function(Uri);

const fxRequestTimeout = Duration(seconds: 4);
const fxMaxRateAge = Duration(days: 7);

class FxRateQuote {
  const FxRateQuote({
    required this.currencyCode,
    required this.rate,
    required this.provider,
    required this.rateDate,
    required this.retrievedAt,
  });

  final String currencyCode;
  final double rate;
  final String provider;
  final DateTime rateDate;
  final DateTime retrievedAt;

  Map<String, Object> toJson() => {
        'currency': currencyCode,
        'rate': rate,
        'provider': provider,
        'rateDate': _dateString(rateDate),
        'retrievedAt': retrievedAt.toUtc().toIso8601String(),
      };
}

class FxRateFetchException implements Exception {
  const FxRateFetchException(this.currencyCode, this.failures);

  final String currencyCode;
  final List<String> failures;

  @override
  String toString() =>
      'Exchange rate unavailable for USD/$currencyCode: ${failures.join('; ')}';
}

String _dateString(DateTime date) =>
    date.toUtc().toIso8601String().substring(0, 10);

DateTime _parseDate(Object? value) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw const FormatException('Missing or invalid rate date');
  }
  final parts = value.split('-');
  final date = DateTime.utc(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
  if (_dateString(date) != value) {
    throw const FormatException('Invalid rate date');
  }
  return date;
}

void _checkQuote(FxRateQuote quote, DateTime now) {
  if (!quote.rate.isFinite || quote.rate <= 0) {
    throw const FormatException('Invalid exchange-rate value');
  }
  final today = DateTime.utc(now.year, now.month, now.day);
  if (quote.rateDate.isAfter(today) ||
      today.difference(quote.rateDate) > fxMaxRateAge) {
    throw const FormatException('Exchange-rate data is stale or future-dated');
  }
  if (quote.retrievedAt.isAfter(now.add(const Duration(minutes: 5)))) {
    throw const FormatException('Invalid retrieval timestamp');
  }
}

Future<http.Response> _getWithDeadline(
  Uri uri,
  FxRateFetcher? fetcher,
  Duration timeout,
) async {
  if (fetcher != null) return fetcher(uri).timeout(timeout);
  final client = http.Client();
  try {
    return await client.get(uri).timeout(timeout);
  } finally {
    client.close();
  }
}

Future<FxRateQuote> fetchUsdRate(
  String currencyCode, {
  FxRateFetcher? fetcher,
  Duration timeout = fxRequestTimeout,
  DateTime Function()? clock,
}) async {
  final code = currencyCode.toUpperCase();
  if (!RegExp(r'^[A-Z]{3}$').hasMatch(code)) {
    throw ArgumentError.value(currencyCode, 'currencyCode');
  }
  final now = (clock?.call() ?? DateTime.now()).toUtc();
  final sources = <(String, Uri)>[
    ('frankfurter', Uri.parse('https://api.frankfurter.dev/v2/rate/USD/$code')),
    (
      'exchangeApiJsdelivr',
      Uri.parse(
        'https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.json',
      ),
    ),
    (
      'exchangeApiCloudflare',
      Uri.parse('https://latest.currency-api.pages.dev/v1/currencies/usd.json'),
    ),
  ];
  final failures = <String>[];

  for (final (provider, uri) in sources) {
    try {
      final response = await _getWithDeadline(uri, fetcher, timeout);
      if (response.statusCode != 200) {
        throw StateError('HTTP ${response.statusCode}');
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final rawRate = provider == 'frankfurter'
          ? json['rate']
          : (json['usd'] as Map<String, dynamic>?)?[code.toLowerCase()];
      if (rawRate is! num) {
        throw const FormatException('Missing numeric exchange rate');
      }
      if (provider == 'frankfurter' &&
          (json['base'] != 'USD' || json['quote'] != code)) {
        throw const FormatException('Currency pair mismatch');
      }
      final quote = FxRateQuote(
        currencyCode: code,
        rate: rawRate.toDouble(),
        provider: provider,
        rateDate: _parseDate(json['date']),
        retrievedAt: now,
      );
      _checkQuote(quote, now);
      return quote;
    } catch (error) {
      failures.add('$provider: $error');
      talker.warning('Exchange-rate provider $provider failed: $error');
    }
  }
  throw FxRateFetchException(code, failures);
}

Future<FxRateQuote> refreshUsdRate(
  String currencyCode, {
  FxRateFetcher? fetcher,
  Duration timeout = fxRequestTimeout,
  DateTime Function()? clock,
}) =>
    backgroundNetworkCoordinator.coalesce<FxRateQuote>(
      RequestCategory.fxRate,
      currencyCode.toUpperCase(),
      () async {
        final quote = await fetchUsdRate(
          currencyCode,
          fetcher: fetcher,
          timeout: timeout,
          clock: clock,
        );
        final prefs = await SqliteSettings.getInstance();
        await prefs.setString(
          'exchangeRateQuote_${quote.currencyCode}',
          jsonEncode(quote.toJson()),
        );
        await prefs.setDouble('exchangeRate_${quote.currencyCode}', quote.rate);
        return quote;
      },
    );

FxRateQuote? readCachedUsdRate(
  String currencyCode,
  SqliteSettings prefs, {
  DateTime Function()? clock,
}) {
  final now = (clock?.call() ?? DateTime.now()).toUtc();
  final serialized = prefs.getString('exchangeRateQuote_$currencyCode');
  if (serialized != null) {
    try {
      final json = jsonDecode(serialized) as Map<String, dynamic>;
      final rate = json['rate'];
      final provider = json['provider'];
      final retrievedAt = DateTime.tryParse(json['retrievedAt'] as String);
      if (json['currency'] != currencyCode ||
          rate is! num ||
          provider is! String ||
          !{'frankfurter', 'exchangeApiJsdelivr', 'exchangeApiCloudflare'}
              .contains(provider) ||
          retrievedAt == null) {
        throw const FormatException('Invalid cached exchange-rate metadata');
      }
      final quote = FxRateQuote(
        currencyCode: currencyCode,
        rate: rate.toDouble(),
        provider: provider,
        rateDate: _parseDate(json['rateDate']),
        retrievedAt: retrievedAt.toUtc(),
      );
      _checkQuote(quote, now);
      return quote;
    } catch (error) {
      talker.warning(
        'Ignoring invalid cached exchange rate for $currencyCode: $error',
      );
      return null;
    }
  }

  final legacyRate = prefs.getDouble('exchangeRate_$currencyCode');
  if (legacyRate == null || !legacyRate.isFinite || legacyRate <= 0) {
    return null;
  }
  return FxRateQuote(
    currencyCode: currencyCode,
    rate: legacyRate,
    provider: 'legacy',
    rateDate: DateTime.utc(now.year, now.month, now.day),
    retrievedAt: now,
  );
}
