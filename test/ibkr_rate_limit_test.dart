import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/ibkr_candle_failure_notice.dart';

void main() {
  const config = IbkrAccountConfig(
    enabled: true,
    baseUrl: 'https://ibkr.example.test',
    token: 'test-token',
  );

  test(
    'broker HTTP 429 pauses queued historical requests across symbols',
    () async {
      var now = DateTime(2026, 11, 8);
      final pacer = IbkrHistoricalPacer(
        spacing: Duration.zero,
        cooldown: const Duration(minutes: 2),
        clock: () => now,
      );
      final firstResponse = Completer<http.Response>();
      final firstStarted = Completer<void>();
      final symbols = <String>[];
      final client = IbkrApiClient(
        config,
        historicalPacer: pacer,
        get: (uri, {headers}) {
          final symbol = uri.queryParameters['symbol']!;
          symbols.add(symbol);
          if (symbol == 'AMGN') {
            firstStarted.complete();
            return firstResponse.future;
          }
          return Future.value(
            http.Response(
              '{"symbol":"AAPL","currency":"USD","candles":[{"date":"2026-11-06","open":1,"high":2,"low":1,"close":2,"volume":10}]}',
              200,
            ),
          );
        },
      );

      final first = client.fetchHistoricalCandles('AMGN');
      await firstStarted.future;
      final queued = client.fetchHistoricalCandles('AAPL');
      final firstFailure =
          expectLater(first, throwsA(isA<IbkrRateLimitException>()));
      final queuedFailure =
          expectLater(queued, throwsA(isA<IbkrRateLimitException>()));
      expect(symbols, ['AMGN']);

      firstResponse.complete(
        http.Response('{"detail":"IBKR Gateway returned HTTP 429"}', 502),
      );
      await Future.wait([firstFailure, queuedFailure]);
      expect(symbols, ['AMGN']);

      now = now.add(const Duration(minutes: 3));
      final recovered = await client.fetchHistoricalCandles('AAPL');
      expect(recovered.candles.single.close, 2);
      expect(symbols, ['AMGN', 'AAPL']);
    },
  );

  test('direct HTTP 429 is classified as rate limiting', () async {
    final client = IbkrApiClient(
      config,
      historicalPacer: IbkrHistoricalPacer(spacing: Duration.zero),
      get: (uri, {headers}) async => http.Response('rate limited', 429),
    );

    await expectLater(
      client.fetchHistoricalCandles('AMGN'),
      throwsA(isA<IbkrRateLimitException>()),
    );
  });

  testWidgets('IBKR failure shows one toast, then repeats after quiet period', (
    tester,
  ) async {
    final key = GlobalKey<ScaffoldMessengerState>();
    var now = DateTime(2026, 11, 8);
    final notice = IbkrCandleFailureNotice(
      clock: () => now,
      messenger: () => key.currentState,
    );
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: key,
        home: const Scaffold(body: SizedBox()),
      ),
    );

    notice.report('AMGN', IbkrRateLimitException('HTTP 429'));
    notice.report('AAPL', IbkrRateLimitException('HTTP 429'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('IBKR rate limited (HTTP 429)'), findsOneWidget);

    notice.report('MSFT', StateError('another failure'));
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);

    key.currentState!.removeCurrentSnackBar();
    await tester.pump();
    now = now.add(const Duration(minutes: 11));
    notice.report('MSFT', StateError('another failure'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.textContaining('IBKR candle sync failed for MSFT'),
      findsOneWidget,
    );
  });
}
