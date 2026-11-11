part of '../charts_page.dart';

extension _ChartSearchWidgets on ChartsPageState {
  Widget _buildSearchBar({required double availableWidth}) {
    final canReturnToPortfolio =
        _mode != _ChartMode.portfolio || _searchController.text.isNotEmpty;
    final desktop = isDesktopLayout(context);
    final settings = context.watch<SettingsState>();
    final inlineCurrencies = desktop &&
        settings.visibleCurrencies.length > 1 &&
        availableWidth >= 750 + settings.visibleCurrencies.length * 65;
    final leading = switch (true) {
      _ when _customChartRange != null => IconButton(
          key: const Key('chart-clear-filter'),
          icon: const Icon(Icons.filter_alt_off_rounded),
          tooltip: 'Clear date filter',
          padding: const EdgeInsets.only(left: 16, right: 8),
          onPressed: () {
            ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
            _setChartRange(const [], null);
          },
        ),
      _ when canReturnToPortfolio => IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: context.l10n.text('Back'),
          padding: const EdgeInsets.only(left: 16, right: 8),
          onPressed: _clearSearch,
        ),
      _ => const Padding(
          padding: EdgeInsets.only(left: 16, right: 8),
          child: Icon(Icons.search),
        ),
    };

    return Padding(
      padding: EdgeInsets.fromLTRB(
        desktop ? 32 : 8,
        desktop ? 28 : 8,
        desktop ? 32 : 8,
        4,
      ),
      child: SearchBar(
        key: const Key('chart-search-bar'),
        constraints: const BoxConstraints(
          minHeight: 56,
          maxWidth: double.infinity,
        ),
        controller: _searchController,
        focusNode: _searchFocus,
        hintText: context.l10n.text('Search stocks...'),
        leading: leading,
        onChanged: _onSearchChanged,
        onTap: () => _searchController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _searchController.text.length,
        ),
        onSubmitted: (text) {
          if (text.isNotEmpty) _onSearchChanged(text);
        },
        trailing: [
          if (desktop && _mode != _ChartMode.searching)
            IconButton(
              onPressed: _networkLoading ? null : _refreshCurrentChart,
              tooltip: context.l10n.text('Refresh'),
              icon: const Icon(Icons.refresh_rounded),
            ),
          if (inlineCurrencies)
            const CurrencyButtons(key: Key('chart-currency-buttons')),
          IconButton(
            key: const Key('chart-settings-button'),
            icon: const Icon(Icons.settings_outlined),
            tooltip: context.l10n.text('Settings'),
            onPressed: () => openAppSettings(context),
          ),
          if (!desktop ||
              (settings.visibleCurrencies.length > 1 && !inlineCurrencies))
            PopupMenuButton<String>(
              key: const Key('chart-menu-button'),
              icon: const Icon(Icons.more_vert),
              tooltip: context.l10n.text('Show menu'),
              onSelected: (value) {
                if (value == '__filter_range__') {
                  if (_pickingChartRange) {
                    _updateState(() => _pickingChartRange = false);
                    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
                  } else {
                    _startChartRangePicker();
                  }
                } else if (value == '__rolling_average__') {
                  runDetachedTask(
                    settings.setShowRollingAverage(
                      !settings.showRollingAverage,
                    ),
                    'Failed to save rolling average',
                  );
                } else if (value == '__candles__') {
                  _candleSelection.value = null;
                  runDetachedTask(
                    settings.setShowCandlesticks(!settings.showCandlesticks),
                    'Failed to save chart style',
                  );
                } else if (value.startsWith('currency:')) {
                  runDetachedTask(
                    settings.setDisplayCurrency(value.substring(9)),
                    'Failed to change display currency',
                  );
                }
              },
              itemBuilder: (context) => [
                if (settings.visibleCurrencies.length > 1) ...[
                  for (final currencyCode in settings.visibleCurrencies)
                    CheckedPopupMenuItem<String>(
                      value: 'currency:$currencyCode',
                      checked: currencyCode == settings.displayCurrency,
                      child: Text(currencyCode),
                    ),
                  if (!desktop) const PopupMenuDivider(),
                ],
                if (!desktop) ...[
                  PopupMenuItem<String>(
                    key: const Key('chart-menu-filter-range'),
                    value: '__filter_range__',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _pickingChartRange
                              ? Icons.close
                              : Icons.filter_alt_outlined,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _pickingChartRange
                              ? 'Cancel picking'
                              : 'Filter range',
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    key: const Key('chart-menu-rolling-average'),
                    value: '__rolling_average__',
                    child: Row(
                      children: [
                        Icon(
                          settings.showRollingAverage
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                        ),
                        const SizedBox(width: 12),
                        Text(context.l10n.text('Rolling average')),
                        if (settings.showRollingAverage) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.check, size: 18),
                        ],
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    key: const Key('chart-menu-candles'),
                    value: '__candles__',
                    child: Row(
                      children: [
                        Icon(
                          settings.showCandlesticks
                              ? Icons.candlestick_chart
                              : Icons.candlestick_chart_outlined,
                        ),
                        const SizedBox(width: 12),
                        const Text('Candles'),
                        if (settings.showCandlesticks) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.check, size: 18),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    final query = _searchController.text.trim().toUpperCase();
    if (query.isEmpty) return const SizedBox.shrink();

    // "Use anyway" tile — always shown so a known symbol remains usable even
    // while Yahoo search is slow or unavailable (e.g. GLD).
    final useAnywayTile = ListTile(
      leading: const Icon(Icons.open_in_new),
      title: Text(context.l10n.text('Use "{query}" anyway', {'query': query})),
      subtitle: Text(context.l10n.text('Load chart for this exact ticker')),
      onTap: () => _selectSymbol(query),
    );

    return RefreshIndicator(
      triggerMode: RefreshIndicatorTriggerMode.anywhere,
      onRefresh: () => _runTickerSearch(_searchController.text),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: bottomNavScrollClearance),
        itemCount: _searchResults.length + 1 + (_searchLoading ? 1 : 0),
        itemBuilder: (context, index) {
          if (_searchLoading && index == _searchResults.length + 1) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: TickerSearchLoading()),
            );
          }
          if (index == _searchResults.length) {
            return useAnywayTile;
          }
          final result = _searchResults[index];
          final name =
              result.longname.isNotEmpty ? result.longname : result.shortname;
          return DesktopContextMenu(
            actions: [
              DesktopMenuAction(
                context.l10n.text('Open chart'),
                () => _selectStock(result),
                icon: Icons.show_chart_rounded,
              ),
              DesktopMenuAction(
                context.l10n.text(
                  _favoriteStocks.contains(result.symbol)
                      ? 'Remove favorite'
                      : 'Add favorite',
                ),
                () => _toggleFavorite(result.symbol),
                icon: _favoriteStocks.contains(result.symbol)
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
              ),
            ],
            copyText: result.symbol,
            copyLabel: context.l10n.text('Copy symbol'),
            child: ListTile(
              title: Text(result.symbol),
              subtitle: Text(name),
              trailing: Text(
                result.exchange,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              onTap: () => _selectStock(result),
            ),
          );
        },
      ),
    );
  }
}
