import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:market_monk/exchange_rate_service.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/utils.dart';

import 'sqlite_test_support.dart';
import 'test_log_support.dart';

final fixedNow = DateTime.now().toUtc();
final recentRateDate = DateTime.utc(fixedNow.year, fixedNow.month, fixedNow.day)
    .subtract(const Duration(days: 1));
String rateDateString(DateTime date) => date.toIso8601String().substring(0, 10);

http.Response frankfurter(double rate, {String? date}) => http.Response(
      jsonEncode({
        'date': date ?? rateDateString(recentRateDate),
        'base': 'USD',
        'quote': 'NZD',
        'rate': rate,
      }),
      200,
    );

http.Response exchangeApi(double rate, {String? date}) => http.Response(
      jsonEncode({
        'date': date ?? rateDateString(recentRateDate),
        'usd': {'nzd': rate},
      }),
      200,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    silenceTalkerForTest();
    await seedTestSqlite({
      'displayCurrency': 'USD',
      'visibleCurrencies': ['USD', 'NZD'],
      'exchangeRate_USD': 1.0,
    });
    allRatesFromUsd
      ..clear()
      ..['USD'] = 1.0;
    currency = NumberFormat.simpleCurrency(name: 'USD');
  });

  test('Frankfurter v2 takes precedence over both CDNs', () async {
    final hosts = <String>[];
    final quote = await fetchUsdRate(
      'NZD',
      clock: () => fixedNow,
      fetcher: (uri) async {
        hosts.add(uri.host);
        return frankfurter(1.77);
      },
    );
    expect(quote.rate, 1.77);
    expect(quote.provider, 'frankfurter');
    expect(quote.rateDate, recentRateDate);
    expect(hosts, ['api.frankfurter.dev']);
  });

  test('jsDelivr fallback converts USD and native currency values', () async {
    final settings = SettingsState(
      localCurrencyDetector: () async => 'USD',
      rateFetcher: (uri) async {
        if (uri.host == 'api.frankfurter.dev') {
          return http.Response('Unavailable', 503);
        }
        return exchangeApi(1.75);
      },
    );
    await settings.initialized;
    await settings.setDisplayCurrency('NZD');
    await _waitForRate('NZD', 1.75);

    expect(fmtCurrency(10), currency.format(17.5));
    expect(fmtNativeCurrency(17.5, 'NZD'), currency.format(17.5));
    final prefs = await SqliteSettings.getInstance();
    final stored = readCachedUsdRate('NZD', prefs, clock: () => DateTime.now());
    expect(stored?.provider, 'exchangeApiJsdelivr');
    expect(stored?.rateDate, isNotNull);
    expect(stored?.retrievedAt, isNotNull);
  });

  test('Cloudflare fallback works after two independent HTTP errors', () async {
    final hosts = <String>[];
    final quote = await fetchUsdRate(
      'NZD',
      clock: () => fixedNow,
      fetcher: (uri) async {
        hosts.add(uri.host);
        if (uri.host == 'api.frankfurter.dev') {
          return http.Response('Unavailable', 503);
        }
        if (uri.host == 'cdn.jsdelivr.net') {
          return http.Response('Too many requests', 429);
        }
        return exchangeApi(1.74);
      },
    );
    expect(quote.provider, 'exchangeApiCloudflare');
    expect(quote.rate, 1.74);
    expect(hosts, [
      'api.frankfurter.dev',
      'cdn.jsdelivr.net',
      'latest.currency-api.pages.dev',
    ]);
  });

  test('stalled primary expires before jsDelivr is attempted', () async {
    final never = Completer<http.Response>();
    final hosts = <String>[];
    final quote = await fetchUsdRate(
      'NZD',
      clock: () => fixedNow,
      timeout: const Duration(milliseconds: 20),
      fetcher: (uri) {
        hosts.add(uri.host);
        if (uri.host == 'api.frankfurter.dev') return never.future;
        return Future.value(exchangeApi(1.73));
      },
    ).timeout(const Duration(seconds: 1));
    expect(quote.provider, 'exchangeApiJsdelivr');
    expect(hosts, ['api.frankfurter.dev', 'cdn.jsdelivr.net']);
  });

  test('all HTTP failures are reported and last cached rate is retained',
      () async {
    final prefs = await SqliteSettings.getInstance();
    await prefs.setDouble('exchangeRate_NZD', 1.69);
    final responseCodes = [503, 429, 503];
    var calls = 0;
    await expectLater(
      refreshUsdRate(
        'NZD',
        clock: () => fixedNow,
        fetcher: (_) async => http.Response('Failed', responseCodes[calls++]),
      ),
      throwsA(
        isA<FxRateFetchException>().having(
          (e) => e.failures.join(' '),
          'failures',
          allOf(contains('HTTP 503'), contains('HTTP 429')),
        ),
      ),
    );
    expect(calls, 3);
    expect(prefs.getDouble('exchangeRate_NZD'), 1.69);
    expect(prefs.getString('exchangeRateQuote_NZD'), isNull);
  });

  test('invalid and stale provider rates are rejected', () async {
    final quote = await fetchUsdRate(
      'NZD',
      clock: () => fixedNow,
      fetcher: (uri) async {
        if (uri.host == 'api.frankfurter.dev') {
          return frankfurter(double.nan);
        }
        if (uri.host == 'cdn.jsdelivr.net') {
          return exchangeApi(
            1.9,
            date: rateDateString(
              recentRateDate.subtract(const Duration(days: 30)),
            ),
          );
        }
        return exchangeApi(1.76);
      },
    );
    expect(quote.provider, 'exchangeApiCloudflare');
    expect(quote.rate, 1.76);
  });

  test('expired cached rates are rejected without deleting saved values',
      () async {
    final prefs = await SqliteSettings.getInstance();
    await prefs.setString(
      'exchangeRateQuote_NZD',
      jsonEncode({
        'currency': 'NZD',
        'rate': 1.66,
        'provider': 'frankfurter',
        'rateDate': '2026-10-01',
        'retrievedAt': '2026-10-01T12:00:00.000Z',
      }),
    );
    await prefs.setDouble('exchangeRate_NZD', 1.66);
    expect(readCachedUsdRate('NZD', prefs, clock: () => fixedNow), isNull);
    expect(prefs.getDouble('exchangeRate_NZD'), 1.66);
  });

  test('Frankfurter source supports display and native conversion', () async {
    final settings = SettingsState(
      localCurrencyDetector: () async => 'USD',
      rateFetcher: (_) async => frankfurter(1.8),
    );
    await settings.initialized;
    await settings.setDisplayCurrency('NZD');
    await _waitForRate('NZD', 1.8);
    expect(fmtCurrency(10), currency.format(18));
    expect(fmtNativeCurrency(18, 'NZD'), currency.format(18));
  });
}

Future<void> _waitForRate(String code, double expected) async {
  for (var i = 0; i < 100; i++) {
    if (allRatesFromUsd[code] == expected) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Expected $code rate $expected, got ${allRatesFromUsd[code]}');
}
