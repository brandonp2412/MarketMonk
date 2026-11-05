import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:market_monk/crypto_market_data.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/utils.dart';

void main() {
  final monero = cryptoAssetForSymbol('xmr-usd')!;

  test('crypto search uses the existing ticker identity', () async {
    expect(searchCryptoAssets('xmr').single.symbol, 'XMR-USD');
    expect(searchCryptoAssets('monero').single.symbol, 'XMR-USD');
    expect(searchCryptoAssets('unknown'), isEmpty);
    expect(cryptoAssetForSymbol('DOGE-USD')!.krakenPair, 'XDGUSD');

    final search = YahooFinanceApi(
      searchFetcher: (_) async => http.Response('unavailable', 503),
    );
    addTearDown(search.dispose);
    final results = await search.searchTickers('XMR');
    expect(results.first.symbol, 'XMR-USD');
    expect(results.first.exchange, 'Crypto');
  });

  test('current quote uses DefiLlama without authentication', () async {
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final service = CryptoMarketData(
      fetch: (uri) async {
        expect(uri.host, 'coins.llama.fi');
        expect(uri.path, '/prices/current/coingecko:monero');
        return http.Response(
            jsonEncode({
              'coins': {
                'coingecko:monero': {'price': 638.25, 'timestamp': timestamp},
              },
            }),
            200,
        );
      },
    );
    final quote = await service.currentPrice(monero);
    expect(quote.priceUsd, 638.25);
    expect(quote.source, 'DefiLlama');
  });

  test('Kraken supplies current prices when DefiLlama is unavailable',
      () async {
    final service = CryptoMarketData(
      fetch: (uri) async {
        if (uri.host == 'coins.llama.fi') return http.Response('', 503);
        expect(uri.queryParameters['pair'], 'XMRUSD');
        return http.Response(
            jsonEncode({
              'error': [],
              'result': {
                'XXMRZUSD': {
                  'c': ['641.75', '0.1'],
                },
              },
            }),
            200,
        );
      },
    );
    final quote = await service.currentPrice(monero);
    expect(quote.priceUsd, 641.75);
    expect(quote.source, 'Kraken');
  });

  test('Kraken intraday has real OHLC and filters old bars', () async {
    final recent = DateTime.now().toUtc().subtract(const Duration(minutes: 10));
    final old = DateTime.now().toUtc().subtract(const Duration(days: 2));
    final service = CryptoMarketData(
      fetch: (uri) async {
        expect(uri.queryParameters['interval'], '5');
        return http.Response(
            jsonEncode({
              'error': [],
              'result': {
                'XXMRZUSD': [
                  [
                    old.millisecondsSinceEpoch ~/ 1000,
                    '10',
                    '12',
                    '9',
                    '11',
                    '11',
                    '4.1',
                    1,
                  ],
                  [
                    recent.millisecondsSinceEpoch ~/ 1000,
                    '600',
                    '610',
                    '590',
                    '605',
                    '604',
                    '10.5',
                    5,
                  ],
                ],
                'last': 123,
              },
            }),
            200,
        );
      },
    );
    final bars = await service.intradayHistory(monero, days: 1);
    expect(bars, hasLength(1));
    expect(bars.single.open, 600);
    expect(bars.single.high, 610);
    expect(bars.single.low, 590);
    expect(bars.single.close, 605);
    expect(bars.single.volume, 11);
  });

  test('long history stays within the provider 500-point limit', () async {
    final now = DateTime.now().toUtc();
    final from = now.subtract(const Duration(days: 1100));
    final timestamp = now.millisecondsSinceEpoch ~/ 1000;
    var requests = 0;
    final service = CryptoMarketData(
      fetch: (uri) async {
        if (uri.path.startsWith('/prices/current/')) {
          return http.Response(jsonEncode({
            'coins': {
              'coingecko:monero': {'price': 650.0, 'timestamp': timestamp},
            },
          }), 200,);
        }
        requests++;
        final span = int.parse(uri.queryParameters['span']!);
        expect(span, inInclusiveRange(1, 500));
        final start = int.parse(uri.queryParameters['start']!);
        return http.Response(jsonEncode({
          'coins': {
            'coingecko:monero': {
              'prices': [
                {'timestamp': start, 'price': 500.0 + requests},
              ],
            },
          },
        }), 200,);
      },
    );
    final bars = await service.dailyHistory(monero, from);
    expect(requests, 3);
    expect(bars, hasLength(4));
    expect(bars.last.close, 650.0);
  });

  test(
      'daily crypto prices populate existing SQLite candles without a migration',
      () async {
    final database = Database.connect(NativeDatabase.memory());
    addTearDown(database.close);
    final now = DateTime.now().toUtc();
    final yesterday = DateTime.utc(now.year, now.month, now.day - 1);
    final timestamp = now.millisecondsSinceEpoch ~/ 1000;
    var calls = 0;
    final service = CryptoMarketData(
      fetch: (uri) async {
        calls++;
        if (uri.path.startsWith('/prices/current/')) {
          return http.Response(
              jsonEncode({
                'coins': {
                  'coingecko:monero': {'price': 640.0, 'timestamp': timestamp},
                },
              }),
              200,
          );
        }
        expect(uri.path, '/chart/coingecko:monero');
        return http.Response(
            jsonEncode({
              'coins': {
                'coingecko:monero': {
                  'prices': [
                    {
                      'timestamp': yesterday.millisecondsSinceEpoch ~/ 1000 - 2,
                      'price': 630.0,
                    },
                  ],
                },
              },
            }),
            200,
        );
      },
    );
    Future<void> sync() => syncCandles(
          ' xmr-usd ',
          database: database,
          cryptoMarketData: service,
          requiredFrom: yesterday,
        );
    await sync();
    final rows = await database.readCandles('XMR-USD');
    expect(rows, hasLength(2));
    expect(rows.map((row) => row.close), [630.0, 640.0]);
    expect(rows.every((row) => row.rawCurrency == 'USD'), isTrue);
    final afterFirst = calls;
    await sync();
    expect(calls, afterFirst);
  });
}
