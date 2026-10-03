import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:market_monk/ibkr_api.dart';

void main() {
  const config = IbkrAccountConfig(
    enabled: true,
    baseUrl: 'https://ibkr-network-coordination.example.test/',
    token: 'token',
  );

  test(
    'IBKR duplicate callers share one in-flight portfolio request',
    () async {
      final gate = Completer<http.Response>();
      var calls = 0;

      Future<http.Response> get(Uri uri, {Map<String, String>? headers}) {
        calls++;
        return gate.future;
      }

      final firstClient = IbkrApiClient(config, get: get);
      final secondClient = IbkrApiClient(config, get: get);
      final first = firstClient.fetchPortfolio();
      final second = secondClient.fetchPortfolio();

      expect(calls, 1);
      gate.complete(http.Response('{"account":"A","positions":[]}', 200));

      final results = await Future.wait([first, second]);
      expect(results.map((result) => result.account), ['A', 'A']);
      expect(calls, 1);
    },
  );

  test('IBKR request failure does not poison a later retry', () async {
    var calls = 0;
    final client = IbkrApiClient(
      config.copyWith(baseUrl: 'https://ibkr-retry.example.test/'),
      get: (uri, {headers}) async {
        calls++;
        if (calls == 1) {
          return http.Response('{"detail":"temporary"}', 503);
        }
        return http.Response('{"account":"B","positions":[]}', 200);
      },
    );

    await expectLater(client.fetchPortfolio(), throwsStateError);
    expect((await client.fetchPortfolio()).account, 'B');
    expect(calls, 2);
  });
}
