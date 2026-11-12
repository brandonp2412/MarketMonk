part of '../charts_page.dart';

extension _ChartFavoriteWidgets on ChartsPageState {
  Future<void> _renameFavorite(String symbol) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) =>
          RenameFavoriteDialog(currentName: _favoriteNames[symbol] ?? symbol),
    );
    if (name == null || !mounted) return;
    final prefs = await SqliteSettings.getInstance();
    if (name.isEmpty || name == symbol) {
      await prefs.remove('favoriteName:$symbol');
    } else {
      await prefs.setString('favoriteName:$symbol', name);
    }
    if (!mounted) return;
    _updateState(() {
      if (name.isEmpty || name == symbol) {
        _favoriteNames.remove(symbol);
      } else {
        _favoriteNames[symbol] = name;
      }
    });
  }

  void _showFavoriteActions(String symbol) {
    runDetachedTask(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(context.l10n.text('Rename')),
                onTap: () {
                  Navigator.pop(sheetContext);
                  runDetachedTask(
                    _renameFavorite(symbol),
                    'Failed to rename favorite',
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.favorite_border),
                title: Text(context.l10n.text('Remove favorite')),
                onTap: () {
                  Navigator.pop(sheetContext);
                  if (_favoriteStocks.contains(symbol)) {
                    runDetachedTask(
                      _toggleFavorite(symbol),
                      'Failed to remove favorite',
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.close),
                title: Text(context.l10n.text('Cancel')),
                onTap: () => Navigator.pop(sheetContext),
              ),
            ],
          ),
        ),
      ),
      'Failed to show favorite actions',
    );
  }

  Widget _buildFavoritesRow() {
    final hasFavorites = _favoriteStocks.isNotEmpty;
    if (!hasFavorites) return const SizedBox.shrink();
    final desktop = isDesktopLayout(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        desktop ? 32 : 11,
        12,
        desktop ? 32 : 11,
        8,
      ),
      child: Column(
        children: [
          if (hasFavorites) ...[
            SizedBox(
              height: 64,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: desktop ? 16 : 0),
                itemCount: _favoriteStocks.length,
                itemBuilder: (context, index) {
                  final symbol = _favoriteStocks[index];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: DesktopContextMenu(
                      actions: [
                        DesktopMenuAction(
                          context.l10n.text('Rename'),
                          () => runDetachedTask(
                            _renameFavorite(symbol),
                            'Failed to rename favorite',
                          ),
                          icon: Icons.edit_rounded,
                        ),
                        DesktopMenuAction(
                          context.l10n.text('Open chart'),
                          () => _selectSymbol(symbol),
                          icon: Icons.show_chart_rounded,
                        ),
                        DesktopMenuAction(
                          context.l10n.text('Remove favorite'),
                          () => _toggleFavorite(symbol),
                          icon: Icons.star_border_rounded,
                        ),
                        if (!context
                            .read<AccountManager>()
                            .ibkrConfigFor()
                            .enabled)
                          DesktopMenuAction(
                            context.l10n.text('Add trade'),
                            () => Navigator.push(
                              context,
                              adaptivePageRoute(
                                context,
                                builder: (_) => EditTickerPage(symbol: symbol),
                              ),
                            ),
                            icon: Icons.add_rounded,
                          ),
                      ],
                      copyText: symbol,
                      copyLabel: context.l10n.text('Copy symbol'),
                      child: FavoriteChartCard(
                        symbol: symbol,
                        displayName: _favoriteNames[symbol] ?? symbol,
                        periodStart: _requiredCandleStart(),
                        periodDays: days,
                        visibleRange: _customChartRange,
                        intraday: _usesIntraday &&
                            _selectedFavorites.contains(symbol) &&
                            (days != 5 ||
                                _favoriteIntraday.containsKey(symbol)),
                        intradaySeries: _favoriteIntraday[symbol],
                        isActive: widget.isActive,
                        selected: _selectedFavorites.contains(symbol),
                        selectionColor: _favoriteColor(symbol),
                        onTap: () => _selectFavorite(symbol),
                        onLongPress: () => _showFavoriteActions(symbol),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
