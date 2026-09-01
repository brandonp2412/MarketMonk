import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:market_monk/database.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    allRatesFromUsd
      ..clear()
      ..['USD'] = 1.0;
  });

  test('IBKR client authenticates and parses portfolio snapshots', () async {
    Uri? requestedUri;
    Map<String, String>? requestedHeaders;
    final client = IbkrApiClient(
      const IbkrAccountConfig(
        enabled: true,
        baseUrl: 'https://ibkr.example.test/base/',
        token: 'secret-token',
      ),
      get: (uri, {headers}) async {
        requestedUri = uri;
        requestedHeaders = headers;
        return http.Response(
          '''{"account":"****1234","read_only":true,"summary":{"netliquidation":{"value":324961.06,"currency":"NZD"},"netliquidationbycurrency":{"value":191853.54,"currency":"USD"}},"ledger":{},"positions":[{"symbol":"AAPL","security_type":"STK","currency":"USD","exchange":"NASDAQ","conid":265598,"quantity":10,"market_price":200,"market_value":2000,"average_cost":150,"unrealized_pnl":500,"realized_pnl":25}]}''',
          200,
        );
      },
    );

    final snapshot = await client.fetchPortfolio();

    expect(
      requestedUri.toString(),
      'https://ibkr.example.test/base/v1/portfolio',
    );
    expect(requestedHeaders?['Authorization'], 'Bearer secret-token');
    expect(snapshot.account, '****1234');
    expect(snapshot.positions, hasLength(1));
    expect(snapshot.positions.single.symbol, 'AAPL');
    expect(snapshot.positions.single.marketValue, 2000);
    expect(snapshot.netLiquidation?.value, 324961.06);
    expect(snapshot.netLiquidation?.currency, 'NZD');
    expect(snapshot.netLiquidationUsd?.value, 191853.54);
    expect(snapshot.netLiquidationUsd?.currency, 'USD');

    cacheIbkrAccountExchangeRate(snapshot);
    expect(
      allRatesFromUsd['NZD'],
      closeTo(324961.06 / 191853.54, 0.000001),
    );
  });

  test('IBKR client authenticates and parses historical candles', () async {
    Uri? requestedUri;
    final client = IbkrApiClient(
      const IbkrAccountConfig(
        enabled: true,
        baseUrl: 'https://ibkr.example.test/base/',
        token: 'secret-token',
      ),
      get: (uri, {headers}) async {
        requestedUri = uri;
        return http.Response(
          '''{"read_only":true,"source":"native","symbol":"AAPL","currency":"USD","candles":[{"date":"2026-08-28","open":198,"high":202,"low":197,"close":200,"volume":1234}]}''',
          200,
        );
      },
    );

    final history = await client.fetchHistoricalCandles('AAPL', years: 10);

    expect(
      requestedUri.toString(),
      'https://ibkr.example.test/base/v1/historical?symbol=AAPL&years=10',
    );
    expect(history.symbol, 'AAPL');
    expect(history.currency, 'USD');
    expect(history.candles, hasLength(1));
    expect(history.candles.single.date, DateTime(2026, 8, 28));
    expect(history.candles.single.close, 200);
    expect(history.candles.single.volume, 1234);
  });

  test('IBKR historical years are bounded', () {
    final client = IbkrApiClient(
      const IbkrAccountConfig(
        enabled: true,
        baseUrl: 'https://ibkr.example.test',
        token: 'secret-token',
      ),
    );

    expect(
      () => client.fetchHistoricalCandles('AAPL', years: 11),
      throwsRangeError,
    );
  });

  test('IBKR client exposes server error details', () async {
    final client = IbkrApiClient(
      const IbkrAccountConfig(
        enabled: true,
        baseUrl: 'https://ibkr.example.test',
        token: 'secret-token',
      ),
      get: (_, {headers}) async => http.Response(
        '{"error":"IBKR unavailable","detail":"Gateway needs login"}',
        502,
      ),
    );

    expect(
      client.fetchPortfolio(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Gateway needs login',
        ),
      ),
    );
  });

  test('IBKR positions use broker valuation and local trade metadata',
      () async {
    final trades = [
      Trade(
        id: 1,
        symbol: 'AAPL',
        name: 'Apple Inc.',
        quantity: 10,
        price: 150,
        tradeType: 'open',
        tradeDate: DateTime(2026, 1, 2),
        realizedPL: 0,
        commission: 0,
      ),
    ];
    final brokerPositions = [
      const IbkrPosition(
        symbol: 'AAPL',
        securityType: 'STK',
        currency: 'USD',
        exchange: 'NASDAQ',
        conid: 265598,
        quantity: 10,
        marketPrice: 200,
        marketValue: 1995,
        averageCost: 150,
        unrealizedPnl: 495,
        realizedPnl: 25,
      ),
      const IbkrPosition(
        symbol: 'USD',
        securityType: 'CASH',
        currency: 'USD',
        exchange: '',
        conid: 0,
        quantity: 100,
        marketPrice: 1,
        marketValue: 100,
        averageCost: 1,
        unrealizedPnl: 0,
        realizedPnl: 0,
      ),
    ];

    final position =
        (await computeIbkrPositions(brokerPositions, trades)).single;

    expect(position.name, 'Apple Inc.');
    expect(position.currentPrice, 200);
    expect(position.currentValue, 1995);
    expect(position.costBasis, 1500);
    expect(position.unrealizedPL, 495);
    expect(position.realizedToday, 25);
    expect(position.change, closeTo(33.3333, 0.001));
    expect(position.firstBuyDate, DateTime(2026, 1, 2));
  });

  test('IBKR settings persist independently per MarketMonk account', () async {
    final accounts = AccountManager();
    await accounts.init();
    const config = IbkrAccountConfig(
      enabled: true,
      baseUrl: 'https://ibkr.example.test',
      token: 'saved-token',
    );

    await accounts.setIbkrConfig('Default', config);
    final reloaded = AccountManager();
    await reloaded.init();

    expect(reloaded.ibkrConfigFor('Default'), config);
    expect(reloaded.ibkrConfigFor('Other'), const IbkrAccountConfig());
  });
}
