part of '../portfolio_page.dart';

extension _PortfolioDesktopView on PortfolioPageState {
  Widget _buildDesktopPortfolio({
    required List<Position> positions,
    required List<PortfolioAllocation> sorted,
    required List<Color> colors,
    required List<MarketDonutSlice> slices,
    required int? selectedIndex,
    required String displayTotal,
    required String totalLabel,
    IbkrAccountValue? cashBalance,
    required double totalGain,
    required double totalGainPct,
    required bool isCashOut,
    required bool hasRefreshWarning,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final settings = context.watch<SettingsState>();
    final accounts = context.watch<AccountManager>();
    final allocationTotal = sorted.fold<double>(
      0,
      (sum, holding) => sum + holding.value,
    );
    final byReturn = [...positions]..sort(
        (firstPosition, secondPosition) =>
            (_holdingReturn(secondPosition)?.percent ?? double.negativeInfinity)
                .compareTo(
          _holdingReturn(firstPosition)?.percent ?? double.negativeInfinity,
        ),
      );
    final currencyCount =
        positions.map((position) => position.nativeCurrency).toSet().length;
    final positionLabel = positions.length == 1 ? 'position' : 'positions';
    final currencyLabel = currencyCount == 1 ? 'currency' : 'currencies';
    final windowWidth = MediaQuery.sizeOf(context).width;
    final expandedActions = windowWidth >= 1280;
    final inlineCurrencies = settings.visibleCurrencies.length > 1 &&
        windowWidth >= 1080 + settings.visibleCurrencies.length * 70;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: SizedBox(
          height: constraints.maxHeight < 840 ? 840 : constraints.maxHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ProfilePicker(
                      key: const Key('portfolio-profile-picker'),
                      onExport: expandedActions
                          ? null
                          : () => runDetachedTask(
                                _exportCsv(context, positions),
                                'Failed to export portfolio CSV',
                              ),
                      onShare: !expandedActions && _supportsFileSharing
                          ? () => runDetachedTask(
                                _shareCsv(context, positions),
                                'Failed to share portfolio CSV',
                              )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${accounts.activeAccount} · ${context.l10n.text('Portfolio')}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${positions.length} $positionLabel · $currencyCount $currencyLabel',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (expandedActions) ...[
                      TextButton.icon(
                        key: const Key('desktop-portfolio-export'),
                        style: TextButton.styleFrom(
                          foregroundColor: colorScheme.onSurface,
                        ),
                        onPressed: () => runDetachedTask(
                          _exportCsv(context, positions),
                          'Failed to export portfolio CSV',
                        ),
                        icon: const Icon(Icons.download_rounded),
                        label: Text(context.l10n.text('Export CSV')),
                      ),
                      const SizedBox(width: 8),
                      if (_supportsFileSharing) ...[
                        OutlinedButton.icon(
                          key: const Key('desktop-portfolio-share'),
                          onPressed: () => runDetachedTask(
                            _shareCsv(context, positions),
                            'Failed to share portfolio CSV',
                          ),
                          icon: const Icon(Icons.share_rounded),
                          label: Text(context.l10n.text('Share CSV')),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                    Tooltip(
                      message: context.l10n.text('Refresh'),
                      child: IconButton(
                        onPressed: _updateCandles,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ),
                    if (settings.visibleCurrencies.length > 1)
                      const SizedBox(width: 8),
                    if (inlineCurrencies)
                      const CurrencyButtons(
                        key: Key('portfolio-currency-buttons'),
                      ),
                    if (settings.visibleCurrencies.length > 1 &&
                        !inlineCurrencies)
                      PopupMenuButton<String>(
                        key: const Key('portfolio-currency-menu'),
                        onSelected: (value) => runDetachedTask(
                          settings.setDisplayCurrency(value),
                          'Failed to change display currency',
                        ),
                        itemBuilder: (_) => [
                          for (final currencyCode in settings.visibleCurrencies)
                            CheckedPopupMenuItem(
                              value: currencyCode,
                              checked: currencyCode == settings.displayCurrency,
                              child: Text(currencyCode),
                            ),
                        ],
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: colorScheme.outlineVariant,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                settings.displayCurrency,
                                style: theme.textTheme.labelLarge,
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.expand_more_rounded, size: 20),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                if (hasRefreshWarning) ...[
                  const SizedBox(height: 16),
                  _buildRefreshWarning(context),
                ],
                const SizedBox(height: 20),
                _periodPicker(),
                const SizedBox(height: 12),
                desktopMetricGrid(
                  key: const Key('desktop-portfolio-metrics'),
                  minCardWidth: 270,
                  cards: [
                    _DesktopPortfolioMetric(
                      label: context.l10n.text(totalLabel),
                      value: displayTotal,
                      icon: Icons.account_balance_wallet_outlined,
                    ),
                    _DesktopPortfolioMetric(
                      label: context.l10n.text('Stock value'),
                      value: fmtCurrency(
                        sorted.where((holding) => !holding.isCash).fold<double>(
                              0,
                              (sum, holding) => sum + holding.value,
                            ),
                      ),
                      detail: switch (true) {
                        _ when _returnCutoff != null =>
                          'Cash · ${fmtCurrency(sorted.where((holding) => holding.isCash).fold<double>(0, (sum, holding) => sum + holding.value))}',
                        _ when cashBalance == null =>
                          context.l10n.text('Open stock positions'),
                        _ => 'Cash · ${formatIbkrReportedCash(cashBalance)}',
                      },
                      icon: Icons.show_chart_rounded,
                    ),
                    _DesktopPortfolioMetric(
                      label: context.l10n.text(
                        switch (true) {
                          _ when isCashOut => 'Total P/L',
                          _ when _period == 0 => 'Unrealized P/L',
                          _ => 'Open holdings P/L',
                        },
                      ),
                      value: totalGain.isFinite
                          ? '${totalGain >= 0 ? '+' : ''}${fmtCurrency(totalGain)}'
                          : 'Unavailable',
                      detail: totalGainPct.isFinite
                          ? '${totalGainPct >= 0 ? '+' : ''}${totalGainPct.toStringAsFixed(2)}%'
                          : 'History does not cover this period',
                      valueColor:
                          totalGain >= 0 ? Colors.green : Colors.redAccent,
                      icon: totalGain >= 0
                          ? Icons.trending_up_rounded
                          : Icons.trending_down_rounded,
                    ),
                    _DesktopPortfolioMetric(
                      label: context.l10n.text('Positions'),
                      value: sorted
                          .where((holding) => !holding.isCash)
                          .length
                          .toString(),
                      detail: _returnCutoff == null
                          ? context.l10n.text('Currently open')
                          : 'Held on this date',
                      icon: Icons.view_list_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 7,
                        child: Card(
                          margin: EdgeInsets.zero,
                          clipBehavior: Clip.antiAlias,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.l10n.text('Allocation'),
                                  style: theme.textTheme.titleLarge,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _returnCutoff == null
                                      ? context.l10n.text(
                                          'How your stock portfolio is distributed',
                                        )
                                      : DateFormat.yMMMd().format(
                                          _returnCutoff!,
                                        ),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 28),
                                Expanded(
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      final holdingsList = Scrollbar(
                                        key: const Key(
                                          'desktop-allocation-scrollbar',
                                        ),
                                        controller: _allocationScrollController,
                                        child: ListView.separated(
                                          controller:
                                              _allocationScrollController,
                                          padding: const EdgeInsets.only(
                                            right: 12,
                                          ),
                                          itemCount: sorted.length,
                                          separatorBuilder: (_, __) =>
                                              const SizedBox(height: 14),
                                          itemBuilder: (context, index) {
                                            final position = sorted[index];
                                            final allocationPct =
                                                allocationTotal > 0
                                                    ? position.value /
                                                        allocationTotal *
                                                        100
                                                    : 0.0;
                                            return _DesktopAllocationRow(
                                              color: colors[index],
                                              symbol: position.symbol,
                                              name: position.name,
                                              value: position.value,
                                              allocationPct: allocationPct,
                                              selected: selectedIndex == index,
                                              onTap: () => _updateState(
                                                () => touchedIndex =
                                                    touchedIndex == index
                                                        ? null
                                                        : index,
                                              ),
                                            );
                                          },
                                        ),
                                      );
                                      final compact =
                                          constraints.maxWidth < 600;
                                      final chart = Center(
                                        child: AspectRatio(
                                          aspectRatio: 1,
                                          child: _buildDesktopAllocationChart(
                                            slices: slices,
                                            sorted: sorted,
                                            selectedIndex: selectedIndex,
                                            compact: compact,
                                          ),
                                        ),
                                      );

                                      if (compact) {
                                        if (constraints.maxHeight < 280) {
                                          return Row(
                                            key: const Key(
                                              'desktop-allocation-compact',
                                            ),
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Expanded(flex: 4, child: chart),
                                              const SizedBox(width: 14),
                                              Expanded(
                                                flex: 6,
                                                child: holdingsList,
                                              ),
                                            ],
                                          );
                                        }

                                        return Column(
                                          key: const Key(
                                            'desktop-allocation-compact',
                                          ),
                                          children: [
                                            SizedBox(height: 220, child: chart),
                                            const SizedBox(height: 14),
                                            Expanded(child: holdingsList),
                                          ],
                                        );
                                      }

                                      return Row(
                                        children: [
                                          Expanded(flex: 5, child: chart),
                                          const SizedBox(width: 28),
                                          Expanded(
                                            flex: 6,
                                            child: holdingsList,
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 5,
                        child: Card(
                          margin: EdgeInsets.zero,
                          clipBehavior: Clip.antiAlias,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(22, 22, 10, 18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.l10n.text('Return by holding'),
                                  style: theme.textTheme.titleLarge,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _returnCutoff == null
                                      ? 'Current · open holdings'
                                      : 'Since ${DateFormat.yMMMd().format(_returnCutoff!)} · open holdings',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Expanded(
                                  child: Scrollbar(
                                    key: const Key('desktop-return-scrollbar'),
                                    controller: _returnScrollController,
                                    child: ListView.separated(
                                      controller: _returnScrollController,
                                      padding: const EdgeInsets.only(right: 24),
                                      itemCount: byReturn.length,
                                      separatorBuilder: (_, __) => Divider(
                                        height: 1,
                                        color: colorScheme.outlineVariant
                                            .withValues(alpha: 0.7),
                                      ),
                                      itemBuilder: (context, index) {
                                        final position = byReturn[index];
                                        return _DesktopReturnRow(
                                          position: position,
                                          periodReturn: _holdingReturn(
                                            position,
                                          ),
                                          onTap: () =>
                                              _openHoldingHistory(position),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Color> _buildColors(BuildContext context, List<String> symbols) {
    for (final symbol in symbols.toList()..sort()) {
      _holdingColorIndices.putIfAbsent(
        symbol,
        () => _holdingColorIndices.length,
      );
    }
    final stableSymbols = _holdingColorIndices.keys.toList();
    final palette = portfolioHoldingColors(
      Theme.of(context).colorScheme,
      stableSymbols,
      accountCount: context.read<AccountManager>().accounts.length,
      favorites: _chartFavorites,
    );
    return [
      for (final symbol in symbols) palette[stableSymbols.indexOf(symbol)],
    ];
  }
}
