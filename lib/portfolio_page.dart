import 'dart:io';

import 'package:drift/drift.dart' hide Column, Table;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/logging.dart';
import 'package:market_monk/settings_page.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/utils.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

class _LoadedPortfolio {
  final List<Position> positions;
  final IbkrAccountValue? netLiquidation;

  const _LoadedPortfolio({
    required this.positions,
    required this.netLiquidation,
  });
}

class PortfolioPage extends StatefulWidget {
  final Future<IbkrPortfolioSnapshot> Function(IbkrAccountConfig)? _ibkrLoader;

  const PortfolioPage({
    super.key,
    Future<IbkrPortfolioSnapshot> Function(IbkrAccountConfig)? ibkrLoader,
  }) : _ibkrLoader = ibkrLoader;

  @override
  State<PortfolioPage> createState() => PortfolioPageState();
}

class PortfolioPageState extends State<PortfolioPage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  @override
  bool get wantKeepAlive => true;

  late Stream<_LoadedPortfolio> _stream;
  List<Position> _positions = [];
  IbkrAccountValue? _netLiquidation;
  int? touchedIndex;
  final _filterController = TextEditingController();
  String _filterText = '';
  String _lastAccount = '';
  int _lastIbkrRefreshVersion = -1;
  IbkrAccountConfig _lastIbkrConfig = const IbkrAccountConfig();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _stream = _buildStream();
    _preload();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final accounts = context.watch<AccountManager>();
    final account = accounts.activeAccount;
    final ibkrConfig = accounts.ibkrConfigFor(account);
    final refreshVersion = accounts.ibkrRefreshVersion;
    if (account != _lastAccount ||
        ibkrConfig != _lastIbkrConfig ||
        refreshVersion != _lastIbkrRefreshVersion) {
      _lastAccount = account;
      _lastIbkrConfig = ibkrConfig;
      _lastIbkrRefreshVersion = refreshVersion;
      setState(() {
        _stream = _buildStream();
        _positions = [];
        touchedIndex = null;
      });
      _preload();
      _syncAllInBackground();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _preload();
      _syncAllInBackground();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _filterController.dispose();
    super.dispose();
  }

  Future<_LoadedPortfolio> _loadPortfolio(List<Trade> trades) async {
    final config = context.read<AccountManager>().ibkrConfigFor();
    if (config.enabled) {
      if (!config.isConfigured) {
        throw StateError('IBKR portfolio source is not fully configured');
      }
      final snapshot = await (widget._ibkrLoader?.call(config) ??
          IbkrApiClient(config).fetchPortfolio());
      cacheIbkrAccountExchangeRate(snapshot);
      return _LoadedPortfolio(
        positions: await computeIbkrPositions(snapshot.positions, trades),
        netLiquidation: snapshot.netLiquidation,
      );
    }
    final symbols = trades.map((t) => t.symbol).toSet().toList();
    final prices = await fetchLatestPrices(symbols);
    return _LoadedPortfolio(
      positions: computePositions(trades, prices),
      netLiquidation: null,
    );
  }

  Future<void> _preload() async {
    try {
      final trades = await db.trades.select().get();
      final loaded = await _loadPortfolio(trades);
      if (mounted) {
        setState(() {
          _positions = loaded.positions;
          _netLiquidation = loaded.netLiquidation;
        });
      }
    } catch (error, stackTrace) {
      talker.handle(error, stackTrace, 'Failed to preload portfolio positions');
    }
  }

  Future<void> _syncAllInBackground() async {
    final accountName = context.read<AccountManager>().activeAccount;
    try {
      final useIbkr = _lastIbkrConfig.enabled;
      final trades = await db.trades.select().get();
      final loaded = await _loadPortfolio(trades);
      final positions = loaded.positions;
      final symbols = useIbkr
          ? positions.map((position) => position.symbol).toSet()
          : trades.map((trade) => trade.symbol).toSet();
      for (final symbol in symbols) {
        await syncCandles(
          symbol,
          ibkrConfig: _lastIbkrConfig,
          syncNamespace: accountName,
        );
      }
      if (mounted) {
        setState(() {
          _positions = positions;
          _netLiquidation = loaded.netLiquidation;
        });
      }
    } catch (error, stackTrace) {
      talker.handle(error, stackTrace, 'Background portfolio sync failed');
    }
    if (mounted) setState(() => _stream = _buildStream());
  }

  Stream<_LoadedPortfolio> _buildStream() =>
      db.trades.select().watch().asyncMap(_loadPortfolio);

  Future<void> _updateCandles() async {
    clearAllSyncCache();
    await _preload();
    await _syncAllInBackground();
  }

  Future<void> _exportCsv(
    BuildContext context,
    List<Position> positions,
  ) async {
    final accountName = context.read<AccountManager>().activeAccount;
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

    final safeName = accountName.replaceAll(RegExp(r'[^\w\-]'), '_');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/positions_$safeName.csv');
    await file.writeAsString(buf.toString());
    talker.info('Exported portfolio CSV with ${positions.length} positions');
    if (!context.mounted) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: 'Portfolio Positions',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<_LoadedPortfolio>(
          stream: _stream,
          builder: _buildBody,
        ),
      ),
    );
  }

  void _retryPortfolio() {
    setState(() => _stream = _buildStream());
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
  }

  Widget _buildLoadError(BuildContext context) {
    final ibkrEnabled = context.watch<AccountManager>().ibkrConfigFor().enabled;
    final title = ibkrEnabled
        ? 'Couldn’t load Interactive Brokers'
        : 'Couldn’t load portfolio';
    final message = ibkrEnabled
        ? 'MarketMonk couldn’t load your portfolio from your IBKR server. '
            'Check the server connection, then try again.'
        : 'MarketMonk couldn’t refresh your portfolio. Check your internet '
            'connection, then try again.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_off_outlined,
                    size: 48,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _retryPortfolio,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try again'),
                      ),
                      if (ibkrEnabled)
                        OutlinedButton.icon(
                          onPressed: _openSettings,
                          icon: const Icon(Icons.settings_outlined),
                          label: const Text('IBKR settings'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRefreshWarning(BuildContext context) {
    final ibkrEnabled = context.watch<AccountManager>().ibkrConfigFor().enabled;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Icon(
              Icons.cloud_off_outlined,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                ibkrEnabled
                    ? 'Couldn’t refresh IBKR. Showing the last loaded portfolio.'
                    : 'Couldn’t refresh market data. Showing the last loaded portfolio.',
              ),
            ),
            TextButton(
              onPressed: _retryPortfolio,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AsyncSnapshot<_LoadedPortfolio> snap,
  ) {
    final positions = snap.data?.positions ?? _positions;
    final netLiquidation = snap.data?.netLiquidation ?? _netLiquidation;

    if (snap.hasError && positions.isEmpty) return _buildLoadError(context);

    if (positions.isEmpty && !snap.hasData) {
      return const Center();
    }

    if (snap.hasData &&
        (snap.data!.positions != _positions ||
            snap.data!.netLiquidation != _netLiquidation)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _positions = snap.data!.positions;
          _netLiquidation = snap.data!.netLiquidation;
        });
      });
    }
    if (positions.isEmpty) {
      final ibkrEnabled =
          context.watch<AccountManager>().ibkrConfigFor().enabled;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(ibkrEnabled ? 'No IBKR stock positions' : 'No holdings yet'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              ),
              icon: Icon(ibkrEnabled ? Icons.settings : Icons.upload_file),
              label: Text(ibkrEnabled ? 'IBKR settings' : 'Import CSV'),
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
    // Holdings can change while this page is kept alive (for example, after
    // switching accounts). Do not use a selection from the previous list.
    final selectedIndex = touchedIndex != null &&
            touchedIndex! >= 0 &&
            touchedIndex! < sorted.length
        ? touchedIndex
        : null;

    final sections = List.generate(sorted.length, (i) {
      final p = sorted[i];
      final val = p.currentValue;
      final pct = totalValue > 0 ? val / totalValue * 100 : 0.0;
      final isTouched = i == selectedIndex;
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
          if (snap.hasError)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: _buildRefreshWarning(context),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _SummaryCard(
                totalValue: totalValue,
                netLiquidation: netLiquidation,
                totalGain: totalGain,
                totalGainPct: totalGainPct,
                onExport: () => _exportCsv(context, positions),
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
                  if (selectedIndex != null)
                    IgnorePointer(
                      child: SizedBox(
                        width: 100,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              sorted[selectedIndex].symbol,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              sorted[selectedIndex].name,
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
                  isHighlighted: sortedIndex == selectedIndex,
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
  final IbkrAccountValue? netLiquidation;
  final double totalGain;
  final double totalGainPct;
  final VoidCallback onExport;

  const _SummaryCard({
    required this.totalValue,
    required this.netLiquidation,
    required this.totalGain,
    required this.totalGainPct,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    final gainColor = totalGain >= 0 ? Colors.green : Colors.redAccent;
    final settings = context.watch<SettingsState>();
    final accounts = context.watch<AccountManager>();
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
                  netLiquidation == null
                      ? fmtCurrency(totalValue)
                      : fmtNativeCurrency(
                          netLiquidation!.value,
                          netLiquidation!.currency,
                        ),
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
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == '__export__') {
                  onExport();
                } else if (value.startsWith('cur:')) {
                  settings.setDisplayCurrency(value.substring(4));
                } else if (value.startsWith('acc:')) {
                  accounts.switchAccount(value.substring(4));
                }
              },
              itemBuilder: (ctx) => [
                ...settings.visibleCurrencies.map(
                  (c) => CheckedPopupMenuItem(
                    value: 'cur:$c',
                    checked: c == settings.displayCurrency,
                    child: Text(c),
                  ),
                ),
                if (accounts.accounts.length > 1) ...[
                  const PopupMenuDivider(),
                  ...accounts.accounts.map(
                    (a) => CheckedPopupMenuItem(
                      value: 'acc:$a',
                      checked: a == accounts.activeAccount,
                      child: Text(a),
                    ),
                  ),
                ],
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: '__export__',
                  child: Row(
                    children: [
                      Icon(Icons.download, size: 20),
                      SizedBox(width: 8),
                      Text('Export CSV'),
                    ],
                  ),
                ),
              ],
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(settings.displayCurrency),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
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

  const _FilterRow({
    required this.controller,
    required this.filterText,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
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
      subtitle: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
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
