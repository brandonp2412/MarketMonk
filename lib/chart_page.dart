import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:market_monk/candle_ticker.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/edit_ticker_page.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/settings_page.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/ticker_line.dart';
import 'package:market_monk/utils.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _ChartMode { portfolio, searching, stock }

class ChartPage extends StatefulWidget {
  const ChartPage({super.key});

  @override
  State<ChartPage> createState() => ChartPageState();
}

class ChartPageState extends State<ChartPage>
    with AutomaticKeepAliveClientMixin {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  _ChartMode _mode = _ChartMode.portfolio;
  String? _selectedSymbol;
  String? _favoriteStock;
  bool _networkLoading = false;

  // Shared time period
  int years = 1;
  int months = 0;
  int days = 0;

  // Stock chart
  Stream<List<CandleTicker>>? _stockStream;

  // Portfolio chart
  List<_DateValue>? _portfolioSeries;
  List<Position> _positions = [];
  String? _portfolioError;
  bool _portfolioLoading = false;

  // Search
  List<StockResult> _searchResults = [];
  bool _searchLoading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadFavorite();
    _loadPortfolio();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadFavorite() async {
    final prefs = await SharedPreferences.getInstance();
    final fav = prefs.getString('favoriteStock');
    if (mounted) setState(() => _favoriteStock = fav);
  }

  Future<void> _loadPortfolio() async {
    if (!mounted) return;
    setState(() {
      _portfolioError = null;
      _portfolioLoading = _portfolioSeries == null;
    });
    try {
      final trades = await db.trades.select().get();
      final symbols = trades.map((t) => t.symbol).toSet().toList();
      final prices = await fetchLatestPrices(symbols);
      final positions = computePositions(trades, prices);
      final series = await _buildPortfolioSeries(positions);
      if (!mounted) return;
      setState(() {
        _positions = positions;
        _portfolioSeries = series;
        _portfolioLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _portfolioError = e.toString();
        _portfolioLoading = false;
      });
    }
  }

  Future<List<_DateValue>> _buildPortfolioSeries(
    List<Position> positions,
  ) async {
    if (positions.isEmpty) return [];

    final now = DateTime.now();
    final after = days > 0
        ? DateTime(now.year, now.month, now.day - days - 4)
        : DateTime(now.year - years, now.month - months, now.day - 1);

    final sharesMap = {for (final p in positions) p.symbol: p.netShares};
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

    final allDates = <DateTime>{};
    for (final prices in pricesBySymbol.values) {
      allDates.addAll(prices.keys);
    }
    final sortedDates = allDates.toList()..sort();

    final Map<String, double> lastKnown = {};
    final Map<DateTime, double> valueByDate = {};

    for (final date in sortedDates) {
      for (final symbol in sharesMap.keys) {
        final price = pricesBySymbol[symbol]?[date];
        if (price != null) lastKnown[symbol] = price;
      }
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

    if (days > 0 && series.length > days) {
      series = series.sublist(series.length - days);
    } else if (years > 0 || months > 5) {
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

  static int _isoWeek(DateTime date) {
    final startOfYear = DateTime(date.year, 1, 1);
    return (date.difference(startOfYear).inDays / 7).floor() + 1;
  }

  void _onSearchChanged(String text) {
    if (text.isEmpty) {
      _debounce?.cancel();
      setState(() {
        _mode = _ChartMode.portfolio;
        _searchResults = [];
        _searchLoading = false;
      });
      return;
    }
    setState(() {
      _mode = _ChartMode.searching;
      _searchLoading = true;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final api = YahooFinanceApi();
      try {
        final results = await api.searchTickers(text);
        if (!mounted) return;
        setState(() {
          _searchResults = results;
          _searchLoading = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _searchLoading = false);
      }
    });
  }

  void _selectStock(StockResult result) => _selectSymbol(result.symbol);

  void _selectSymbol(String symbol) {
    _searchFocus.unfocus();
    setState(() {
      _mode = _ChartMode.stock;
      _selectedSymbol = symbol;
      _networkLoading = true;
    });
    _setStockStream(symbol);
    syncCandles(symbol).then((_) {
      if (mounted) {
        _setStockStream(symbol);
        setState(() => _networkLoading = false);
      }
    }).catchError((_) {
      if (mounted) setState(() => _networkLoading = false);
    });
  }

  void _setStockStream(String symbol) {
    final now = DateTime.now();
    final after = days > 0
        ? DateTime(now.year, now.month, now.day - days - 4)
        : DateTime(now.year - years, now.month - months, now.day - 1);

    const weekExpression = CustomExpression<String>(
      "STRFTIME('%Y-%m-%W', DATE(\"date\", 'unixepoch', 'localtime'))",
    );
    Iterable<Expression<Object>> groupBy = [db.candles.date];
    if (years > 0 || months > 5) groupBy = [weekExpression];

    final capturedDays = days;
    _stockStream = (db.selectOnly(db.candles)
          ..addColumns([db.candles.date, db.candles.close])
          ..where(
            db.candles.symbol.equals(symbol) &
                db.candles.date.isBiggerThanValue(after),
          )
          ..orderBy([
            OrderingTerm(expression: db.candles.date, mode: OrderingMode.asc),
          ])
          ..groupBy(groupBy))
        .watch()
        .map((results) {
      var list = results
          .map(
            (result) => CandleTicker(
              candle: CandlesCompanion(
                date: Value(result.read(db.candles.date)!),
                close: Value(result.read(db.candles.close)!),
              ),
            ),
          )
          .toList();
      if (capturedDays > 0 && list.length > capturedDays) {
        list = list.sublist(list.length - capturedDays);
      }
      return list;
    });
    setState(() {});
  }

  void _onPeriodSelected({int y = 0, int m = 0, int d = 0}) {
    setState(() {
      years = y;
      months = m;
      days = d;
    });
    if (_mode == _ChartMode.stock && _selectedSymbol != null) {
      _setStockStream(_selectedSymbol!);
    } else {
      _loadPortfolio();
    }
  }

  void _clearSearch() {
    _searchController.clear();
    _searchFocus.unfocus();
    _debounce?.cancel();
    setState(() {
      _mode = _ChartMode.portfolio;
      _searchResults = [];
      _selectedSymbol = null;
      _searchLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final settings = context.watch<SettingsState>();

    return Column(
      children: [
        _buildSearchBar(),
        if (_networkLoading)
          LinearProgressIndicator(
            minHeight: 2,
            color: Theme.of(context).colorScheme.primary,
          ),
        Expanded(
          child: _mode == _ChartMode.searching
              ? _buildSearchResults()
              : _buildChartContent(settings),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    final hasText = _searchController.text.isNotEmpty;
    final leading = hasText
        ? IconButton(
            icon: const Icon(Icons.arrow_back),
            padding: const EdgeInsets.only(left: 16, right: 8),
            onPressed: _clearSearch,
          )
        : const Padding(
            padding: EdgeInsets.only(left: 16, right: 8),
            child: Icon(Icons.search),
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: SearchBar(
        controller: _searchController,
        focusNode: _searchFocus,
        hintText: 'Search stocks...',
        leading: leading,
        onChanged: _onSearchChanged,
        onTap: () => _searchController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _searchController.text.length,
        ),
        onSubmitted: (text) {
          if (text.isNotEmpty) _onSearchChanged(text);
        },
        trailing: [
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            ),
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    final query = _searchController.text.trim().toUpperCase();
    if (_searchLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // "Use anyway" tile — always shown at the bottom so the user can force a
    // known symbol that the Yahoo Finance search API doesn't surface (e.g. GLD).
    final useAnywayTile = ListTile(
      leading: const Icon(Icons.open_in_new),
      title: Text('Use "$query" anyway'),
      subtitle: const Text('Load chart for this exact ticker'),
      onTap: () => _selectSymbol(query),
    );

    if (_searchResults.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [useAnywayTile],
      );
    }

    return ListView.builder(
      itemCount: _searchResults.length + 1,
      itemBuilder: (context, i) {
        if (i == _searchResults.length) return useAnywayTile;
        final r = _searchResults[i];
        final name = r.longname.isNotEmpty ? r.longname : r.shortname;
        return ListTile(
          title: Text(r.symbol),
          subtitle: Text(name),
          trailing: Text(
            r.exchange,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          onTap: () => _selectStock(r),
        );
      },
    );
  }

  Widget _buildChartContent(SettingsState settings) {
    return ListView(
      children: [
        const SizedBox(height: 8),
        _buildTimeChips(),
        const SizedBox(height: 4),
        if (_mode == _ChartMode.stock)
          ..._buildStockContent(settings)
        else
          ..._buildPortfolioContent(settings),
      ],
    );
  }

  Widget _buildTimeChips() {
    final options = [
      ('5d', 0, 0, 5),
      ('1m', 0, 1, 0),
      ('2m', 0, 2, 0),
      ('3m', 0, 3, 0),
      ('6m', 0, 6, 0),
      ('1y', 1, 0, 0),
      ('2y', 2, 0, 0),
      ('3y', 3, 0, 0),
      ('5y', 5, 0, 0),
      ('10y', 10, 0, 0),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          for (final (label, y, m, d) in options)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: _PeriodChip(
                label: label,
                selected: y == years && m == months && d == days,
                onTap: () => _onPeriodSelected(y: y, m: m, d: d),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildStockContent(SettingsState settings) {
    return [
      StreamBuilder(
        stream: _stockStream,
        builder: (context, snapshot) =>
            _buildStockChart(context, snapshot, settings),
      ),
      StreamBuilder(
        stream: _stockStream,
        builder: _buildStockSummary,
      ),
    ];
  }

  Widget _buildStockChart(
    BuildContext context,
    AsyncSnapshot<List<CandleTicker>> snapshot,
    SettingsState settings,
  ) {
    final height = MediaQuery.of(context).size.height * 0.35;
    if (snapshot.hasError) {
      return SizedBox(
        height: height,
        child: Center(child: Text(snapshot.error.toString())),
      );
    }
    if (snapshot.data == null || snapshot.data!.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final candles = snapshot.data!.map((tc) => tc.candle).toList();
    final spots = <FlSpot>[
      for (var i = 0; i < candles.length; i++)
        FlSpot(i.toDouble(), candles[i].close.value),
    ];

    return SizedBox(
      height: height,
      child: TickerLine(
        dates: candles.map((c) => c.date.value),
        spots: spots,
      ),
    );
  }

  Widget _buildStockSummary(
    BuildContext context,
    AsyncSnapshot<List<CandleTicker>> snapshot,
  ) {
    if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox();

    final candles = snapshot.data!.map((tc) => tc.candle).toList();
    final pct = safePercentChange(
      candles.first.close.value,
      candles.last.close.value,
    );
    final color = pct >= 0 ? Colors.green : Colors.redAccent;
    final symbol = _selectedSymbol ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    pct >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                    color: color,
                  ),
                  Text(
                    '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge!
                        .copyWith(color: color),
                  ),
                ],
              ),
              Text(
                '\$${candles.last.close.value.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              _ActionChip(
                icon: Icons.add,
                label: 'Add trade',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditTickerPage(symbol: symbol),
                  ),
                ),
              ),
              _ActionChip(
                icon: _favoriteStock == symbol
                    ? Icons.favorite
                    : Icons.favorite_border,
                label: 'Favorite',
                onTap: () async {
                  final ctx = context;
                  final prefs = await SharedPreferences.getInstance();
                  if (!ctx.mounted) return;
                  if (_favoriteStock == symbol) {
                    prefs.remove('favoriteStock');
                    setState(() => _favoriteStock = null);
                    toast(ctx, 'Removed as favorite');
                  } else {
                    prefs.setString('favoriteStock', symbol);
                    setState(() => _favoriteStock = symbol);
                    toast(ctx, 'Set as favorite');
                  }
                },
              ),
              _ActionChip(
                icon: Icons.refresh,
                label: 'Refresh',
                onTap: () async {
                  setState(() => _networkLoading = true);
                  clearSyncCache(symbol);
                  await syncCandles(symbol);
                  if (_selectedSymbol != null)
                    _setStockStream(_selectedSymbol!);
                  if (mounted) setState(() => _networkLoading = false);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPortfolioContent(SettingsState settings) {
    return [
      _buildPortfolioChart(context, settings),
      _buildPortfolioSummary(context, settings),
    ];
  }

  Widget _buildPortfolioChart(BuildContext context, SettingsState settings) {
    final height = MediaQuery.of(context).size.height * 0.38;

    if (_portfolioError != null) {
      return SizedBox(
        height: height,
        child: Center(child: Text(_portfolioError!)),
      );
    }
    if (_portfolioLoading || _portfolioSeries == null) {
      return SizedBox(
        height: height,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_portfolioSeries!.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            _positions.isEmpty
                ? 'No trades yet.\nSearch for a stock above to get started.'
                : 'No candle data for current holdings.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      );
    }

    final spots = <FlSpot>[
      for (var i = 0; i < _portfolioSeries!.length; i++)
        FlSpot(i.toDouble(), _portfolioSeries![i].value),
    ];

    return SizedBox(
      height: height,
      child: TickerLine(
        dates: _portfolioSeries!.map((d) => d.date),
        spots: spots,
      ),
    );
  }

  Widget _buildPortfolioSummary(BuildContext context, SettingsState settings) {
    if (_portfolioSeries == null ||
        _portfolioSeries!.isEmpty ||
        _positions.isEmpty) {
      return const SizedBox();
    }

    final first = _portfolioSeries!.first.value;
    final last = _portfolioSeries!.last.value;
    final pct = safePercentChange(first, last);
    final color = pct >= 0 ? Colors.green : Colors.redAccent;
    final totalValue = _positions.fold(0.0, (s, p) => s + p.currentValue);
    final totalCost = _positions.fold(0.0, (s, p) => s + p.costBasis);
    final unrealized = totalValue - totalCost;
    final unrealizedPct = totalCost > 0 ? (unrealized / totalCost) * 100 : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    pct >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                    color: color,
                  ),
                  Text(
                    '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%',
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
          const SizedBox(height: 8),
          Text(
            'Unrealized P/L: '
            '${unrealized >= 0 ? '+' : ''}${fmtCurrency(unrealized)}'
            ' (${unrealizedPct.toStringAsFixed(2)}%)',
            style: TextStyle(
              color: unrealized >= 0 ? Colors.green : Colors.redAccent,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<String>(
                value: settings.displayCurrency,
                isDense: true,
                underline: const SizedBox(),
                items: supportedCurrencies
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (value) {
                  if (value != null) settings.setDisplayCurrency(value);
                },
              ),
              _ActionChip(
                icon: Icons.refresh,
                label: 'Refresh',
                onTap: () async {
                  setState(() => _networkLoading = true);
                  clearAllSyncCache();
                  final trades = await db.trades.select().get();
                  final symbols = trades.map((t) => t.symbol).toSet();
                  for (final s in symbols) {
                    await syncCandles(s);
                  }
                  await _loadPortfolio();
                  if (mounted) setState(() => _networkLoading = false);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

class _DateValue {
  final DateTime date;
  final double value;

  const _DateValue(this.date, this.value);
}

/// A chip button styled after Flexify's DaySelector — animated border
/// highlights the selected state.
class _PeriodChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.7)
              : colorScheme.outline.withValues(alpha: 0.3),
          width: selected ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Center(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
                child: Text(label),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A chip-styled action button (no toggle state, always consistent border).
class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
