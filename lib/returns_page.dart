import 'package:drift/drift.dart' hide Column;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/ticker_line.dart';
import 'package:market_monk/utils.dart';
import 'package:provider/provider.dart';

class ReturnsPage extends StatefulWidget {
  const ReturnsPage({super.key});

  @override
  State<ReturnsPage> createState() => _ReturnsPageState();
}

class _ReturnsPageState extends State<ReturnsPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  int years = 1;
  int months = 0;
  int days = 0;

  List<_DateValue>? _series;
  List<Position> _positions = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    // Don't clear _series — keep the previous chart visible while reloading.
    setState(() {
      _error = null;
    });

    try {
      final trades = await db.trades.select().get();
      final symbols = trades.map((t) => t.symbol).toSet().toList();
      final prices = await fetchLatestPrices(symbols);
      final positions = computePositions(trades, prices);

      final series = await _buildSeries(positions);
      if (!mounted) return;
      setState(() {
        _positions = positions;
        _series = series;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    }
  }

  Future<List<_DateValue>> _buildSeries(List<Position> positions) async {
    if (positions.isEmpty) return [];

    final now = DateTime.now();
    final after =
        DateTime(now.year - years, now.month - months, now.day - days - 1);

    final sharesMap = {for (final p in positions) p.symbol: p.netShares};

    // Query daily candles per symbol, group/align in Dart to avoid
    // non-deterministic SQLite GROUP BY row selection across symbols.
    final Map<String, Map<DateTime, double>> pricesBySymbol = {};

    for (final symbol in sharesMap.keys) {
      final rows = await (db.candles.select()
            ..where(
              (c) => c.symbol.equals(symbol) & c.date.isBiggerThanValue(after),
            )
            ..orderBy([
              (c) => OrderingTerm(expression: c.date, mode: OrderingMode.asc),
            ]))
          .get();

      pricesBySymbol[symbol] = {
        for (final c in rows)
          DateTime(c.date.year, c.date.month, c.date.day): c.close,
      };
    }

    // Collect all dates that appear in any symbol's candles.
    final allDates = <DateTime>{};
    for (final prices in pricesBySymbol.values) {
      allDates.addAll(prices.keys);
    }
    final sortedDates = allDates.toList()..sort();

    // Forward-fill each symbol's price across all dates, then sum the
    // portfolio value. This ensures every date gets a complete total even
    // when symbols have candles on slightly different trading days.
    final Map<String, double> lastKnown = {};
    final Map<DateTime, double> valueByDate = {};

    for (final date in sortedDates) {
      for (final symbol in sharesMap.keys) {
        final price = pricesBySymbol[symbol]?[date];
        if (price != null) lastKnown[symbol] = price;
      }
      // Only emit a point once every symbol has at least one price.
      if (lastKnown.length == sharesMap.length) {
        var total = 0.0;
        for (final entry in sharesMap.entries) {
          total += entry.value * lastKnown[entry.key]!;
        }
        valueByDate[date] = total;
      }
    }

    var series = valueByDate.entries
        .map((e) => _DateValue(e.key, e.value))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    // For periods longer than 5 months, downsample to weekly points
    // (last trading day of each ISO week) to keep the chart readable.
    if (years > 0 || months > 5) {
      final Map<String, _DateValue> byWeek = {};
      for (final dv in series) {
        final key = '${dv.date.year}-${_isoWeek(dv.date)}';
        final existing = byWeek[key];
        if (existing == null || dv.date.isAfter(existing.date)) {
          byWeek[key] = dv;
        }
      }
      series = byWeek.values.toList()..sort((a, b) => a.date.compareTo(b.date));
    }

    return series;
  }

  // Returns the ISO week number for [date].
  static int _isoWeek(DateTime date) {
    final startOfYear = DateTime(date.year, 1, 1);
    return (date.difference(startOfYear).inDays / 7).floor() + 1;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final settings = context.watch<SettingsState>();

    final yearOptions = [1, 2, 3, 5, 10];
    final monthOptions = [1, 2, 3, 6];

    List<Widget> timeButtons = [
      Tooltip(
        message: 'Show the last 5 days of prices',
        child: OutlinedButton(
          onPressed: () {
            setState(() {
              days = 5;
              years = 0;
              months = 0;
            });
            _load();
          },
          style: OutlinedButton.styleFrom(
            side: BorderSide(
              color: days == 5
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
            ),
          ),
          child: const Text("5d"),
        ),
      ),
      for (final option in monthOptions)
        Tooltip(
          message: 'Show the last $option months of prices',
          child: OutlinedButton(
            onPressed: () {
              setState(() {
                months = option;
                years = 0;
                days = 0;
              });
              _load();
            },
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: option == months
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
              ),
            ),
            child: Text("${option}m"),
          ),
        ),
      for (final option in yearOptions)
        Tooltip(
          message: 'Show the last $option years of prices',
          child: OutlinedButton(
            onPressed: () {
              setState(() {
                years = option;
                months = 0;
                days = 0;
              });
              _load();
            },
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: option == years
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
              ),
            ),
            child: Text("${option}y"),
          ),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: ListView(
        children: [
          const SizedBox(height: 8),
          Wrap(alignment: WrapAlignment.center, children: timeButtons),
          _buildChart(context, settings),
          _buildSummary(context),
        ],
      ),
    );
  }

  Widget _buildChart(BuildContext context, SettingsState settings) {
    final chartHeight = MediaQuery.of(context).size.height * 0.3;

    Widget inner;
    if (_error != null) {
      inner = Center(child: Text(_error!));
    } else if (_series == null) {
      // First-ever load: no cached data yet, show a spinner.
      inner = const Center(child: CircularProgressIndicator());
    } else if (_series!.isEmpty) {
      inner = const Center(child: Text('No candle data for current holdings'));
    } else {
      final spots = <FlSpot>[];
      for (var i = 0; i < _series!.length; i++) {
        spots.add(FlSpot(i.toDouble(), _series![i].value));
      }
      inner = TickerLine(dates: _series!.map((d) => d.date), spots: spots);
    }

    return SizedBox(
      height: chartHeight,
      child: Stack(
        children: [
          inner,
        ],
      ),
    );
  }

  Widget _buildSummary(BuildContext context) {
    if (_series == null || _series!.isEmpty || _positions.isEmpty) {
      return const SizedBox();
    }

    final first = _series!.first.value;
    final last = _series!.last.value;
    final pctChange = safePercentChange(first, last);
    final color = pctChange >= 0 ? Colors.green : Colors.redAccent;
    final totalValue = _positions.fold(0.0, (s, p) => s + p.currentValue);
    final totalCost = _positions.fold(0.0, (s, p) => s + p.costBasis);
    final unrealized = totalValue - totalCost;
    final unrealizedPct = totalCost > 0 ? (unrealized / totalCost) * 100 : 0.0;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    pctChange >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                    color: color,
                  ),
                  Text(
                    '${pctChange >= 0 ? '+' : ''}${pctChange.toStringAsFixed(2)}%',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge!
                        .copyWith(color: color),
                  ),
                ],
              ),
              Text(
                fmtCurrency(last),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Unrealized P/L: '
            '${unrealized >= 0 ? '+' : ''}${fmtCurrency(unrealized)}'
            ' (${unrealizedPct.toStringAsFixed(2)}%)',
            style: TextStyle(
              color: unrealized >= 0 ? Colors.green : Colors.redAccent,
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () async {
              clearAllSyncCache();
              final trades = await db.trades.select().get();
              final symbols = trades.map((t) => t.symbol).toSet();
              for (final symbol in symbols) {
                await syncCandles(symbol);
              }
              await _load();
            },
            label: const Text('Refresh'),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}

class _DateValue {
  final DateTime date;
  final double value;
  const _DateValue(this.date, this.value);
}
