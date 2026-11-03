import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/desktop_context_menu.dart';
import 'package:market_monk/l10n/app_localizations.dart';
import 'package:market_monk/utils.dart';

/// Dense, desktop-only stock trade history. The compact mobile tiles live in
/// TradeHistoryPage and remain independent of this layout.
class DesktopTradeHistory extends StatefulWidget {
  final String symbol;
  final String name;
  final Position? position;
  final List<Trade> trades;
  final double? totalRealizedUsd;
  final double? realizedToday;
  final double? totalGain;
  final bool hasImportedRealized;
  final bool brokerManaged;
  final Widget emptyState;
  final VoidCallback onAddTrade;
  final Future<void> Function(Trade) onEditTrade;
  final Future<void> Function(Trade) onDeleteTrade;

  const DesktopTradeHistory({
    super.key,
    required this.symbol,
    required this.name,
    required this.position,
    required this.trades,
    required this.totalRealizedUsd,
    required this.realizedToday,
    required this.totalGain,
    required this.hasImportedRealized,
    required this.brokerManaged,
    required this.emptyState,
    required this.onAddTrade,
    required this.onEditTrade,
    required this.onDeleteTrade,
  });

  @override
  State<DesktopTradeHistory> createState() => _DesktopTradeHistoryState();
}

class _DesktopTradeHistoryState extends State<DesktopTradeHistory> {
  final ScrollController _tableHorizontalController = ScrollController();
  String _sideFilter = 'all';
  int _sortColumn = 0;
  bool _sortAscending = false;

  @override
  void dispose() {
    _tableHorizontalController.dispose();
    super.dispose();
  }

  String _signedUsd(double? value) {
    if (value == null) return 'Historical FX unavailable';
    return '${value >= 0 ? '+' : ''}${fmtCurrency(value)}';
  }

  Color? _gainColor(double? value) {
    if (value == null) return null;
    return value >= 0 ? Colors.green : Colors.redAccent;
  }

  String _tradeCopyText(Trade trade) =>
      '${trade.symbol} ${trade.tradeType == 'open' ? 'BUY' : 'SELL'} '
      '${trade.quantity.abs()} @ ${fmtTradeNative(trade, trade.price)} · '
      '${DateFormat('yyyy-MM-dd').format(trade.tradeDate)}';

  List<DesktopMenuAction> _contextActions(Trade trade, BuildContext context) {
    if (widget.brokerManaged) return [];
    return [
      DesktopMenuAction(
        context.l10n.text('Edit trade'),
        () =>
            runDetachedTask(widget.onEditTrade(trade), 'Failed to edit trade'),
      ),
      DesktopMenuAction(
        context.l10n.text('Delete trade'),
        () => runDetachedTask(
          widget.onDeleteTrade(trade),
          'Failed to delete trade',
        ),
      ),
    ];
  }

  int _compareTrades(Trade a, Trade b) {
    final result = switch (_sortColumn) {
      1 => a.tradeType.compareTo(b.tradeType),
      2 => a.quantity.abs().compareTo(b.quantity.abs()),
      3 => a.price.compareTo(b.price),
      4 => (a.price * a.quantity.abs()).compareTo(b.price * b.quantity.abs()),
      5 => a.commission.abs().compareTo(b.commission.abs()),
      6 => a.realizedPL.compareTo(b.realizedPL),
      _ => a.tradeDate.compareTo(b.tradeDate),
    };
    if (result != 0) return _sortAscending ? result : -result;
    return b.tradeDate.compareTo(a.tradeDate);
  }

  void _sortBy(int column, bool ascending) {
    setState(() {
      _sortColumn = column;
      _sortAscending = ascending;
    });
  }

  Widget _metric(
    BuildContext context,
    String label,
    String value, {
    Color? color,
    String? detail,
  }) {
    final theme = Theme.of(context);
    return Container(
      height: 112,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(color: color),
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
    );
  }

  Widget _performanceChip(BuildContext context, String label, double? value) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: scheme.surfaceContainerLow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 10),
          Text(
            _signedUsd(value),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: _gainColor(value),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tradeTable(BuildContext context, List<Trade> displayedTrades) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final headings = [
      context.l10n.text('Date'),
      context.l10n.text('Type'),
      context.l10n.text('Quantity'),
      context.l10n.text('Price'),
      context.l10n.text('Value'),
      context.l10n.text('Fees'),
      context.l10n.text('Realized P/L'),
    ];

    return Card(
      key: const Key('desktop-trade-history-table'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) => Scrollbar(
          controller: _tableHorizontalController,
          thumbVisibility: true,
          notificationPredicate: (notification) => notification.depth == 0,
          child: SingleChildScrollView(
            controller: _tableHorizontalController,
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: math.max(900, constraints.maxWidth - 2),
              ),
              child: DataTable(
                key: const Key('desktop-trade-history-data-table'),
                sortColumnIndex: _sortColumn,
                sortAscending: _sortAscending,
                dataRowMinHeight: 62,
                dataRowMaxHeight: 62,
                headingRowColor: WidgetStatePropertyAll(
                  scheme.surfaceContainerLow,
                ),
                headingTextStyle: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                horizontalMargin: 20,
                columnSpacing: 26,
                columns: [
                  for (var index = 0; index < headings.length; index++)
                    DataColumn(
                      label: Text(headings[index]),
                      numeric: index >= 2,
                      onSort: _sortBy,
                    ),
                  const DataColumn(label: SizedBox(width: 36)),
                ],
                rows: [
                  for (final trade in displayedTrades)
                    _tradeRow(context, trade),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  DataRow _tradeRow(BuildContext context, Trade trade) {
    final isBuy = trade.tradeType == 'open';
    final sideColor = isBuy ? Colors.green : Colors.redAccent;
    final qty = trade.quantity.abs();
    final total = qty * trade.price;
    final theme = Theme.of(context);
    final actions = _contextActions(trade, context);
    final textStyle = theme.textTheme.bodyMedium;
    final muted = theme.colorScheme.onSurfaceVariant;

    return DataRow(
      key: ValueKey(
        'desktop-trade-${trade.id}-${trade.tradeDate.microsecondsSinceEpoch}',
      ),
      color: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered)) {
          return theme.colorScheme.primary.withValues(alpha: 0.05);
        }
        return null;
      }),
      cells: [
        DataCell(
          DesktopContextMenu(
            actions: actions,
            copyText: _tradeCopyText(trade),
            copyLabel: context.l10n.text('Copy trade'),
            child: Text(DateFormat('dd MMM yyyy').format(trade.tradeDate)),
          ),
        ),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: sideColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              context.l10n.text(isBuy ? 'BUY' : 'SELL'),
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: sideColor,
              ),
            ),
          ),
        ),
        DataCell(Text(qty.toStringAsFixed(4), style: textStyle)),
        DataCell(Text(fmtTradeNative(trade, trade.price), style: textStyle)),
        DataCell(Text(fmtTradeNative(trade, total), style: textStyle)),
        DataCell(
          Text(
            trade.commission == 0
                ? '—'
                : fmtTradeNative(trade, trade.commission.abs()),
            style: textStyle?.copyWith(color: muted),
          ),
        ),
        DataCell(
          Text(
            isBuy || trade.realizedPL == 0
                ? '—'
                : '${trade.realizedPL >= 0 ? '+' : ''}${fmtTradeNative(trade, trade.realizedPL)}',
            style: textStyle?.copyWith(
              color: isBuy || trade.realizedPL == 0
                  ? muted
                  : _gainColor(trade.realizedPL),
            ),
          ),
        ),
        DataCell(
          widget.brokerManaged
              ? const SizedBox(width: 36)
              : PopupMenuButton<String>(
                  key: ValueKey('desktop-trade-actions-${trade.id}'),
                  tooltip: context.l10n.text('Trade actions'),
                  icon: const Icon(Icons.more_horiz_rounded),
                  onSelected: (action) {
                    if (action == 'edit') {
                      runDetachedTask(
                        widget.onEditTrade(trade),
                        'Failed to edit trade',
                      );
                    } else {
                      runDetachedTask(
                        widget.onDeleteTrade(trade),
                        'Failed to delete trade',
                      );
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text(context.l10n.text('Edit trade')),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(context.l10n.text('Delete trade')),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final position = widget.position;
    final buys = widget.trades.where((t) => t.tradeType == 'open').length;
    final sells = widget.trades.length - buys;
    final displayedTrades = widget.trades
        .where(
          (trade) => _sideFilter == 'all' || trade.tradeType == _sideFilter,
        )
        .toList()
      ..sort(_compareTrades);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1500),
        child: ListView(
          key: const Key('desktop-trade-history-content'),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.symbol,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        widget.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!widget.brokerManaged) ...[
                  const SizedBox(width: 16),
                  FilledButton.icon(
                    onPressed: widget.onAddTrade,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(context.l10n.text('Add trade')),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 940 ? 4 : 2;
                const gap = 12.0;
                final width =
                    (constraints.maxWidth - (columns - 1) * gap) / columns;
                final metrics = [
                  _metric(
                    context,
                    context.l10n.text('Shares held'),
                    position?.netShares.toStringAsFixed(4) ?? '—',
                  ),
                  _metric(
                    context,
                    context.l10n.text('Avg cost'),
                    position == null
                        ? '—'
                        : fmtNativeCurrency(
                            position.avgCost,
                            position.nativeCurrency,
                          ),
                  ),
                  _metric(
                    context,
                    context.l10n.text('Current value'),
                    position == null ? '—' : fmtCurrency(position.currentValue),
                  ),
                  _metric(
                    context,
                    context.l10n.text('Total gain'),
                    position == null && widget.trades.isEmpty
                        ? '—'
                        : _signedUsd(widget.totalGain),
                    color: position == null && widget.trades.isEmpty
                        ? null
                        : _gainColor(widget.totalGain),
                  ),
                ];
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final metric in metrics)
                      SizedBox(width: width, child: metric),
                  ],
                );
              },
            ),
            if (position != null ||
                widget.realizedToday != null ||
                widget.hasImportedRealized) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (position != null)
                    _performanceChip(
                      context,
                      context.l10n.text('Unrealized P/L'),
                      position.unrealizedPL,
                    ),
                  if (widget.realizedToday != null)
                    _performanceChip(
                      context,
                      context.l10n.text('Realized P/L today'),
                      widget.realizedToday,
                    ),
                  if (widget.hasImportedRealized)
                    _performanceChip(
                      context,
                      context.l10n.text('Imported realized P/L'),
                      widget.totalRealizedUsd,
                    ),
                ],
              ),
            ],
            const SizedBox(height: 30),
            LayoutBuilder(
              builder: (context, constraints) {
                final title = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.text('Trade History'),
                      style: theme.textTheme.titleLarge,
                    ),
                    Text(
                      '${widget.trades.length} ${context.l10n.text('Trades')} · '
                      '$buys ${context.l10n.text('Buy')} · '
                      '$sells ${context.l10n.text('Sell')}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                );
                final filter = SegmentedButton<String>(
                  key: const Key('desktop-trade-history-filter'),
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: 'all',
                      label: Text(context.l10n.text('All')),
                    ),
                    ButtonSegment(
                      value: 'open',
                      label: Text(context.l10n.text('Buy')),
                    ),
                    ButtonSegment(
                      value: 'close',
                      label: Text(context.l10n.text('Sell')),
                    ),
                  ],
                  selected: {_sideFilter},
                  onSelectionChanged: (selection) =>
                      setState(() => _sideFilter = selection.first),
                );
                if (widget.trades.isEmpty) return title;
                if (constraints.maxWidth < 650) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      title,
                      const SizedBox(height: 14),
                      filter,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: title),
                    filter,
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            if (widget.trades.isEmpty)
              SizedBox(height: 300, child: widget.emptyState)
            else if (displayedTrades.isEmpty)
              SizedBox(
                height: 180,
                child: Center(
                  child: Text(context.l10n.text('No matching trades')),
                ),
              )
            else
              _tradeTable(context, displayedTrades),
          ],
        ),
      ),
    );
  }
}
