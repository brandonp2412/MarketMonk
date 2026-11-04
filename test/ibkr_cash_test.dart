import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/ibkr_cash.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/utils.dart';

IbkrPortfolioSnapshot cashSnapshot({
  required Map<String, dynamic> summary,
  Map<String, dynamic> ledger = const {},
}) =>
    IbkrPortfolioSnapshot(
      account: 'test',
      positions: const [],
      summary: summary,
      ledger: ledger,
    );

void main() {
  setUp(() {
    allRatesFromUsd
      ..clear()
      ..['USD'] = 1;
  });

  test('prefers account-level total cash over per-currency ledger', () {
    final cash = resolveIbkrCash(
      cashSnapshot(
        summary: {
          'netliquidation': {'value': 1700, 'currency': 'NZD'},
          'netliquidationbycurrency:usd': {'value': 1000, 'currency': 'USD'},
          'totalcashvalue:nzd': {'value': 17, 'currency': 'NZD'},
        },
        ledger: const {
          'USD': {'cashbalance': 8},
        },
      ),
    );
    expect(cash?.reported.value, 17);
    expect(cash?.reported.currency, 'NZD');
    expect(cash?.usd, closeTo(10, 0.00001));
  });

  test('converts NZD cash without a USD net liquidation using FX cache', () {
    allRatesFromUsd['NZD'] = 1.7;
    final cash = resolveIbkrCash(
      cashSnapshot(
        summary: {
          'netliquidation': {'value': 1700, 'currency': 'NZD'},
          'totalcashvalue': {'value': 170, 'currency': 'NZD'},
        },
      ),
    );
    expect(cash?.usd, closeTo(100, 0.00001));
  });

  test('uses broker USD exchange rate before external FX cache', () {
    final cash = resolveIbkrCash(
      cashSnapshot(
        summary: {
          'netliquidation': {'value': 1700, 'currency': 'NZD'},
          'totalcashvalue': {'value': 170, 'currency': 'NZD'},
          'exchangerate:usd': {'value': 1.7, 'currency': 'USD'},
        },
      ),
    );
    expect(cash?.usd, closeTo(100, 0.00001));
  });

  test('retains native cash when no reliable conversion is available', () {
    final cash = resolveIbkrCash(
      cashSnapshot(
        summary: {
          'netliquidation': {'value': 1700, 'currency': 'NZD'},
          'totalcashvalue': {'value': 170, 'currency': 'NZD'},
        },
      ),
    );
    expect(cash?.reported.value, 170);
    expect(cash?.usd, isNull);
  });

  test('falls back to BASE or USD ledger cash, including zero', () {
    final summary = {
      'netliquidation': {'value': 1700, 'currency': 'NZD'},
    };
    final native = resolveIbkrCash(
      cashSnapshot(
        summary: summary,
        ledger: const {
          'BASE': {'cashbalance': 42},
          'USD': {'cashbalance': 100},
        },
      ),
    );
    expect(native?.reported.currency, 'NZD');
    expect(native?.reported.value, 42);
    final usd = resolveIbkrCash(
      cashSnapshot(
        summary: summary,
        ledger: const {
          'USD': {'cashbalance': 0},
        },
      ),
    );
    expect(usd?.reported.currency, 'USD');
    expect(usd?.usd, 0);
  });

  test('old persistent cache requests fresh IBKR cash snapshot', () {
    final old = CachedPortfolioData.fromJson({
      'positions': [],
      'cachedAt': DateTime.now().toIso8601String(),
    });
    expect(old.cashChecked, isFalse);
    final current = CachedPortfolioData(
      positions: const [],
      netLiquidation: const IbkrAccountValue(value: 200, currency: 'NZD'),
      cashBalance: const IbkrAccountValue(value: 3, currency: 'NZD'),
      cashUsd: 1.8,
      cachedAt: DateTime.now(),
    );
    final restored = CachedPortfolioData.fromJson(current.toJson());
    expect(restored.cashChecked, isTrue);
    expect(restored.cashBalance?.value, 3);
    expect(restored.cashBalance?.currency, 'NZD');
    expect(restored.cashUsd, 1.8);
  });
}
