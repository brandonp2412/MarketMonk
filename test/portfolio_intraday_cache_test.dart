import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/intraday_portfolio.dart';
import 'package:market_monk/portfolio_intraday_cache.dart';
import 'package:market_monk/utils.dart';

void main() {
  Position position(String symbol, double shares) => Position(
        symbol: symbol,
        name: symbol,
        nativeCurrency: 'USD',
        netShares: shares,
        avgCost: 100,
        currentPrice: 110,
        firstBuyDate: DateTime(2025),
        lastBuyDate: DateTime(2026),
      );

  test('SQLite intraday cache round-trips prices and signed trades', () {
    final now = DateTime.now().toUtc();
    final data = CachedPortfolioIntraday(
      positionsKey: CachedPortfolioIntraday.keyFor([position('VOO', 10)]),
      cachedAt: now,
      holdings: {
        'VOO': IntradayPortfolioHolding(
          quantity: 10,
          trades: [
            IntradayPortfolioTrade(
              now.subtract(const Duration(hours: 2)),
              5,
              95,
            ),
          ],
          pricesUsd: {
            now.subtract(const Duration(hours: 3)): 101,
            now: 102,
          },
        ),
      },
    );
    final restored = CachedPortfolioIntraday.fromJson(data.toJson());
    expect(restored.isUsableFor([position('VOO', 10)], now), isTrue);
    final holding = restored.holdings['VOO']!;
    expect(holding.quantityAt(now.subtract(const Duration(hours: 4))), 5);
    expect(holding.priceAt(now), 102);
    expect(holding.trades.single.priceUsd, 95);
  });

  test('period cache rejects different holdings, expired and corrupt payloads',
      () {
    final now = DateTime.now().toUtc();
    final data = CachedPortfolioIntraday(
      positionsKey: CachedPortfolioIntraday.keyFor([position('VOO', 10)]),
      cachedAt: now.subtract(const Duration(days: 8)),
      holdings: {
        'VOO': IntradayPortfolioHolding(
          quantity: 10,
          pricesUsd: {now: 100},
        ),
      },
    );
    expect(data.isUsableFor([position('VOO', 10)], now), isFalse);
    final recent = CachedPortfolioIntraday(
      positionsKey: data.positionsKey,
      cachedAt: now,
      holdings: data.holdings,
    );
    expect(recent.isUsableFor([position('MSFT', 10)], now), isFalse);
    expect(recent.isUsableFor([position('VOO', 11)], now), isFalse);
    expect(
      CachedPortfolioIntraday(
        positionsKey: CachedPortfolioIntraday.keyFor([
          position('VOO', 10),
          position('MSFT', 10),
        ]),
        cachedAt: now,
        holdings: data.holdings,
      ).isUsableFor([position('VOO', 10), position('MSFT', 10)], now),
      isFalse,
    );
    expect(
      CachedPortfolioIntraday(
        positionsKey: data.positionsKey,
        cachedAt: now.subtract(const Duration(hours: 37)),
        holdings: data.holdings,
      ).isUsableFor([position('VOO', 10)], now),
      isFalse,
    );
    expect(
      () => CachedPortfolioIntraday.fromJson({
        ...recent.toJson(),
        'version': 999,
      }),
      throwsFormatException,
    );
  });
}
