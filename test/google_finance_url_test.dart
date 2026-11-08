import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/google_finance_url.dart';

void main() {
  test('resolves US exchanges from Yahoo market codes', () {
    expect(
      googleFinanceUrl('AMGN', yahooExchange: 'NMS'),
      'https://www.google.com/finance/quote/AMGN:NASDAQ',
    );
    expect(
      googleFinanceUrl('IBM', yahooExchange: 'NYQ'),
      'https://www.google.com/finance/quote/IBM:NYSE',
    );
    expect(
      googleFinanceUrl('SPY', yahooExchange: 'PCX'),
      'https://www.google.com/finance/quote/SPY:NYSEARCA',
    );
  });

  test('resolves international exchanges from ticker suffixes', () {
    expect(
      googleFinanceUrl('BHP.AX'),
      'https://www.google.com/finance/quote/BHP:ASX',
    );
    expect(
      googleFinanceUrl('FPH.NZ'),
      'https://www.google.com/finance/quote/FPH:NZE',
    );
    expect(
      googleFinanceUrl('VOD.L'),
      'https://www.google.com/finance/quote/VOD:LON',
    );
  });

  test('preserves explicit markets and searches unknown ones', () {
    expect(
      googleFinanceUrl('AMGN:NASDAQ'),
      'https://www.google.com/finance/quote/AMGN:NASDAQ',
    );
    expect(
      googleFinanceUrl('UNKNOWN'),
      'https://www.google.com/finance/search?q=UNKNOWN',
    );
  });
}
