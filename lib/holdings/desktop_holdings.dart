part of '../holdings_page.dart';

extension _HoldingsDesktopView on HoldingsPageState {
  void _setDesktopSort(_HoldingsSort sort) {
    _updateState(() {
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
    Widget? detailWidget,
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
              style: theme.textTheme.titleLarge?.copyWith(color: valueColor),
            ),
            if (detail != null || detailWidget != null) ...[
              const SizedBox(height: 3),
              detailWidget ??
                  Text(
                    detail!,
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

  ({double gainUsd, double gainPct})? _ibkrCashOutSummary(
    AccountManager accounts,
  ) {
    final account = accounts.activeAccount;
    final performance = accounts.ibkrPerformanceCacheFor(account, '1Y');
    final netLiquidation = accounts.portfolioCacheFor(account)?.netLiquidation;
    if (performance == null || netLiquidation == null) return null;

    try {
      final pnl = calculateIbkrCashOutPnl(performance, netLiquidation);
      final basePerUsd = requireUsdRate(performance.currency);
      if (!basePerUsd.isFinite || basePerUsd <= 0) return null;
      return (gainUsd: pnl.profitLoss / basePerUsd, gainPct: pnl.percent ?? 0);
    } catch (_) {
      return null;
    }
  }

  ({double valueUsd, double percent})? _cashAllocation(
    AccountManager accounts,
    Iterable<Position> positions,
  ) {
    if (!accounts.ibkrConfigFor().enabled) return null;
    final cached = accounts.portfolioCacheFor();
    final cash = ibkrCashValueUsd(
      cashBalance: cached?.cashBalance,
      netLiquidation: cached?.netLiquidation,
      netLiquidationUsd: cached?.netLiquidationUsd,
    );
    if (cash == null) return null;
    final accountPositions = cached?.positions ?? positions;
    final stocks = accountPositions.fold<double>(
      0,
      (sum, position) => sum + position.currentValue,
    );
    final total = stocks + cash;
    return (valueUsd: cash, percent: total > 0 ? cash / total * 100 : 0);
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
    final totalValue = open.fold(
      0.0,
      (sum, position) => sum + position.currentValue,
    );
    final totalCost = open.fold(
      0.0,
      (sum, position) => sum + position.costBasis,
    );
    final costBasisGain = open.fold(
      0.0,
      (sum, position) => sum + position.unrealizedPL,
    );
    final accounts = context.watch<AccountManager>();
    final cashOutSummary = _ibkrCashOutSummary(accounts);
    final cashBalance =
        ibkrManaged ? accounts.portfolioCacheFor()?.cashBalance : null;
    final cash = ibkrManaged ? _cashAllocation(accounts, open) : null;
    final query = _search.text.trim().toLowerCase();
    final showCashRow =
        cash != null && (query.isEmpty || 'cash'.contains(query));
    final totalUnrealized = cashOutSummary?.gainUsd ?? costBasisGain;
    final totalUnrealizedPct = cashOutSummary?.gainPct ??
        (totalCost > 0 ? costBasisGain / totalCost * 100 : 0.0);
    final winners = open.where((position) => position.change >= 0).length;
    final sorted = _sortDesktopSummaries(summaries);
    final focusedSymbol = _viFocusIndex >= 0 && _viFocusIndex < sorted.length
        ? sorted[_viFocusIndex].symbol
        : null;

    DataCell textCell(
      String text, {
      required SymbolSummary summary,
      bool numeric = true,
      Color? color,
    }) {
      return DataCell(
        DesktopContextMenu(
          actionsBuilder: () => _holdingActions(summary, ibkrManaged),
          copyText: text,
          copyLabel: context.l10n.text('Copy value'),
          child: Align(
            alignment: numeric ? Alignment.centerRight : Alignment.centerLeft,
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        onTap: _selecting ? null : () => _openDetail(summary),
      );
    }

    return Padding(
      key: const Key('desktop-holdings-content'),
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          desktopMetricGrid(
            key: const Key('desktop-holdings-metrics'),
            minCardWidth: 235,
            cards: [
              if (cashBalance != null)
                _desktopMetric(
                  context,
                  label: context.l10n.text('Cash'),
                  value: formatIbkrReportedCash(cashBalance),
                  detail: cash == null
                      ? null
                      : '${formatCashAllocationPercent(cash.percent)}% allocation',
                ),
              _desktopMetric(
                context,
                label: context.l10n.text('Market value'),
                value: fmtCurrency(totalValue),
              ),
              _desktopMetric(
                context,
                label: context.l10n.text('Cost basis'),
                value: fmtCurrency(totalCost),
              ),
              _desktopMetric(
                context,
                label: context.l10n.text(
                  cashOutSummary == null ? 'Unrealized P/L' : 'Total P/L',
                ),
                value:
                    '${totalUnrealized >= 0 ? '+' : ''}${fmtCurrency(totalUnrealized)}',
                detail:
                    '${totalUnrealizedPct >= 0 ? '+' : ''}${totalUnrealizedPct.toStringAsFixed(2)}%',
                valueColor:
                    totalUnrealized >= 0 ? Colors.green : Colors.redAccent,
              ),
              _desktopMetric(
                context,
                label: context.l10n.text('Open positions'),
                value: open.length.toString(),
                detailWidget: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$winners positive',
                        style: const TextStyle(color: Colors.green),
                      ),
                      const TextSpan(text: ' · '),
                      TextSpan(
                        text: '${open.length - winners} negative',
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ],
                  ),
                  key: const Key('desktop-holdings-position-breakdown'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: Builder(
                builder: (context) {
                  return LayoutBuilder(
                    builder: (context, constraints) => Scrollbar(
                      key: const Key('desktop-holdings-horizontal-scrollbar'),
                      controller: _desktopTableHorizontalScrollController,
                      thumbVisibility: true,
                      notificationPredicate: (notification) =>
                          notification.depth == 0,
                      child: SingleChildScrollView(
                        key: const Key('desktop-holdings-horizontal-scroll'),
                        controller: _desktopTableHorizontalScrollController,
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: (constraints.maxWidth - 8).clamp(
                              0,
                              double.infinity,
                            ),
                          ),
                          child: Scrollbar(
                            controller: _desktopTableScrollController,
                            child: SingleChildScrollView(
                              controller: _desktopTableScrollController,
                              child: DataTable(
                                showCheckboxColumn: true,
                                onSelectAll: (_) => _toggleSelectAll(),
                                sortColumnIndex: switch (_desktopSort) {
                                  _HoldingsSort.symbol => 0,
                                  _HoldingsSort.shares => 1,
                                  _HoldingsSort.avgCost => 2,
                                  _HoldingsSort.price => 3,
                                  _HoldingsSort.value => 4,
                                  _HoldingsSort.unrealized => 5,
                                  _HoldingsSort.returnPct => 6,
                                },
                                sortAscending: _desktopSortAscending,
                                headingRowColor: WidgetStatePropertyAll(
                                  theme.colorScheme.surfaceContainerLow,
                                ),
                                headingTextStyle:
                                    theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                dataRowMinHeight: 62,
                                dataRowMaxHeight: 70,
                                horizontalMargin: 18,
                                columnSpacing: 20,
                                columns: [
                                  DataColumn(
                                    columnWidth: const IntrinsicColumnWidth(),
                                    label: Text(context.l10n.text('Holding')),
                                    onSort: (_, __) =>
                                        _setDesktopSort(_HoldingsSort.symbol),
                                  ),
                                  DataColumn(
                                    columnWidth: const IntrinsicColumnWidth(),
                                    numeric: true,
                                    label: Text(context.l10n.text('Shares')),
                                    onSort: (_, __) =>
                                        _setDesktopSort(_HoldingsSort.shares),
                                  ),
                                  DataColumn(
                                    numeric: true,
                                    label: Text(context.l10n.text('Avg cost')),
                                    onSort: (_, __) =>
                                        _setDesktopSort(_HoldingsSort.avgCost),
                                  ),
                                  DataColumn(
                                    columnWidth: const IntrinsicColumnWidth(
                                      flex: 1,
                                    ),
                                    numeric: true,
                                    label: Text(context.l10n.text('Price')),
                                    onSort: (_, __) =>
                                        _setDesktopSort(_HoldingsSort.price),
                                  ),
                                  DataColumn(
                                    columnWidth: const IntrinsicColumnWidth(
                                      flex: 1,
                                    ),
                                    numeric: true,
                                    label: Text(
                                      context.l10n.text('Market value'),
                                    ),
                                    onSort: (_, __) =>
                                        _setDesktopSort(_HoldingsSort.value),
                                  ),
                                  DataColumn(
                                    columnWidth: const IntrinsicColumnWidth(
                                      flex: 1,
                                    ),
                                    numeric: true,
                                    label: Text(context.l10n.text('P/L')),
                                    onSort: (_, __) => _setDesktopSort(
                                      _HoldingsSort.unrealized,
                                    ),
                                  ),
                                  DataColumn(
                                    columnWidth: const IntrinsicColumnWidth(
                                      flex: 1,
                                    ),
                                    numeric: true,
                                    label: Text(context.l10n.text('Return')),
                                    onSort: (_, __) => _setDesktopSort(
                                      _HoldingsSort.returnPct,
                                    ),
                                  ),
                                ],
                                rows: [
                                  if (showCashRow)
                                    DataRow(
                                      cells: [
                                        DataCell(
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons
                                                    .account_balance_wallet_outlined,
                                                size: 20,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                'Cash · ${formatCashAllocationPercent(cash.percent)}%',
                                              ),
                                            ],
                                          ),
                                        ),
                                        for (var i = 0; i < 3; i++)
                                          const DataCell(Text('—')),
                                        DataCell(
                                          Text(fmtCurrency(cash.valueUsd)),
                                        ),
                                        const DataCell(Text('—')),
                                        const DataCell(Text('—')),
                                      ],
                                    ),
                                  for (final summary in sorted)
                                    (() {
                                      final position = summary.position;
                                      final isClosed = position == null;
                                      final returnPct = position?.change ?? 0;
                                      final pnl = position?.unrealizedPL;
                                      final pnlText = pnl == null
                                          ? '—'
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
                                      final changeColor = switch (true) {
                                        _ when isClosed =>
                                          theme.colorScheme.onSurfaceVariant,
                                        _ when returnPct >= 0 => Colors.green,
                                        _ => Colors.redAccent,
                                      };
                                      final pnlColor = switch (true) {
                                        _ when pnl == null => null,
                                        _ when pnl >= 0 => Colors.green,
                                        _ => Colors.redAccent,
                                      };

                                      return DataRow(
                                        color: summary.symbol == focusedSymbol
                                            ? WidgetStatePropertyAll(
                                                theme.colorScheme.secondary
                                                    .withValues(alpha: 0.15),
                                              )
                                            : null,
                                        selected: _selectedSymbols.contains(
                                          summary.symbol,
                                        ),
                                        onSelectChanged: (_) =>
                                            _toggleHoldingSelection(
                                          summary.symbol,
                                        ),
                                        cells: [
                                          DataCell(
                                            DesktopContextMenu(
                                              key: summary.symbol ==
                                                      focusedSymbol
                                                  ? _viRowKey
                                                  : ValueKey<String>(
                                                      summary.symbol,
                                                    ),
                                              actionsBuilder: () =>
                                                  _holdingActions(
                                                summary,
                                                ibkrManaged,
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    switch (true) {
                                                      _ when isClosed =>
                                                        Icons.history_rounded,
                                                      _ when returnPct >= 0 =>
                                                        Icons
                                                            .trending_up_rounded,
                                                      _ => Icons
                                                          .trending_down_rounded,
                                                    },
                                                    size: 20,
                                                    color: changeColor,
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Column(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Row(
                                                          children: [
                                                            Flexible(
                                                              child: Text(
                                                                summary.symbol,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                style: theme
                                                                    .textTheme
                                                                    .titleSmall
                                                                    ?.copyWith(),
                                                              ),
                                                            ),
                                                            if (isClosed) ...[
                                                              const SizedBox(
                                                                width: 8,
                                                              ),
                                                              Text(
                                                                context.l10n
                                                                    .text(
                                                                  'Closed',
                                                                ),
                                                                style: theme
                                                                    .textTheme
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
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: theme.textTheme
                                                              .bodySmall
                                                              ?.copyWith(
                                                            color: theme
                                                                .colorScheme
                                                                .onSurfaceVariant,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            onTap: _selecting
                                                ? null
                                                : () => _openDetail(summary),
                                          ),
                                          textCell(shares, summary: summary),
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
                                          textCell(
                                            position == null
                                                ? '—'
                                                : fmtCurrency(
                                                    position.currentValue,
                                                  ),
                                            summary: summary,
                                          ),
                                          textCell(
                                            pnlText,
                                            summary: summary,
                                            color: pnlColor,
                                          ),
                                          textCell(
                                            position == null
                                                ? '—'
                                                : '${returnPct >= 0 ? '+' : ''}${returnPct.toStringAsFixed(2)}%',
                                            summary: summary,
                                            color: changeColor,
                                          ),
                                        ],
                                      );
                                    })(),
                                ],
                              ),
                            ),
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
      ),
    );
  }
}
