import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:market_monk/background_network_coordinator.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/intraday_market_data.dart';

import 'test_log_support.dart';

const _config = IbkrAccountConfig(
  enabled: true,
  baseUrl: 'https://intraday.example.test',
  token: 'test-token',
);

http.Response _yahooResponse({String currency = 'USD'}) => http.Response(
      jsonEncode({
        'chart': {
          'error': null,
          'result': [
            {
              'meta': {'currency': currency},
              'timestamp': [1791552660, 1791552600, 1791552720, 1791552660],
              'indicators': {
                'quote': [
                  {
                    'open': [101, 100, null, 102],
                    'high': [102, 101, null, 103],
                    'low': [100, 99, null, 101],
                    'close': [101.5, 100.5, null, 102.5],
                    'volume': [10, 20, null, 30],
                  },
                ],
              },
            },
          ],
        },
      }),
      200,
    );

IbkrHistoricalSeries _ibkrSeries({bool empty = false, bool daily = false}) =>
    IbkrHistoricalSeries(
      symbol: 'AAPL',
      currency: 'NZD',
      candles: empty
          ? []
          : [
              IbkrHistoricalCandle(
                date: daily
                    ? DateTime(2026, 10, 9)
                    : DateTime.utc(2026, 10, 9, 14),
                open: 100,
                high: 102,
                low: 99,
                close: 101,
                volume: 1000,
              ),
            ],
    );

void main() {
  setUp(silenceTalkerForTest);

  test(
    'Yahoo uses minute parameters and preserves timestamps and cent units',
    () async {
      late Uri request;
      final loader = IntradayMarketData(
        yahooGet: (uri) async {
          request = uri;
          return _yahooResponse(currency: 'GBp');
        },
      );
      final series = await loader.fetch(' vod.l ');
      expect(request.path, '/v8/finance/chart/VOD.L');
      expect(request.queryParameters, {
        'range': '1d',
        'interval': '1m',
        'includePrePost': 'false',
      });
      expect(series.currency, 'GBp');
      expect(series.source, 'Yahoo');
      expect(series.candles, hasLength(2));
      expect(series.candles.first.date.millisecondsSinceEpoch, 1791552600000);
      expect(
        series.candles.last.date.difference(series.candles.first.date),
        const Duration(minutes: 1),
      );
      expect(series.candles.last.close, 102.5);
      expect(series.candles.last.volume, 30);
      expect(() => series.candles.clear(), throwsUnsupportedError);
    },
  );

  test('five days uses 15-minute Yahoo bars', () async {
    late Uri request;
    final loader = IntradayMarketData(
      yahooGet: (uri) async {
        request = uri;
        return _yahooResponse();
      },
    );
    await loader.fetch('AAPL', days: 5);
    expect(request.queryParameters['range'], '5d');
    expect(request.queryParameters['interval'], '15m');
  });

  test('configured IBKR is preferred without calling Yahoo', () async {
    final loader = IntradayMarketData(
      yahooGet: (_) async => throw StateError('Yahoo should not be used'),
      ibkrFetch: (config, symbol, days) async {
        expect(config, _config);
        expect(symbol, 'AAPL');
        expect(days, 5);
        return _ibkrSeries();
      },
    );
    final series = await loader.fetch('aapl', days: 5, config: _config);
    expect(series.source, 'IBKR');
    expect(series.currency, 'NZD');
    expect(series.candles.single.date, DateTime.utc(2026, 10, 9, 14));
  });

  for (final failure in ['subscription', 'empty', 'daily']) {
    test('falls back to Yahoo for IBKR $failure data', () async {
      final loader = IntradayMarketData(
        yahooGet: (_) async => _yahooResponse(),
        ibkrFetch: (_, __, ___) async {
          if (failure == 'subscription')
            throw StateError('No market data permission');
          return _ibkrSeries(
            empty: failure == 'empty',
            daily: failure == 'daily',
          );
        },
      );
      expect((await loader.fetch('AAPL', config: _config)).source, 'Yahoo');
    });
  }

  test(
    'cache expires after five minutes and forced refresh bypasses it',
    () async {
      var now = DateTime.utc(2026, 10, 9, 14);
      var calls = 0;
      final loader = IntradayMarketData(
        now: () => now,
        yahooGet: (_) async {
          calls++;
          return _yahooResponse();
        },
      );
      final first = await loader.fetch('AAPL');
      expect(await loader.fetch('aapl'), same(first));
      expect(calls, 1);
      await loader.fetch('AAPL', forceRefresh: true);
      expect(calls, 2);
      now = now.add(const Duration(minutes: 5));
      await loader.fetch('AAPL');
      expect(calls, 3);
      await loader.fetch('AAPL', days: 5);
      expect(calls, 4);
    },
  );

  test(
    'portfolio batch seeds individual prices without repeated broker requests',
    () async {
      var batches = 0;
      var individual = 0;
      final loader = IntradayMarketData(
        ibkrPortfolioFetch: (_, days) async {
          batches++;
          return [_ibkrSeries()];
        },
        ibkrFetch: (_, symbol, days) async {
          individual++;
          return _ibkrSeries();
        },
        yahooGet: (_) async =>
            throw StateError('Yahoo should not be requested'),
      );
      expect(await loader.prefetchPortfolio(_config, days: 5), isTrue);
      final series = await loader.fetch('AAPL', config: _config, days: 5);
      expect(series.source, 'IBKR');
      expect(await loader.prefetchPortfolio(_config, days: 5), isTrue);
      expect(batches, 1);
      expect(individual, 0);
      await loader.prefetchPortfolio(_config, days: 5, forceRefresh: true);
      expect(batches, 2);
      await loader.prefetchPortfolio(_config, days: 1);
      expect(batches, 3);
    },
  );

  test('broker timeout while paused retries on resume before fallback',
      () async {
    addTearDown(() {
      backgroundNetworkCoordinator.didChangeAppLifecycleState(
        AppLifecycleState.resumed,
      );
    });
    final started = Completer<void>();
    final interrupted = Completer<IbkrHistoricalSeries>();
    var brokerCalls = 0;
    var yahooCalls = 0;
    final loader = IntradayMarketData(
      brokerTimeout: const Duration(milliseconds: 5),
      ibkrFetch: (_, __, ___) {
        brokerCalls++;
        if (brokerCalls == 1) {
          started.complete();
          return interrupted.future;
        }
        return Future.value(_ibkrSeries());
      },
      yahooGet: (_) async {
        yahooCalls++;
        return _yahooResponse();
      },
    );
    final result = loader.fetch('AAPL', config: _config);
    await started.future;
    backgroundNetworkCoordinator
        .didChangeAppLifecycleState(AppLifecycleState.paused);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(brokerCalls, 1);
    expect(yahooCalls, 0);

    backgroundNetworkCoordinator
        .didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect((await result).source, 'IBKR');
    expect(brokerCalls, 2);
    expect(yahooCalls, 0);
  });

  test('batch failure does not prevent an immediate broker retry', () async {
    var batches = 0;
    final loader = IntradayMarketData(
      ibkrPortfolioFetch: (_, __) async {
        batches++;
        if (batches == 1) throw http.ClientException('connection interrupted');
        return [_ibkrSeries()];
      },
      ibkrFetch: (_, __, ___) async => _ibkrSeries(),
    );

    expect(await loader.prefetchPortfolio(_config, days: 1), isFalse);
    expect((await loader.fetch('MSFT', config: _config)).source, 'IBKR');
    expect(await loader.prefetchPortfolio(_config, days: 1), isTrue);
    expect(batches, 2);
  });

  test('account config changes do not reuse another account cache', () async {
    var calls = 0;
    final loader = IntradayMarketData(
      ibkrFetch: (_, __, ___) async {
        calls++;
        return _ibkrSeries();
      },
    );
    await loader.fetch('AAPL', config: _config);
    await loader.fetch('AAPL', config: _config.copyWith(token: 'new-token'));
    expect(calls, 2);
  });

  test(
    'concurrent requests coalesce and failed requests can be retried',
    () async {
      final response = Completer<http.Response>();
      var calls = 0;
      final loader = IntradayMarketData(
        yahooGet: (_) {
          calls++;
          return calls == 1 ? response.future : Future.value(_yahooResponse());
        },
      );
      final first = loader.fetch('AAPL');
      final second = loader.fetch('AAPL');
      final assertions = Future.wait([
        expectLater(first, throwsStateError),
        expectLater(second, throwsStateError),
      ]);
      response.complete(http.Response('not found', 404));
      await assertions;
      expect(calls, 1);
      expect((await loader.fetch('AAPL')).candles, hasLength(2));
      expect(calls, 2);
    },
  );

  test(
    'Yahoo automatically retries HTTP 429 through its alternate host',
    () async {
      final hosts = <String>[];
      final delays = <Duration>[];
      final loader = IntradayMarketData(
        retryDelay: (delay) async => delays.add(delay),
        yahooGet: (uri) async {
          hosts.add(uri.host);
          return hosts.length == 1
              ? http.Response('rate limited', 429)
              : _yahooResponse();
        },
      );
      final series = await loader.fetch('NVDA');
      expect(series.candles, hasLength(2));
      expect(hosts, ['query1.finance.yahoo.com', 'query2.finance.yahoo.com']);
      expect(delays, [const Duration(milliseconds: 400)]);
    },
  );

  test(
    'repeated Yahoo 429 exposes the HTTP status after bounded retries',
    () async {
      var calls = 0;
      final loader = IntradayMarketData(
        retryDelay: (_) async {},
        yahooGet: (_) async {
          calls++;
          return http.Response('rate limited', 429);
        },
      );
      await expectLater(
        loader.fetch('NVDA'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('HTTP 429'),
          ),
        ),
      );
      expect(calls, 3);
    },
  );

  test(
    'parallel Yahoo requests never exceed two active HTTP requests',
    () async {
      final pending = <Completer<http.Response>>[];
      var active = 0;
      var maximumActive = 0;
      final loader = IntradayMarketData(
        yahooGet: (uri) async {
          active++;
          if (active > maximumActive) maximumActive = active;
          final reply = Completer<http.Response>();
          pending.add(reply);
          try {
            return await reply.future;
          } finally {
            active--;
          }
        },
      );
      final requests = [
        loader.fetch('AAPL'),
        loader.fetch('MSFT'),
        loader.fetch('NVDA'),
      ];
      await Future<void>.delayed(Duration.zero);
      expect(pending, hasLength(2));
      pending.first.complete(_yahooResponse());
      await Future<void>.delayed(Duration.zero);
      expect(pending, hasLength(3));
      expect(maximumActive, 2);
      for (final reply in pending.skip(1)) {
        reply.complete(_yahooResponse());
      }
      await Future.wait(requests);
      expect(active, 0);
    },
  );

  test('empty and error Yahoo responses report unavailable data', () async {
    for (final body in [
      {
        'chart': {
          'result': null,
          'error': {'code': 'Not Found'},
        },
      },
      {
        'chart': {'result': [], 'error': null},
      },
    ]) {
      final loader = IntradayMarketData(
        yahooGet: (_) async => http.Response(jsonEncode(body), 200),
      );
      await expectLater(loader.fetch('MISSING'), throwsStateError);
    }
  });

  test('rejects unsupported ranges before requesting a provider', () {
    final loader = IntradayMarketData();
    expect(() => loader.fetch('AAPL', days: 30), throwsArgumentError);
  });

  test(
    'IBKR client requests new endpoint and rejects daily-only responses',
    () async {
      late Uri request;
      final client = IbkrApiClient(
        _config,
        get: (uri, {headers}) async {
          request = uri;
          expect(headers?['Authorization'], 'Bearer test-token');
          return http.Response(
            jsonEncode({
              'symbol': 'AAPL',
              'currency': 'USD',
              'interval': '1m',
              'candles': [
                {
                  'date': '2026-10-09T14:00:00+00:00',
                  'open': 100,
                  'high': 102,
                  'low': 99,
                  'close': 101,
                  'volume': 1000,
                },
              ],
            }),
            200,
          );
        },
      );
      final series = await client.fetchIntradayCandles('AAPL');
      expect(request.path, '/v1/intraday');
      expect(request.queryParameters, {'symbol': 'AAPL', 'days': '1'});
      expect(series.candles.single.date, DateTime.utc(2026, 10, 9, 14));
      final oldClient = IbkrApiClient(
        _config,
        get: (_, {headers}) async =>
            http.Response('{"interval":"1d","candles":[]}', 200),
      );
      await expectLater(
        oldClient.fetchIntradayCandles('AAPL'),
        throwsStateError,
      );
    },
  );
}
