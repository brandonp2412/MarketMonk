import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'visibleCurrencies': ['GBP', 'NZD', 'USD'],
      'displayCurrency': 'GBP',
      'exchangeRate_GBP': 0.8,
      'exchangeRate_NZD': 1.6,
      'exchangeRate_USD': 1.0,
    });
    allRatesFromUsd
      ..clear()
      ..['USD'] = 1.0;
    currency = NumberFormat.simpleCurrency(name: 'USD');
  });

  test('locale currency detection respects the device region', () {
    expect(SettingsState.currencyForLocale(const Locale('en', 'NZ')), 'NZD');
    expect(SettingsState.currencyForLocale(const Locale('en', 'GB')), 'GBP');
    expect(SettingsState.currencyForLocale(const Locale('en', 'US')), 'USD');
  });

  testWidgets('fresh install uses the Flutter device locale', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.binding.platformDispatcher.localeTestValue =
        const Locale('en', 'NZ');
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);

    final settings = SettingsState(
      rateFetcher: (_) async => http.Response('{"rates":{"NZD":1.6}}', 200),
    );
    await settings.initialized;

    expect(settings.displayCurrency, 'NZD');
    expect(settings.visibleCurrencies, ['NZD', 'USD']);
    expect(currency.currencyName, 'NZD');
  });

  test('removing the active currency immediately activates the fallback',
      () async {
    final settings = SettingsState();
    await settings.initialized;

    expect(settings.displayCurrency, 'GBP');
    expect(currency.currencyName, 'GBP');

    await settings.setVisibleCurrencies(['NZD', 'USD']);

    expect(settings.displayCurrency, 'NZD');
    expect(currency.currencyName, 'NZD');
    expect(exchangeRate, 1.6);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('displayCurrency'), 'NZD');
  });

  test('changing display currency switches the formatter immediately',
      () async {
    final settings = SettingsState();
    await settings.initialized;

    await settings.setDisplayCurrency('USD');

    expect(settings.displayCurrency, 'USD');
    expect(currency.currencyName, 'USD');
    expect(exchangeRate, 1.0);
  });

  test('stale exchange-rate responses cannot restore an old currency',
      () async {
    final gbpResponse = Completer<http.Response>();
    final nzdResponse = Completer<http.Response>();
    final settings = SettingsState(
      rateFetcher: (uri) {
        final target = uri.queryParameters['to'];
        if (target == 'GBP') return gbpResponse.future;
        if (target == 'NZD') return nzdResponse.future;
        return Future.value(http.Response('{"rates":{}}', 200));
      },
    );
    await settings.initialized;

    await settings.setDisplayCurrency('NZD');
    nzdResponse.complete(http.Response('{"rates":{"NZD":1.7}}', 200));
    await Future<void>.delayed(Duration.zero);

    gbpResponse.complete(http.Response('{"rates":{"GBP":0.8}}', 200));
    await Future<void>.delayed(Duration.zero);

    expect(settings.displayCurrency, 'NZD');
    expect(currency.currencyName, 'NZD');
    expect(exchangeRate, 1.7);
  });

  test('ticker sync reports progress and refreshes portfolio data', () async {
    final settings = SettingsState();
    await settings.initialized;
    final synced = <String>[];
    final initialVersion = settings.tradesVersion;

    await settings.syncTickers(['MSFT', 'AAPL', 'AAPL'], (symbol) async {
      synced.add(symbol);
    });

    expect(synced, ['AAPL', 'MSFT']);
    expect(settings.syncInProgress, isFalse);
    expect(settings.syncCompleted, 2);
    expect(settings.syncTotal, 2);
    expect(settings.syncFailed, 0);
    expect(settings.syncingSymbol, isNull);
    expect(settings.syncProgress, 1.0);
    expect(settings.tradesVersion, initialVersion + 1);
  });

  test('ticker sync continues after an individual ticker fails', () async {
    final settings = SettingsState();
    await settings.initialized;
    final synced = <String>[];

    await settings.syncTickers(['AAPL', 'FAIL', 'MSFT'], (symbol) async {
      synced.add(symbol);
      if (symbol == 'FAIL') throw StateError('network failed');
    });

    expect(synced, ['AAPL', 'FAIL', 'MSFT']);
    expect(settings.syncCompleted, 3);
    expect(settings.syncFailed, 1);
    expect(settings.lastSyncError, contains('network failed'));
    expect(settings.syncInProgress, isFalse);
  });

  test('ticker sync queues requests made while another sync is running',
      () async {
    final settings = SettingsState();
    await settings.initialized;
    final synced = <String>[];
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();

    final first = settings.syncTickers(['AAPL'], (symbol) async {
      synced.add(symbol);
      firstStarted.complete();
      await releaseFirst.future;
    });
    await firstStarted.future;
    final second = settings.syncTickers(['MSFT'], (symbol) async {
      synced.add(symbol);
    });

    expect(synced, ['AAPL']);
    releaseFirst.complete();
    await Future.wait([first, second]);

    expect(synced, ['AAPL', 'MSFT']);
    expect(settings.syncInProgress, isFalse);
  });
}
