import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/intraday_market_data.dart';
import 'package:market_monk/l10n/app_localizations.dart';
import 'package:market_monk/market_data_store.dart';
import 'package:market_monk/utils.dart';

/// A chip button styled after Flexify's DaySelector — animated border
/// highlights the selected state.
class ChartPeriodChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const ChartPeriodChip({
    super.key,
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
                style: TextStyle(color: colorScheme.onSurface, fontSize: 13),
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
class ChartActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const ChartActionChip({
    super.key,
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
                  style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small card showing a favorited symbol's latest price and selected period change,
/// used in the favorites row on the portfolio landing view.
class FavoriteChartCard extends StatelessWidget {
  // Price (11) + gap (8) + percent change (10), so the empty state
  // matches the filled state and the card height never shifts.
  static const double _valueHeight = 29;

  final String symbol;
  final String displayName;
  final DateTime periodStart;
  final int periodDays;
  final (DateTime, DateTime)? visibleRange;
  final bool intraday;
  final IntradaySeries? intradaySeries;
  final bool isActive;
  final bool selected;
  final Color selectionColor;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const FavoriteChartCard({
    super.key,
    required this.symbol,
    required this.displayName,
    required this.periodStart,
    required this.periodDays,
    this.visibleRange,
    required this.intraday,
    this.intradaySeries,
    required this.isActive,
    required this.selected,
    required this.selectionColor,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final stream = isActive && !intraday
        ? (marketDataDatabase.candles.select()
              ..where(
                (candle) =>
                    candle.symbol.equals(canonicalMarketSymbol(symbol)) &
                    candle.date.isBiggerThanValue(periodStart),
              )
              ..orderBy([
                (candle) => OrderingTerm(
                      expression: candle.date,
                      mode: OrderingMode.desc,
                    ),
              ])
              ..limit(periodDays > 0 ? periodDays : -1))
            .watch()
        : const Stream<List<StoredCandle>>.empty();

    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        width: 108,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected ? selectionColor.withValues(alpha: 0.10) : null,
          border: Border.all(
            color: selected
                ? selectionColor
                : colorScheme.outline.withValues(alpha: 0.3),
            width: selected ? 2 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            onLongPress: onLongPress,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          displayName,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (selected)
                        Icon(
                          Icons.check_circle_rounded,
                          size: 14,
                          color: selectionColor,
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  StreamBuilder<List<StoredCandle>>(
                    stream: intraday
                        ? Stream.value([
                            for (final bar
                                in intradaySeries?.candles.reversed ??
                                    <IbkrHistoricalCandle>[])
                              StoredCandle(
                                symbol: canonicalMarketSymbol(symbol),
                                date: bar.date.toLocal(),
                                open: bar.open,
                                high: bar.high,
                                low: bar.low,
                                close: bar.close,
                                adjClose: bar.close,
                                volume: bar.volume,
                              ),
                          ])
                        : stream,
                    builder: (context, snapshot) {
                      final candles = snapshot.data;
                      if (candles == null || candles.isEmpty) {
                        return const SizedBox(height: _valueHeight, width: 14);
                      }
                      final range = visibleRange;
                      final visibleCandles = range == null
                          ? candles
                          : candles
                              .where(
                                (candle) =>
                                    !candle.date.isBefore(range.$1) &&
                                    !candle.date.isAfter(range.$2),
                              )
                              .toList();
                      if (visibleCandles.isEmpty) {
                        return const SizedBox(height: _valueHeight, width: 14);
                      }
                      final price = visibleCandles.first.close /
                          candleCentDivisor(visibleCandles.first);
                      final pct = visibleCandles.length > 1
                          ? safePercentChange(
                              visibleCandles.last.close,
                              visibleCandles.first.close,
                            )
                          : null;
                      final changeColor =
                          (pct ?? 0) >= 0 ? Colors.green : Colors.redAccent;
                      return SizedBox(
                        height: _valueHeight,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              fmtNativeCurrency(price, symbolCurrency(symbol)),
                              style: const TextStyle(fontSize: 11, height: 1),
                            ),
                            const SizedBox(height: 8),
                            if (pct != null)
                              Text(
                                '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%',
                                style: TextStyle(
                                  fontSize: 10,
                                  height: 1,
                                  color: changeColor,
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RenameFavoriteDialog extends StatefulWidget {
  const RenameFavoriteDialog({super.key, required this.currentName});

  final String currentName;

  @override
  State<RenameFavoriteDialog> createState() => _RenameFavoriteDialogState();
}

class _RenameFavoriteDialogState extends State<RenameFavoriteDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.text('Rename favorite')),
      content: TextField(
        controller: _controller,
        decoration: InputDecoration(labelText: context.l10n.text('Name')),
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        onSubmitted: (value) => Navigator.pop(context, value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.text('Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(context.l10n.text('Rename')),
        ),
      ],
    );
  }
}
