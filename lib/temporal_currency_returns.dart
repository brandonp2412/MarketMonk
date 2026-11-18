import 'package:market_monk/database.dart';
import 'package:market_monk/market_data.dart';
import 'package:market_monk/portfolio_returns.dart';
import 'package:market_monk/sqlite_settings.dart';

/// Calendar-day FX keys, independent of the device's timezone.
DateTime temporalFxDay(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day);

/// Fetch only the trade dates required by the selected display currency.
/// Missing rates are not silently replaced with today's spot rate.
Future<Map<DateTime, double>> loadTemporalRatesForDates(
  Iterable<DateTime> dates,
  String displayCurrency, {
  bool cacheOnly = false,
  Future<double> Function(String currency, DateTime date)? rateLoader,
  void Function(Map<DateTime, double> rates)? onBatch,
}) async {
  final code = displayCurrency.toUpperCase();
  final days = <DateTime, DateTime>{};
  for (final date in dates) {
    days.putIfAbsent(temporalFxDay(date), () => date);
  }
  final ordered = days.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
  if (code == 'USD') {
    return {for (final entry in ordered) entry.key: 1.0};
  }
  final settings = await SqliteSettings.getInstance();
  final rates = <DateTime, double>{};
  final missing = <MapEntry<DateTime, DateTime>>[];
  for (final entry in ordered) {
    final key =
        'historicalUsdRate_${code}_${entry.key.toIso8601String().substring(0, 10)}';
    final cached = settings.getDouble(key);
    if (cached != null && cached.isFinite && cached > 0) {
      rates[entry.key] = cached;
    } else if (!cacheOnly) {
      missing.add(entry);
    }
  }
  onBatch?.call(Map<DateTime, double>.of(rates));
  for (var offset = 0; offset < missing.length; offset += 4) {
    final batch = missing.skip(offset).take(4);
    final found = await Future.wait(
      batch.map((entry) async {
        final day = entry.key;
        try {
          final loaded =
              await (rateLoader ?? historicalTradeUsdRate)(code, entry.value);
          if (!loaded.isFinite || loaded <= 0) {
            return (date: day, rate: null as double?);
          }
          return (date: day, rate: loaded);
        } catch (_) {
          return (date: day, rate: null as double?);
        }
      }),
    );
    for (final item in found) {
      if (item.rate != null) rates[item.date] = item.rate!;
    }
    onBatch?.call(Map<DateTime, double>.of(rates));
  }
  return rates;
}

Future<Map<DateTime, double>> loadTemporalTradeRates(
  Iterable<Trade> trades,
  String displayCurrency, {
  bool cacheOnly = false,
  Future<double> Function(String currency, DateTime date)? rateLoader,
  void Function(Map<DateTime, double> rates)? onBatch,
}) =>
    loadTemporalRatesForDates(
      [
        for (final trade in trades)
          if (trade.quantity != 0) trade.tradeDate,
      ],
      displayCurrency,
      cacheOnly: cacheOnly,
      rateLoader: rateLoader,
      onBatch: onBatch,
    );

/// Reconstruct a cost basis in the chosen currency at each purchase date,
/// reducing that basis proportionally on partial sales (moving-average method).
/// The broker's verified USD basis remains authoritative for fees and splits.
/// Returns null for missing historical rates or ambiguous corporate actions.
PortfolioReturn? temporalOpenHoldingReturn({
  required Position position,
  required List<Trade> trades,
  required String displayCurrency,
  required Map<DateTime, double> ratesByDate,
}) {
  final code = displayCurrency.toUpperCase();
  if (code == 'USD') {
    return PortfolioReturn(position.unrealizedPL, position.costBasis);
  }
  final spot = allRatesFromUsd[code];
  if (spot == null || !spot.isFinite || spot <= 0) return null;
  if (trades.isEmpty || position.netShares <= 0) return null;
  final ordered = List<Trade>.of(trades)
    ..sort((a, b) {
      final byDate = a.tradeDate.compareTo(b.tradeDate);
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });
  var shares = 0.0;
  var avgUsd = 0.0;
  var avgDisplay = 0.0;
  final buyDates = <DateTime>{};
  for (final trade in ordered) {
    final qty = trade.quantity;
    if (qty > 0) {
      final date = temporalFxDay(trade.tradeDate);
      final rate = ratesByDate[date];
      final usdPrice = verifiedTradeAmountUsd(trade, trade.price);
      if ((code != 'USD' && trade.rawCurrency == null) ||
          rate == null ||
          !rate.isFinite ||
          rate <= 0 ||
          usdPrice == null ||
          !usdPrice.isFinite ||
          usdPrice <= 0) {
        return null;
      }
      buyDates.add(date);
      final previous = shares > 0 ? shares : 0.0;
      final shortShares = shares < 0 ? -shares : 0.0;
      final opening = qty > shortShares ? qty - shortShares : 0.0;
      shares += qty;
      if (shares > 0) {
        avgUsd = previous > 0
            ? (previous * avgUsd + opening * usdPrice) / shares
            : usdPrice;
        avgDisplay = previous > 0
            ? (previous * avgDisplay + opening * usdPrice * rate) / shares
            : usdPrice * rate;
      } else {
        avgUsd = 0;
        avgDisplay = 0;
      }
    } else if (qty < 0) {
      shares += qty;
      if (shares <= 0) {
        avgUsd = 0;
        avgDisplay = 0;
      }
    }
  }
  final matchingShares = (shares - position.netShares).abs() < 0.0001;
  if (!matchingShares && buyDates.length != 1) return null;
  // One unambiguous acquisition date survives missing split/corporate actions:
  // apply that day's FX to the broker-authoritative original USD cost basis.
  final historicalRate = matchingShares && avgUsd > 0 && avgDisplay > 0
      ? avgDisplay / avgUsd
      : buyDates.length == 1
          ? ratesByDate[buyDates.single]
          : null;
  if (historicalRate == null) return null;
  final currentRate = requireUsdRate(code);
  final displayedBasis = position.costBasis * historicalRate;
  final displayedValue = position.currentValue * currentRate;
  // PortfolioReturn remains USD-normalised for existing fmtCurrency callers;
  // its percentage is calculated from purchase-date currency amounts.
  return PortfolioReturn(
    (displayedValue - displayedBasis) / currentRate,
    displayedBasis / currentRate,
  );
}

/// Sale proceeds and purchase-date cost converted on their respective days.
/// Returns USD-normalised amounts for existing fmtCurrency callers.
double? temporalRealizedTradeGain({
  required List<Trade> trades,
  required String displayCurrency,
  required Map<DateTime, double> ratesByDate,
}) {
  if (trades.isEmpty) return 0;
  final code = displayCurrency.toUpperCase();
  final currentRate = allRatesFromUsd[code];
  if (currentRate == null || !currentRate.isFinite || currentRate <= 0) {
    return null;
  }
  final ordered = List<Trade>.of(trades)
    ..sort((a, b) {
      final date = a.tradeDate.compareTo(b.tradeDate);
      return date != 0 ? date : a.id.compareTo(b.id);
    });
  var openShares = 0.0;
  var averageCost = 0.0;
  var realized = 0.0;
  for (final trade in ordered) {
    final rate =
        code == 'USD' ? 1.0 : ratesByDate[temporalFxDay(trade.tradeDate)];
    final priceUsd = verifiedTradeAmountUsd(trade, trade.price);
    final commissionUsd = verifiedTradeAmountUsd(trade, trade.commission);
    if ((code != 'USD' && trade.rawCurrency == null) ||
        rate == null ||
        priceUsd == null ||
        commissionUsd == null ||
        !rate.isFinite ||
        rate <= 0) {
      return null;
    }
    if (trade.quantity > 0) {
      final quantity = trade.quantity;
      averageCost = (openShares * averageCost +
              (quantity * priceUsd + commissionUsd) * rate) /
          (openShares + quantity);
      openShares += quantity;
    } else if (trade.quantity < 0) {
      final count = -trade.quantity;
      // Unrecorded splits/corporate actions need the broker's ledger.
      if (count > openShares + 0.0001) return null;
      realized +=
          count * (priceUsd * rate - averageCost) - commissionUsd * rate;
      openShares = (openShares - count).clamp(0, double.infinity);
      if (openShares == 0) averageCost = 0;
    }
  }
  return realized / currentRate;
}
