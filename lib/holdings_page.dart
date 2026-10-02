import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:market_monk/adaptive_layout.dart';
import 'package:market_monk/bottom_nav.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/edit_ticker_page.dart';
import 'package:market_monk/empty_state.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/l10n/app_localizations.dart';
import 'package:market_monk/settings_page.dart';
import 'package:market_monk/trade_history_page.dart';
import 'package:market_monk/utils.dart';
import 'package:provider/provider.dart';

enum _HoldingsSort { symbol, value, returnPct, unrealized }

/// A summary of a symbol: open position (if any) + full trade history.
class SymbolSummary {
  final String symbol;
  final String name;
  final Position? position; // null = fully closed position
  final List<Trade> trades;

  SymbolSummary({
    required this.symbol,
    required this.name,
    required this.position,
    required this.trades,
  });

  double get totalRealizedPL =>
      trades.fold(0.0, (sum, t) => sum + t.realizedPL);
}

class HoldingsPage extends StatefulWidget {
  final Future<List<Position>> Function(List<Trade>)? _positionsLoader;
  const HoldingsPage({
    super.key,
    Future<List<Position>> Function(List<Trade>)? positionsLoader,
  }) : _positionsLoader = positionsLoader;

  @override
  State<HoldingsPage> createState() => HoldingsPageState();
}

class HoldingsPageState extends State<HoldingsPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _search = TextEditingController();
  List<SymbolSummary> _summaries = [];
  late Stream<List<SymbolSummary>> _stream;
  String _lastAccount = '';
  int _lastIbkrRefreshVersion = -1;
  IbkrAccountConfig _lastIbkrConfig = const IbkrAccountConfig();

  bool _selecting = false;
  final Set<String> _selectedSymbols = {};
  _HoldingsSort _desktopSort = _HoldingsSort.value;
  bool _desktopSortAscending = false;

  @override
  void initState() {
    super.initState();
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
        _summaries = [];
      });
      _preload();
      _syncAllInBackground();
    }
  }

  /// Pre-loads data immediately via get() so the UI has something to show
  /// before the watch() stream emits its first value.
  Future<void> _preload() async {
    try {
      final accounts = context.read<AccountManager>();
      final trades = await db.trades.select().get();
      final cached = accounts.portfolioCacheFor();
      if (cached != null) {
        final result = _summariesFromPositions(trades, cached.positions);
        if (mounted) setState(() => _summaries = result);
        return;
      }
      final result = await _computeSummaries(trades);
      if (mounted) setState(() => _summaries = result);
    } catch (_) {}
  }

  Future<List<Position>> _loadPositions(List<Trade> trades) async {
    if (widget._positionsLoader != null) {
      return widget._positionsLoader!(trades);
    }

    final accounts = context.read<AccountManager>();
    final config = accounts.ibkrConfigFor();
    final accountName = accounts.activeAccount;
    if (!config.enabled) {
      final symbols = trades.map((trade) => trade.symbol).toSet().toList();
      final prices = await fetchLatestPrices(symbols);
      final positions = computePositions(trades, prices);
      await accounts.cachePortfolio(accountName, positions, null);
      return positions;
    }
    if (!config.isConfigured) {
      throw StateError('IBKR portfolio source is not fully configured');
    }
    final snapshot = await IbkrApiClient(config).fetchPortfolio();
    cacheIbkrAccountExchangeRate(snapshot);
    final positions = await computeIbkrPositions(snapshot.positions, trades);
    await accounts.cachePortfolio(
      accountName,
      positions,
      snapshot.netLiquidation,
    );
    return positions;
  }

  /// Fires candle syncs for all held symbols in the background without
  /// blocking the UI.
  Future<void> _syncAllInBackground() async {
    final accountName = context.read<AccountManager>().activeAccount;
    try {
      final useIbkr = _lastIbkrConfig.enabled;
      final trades = await db.trades.select().get();
      final positions = await _loadPositions(trades);
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
    } catch (_) {}
    if (mounted) setState(() => _stream = _buildStream());
  }

  Future<List<SymbolSummary>> _computeSummaries(List<Trade> trades) async =>
      _summariesFromPositions(trades, await _loadPositions(trades));

  List<SymbolSummary> _summariesFromPositions(
    List<Trade> trades,
    List<Position> positions,
  ) {
    final positionMap = {
      for (final position in positions) position.symbol: position,
    };
    final q = _search.text.toLowerCase();
    final Map<String, List<Trade>> bySymbol = {};
    for (final t in trades) {
      if (q.isNotEmpty &&
          !t.symbol.toLowerCase().contains(q) &&
          !t.name.toLowerCase().contains(q)) continue;
      bySymbol.putIfAbsent(t.symbol, () => []).add(t);
    }

    for (final position in positions) {
      if (q.isNotEmpty &&
          !position.symbol.toLowerCase().contains(q) &&
          !position.name.toLowerCase().contains(q)) {
        continue;
      }
      bySymbol.putIfAbsent(position.symbol, () => []);
    }

    final summaries = <SymbolSummary>[];
    for (final entry in bySymbol.entries) {
      final symbol = entry.key;
      final symbolTrades = entry.value;
      final position = positionMap[symbol];
      final name = position?.name ?? symbolTrades.first.name;
      summaries.add(
        SymbolSummary(
          symbol: symbol,
          name: name,
          position: position,
          trades: symbolTrades,
        ),
      );
    }

    summaries.sort((a, b) {
      if (a.position != null && b.position == null) return -1;
      if (a.position == null && b.position != null) return 1;
      return a.symbol.compareTo(b.symbol);
    });

    return summaries;
  }

  Stream<List<SymbolSummary>> _buildStream() {
    return db.trades.select().watch().asyncMap(_computeSummaries);
  }

  void _exitSelecting() {
    setState(() {
      _selecting = false;
      _selectedSymbols.clear();
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedSymbols.length == _summaries.length) {
        _selectedSymbols.clear();
      } else {
        _selectedSymbols
          ..clear()
          ..addAll(_summaries.map((s) => s.symbol));
      }
    });
  }

  Future<void> _deleteSelected(BuildContext context) async {
    if (_selectedSymbols.isEmpty) return;

    final count = _selectedSymbols.length;
    final ctx = context;
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (ctx) => AlertDialog(
        title: Text(
          context.l10n.text(
            count == 1 ? 'Delete {count} holding?' : 'Delete {count} holdings?',
            {'count': count},
          ),
        ),
        content: Text(
          'All trades for the selected symbol${count == 1 ? '' : 's'} will '
          'be permanently deleted. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.text('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.text('Delete')),
          ),
        ],
      ),
    );

    if (confirmed != true || !ctx.mounted) return;

    for (final symbol in _selectedSymbols) {
      await (db.trades.delete()..where((t) => t.symbol.equals(symbol))).go();
    }
    _exitSelecting();
    if (ctx.mounted)
      toast(
        ctx,
        context.l10n.text(
          count == 1 ? 'Deleted {count} holding' : 'Deleted {count} holdings',
          {'count': count},
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final desktop = isDesktopLayout(context);
    final ibkrManaged = context.watch<AccountManager>().ibkrConfigFor().enabled;
    final allSelected =
        _summaries.isNotEmpty && _selectedSymbols.length == _summaries.length;

    final menuButton = PopupMenuButton(
      icon: const Icon(Icons.more_vert),
      tooltip: context.l10n.text('Show menu'),
      itemBuilder: (context) => [
        if (_selecting) ...[
          PopupMenuItem(
            onTap: _toggleSelectAll,
            child: ListTile(
              leading: Icon(allSelected ? Icons.deselect : Icons.select_all),
              title: Text(
                allSelected
                    ? context.l10n.text('Deselect all')
                    : context.l10n.text('Select all'),
              ),
            ),
          ),
          PopupMenuItem(
            onTap: () => _deleteSelected(context),
            child: ListTile(
              leading: const Icon(Icons.delete),
              title: Text(context.l10n.text('Delete selected')),
            ),
          ),
          PopupMenuItem(
            onTap: _exitSelecting,
            child: ListTile(
              leading: const Icon(Icons.close),
              title: Text(context.l10n.text('Cancel selection')),
            ),
          ),
        ] else ...[
          PopupMenuItem(
            child: ListTile(
              leading: const Icon(Icons.settings),
              title: Text(context.l10n.text('Settings')),
              onTap: () async {
                Navigator.pop(context);
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                );
              },
            ),
          ),
        ],
      ],
    );

    final leading = _search.text.isEmpty
        ? const Padding(
            padding: EdgeInsets.only(left: 16, right: 8),
            child: Icon(Icons.search),
          )
        : IconButton(
            onPressed: () {
              setState(() {
                _search.text = '';
                _stream = _buildStream();
              });
            },
            icon: const Icon(Icons.arrow_back),
            padding: const EdgeInsets.only(left: 16, right: 8),
          );

    if (desktop) {
      final openCount =
          _summaries.where((summary) => summary.position != null).length;
      return Scaffold(
        body: Padding(
          padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.text('Holdings'),
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$openCount open · ${_summaries.length} total symbols',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  if (_selecting) ...[
                    TextButton.icon(
                      onPressed: _toggleSelectAll,
                      icon:
                          Icon(allSelected ? Icons.deselect : Icons.select_all),
                      label: Text(
                        allSelected
                            ? context.l10n.text('Deselect all')
                            : context.l10n.text('Select all'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: () => _deleteSelected(context),
                      icon: const Icon(Icons.delete_outline),
                      label: Text(
                        context.l10n.text(
                          'Delete ({count})',
                          {'count': _selectedSymbols.length},
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _exitSelecting,
                      tooltip: context.l10n.text('Cancel selection'),
                      icon: const Icon(Icons.close),
                    ),
                  ] else if (!ibkrManaged) ...[
                    OutlinedButton.icon(
                      onPressed: _summaries.isEmpty
                          ? null
                          : () => setState(() => _selecting = true),
                      icon: const Icon(Icons.checklist_rounded),
                      label: Text(context.l10n.text('Select')),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const EditTickerPage(),
                        ),
                      ),
                      icon: const Icon(Icons.add),
                      label: Text(context.l10n.text('Add trade')),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 460,
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {
                      _stream = _buildStream();
                    }),
                    decoration: InputDecoration(
                      hintText: context.l10n.text('Search...'),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                setState(() {
                                  _search.clear();
                                  _stream = _buildStream();
                                });
                              },
                              icon: const Icon(Icons.close),
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      isDense: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: StreamBuilder<List<SymbolSummary>>(
                  stream: _stream,
                  builder: _buildList,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
              child: SearchBar(
                controller: _search,
                hintText: _selecting
                    ? context.l10n.text(
                        '{count} selected',
                        {'count': _selectedSymbols.length},
                      )
                    : context.l10n.text('Search...'),
                padding: WidgetStateProperty.all(
                  const EdgeInsets.only(right: 8),
                ),
                leading: leading,
                onTap: () => _search.selection = TextSelection(
                  baseOffset: 0,
                  extentOffset: _search.text.length,
                ),
                onChanged: (_) => setState(() {
                  _stream = _buildStream();
                }),
                trailing: [menuButton],
              ),
            ),
            Expanded(
              child: StreamBuilder<List<SymbolSummary>>(
                stream: _stream,
                builder: _buildList,
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: ibkrManaged
          ? null
          : _selecting
              ? FloatingActionButton.extended(
                  onPressed: () => _deleteSelected(context),
                  label: Text(
                    context.l10n.text('Delete ({count})', {
                      'count': _selectedSymbols.length,
                    }),
                  ),
                  icon: const Icon(Icons.delete),
                )
              : Padding(
                  padding: const EdgeInsets.only(bottom: bottomNavHeight),
                  child: FloatingActionButton.extended(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const EditTickerPage()),
                    ),
                    label: Text(context.l10n.text('Add')),
                    icon: const Icon(Icons.add),
                    tooltip: context.l10n.text('Add trade'),
                  ),
                ),
    );
  }

  List<SymbolSummary> _sortDesktopSummaries(
    List<SymbolSummary> summaries,
  ) {
    final sorted = [...summaries];
    int compare(SymbolSummary a, SymbolSummary b) {
      final multiplier = _desktopSortAscending ? 1 : -1;
      switch (_desktopSort) {
        case _HoldingsSort.symbol:
          return multiplier * a.symbol.compareTo(b.symbol);
        case _HoldingsSort.value:
          return multiplier *
              (a.position?.currentValue ?? 0)
                  .compareTo(b.position?.currentValue ?? 0);
        case _HoldingsSort.returnPct:
          return multiplier *
              (a.position?.change ?? double.negativeInfinity)
                  .compareTo(b.position?.change ?? double.negativeInfinity);
        case _HoldingsSort.unrealized:
          return multiplier *
              (a.position?.unrealizedPL ?? a.totalRealizedPL).compareTo(
                b.position?.unrealizedPL ?? b.totalRealizedPL,
              );
      }
    }

    sorted.sort(compare);
    return sorted;
  }

  void _setDesktopSort(_HoldingsSort sort) {
    setState(() {
      if (_desktopSort == sort) {
        _desktopSortAscending = !_desktopSortAscending;
      } else {
        _desktopSort = sort;
        _desktopSortAscending = sort == _HoldingsSort.symbol;
      }
    });
  }

  Widget _desktopMetric(
    BuildContext context, {
    required String label,
    required String value,
    String? detail,
    Color? valueColor,
  }) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: valueColor,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 3),
              Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopHoldings(
    BuildContext context,
    List<SymbolSummary> summaries,
    bool ibkrManaged,
  ) {
    final theme = Theme.of(context);
    final open = summaries
        .where((summary) => summary.position != null)
        .map((summary) => summary.position!)
        .toList();
    final totalValue =
        open.fold(0.0, (sum, position) => sum + position.currentValue);
    final totalCost =
        open.fold(0.0, (sum, position) => sum + position.costBasis);
    final totalUnrealized =
        open.fold(0.0, (sum, position) => sum + position.unrealizedPL);
    final winners = open.where((position) => position.change >= 0).length;
    final sorted = _sortDesktopSummaries(summaries);

    final sortColumnIndex = switch (_desktopSort) {
      _HoldingsSort.symbol => 0,
      _HoldingsSort.value => 4,
      _HoldingsSort.unrealized => 5,
      _HoldingsSort.returnPct => 6,
    };

    void toggleSelection(SymbolSummary summary) {
      setState(() {
        if (_selectedSymbols.contains(summary.symbol)) {
          _selectedSymbols.remove(summary.symbol);
          if (_selectedSymbols.isEmpty) _selecting = false;
        } else {
          _selectedSymbols.add(summary.symbol);
        }
      });
    }

    DataCell textCell(
      String text, {
      required SymbolSummary summary,
      bool numeric = true,
      Color? color,
      FontWeight? fontWeight,
    }) {
      return DataCell(
        Align(
          alignment: numeric ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: fontWeight,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        onTap: _selecting ? null : () => _openDetail(summary),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            _desktopMetric(
              context,
              label: context.l10n.text('Market value'),
              value: fmtCurrency(totalValue),
            ),
            const SizedBox(width: 12),
            _desktopMetric(
              context,
              label: context.l10n.text('Cost basis'),
              value: fmtCurrency(totalCost),
            ),
            const SizedBox(width: 12),
            _desktopMetric(
              context,
              label: context.l10n.text('Unrealized P/L'),
              value:
                  '${totalUnrealized >= 0 ? '+' : ''}${fmtCurrency(totalUnrealized)}',
              valueColor:
                  totalUnrealized >= 0 ? Colors.green : Colors.redAccent,
            ),
            const SizedBox(width: 12),
            _desktopMetric(
              context,
              label: context.l10n.text('Open positions'),
              value: open.length.toString(),
              detail: '$winners positive · ${open.length - winners} negative',
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compactTable = constraints.maxWidth < 1000;
                final effectiveSortColumnIndex = compactTable
                    ? switch (_desktopSort) {
                        _HoldingsSort.symbol => 0,
                        _HoldingsSort.value => 1,
                        _HoldingsSort.unrealized => 2,
                        _HoldingsSort.returnPct => 3,
                      }
                    : sortColumnIndex;
                final tableWidth = compactTable
                    ? constraints.maxWidth
                    : constraints.maxWidth < 1240
                        ? 1240.0
                        : constraints.maxWidth;
                return Scrollbar(
                  child: SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: tableWidth,
                        child: DataTable(
                          showCheckboxColumn: _selecting && !ibkrManaged,
                          sortColumnIndex: effectiveSortColumnIndex,
                          sortAscending: _desktopSortAscending,
                          headingRowColor: WidgetStatePropertyAll(
                            theme.colorScheme.surfaceContainerLow,
                          ),
                          headingTextStyle:
                              theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                          dataRowMinHeight: 62,
                          dataRowMaxHeight: 70,
                          horizontalMargin: 18,
                          columnSpacing: 24,
                          columns: [
                            DataColumn(
                              label: Text(context.l10n.text('Holding')),
                              onSort: (_, __) =>
                                  _setDesktopSort(_HoldingsSort.symbol),
                            ),
                            if (!compactTable) ...[
                              DataColumn(
                                numeric: true,
                                label: Text(context.l10n.text('Shares')),
                              ),
                              DataColumn(
                                numeric: true,
                                label: Text(context.l10n.text('Avg cost')),
                              ),
                              DataColumn(
                                numeric: true,
                                label: Text(context.l10n.text('Price')),
                              ),
                            ],
                            DataColumn(
                              numeric: true,
                              label: Text(
                                context.l10n.text(
                                  compactTable ? 'Value' : 'Market value',
                                ),
                              ),
                              onSort: (_, __) =>
                                  _setDesktopSort(_HoldingsSort.value),
                            ),
                            DataColumn(
                              numeric: true,
                              label: Text(context.l10n.text('P/L')),
                              onSort: (_, __) =>
                                  _setDesktopSort(_HoldingsSort.unrealized),
                            ),
                            DataColumn(
                              numeric: true,
                              label: Text(context.l10n.text('Return')),
                              onSort: (_, __) =>
                                  _setDesktopSort(_HoldingsSort.returnPct),
                            ),
                          ],
                          rows: [
                            for (final summary in sorted)
                              (() {
                                final position = summary.position;
                                final isClosed = position == null;
                                final returnPct = position?.change ?? 0;
                                final pnl = position?.unrealizedPL ??
                                    summary.totalRealizedPL;
                                final pnlText = isClosed
                                    ? '${pnl >= 0 ? '+' : ''}${fmtNativeCurrency(pnl, symbolCurrency(summary.symbol))}'
                                    : '${pnl >= 0 ? '+' : ''}${fmtCurrency(pnl)}';
                                final shares = position == null
                                    ? '—'
                                    : position.netShares.toStringAsFixed(
                                        position.netShares ==
                                                position.netShares
                                                    .roundToDouble()
                                            ? 0
                                            : 3,
                                      );
                                final changeColor = isClosed
                                    ? theme.colorScheme.onSurfaceVariant
                                    : returnPct >= 0
                                        ? Colors.green
                                        : Colors.redAccent;
                                final pnlColor =
                                    pnl >= 0 ? Colors.green : Colors.redAccent;

                                return DataRow(
                                  selected:
                                      _selectedSymbols.contains(summary.symbol),
                                  onSelectChanged: _selecting && !ibkrManaged
                                      ? (_) => toggleSelection(summary)
                                      : null,
                                  cells: [
                                    DataCell(
                                      Row(
                                        children: [
                                          Icon(
                                            isClosed
                                                ? Icons.history_rounded
                                                : returnPct >= 0
                                                    ? Icons.trending_up_rounded
                                                    : Icons
                                                        .trending_down_rounded,
                                            size: 20,
                                            color: changeColor,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Flexible(
                                                      child: Text(
                                                        summary.symbol,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: theme.textTheme
                                                            .titleSmall
                                                            ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                    ),
                                                    if (isClosed) ...[
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        context.l10n
                                                            .text('Closed'),
                                                        style: theme.textTheme
                                                            .labelSmall
                                                            ?.copyWith(
                                                          color: theme
                                                              .colorScheme
                                                              .onSurfaceVariant,
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                                Text(
                                                  summary.name,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: theme
                                                      .textTheme.bodySmall
                                                      ?.copyWith(
                                                    color: theme.colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      onTap: _selecting
                                          ? null
                                          : () => _openDetail(summary),
                                    ),
                                    if (!compactTable) ...[
                                      textCell(
                                        shares,
                                        summary: summary,
                                      ),
                                      textCell(
                                        position == null
                                            ? '—'
                                            : fmtNativeCurrency(
                                                position.avgCost,
                                                position.nativeCurrency,
                                              ),
                                        summary: summary,
                                      ),
                                      textCell(
                                        position == null
                                            ? '—'
                                            : fmtNativeCurrency(
                                                position.currentPrice,
                                                position.nativeCurrency,
                                              ),
                                        summary: summary,
                                      ),
                                    ],
                                    textCell(
                                      position == null
                                          ? '—'
                                          : fmtCurrency(position.currentValue),
                                      summary: summary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    textCell(
                                      pnlText,
                                      summary: summary,
                                      color: pnlColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    textCell(
                                      position == null
                                          ? '—'
                                          : '${returnPct >= 0 ? '+' : ''}${returnPct.toStringAsFixed(2)}%',
                                      summary: summary,
                                      color: changeColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ],
                                );
                              })(),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildList(
    BuildContext context,
    AsyncSnapshot<List<SymbolSummary>> snap,
  ) {
    if (snap.hasError) return Center(child: Text(snap.error.toString()));

    final ibkrManaged = context.watch<AccountManager>().ibkrConfigFor().enabled;
    final summaries = snap.data ?? _summaries;

    if (summaries.isEmpty && !snap.hasData) {
      return const Center(child: CircularProgressIndicator());
    }

    if (snap.hasData && snap.data != _summaries) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _summaries = snap.data!);
      });
    }

    if (summaries.isEmpty) {
      final query = _search.text.trim();
      return AppEmptyState(
        icon: ibkrManaged
            ? Icons.account_balance_rounded
            : query.isEmpty
                ? Icons.candlestick_chart_rounded
                : Icons.search_off_rounded,
        title: ibkrManaged
            ? context.l10n.text('No IBKR stocks found')
            : query.isEmpty
                ? context.l10n.text('No stocks yet')
                : context.l10n.text('No matching stocks'),
        message: ibkrManaged
            ? context.l10n.text(
                'Refresh your portfolio or check your Interactive Brokers connection.',
              )
            : query.isEmpty
                ? context.l10n.text(
                    'Import a CSV or add your first trade manually.',
                  )
                : context.l10n.text(
                    'Nothing matches “{query}”. You can add that ticker now.',
                    {'query': query},
                  ),
        actionLabel: ibkrManaged
            ? context.l10n.text('IBKR settings')
            : query.isEmpty
                ? context.l10n.text('Import CSV')
                : context.l10n.text('Add {symbol}', {
                    'symbol': query.toUpperCase(),
                  }),
        actionIcon: ibkrManaged
            ? Icons.settings_rounded
            : query.isEmpty
                ? Icons.upload_file_rounded
                : Icons.add_rounded,
        onAction: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ibkrManaged || query.isEmpty
                ? const SettingsPage()
                : EditTickerPage(symbol: query.toUpperCase()),
          ),
        ),
      );
    }

    if (isDesktopLayout(context)) {
      return _buildDesktopHoldings(context, summaries, ibkrManaged);
    }

    return RefreshIndicator(
      onRefresh: _refreshCandles,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: bottomNavScrollClearance),
        itemCount: summaries.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) return const SizedBox(height: 8);
          final s = summaries[index - 1];
          return _SymbolTile(
            summary: s,
            selecting: _selecting,
            isSelected: _selectedSymbols.contains(s.symbol),
            onTap: () {
              if (_selecting) {
                setState(() {
                  if (_selectedSymbols.contains(s.symbol)) {
                    _selectedSymbols.remove(s.symbol);
                    if (_selectedSymbols.isEmpty) _selecting = false;
                  } else {
                    _selectedSymbols.add(s.symbol);
                  }
                });
              } else {
                _openDetail(s);
              }
            },
            onLongPress: ibkrManaged
                ? null
                : () {
                    setState(() {
                      _selecting = true;
                      _selectedSymbols.add(s.symbol);
                    });
                  },
          );
        },
      ),
    );
  }

  void _openDetail(SymbolSummary s) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TradeHistoryPage(summary: s)),
    );
  }

  Future<void> _refreshCandles() async {
    final accountManager = context.read<AccountManager>();
    clearAllSyncCache();
    await _preload();
    final symbols = _summaries.map((summary) => summary.symbol).toSet();
    for (final symbol in symbols) {
      await syncCandles(
        symbol,
        ibkrConfig: accountManager.ibkrConfigFor(),
        syncNamespace: accountManager.activeAccount,
      );
    }
    if (mounted) setState(() => _stream = _buildStream());
  }
}

class _SymbolTile extends StatelessWidget {
  final SymbolSummary summary;
  final bool selecting;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _SymbolTile({
    required this.summary,
    required this.selecting,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final position = summary.position;
    final changePct = position?.change ?? 0.0;
    final hasRealizedPL = summary.trades.any((t) => t.realizedPL != 0);
    final realizedPL = summary.totalRealizedPL;
    final realizedToday = position?.realizedToday;

    Widget leadingWidget;
    if (selecting) {
      leadingWidget = Checkbox(
        value: isSelected,
        onChanged: (_) => onTap(),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      );
    } else {
      leadingWidget = SizedBox(
        width: 40,
        height: 40,
        child: position != null
            ? Icon(
                changePct >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                color: changePct >= 0 ? Colors.green : Colors.redAccent,
              )
            : const Icon(Icons.history, color: Colors.grey),
      );
    }

    return ListTile(
      selected: isSelected,
      selectedTileColor: Theme.of(
        context,
      ).colorScheme.primaryContainer.withValues(alpha: 0.3),
      leading: leadingWidget,
      title: Text(summary.symbol),
      subtitle: position != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${changePct >= 0 ? '+' : ''}${changePct.toStringAsFixed(2)}%',
                  style: TextStyle(
                    color: changePct >= 0 ? Colors.green : Colors.redAccent,
                    fontSize: 13,
                  ),
                ),
                if (realizedToday != null)
                  Text(
                    'Realized today: ${realizedToday >= 0 ? '+' : ''}${fmtCurrency(realizedToday)}',
                    style: TextStyle(
                      color:
                          realizedToday >= 0 ? Colors.green : Colors.redAccent,
                      fontSize: 12,
                    ),
                  )
                else if (hasRealizedPL)
                  Text(
                    'Realized: ${realizedPL >= 0 ? '+' : ''}${fmtNativeCurrency(realizedPL, symbolCurrency(position.symbol))}',
                    style: TextStyle(
                      color: realizedPL >= 0 ? Colors.green : Colors.redAccent,
                      fontSize: 12,
                    ),
                  ),
              ],
            )
          : Text(
              '${summary.trades.length} trade(s) — closed position',
              style: const TextStyle(color: Colors.grey),
            ),
      trailing: position != null
          ? Text(
              fmtCurrency(position.currentValue),
              style: Theme.of(context).textTheme.bodyMedium,
            )
          : null,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}
