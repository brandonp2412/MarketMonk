import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/portfolio_history.dart';
import 'package:market_monk/portfolio_returns.dart';
import 'package:market_monk/utils.dart';

import 'sqlite_test_support.dart';

void main() {
  final now = DateTime(2026, 11, 8);
  final inception = DateTime(2026, 8, 10);
  final september = DateTime(2026, 9, 8);
  final october = DateTime(2026, 10, 8);
  final latest = DateTime(2026, 11, 6);
  final positions = [
    Position(
      symbol: 'OPEN',
      name: 'Open holding',
      nativeCurrency: 'USD',
      netShares: 5,
      avgCost: 10,
      currentPrice: 12,
      firstBuyDate: DateTime(2026, 9, 1),
      lastBuyDate: DateTime(2026, 9, 1),
    ),
  ];
  IbkrTrade trade(String symbol, double quantity, DateTime date) => IbkrTrade(
        symbol: symbol,
        name: symbol,
        currency: 'USD',
        conid: symbol == 'OPEN' ? 1 : 2,
        quantity: quantity,
        price: symbol == 'OPEN' ? 10 : 20,
        tradeType: quantity > 0 ? 'open' : 'close',
        tradeDate: date,
        realizedPnl: 0,
        commission: 0,
      );
  final brokerTrades = IbkrTradeHistory(
    available: true,
    trades: [
      trade('OPEN', 10, DateTime(2026, 9, 1)),
      trade('CLOSED', 4, DateTime(2026, 9, 1)),
      trade('CLOSED', -4, DateTime(2026, 10, 15)),
      trade('OPEN', -5, DateTime(2026, 11, 2)),
    ],
  );
  final performance = IbkrPerformanceSeries(
    period: '1Y',
    measure: 'TWR',
    currency: 'NZD',
    startDate: DateTime(2026, 8, 7),
    startNav: 0,
    dates: [inception, september, october, latest],
    nav: const [1000, 1100, 1200, 1300],
    returnDates: [inception, september, october, latest],
    returns: const [0, .1, .2, .3],
  );

  Future<AccountManager> setup() async {
    await seedTestSqlite({});
    final accounts = testAccountManager();
    await accounts.init();
    await accounts.setIbkrConfig(
      'Default',
      const IbkrAccountConfig(
        enabled: true,
        baseUrl: 'https://broker.example.test',
        token: 'test',
      ),
    );
    await accounts.cacheIbkrPerformance('Default', performance);
    return accounts;
  }

  Future<void> seedPrices(String symbol) async {
    for (final date in [september, october, latest]) {
      await testDatabase.into(testDatabase.candles).insertOnConflictUpdate(
            CandlesCompanion.insert(
              symbol: symbol,
              date: date,
              close: Value(
                switch (true) {
                  _ when (symbol == 'OPEN') && (date == latest) => 12,
                  _ when (symbol == 'OPEN') => 10,
                  _ => 20,
                },
              ),
              rawCurrency: const Value('USD'),
            ),
          );
    }
  }

  test('backfills sold holdings and reconstructs historical cash with dated FX',
      () async {
    final accounts = await setup();
    final synced = <String, DateTime>{};
    var tradeLoads = 0;
    final rateDates = <DateTime>{};
    final history = await loadPortfolioHistory(
      accounts: accounts,
      accountName: 'Default',
      positions: positions,
      database: testDatabase,
      now: now,
      tradeLoader: (_) async {
        tradeLoads++;
        return brokerTrades;
      },
      candleSync: (symbol, from, config) async {
        synced[symbol] = from;
        expect(config.enabled, symbol == 'OPEN');
        await seedPrices(symbol);
      },
      rateLoader: (currency, date) async {
        expect(currency, 'NZD');
        rateDates.add(date);
        return 2;
      },
    );
    expect(tradeLoads, 1);
    expect(accounts.ibkrTradeHistoryCacheFor('Default'), brokerTrades);
    expect(synced.keys, unorderedEquals(['OPEN', 'CLOSED']));
    expect(synced.values.every((date) => date.isBefore(inception)), isTrue);
    expect(portfolioInception(performance), inception);
    expect(rateDates, containsAll([inception, september, october, latest]));
    for (final entry in {
      inception: {'CASH': 500.0},
      september: {'OPEN': 100.0, 'CLOSED': 80.0, 'CASH': 370.0},
      october: {'OPEN': 100.0, 'CLOSED': 80.0, 'CASH': 420.0},
      DateTime(2026, 11, 7): {'OPEN': 60.0, 'CASH': 590.0},
    }.entries) {
      final allocation = history.allocationAt(
        positions: positions,
        date: entry.key,
        performance: performance,
      );
      expect(allocation, isNotNull, reason: '${entry.key}');
      expect(
        {for (final holding in allocation!) holding.symbol: holding.value},
        entry.value,
      );
      final index = accountNetAssetValueIndexAt(performance, entry.key)!;
      expect(
        allocation.fold<double>(0, (sum, holding) => sum + holding.value),
        performance.nav[index] / 2,
      );
    }
  });

  test(
      'portfolio history backfills different holdings concurrently, capped at four',
      () async {
    final accounts = await setup();
    await accounts.cacheIbkrTradeHistory(
      'Default',
      const IbkrTradeHistory(available: true, trades: []),
    );
    final symbols = ['AAA', 'BBB', 'CCC', 'DDD', 'EEE', 'FFF', 'GGG', 'HHH'];
    final holdings = [
      for (final symbol in symbols)
        Position(
          symbol: symbol,
          name: symbol,
          nativeCurrency: 'USD',
          netShares: 1,
          avgCost: 10,
          currentPrice: 12,
          firstBuyDate: september,
          lastBuyDate: september,
        ),
    ];
    final firstBatchGate = Completer<void>();
    var active = 0;
    var maxActive = 0;
    final started = <String>[];
    final loading = loadPortfolioHistory(
      accounts: accounts,
      accountName: 'Default',
      positions: holdings,
      database: testDatabase,
      now: now,
      tradeLoader: (_) async => fail('Cached trades should be used'),
      candleSync: (symbol, from, config) async {
        started.add(symbol);
        active++;
        if (active > maxActive) maxActive = active;
        try {
          if (started.length <= 4) await firstBatchGate.future;
          await seedPrices(symbol);
        } finally {
          active--;
        }
      },
      rateLoader: (_, __) async => 2,
    );
    // All four requests should start before the first finishes. Serial
    // backfilling used to make eight holdings wait eight network round trips.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(started.length, 4);
    expect(maxActive, 4);
    firstBatchGate.complete();
    final history = await loading;
    expect(started, unorderedEquals(symbols));
    expect(maxActive, 4);
    expect(history.candles.keys, containsAll(symbols));
    for (final symbol in symbols) {
      expect(history.candles[symbol], isNotEmpty);
    }
  });

  test('full cached periods are usable without refreshing broker history', () {
    final historicalDates = <DateTime>{
      september,
      for (var period = 1; period < firstIntradayPeriod; period++)
        if (portfolioReturnCutoff(period, now)!.isAfter(september))
          portfolioReturnCutoff(period, now)!,
      latest,
    }.toList()
      ..sort();
    final history = PortfolioHistory(
      trades: const [],
      candles: {
        'OPEN': [
          for (final date in historicalDates)
            StoredCandle(
              symbol: 'OPEN',
              date: date,
              open: 10,
              high: 10,
              low: 10,
              close: 10,
              volume: 1,
              adjClose: 10,
              rawCurrency: 'USD',
            ),
        ],
      },
      rates: {
        for (final date in historicalDates) date: {'USD': 1},
      },
    );
    final usdPerformance = IbkrPerformanceSeries(
      period: '1Y',
      measure: 'TWR',
      currency: 'USD',
      startDate: september,
      startNav: 1000,
      dates: historicalDates,
      nav: [for (final _ in historicalDates) 1200],
      returnDates: historicalDates,
      returns: [for (final _ in historicalDates) 0.0],
    );
    expect(
      cachedPortfolioDailyPeriodsComplete(
        history: history,
        positions: positions,
        performance: usdPerformance,
        now: now,
      ),
      isTrue,
    );
    expect(
      cachedPortfolioDailyPeriodsComplete(
        history: PortfolioHistory(
          trades: history.trades,
          candles: {
            'OPEN': [history.candles['OPEN']!.first],
          },
          rates: history.rates,
        ),
        positions: positions,
        performance: usdPerformance,
        now: now,
      ),
      isFalse,
      reason:
          'One cached point must not unlock a partially loaded period ruler',
    );
  });

  test('history reads keep the baseline week and skip older candles', () async {
    final accounts = await setup();
    await accounts.cacheIbkrTradeHistory('Default', brokerTrades);
    final baseline = inception.subtract(const Duration(days: 7));
    for (final date in [baseline.subtract(const Duration(days: 1)), baseline]) {
      await testDatabase.into(testDatabase.candles).insert(
            CandlesCompanion.insert(
              symbol: 'OPEN',
              date: date,
              close: const Value(10),
              rawCurrency: const Value('USD'),
            ),
          );
    }
    await seedPrices('OPEN');
    final history = await loadPortfolioHistory(
      accounts: accounts,
      accountName: 'Default',
      positions: positions,
      database: testDatabase,
      now: now,
      cacheOnly: true,
    );
    expect(
      history.candles['OPEN']!.map((candle) => candle.date),
      [baseline, september, october, latest],
    );
  });

  test('cached history renders without network and covered prices are reused',
      () async {
    final accounts = await setup();
    await accounts.cacheIbkrTradeHistory('Default', brokerTrades);
    for (final symbol in ['OPEN', 'CLOSED']) {
      await seedPrices(symbol);
    }
    final prefs = await SqliteSettings.getInstance();
    for (final date in [inception, september, october, latest]) {
      final day = DateTime.utc(date.year, date.month, date.day)
          .toIso8601String()
          .substring(0, 10);
      await prefs.setDouble('historicalUsdRate_NZD_$day', 2);
    }
    for (final cacheOnly in [true, false]) {
      final history = await loadPortfolioHistory(
        accounts: accounts,
        accountName: 'Default',
        positions: positions,
        database: testDatabase,
        now: now,
        cacheOnly: cacheOnly,
        tradeLoader: (_) async => throw StateError('unexpected trade request'),
        candleSync: (symbol, from, config) async {
          fail('Cached $symbol prices already cover every slider date');
        },
        rateLoader: (currency, date) async {
          expect(cacheOnly, isFalse);
          return 2;
        },
      );
      expect(
        history
            .allocationAt(
              positions: positions,
              date: inception,
              performance: performance,
            )!
            .single
            .value,
        500,
      );
      expect(
        history.allocationAt(
          positions: positions,
          date: october,
          performance: performance,
        ),
        isNotNull,
      );
    }
  });

  test('10 August allocation uses same-day cached prices with a time',
      () async {
    final accounts = await setup();
    final day = DateTime(2026, 8, 10);
    final series = IbkrPerformanceSeries(
      period: '1Y',
      measure: 'TWR',
      currency: 'USD',
      startDate: day,
      startNav: 1000,
      dates: [day],
      nav: const [1000],
      returnDates: [day],
      returns: const [0],
    );
    await accounts.cacheIbkrPerformance('Default', series);
    await accounts.cacheIbkrTradeHistory(
      'Default',
      const IbkrTradeHistory(available: true, trades: []),
    );
    for (final entry in {
      DateTime(2026, 8, 7): 250.0,
      DateTime(2026, 8, 10, 12): 100.0,
    }.entries) {
      await testDatabase.into(testDatabase.candles).insert(
            CandlesCompanion.insert(
              symbol: 'OPEN',
              date: entry.key,
              close: Value(entry.value),
              rawCurrency: const Value('USD'),
            ),
          );
    }
    for (final cacheOnly in [true, false]) {
      final history = await loadPortfolioHistory(
        accounts: accounts,
        accountName: 'Default',
        positions: positions,
        database: testDatabase,
        now: day.add(const Duration(days: 1)),
        cacheOnly: cacheOnly,
        candleSync: (symbol, from, config) async {
          fail('The same-day price is already cached');
        },
      );
      final allocation = history.allocationAt(
        positions: positions,
        date: day,
        performance: series,
      );
      expect(allocation, isNotNull);
      expect(
        {for (final holding in allocation!) holding.symbol: holding.value},
        {'OPEN': 500.0, 'CASH': 500.0},
      );
    }
  });

  test('manual refresh updates open holdings without refetching covered sales',
      () async {
    final accounts = await setup();
    await accounts.cacheIbkrTradeHistory('Default', brokerTrades);
    for (final symbol in ['OPEN', 'CLOSED']) {
      await seedPrices(symbol);
    }
    final synced = <String>[];
    await loadPortfolioHistory(
      accounts: accounts,
      accountName: 'Default',
      positions: positions,
      database: testDatabase,
      now: now,
      forceRefresh: true,
      tradeLoader: (_) async => brokerTrades,
      candleSync: (symbol, from, config) async {
        expect(config.enabled, isTrue);
        synced.add(symbol);
      },
      rateLoader: (currency, date) async => 2,
    );
    expect(synced, ['OPEN']);
  });

  test(
      'uses cached broker trades offline and never turns missing prices into cash',
      () async {
    final accounts = await setup();
    await accounts.cacheIbkrTradeHistory('Default', brokerTrades);
    final profile = (await testDatabase.readProfileByName('Default'))!;
    final expiredAt = DateTime(2000);
    await testDatabase.writeIbkrCache(
      profileId: profile.id,
      kind: 'trades',
      cacheKey: 'history',
      payloadJson: jsonEncode(
        CachedIbkrTradeHistoryData(
          history: brokerTrades,
          cachedAt: expiredAt,
        ).toJson(),
      ),
      cachedAt: expiredAt,
    );
    final reloaded = testAccountManager();
    await reloaded.init();
    var tradeLoads = 0;
    final history = await loadPortfolioHistory(
      accounts: reloaded,
      accountName: 'Default',
      positions: positions,
      database: testDatabase,
      now: now,
      tradeLoader: (_) async {
        tradeLoads++;
        throw StateError('offline');
      },
      candleSync: (symbol, from, config) async {
        if (symbol == 'CLOSED') throw StateError('unavailable');
        await seedPrices(symbol);
      },
      rateLoader: (currency, date) async => 2,
    );
    expect(tradeLoads, 1);
    expect(history.trades, hasLength(4));
    expect(
      history.allocationAt(
        positions: positions,
        date: october,
        performance: performance,
      ),
      isNull,
    );
    expect(
      history.allocationAt(
        positions: positions,
        date: latest,
        performance: performance,
      ),
      isNotNull,
    );
  });
}
