import 'dart:ffi';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:market_monk/csv_import.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/main.dart' as app;
import 'package:sqlite3/open.dart';
import 'package:test/test.dart';

void _overrideSqlite3() {
  open.overrideForAll(() => DynamicLibrary.open('libsqlite3.so.0'));
}

Database _openDb() => Database.connect(NativeDatabase.memory());

// ---------------------------------------------------------------------------
// Minimal Tiger Brokers CSV fixture that mirrors the real format exactly:
// rows with a multi-line quoted Trade Time field, commas inside values, etc.
// ---------------------------------------------------------------------------
const _tigerCsvMinimal = '''
Activity Statement,,,,2025-01-01 - 2025-12-31
Trades,,,,Symbol,Market,Exchange,Activity Type,Quantity,Trade Price,Amount,Accrued Interest in Trade,Transaction Fee,Other Tripartite fees,Settlement Fee,SEC Fee,Option Regulatory Fee,Stamp Duty,Transaction Levy,Clearing Fee,Trading Activity Fee,Exchange Fee,Future Regulatory Fee,Commission,Platform Fee,Option Settlement Fee,Subscription Fee,Redemption Fee,Switching Fee,PH Stock Transaction Tax,Tax Service Fee,AFRC Transaction Levy,Trading Tariff,Transaction Fee,Brokerage fee,Handing Fee,Securities Management Fee,Transfer Fees (CSDC),Transfer Fees (HKSCC),Stamp Duty On Stock Borrowing,Consolidated Audit Trail Fee,Processing Fee,CM DA SI Fee,DVP SI Fee,IPO Transaction Fee,IPO Process Fee,Ipo Settle Fee,IPO Channel Fee,Realized P/L,Notes,Trade Time,Settle Date,Currency
Trades,Stock,,DATA,Apple (AAPL),US,NASDAQ,Open,10,150.00,1500.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,-2.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,,,"2025-03-01
09:30:00, US/Eastern",2025-03-02,USD
Trades,Stock,,DATA,Apple (AAPL),US,NASDAQ,Close,-5,180.00,-900.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,-2.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,150.00,,"2025-06-01
09:30:00, US/Eastern",2025-06-02,USD
Trades,Stock,,DATA,"Meta Platforms, Inc. (META)",US,NASDAQ,Open,3,400.00,1200.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,-2.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,,,"2025-04-01
09:30:00, US/Eastern",2025-04-02,USD
Holdings,,,,Symbol,Quantity,Multiplier,Cost Price,Close Price,Value,Unrealized P/L,Initial Margin,Maint Margin,Currency
Holdings,Stock,,DATA,Apple (AAPL),5,1.0,150.00,175.00,875.00,125.00,262.50,218.75,USD
Holdings,Stock,,DATA,"Meta Platforms, Inc. (META)",3,1.0,400.00,450.00,1350.00,150.00,675.00,562.50,USD
''';

// CSV with ONLY trade history (no current holdings — fully closed position)
const _closedPositionCsv = '''
Activity Statement,,,,2025-01-01 - 2025-12-31
Trades,,,,Symbol,Market,Exchange,Activity Type,Quantity,Trade Price,Amount,Accrued Interest in Trade,Transaction Fee,Other Tripartite fees,Settlement Fee,SEC Fee,Option Regulatory Fee,Stamp Duty,Transaction Levy,Clearing Fee,Trading Activity Fee,Exchange Fee,Future Regulatory Fee,Commission,Platform Fee,Option Settlement Fee,Subscription Fee,Redemption Fee,Switching Fee,PH Stock Transaction Tax,Tax Service Fee,AFRC Transaction Levy,Trading Tariff,Transaction Fee,Brokerage fee,Handing Fee,Securities Management Fee,Transfer Fees (CSDC),Transfer Fees (HKSCC),Stamp Duty On Stock Borrowing,Consolidated Audit Trail Fee,Processing Fee,CM DA SI Fee,DVP SI Fee,IPO Transaction Fee,IPO Process Fee,Ipo Settle Fee,IPO Channel Fee,Realized P/L,Notes,Trade Time,Settle Date,Currency
Trades,Stock,,DATA,NVIDIA (NVDA),US,NASDAQ,Open,10,100.00,1000.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,-2.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,,,"2025-01-10
09:30:00, US/Eastern",2025-01-11,USD
Trades,Stock,,DATA,NVIDIA (NVDA),US,NASDAQ,Close,-10,200.00,-2000.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,-2.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,"1,000.00",,"2025-03-10
09:30:00, US/Eastern",2025-03-11,USD
Holdings,,,,Symbol,Quantity,Multiplier,Cost Price,Close Price,Value,Unrealized P/L,Initial Margin,Maint Margin,Currency
''';

// Malformed / empty CSV — should produce empty results, not throw
const _emptyCsv = 'Activity Statement,,,,2025-01-01 - 2025-12-31\n';

// ---------------------------------------------------------------------------
// Minimal Interactive Brokers CSV fixture (EXECUTION rows only).
// Includes: 2 STK BUY rows, 1 STK SELL row, and 1 CASH row to be skipped.
// ---------------------------------------------------------------------------
const _ibkrCsvMinimal =
    '"ClientAccountID","AccountAlias","Model","CurrencyPrimary","AssetClass","SubCategory","Symbol","Description","Conid","SecurityID","SecurityIDType","CUSIP","ISIN","FIGI","ListingExchange","UnderlyingConid","UnderlyingSymbol","UnderlyingSecurityID","UnderlyingListingExchange","Issuer","IssuerCountryCode","Multiplier","Strike","Expiry","Put/Call","PrincipalAdjustFactor","TransactionType","TradeID","OrderID","ExecID","BrokerageOrderID","OrderReference","VolatilityOrderLink","ClearingFirmID","OrigTradePrice","OrigTradeDate","OrigTradeID","ExtExecID","BlockID","OrderTime","Date/Time","ReportDate","SettleDate","TradeDate","Exchange","Buy/Sell","Quantity","Price","Amount","Proceeds","NetCash","NetCashWithBillable","Commission","BrokerExecutionCommission","BrokerClearingCommission","ThirdPartyExecutionCommission","ThirdPartyClearingCommission","ThirdPartyRegulatoryCommission","OtherCommission","CommissionCurrency","Tax","SalesTax","TradeCharge","OtherTax","Code","OrderType","LevelOfDetail","TraderID","IsAPIOrder","AllocatedTo","AccruedInterest","RFQID","PositionActionID","SerialNumber","DeliveryType","CommodityType","Fineness","Weight"\n'
    '"U1234","","","USD","STK","COMMON","AAPL","APPLE INC","12345","US0378331005","ISIN","037833100","US0378331005","BBG000B9XRY4","NASDAQ","","AAPL","","","","US","1","","","","","ExchTrade","111","222","aaa","bbb","ccc","","","0","","","ext1","0","20260413;090000","20260413;090000","20260413","20260414","20260413","NASDAQ","BUY","10","150.00","-1500","1500","-1501","-1501","-1","-1","0","0","0","0","0","USD","0","0","0","0","O","MKT","EXECUTION","","N","","0","","","","","","0.0","0.0"\n'
    '"U1234","","","USD","STK","COMMON","AAPL","APPLE INC","12345","US0378331005","ISIN","037833100","US0378331005","BBG000B9XRY4","NASDAQ","","AAPL","","","","US","1","","","","","ExchTrade","113","222","aac","bbc","ccc","","","0","","","ext3","0","20260413;090100","20260413;090100","20260413","20260414","20260413","NASDAQ","BUY","5","149.50","-747.5","747.5","-747.5","-747.5","0","0","0","0","0","0","0","USD","0","0","0","0","O","MKT","EXECUTION","","N","","0","","","","","","0.0","0.0"\n'
    '"U1234","","","USD","STK","COMMON","AAPL","APPLE INC","12345","US0378331005","ISIN","037833100","US0378331005","BBG000B9XRY4","NASDAQ","","AAPL","","","","US","1","","","","","ExchTrade","114","333","aad","bbd","ddd","","","0","","","ext4","0","20260415;093000","20260415;093000","20260415","20260416","20260415","NASDAQ","SELL","8","175.00","1400","-1400","1400","1400","0","0","0","0","0","0","0","USD","0","0","0","0","C","MKT","EXECUTION","","N","","0","","","","","","0.0","0.0"\n'
    '"U1234","","","USD","CASH","","NZD.USD","NZD.USD","99999","","","","","","","","","","","","","1","","","","","ExchTrade","999","888","xxx","yyy","","","","0","","","N/A","0","20260413;150000","20260413;150000","20260413","20260413","20260413","IDEALFX","BUY","100","0.58","58","-58","0","0","0","","","","","","","NZD","0","0","0","0","","","EXECUTION","","N","","0","","","","","","0.0","0.0"\n';

void main() {
  setUpAll(_overrideSqlite3);

  // ─── TigerBrokersParser — Trades section ───────────────────────────────────
  group('TigerBrokersParser — trades', () {
    late ParseResult result;

    setUpAll(() {
      result = TigerBrokersParser().parse(_tigerCsvMinimal);
    });

    test('parses correct number of trades', () {
      expect(result.trades, hasLength(3));
    });

    test('BUY trade has positive quantity and tradeType open', () {
      final buy = result.trades.firstWhere(
        (t) => t.symbol == 'AAPL' && t.tradeType == 'open',
      );
      expect(buy.quantity, greaterThan(0));
      expect(buy.quantity, closeTo(10.0, 0.001));
      expect(buy.price, closeTo(150.0, 0.001));
    });

    test('SELL trade has negative quantity, tradeType close, and realizedPL',
        () {
      final sell = result.trades.firstWhere(
        (t) => t.symbol == 'AAPL' && t.tradeType == 'close',
      );
      expect(sell.quantity, lessThan(0));
      expect(sell.quantity, closeTo(-5.0, 0.001));
      expect(sell.price, closeTo(180.0, 0.001));
      expect(sell.realizedPL, closeTo(150.0, 0.01));
    });

    test('commission is stored as positive absolute value', () {
      final buy = result.trades.firstWhere(
        (t) => t.symbol == 'AAPL' && t.tradeType == 'open',
      );
      expect(buy.commission, closeTo(2.0, 0.001));
    });

    test('tradeDate is parsed from Trade Time field', () {
      final buy = result.trades.firstWhere(
        (t) => t.symbol == 'AAPL' && t.tradeType == 'open',
      );
      expect(buy.tradeDate.year, 2025);
      expect(buy.tradeDate.month, 3);
      expect(buy.tradeDate.day, 1);
    });

    test('symbol extracted correctly from "Name (TICKER)" format', () {
      final symbols = result.trades.map((t) => t.symbol).toSet();
      expect(symbols, containsAll(['AAPL', 'META']));
    });

    test('name extracted correctly (handles comma in quoted name)', () {
      final meta = result.trades.firstWhere((t) => t.symbol == 'META');
      expect(meta.name, contains('Meta Platforms'));
    });

    test('open trades have realizedPL == 0', () {
      for (final t in result.trades.where((t) => t.tradeType == 'open')) {
        expect(t.realizedPL, equals(0.0));
      }
    });
  });

  // ─── TigerBrokersParser — fully-closed position ────────────────────────────
  group('TigerBrokersParser — closed position (no holdings row)', () {
    late ParseResult result;

    setUpAll(() {
      result = TigerBrokersParser().parse(_closedPositionCsv);
    });

    test('produces two trades for the fully-closed NVDA position', () {
      expect(result.trades, hasLength(2));
    });

    test('sell trade for closed position has correct realizedPL', () {
      final sell = result.trades.firstWhere((t) => t.tradeType == 'close');
      expect(sell.realizedPL, closeTo(1000.0, 0.01));
    });
  });

  // ─── TigerBrokersParser — empty / malformed CSV ────────────────────────────
  group('TigerBrokersParser — empty CSV', () {
    test('empty CSV returns empty ParseResult without throwing', () {
      final result = TigerBrokersParser().parse(_emptyCsv);
      expect(result.trades, isEmpty);
    });

    test('completely empty string returns empty ParseResult', () {
      final result = TigerBrokersParser().parse('');
      expect(result.trades, isEmpty);
    });
  });

  // ─── InteractiveBrokersParser — trades ────────────────────────────────────
  group('InteractiveBrokersParser — trades', () {
    late ParseResult result;

    setUpAll(() {
      result = InteractiveBrokersParser().parse(_ibkrCsvMinimal);
    });

    test('parses only STK EXECUTION rows (skips CASH row)', () {
      expect(result.trades, hasLength(3));
    });

    test('BUY rows produce positive quantity and tradeType open', () {
      final buys = result.trades
          .where((t) => t.symbol == 'AAPL' && t.tradeType == 'open')
          .toList();
      expect(buys, hasLength(2));
      for (final t in buys) {
        expect(t.quantity, greaterThan(0));
      }
    });

    test('SELL row produces negative quantity and tradeType close', () {
      final sell = result.trades.firstWhere((t) => t.tradeType == 'close');
      expect(sell.quantity, closeTo(-8.0, 0.001));
      expect(sell.price, closeTo(175.0, 0.001));
    });

    test('commission stored as positive absolute value', () {
      final buy = result.trades.firstWhere(
        (t) => t.symbol == 'AAPL' && t.tradeType == 'open' && t.quantity > 9,
      );
      expect(buy.commission, closeTo(1.0, 0.001));
    });

    test('TradeDate parsed correctly from YYYYMMDD format', () {
      final buy = result.trades.first;
      expect(buy.tradeDate.year, 2026);
      expect(buy.tradeDate.month, 4);
      expect(buy.tradeDate.day, 13);
    });

    test('symbol and name extracted from dedicated columns', () {
      final trade = result.trades.first;
      expect(trade.symbol, 'AAPL');
      expect(trade.name, 'APPLE INC');
    });

    test('realizedPL is always 0.0 (not available per execution)', () {
      for (final t in result.trades) {
        expect(t.realizedPL, equals(0.0));
      }
    });
  });

  group('InteractiveBrokersParser — empty/malformed CSV', () {
    test('empty string returns empty ParseResult without throwing', () {
      expect(InteractiveBrokersParser().parse('').trades, isEmpty);
    });

    test('header-only CSV returns empty ParseResult', () {
      final headerOnly = _ibkrCsvMinimal.split('\n').first;
      expect(InteractiveBrokersParser().parse(headerOnly).trades, isEmpty);
    });
  });

  // ─── importTrades — database round-trip ───────────────────────────────────
  group('importTrades — database round-trip', () {
    late Database testDb;

    setUp(() {
      testDb = _openDb();
      app.db = testDb;
    });

    tearDown(() async {
      await testDb.close();
    });

    test('all parsed trades are persisted to the DB', () async {
      final result = TigerBrokersParser().parse(_tigerCsvMinimal);
      final count = await importTrades(result.trades);

      expect(count, equals(3));

      final stored = await testDb.trades.select().get();
      expect(stored, hasLength(3));
    });

    test('stored trade data matches parsed data', () async {
      final result = TigerBrokersParser().parse(_tigerCsvMinimal);
      await importTrades(result.trades);

      final stored = await testDb.trades.select().get();
      final sell = stored.firstWhere(
        (t) => t.symbol == 'AAPL' && t.tradeType == 'close',
      );

      expect(sell.quantity, closeTo(-5.0, 0.001));
      expect(sell.price, closeTo(180.0, 0.001));
      expect(sell.realizedPL, closeTo(150.0, 0.01));
      expect(sell.commission, closeTo(2.0, 0.001));
    });

    test('closed-position trades stored even with no matching holding',
        () async {
      final result = TigerBrokersParser().parse(_closedPositionCsv);
      final tCount = await importTrades(result.trades);

      expect(tCount, equals(2));
    });
  });
}
