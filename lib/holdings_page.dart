import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/edit_ticker_page.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/settings_page.dart';
import 'package:market_monk/utils.dart';

/// A summary of a symbol's position: current holding (if any) + trade history.
class _SymbolSummary {
  final String symbol;
  final String name;
  final Ticker? holding;
  final List<Trade> trades;

  _SymbolSummary({
    required this.symbol,
    required this.name,
    required this.holding,
    required this.trades,
  });

  double get totalRealizedPL =>
      trades.fold(0.0, (sum, t) => sum + t.realizedPL);

  bool get hasActivity => holding != null || trades.isNotEmpty;
}

class HoldingsPage extends StatefulWidget {
  const HoldingsPage({super.key});

  @override
  State<HoldingsPage> createState() => _HoldingsPageState();
}

class _HoldingsPageState extends State<HoldingsPage> {
  final _search = TextEditingController();
  final List<int> _selected = [];
  List<_SymbolSummary> _summaries = [];

  Stream<List<_SymbolSummary>> get _stream {
    return (db.tickers.select()
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.createdAt,
                  mode: OrderingMode.desc,
                ),
          ]))
        .watch()
        .asyncMap((tickers) async {
      final allTrades = await db.trades.select().get();
      final q = _search.text.toLowerCase();

      // Collect all symbols from both tickers and trades
      final Map<String, _SymbolSummary> bySymbol = {};

      for (final t in tickers) {
        if (q.isNotEmpty &&
            !t.symbol.toLowerCase().contains(q) &&
            !t.name.toLowerCase().contains(q)) continue;
        bySymbol[t.symbol] = _SymbolSummary(
          symbol: t.symbol,
          name: t.name,
          holding: t,
          trades: [],
        );
      }

      for (final trade in allTrades) {
        if (q.isNotEmpty &&
            !trade.symbol.toLowerCase().contains(q) &&
            !trade.name.toLowerCase().contains(q)) continue;
        final existing = bySymbol[trade.symbol];
        if (existing != null) {
          existing.trades.add(trade);
        } else {
          bySymbol
              .putIfAbsent(
                trade.symbol,
                () => _SymbolSummary(
                  symbol: trade.symbol,
                  name: trade.name,
                  holding: null,
                  trades: [],
                ),
              )
              .trades
              .add(trade);
        }
      }

      final summaries = bySymbol.values.toList()
        ..sort((a, b) {
          // Holdings first, then by symbol
          if (a.holding != null && b.holding == null) return -1;
          if (a.holding == null && b.holding != null) return 1;
          return a.symbol.compareTo(b.symbol);
        });

      return summaries;
    });
  }

  @override
  Widget build(BuildContext context) {
    final deleteButton = IconButton(
      icon: const Icon(Icons.delete),
      tooltip: 'Delete selected',
      onPressed: _confirmDelete,
    );

    final leading = _selected.isNotEmpty
        ? IconButton(
            onPressed: () => setState(() => _selected.clear()),
            icon: const Icon(Icons.arrow_back),
            padding: const EdgeInsets.only(left: 16, right: 8),
          )
        : (_search.text.isEmpty
            ? const Padding(
                padding: EdgeInsets.only(left: 16, right: 8),
                child: Icon(Icons.search),
              )
            : IconButton(
                onPressed: () {
                  _search.text = '';
                  setState(() {});
                },
                icon: const Icon(Icons.arrow_back),
                padding: const EdgeInsets.only(left: 16, right: 8),
              ));

    final menuButton = PopupMenuButton(
      icon: const Icon(Icons.more_vert),
      tooltip: 'Show menu',
      itemBuilder: (context) => [
        if (_summaries.any((s) => s.holding != null))
          PopupMenuItem(
            child: ListTile(
              leading: const Icon(Icons.select_all),
              title: const Text('Select all'),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _selected
                    ..clear()
                    ..addAll(
                      _summaries
                          .where((s) => s.holding != null)
                          .map((s) => s.holding!.id),
                    );
                });
              },
            ),
          ),
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
                onChanged: (_) => setState(() {}),
                trailing: [
                  if (_selected.isNotEmpty) deleteButton,
                  menuButton,
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<List<_SymbolSummary>>(
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
        tooltip: 'Add to portfolio',
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    AsyncSnapshot<List<_SymbolSummary>> snap,
  ) {
    if (!snap.hasData) return const SizedBox();
    if (snap.hasError) return Center(child: Text(snap.error.toString()));

    final summaries = snap.data!;
    if (_summaries != summaries) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _summaries = summaries);
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
            isSelected: s.holding != null && _selected.contains(s.holding!.id),
            onTap: () {
              if (_selected.isNotEmpty && s.holding != null) {
                _toggleSelect(s.holding!.id);
              } else {
                _openDetail(s);
              }
            },
            onLongPress:
                s.holding != null ? () => _toggleSelect(s.holding!.id) : null,
          );
        },
      ),
    );
  }

  void _toggleSelect(int id) {
    setState(() {
      if (_selected.contains(id))
        _selected.remove(id);
      else
        _selected.add(id);
    });
  }

  void _openDetail(_SymbolSummary s) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _TradeHistoryPage(summary: s)),
    );
  }

  Future<void> _refreshCandles() async {
    final tickers = await db.tickers.select().get();
    for (final t in tickers) {
      await syncCandles(t.symbol);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text(
          'Delete ${_selected.length} holding(s)? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final symbolsToDelete = _summaries
        .where((s) => s.holding != null && _selected.contains(s.holding!.id))
        .map((s) => s.symbol)
        .toSet()
        .toList();
    await (db.tickers.delete()
          ..where((t) => t.symbol.isIn(symbolsToDelete)))
        .go();
    setState(() => _selected.clear());
  }
}

class _SymbolTile extends StatelessWidget {
  final _SymbolSummary summary;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _SymbolTile({
    required this.summary,
    required this.isSelected,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final holding = summary.holding;
    final changePct = holding?.change ?? 0.0;
    final hasRealizedPL = summary.trades.isNotEmpty;
    final realizedPL = summary.totalRealizedPL;

    return ListTile(
      selected: isSelected,
      leading: GestureDetector(
        onTap: onLongPress,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, animation) => ScaleTransition(
            scale: animation,
            child: child,
          ),
          child: isSelected
              ? Container(
                  key: const ValueKey('selected'),
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check,
                    color: Theme.of(context).colorScheme.onPrimary,
                    size: 18,
                  ),
                )
              : SizedBox(
                  key: const ValueKey('unselected'),
                  width: 30,
                  height: 30,
                  child: holding != null
                      ? Icon(
                          changePct >= 0
                              ? Icons.arrow_upward
                              : Icons.arrow_downward,
                          color:
                              changePct >= 0 ? Colors.green : Colors.redAccent,
                        )
                      : const Icon(Icons.history, color: Colors.grey),
                ),
        ),
      ),
      title: Text(summary.symbol),
      subtitle: holding != null
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
                    'Realized: ${realizedPL >= 0 ? '+' : ''}${currency.format(realizedPL)}',
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
      trailing: holding != null
          ? Text(
              currency.format(holding.amount * holding.price),
              style: Theme.of(context).textTheme.bodyMedium,
            )
          : null,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

/// Full trade history for one symbol.
class _TradeHistoryPage extends StatelessWidget {
  final _SymbolSummary summary;

  const _TradeHistoryPage({required this.summary});

  @override
  Widget build(BuildContext context) {
    final holding = summary.holding;
    final trades = [...summary.trades]
      ..sort((a, b) => b.tradeDate.compareTo(a.tradeDate));

    final totalRealized = summary.totalRealizedPL;
    final unrealizedGain = holding != null
        ? holding.amount * holding.price * (holding.change / 100)
        : 0.0;
    final totalGain = totalRealized + unrealizedGain;

    return Scaffold(
      appBar: AppBar(
        title: Text('${summary.symbol} — History'),
        actions: [
          if (holding != null)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Edit holding',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EditTickerPage(tickerId: holding.id),
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Summary card
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    summary.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  if (holding != null) ...[
                    _SummaryRow(
                      label: 'Shares held',
                      value: holding.amount.toStringAsFixed(4),
                    ),
                    _SummaryRow(
                      label: 'Avg cost',
                      value: currency.format(holding.price),
                    ),
                    _SummaryRow(
                      label: 'Current value',
                      value: currency.format(
                        holding.amount *
                            holding.price *
                            (1 + holding.change / 100),
                      ),
                    ),
                    _SummaryRow(
                      label: 'Unrealized P/L',
                      value:
                          '${unrealizedGain >= 0 ? '+' : ''}${currency.format(unrealizedGain)}'
                          ' (${holding.change.toStringAsFixed(2)}%)',
                      color:
                          unrealizedGain >= 0 ? Colors.green : Colors.redAccent,
                    ),
                  ],
                  if (trades.isNotEmpty) ...[
                    _SummaryRow(
                      label: 'Realized P/L',
                      value:
                          '${totalRealized >= 0 ? '+' : ''}${currency.format(totalRealized)}',
                      color:
                          totalRealized >= 0 ? Colors.green : Colors.redAccent,
                    ),
                  ],
                  if (holding != null || trades.isNotEmpty)
                    _SummaryRow(
                      label: 'Total gain',
                      value:
                          '${totalGain >= 0 ? '+' : ''}${currency.format(totalGain)}',
                      color: totalGain >= 0 ? Colors.green : Colors.redAccent,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (trades.isNotEmpty) ...[
            Text(
              'Trade History',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ...trades.map((t) => _TradeTile(trade: t)),
          ] else
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No trade history imported yet'),
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _SummaryRow({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _TradeTile extends StatelessWidget {
  final Trade trade;

  const _TradeTile({required this.trade});

  @override
  Widget build(BuildContext context) {
    final isBuy = trade.tradeType == 'open';
    final dateStr = DateFormat('dd MMM yyyy').format(trade.tradeDate);
    final qty = trade.quantity.abs();
    final total = (qty * trade.price).abs();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isBuy
              ? Colors.green.withValues(alpha: 0.15)
              : Colors.red.withValues(alpha: 0.15),
          child: Icon(
            isBuy ? Icons.arrow_downward : Icons.arrow_upward,
            color: isBuy ? Colors.green : Colors.redAccent,
            size: 18,
          ),
        ),
        title: Row(
          children: [
            Text(
              isBuy ? 'BUY' : 'SELL',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isBuy ? Colors.green : Colors.redAccent,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${qty.toStringAsFixed(4)} @ ${currency.format(trade.price)}',
            ),
          ],
        ),
        subtitle: Text(dateStr),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(currency.format(total)),
            if (!isBuy && trade.realizedPL != 0)
              Text(
                '${trade.realizedPL >= 0 ? '+' : ''}${currency.format(trade.realizedPL)}',
                style: TextStyle(
                  fontSize: 11,
                  color:
                      trade.realizedPL >= 0 ? Colors.green : Colors.redAccent,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
