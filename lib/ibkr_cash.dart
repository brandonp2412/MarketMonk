import 'package:intl/intl.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/utils.dart';

String formatIbkrReportedCash(IbkrAccountValue cash) =>
    '${cash.currency.toUpperCase()} ${NumberFormat.decimalPatternDigits(decimalDigits: 2).format(cash.value)}';

class IbkrCash {
  final IbkrAccountValue reported;
  final double? usd;

  const IbkrCash(this.reported, this.usd);
}

IbkrCash? resolveIbkrCash(IbkrPortfolioSnapshot snapshot) {
  final base = snapshot.netLiquidation?.currency.trim().toUpperCase() ?? '';
  IbkrAccountValue? cash;

  for (final key in [
    if (base.isNotEmpty) 'totalcashvalue:${base.toLowerCase()}',
    'totalcashvalue:base',
    'totalcashvalue',
    if (base.isNotEmpty) 'cashbalance:${base.toLowerCase()}',
    'cashbalance:base',
    'cashbalance',
  ]) {
    final value = snapshot.summaryValue(key);
    if (value == null || !value.value.isFinite) continue;
    final code = value.currency.trim().toUpperCase();
    if (code.isEmpty || code == 'BASE') {
      if (base.isEmpty) continue;
      cash = IbkrAccountValue(value: value.value, currency: base);
    } else {
      cash = IbkrAccountValue(value: value.value, currency: code);
    }
    break;
  }

  if (cash == null) {
    final ledger = {
      for (final entry in snapshot.ledger.entries)
        entry.key.trim().toUpperCase(): entry.value,
    };
    for (final code in ['BASE', if (base.isNotEmpty) base, 'USD']) {
      final values = ledger[code];
      if (values is! Map) continue;
      final raw = values['cashbalance'] ?? values['totalcashvalue'];
      final amount = raw is num ? raw.toDouble() : double.tryParse('$raw');
      if (amount == null || !amount.isFinite) continue;
      final currency = code == 'BASE' ? base : code;
      if (currency.isEmpty) continue;
      cash = IbkrAccountValue(value: amount, currency: currency);
      break;
    }
  }

  if (cash == null) return null;
  final code = cash.currency.toUpperCase();
  if (code == 'USD') return IbkrCash(cash, cash.value);

  final brokerRate = snapshot.summaryValue('exchangerate:usd') ??
      snapshot.summaryValue('exchangerate');
  if (brokerRate != null &&
      brokerRate.currency.toUpperCase() == 'USD' &&
      brokerRate.value.isFinite &&
      brokerRate.value > 0 &&
      base == code) {
    return IbkrCash(cash, cash.value / brokerRate.value);
  }

  final baseValue = snapshot.netLiquidation;
  final usdValue = snapshot.netLiquidationUsd;
  if (baseValue != null &&
      usdValue != null &&
      baseValue.currency.toUpperCase() == code &&
      baseValue.value.isFinite &&
      usdValue.value.isFinite &&
      baseValue.value != 0 &&
      usdValue.value != 0) {
    return IbkrCash(cash, cash.value * usdValue.value / baseValue.value);
  }
  try {
    return IbkrCash(cash, cash.value / requireUsdRate(code));
  } on StateError {
    return IbkrCash(cash, null);
  }
}
