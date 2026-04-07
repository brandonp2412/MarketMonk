import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/edit_ticker_page.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/settings_page.dart';
import 'package:market_monk/trade_history_page.dart';
import 'package:market_monk/utils.dart';

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
  const HoldingsPage({super.key});

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

  @override
  void initState() {
    super.initState();
    _stream = _buildStream();
    _preload();
    _syncAllInBackground();
  }

  /// Pre-loads data immediately via get() so the UI has something to show
  /// before the watch() stream emits its first value.
  Future<void> _preload() async {
    try {
      final trades = await db.trades.select().get();
      final result = await _computeSummaries(trades);
      if (mounted) setState(() => _summaries = result);
    } catch (_) {}
  }

  /// Fires candle syncs for all held symbols in the background without
  /// blocking the UI. Rebuilds the stream when finished so prices refresh.
  Future<void> _syncAllInBackground() async {
    try {
      final trades = await db.trades.select().get();
      final symbols = trades.map((t) => t.symbol).toSet();
      for (final symbol in symbols) {
        await syncCandles(symbol);
      }
    } catch (_) {
      // Silently ignore network errors on background sync
    }
    if (mounted) setState(() => _stream = _buildStream());
  }

  Future<List<SymbolSummary>> _computeSummaries(List<Trade> trades) async {
    final symbols = trades.map((t) => t.symbol).toSet().toList();
    final prices = await fetchLatestPrices(symbols);

    final q = _search.text.toLowerCase();
    final Map<String, List<Trade>> bySymbol = {};
    for (final t in trades) {
      if (q.isNotEmpty &&
          !t.symbol.toLowerCase().contains(q) &&
          !t.name.toLowerCase().contains(q)) continue;
      bySymbol.putIfAbsent(t.symbol, () => []).add(t);
    }

    final positions = computePositions(trades, prices);
    final positionMap = {for (final p in positions) p.symbol: p};

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

  /// Builds a stream that reacts only to trade changes.
  /// Prices are fetched via targeted per-symbol queries (not a full candles watch).
  Stream<List<SymbolSummary>> _buildStream() {
    return db.trades.select().watch().asyncMap(_computeSummaries);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final menuButton = PopupMenuButton(
      icon: const Icon(Icons.more_vert),
      tooltip: 'Show menu',
      itemBuilder: (context) => [
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Settings'),
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

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
              child: SearchBar(
                controller: _search,
                hintText: 'Search...',
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EditTickerPage()),
        ),
        label: const Text('Add'),
        icon: const Icon(Icons.add),
        tooltip: 'Add trade',
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    AsyncSnapshot<List<SymbolSummary>> snap,
  ) {
    if (snap.hasError) return Center(child: Text(snap.error.toString()));

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
      return ListTile(
        title: const Text('No stocks found'),
        subtitle: _search.text.isEmpty
            ? const Text('Import a CSV or tap + to add manually')
            : Text('Tap to add ${_search.text}'),
        onTap: _search.text.isEmpty
            ? null
            : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        EditTickerPage(symbol: _search.text.toUpperCase()),
                  ),
                ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshCandles,
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: summaries.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) return const SizedBox(height: 8);
          final s = summaries[index - 1];
          return _SymbolTile(
            summary: s,
            onTap: () => _openDetail(s),
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
    final symbols = _summaries.map((s) => s.symbol).toSet();
    for (final symbol in symbols) {
      await syncCandles(symbol);
    }
  }
}

class _SymbolTile extends StatelessWidget {
  final SymbolSummary summary;
  final VoidCallback onTap;

  const _SymbolTile({
    required this.summary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final position = summary.position;
    final changePct = position?.change ?? 0.0;
    final hasRealizedPL = summary.trades.any((t) => t.realizedPL != 0);
    final realizedPL = summary.totalRealizedPL;

    return ListTile(
      leading: SizedBox(
        width: 30,
        height: 30,
        child: position != null
            ? Icon(
                changePct >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                color: changePct >= 0 ? Colors.green : Colors.redAccent,
              )
            : const Icon(Icons.history, color: Colors.grey),
      ),
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
                if (hasRealizedPL)
                  Text(
                    'Realized: ${realizedPL >= 0 ? '+' : ''}${fmtCurrency(realizedPL)}',
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
    );
  }
}
