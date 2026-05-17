import 'dart:io';

import 'package:drift/drift.dart' hide Column, Table;
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/settings_page.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/utils.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

class PortfolioPage extends StatefulWidget {
  const PortfolioPage({super.key});

  @override
  State<PortfolioPage> createState() => PortfolioPageState();
}

class PortfolioPageState extends State<PortfolioPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late Stream<List<Position>> stream;
  List<Position> _positions = [];
  int? touchedIndex;
  final _filterController = TextEditingController();
  String _filterText = '';
  String _lastAccount = '';

  @override
  void initState() {
    super.initState();
    stream = _buildStream();
    _preload();
    _syncAllInBackground();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final account = context.watch<AccountManager>().activeAccount;
    if (account != _lastAccount) {
      _lastAccount = account;
      setState(() {
        stream = _buildStream();
        _positions = [];
      });
      _preload();
    }
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  Future<void> _preload() async {
    try {
      final trades = await db.trades.select().get();
      final symbols = trades.map((t) => t.symbol).toSet().toList();
      final prices = await fetchLatestPrices(symbols);
      final positions = computePositions(trades, prices);
      if (mounted) setState(() => _positions = positions);
    } catch (_) {}
  }

  Future<void> _syncAllInBackground() async {
    try {
      final trades = await db.trades.select().get();
      final symbols = trades.map((t) => t.symbol).toSet();
      for (final symbol in symbols) {
        await syncCandles(symbol);
      }
    } catch (_) {
      // Silently ignore network errors
    }
    if (mounted) setState(() => stream = _buildStream());
  }

  Stream<List<Position>> _buildStream() {
    return db.trades.select().watch().asyncMap((trades) async {
      final symbols = trades.map((t) => t.symbol).toSet().toList();
      final prices = await fetchLatestPrices(symbols);
      return computePositions(trades, prices);
    });
  }

  Future<void> _updateCandles() async {
    clearAllSyncCache();
    await _syncAllInBackground();
  }

  Future<void> _exportCsv(
    BuildContext context,
    List<Position> positions,
  ) async {
    final buf = StringBuffer();
    buf.writeln(
      'Symbol,Name,Shares,Avg Cost,Current Price,Current Value,Cost Basis,Unrealized P/L,% Change,Last Purchase Date',
    );
    final dateFmt = DateFormat('yyyy-MM-dd');
    for (final p in positions) {
      final cells = [
        p.symbol,
        '"${p.name.replaceAll('"', '""')}"',
        p.netShares.toStringAsFixed(6),
        p.avgCost.toStringAsFixed(4),
        p.currentPrice.toStringAsFixed(4),
        p.currentValue.toStringAsFixed(2),
        p.costBasis.toStringAsFixed(2),
        p.unrealizedPL.toStringAsFixed(2),
        p.change.toStringAsFixed(2),
        dateFmt.format(p.lastBuyDate),
      ];
      buf.writeln(cells.join(','));
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/positions.csv');
    await file.writeAsString(buf.toString());
    if (!context.mounted) return;
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: 'Portfolio Positions',
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<List<Position>>(
          stream: stream,
          builder: _buildBody,
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AsyncSnapshot<List<Position>> snap) {
    if (snap.hasError) return Center(child: Text(snap.error.toString()));

    final positions = snap.data ?? _positions;

    if (positions.isEmpty && !snap.hasData) {
      return const Center(child: CircularProgressIndicator());
    }

    if (snap.hasData && snap.data != _positions) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _positions = snap.data!);
      });
    }
    if (positions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('No holdings yet'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              ),
              icon: const Icon(Icons.upload_file),
              label: const Text('Import CSV'),
            ),
          ],
        ),
      );
    }

    final totalValue = positions.fold(0.0, (sum, p) => sum + p.currentValue);
    final totalCost = positions.fold(0.0, (sum, p) => sum + p.costBasis);
    final totalGain = totalValue - totalCost;
    final totalGainPct = totalCost > 0 ? (totalGain / totalCost) * 100 : 0.0;

    // Sort by value descending for consistent colours
    final sorted = [...positions]
      ..sort((a, b) => b.currentValue.compareTo(a.currentValue));

    final query = _filterText.toLowerCase();
    final filtered = query.isEmpty
        ? sorted
        : sorted
            .where(
              (p) =>
                  p.symbol.toLowerCase().contains(query) ||
                  p.name.toLowerCase().contains(query),
            )
            .toList();

    final colors = _buildColors(context, sorted.length);

    final sections = List.generate(sorted.length, (i) {
      final p = sorted[i];
      final val = p.currentValue;
      final pct = totalValue > 0 ? val / totalValue * 100 : 0.0;
      final isTouched = i == touchedIndex;
      return PieChartSectionData(
        value: val,
        color: colors[i],
        radius: isTouched ? 90 : 75,
        title: isTouched ? '${pct.toStringAsFixed(1)}%' : '',
        titleStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    });

    return RefreshIndicator(
      onRefresh: _updateCandles,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _SummaryCard(
                totalValue: totalValue,
                totalGain: totalGain,
                totalGainPct: totalGainPct,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: _FilterRow(
                controller: _filterController,
                filterText: _filterText,
                onChanged: (v) => setState(() => _filterText = v.trim()),
                onClear: () => setState(() {
                  _filterText = '';
                  _filterController.clear();
                }),
                onExport: () => _exportCsv(context, positions),
              ),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _PieHeaderDelegate(
              height: 260,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sections: sections,
                      centerSpaceRadius: 55,
                      sectionsSpace: 2,
                      pieTouchData: PieTouchData(
                        touchCallback: (event, response) {
                          setState(() {
                            if (!event.isInterestedForInteractions ||
                                response == null ||
                                response.touchedSection == null) {
                              touchedIndex = null;
                              return;
                            }
                            final idx =
                                response.touchedSection!.touchedSectionIndex;
                            touchedIndex = idx >= 0 ? idx : null;
                          });
                        },
                      ),
                    ),
                  ),
                  if (touchedIndex != null)
                    IgnorePointer(
                      child: SizedBox(
                        width: 100,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              sorted[touchedIndex!].symbol,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              sorted[touchedIndex!].name,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 10),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.builder(
              itemCount: filtered.length,
              itemBuilder: (context, i) {
                final p = filtered[i];
                final sortedIndex = sorted.indexOf(p);
                final val = p.currentValue;
                final pct = totalValue > 0 ? val / totalValue * 100 : 0.0;
                return _LegendTile(
                  color: colors[sortedIndex >= 0 ? sortedIndex : i],
                  symbol: p.symbol,
                  name: p.name,
                  value: val,
                  allocationPct: pct,
                  changePct: p.change,
                  isHighlighted: sortedIndex == touchedIndex,
                  onTap: () => setState(
                    () => touchedIndex =
                        touchedIndex == sortedIndex ? null : sortedIndex,
                  ),
                );
              },
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  List<Color> _buildColors(BuildContext context, int count) {
    final base = Theme.of(context).colorScheme.primary;
    final hsl = HSLColor.fromColor(base);
    return List.generate(count, (i) {
      final hue = (hsl.hue + i * (360 / count)) % 360;
      return HSLColor.fromAHSL(
        1.0,
        hue,
        hsl.saturation.clamp(0.4, 0.8),
        hsl.lightness.clamp(0.35, 0.65),
      ).toColor();
    });
  }
}

class _PieHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;
  final Color backgroundColor;

  const _PieHeaderDelegate({
    required this.child,
    required this.height,
    required this.backgroundColor,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(color: backgroundColor, child: child);
  }

  @override
  bool shouldRebuild(covariant _PieHeaderDelegate oldDelegate) =>
      child != oldDelegate.child ||
      backgroundColor != oldDelegate.backgroundColor;
}

class _SummaryCard extends StatelessWidget {
  final double totalValue;
  final double totalGain;
  final double totalGainPct;

  const _SummaryCard({
    required this.totalValue,
    required this.totalGain,
    required this.totalGainPct,
  });

  @override
  Widget build(BuildContext context) {
    final gainColor = totalGain >= 0 ? Colors.green : Colors.redAccent;
    final settings = context.watch<SettingsState>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            const Icon(Icons.account_balance, size: 32),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fmtCurrency(totalValue),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(
                  '${totalGain >= 0 ? '+' : ''}${fmtCurrency(totalGain)}'
                  '  (${totalGainPct.toStringAsFixed(2)}%)',
                  style: TextStyle(color: gainColor, fontSize: 13),
                ),
              ],
            ),
            const Spacer(),
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
          ],
        ),
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  final TextEditingController controller;
  final String filterText;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onExport;

  const _FilterRow({
    required this.controller,
    required this.filterText,
    required this.onChanged,
    required this.onClear,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<AccountManager>();
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: 'Filter holdings...',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              suffixIcon: filterText.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: onClear,
                    )
                  : null,
            ),
          ),
        ),
        if (accounts.accounts.length > 1) ...[
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            initialValue: accounts.activeAccount,
            onSelected: accounts.switchAccount,
            popUpAnimationStyle: const AnimationStyle(
              duration: Duration(milliseconds: 80),
            ),
            itemBuilder: (context) => accounts.accounts
                .map((a) => PopupMenuItem(value: a, child: Text(a)))
                .toList(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(accounts.activeAccount[0].toUpperCase()),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        ],
        const SizedBox(width: 4),
        IconButton(
          icon: const Icon(Icons.download),
          tooltip: 'Export positions as CSV',
          onPressed: onExport,
        ),
      ],
    );
  }
}

class _LegendTile extends StatelessWidget {
  final Color color;
  final String symbol;
  final String name;
  final double value;
  final double allocationPct;
  final double changePct;
  final bool isHighlighted;
  final VoidCallback onTap;

  const _LegendTile({
    required this.color,
    required this.symbol,
    required this.name,
    required this.value,
    required this.allocationPct,
    required this.changePct,
    required this.isHighlighted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0),
      onTap: onTap,
      selected: isHighlighted,
      leading: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      title: Text(symbol),
      subtitle: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            fmtCurrency(value),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          Text(
            '${allocationPct.toStringAsFixed(1)}%  '
            '${changePct >= 0 ? '+' : ''}${changePct.toStringAsFixed(2)}%',
            style: TextStyle(
              fontSize: 13,
              color: changePct >= 0 ? Colors.green : Colors.redAccent,
            ),
          ),
        ],
      ),
    );
  }
}
