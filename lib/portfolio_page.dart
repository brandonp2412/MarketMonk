import 'package:drift/drift.dart' hide Column, Table;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/settings_page.dart';
import 'package:market_monk/utils.dart';

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

  @override
  void initState() {
    super.initState();
    stream = _buildStream();
    _preload();
    _syncAllInBackground();
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _SummaryCard(
                totalValue: totalValue,
                totalGain: totalGain,
                totalGainPct: totalGainPct,
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
              itemCount: sorted.length,
              itemBuilder: (context, i) {
                final p = sorted[i];
                final val = p.currentValue;
                final pct = totalValue > 0 ? val / totalValue * 100 : 0.0;
                return _LegendTile(
                  color: colors[i],
                  symbol: p.symbol,
                  name: p.name,
                  value: val,
                  allocationPct: pct,
                  changePct: p.change,
                  isHighlighted: i == touchedIndex,
                  onTap: () => setState(
                    () => touchedIndex = touchedIndex == i ? null : i,
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
          ],
        ),
      ),
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
