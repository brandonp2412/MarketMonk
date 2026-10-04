import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:market_monk/utils.dart';

import 'test_log_support.dart';

void main() {
  test('identical ticker searches share one request', () async {
    final response = Completer<http.Response>();
    var calls = 0;
    final api = YahooFinanceApi(
      searchFetcher: (_) {
        calls++;
        return response.future;
      },
    );
    addTearDown(api.dispose);

    final first = api.searchTickers('AAPL');
    final second = api.searchTickers(' AAPL ');

    expect(identical(first, second), isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(calls, 1);

    response.complete(http.Response('{"quotes":[]}', 200));
    await Future.wait([first, second]);
  });

  test('ticker search failure does not poison a later retry', () async {
    silenceTalkerForTest();
    var calls = 0;
    final api = YahooFinanceApi(
      searchFetcher: (_) async {
        calls++;
        if (calls == 1) throw StateError('temporary failure');
        return http.Response('{"quotes":[]}', 200);
      },
    );
    addTearDown(api.dispose);

    expect(await api.searchTickers('MSFT'), isEmpty);
    expect(await api.searchTickers('MSFT'), isEmpty);
    expect(calls, 2);
  });

  test('detached task failures are contained', () async {
    silenceTalkerForTest();
    Object? uncaught;

    await runZonedGuarded<Future<void>>(
      () async {
        runDetachedTask(
          Future<void>.error(StateError('expected test failure')),
          'Expected detached task failure',
        );
        await Future<void>.delayed(Duration.zero);
      },
      (error, stackTrace) => uncaught = error,
    );

    expect(uncaught, isNull);
  });
}
