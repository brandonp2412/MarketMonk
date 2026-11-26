import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/market_data/web_market_uri.dart';

void main() {
  final page = Uri.parse('https://brandonp2412.github.io/MarketMonk/');
  final search = Uri.parse(
    'https://query1.finance.yahoo.com/v1/finance/search?q=ant',
  );
  final chart = Uri.parse(
    'https://query2.finance.yahoo.com/v8/finance/chart/ANT?interval=1d&range=1d',
  );

  test('Pages uses configured finance gateway for search and charts', () {
    const base = 'https://presley.nz/marketmonk/';
    expect(
      resolveWebMarketDataUri(search, page, base).toString(),
      '${base}api/finance/v1/finance/search?q=ant',
    );
    expect(
      resolveWebMarketDataUri(chart, page, base).toString(),
      '${base}api/finance/v8/finance/chart/ANT?interval=1d&range=1d',
    );
  });

  test('self-hosted web keeps its same-origin gateway', () {
    expect(
      resolveWebMarketDataUri(
        search,
        Uri.parse('http://localhost:8765/'),
        '',
      ).toString(),
      'http://localhost:8765/api/finance/v1/finance/search?q=ant',
    );
  });

  test('unrelated providers are not rewritten', () {
    final other = Uri.parse('https://example.com/data');
    expect(resolveWebMarketDataUri(other, page, 'https://presley.nz/'), other);
  });

  test('insecure configured gateway is rejected', () {
    expect(
      () => resolveWebMarketDataUri(search, page, 'http://example.com/'),
      throwsStateError,
    );
  });
}
