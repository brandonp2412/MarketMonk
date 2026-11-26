import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:market_monk/market_data/web_rate_limit_notice.dart';

void main() {
  test('detects 429 and Cloudflare 1027 but not ordinary server errors', () {
    expect(
      classifyWebMarketResponse(http.Response('', 429)),
      WebMarketProblem.rateLimited,
    );
    expect(
      classifyWebMarketResponse(
        http.Response(
          '<h1>Error 1027</h1>',
          503,
          headers: {'content-type': 'text/html'},
        ),
      ),
      WebMarketProblem.rateLimited,
    );
    expect(
      classifyWebMarketResponse(http.Response('unavailable', 503)),
      isNull,
    );
    expect(classifyWebMarketResponse(http.Response('1027', 200)), isNull);
  });

  testWidgets('rate limit toast links to native releases and deduplicates',
      (tester) async {
    final key = GlobalKey<ScaffoldMessengerState>();
    Uri? opened;
    final notice = WebRateLimitNotice(
      messenger: () => key.currentState,
      openUrl: (uri) async {
        opened = uri;
        return true;
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: key,
        home: const Scaffold(body: Text('MarketMonk')),
      ),
    );
    notice.report(WebMarketProblem.rateLimited);
    notice.report(WebMarketProblem.rateLimited);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(
      find.text('Web market data limit hit. Native apps have no web quota.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Download native app'));
    await tester.pumpAndSettle();
    expect(opened.toString(), nativeReleasesUrl);
    notice.report(WebMarketProblem.rateLimited);
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('unconfirmed browser error does not claim quota was exhausted',
      (tester) async {
    final key = GlobalKey<ScaffoldMessengerState>();
    final notice = WebRateLimitNotice(messenger: () => key.currentState);
    await tester.pumpWidget(
      MaterialApp(scaffoldMessengerKey: key, home: const Scaffold()),
    );
    notice.report(WebMarketProblem.unavailable);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.textContaining('possibly rate limited'), findsOneWidget);
    expect(find.text('Download native app'), findsOneWidget);
  });
}
