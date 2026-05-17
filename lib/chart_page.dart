import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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

  static const _accountColors = [
    Color(0xFF2196F3),
    Color(0xFFFF9800),
    Color(0xFF4CAF50),
    Color(0xFF9C27B0),
    Color(0xFFE91E63),
    Color(0xFF00BCD4),
    Color(0xFFFF5722),
    Color(0xFF607D8B),
  ];

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

  // Portfolio chart — keyed by account name
  Map<String, List<_DateValue>> _portfolioSeriesByAccount = {};
  String? _portfolioError;
  bool _portfolioLoading = false;
  final Set<String> _hiddenAccounts = {};

  // Search
  List<StockResult> _searchResults = [];
  bool _searchLoading = false;
  Timer? _debounce;

  int _lastTradesVersion = 0;
  String _lastAccountsKey = '';

  @override
  void initState() {
    super.initState();
    _loadFavorite();
    _loadPeriodThenPortfolios();
    _syncCandlesInBackground();
  }

  Future<void> _loadPeriodThenPortfolios() async {
    final prefs = await SharedPreferences.getInstance();
    final y = prefs.getInt('chartPeriodYears') ?? 1;
    final m = prefs.getInt('chartPeriodMonths') ?? 0;
    final d = prefs.getInt('chartPeriodDays') ?? 0;
    if (mounted)
      setState(() {
        years = y;
        months = m;
        days = d;
      });
    _loadAllPortfolios();
  }

  Future<void> _savePeriod() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('chartPeriodYears', years);
    await prefs.setInt('chartPeriodMonths', months);
    await prefs.setInt('chartPeriodDays', days);
  }

  Future<void> _syncCandlesInBackground() async {
    if (!mounted) return;
    final accountManager = context.read<AccountManager>();
    try {
      for (final accountName in accountManager.accounts) {
        final isActive = accountName == accountManager.activeAccount;
        final accountDb = isActive
            ? db
            : (accountName == 'Default'
                ? Database()
                : Database('market-monk-$accountName'));
        try {
          final trades = await accountDb.trades.select().get();
          final symbols = trades.map((t) => t.symbol).toSet().toList();
          for (final s in symbols) {
            await syncCandles(s, database: accountDb);
          }
        } finally {
          if (!isActive) await accountDb.close();
        }
      }
    } catch (_) {}
    if (mounted) _loadAllPortfolios();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final version = context.watch<SettingsState>().tradesVersion;
    if (version != _lastTradesVersion) {
      _lastTradesVersion = version;
      if (version > 0) _loadAllPortfolios();
    }
    final accountManager = context.watch<AccountManager>();
    final accountsKey = accountManager.accounts.join(',');
    if (accountsKey != _lastAccountsKey) {
      _lastAccountsKey = accountsKey;
      _loadAllPortfolios();
      if (_selectedSymbol != null) _setStockStream(_selectedSymbol!);
    }
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

  Future<void> _loadAllPortfolios() async {
    if (!mounted) return;
    final accountManager = context.read<AccountManager>();
    final accounts = accountManager.accounts;

    setState(() {
      _portfolioError = null;
      _portfolioLoading = _portfolioSeriesByAccount.isEmpty;
    });

    final newSeries = <String, List<_DateValue>>{};
    String? firstError;

    for (final accountName in accounts) {
      final isActive = accountName == accountManager.activeAccount;
      final accountDb = isActive
          ? db
          : (accountName == 'Default'
              ? Database()
              : Database('market-monk-$accountName'));
      try {
        final trades = await accountDb.trades.select().get();
        final symbols = trades.map((t) => t.symbol).toSet().toList();
        final prices = await fetchLatestPrices(symbols, database: accountDb);
        final positions = computePositions(trades, prices);
        newSeries[accountName] = await _buildPortfolioSeries(
          positions,
          accountDb,
        );
      } catch (e) {
        newSeries[accountName] = [];
        firstError ??= e.toString();
      } finally {
        if (!isActive) await accountDb.close();
      }
    }

    if (!mounted) return;
    setState(() {
      _portfolioSeriesByAccount = newSeries;
      _portfolioError = firstError;
      _portfolioLoading = false;
    });
  }

  Future<List<_DateValue>> _buildPortfolioSeries(
    List<Position> positions,
    Database accountDb,
  ) async {
    if (positions.isEmpty) return [];

    final now = DateTime.now();
    final after = days > 0
        ? DateTime(now.year, now.month, now.day - days - 4)
        : DateTime(now.year - years, now.month - months, now.day - 1);

    final sharesMap = {for (final p in positions) p.symbol: p.netShares};
    final Map<String, Map<DateTime, double>> pricesBySymbol = {};

    for (final symbol in sharesMap.keys) {
      final rows = await (accountDb.candles.select()
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
    _savePeriod();
    if (_mode == _ChartMode.stock && _selectedSymbol != null) {
      _setStockStream(_selectedSymbol!);
    } else {
      _loadAllPortfolios();
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
        if (!_networkLoading) const SizedBox(height: 2),
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

    return Center(
      child: SingleChildScrollView(
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
    final dollarChange = candles.last.close.value - candles.first.close.value;

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
          const SizedBox(height: 4),
          Text(
            '${dollarChange >= 0 ? '+' : '-'}\$${dollarChange.abs().toStringAsFixed(2)} period change',
            style: TextStyle(color: color, fontSize: 13),
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
      _buildPortfolioLegend(context),
      _buildPortfolioSummary(context, settings),
    ];
  }

  Widget _buildPortfolioChart(BuildContext context, SettingsState settings) {
    final height = MediaQuery.of(context).size.height * 0.38;

    if (_portfolioLoading) {
      return SizedBox(
        height: height,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_portfolioError != null && _portfolioSeriesByAccount.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(child: Text(_portfolioError!)),
      );
    }

    final accounts = context.read<AccountManager>().accounts;
    final visibleSeries = {
      for (final entry in _portfolioSeriesByAccount.entries)
        if (!_hiddenAccounts.contains(entry.key) && entry.value.isNotEmpty)
          entry.key: entry.value,
    };

    if (visibleSeries.isEmpty) {
      final allEmpty = _portfolioSeriesByAccount.values.every((s) => s.isEmpty);
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            allEmpty
                ? 'No trades yet.\nSearch for a stock above to get started.'
                : 'All portfolios hidden — tap a legend item to show it.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      );
    }

    // Union of all visible dates → shared X index axis
    final allDates = <DateTime>{};
    for (final series in visibleSeries.values) {
      for (final dv in series) allDates.add(dv.date);
    }
    final sortedDates = allDates.toList()..sort();
    final dateIndex = <DateTime, int>{
      for (var i = 0; i < sortedDates.length; i++) sortedDates[i]: i,
    };

    final singleLine = visibleSeries.length == 1;
    final lineBarsData = <LineChartBarData>[];
    for (final entry in visibleSeries.entries) {
      final idx = accounts.indexOf(entry.key);
      final color = _accountColors[idx.clamp(0, _accountColors.length - 1)];
      final spots = entry.value
          .map((dv) => FlSpot(dateIndex[dv.date]!.toDouble(), dv.value))
          .toList();
      lineBarsData.add(
        LineChartBarData(
          spots: spots,
          color: color,
          isCurved: settings.curveLines,
          curveSmoothness: settings.curveSmoothness,
          preventCurveOverShooting: true,
          barWidth: 2.5,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: singleLine,
            gradient: LinearGradient(
              colors: [
                color.withValues(alpha: 0.3),
                Theme.of(context).colorScheme.surface.withValues(alpha: 0.0),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      );
    }

    final formatter = DateFormat(settings.dateFormat);
    final visibleKeys = visibleSeries.keys.toList();

    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.only(right: 32, top: 16),
        child: LineChart(
          LineChartData(
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: true, reservedSize: 45),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 27,
                  interval: 1,
                  getTitlesWidget: (value, meta) {
                    final i = value.toInt();
                    if (i < 0 || i >= sortedDates.length) {
                      return const SizedBox();
                    }
                    final screenWidth = MediaQuery.of(context).size.width;
                    final labelCount = (screenWidth / 120).floor();
                    final indices = List.generate(labelCount, (n) {
                      return ((sortedDates.length - 1) * n / (labelCount - 1))
                          .round();
                    });
                    if (!indices.contains(i)) return const SizedBox();
                    return SideTitleWidget(
                      meta: meta,
                      child: Text(
                        formatter.format(sortedDates[i]),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            lineBarsData: lineBarsData,
            gridData: const FlGridData(show: false),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => Theme.of(context).colorScheme.surface,
                getTooltipItems: (touchedSpots) {
                  return touchedSpots.map((spot) {
                    final i = spot.x.toInt();
                    final date = (i >= 0 && i < sortedDates.length)
                        ? formatter.format(sortedDates[i])
                        : '';
                    final accountName = spot.barIndex < visibleKeys.length
                        ? visibleKeys[spot.barIndex]
                        : '';
                    final accountIdx = accounts.indexOf(accountName);
                    final spotColor = _accountColors[
                        accountIdx.clamp(0, _accountColors.length - 1)];
                    final label =
                        visibleKeys.length > 1 ? '$accountName\n' : '';
                    return LineTooltipItem(
                      '$label${fmtCurrency(spot.y)}\n$date',
                      Theme.of(context)
                          .textTheme
                          .bodySmall!
                          .copyWith(color: spotColor),
                    );
                  }).toList();
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPortfolioLegend(BuildContext context) {
    final accounts = context.watch<AccountManager>().accounts;
    if (accounts.length <= 1) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        alignment: WrapAlignment.center,
        children: [
          for (var i = 0; i < accounts.length; i++)
            GestureDetector(
              onTap: () => setState(() {
                if (_hiddenAccounts.contains(accounts[i])) {
                  _hiddenAccounts.remove(accounts[i]);
                } else {
                  _hiddenAccounts.add(accounts[i]);
                }
              }),
              child: AnimatedOpacity(
                opacity: _hiddenAccounts.contains(accounts[i]) ? 0.35 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _accountColors[i % _accountColors.length],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      accounts[i],
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPortfolioSummary(BuildContext context, SettingsState settings) {
    final accounts = context.read<AccountManager>().accounts;
    final visibleSeries = {
      for (final entry in _portfolioSeriesByAccount.entries)
        if (!_hiddenAccounts.contains(entry.key) && entry.value.isNotEmpty)
          entry.key: entry.value,
    };
    if (visibleSeries.isEmpty) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          for (final entry in visibleSeries.entries)
            _buildAccountSummaryRow(
              context,
              accounts,
              entry.key,
              entry.value,
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
                items: settings.visibleCurrencies
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
                  final accountManager = context.read<AccountManager>();
                  for (final accountName in accountManager.accounts) {
                    final isActive =
                        accountName == accountManager.activeAccount;
                    final accountDb = isActive
                        ? db
                        : (accountName == 'Default'
                            ? Database()
                            : Database('market-monk-$accountName'));
                    try {
                      final trades = await accountDb.trades.select().get();
                      final symbols =
                          trades.map((t) => t.symbol).toSet().toList();
                      for (final s in symbols) {
                        await syncCandles(s, database: accountDb);
                      }
                    } finally {
                      if (!isActive) await accountDb.close();
                    }
                  }
                  await _loadAllPortfolios();
                  if (mounted) setState(() => _networkLoading = false);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAccountSummaryRow(
    BuildContext context,
    List<String> accounts,
    String accountName,
    List<_DateValue> series,
  ) {
    final idx = accounts.indexOf(accountName);
    final dotColor = _accountColors[idx.clamp(0, _accountColors.length - 1)];
    final pct = safePercentChange(series.first.value, series.last.value);
    final returnColor = pct >= 0 ? Colors.green : Colors.redAccent;
    final change = series.last.value - series.first.value;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  accountName,
                  style: Theme.of(context).textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    pct >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                    color: returnColor,
                    size: 18,
                  ),
                  Text(
                    '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium!
                        .copyWith(color: returnColor),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Text(
                fmtCurrency(series.last.value),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${change >= 0 ? '+' : ''}${fmtCurrency(change)} period change',
                style: TextStyle(color: returnColor, fontSize: 13),
              ),
            ),
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
