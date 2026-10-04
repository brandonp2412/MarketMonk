import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/holdings_page.dart';

void main() {
  test('configured IBKR does not reuse a stale holdings cache', () {
    expect(
      HoldingsPageState.shouldUsePortfolioCache(
        hasCache: true,
        refreshPortfolio: false,
        ibkrEnabled: true,
        ibkrConfigured: true,
        cacheFresh: false,
      ),
      isFalse,
    );
  });

  test('configured IBKR can reuse a fresh holdings cache', () {
    expect(
      HoldingsPageState.shouldUsePortfolioCache(
        hasCache: true,
        refreshPortfolio: false,
        ibkrEnabled: true,
        ibkrConfigured: true,
        cacheFresh: true,
      ),
      isTrue,
    );
  });

  test('explicit refresh bypasses holdings cache', () {
    expect(
      HoldingsPageState.shouldUsePortfolioCache(
        hasCache: true,
        refreshPortfolio: true,
        ibkrEnabled: true,
        ibkrConfigured: true,
        cacheFresh: true,
      ),
      isFalse,
    );
  });

  test('local holdings retain existing cache behavior', () {
    expect(
      HoldingsPageState.shouldUsePortfolioCache(
        hasCache: true,
        refreshPortfolio: false,
        ibkrEnabled: false,
        ibkrConfigured: false,
        cacheFresh: false,
      ),
      isTrue,
    );
  });
}
