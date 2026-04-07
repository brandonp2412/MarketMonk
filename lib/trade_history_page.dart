import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/edit_ticker_page.dart';
import 'package:market_monk/holdings_page.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/utils.dart';

class TradeHistoryPage extends StatefulWidget {
  final SymbolSummary summary;

  const TradeHistoryPage({super.key, required this.summary});

  @override
  State<TradeHistoryPage> createState() => _TradeHistoryPageState();
}

class _TradeHistoryPageState extends State<TradeHistoryPage> {
  late Stream<List<Trade>> _tradesStream;

  @override
  void initState() {
    super.initState();
    _tradesStream = (db.trades.select()
          ..where((t) => t.symbol.equals(widget.summary.symbol))
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.tradeDate,
                  mode: OrderingMode.desc,
                ),
          ]))
        .watch();
  }

  @override
  Widget build(BuildContext context) {
    final position = widget.summary.position;

    return StreamBuilder<List<Trade>>(
      stream: _tradesStream,
      builder: (context, snap) {
        final trades = snap.data ?? widget.summary.trades;
        final totalRealized = trades.fold(0.0, (sum, t) => sum + t.realizedPL);
        final unrealizedPL = position?.unrealizedPL ?? 0.0;
        final totalGain = totalRealized + unrealizedPL;

        return Scaffold(
          appBar: AppBar(
            title: Text('${widget.summary.symbol} — History'),
            actions: [
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Add trade',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        EditTickerPage(symbol: widget.summary.symbol),
                  ),
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
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
                          widget.summary.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        if (position != null) ...[
                          _SummaryRow(
                            label: 'Shares held',
                            value: position.netShares.toStringAsFixed(4),
                          ),
                          _SummaryRow(
                            label: 'Avg cost',
                            value: fmtCurrency(position.avgCost),
                          ),
                          _SummaryRow(
                            label: 'Current value',
                            value: fmtCurrency(position.currentValue),
                          ),
                          _SummaryRow(
                            label: 'Unrealized P/L',
                            value:
                                '${unrealizedPL >= 0 ? '+' : ''}${fmtCurrency(unrealizedPL)}'
                                ' (${position.change.toStringAsFixed(2)}%)',
                            color: unrealizedPL >= 0
                                ? Colors.green
                                : Colors.redAccent,
                          ),
                        ],
                        if (trades.any((t) => t.realizedPL != 0)) ...[
                          _SummaryRow(
                            label: 'Realized P/L',
                            value:
                                '${totalRealized >= 0 ? '+' : ''}${fmtCurrency(totalRealized)}',
                            color: totalRealized >= 0
                                ? Colors.green
                                : Colors.redAccent,
                          ),
                        ],
                        if (position != null || trades.isNotEmpty)
                          _SummaryRow(
                            label: 'Total gain',
                            value:
                                '${totalGain >= 0 ? '+' : ''}${fmtCurrency(totalGain)}',
                            color: totalGain >= 0
                                ? Colors.green
                                : Colors.redAccent,
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
                  ...trades.map(
                    (t) => _TradeTile(
                      trade: t,
                      onLongPress: () => _showTradeActions(t),
                    ),
                  ),
                ] else
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No trade history imported yet'),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showTradeActions(Trade trade) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit trade'),
              onTap: () {
                Navigator.pop(ctx);
                _editTrade(trade);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.redAccent),
              title: const Text(
                'Delete trade',
                style: TextStyle(color: Colors.redAccent),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteTrade(trade);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editTrade(Trade trade) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _EditTradeDialog(trade: trade),
    );
  }

  Future<void> _confirmDeleteTrade(Trade trade) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Trade'),
        content: const Text('Delete this trade? This cannot be undone.'),
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
    await (db.trades.delete()..where((t) => t.id.equals(trade.id))).go();
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
  final VoidCallback? onLongPress;

  const _TradeTile({required this.trade, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final isBuy = trade.tradeType == 'open';
    final dateStr = DateFormat('dd MMM yyyy').format(trade.tradeDate);
    final qty = trade.quantity.abs();
    final total = (qty * trade.price).abs();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        onLongPress: onLongPress,
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
        title: Text(
          isBuy ? 'BUY' : 'SELL',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isBuy ? Colors.green : Colors.redAccent,
            fontSize: 13,
          ),
        ),
        subtitle: Text(
          '${qty.toStringAsFixed(4)} @ ${fmtCurrency(trade.price)}  ·  $dateStr',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(fmtCurrency(total)),
            if (!isBuy && trade.realizedPL != 0)
              Text(
                '${trade.realizedPL >= 0 ? '+' : ''}${fmtCurrency(trade.realizedPL)}',
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

class _EditTradeDialog extends StatefulWidget {
  final Trade trade;

  const _EditTradeDialog({required this.trade});

  @override
  State<_EditTradeDialog> createState() => _EditTradeDialogState();
}

class _EditTradeDialogState extends State<_EditTradeDialog> {
  late bool _isBuy;
  late TextEditingController _qty;
  late TextEditingController _price;
  late TextEditingController _realizedPL;
  late DateTime _tradeDate;

  @override
  void initState() {
    super.initState();
    _isBuy = widget.trade.tradeType == 'open';
    _qty = TextEditingController(
      text: widget.trade.quantity.abs().toStringAsFixed(4),
    );
    _price = TextEditingController(
      text: widget.trade.price.toStringAsFixed(2),
    );
    _realizedPL = TextEditingController(
      text: widget.trade.realizedPL.toStringAsFixed(2),
    );
    _tradeDate = widget.trade.tradeDate;
  }

  @override
  void dispose() {
    _qty.dispose();
    _price.dispose();
    _realizedPL.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _tradeDate,
      firstDate: DateTime(1970),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _tradeDate = picked);
  }

  Future<void> _save() async {
    final qty = double.tryParse(_qty.text);
    final price = double.tryParse(_price.text);
    final realizedPL = double.tryParse(_realizedPL.text) ?? 0.0;
    if (qty == null || qty <= 0 || price == null || price <= 0) return;

    await (db.trades.update()..where((t) => t.id.equals(widget.trade.id)))
        .write(
      TradesCompanion(
        quantity: Value(_isBuy ? qty : -qty),
        price: Value(price),
        tradeType: Value(_isBuy ? 'open' : 'close'),
        tradeDate: Value(_tradeDate),
        realizedPL: Value(realizedPL),
      ),
    );

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('dd MMM yyyy').format(_tradeDate);

    return AlertDialog(
      title: const Text('Edit Trade'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Buy')),
                ButtonSegment(value: false, label: Text('Sell')),
              ],
              selected: {_isBuy},
              onSelectionChanged: (s) => setState(() => _isBuy = s.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _qty,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Quantity',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _price,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Price',
                border: OutlineInputBorder(),
                prefixText: '\$',
              ),
            ),
            if (!_isBuy) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _realizedPL,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Realized P/L',
                  border: OutlineInputBorder(),
                  prefixText: '\$',
                ),
              ),
            ],
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Trade date'),
              subtitle: Text(dateStr),
              trailing: const Icon(Icons.calendar_today),
              onTap: _pickDate,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
